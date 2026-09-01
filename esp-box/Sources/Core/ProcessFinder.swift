import Foundation
import Darwin

class ProcessFinder {
    
    // Method 1: sysctl KERN_PROC
    static func findPID(byName name: String) -> Int32? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: Int = 0
        
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else {
            return findPIDByProcPath(byName: name)
        }
        
        let count = size / MemoryLayout<kinfo_proc>.stride
        guard count > 0 else { return nil }
        
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else {
            return findPIDByProcPath(byName: name)
        }
        
        let actualCount = size / MemoryLayout<kinfo_proc>.stride
        
        for i in 0..<actualCount {
            let proc = procs[i]
            let pid = proc.kp_proc.p_pid
            guard pid > 0 else { continue }
            
            // Get process name from comm field
            let procName = withUnsafeBytes(of: proc.kp_proc.p_comm) { raw -> String in
                let bytes = raw.prefix(16).filter { $0 != 0 }
                return String(bytes: bytes, encoding: .utf8) ?? ""
            }
            
            if procName.lowercased().contains(name.lowercased()) {
                return pid
            }
        }
        
        // Fallback
        return findPIDByProcPath(byName: name)
    }
    
    // Method 2: proc_pidpath (works on some systems where sysctl is restricted)
    static func findPIDByProcPath(byName name: String) -> Int32? {
        var buffer = [pid_t](repeating: 0, count: 1024)
        let bufferSize = Int32(MemoryLayout<pid_t>.size * buffer.count)
        
        let count = proc_listallpids(&buffer, bufferSize)
        guard count > 0 else { return nil }
        
        for i in 0..<Int(count) {
            let pid = buffer[i]
            guard pid > 0 else { continue }
            
            var pathBuf = [CChar](repeating: 0, count: 4096)
            let pathLen = proc_pidpath(pid, &pathBuf, 4096)
            
            if pathLen > 0 {
                let path = String(cString: pathBuf)
                if path.lowercased().contains(name.lowercased()) {
                    return pid
                }
            }
        }
        
        return nil
    }
}
