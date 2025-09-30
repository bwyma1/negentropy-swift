import QuickLMDB
import Logging
import RAW

let MAX_U64: UInt64 = UInt64.max

@RAW_staticbuff(bytes:8)
@RAW_staticbuff_fixedwidthinteger_type<UInt64>(bigEndian:true)
internal struct EncodedUInt64:Sendable, ExpressibleByIntegerLiteral {}

struct Negentropy<DatabaseType> where DatabaseType:MDB_db_strict, DatabaseType.MDB_db_key_type: StorageID {
	
	typealias ID = DatabaseType.MDB_db_key_type
	
	private let buckets:Int
	private var storage: DatabaseType
	private let frameSizeLimit: UInt64
	
	private var isInitiator = false
	
	private let log:Logger
	
	init(storage: DatabaseType, frameSizeLimit: UInt64 = 0, buckets:Int = 16, logLevel:Logger.Level) throws {
		var buildLogger = Logger(label:"\(String(describing:Self.self))")
		buildLogger.logLevel = logLevel
		log = buildLogger
		
		if frameSizeLimit != 0 && frameSizeLimit < 4096 {
			throw NegentropyError.frameSizeTooSmall
		}
		self.buckets = buckets
		self.storage = storage
		self.frameSizeLimit = frameSizeLimit
	}
	
	public mutating func initiate() throws -> [UInt8] {
		guard !isInitiator else {
			throw NegentropyError.wrongInitiator
		}
		isInitiator = true
		
		var output:[UInt8] = try splitRange(lower: storage.first(), upper: nil, upperBound: getMaxBound())
		
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
	
	private mutating func doSkip(_ o: inout [UInt8], _ skip: inout Bool, _ prevBound:(bound:ID, len:Int)) {
		if skip {
			skip = false
			o += encodeBound(prevBound.bound, len: prevBound.len)
			o += [Mode.skip.rawValue]
		}
	}
	
	private mutating func reconcileAux(query: inout [UInt8], haveIds: inout [ID], needIds: inout [ID]) throws -> [UInt8] {
		log.debug("Reconciling Query", metadata: ["query": "\(query.count)"])
		var fullOutput:[UInt8] = []
		
		var prevBound = (ID(RAW_staticbuff: ID.RAW_staticbuff_zeroed()), MemoryLayout<ID>.size)
		var prevIndex:ID = try storage.first()
		var skip:Bool = false
		
		while (query.count != 0) {
			// Temporary output for this iteration
			var o:[UInt8] = []
			
			var currBound = try decodeBound(encoded: &query)
			let mode = try decodeMode(&query)
			
			// Lower and upper in terms of our storage
			let lower = prevIndex
			var upper = try storage.findLowerBound(begin: prevIndex, end: nil, value: currBound.bound)
			
			switch mode {
				case .skip:
					skip = true
				case .fingerprint:
					let theirFingerprint = try decodeFingerprint(&query)
					let ourFingerprint = try storage.fingerprint(begin: lower, end: upper)
					
					try ourFingerprint.RAW_access { ptr in
						if(theirFingerprint != Array(UnsafeBufferPointer(start: ptr.baseAddress!, count: ptr.count))) {
							doSkip(&o, &skip, prevBound)
							o += try splitRange(lower: lower, upper: upper, upperBound: currBound)
						} else {
							skip = true
						}
					}
				case .idList:
					let numIds = try decodeNumElements(&query)
					
					var theirElems:[ID] = []
					for _ in 0..<numIds {
						let id = try decodeID(&query)
						if(isInitiator) { theirElems.append(id) }
					}
					
					if(isInitiator) {
						skip = true
						
						try storage.iterate(begin: lower, end: upper, cb: { id in
							if let index = theirElems.firstIndex(of: id) {
								// ID exists on both sides
								theirElems.remove(at: index)
							} else {
								// ID exists on our side, but not their side
								haveIds.append(id)
							}
							return true
						})
						
						for id in theirElems {
							needIds.append(id)
						}
					} else {
						doSkip(&o, &skip, prevBound)
						
						var responseIds:[UInt8] = []
						var numResponseIds = 0
						
						var endBound = currBound
						
						try storage.iterate(begin: lower, end: upper, cb: { id in
							if(exceededFrameSizeLimit(fullOutput.count + responseIds.count)) {
								endBound = (id, MemoryLayout<ID>.size)
								upper = id
								return false
							}
							
							responseIds += id.RAW_access { ptr in
								return Array(UnsafeBufferPointer(start: ptr.baseAddress!, count: MemoryLayout<ID>.size))
							}
							
							numResponseIds += 1
							return true
						})
						
						log.debug("Encoded response id's", metadata: ["count": "\(numResponseIds)"])
						
						o += encodeBound(endBound.bound, len: endBound.len)
						o += [Mode.idList.rawValue]
						o += encodeNumElements(numResponseIds)
						o += responseIds
						
						fullOutput += o
						o = []
					}
				default:
					throw NegentropyError.unexpectedMode
			}
			
			if(exceededFrameSizeLimit(fullOutput.count + o.count)) {
				let remainingFingerprint = try storage.fingerprint(begin: upper, end: nil)
				let maxBound = getMaxBound()
				
				fullOutput += encodeBound(maxBound.bound, len: maxBound.len)
				fullOutput += [Mode.fingerprint.rawValue]
				remainingFingerprint.RAW_access ({ ptr in
					fullOutput += Array(UnsafeBufferPointer(start: ptr.baseAddress!, count: ptr.count))
				})
				break
			} else {
				fullOutput += o
			}
			
			guard let nextUpper = upper else {
				break
			}
			prevIndex = nextUpper
			prevBound = currBound
		}

		log.debug("Reconcile finished", metadata: ["Number Have IDs": "\(haveIds.count)", "Number Need IDs": "\(needIds.count)", "bytes": "\(fullOutput.count)"])
		return fullOutput
	}
	
	private func exceededFrameSizeLimit(_ size:Int) -> Bool {
		return frameSizeLimit != 0 && size > frameSizeLimit - 200
	}
	
	private mutating func splitRange(lower:ID, upper:ID?, upperBound: (bound:ID, len:Int)) throws -> [UInt8] {
		var ret:[UInt8] = []
		
		let numElements:Int = try storage.numElements(begin: lower, end: upper)
		
		if(numElements < buckets * 2) {
			// | Bound | idList (2) | numIds (i.e. 20) | ID1 | ID2 | ... | ID20 |
			
			ret += encodeBound(upperBound.bound, len: upperBound.len)
			ret += [Mode.idList.rawValue]
			ret += encodeNumElements(numElements)
			
			try storage.iterate(begin: lower, end: upper, cb: { id in
				id.RAW_access({ptr in
					ret += Array(UnsafeBufferPointer(start: ptr.baseAddress!, count: ptr.count))
				})
				return true
			})
		} else {
			let idsPerBucket:Int = numElements / buckets
			let bucketsWithExtra = numElements % buckets
			var curr:ID = lower
			
			// For each bucket
			// | Bound (last id this bucket, next bucket first id) | fingerprintMode (1) | Fingerprint |
			for i in 0..<buckets {
				let bucketSize = idsPerBucket + (i < bucketsWithExtra ? 1 : 0)
				
				// Shifted is first id in NEXT bucket
				let shifted = try storage.shift(curr: curr, amount: bucketSize)
				let ourFingerprint = try storage.fingerprint(begin: curr, end: shifted)
				
				var nextBound:(bound:ID, len:Int)
				
				if(shifted == upper) {
					nextBound = upperBound
				} else {
					let startNextBucket = shifted!
					let endCurrBucket = try storage.prev(curr: startNextBucket)
					
					nextBound = try getMinimalBound(prev: endCurrBucket, curr: startNextBucket)
				}
				
				if(shifted != nil){
					curr = shifted!
				}
				
				ret += encodeBound(nextBound.bound, len: nextBound.len)
				ret += [Mode.fingerprint.rawValue]
				ourFingerprint.RAW_access( { ptr in
					ret += Array(UnsafeBufferPointer(start: ptr.baseAddress!, count: FINGERPRINT_SIZE))
				})
			}
		}
		return ret
	}
	
	// Returns the first 'x' sliced bytes that make prev and curr unique from each other
	private func getMinimalBound(prev:ID, curr:ID) throws -> (ID, Int) {
		var sharedPrefixBytes:Int = 0
		let currKey = curr
		let prevKey = prev
		
		currKey.RAW_access { ptr in
			prevKey.RAW_access { ptr2 in
				for i in 0..<ID_SIZE {
					sharedPrefixBytes += 1
					if(ptr[i] != ptr2[i]) {
						break
					}
				}
			}
		}
		
		return currKey.RAW_access { ptr in
			let idArray = Array(ptr.prefix(sharedPrefixBytes))
			return idArray.withUnsafeBufferPointer { arrPtr in
				return (ID(RAW_staticbuff: arrPtr.baseAddress!), sharedPrefixBytes)
			}
		}
	}
	
	// Returns the maximum bound (special bound)
	private func getMaxBound() -> (bound:ID, len:Int) {
		var maxID:[UInt8] = Array(repeating: 255, count: MemoryLayout<ID>.size)
		let id = maxID.withUnsafeBufferPointer { ptr in
			return ID(RAW_accessed: ptr)!
		}
		return (id, MemoryLayout<ID>.size)
	}
}

// ---------------- Encode Functions ----------------
extension Negentropy {
	func encodeBound(_ b:ID, len:Int) -> [UInt8] {
		var ret:[UInt8] = []
		ret += [UInt8(len)]
		ret += b.RAW_access { ptr in
			return Array(UnsafeBufferPointer(start: ptr.baseAddress!, count: len))
		}
		return ret
	}
	
	func encodeNumElements(_ numElements:Int) -> [UInt8] {
		// Use static buff for endianness
		let encodedNumElements = EncodedUInt64(RAW_native:UInt64(numElements))
		return encodedNumElements.RAW_access { ptr in
			return Array(UnsafeBufferPointer(start: ptr.baseAddress!, count: ptr.count))
		}
	}
}

// ---------------- Decode Functions ----------------
extension Negentropy {
	func decodeBound(encoded: inout [UInt8]) throws -> (bound:ID, len:Int) {
		guard !encoded.isEmpty else { throw NegentropyError.parseEndsPrematurely }
		
		let len = Int(encoded[encoded.startIndex])
		guard encoded.count >= len else { throw NegentropyError.parseEndsPrematurely }
		encoded.removeFirst(1)
		let idArray = Array(encoded.prefix(len)) + Array(repeating: 0, count: ID_SIZE - len)
		encoded.removeFirst(len)

		return idArray.withUnsafeBufferPointer { ptr in
			return (ID(RAW_staticbuff: ptr.baseAddress!), len)
		}
	}
	
	func decodeNumElements(_ encoded: inout [UInt8]) throws -> Int {
		guard encoded.count >= 8 else { throw NegentropyError.parseEndsPrematurely }
		// Extract int
		let value = encoded.RAW_access {
			return EncodedUInt64(RAW_staticbuff:$0.baseAddress!).RAW_native()
		}
		encoded.removeFirst(8)
		return Int(value)
	}
	
	func decodeMode(_ encoded: inout [UInt8]) throws -> Mode {
		guard encoded.count >= 1 else { throw NegentropyError.parseEndsPrematurely }
		
		let ret:Mode = Mode(rawValue: encoded[encoded.startIndex])!
		encoded.removeFirst(1)
		return ret
	}
	
	func decodeFingerprint(_ encoded: inout [UInt8]) throws -> [UInt8] {
		guard encoded.count >= FINGERPRINT_SIZE else { throw NegentropyError.parseEndsPrematurely }

		let slice = encoded.prefix(FINGERPRINT_SIZE)
		encoded.removeFirst(FINGERPRINT_SIZE)

		return Array(slice)
	}
	
	func decodeID(_ encoded: inout [UInt8]) throws -> ID {
		guard encoded.count >= ID_SIZE else { throw NegentropyError.parseEndsPrematurely }
		
		defer {
			encoded.removeFirst(ID_SIZE)
		}
		return encoded.withUnsafeBufferPointer { ptr in
			return ID(RAW_staticbuff: ptr.baseAddress!)
		}
	}
}
