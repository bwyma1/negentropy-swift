import RAW
import RAW_blake2
import QuickLMDB
import NIO
import Logging

enum Mode:UInt8 {
	case skip = 0
	case fingerprint = 1
	case idList = 2
}

enum IO<BoundIdentifierType:RAW_staticbuff> {
	enum IdentifierBacking {
		case rawBytes(UnsafeRawBufferPointer)
		case identifier(BoundIdentifierType)
	}
	case bound(Bound<BoundIdentifierType>)
	case numberOfElements(Int)
	case fingerprint(Fingerprint)
	case id(IdentifierBacking)
	case mode(Mode)
}
struct InternalFatalError:Swift.Error {}



extension MDB_db_strict where Self.MDB_db_key_type:DatabaseIndexVector {
	private func doSkip(channel:Channel, _ skip:inout Bool, _ prevBound:Bound<MDB_db_key_type>) {
		if skip {
			skip = false
			o.append(.bound(prevBound))
			o.append(.mode(.skip))
		}
	}
	
}

extension MDB_cursor_strict where Self.MDB_cursor_dbtype.MDB_db_key_type:DatabaseIndexVector {
	private borrowing func reconcileAux(channel:Channel, isInitiator:Bool, buckets:Int, queryBuffer:inout ByteBuffer, haveIDs:inout Set<MDB_cursor_dbtype.MDB_db_key_type>, needIDs:inout Set<MDB_cursor_dbtype.MDB_db_key_type>, tx:borrowing Transaction) throws {
		guard buckets > 0 else {
			fatalError("fatal developer usage error in \(#function) - `buckets` must be greater than 0 - \(#file):\(#line)")
		}
		var returnValues = [IO<MDB_cursor_dbtype.MDB_db_key_type>]()
		var prevBound = Bound(length:RAW_byte(RAW_native:UInt8(MemoryLayout<MDB_cursor_dbtype.MDB_db_key_type>.size)), identifier:MDB_cursor_dbtype.MDB_db_key_type(RAW_staticbuff: MDB_cursor_dbtype.MDB_db_key_type.RAW_staticbuff_zeroed()))
		var prevIndex = try opFirst(returning:(key:MDB_val, value:MDB_val).self).key
		var skip:Bool = false
		while queryBuffer.readableBytes > 0 {
			// read the length of the bound key
			let dataLength = queryBuffer.readInteger(as:UInt8.self)!
			guard let readBytes = queryBuffer.readBytes(length:Int(dataLength)) else {
				throw InternalFatalError()
			}
			// read the bound key based on the length
			let curBound = Bound<MDB_cursor_dbtype.MDB_db_key_type>(length:RAW_byte(RAW_native:dataLength), identifier:MDB_cursor_dbtype.MDB_db_key_type(RAW_staticbuff:readBytes))
			guard let modeByte = queryBuffer.readInteger(as:UInt8.self), let mode = Mode(rawValue:modeByte) else {
				throw InternalFatalError()
			}
			var lower = prevIndex
			var upper = try curBound.identifier.MDB_access { (curBoundKey:consuming MDB_val) in
				return try findLowerBound(begin:&prevIndex, value:&curBoundKey)
			}
			switch mode {
				case .skip:
					skip = true
				case .fingerprint:
					guard let fingerprintBytes = queryBuffer.readBytes(length:MemoryLayout<Fingerprint>.size) else {
						throw InternalFatalError()
					}
					let theirFingerprint = Fingerprint(RAW_staticbuff:fingerprintBytes)
					let ourFingerprint = try fingerprint(begin:&lower, end:&upper)
					if theirFingerprint != ourFingerprint {
						doSkip(&returnValues, &skip, prevBound)
						returnValues.append(contentsOf:try splitRange(buckets:buckets, lower:&lower, upper:&upper, upperBound:curBound, tx:tx))
					} else {
						skip = true
					}
				case .idList:
					guard let numIDs = queryBuffer.readInteger(endianness:.big, as:EncodedUInt64.RAW_native_type.self) else {
						throw InternalFatalError()
					}
					var theirIDs = Set<MDB_cursor_dbtype.MDB_db_key_type>()
					for _ in 0..<numIDs {
						guard let idBytes = queryBuffer.readBytes(length:MemoryLayout<MDB_cursor_dbtype.MDB_db_key_type>.size) else {
							throw InternalFatalError()
						}
						let id = MDB_cursor_dbtype.MDB_db_key_type(RAW_staticbuff:idBytes)
						if isInitiator {
							theirIDs.insert(id)
						}
					}

					if isInitiator {
						skip = true
						try iterate(begin:&lower, end:&upper) { id in
							let key = MDB_cursor_dbtype.MDB_db_key_type(RAW_staticbuff:id.pointee.mv_data)
							if theirIDs.contains(key) {
								theirIDs.remove(key)
							} else {
								haveIDs.update(with:key)
							}
							return true
						}
						
						for id in theirIDs {
							needIDs.update(with: id)
						}
					} else {
						doSkip(&returnValues, &skip, prevBound)
						var responseIds:[IO<MDB_cursor_dbtype.MDB_db_key_type>] = []
						try iterate(begin:&lower, end:&upper) { id in
							let key = MDB_cursor_dbtype.MDB_db_key_type(RAW_staticbuff:id.pointee.mv_data)
							responseIds.append(.id(.identifier(key)))
							return true
						}

						returnValues.append(.bound(curBound))
						returnValues.append(.mode(.idList))
						returnValues.append(.numberOfElements(responseIds.count))
						returnValues.append(contentsOf: responseIds)
					}
			}
			prevIndex = upper
			prevBound = curBound
		}
	}
}

extension MDB_db_strict where Self.MDB_db_key_type:DatabaseIndexVector {
	private func splitRange(channel:Channel, buckets:Int, lower:UnsafePointer<MDB_val>, upper:UnsafePointer<MDB_val>, upperBound:Bound<MDB_db_key_type>, tx:borrowing Transaction) throws -> [IO<MDB_db_key_type>] {
		func getMinimalBound(prev:MDB_val, cur:MDB_val) -> Bound<MDB_db_key_type> {
			var sharedPrefixBytes:UInt8 = 0
			var returnKey = MDB_db_key_type.RAW_comparable_fixed_theoretical_min()
			returnKey.RAW_access_mutating { retKey in
				copyLoop: for i in 0..<min(cur.mv_size, prev.mv_size) {
					if cur.mv_data.assumingMemoryBound(to:UInt8.self)[i] == prev.mv_data.assumingMemoryBound(to:UInt8.self)[i] {
						retKey[i] = cur.mv_data.assumingMemoryBound(to:UInt8.self)[i]
						sharedPrefixBytes += 1
					} else {
						break copyLoop
					}
				}
			}
			return Bound<MDB_db_key_type>(length:RAW_byte(RAW_native:sharedPrefixBytes), identifier:returnKey)
		}
		
		var ret:[IO<MDB_db_key_type>] = []
		try cursor(tx:tx) { cursor in
			let numElements:Int = try cursor.countEntries(begin:lower, end:upper)
			if (numElements < buckets * 2) {
				// | Bound | idList (0x2) | numIds (i.e. 20) | ID1 | ID2 | ... | ID20 |
				ret.append(.bound(upperBound))
				ret.append(.mode(.idList))
				ret.append(.numberOfElements(numElements))
				try cursor.iterate(begin:lower, end:upper, { id in
					ret.append(.id(.rawBytes(UnsafeRawBufferPointer(start:id.pointee.mv_data, count:id.pointee.mv_size))))
					return true
				})
			} else {
				let idsPerBucket:Int = numElements / buckets
				let bucketsWithExtra = numElements % buckets
				var cur = try cursor.opSetRange(returning:(key:MDB_val, value:MDB_val).self, key:lower.pointee).key
				// For each bucket
				// | Bound (last id this bucket, next bucket first id) | fingerprintMode (1) | Fingerprint |
				for i in 0..<buckets {
					let bucketSize = idsPerBucket + (i < bucketsWithExtra ? 1 : 0)
					let ourFingerprint = try cursor.fingerprintShift(begin:&cur, bucketSize:bucketSize)
					let endCurrBucket = try cursor.opGetCurrent(returning:(key:MDB_val, value:MDB_val).self).key
					let startNextBucket = try cursor.opNext(returning:(key:MDB_val, value:MDB_val).self).key
					ret.append(.bound(getMinimalBound(prev:endCurrBucket, cur:startNextBucket)))
					ret.append(.mode(.fingerprint))
					ret.append(.fingerprint(ourFingerprint))
				}
			}
		}
		return ret
	}
}

