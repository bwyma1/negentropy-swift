import QuickLMDB

extension MDB_cursor_basic {
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
		guard compareEntryKeys(begin.pointee, end.pointee) != 0 else {
			return 0
		}
		#if DEBUG
		guard compareEntryKeys(begin.pointee, end.pointee) < 0 else {
			fatalError("critical developer error: begin key must be less than end key - \(#file):\(#line)")
		}
		#endif
		var count = 0
		do {
			var key:MDB_val = try opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:begin.pointee).key
			while compareEntryKeys(key, end.pointee) < 0 {
				count += 1
				do {
					key = try opNext(returning:(key:MDB_val, value:MDB_val).self).key
				} catch {
					break
				}
			}
			return count
		} catch LMDBError.notFound {
			return count
		}
	}
}

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
		guard MDB_cursor_dbtype.MDB_db_key_type.MDB_compare_f(begin, end) != 0 else {
			return 0
		}
		#if DEBUG
		guard MDB_cursor_dbtype.MDB_db_key_type.MDB_compare_f(begin, end) < 0 else {
			fatalError("critical developer error: begin key must be less than end key - \(#file):\(#line)")
		}
		#endif
		var count = 0
		do {
			var key:MDB_val = try opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:begin.pointee).key
			while MDB_cursor_dbtype.MDB_db_key_type.MDB_compare_f(&key, end) < 0 {
				count += 1
				do {
					key = try opNext(returning:(key:MDB_val, value:MDB_val).self).key
				} catch {
					break
				}
			}
			return count
		} catch LMDBError.notFound {
			return count
		}
	}
}
