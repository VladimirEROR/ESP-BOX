import Foundation

// MARK: - MLBB v2.1.95 Offsets
struct MLBBOffsets {
    
    // GameMapBase Methods (RVA)
    static let get_Instance: UInt64        = 0x3F2F90C
    static let FindAllPlayerInMap: UInt64  = 0x3F2E7A8
    
    // EntityBase Field Offsets
    static let m_Hp: UInt64            = 0xC8
    static let m_HpMax: UInt64          = 0xCC
    static let m_EntityCampType: UInt64 = 0x1DC
    static let m_bDeath: UInt64         = 0x1D0
    static let m_bSelf: UInt64          = 0x1B0
    static let m_uGuid: UInt64          = 0xA8
    static let m_ID: UInt64             = 0xAC
    static let m_Level: UInt64          = 0xB4
    static let IsPlayer: UInt64         = 0x5C
    
    // ShowEntity Additional Offsets
    static let m_vCachePosition: UInt64 = 0x294  // Vector3
    static let m_EntityObjPos: UInt64   = 0x310  // Vector3
    static let m_Owner: UInt64          = 0x420
    static let _logicFighter: UInt64    = 0x3C8
}
