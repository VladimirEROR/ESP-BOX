import Foundation
import CoreGraphics

// MARK: - Data Types
struct Vector3 {
    var x: Float
    var y: Float
    var z: Float
}

struct ESPBox {
    var screenX: CGFloat
    var screenY: CGFloat
    var width: CGFloat
    var height: CGFloat
    var health: Int
    var healthMax: Int
    var isEnemy: Bool
    var isSelf: Bool
    var isDead: Bool
    var distance: Float
    var level: Int
    var guid: UInt64
    var name: String
}

enum CampType: Int {
    case none = 0
    case blue = 1
    case red = 2
    case neutral = 3
}

// MARK: - Entity Parser
class EntityParser {
    
    private var memory: MemoryManager
    private var base: UInt64
    
    private var gameMapBase: UInt64 = 0
    private var selfPlayerPos: Vector3 = Vector3(x: 0, y: 0, z: 0)
    private var selfCamp: CampType = .none
    
    var screenWidth: Float = 844
    var screenHeight: Float = 390
    
    // View matrix (4x4 column-major)
    var viewMatrix: [Float] = Array(repeating: 0, count: 16)
    
    init(memory: MemoryManager, baseAddress: UInt64) {
        self.memory = memory
        self.base = baseAddress
        
        let bounds = UIScreen.main.bounds
        self.screenWidth = Float(bounds.width)
        self.screenHeight = Float(bounds.height)
    }
    
    // MARK: - Get GameMapBase Instance
    private func getGameMapInstance() -> UInt64? {
        // Read the get_Instance method prologue to find
        // the static pointer it reads from
        
        let instanceMethodAddr = base + MLBBOffsets.get_Instance
        
        guard let code = memory.readBytes(instanceMethodAddr, size: 16) else {
            return nil
        }
        
        let bytes = [UInt8](code)
        guard bytes.count >= 8 else { return nil }
        
        // Decode ARM64 instructions
        let instr1 = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) 
                   | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
        let instr2 = UInt32(bytes[4]) | (UInt32(bytes[5]) << 8) 
                   | (UInt32(bytes[6]) << 16) | (UInt32(bytes[7]) << 24)
        
        // ADRP + LDR pattern for singleton getter
        if (instr1 & 0x9F000000) == 0x90000000 {
            // Decode ADRP
            let immlo = (instr1 >> 29) & 0x3
            let immhi = (instr1 >> 5) & 0x7FFFF
            let imm = (Int(immhi) << 2) | Int(immlo)
            let pageOffset = Int(imm) << 12
            
            let pc = Int(instanceMethodAddr)
            let page = (pc & ~0xFFF) + pageOffset
            
            // Check LDR X, [X, #offset]
            if (instr2 & 0xFFC00000) == 0xF9400000 {
                let imm12 = (instr2 >> 10) & 0xFFF
                let offset = Int(imm12) * 8
                
                let staticAddr = UInt64(page + offset)
                
                if let instancePtr: UInt64 = memory.read(staticAddr) {
                    if instancePtr > 0x100000000 && instancePtr < 0x80000000000 {
                        return instancePtr
                    }
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Parse All Entities
    func parseEntities() -> [ESPBox] {
        var results: [ESPBox] = []
        
        guard let gameMap = getGameMapInstance() else {
            return results
        }
        
        self.gameMapBase = gameMap
        
        // Probe for entity list within GameMapBase
        // Common list offsets: 0x10 through 0xB0
        let candidateOffsets: [UInt64] = [
            0x10, 0x18, 0x20, 0x28, 0x30, 0x38, 
            0x40, 0x48, 0x50, 0x58, 0x60, 0x68,
            0x70, 0x78, 0x80, 0x88, 0x90, 0x98,
            0xA0, 0xA8, 0xB0
        ]
        
        for listOffset in candidateOffsets {
            let listAddr = gameMap + listOffset
            
            // Try as pointer to entity array
            if let listPtr: UInt64 = memory.read(listAddr) {
                if listPtr > 0x100000000 && listPtr < 0x80000000000 {
                    results = parseEntityArray(listPtr)
                    if results.count >= 2 {
                        return results
                    }
                }
            }
            
            // Try as inline entity pointer
            if let first: UInt64 = memory.read(listAddr) {
                if isValidPlayerEntity(first) {
                    results = parseEntityArray(listAddr)
                    if results.count >= 2 {
                        return results
                    }
                    results.removeAll()
                }
            }
        }
        
        return results
    }
    
    // MARK: - Entity Array Parsing
    private func parseEntityArray(_ arrayPtr: UInt64) -> [ESPBox] {
        var results: [ESPBox] = []
        
        // Read up to 10 players (MLBB max is 5v5)
        for i in 0..<12 {
            let entityPtrAddr = arrayPtr + UInt64(i * 8)
            guard let entityPtr: UInt64 = memory.read(entityPtrAddr) else { break }
            
            if entityPtr == 0 { continue }
            if !isValidPlayerEntity(entityPtr) { continue }
            
            if let box = parseEntity(entityPtr) {
                results.append(box)
            }
        }
        
        return results
    }
    
    // MARK: - Entity Validation
    private func isValidPlayerEntity(_ ptr: UInt64) -> Bool {
        guard ptr > 0x100000000 else { return false }
        guard ptr < 0x80000000000 else { return false }
        
        // Check IsPlayer flag
        guard let isPlayerByte: UInt8 = memory.read(ptr + MLBBOffsets.IsPlayer) else {
            return false
        }
        
        return isPlayerByte == 1
    }
    
    // MARK: - Parse Single Entity
    private func parseEntity(_ ptr: UInt64) -> ESPBox? {
        // HP
        guard let hp: Int32 = memory.read(ptr + MLBBOffsets.m_Hp) else { return nil }
        guard let hpMax: Int32 = memory.read(ptr + MLBBOffsets.m_HpMax) else { return nil }
        
        // Camp type
        guard let campTypeRaw: Int32 = memory.read(ptr + MLBBOffsets.m_EntityCampType) else {
            return nil
        }
        
        // Flags
        let isDead: Bool = ((memory.read(ptr + MLBBOffsets.m_bDeath) as UInt8?) ?? 1) != 0
        let isSelf: Bool = ((memory.read(ptr + MLBBOffsets.m_bSelf) as UInt8?) ?? 0) != 0
        
        // Level
        let level: Int32 = (memory.read(ptr + MLBBOffsets.m_Level) as Int32?) ?? 1
        
        // GUID
        let guid: UInt64 = (memory.read(ptr + MLBBOffsets.m_uGuid) as UInt64?) ?? 0
        
        // Position
        let posAddr = ptr + MLBBOffsets.m_vCachePosition
        guard let posX: Float = memory.read(posAddr),
              let posY: Float = memory.read(posAddr + 4),
              let posZ: Float = memory.read(posAddr + 8) else {
            return nil
        }
        
        let worldPos = Vector3(x: posX, y: posY, z: posZ)
        
        // Track self position
        if isSelf {
            selfPlayerPos = worldPos
            selfCamp = CampType(rawValue: Int(campTypeRaw)) ?? .blue
        }
        
        // World-to-screen
        guard let screen = worldToScreen(worldPos) else { return nil }
        
        // Distance from self
        let dx = worldPos.x - selfPlayerPos.x
        let dz = worldPos.z - selfPlayerPos.z
        let distance = sqrtf(dx * dx + dz * dz)
        
        // Team determination
        let camp = CampType(rawValue: Int(campTypeRaw)) ?? .none
        let isEnemy: Bool
        
        if isSelf {
            isEnemy = false
        } else if camp == .none || camp == .neutral {
            isEnemy = false
        } else {
            isEnemy = (camp != selfCamp)
        }
        
        // Box dimensions based on distance
        let boxHeight: CGFloat = max(30, 110 - CGFloat(distance / 8))
        let boxWidth: CGFloat = boxHeight * 0.55
        
        return ESPBox(
            screenX: screen.x,
            screenY: screen.y,
            width: boxWidth,
            height: boxHeight,
            health: Int(hp),
            healthMax: Int(hpMax),
            isEnemy: isEnemy,
            isSelf: isSelf,
            isDead: isDead,
            distance: distance,
            level: Int(level),
            guid: guid,
            name: ""
        )
    }
    
    // MARK: - World-to-Screen
    private func worldToScreen(_ world: Vector3) -> (x: CGFloat, y: CGFloat)? {
        // If we have a real view matrix, use it
        if viewMatrix[0] != 0 || viewMatrix[5] != 0 || viewMatrix[10] != 0 {
            return projectWithMatrix(world)
        }
        
        // Fallback: isometric approximation for MLBB camera
        let screenW = screenWidth
        let screenH = screenHeight
        
        let mapCenterX: Float = 0
        let mapCenterZ: Float = 0
        let cameraAngle: Float = 0.96
        
        let relX = world.x - mapCenterX
        let relZ = world.z - mapCenterZ
        
        let cosA = cosf(cameraAngle)
        let sinA = sinf(cameraAngle)
        
        let rotatedX = relX * cosA - relZ * sinA
        let rotatedZ = relX * sinA + relZ * cosA
        
        let scale: Float = screenW / 200.0
        
        let sx = screenW / 2 + rotatedX * scale
        let sy = screenH / 2 + rotatedZ * scale * 0.6 - world.y * scale * 0.3
        
        if sx < -100 || sx > screenW + 100 { return nil }
        if sy < -100 || sy > screenH + 100 { return nil }
        
        return (CGFloat(sx), CGFloat(sy))
    }
    
    private func projectWithMatrix(_ world: Vector3) -> (x: CGFloat, y: CGFloat)? {
        let x = world.x
        let y = world.y
        let z = world.z
        let m = viewMatrix
        
        let clipX = m[0] * x + m[4] * y + m[8] * z + m[12]
        let clipY = m[1] * x + m[5] * y + m[9] * z + m[13]
        let clipW = m[3] * x + m[7] * y + m[11] * z + m[15]
        
        guard clipW > 0.1 else { return nil }
        
        let ndcX = clipX / clipW
        let ndcY = clipY / clipW
        
        let sx = (ndcX + 1.0) * 0.5 * screenWidth
        let sy = (1.0 - ndcY) * 0.5 * screenHeight
        
        return (CGFloat(sx), CGFloat(sy))
    }
}
