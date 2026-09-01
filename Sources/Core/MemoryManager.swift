import Foundation
import Darwin

// MARK: - Mach VM function declarations (not in public iOS SDK headers)
// These exist in libSystem.dylib on iOS but aren't publicly declared

@_silgen_name("mach_vm_read_overwrite")
internal func _mach_vm_read_overwrite(
    _ target_task: mach_port_t,
    _ address: UInt64,
    _ size: UInt64,
    _ data: UInt64,
    _ outsize: UnsafeMutablePointer<UInt64>
) -> kern_return_t

@_silgen_name("mach_vm_region_recurse")
internal func _mach_vm_region_recurse(
    _ target_task: mach_port_t,
    _ address: UnsafeMutablePointer<UInt64>,
    _ size: UnsafeMutablePointer<UInt64>,
    _ object_name: UnsafeMutablePointer<mach_port_t>,
    _ info: UnsafeMutableRawPointer,
    _ infoCnt: UnsafeMutablePointer<UInt32>
) -> kern_return_t

// MARK: - Memory Manager (External Read — READONLY)
class MemoryManager {
    
    private var taskPort: mach_port_t = 0
    private var targetPID: Int32 = 0
    private var moduleBase: UInt64 = 0
    private var moduleSize: UInt64 = 0
    
    var isAttached: Bool {
        return taskPort != 0
    }
    
    var baseAddress: UInt64 {
        return moduleBase
    }
    
    // MARK: - Attach
    func attach(to pid: Int32) -> Bool {
        targetPID = pid
        taskPort = 0
        
        let kr = task_for_pid(mach_task_self_, pid, &taskPort)
        
        guard kr == KERN_SUCCESS, taskPort != 0 else {
            print("[VEX] task_for_pid failed with error: \(kr)")
            return false
        }
        
        print("[VEX] Attached to PID \(pid)")
        return true
    }
    
    func detach() {
        if taskPort != 0 {
            mach_port_deallocate(mach_task_self_, taskPort)
            taskPort = 0
        }
        moduleBase = 0
        moduleSize = 0
    }
    
    // MARK: - Find Module Base
    func findModuleBase(named moduleName: String) -> UInt64? {
        guard isAttached else { return nil }
        
        var address: UInt64 = 0
        var size: UInt64 = 0
        var objectName: mach_port_t = 0
        
        // vm_region_submap_info_data_64 structure is 152 bytes
        // we'll use a raw buffer to avoid struct layout issues
        let infoSize = 152
        var infoBuffer = [UInt8](repeating: 0, count: infoSize)
        var infoCount: UInt32 = UInt32(infoSize / MemoryLayout<integer_t>.size)
        
        var largestExec: (UInt64, UInt64) = (0, 0)
        
        while true {
            // protection field is at offset 40 in vm_region_submap_info_data_64
            // share_mode at offset 56
            // we only need protection (offset 40, 4 bytes) and is_submap (offset 152-4)
            
            let kr = _mach_vm_region_recurse(
                taskPort,
                &address,
                &size,
                &objectName,
                &infoBuffer,
                &infoCount
            )
            
            if kr != KERN_SUCCESS { break }
            
            // Extract protection from the info buffer
            // vm_region_submap_info_data_64 layout:
            //   offset 0-27: vm_region_basic_info_data_64 (28 bytes)
            //   offset 28: protection (4 bytes)
            //   offset 32: max_protection (4 bytes)
            //   ... etc
            // Actually let me recalculate:
            // vm_region_submap_info_data_64:
            //   0-3: protection
            //   4-7: max_protection  
            //   8-11: inheritance
            //   12-15: reserved (was shared)
            //   16-23: offset (8 bytes)
            //   24-27: user_tag
            //   28-31: pages_resident
            //   32-35: pages_shared_now_private
            //   36-39: pages_swapped_out
            //   40-43: pages_dirtied
            //   44-47: ref_count
            //   48-51: shadow_depth
            //   52-55: external_pager
            //   56-59: share_mode
            //   60-63: is_submap (boolean)
            //   64-...: behavior
            
            // protection is at offset 0
            let protection = infoBuffer.withUnsafeBytes { raw in
                raw.load(fromByteOffset: 0, as: Int32.self)
            }
            
            // share_mode at offset 56
            let shareMode = infoBuffer.withUnsafeBytes { raw in
                raw.load(fromByteOffset: 56, as: Int32.self)
            }
            
            // is_submap at offset 60 (1 byte bool)
            let isSubmap = infoBuffer[60] != 0
            
            let isExecutable = (protection & VM_PROT_EXECUTE) != 0
            
            if isExecutable && size > largestExec.1 {
                largestExec = (address, size)
            }
            
            _ = shareMode
            
            if isSubmap {
                // skip submaps, just advance
                address += size
            } else {
                address += size
            }
            
            if address > 0x80000000000 { break }
        }
        
        if largestExec.1 > 0x1000000 {
            moduleBase = largestExec.0
            moduleSize = largestExec.1
            print("[VEX] Module Base: 0x\(String(moduleBase, radix: 16, uppercase: true))")
            print("[VEX] Module Size: 0x\(String(moduleSize, radix: 16, uppercase: true))")
            return moduleBase
        }
        
        print("[VEX] No suitable executable region found")
        return nil
    }
    
    // MARK: - Generic Read
    func read<T>(_ address: UInt64) -> T? {
        let size = max(MemoryLayout<T>.size, 1)
        let alignment = max(MemoryLayout<T>.alignment, 1)
        
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: size,
            alignment: alignment
        )
        defer { buffer.deallocate() }
        
        var bytesRead: UInt64 = 0
        
        let kr = _mach_vm_read_overwrite(
            taskPort,
            address,
            UInt64(size),
            UInt64(UInt(bitPattern: buffer)),
            &bytesRead
        )
        
        guard kr == KERN_SUCCESS, bytesRead >= UInt64(size) else {
            return nil
        }
        
        // Bool is stored as 1 byte in memory
        if T.self == Bool.self {
            let byte = buffer.assumingMemoryBound(to: UInt8.self).pointee
            return (byte != 0) as? T
        }
        
        return buffer.assumingMemoryBound(to: T.self).pointee
    }
    
    // MARK: - Read Bytes
    func readBytes(_ address: UInt64, size: Int) -> Data? {
        guard size > 0 else { return nil }
        
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: size,
            alignment: MemoryLayout<UInt64>.alignment
        )
        defer { buffer.deallocate() }
        
        var bytesRead: UInt64 = 0
        
        let kr = _mach_vm_read_overwrite(
            taskPort,
            address,
            UInt64(size),
            UInt64(UInt(bitPattern: buffer)),
            &bytesRead
        )
        
        guard kr == KERN_SUCCESS, bytesRead >= UInt64(size) else {
            return nil
        }
        
        return Data(bytes: buffer, count: size)
    }
    
    // MARK: - Read Pointer
    func readPointer(_ address: UInt64) -> UInt64? {
        return read(address) as UInt64?
    }
    
    // MARK: - Read Chain
    func readChain(_ base: UInt64, _ offsets: [UInt64]) -> UInt64? {
        var current = base
        
        for offset in offsets {
            guard let next: UInt64 = read(current + offset) else { return nil }
            current = next
        }
        
        return current
    }
    
    // MARK: - Read String
    func readString(_ address: UInt64, maxLength: Int = 64) -> String? {
        guard let data = readBytes(address, size: maxLength) else { return nil }
        
        var bytes: [UInt8] = []
        for byte in data {
            if byte == 0 { break }
            bytes.append(byte)
        }
        
        guard !bytes.isEmpty else { return nil }
        return String(bytes: bytes, encoding: .utf8)
    }
    
    // MARK: - Read UTF-16 String
    func readWideString(_ address: UInt64, maxLength: Int = 64) -> String? {
        guard let data = readBytes(address, size: maxLength * 2) else { return nil }
        
        var chars: [UInt16] = []
        var i = 0
        while i < data.count - 1 {
            let char = UInt16(data[i]) | (UInt16(data[i + 1]) << 8)
            if char == 0 { break }
            chars.append(char)
            i += 2
        }
        
        guard !chars.isEmpty else { return nil }
        return String(utf16CodeUnits: chars, count: chars.count)
    }
    
    // MARK: - Pattern Scan
    func scanPattern(
        _ base: UInt64,
        _ size: UInt64,
        pattern: [UInt8],
        mask: [Bool]
    ) -> UInt64? {
        guard !pattern.isEmpty, pattern.count == mask.count else { return nil }
        
        let chunkSize = 0x100000
        var offset: UInt64 = 0
        
        while offset < size {
            let remaining = min(chunkSize, Int(size - offset))
            guard let data = readBytes(base + offset, size: remaining) else {
                offset += UInt64(chunkSize)
                continue
            }
            
            let bytes = [UInt8](data)
            
            outer: for i in 0..<(bytes.count - pattern.count) {
                for j in 0..<pattern.count {
                    if mask[j] && bytes[i + j] != pattern[j] {
                        continue outer
                    }
                }
                return base + offset + UInt64(i)
            }
            
            offset += UInt64(chunkSize)
        }
        
        return nil
    }
}
