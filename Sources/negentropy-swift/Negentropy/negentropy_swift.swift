import QuickLMDB

let MAX_U64: UInt64 = UInt64.max

struct Negentropy<DatabaseType> where DatabaseType:MDB_db_strict, DatabaseType.MDB_db_key_type: StorageItem {
	
	// Bound for checking against items
	public struct Bound: Equatable, Comparable {
		public var item:Index
		public var idLen:Int
		
		/// `Bound(timestamp:idSlice:)`
		init(timestamp:TimeStamp = TimeStamp(RAW_native: 0), idSlice:[UInt8] = []) throws {
			let suppliedLen = idSlice.count
			guard suppliedLen <= ID_SIZE else {
				throw NegentropyError.badIDSize
			}
			
			self.idLen = idSlice.count
			self.item = Index(timestamp: timestamp.RAW_native())
			
			self.item.RAW_access_mutating({ myStructBuff in
				for i in 0..<idSlice.count {
					myStructBuff[i] = idSlice[i]
				}
			})
			
		}
		
		/// `Bound(item:)`
		init(item: Index) {
			var constructedItem: Index? = nil
			try! item.id.RAW_access_staticbuff({ myStructBuff in
				constructedItem = try Index(timestamp: 0, id: Index.StoredIdType(RAW_staticbuff: myStructBuff))
			})
			self.item = constructedItem!
			self.idLen = ID_SIZE
		}
		
		static public func == (lhs: Bound, rhs: Bound) -> Bool {
			lhs.item == rhs.item
		}

		static public func < (lhs: Bound, rhs: Bound) -> Bool {
			lhs.item < rhs.item
		}
	}
	
	typealias Index = DatabaseType.MDB_db_key_type
	typealias ID = DatabaseType.MDB_db_key_type.StoredIdType
	
	var storage: DatabaseType
	var frameSizeLimit: UInt64
	
	var isInitiator = false
	
	var lastTimestampIn:TimeStamp = TimeStamp(RAW_staticbuff: TimeStamp.RAW_staticbuff_zeroed())
	var lastTimestampOut:TimeStamp = TimeStamp(RAW_staticbuff: TimeStamp.RAW_staticbuff_zeroed())
	
	init(storage: DatabaseType, frameSizeLimit: UInt64 = 0) throws {
		if frameSizeLimit != 0 && frameSizeLimit < 4096 {
			throw NegentropyError.frameSizeTooSmall
		}
		self.storage = storage
		self.frameSizeLimit = frameSizeLimit
	}
	
	public mutating func initiate() throws -> [UInt8] {
		guard !isInitiator else {
			throw NegentropyError.wrongInitiator
		}
		isInitiator = true
		
		var output:[UInt8] = []
		let ts = TimeStamp(RAW_native: MAX_U64)
		var bound = try Bound(timestamp: ts)
		output += try splitRange(lower: storage.first(), upper: storage.last(), upperBound: &bound)
		
		return output
	}
	
	public mutating func setInitiator() {
		isInitiator = true
	}
	
	public mutating func reconcile(query: consuming [UInt8]) throws -> [UInt8] {
		guard !isInitiator else {
			throw NegentropyError.wrongInitiator
		}
		var haveIds:[ID] = []
		var needIds:[ID] = []
		return try reconcileAux(query: &query, haveIds: &haveIds, needIds: &needIds)
	}
	
	public mutating func reconcile(query: consuming [UInt8], haveIds: inout [ID], needIds: inout [ID]) throws -> [UInt8]? {
		guard isInitiator else {
			throw NegentropyError.wrongInitiator
		}
		let output = try reconcileAux(query: &query, haveIds: &haveIds, needIds: &needIds)
		if output.count == 0 {
			return nil
		}
		return output
	}
	
	private mutating func doSkip(_ o: inout [UInt8], _ skip: inout Bool, _ prevBound:Bound) {
		if skip {
			skip = false
			o += encodeBound(prevBound)
			o += encodeVarInt(Mode.skip.rawValue)
		}
	}
	
	private mutating func reconcileAux(query: inout [UInt8], haveIds: inout [ID], needIds: inout [ID]) throws -> [UInt8] {
		// Reset timestamps
		lastTimestampIn = TimeStamp(RAW_staticbuff: TimeStamp.RAW_staticbuff_zeroed())
		lastTimestampOut = TimeStamp(RAW_staticbuff: TimeStamp.RAW_staticbuff_zeroed())
		
		var fullOutput:[UInt8] = []
		
		let storageSize = try storage.size()
		var prevBound = try Bound()
		var prevIndex:Index = try storage.first()
		var skip:Bool = false
		let end = try storage.last()
		
		while (query.count != 0) {
			// Temporary output for this iteration
			var o:[UInt8] = []
			
			var currBound = try decodeBound(encoded: &query)
			let mode = try Mode(rawValue: Int(decodeVarInt(&query)))
			
			let lower = prevIndex
			var upper = try storage.findLowerBound(begin: prevIndex, end: end, value: currBound.item)
			
			switch mode {
				case .skip:
					skip = true
				case .fingerprint:
					let theirFingerprint = try getBytes(&query, 16)
					let ourFingerprint = try storage.fingerprint(begin: lower, end: upper)
					
					try ourFingerprint.RAW_access { ptr in
						if(theirFingerprint != Array(UnsafeBufferPointer(start: ptr.baseAddress!, count: ptr.count))) {
							doSkip(&o, &skip, prevBound)
							o += try splitRange(lower: lower, upper: upper, upperBound: &currBound)
						} else {
							skip = true
						}
					}
				case .idList:
					let numIds = try decodeVarInt(&query)
					
					var theirElems:[ID] = []
					for _ in 0..<numIds {
						let e = try getBytes(&query, 32)
						e.withUnsafeBufferPointer { ptr in
							let id = ID(RAW_accessed: ptr)
							if(isInitiator) { theirElems.append(id!) }
						}
					}
					
					if(isInitiator) {
						skip = true
						
						try storage.iterate(begin: lower, end: upper, cb: { item in
							let k = item.id
							
							if let index = theirElems.firstIndex(of: k) {
								// ID exists on both sides
								theirElems.remove(at: index)
							} else {
								// ID exists on our side, but not their side
								haveIds.append(k)
							}
						})
						
						for k in theirElems {
							needIds.append(k)
						}
					} else {
						doSkip(&o, &skip, prevBound)
						
						var responseIds:[UInt8] = []
						var numResponseIds = 0
						
						var endBound = currBound
						
						try storage.iterate(begin: lower, end: upper, cb: { item in
							if(exceededFrameSizeLimit(fullOutput.count + responseIds.count)) {
								endBound = Bound(item: item)
								upper = item
								return
							}
							responseIds += item.getId()
							numResponseIds += 1
							return
						})
						
						o += encodeBound(endBound)
						o += encodeVarInt(Mode.idList.rawValue)
						o += encodeVarInt(numResponseIds)
						o += responseIds
						
						fullOutput += o
						o = []
					}
				default:
					throw NegentropyError.unexpectedMode
			}
			
			if(exceededFrameSizeLimit(fullOutput.count + o.count)) {
				let remainingFingerprint = try storage.fingerprint(begin: upper, end: end)
				let ts = TimeStamp(RAW_native: MAX_U64)
				
				fullOutput += try encodeBound(Bound(timestamp: ts))
				fullOutput += encodeVarInt(Mode.fingerprint.rawValue)
				remainingFingerprint.RAW_access ({ ptr in
					fullOutput += Array(UnsafeBufferPointer(start: ptr.baseAddress!, count: ptr.count))
				})
				break
			} else {
				fullOutput += o
			}
			
			prevIndex = upper
			prevBound = currBound
		}
		
		return fullOutput
	}
	
	private func exceededFrameSizeLimit(_ size:Int) -> Bool {
		return frameSizeLimit != 0 && size > frameSizeLimit - 200
	}
	
	private mutating func splitRange(lower:Index, upper:Index, upperBound: inout Bound) throws -> [UInt8] {
		var ret:[UInt8] = []
		
		let numElements:Int = try storage.numElements(begin: lower, end: upper)
		let buckets = 16
		
		if(numElements < buckets * 2) {
			ret += encodeBound(upperBound)
			ret += encodeVarInt(Mode.idList.rawValue)
			
			ret += encodeVarInt(numElements)
			
			try storage.iterate(begin: lower, end: upper, cb: { item in
				item.id.RAW_access({ptr in
					ret += Array(UnsafeBufferPointer(start: ptr.baseAddress!, count: ptr.count))
				})
			})
		} else {
			let itemsPerBucket:Int = numElements / buckets
			let bucketsWithExtra = numElements % buckets
			var curr = lower
			
			for i in 0..<buckets {
				let bucketSize = itemsPerBucket + (i < bucketsWithExtra ? 1 : 0)
				let shifted = try! storage.shift(curr: curr, amount: bucketSize)
				let ourFingerprint = try storage.fingerprint(begin: curr, end: shifted)
				curr = shifted
				
				var nextBound:Bound
				
				if(curr == upper) {
					nextBound = upperBound
				} else {
					let currItem = curr
					let prevItem = try storage.prev(curr: currItem)

					nextBound = try getMinimalBound(prev: prevItem, curr: currItem)
				}
				
				ret += encodeBound(nextBound)
				ret += encodeVarInt(Mode.fingerprint.rawValue)
				ourFingerprint.RAW_access( { ptr in
					ret += Array(UnsafeBufferPointer(start: ptr.baseAddress!, count: FINGERPRINT_SIZE))
				})
			}
		}
		return ret
	}
	
	private mutating func decodeTimestampIn(encoded: inout [UInt8]) throws -> UInt64 {
		var timestamp:UInt64 = 0
		timestamp = try decodeVarInt(&encoded)
		if(timestamp == 0) {
			timestamp = MAX_U64
		} else {
			timestamp = UInt64(timestamp) - 1 + lastTimestampIn.RAW_native()
		}
		lastTimestampIn = TimeStamp(RAW_native: timestamp)
		return timestamp
	}
	
	mutating func decodeBound(encoded: inout [UInt8]) throws -> Bound {
		let timestamp = try decodeTimestampIn(encoded: &encoded)
		var len = 0
		len = try Int(decodeVarInt(&encoded))
		return try Bound(timestamp: TimeStamp(RAW_native: timestamp), idSlice: getBytes(&encoded, len))
	}
		
	private mutating func encodeTimestampOut(timestamp:TimeStamp) -> [UInt8] {
		let ts = timestamp.RAW_native()
		if (ts == MAX_U64) {
			lastTimestampOut = TimeStamp(RAW_native: MAX_U64)
			return encodeVarInt(0)
		}

		let ret = timestamp.RAW_native() - lastTimestampOut.RAW_native()
		timestamp.RAW_access_staticbuff({ myStructBuff in
			lastTimestampOut = TimeStamp(RAW_staticbuff: myStructBuff)
		})

		return encodeVarInt(Int(ret) + 1)
	}
	
	mutating func encodeBound(_ b:Bound) -> [UInt8] {
		var ret:[UInt8] = []
		let time = b.item.timestamp.RAW_access_staticbuff { ptr in
			return TimeStamp(RAW_staticbuff: ptr)
		}
		ret += encodeTimestampOut(timestamp: time)
		ret += encodeVarInt(b.idLen)
		b.item.id.RAW_access { ptr in
			ret += Array(UnsafeBufferPointer(start: ptr.baseAddress!, count: Int(b.idLen)))
		}
		return ret
	}
	
	private func getMinimalBound(prev:Index, curr:Index) throws -> Bound{
		let ts = curr.timestamp.RAW_access_staticbuff { ptr in
			return TimeStamp(RAW_staticbuff: ptr)
		}
		if(curr.timestamp != prev.timestamp) {
			return try Bound(timestamp: ts)
		} else {
			var sharedPrefixBytes:Int = 0
			let currKey = curr.id
			let prevKey = prev.id
			
			currKey.RAW_access { ptr in
				prevKey.RAW_access { ptr2 in
					for i in 0..<ID_SIZE {
						if(ptr[i] != ptr2[i]) {
							break
						}
						sharedPrefixBytes += 1
					}
				}
			}
			
			return try currKey.RAW_access { ptr in
				return try Bound(timestamp: ts, idSlice: Array(UnsafeBufferPointer(start: ptr.baseAddress!, count: sharedPrefixBytes + 1)))
			}
		}
	}
}
