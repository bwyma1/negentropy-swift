import RAW
import RAW_blake2
import QuickLMDB

extension MDB_db_strict where Self.MDB_db_key_type: StorageID {
	
	func size() throws -> Int {
		let env = dbEnvironment()
		let trans = try Transaction(env: env, readOnly: true)
		return try dbStatistics(tx: trans).ms_entries
	}
	
	func numElements(begin: Self.MDB_db_key_type?, end: Self.MDB_db_key_type?) throws -> Int {
		guard let begin = begin else { return 0 }
		let env = dbEnvironment()
		let trans = try Transaction(env: env, readOnly: true)
		return try cursor(tx: trans) { cursor in
			var count = 0
			if(begin == end) {return count}
			var key:Self.MDB_db_key_type? = try cursor.opSetRange(key: begin).key
			while true {
				if(key == end || key == nil) {
					return count
				}
				key = try? cursor.opNext().key
				count += 1
			}
		}
	}

	func first() throws -> Self.MDB_db_key_type? {
		guard try size() > 0 else { return nil }
		let env = dbEnvironment()
		let trans = try Transaction(env: env, readOnly: true)
		return try cursor(tx: trans) { cursor in
			return try cursor.opFirst().key
		}
	}
	
	func last() throws -> Self.MDB_db_key_type? {
		guard try size() > 0 else { return nil }
		let env = dbEnvironment()
		let trans = try Transaction(env: env, readOnly: true)
		return try cursor(tx: trans) { cursor in
			return try cursor.opLast().key
		}
	}
	
	func shift(curr: Self.MDB_db_key_type, amount: Int) throws -> Self.MDB_db_key_type? {
		let env = dbEnvironment()
		let trans = try Transaction(env: env, readOnly: true)
		return try cursor(tx: trans) { cursor in
			_ = try cursor.opSetRange(key: curr)
			for _ in 0..<abs(amount) {
				if amount < 0 {
					_ = try cursor.opPrevious()
				} else {
					do {
						_ = try cursor.opNext()
					} catch {
						return nil
					}
				}
			}
			return try cursor.opGetCurrent().key
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

	func iterate(begin: Self.MDB_db_key_type?, end: Self.MDB_db_key_type?, cb: (Self.MDB_db_key_type) -> Bool) throws {
		guard let begin = begin else { return }
		if(begin == end) {return}
		let env = dbEnvironment()
		let trans = try Transaction(env: env, readOnly: true)
		try cursor(tx: trans) { cursor in
			var key:Self.MDB_db_key_type? = try cursor.opSetRange(key: begin).key
			while true {
				if(cb(key!) == false) {
					break
				}
				key = try? cursor.opNext().key
				guard let end = end else {
					if(key == end) {
						break
					}
					continue
				}
				if(key! >= end) {
					break
				}
			}
		}
	}

	func findLowerBound(begin: Self.MDB_db_key_type?, end: Self.MDB_db_key_type?, value: Self.MDB_db_key_type) throws -> Self.MDB_db_key_type? {
		guard let begin = begin else { return nil }
		let env = dbEnvironment()
		let trans = try Transaction(env: env, readOnly: true)
		return try cursor(tx: trans) { cursor in
			let first = try cursor.opSetRange(key: begin).key
			if(value <= first) {
				return first
			}
			while let key = try? cursor.opNext().key {
				if(key == end) {
					break
				}
				if(value <= key) {
					return key
				}
			}
			return end
		}
	}

	func fingerprint(begin: Self.MDB_db_key_type?, end: Self.MDB_db_key_type?) throws -> Fingerprint {
		guard let begin = begin else {
			return Fingerprint(RAW_staticbuff: Fingerprint.RAW_staticbuff_zeroed())
		}
		if(end != nil) {
			guard begin < end! else {
				return Fingerprint(RAW_staticbuff: Fingerprint.RAW_staticbuff_zeroed())
			}
		}
		var hasher = try WGHasher<Self.MDB_db_key_type>()
		let env = dbEnvironment()
		let trans = try Transaction(env: env, readOnly: true)
		try cursor(tx: trans) { cursor in
			var key:Self.MDB_db_key_type? = try cursor.opSetRange(key: begin).key
			while true {
				try hasher.update(key!)
				key = try? cursor.opNext().key
				guard let end = end else {
					if(key == end) {
						break
					}
					continue
				}
				if(key! >= end) {
					break
				}
			}
		}
		let h = try hasher.finish()
		return h.RAW_access { ptr in
			let first16 = Array(ptr.prefix(FINGERPRINT_SIZE)) + Array(repeating: 0, count: max(0, FINGERPRINT_SIZE - ptr.count))
			return first16.withUnsafeBufferPointer { arrPtr in
				return Fingerprint(RAW_staticbuff: arrPtr.baseAddress!)
			}
		}
	}
	
	func itemFor(_ id: Self.MDB_db_key_type) throws -> Self.MDB_db_val_type? {
		let env = dbEnvironment()
		let trans = try Transaction(env: env, readOnly: true)
		return try cursor(tx: trans) { cursor in
			let end = try cursor.opLast()
			let first = try cursor.opFirst()
			if(first.key == id) {
				return first.value
			}
			while let next = try? cursor.opNext() {
				if(next.key == id) {
					return next.value
				}
				if(next.key >= end.key) {
					break
				}
			}
			return nil
		}
	}
}
