import QuickLMDB

extension MDB_cursor_strict where MDB_cursor_dbtype.MDB_db_key_type:DatabaseIndexVector {
	
	internal borrowing func findLowerBound(begin:UnsafePointer<MDB_val>, end:UnsafePointer<MDB_val>, value:UnsafePointer<MDB_val>) throws -> MDB_val {
		var first = try opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:begin.pointee).key
		guard MDB_cursor_dbtype.MDB_db_key_type.MDB_compare_f(value, &first) > 0 else {
			return first
		}
		do {
			var key:MDB_val
			while true {
				key = try opNext(returning:(key:MDB_val, value:MDB_val).self).key
				guard MDB_cursor_dbtype.MDB_db_key_type.MDB_compare_f(&key, end) != 0 else {
					return end.pointee
				}
				guard MDB_cursor_dbtype.MDB_db_key_type.MDB_compare_f(value, &key) > 0 else {
					return key
				}
			}
			return end.pointee
		} catch LMDBError.notFound {
			return end.pointee
		}
	}

	internal borrowing func findLowerBound(begin:UnsafePointer<MDB_val>, value:UnsafePointer<MDB_val>) throws -> MDB_val {
		var first = try opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:begin.pointee).key
		guard MDB_cursor_dbtype.MDB_db_key_type.MDB_compare_f(value, &first) > 0 else {
			return first
		}
		var key:MDB_val
		while true {
			key = try opNext(returning:(key:MDB_val, value:MDB_val).self).key
			guard MDB_cursor_dbtype.MDB_db_key_type.MDB_compare_f(value, &key) > 0 else {
				return key
			}
		}
	}
}
