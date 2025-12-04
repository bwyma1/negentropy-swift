import QuickLMDB

public protocol NegentropyDatabaseStrict:MDB_db_strict, Sendable where Self.MDB_db_key_type:DatabaseIndexVector {}
extension Database.Strict: NegentropyDatabaseStrict where Self.MDB_db_key_type:DatabaseIndexVector {}

public protocol NegentropyDatabase:MDB_db_basic, Sendable {}
extension Database: NegentropyDatabase {}
