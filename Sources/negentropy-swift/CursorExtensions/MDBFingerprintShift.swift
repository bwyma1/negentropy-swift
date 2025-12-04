import QuickLMDB
import RAW_blake2
import RAW

@RAW_staticbuff(bytes:24)
public struct Fingerprint:Sendable, Equatable {}

extension MDB_cursor_basic {
	internal func fingerprintShift(begin:UnsafePointer<MDB_val>, bucketSize:Int) throws -> Fingerprint {
		var hasher = try RAW_blake2.Hasher<S, Fingerprint>()
		var key:MDB_val = try opGetCurrent(returning:(key:MDB_val, value:MDB_val).self).key
		try hasher.update(key.mv_data, count:key.mv_size)
		for _ in 1..<bucketSize {
			key = try opNext(returning:(key:MDB_val, value:MDB_val).self).key
			try hasher.update(key.mv_data, count:key.mv_size)
		}
		return try hasher.finish()
	}

	internal func fingerprint(begin:UnsafePointer<MDB_val>, end:UnsafePointer<MDB_val>) throws -> Fingerprint {
		guard compareEntryKeys(begin.pointee, end.pointee) < 0 else {
			return Fingerprint(RAW_staticbuff: Fingerprint.RAW_staticbuff_zeroed())
			//fatalError("fatal usage error: `begin` must be less than `end` \(#file):\(#line)")
		}
		var hasher = try RAW_blake2.Hasher<S, Fingerprint>()
		var key:MDB_val = try opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:begin.pointee).key
		while true {
			try hasher.update(key.mv_data, count:key.mv_size)
			guard compareEntryKeys(key, end.pointee) < 0 else {
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

extension MDB_cursor_strict where Self.MDB_cursor_dbtype.MDB_db_key_type:DatabaseIndexVector {
	internal func fingerprintShift(begin:UnsafePointer<MDB_val>, bucketSize:Int) throws -> Fingerprint {
		var hasher = try RAW_blake2.Hasher<S, Fingerprint>()
		var key:MDB_val = try opGetCurrent(returning:(key:MDB_val, value:MDB_val).self).key
		try hasher.update(key.mv_data, count:key.mv_size)
		for _ in 1..<bucketSize {
			key = try opNext(returning:(key:MDB_val, value:MDB_val).self).key
			try hasher.update(key.mv_data, count:key.mv_size)
		}
		return try hasher.finish()
	}

	internal func fingerprint(begin:UnsafePointer<MDB_val>, end:UnsafePointer<MDB_val>) throws -> Fingerprint {
		guard MDB_cursor_dbtype.MDB_db_key_type.MDB_compare_f(begin, end) < 0 else {
			return Fingerprint(RAW_staticbuff: Fingerprint.RAW_staticbuff_zeroed())
			//fatalError("fatal usage error: `begin` must be less than `end` \(#file):\(#line)")
		}
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
