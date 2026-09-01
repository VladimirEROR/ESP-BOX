import Foundation
import Darwin

class ProcessFinder {
    
    // MARK: - Resolve private libproc functions via dlsym
    private static let procListAllPids: (@convention(c) (UnsafeMutablePointer<pid_t>?, Int32) -> Int32)? = {
        let handle = dlopen("/usr/lib/libSystem.dylib", RTLD_LAZY)
        guard let handle = handle else { return nil }
        let sym = dlsym(handle, "proc_listallpids")
        return unsafeBitCast(sym, to: (@convention(c) (UnsafeMutablePointer<pid_t>?, Int32) -> Int32)?.self)
    }()
    
    private static let procPidPath: (@convention(c) (Int32, UnsafeMutablePointer<CChar>?, Int32) -> Int32)? = {
        let handle = dlopen("/usr/lib/libSystem.dylib", RTLD_LAZY)
        guard let handle = handle else { return nil }
        let sym = dlsym(handle, "proc_pidpath")
        return unsafeBitCast(sym, to: (@convention(c) (Int32, UnsafeMutablePointer<CChar>?, Int32) -> Int32)?.self)
    }()
    
    // MARK: - Find PID by process name
    static func findPID(byName name: String) -> Int32? {
        // Method 1: proc_listallpids (resolves via dlsym)
        if let listAll = procListAllPids {
            let bufferSize: Int32 = 1024
            var buffer = [pid_t](repeating: 0, count: Int(bufferSize))
            
            let count = listAll(&buffer, bufferSize)
            if count > 0 {
                for i in 0..<Int(count) {
                    let pid = buffer[i]
                    guard pid > 0 else { continue }
                    
                    // Get process name via proc_pidpath
                    if let pidPath = procPidPath {
                        var pathBuf = [CChar](repeating: 0, count: 4096)
                        let pathLen = pidPath(pid, &pathBuf, 4096)
                        
                        if pathLen > 0 {
                            let path = String(cString: pathBuf)
                            
                            // Check full path
                            if path.lowercased().contains(name.lowercased()) {
                                return pid
                            }
                            
                            // Check just the binary name (last component)
                            let binaryName = (path as NSString).lastPathComponent
                            if binaryName.lowercased().contains(name.lowercased()) {
                                return pid
                            }
                        }
                    }
                }
            }
        }
        
        // Method 2: sysctl KERN_PROC fallback
        return findBySysctl(byName: name)
    }
    
    // MARK: - Sysctl fallback
    private static func findBySysctl(byName name: String) -> Int32? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: Int = 0
        
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return nil }
        
        let count = size / MemoryLayout<kinfo_proc>.stride
        guard count > 0 else { return nil }
        
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return nil }
        
        let actualCount = size / MemoryLayout<kinfo_proc>.stride
        
        for i in 0..<actualCount {
            let proc = procs[i]
            let pid = proc.kp_proc.p_pid
            guard pid > 0 else { continue }
            
            // Get process name from comm field (max 16 chars)
            let procName = withUnsafeBytes(of: proc.kp_proc.p_comm) { raw -> String in
                let bytes = raw.prefix(16).filter { $0 != 0 }
                return String(bytes: bytes, encoding: .utf8) ?? ""
            }
            
            if procName.lowercased().contains(name.lowercased()) {
                return pid
            }
        }
        
        return nil
    }
}
