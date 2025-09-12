import RAW
import RAW_blake2
import QuickLMDB

extension MDB_db_strict where Self.MDB_db_key_type: StorageItem {
	
	func size() throws -> Int {
		let env = dbEnvironment()
		let trans = try Transaction(env: env, readOnly: true)
		return try dbStatistics(tx: trans).ms_entries
	}
	
	func numElements(begin: Self.MDB_db_key_type, end: Self.MDB_db_key_type) throws -> Int {
		let env = dbEnvironment()
		let trans = try Transaction(env: env, readOnly: true)
		return try cursor(tx: trans) { cursor in
			var count = 0
			if(begin == end) {return count + 1}
			_ = try cursor.opSetRange(key: begin).key
			while let key = try? cursor.opNext().key {
				count += 1
				if(key >= end) {
					return count + 1
				}
			}
			return count + 1
		}
	}

	func first() throws -> Self.MDB_db_key_type {
		let env = dbEnvironment()
		let trans = try Transaction(env: env, readOnly: true)
		return try cursor(tx: trans) { cursor in
			return try cursor.opFirst().key
		}
	}
	
	func last() throws -> Self.MDB_db_key_type {
		let env = dbEnvironment()
		let trans = try Transaction(env: env, readOnly: true)
		return try cursor(tx: trans) { cursor in
			return try cursor.opLast().key
		}
	}
	
	func shift(curr: Self.MDB_db_key_type, amount: Int) throws -> Self.MDB_db_key_type {
		let env = dbEnvironment()
		let trans = try Transaction(env: env, readOnly: true)
		return try cursor(tx: trans) { cursor in
			let end = try cursor.opLast().key
			_ = try cursor.opSetRange(key: curr)
			for _ in 0..<abs(amount) {
				if(try cursor.opGetCurrent().key == end) {
					return try cursor.opLast().key
				}
				if amount < 0 {
					_ = try cursor.opPrevious()
				} else {
					_ = try! cursor.opNext()
				}
			}
			return try! cursor.opGetCurrent().key
		}
	}
	
	func prev(curr:Self.MDB_db_key_type) throws -> Self.MDB_db_key_type {
		let env = dbEnvironment()
		let trans = try Transaction(env: env, readOnly: true)
		return try cursor(tx: trans) { cursor in
			_ = try cursor.opSetRange(key: curr)
			return try cursor.opPrevious().key
		}
	}

	func iterate(begin: Self.MDB_db_key_type, end: Self.MDB_db_key_type, cb: (Self.MDB_db_key_type) -> Void) throws {
		let env = dbEnvironment()
		let trans = try Transaction(env: env, readOnly: true)
		try cursor(tx: trans) { cursor in
			let first = try cursor.opSetRange(key: begin).key
			cb(first)
			while let key = try? cursor.opNext().key {
				cb(key)
				if(key >= end) {
					break
				}
			}
		}
	}

	func findLowerBound(begin: Self.MDB_db_key_type, end: Self.MDB_db_key_type, value: Self.MDB_db_key_type) throws -> Self.MDB_db_key_type {
		let env = dbEnvironment()
		let trans = try Transaction(env: env, readOnly: true)
		return try cursor(tx: trans) { cursor in
			let first = try cursor.opSetRange(key: begin).key
			if(value <= first) {
				return first
			}
			while let key = try? cursor.opNext().key {
				if(value <= key) {
					return key
				}
				if(key >= end) {
					break
				}
			}
			return end
		}
	}

	func fingerprint(begin: Self.MDB_db_key_type, end: Self.MDB_db_key_type) throws -> Fingerprint {
		guard begin < end else {
			return Fingerprint(RAW_staticbuff: Fingerprint.RAW_staticbuff_zeroed())
		}
		var hasher = try WGHasher<Self.MDB_db_key_type.StoredIdType>()
		let env = dbEnvironment()
		let trans = try Transaction(env: env, readOnly: true)
		try cursor(tx: trans) { cursor in
			let first = try cursor.opSetRange(key: begin).key
			try hasher.update(first.id)
			while let key = try? cursor.opNext().key {
				if(key >= end) {
					break
				}
				try hasher.update(key.id)
			}
		}
		let h = try hasher.finish()
		var fingerprint:Fingerprint? = nil
		h.RAW_access { ptr in
			let first16 = ptr.prefix(16)
			fingerprint = Fingerprint(RAW_accessed: UnsafeBufferPointer(rebasing: first16))
		}
		return fingerprint!
	}
	
	func itemFor(_ id: Self.MDB_db_key_type.StoredIdType) throws -> Self.MDB_db_key_type? {
		let env = dbEnvironment()
		let trans = try Transaction(env: env, readOnly: true)
		return try cursor(tx: trans) { cursor in
			let first = try cursor.opFirst().key
			let end = try cursor.opLast().key
			while let key = try? cursor.opNext().key {
				if(key.id == id) {
					return key
				}
				if(key >= end) {
					break
				}
			}
			return nil
		}
	}
}
