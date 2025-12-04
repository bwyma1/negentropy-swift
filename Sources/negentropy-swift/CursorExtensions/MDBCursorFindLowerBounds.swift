import QuickLMDB

extension MDB_cursor_basic {
	internal borrowing func findLowerBound(begin:UnsafePointer<MDB_val>, value:UnsafePointer<MDB_val>) throws -> MDB_val {
		let last = try opLast(returning:(key:MDB_val, value:MDB_val).self).key
		var first = begin.pointee
		do {
			first = try opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:begin.pointee).key
		} catch {
			return value.pointee
		}
		guard compareEntryKeys(value.pointee, first) > 0 else {
			return first
		}
		var key:MDB_val = first
		while true {
			guard key != last else {
				return value.pointee
			}
			key = try opNext(returning:(key:MDB_val, value:MDB_val).self).key
			guard compareEntryKeys(value.pointee, key) > 0 else {
				return key
			}
		}
	}
}

extension MDB_cursor_strict where MDB_cursor_dbtype.MDB_db_key_type:DatabaseIndexVector {
	internal borrowing func findLowerBound(begin:UnsafePointer<MDB_val>, value:UnsafePointer<MDB_val>) throws -> MDB_val {
		let last = try opLast(returning:(key:MDB_val, value:MDB_val).self).key
		var first = begin.pointee
		do {
			first = try opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:begin.pointee).key
		} catch {
			return value.pointee
		}
		guard MDB_cursor_dbtype.MDB_db_key_type.MDB_compare_f(value, &first) > 0 else {
			return first
		}
		var key:MDB_val = first
		while true {
			guard key != last else {
				return value.pointee
			}
			key = try opNext(returning:(key:MDB_val, value:MDB_val).self).key
			guard MDB_cursor_dbtype.MDB_db_key_type.MDB_compare_f(value, &key) > 0 else {
				return key
			}
		}
	}
}
