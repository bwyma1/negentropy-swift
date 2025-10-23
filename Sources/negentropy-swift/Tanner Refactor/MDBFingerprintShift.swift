import QuickLMDB
import RAW_blake2
import RAW

@RAW_staticbuff(bytes:24)
public struct Fingerprint:Sendable, Equatable {}

extension MDB_cursor_strict where Self.MDB_cursor_dbtype.MDB_db_key_type:DatabaseIndexVector {
	internal func fingerprintShift(begin:UnsafePointer<MDB_val>, bucketSize:Int) throws -> Fingerprint {
		var hasher = try RAW_blake2.Hasher<S, Fingerprint>()
		var key:MDB_val = try opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:begin.pointee).key
		try hasher.update(key.mv_data, count:key.mv_size)
		for _ in 1..<bucketSize {
			key = try opNext(returning:(key:MDB_val, value:MDB_val).self).key
			try hasher.update(key.mv_data, count:key.mv_size)
		}
		return try hasher.finish()
	}

	internal func fingerprint(begin:UnsafePointer<MDB_val>, end:UnsafePointer<MDB_val>) throws -> Fingerprint {
		#if DEBUG
		guard MDB_cursor_dbtype.MDB_db_key_type.MDB_compare_f(begin, end) < 0 else {
			fatalError("fatal usage error: `begin` must be less than `end` \(#file):\(#line)")
		}
		#endif
		var hasher = try RAW_blake2.Hasher<S, Fingerprint>()
		var key:MDB_val = try opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:begin.pointee).key
		while true {
			try hasher.update(key.mv_data, count:key.mv_size)
			guard MDB_cursor_dbtype.MDB_db_key_type.MDB_compare_f(&key, end) < 0 else {
				break
			}
			do {
				key = try opNext(returning:(key:MDB_val, value:MDB_val).self).key
			} catch LMDBError.notFound {
				break
			}
		}
		return try hasher.finish()
	}
}
