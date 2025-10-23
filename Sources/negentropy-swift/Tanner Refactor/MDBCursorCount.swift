import QuickLMDB

extension MDB_cursor_strict where Self.MDB_cursor_dbtype.MDB_db_key_type:DatabaseIndexVector {
	internal borrowing func countEntries(begin:UnsafePointer<MDB_val>) throws -> Int {
		var count = 0
		do {
			_ = try opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:begin.pointee).key
			count += 1
			while true {
				_ = try opNext(returning:(key:MDB_val, value:MDB_val).self).key
				count += 1
			}
		} catch LMDBError.notFound {
			return count
		}
	}
	internal borrowing func countEntries(begin:UnsafePointer<MDB_val>, end:UnsafePointer<MDB_val>) throws -> Int {
		#if DEBUG
		guard MDB_cursor_dbtype.MDB_db_key_type.MDB_compare_f(begin, end) < 0 else {
			fatalError("critical developer error: begin key must be less than end key - \(#file):\(#line)")
		}
		#endif
		var count = 0
		do {
			var key:MDB_val = try opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:begin.pointee).key
			while MDB_cursor_dbtype.MDB_db_key_type.MDB_compare_f(&key, end) < 0 {
				key = try opNext(returning:(key:MDB_val, value:MDB_val).self).key
				count += 1
			}
			return count
		} catch LMDBError.notFound {
			return count
		}
	}
}
