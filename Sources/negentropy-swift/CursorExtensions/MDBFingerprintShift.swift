import QuickLMDB
import RAW_blake2
import RAW

@RAW_staticbuff(bytes:24)
public struct Fingerprint:Sendable, Equatable {}

/// Decodes a raw 24-byte blake2s digest into a `Fingerprint`.
internal func decodeFingerprint(fromDigest digest:[UInt8]) -> Fingerprint {
	return digest.withUnsafeBytes { Fingerprint(RAW_decode:$0)! }
}

/// A zeroed fingerprint (no entries hashed) — the v22 spelling of the deprecated
/// `Fingerprint.RAW_staticbuff_zeroed()`.
internal func zeroedFingerprint() -> Fingerprint {
	return [UInt8](repeating:0, count:MemoryLayout<Fingerprint>.size).withUnsafeBytes { Fingerprint(RAW_decode:$0)! }
}

extension MDB_cursor_basic {
	/// Makes the Fingerprint for the items in the database from [begin, begin + bucketSize)
	/// Also shifts the cursor to the start of the next bucket.
	internal func fingerprintShift(begin:UnsafePointer<MDB_val>, bucketSize:Int) throws -> Fingerprint {
		var hasher = try RAW_blake2.Hasher<S, [UInt8]>(outputLength: MemoryLayout<Fingerprint>.size)
		var key:MDB_val = try opGetCurrent(returning:(key:MDB_val, value:MDB_val).self).key
		try hasher.update(UnsafeRawBufferPointer(start:key.mv_data, count:key.mv_size))
		for _ in 1..<bucketSize {
			key = try opNext(returning:(key:MDB_val, value:MDB_val).self).key
			try hasher.update(UnsafeRawBufferPointer(start:key.mv_data, count:key.mv_size))
		}
		return decodeFingerprint(fromDigest: try hasher.finish())
	}

	/// Makes the Fingerprint for the items in the database from [begin, end]
	internal func fingerprint(begin:UnsafePointer<MDB_val>, end:UnsafePointer<MDB_val>) throws -> Fingerprint {
		guard compareEntryKeys(begin.pointee, end.pointee) < 0 else {
			return zeroedFingerprint()
		}
		var hasher = try RAW_blake2.Hasher<S, [UInt8]>(outputLength: MemoryLayout<Fingerprint>.size)
		var key:MDB_val = try opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:begin.pointee).key
		while true {
			try hasher.update(UnsafeRawBufferPointer(start:key.mv_data, count:key.mv_size))
			guard compareEntryKeys(key, end.pointee) < 0 else {
				break
			}
			do {
				key = try opNext(returning:(key:MDB_val, value:MDB_val).self).key
			} catch LMDBError.notFound {
				break
			}
		}
		return decodeFingerprint(fromDigest: try hasher.finish())
	}
}

extension MDB_cursor_strict where Self.MDB_cursor_dbtype.MDB_db_key_type:DatabaseIndexVector {
	/// Makes the Fingerprint for the items in the database from [begin, begin + bucketSize)
	/// Also shifts the cursor to the start of the next bucket.
	internal func fingerprintShift(begin:UnsafePointer<MDB_val>, bucketSize:Int) throws -> Fingerprint {
		var hasher = try RAW_blake2.Hasher<S, [UInt8]>(outputLength: MemoryLayout<Fingerprint>.size)
		var key:MDB_val = try opGetCurrent(returning:(key:MDB_val, value:MDB_val).self).key
		try hasher.update(UnsafeRawBufferPointer(start:key.mv_data, count:key.mv_size))
		for _ in 1..<bucketSize {
			key = try opNext(returning:(key:MDB_val, value:MDB_val).self).key
			try hasher.update(UnsafeRawBufferPointer(start:key.mv_data, count:key.mv_size))
		}
		return decodeFingerprint(fromDigest: try hasher.finish())
	}

	/// Makes the Fingerprint for the items in the database from [begin, end]
	internal func fingerprint(begin:UnsafePointer<MDB_val>, end:UnsafePointer<MDB_val>) throws -> Fingerprint {
		guard MDB_cursor_dbtype.MDB_db_key_type.MDB_compare_f(begin, end) < 0 else {
			return zeroedFingerprint()
		}
		var hasher = try RAW_blake2.Hasher<S, [UInt8]>(outputLength: MemoryLayout<Fingerprint>.size)
		var key:MDB_val = try opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:begin.pointee).key
		while true {
			try hasher.update(UnsafeRawBufferPointer(start:key.mv_data, count:key.mv_size))
			guard MDB_cursor_dbtype.MDB_db_key_type.MDB_compare_f(&key, end) < 0 else {
				break
			}
			do {
				key = try opNext(returning:(key:MDB_val, value:MDB_val).self).key
			} catch LMDBError.notFound {
				break
			}
		}
		return decodeFingerprint(fromDigest: try hasher.finish())
	}
}
