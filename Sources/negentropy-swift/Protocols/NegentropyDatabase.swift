import QuickLMDB

public protocol NegentropyDatabase:MDB_db_strict, Sendable where Self.MDB_db_key_type:DatabaseIndexVector {}
extension Database.Strict: NegentropyDatabase where Self.MDB_db_key_type:DatabaseIndexVector {}
