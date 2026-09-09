import RAW
import RAW_blake2
import QuickLMDB

extension MDB_cursor_basic {
	/// Applies the cb function to every item in the database from [begin, opLast()]
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
	
	/// Applies the cb function to every item in the database from [begin, end)
	internal borrowing func iterate(begin:UnsafePointer<MDB_val>, end:UnsafePointer<MDB_val>, _ cb:(UnsafePointer<MDB_val>) -> Bool) throws {
		guard compareEntryKeys(begin.pointee, end.pointee) != 0 else {
			return
		}
		var key:MDB_val = try opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:begin.pointee).key
		while cb(&key) {
			do {
				do {
					key = try opNext(returning:(key:MDB_val, value:MDB_val).self).key
				} catch LMDBError.notFound {
					break
				}
				guard compareEntryKeys(key, end.pointee) < 0 else {
					break
				}
			}
		}
	}
}

extension MDB_cursor_strict where Self.MDB_cursor_dbtype.MDB_db_key_type:DatabaseIndexVector {
	/// Applies the cb function to every item in the database from [begin, opLast()]
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
	
	/// Applies the cb function to every item in the database from [begin, end)
	internal borrowing func iterate(begin:UnsafePointer<MDB_val>, end:UnsafePointer<MDB_val>, _ cb:(UnsafePointer<MDB_val>) -> Bool) throws {
		guard MDB_cursor_dbtype.MDB_db_key_type.MDB_compare_f(begin, end) != 0 else {
			return
		}
		var key:MDB_val = try opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:begin.pointee).key
		while cb(&key) {
			do {
				do {
					key = try opNext(returning:(key:MDB_val, value:MDB_val).self).key
				} catch LMDBError.notFound {
					break
				}
				guard MDB_cursor_dbtype.MDB_db_key_type.MDB_compare_f(&key, end) < 0 else {
					break
				}
			}
		}
	}
}
