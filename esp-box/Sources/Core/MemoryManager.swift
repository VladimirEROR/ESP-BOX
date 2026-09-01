import Foundation
import Darwin

// MARK: - Memory Manager (External Read — READONLY)
class MemoryManager {
    
    private var taskPort: mach_port_t = MACH_PORT_NULL
    private var targetPID: Int32 = 0
    private var moduleBase: UInt64 = 0
    private var moduleSize: UInt64 = 0
    
    var isAttached: Bool {
        return taskPort != MACH_PORT_NULL
    }
    
    var baseAddress: UInt64 {
        return moduleBase
    }
    
    // MARK: - Attach
    func attach(to pid: Int32) -> Bool {
        targetPID = pid
        taskPort = MACH_PORT_NULL
        
        let kr = task_for_pid(mach_task_self_, pid, &taskPort)
        
        guard kr == KERN_SUCCESS else {
            print("[VEX] task_for_pid failed with error: \(kr)")
            print("[VEX] — need JB or TrollStore with entitlements")
            return false
        }
        
        print("[VEX] Attached to PID \(pid)")
        return true
    }
    
    func detach() {
        if taskPort != MACH_PORT_NULL {
            mach_port_deallocate(mach_task_self_, taskPort)
            taskPort = MACH_PORT_NULL
        }
        moduleBase = 0
        moduleSize = 0
    }
    
    // MARK: - Find Module Base
    func findModuleBase(named moduleName: String) -> UInt64? {
        guard isAttached else { return nil }
        
        var address: mach_vm_address_t = 0
        var count: mach_vm_size_t = 0
        var objectName: mach_vm_offset_t = 0
        
        var info = vm_region_submap_info_data_64_t()
        var infoCount: mach_msg_type_number_t = 
            mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        
        var largestExec: (UInt64, UInt64) = (0, 0)
        
        while true {
            let kr = mach_vm_region_recurse(
                taskPort,
                &address,
                &count,
                &objectName,
                &info
            )
            
            if kr != KERN_SUCCESS { break }
            
            let regionSize = UInt64(count)
            let isExecutable = (info.protection & VM_PROT_EXECUTE) != 0
            
            if isExecutable && regionSize > largestExec.1 {
                largestExec = (address, regionSize)
            }
            
            if info.is_submap != 0 {
                // Recurse into submap
                address += regionSize
            } else {
                address += regionSize
            }
            
            if address > 0x80000000000 { break }
        }
        
        // MLBB is a monolithic game binary — the largest executable
        // region is the main binary
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
        
        var bytesRead: mach_vm_size_t = 0
        
        let kr = mach_vm_read_overwrite(
            taskPort,
            mach_vm_address_t(address),
            mach_vm_size_t(size),
            mach_vm_address_t(UInt(bitPattern: buffer)),
            &bytesRead
        )
        
        guard kr == KERN_SUCCESS, bytesRead >= mach_vm_size_t(size) else {
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
        
        var bytesRead: mach_vm_size_t = 0
        
        let kr = mach_vm_read_overwrite(
            taskPort,
            mach_vm_address_t(address),
            mach_vm_size_t(size),
            mach_vm_address_t(UInt(bitPattern: buffer)),
            &bytesRead
        )
        
        guard kr == KERN_SUCCESS, bytesRead >= mach_vm_size_t(size) else {
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
