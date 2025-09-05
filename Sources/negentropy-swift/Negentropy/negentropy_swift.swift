let MAX_U64: UInt64 = UInt64.max

struct Negentropy<StorageImpl:StorageBase> {
	var storage:StorageImpl
//	typealias sItem = StorageImpl.Item
	var frameSizeLimit: UInt64
	
	var isInitiator = false
	
	var lastTimestampIn:TimeStamp = TimeStamp(RAW_staticbuff: TimeStamp.RAW_staticbuff_zeroed())
	var lastTimestampOut:TimeStamp = TimeStamp(RAW_staticbuff: TimeStamp.RAW_staticbuff_zeroed())
	
	init(storage: StorageImpl, frameSizeLimit: UInt64 = 0) throws {
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
		output += try splitRange(lower: 0, upper: storage.size(), upperBound: &bound)
		
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
		
		let storageSize = storage.size()
		var prevBound:Bound = try Bound()
		var prevIndex:Int = 0
		var skip:Bool = false
		
		while (query.count != 0) {
			// Temporary output for this iteration
			var o:[UInt8] = []
			
	
			
			var currBound = try decodeBound(encoded: &query)
			let mode = try Mode(rawValue: Int(decodeVarInt(&query)))
			
			let lower = prevIndex
			var upper = storage.findLowerBound(begin: prevIndex, end: Int(storageSize), value: currBound)
			
			switch mode {
				case .skip:
					skip = true
				case .fingerprint:
					let theirFingerprint = try getBytes(&query, 16)
					let ourFingerprint = storage.fingerprint(begin: lower, end: upper)
					
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
						
						storage.iterate(begin: lower, end: upper, cb: { item, _ in
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
						
						storage.iterate(begin: lower, end: upper, cb: { item, index in
							if(exceededFrameSizeLimit(fullOutput.count + responseIds.count)) {
								endBound = Bound(item: item)
								upper = index
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
				let remainingFingerprint = storage.fingerprint(begin: upper, end: Int(storageSize))
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
	
	private mutating func splitRange(lower:Int, upper:Int, upperBound: inout Bound) throws -> [UInt8] {
		var ret:[UInt8] = []
		
		let numElements:Int = upper - lower
		let buckets = 16
		
		if(numElements < buckets * 2) {
			ret += encodeBound(upperBound)
			ret += encodeVarInt(Mode.idList.rawValue)
			
			ret += encodeVarInt(numElements)
			
			storage.iterate(begin: lower, end: upper, cb: { item, len in
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
				let ourFingerprint = storage.fingerprint(begin: curr, end: curr + bucketSize)
				curr += bucketSize
				
				var nextBound:Bound
				
				if(curr == upper) {
					nextBound = upperBound
				} else {
					var prevItem:Item = Item()
					var currItem:Item = Item()
					
					storage.iterate(begin: curr - 1, end: curr + 1, cb: { item, index in
						if(index == curr - 1) { prevItem = item }
						else { currItem = item }
					})
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
		ret += encodeTimestampOut(timestamp: b.item.timestamp)
		ret += encodeVarInt(b.idLen)
		b.item.id.RAW_access { ptr in
			ret += Array(UnsafeBufferPointer(start: ptr.baseAddress!, count: Int(b.idLen)))
		}
		return ret
	}
	
	private func getMinimalBound(prev:Item, curr:Item) throws -> Bound{
		if(curr.timestamp != prev.timestamp) {
			return try Bound(timestamp: curr.timestamp)
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
				return try Bound(timestamp: curr.timestamp, idSlice: Array(UnsafeBufferPointer(start: ptr.baseAddress!, count: sharedPrefixBytes + 1)))
			}
		}
	}
}
