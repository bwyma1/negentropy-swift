import QuickLMDB
import Logging
import RAW

enum MessageType:UInt8 {
	case initiator = 0
	case responder = 1
}

public struct Negentropy<DatabaseType> where DatabaseType:MDB_db_strict, DatabaseType.MDB_db_key_type: StorageID {
	public typealias ID = DatabaseType.MDB_db_key_type
	
	private let buckets:Int
	private var storage: DatabaseType
	private let frameSizeLimit: UInt64
	
	private var isInitiator = false
	
	private let log:Logger
	
	public init(storage:DatabaseType, frameSizeLimit:UInt64 = 0, buckets:Int = 16, logLevel:Logger.Level) throws {
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
}

	public mutating func initiate() throws -> [UInt8] {
		guard !isInitiator else {
			throw NegentropyError.wrongInitiator
		}
		isInitiator = true
		
		var output:[UInt8] = try splitRange(lower: storage.first(), upper: nil, upperBound: getMaxBound())
		encodeHeader(type: .responder, data: &output)
		return output
	}
	
// 	public mutating func setInitiator() {
// 		isInitiator = true
// 	}
	
	// public func reconcile(query: consuming [UInt8]) throws -> [UInt8] {
	// 	guard !isInitiator else {
	// 		throw NegentropyError.wrongInitiator
	// 	}
	// 	guard query.count > 0 else {
	// 		throw NegentropyError.expectedResponderMessage
	// 	}
	// 	var verifiedQuery = try query.withUnsafeBytes { ptr in
	// 		guard let negData = NegentropyData(RAW_decode: ptr.baseAddress!, count: ptr.count) else {
	// 			throw NegentropyError.expectedResponderMessage
	// 		}
	// 		let negType = negData.type.RAW_access{ ptr in
	// 			return MessageType(rawValue: ptr.first!)
	// 		}
	// 		guard negType == .responder else {
	// 			throw NegentropyError.expectedResponderMessage
	// 		}
			
	// 		return negData.data
	// 	}
	// 	var haveIds:[ID] = []
	// 	var needIds:[ID] = []
	// 	var retData = try reconcileAux(query: &verifiedQuery, haveIds: &haveIds, needIds: &needIds)
	// 	encodeHeader(type: .initiator, data: &retData)
	// 	return retData
	// }
	

	// public mutating func reconcile(query: consuming [UInt8], haveIds: inout [ID], needIds: inout [ID]) throws -> [UInt8]? {
	// 	guard isInitiator else {
	// 		throw NegentropyError.wrongInitiator
	// 	}
	// 	guard query.count > 0 else {
	// 		throw NegentropyError.expectedInitiatorMessage
	// 	}
	// 	var verifiedQuery = try query.withUnsafeBytes { ptr in
	// 		guard let negData = NegentropyData(RAW_decode: ptr.baseAddress!, count: ptr.count) else {
	// 			throw NegentropyError.expectedInitiatorMessage
	// 		}
	// 		let negType = negData.type.RAW_access { ptr in
	// 			return MessageType(rawValue:ptr.first!)
	// 		}
	// 		guard negType == .initiator else {
	// 			throw NegentropyError.expectedInitiatorMessage
	// 		}
			
	// 		return negData.data
	// 	}
	// 	var output = try reconcileAux(query: &verifiedQuery, haveIds: &haveIds, needIds: &needIds)
	// 	if output.count == 0 {
	// 		return nil
	// 	}
	// 	encodeHeader(type: .responder, data: &output)
	// 	return output
	// }


	private func doSkip(_ o:inout [SplitRangeResult], _ skip: inout Bool, _ prevBound:(bound:ID, len:Int)) {
		if skip {
			skip = false
			o += encodeBound(prevBound.bound, len: prevBound.len)
			o += [Mode.skip.rawValue]
		}
	}
	
	// private mutating func reconcileAux(query: inout [UInt8], haveIds: inout [ID], needIds: inout [ID]) throws -> [UInt8] {
	// 	log.debug("Reconciling Query", metadata: ["query": "\(query.count)"])
	// 	var fullOutput:[UInt8] = []
		
	// 	var prevBound = (ID(RAW_staticbuff: ID.RAW_staticbuff_zeroed()), MemoryLayout<ID>.size)
	// 	var prevIndex:ID? = try storage.first()
	// 	var skip:Bool = false
		
	// 	while (query.count != 0) {
	// 		// Temporary output for this iteration
	// 		var o:[UInt8] = []
			
	// 		let currBound = try decodeBound(encoded: &query)
	// 		let mode = try decodeMode(&query)
			
	// 		// Lower and upper in terms of our storage
	// 		let lower = prevIndex
	// 		var upper = try storage.findLowerBound(begin: prevIndex, end: nil, value: currBound.bound)
			
	// 		switch mode {
	// 			case .skip:
	// 				skip = true
	// 			case .fingerprint:
	// 				let theirFingerprint = try decodeFingerprint(&query)
	// 				let ourFingerprint = try storage.fingerprint(begin: lower, end: upper)
					
	// 				try ourFingerprint.RAW_access { ptr in
	// 					if(theirFingerprint != Array(UnsafeBufferPointer(start: ptr.baseAddress!, count: ptr.count))) {
	// 						doSkip(&o, &skip, prevBound)
	// 						o += try splitRange(lower: lower, upper: upper, upperBound: currBound)
	// 					} else {
	// 						skip = true
	// 					}
	// 				}
	// 			case .idList:
	// 				let numIds = try decodeNumElements(&query)
					
	// 				var theirSet = Set<ID>()
	// 				for _ in 0..<numIds {
	// 					let id = try decodeID(&query)
	// 					if(isInitiator) { theirSet.insert(id) }
	// 				}
					
	// 				if(isInitiator) {
	// 					skip = true
						
	// 					try storage.iterate(begin: lower, end: upper, cb: { id in
	// 						if theirSet.contains(id){
	// 							// ID exists on both sides
	// 							theirSet.remove(id)
	// 						} else {
	// 							// ID exists on our side, but not their side
	// 							haveIds.append(id)
	// 						}
	// 						return true
	// 					})
						
	// 					for id in theirSet {
	// 						needIds.append(id)
	// 					}
	// 				} else {
	// 					doSkip(&o, &skip, prevBound)
						
	// 					var responseIds:[UInt8] = []
	// 					var numResponseIds = 0
						
	// 					var endBound = currBound
						
	// 					try storage.iterate(begin: lower, end: upper, cb: { id in
	// 						if(exceededFrameSizeLimit(fullOutput.count + responseIds.count)) {
	// 							endBound = (id, MemoryLayout<ID>.size)
	// 							upper = id
	// 							return false
	// 						}
							
	// 						responseIds += id.RAW_access { ptr in
	// 							return Array(UnsafeBufferPointer(start: ptr.baseAddress!, count: MemoryLayout<ID>.size))
	// 						}
							
	// 						numResponseIds += 1
	// 						return true
	// 					})
						
	// 					log.debug("Encoded response id's", metadata: ["count": "\(numResponseIds)"])
						
	// 					o += encodeBound(endBound.bound, len: endBound.len)
	// 					o += [Mode.idList.rawValue]
	// 					o += encodeNumElements(numResponseIds)
	// 					o += responseIds
						
	// 					fullOutput += o
	// 					o = []
	// 				}
	// 			default:
	// 				throw NegentropyError.unexpectedMode
	// 		}
			
	// 		if(exceededFrameSizeLimit(fullOutput.count + o.count)) {
	// 			let remainingFingerprint = try storage.fingerprint(begin: upper, end: nil)
	// 			let maxBound = getMaxBound()
				
	// 			fullOutput += encodeBound(maxBound.bound, len: maxBound.len)
	// 			fullOutput += [Mode.fingerprint.rawValue]
	// 			remainingFingerprint.RAW_access ({ ptr in
	// 				fullOutput += Array(UnsafeBufferPointer(start: ptr.baseAddress!, count: ptr.count))
	// 			})
	// 			break
	// 		} else {
	// 			fullOutput += o
	// 		}
			
	// 		prevIndex = upper
	// 		prevBound = currBound
	// 	}

	// 	log.debug("Reconcile finished", metadata: ["Number Have IDs": "\(haveIds.count)", "Number Need IDs": "\(needIds.count)", "bytes": "\(fullOutput.count)"])
	// 	return fullOutput
	// }

	
// 	// Returns the first 'x' bytes that make prev and curr common.
	
// }

// // ---------------- Encode Functions ----------------
// extension Negentropy {
// 	private func encodeBound(_ b:ID, len:Int) -> [UInt8] {
// 		var ret:[UInt8] = []
// 		ret += [UInt8(len)]
// 		ret += b.RAW_access { ptr in
// 			return Array(UnsafeBufferPointer(start: ptr.baseAddress!, count: len))
// 		}
// 		return ret
// 	}
	
// 	private func encodeNumElements(_ numElements:Int) -> [UInt8] {
// 		// Use static buff for endianness
// 		let encodedNumElements = EncodedUInt64(RAW_native:UInt64(numElements))
// 		return encodedNumElements.RAW_access { ptr in
// 			return Array(UnsafeBufferPointer(start: ptr.baseAddress!, count: ptr.count))
// 		}
// 	}
// }

// // ---------------- Decode Functions ----------------
// extension Negentropy {
// 	private func decodeBound(encoded: inout [UInt8]) throws -> (bound:ID, len:Int) {
// 		guard !encoded.isEmpty else { throw NegentropyError.parseEndsPrematurely }
		
// 		let len = Int(encoded[encoded.startIndex])
// 		guard encoded.count >= len else { throw NegentropyError.parseEndsPrematurely }
// 		encoded.removeFirst(1)
// 		let idArray = Array(encoded.prefix(len)) + Array(repeating: 0, count: MemoryLayout<ID>.size - len)
// 		encoded.removeFirst(len)

// 		return idArray.withUnsafeBufferPointer { ptr in
// 			return (ID(RAW_staticbuff: ptr.baseAddress!), len)
// 		}
// 	}
	
// 	private func decodeNumElements(_ encoded: inout [UInt8]) throws -> Int {
// 		guard encoded.count >= 8 else { throw NegentropyError.parseEndsPrematurely }
// 		// Extract int
// 		let value = encoded.RAW_access {
// 			return EncodedUInt64(RAW_staticbuff:$0.baseAddress!).RAW_native()
// 		}
// 		encoded.removeFirst(8)
// 		return Int(value)
// 	}
	
// 	private func decodeMode(_ encoded: inout [UInt8]) throws -> Mode {
// 		guard encoded.count >= 1 else { throw NegentropyError.parseEndsPrematurely }
		
// 		let ret:Mode = Mode(rawValue: encoded[encoded.startIndex])!
// 		encoded.removeFirst(1)
// 		return ret
// 	}
	
// 	private func decodeFingerprint(_ encoded: inout [UInt8]) throws -> [UInt8] {
// 		guard encoded.count >= FINGERPRINT_SIZE else { throw NegentropyError.parseEndsPrematurely }

// 		let slice = encoded.prefix(FINGERPRINT_SIZE)
// 		encoded.removeFirst(FINGERPRINT_SIZE)

// 		return Array(slice)
// 	}
	
// 	private func decodeID(_ encoded: inout [UInt8]) throws -> ID {
// 		guard encoded.count >= MemoryLayout<ID>.size else { throw NegentropyError.parseEndsPrematurely }
		
// 		defer {
// 			encoded.removeFirst(MemoryLayout<ID>.size)
// 		}
// 		return encoded.withUnsafeBufferPointer { ptr in
// 			return ID(RAW_staticbuff: ptr.baseAddress!)
// 		}
// 	}
// }

// Negentropy packet headers
// Type 0 - Initiator Message
// Type 1 - Responder Message

// extension Negentropy {
// 	func encodeHeader(type:MessageType, data:inout [UInt8]) {
// 		let negData = NegentropyData(type: type, data: data)
// 		data = [UInt8](repeating: 0, count: data.count + 5)
// 		_ = data.withUnsafeMutableBytes { ptr in
// 			negData.RAW_encode(dest: ptr.baseAddress!.assumingMemoryBound(to: UInt8.self))
// 		}
// 	}
// }
