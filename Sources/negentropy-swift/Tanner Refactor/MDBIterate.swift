import RAW
import RAW_blake2
import QuickLMDB

extension MDB_cursor_strict where Self.MDB_cursor_dbtype.MDB_db_key_type:DatabaseIndexVector {
	internal borrowing func iterate(begin:UnsafePointer<MDB_val>, _ cb:(UnsafePointer<MDB_val>) -> Bool) throws {
		var key:MDB_val = try opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:begin.pointee).key
		while cb(&key) {
			do {
				key = try opNext(returning:(key:MDB_val, value:MDB_val).self).key
			} catch LMDBError.notFound {
				break
			}
		}
	}
	
	internal borrowing func iterate(begin:UnsafePointer<MDB_val>, end:UnsafePointer<MDB_val>, _ cb:(UnsafePointer<MDB_val>) -> Bool) throws {
		guard MDB_cursor_dbtype.MDB_db_key_type.MDB_compare_f(begin, end) != 0 else {
			return
		}
		var key:MDB_val = try opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:begin.pointee).key
		while cb(&key) {
			do {
				key = try opNext(returning:(key:MDB_val, value:MDB_val).self).key
				guard MDB_cursor_dbtype.MDB_db_key_type.MDB_compare_f(&key, end) < 0 else {
					break
				}
			}
		}
	}
}