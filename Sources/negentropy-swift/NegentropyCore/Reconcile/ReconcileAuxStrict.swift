import RAW
import RAW_blake2
import QuickLMDB
import NIO
import Logging

internal enum Mode:UInt8 {
	case skip = 0
	case fingerprint = 1
	case idList = 2
}

internal struct InternalFatalError:Swift.Error {}

extension NegentropyDatabaseStrict {
	private func doSkip(_ skip:inout Bool, _ prevBound:Bound<MDB_db_key_type>, returnBuffer:inout ByteBuffer) {
		if skip {
			skip = false
			write(bound: prevBound, writeBuffer: &returnBuffer)
			write(mode: .skip, writeBuffer: &returnBuffer)
		}
	}
	
}

extension NegentropyDatabaseStrict {
	internal func reconcileAux(isInitiator:Bool, buckets:Int, queryBuffer:inout ByteBuffer, returnBuffer: inout ByteBuffer, haveIDs:inout Set<MDB_db_key_type>, needIDs:inout Set<MDB_db_key_type>, cursor:consuming MDB_db_cursor_type, tx:borrowing Transaction) throws {
		guard buckets > 0 else {
			fatalError("fatal developer usage error in \(#function) - `buckets` must be greater than 0 - \(#file):\(#line)")
		}
		var prevBound = Bound(length:RAW_byte(RAW_native:UInt8(MemoryLayout<MDB_db_key_type>.size)).RAW_native(), identifier:MDB_db_key_type(RAW_staticbuff: MDB_db_key_type.RAW_staticbuff_zeroed()))
		var prevIndex = try cursor.opFirst(returning:(key:MDB_val, value:MDB_val).self).key
		var skip:Bool = false
		while queryBuffer.readableBytes > 0 {
			
			let dataLength = queryBuffer.readInteger(as:UInt8.self)!
			guard let readBytes = queryBuffer.readBytes(length:Int(dataLength)) else {
				throw InternalFatalError()
			}
			let curBound = Bound<MDB_db_key_type>(length:RAW_byte(RAW_native:dataLength).RAW_native(), identifier:MDB_db_key_type(RAW_staticbuff:readBytes))
			guard let modeByte = queryBuffer.readInteger(as:UInt8.self), let mode = Mode(rawValue:modeByte) else {
				throw InternalFatalError()
			}
			
			var lower = prevIndex
			
			
			_ = try curBound.identifier.MDB_access { (curBoundKey:consuming MDB_val) in
				var upper = try cursor.findLowerBound(begin:&prevIndex, value:&curBoundKey)
				
				switch mode {
					case .skip:
						skip = true
					case .fingerprint:
						guard let fingerprintBytes = queryBuffer.readBytes(length:MemoryLayout<Fingerprint>.size) else {
							throw InternalFatalError()
						}
						let theirFingerprint = Fingerprint(RAW_staticbuff:fingerprintBytes)
						let ourFingerprint = try cursor.fingerprint(begin:&lower, end:&upper)
						if theirFingerprint != ourFingerprint {
							doSkip(&skip, prevBound, returnBuffer: &returnBuffer)
							try splitRange(buckets: buckets, returnBuffer: &returnBuffer, lower: &lower, upper: &upper, upperBound: curBound, cursor: cursor)
						} else {
							skip = true
						}
					case .idList:
						guard let numIDs = queryBuffer.readInteger(endianness:.big, as:EncodedUInt64.RAW_native_type.self) else {
							throw InternalFatalError()
						}
						var theirIDs = Set<MDB_db_key_type>()
						for _ in 0..<numIDs {
							guard let idBytes = queryBuffer.readBytes(length:MemoryLayout<MDB_db_key_type>.size) else {
								throw InternalFatalError()
							}
							let id = MDB_db_key_type(RAW_staticbuff:idBytes)
							if isInitiator {
								theirIDs.insert(id)
							}
						}
						
						if isInitiator {
							skip = true
							try cursor.iterate(begin:&lower, end:&upper) { id in
								let key = MDB_db_key_type(RAW_staticbuff:id.pointee.mv_data)
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
							var responseIds = ByteBuffer()
							var idCount = 0
							doSkip(&skip, prevBound, returnBuffer: &returnBuffer)
							try cursor.iterate(begin:&lower, end:&upper) { id in
								idCount += 1
								write(identifier: id.pointee, writeBuffer: &responseIds)
								return true
							}
							
							write(bound: curBound, writeBuffer: &returnBuffer)
							write(mode: .idList, writeBuffer: &returnBuffer)
							write(numElements: idCount, writeBuffer: &returnBuffer)
							returnBuffer.writeBuffer(&responseIds)
						}
				}
				prevIndex = upper
				prevBound = curBound
			}
		}
	}
	
	internal func reconcileAuxZeroDB(isInitiator:Bool, buckets:Int, queryBuffer:inout ByteBuffer, returnBuffer: inout ByteBuffer, haveIDs:inout Set<MDB_db_key_type>, needIDs:inout Set<MDB_db_key_type>, cursor:consuming MDB_db_cursor_type, tx:borrowing Transaction) throws {
		guard buckets > 0 else {
			fatalError("fatal developer usage error in \(#function) - `buckets` must be greater than 0 - \(#file):\(#line)")
		}
		var prevBound = Bound(length:RAW_byte(RAW_native:UInt8(MemoryLayout<MDB_db_key_type>.size)).RAW_native(), identifier:MDB_db_key_type(RAW_staticbuff: MDB_db_key_type.RAW_staticbuff_zeroed()))
		var skip:Bool = false
		while queryBuffer.readableBytes > 0 {
			
			let dataLength = queryBuffer.readInteger(as:UInt8.self)!
			guard let readBytes = queryBuffer.readBytes(length:Int(dataLength)) else {
				throw InternalFatalError()
			}
			let curBound = Bound<MDB_db_key_type>(length:RAW_byte(RAW_native:dataLength).RAW_native(), identifier:MDB_db_key_type(RAW_staticbuff:readBytes))
			guard let modeByte = queryBuffer.readInteger(as:UInt8.self), let mode = Mode(rawValue:modeByte) else {
				throw InternalFatalError()
			}
				
			switch mode {
				case .skip:
					skip = true
				case .fingerprint:
					guard let fingerprintBytes = queryBuffer.readBytes(length:MemoryLayout<Fingerprint>.size) else {
						throw InternalFatalError()
					}
					let theirFingerprint = Fingerprint(RAW_staticbuff:fingerprintBytes)
					let ourFingerprint = Fingerprint(RAW_staticbuff: Fingerprint.RAW_staticbuff_zeroed())
					if theirFingerprint != ourFingerprint {
						doSkip(&skip, prevBound, returnBuffer: &returnBuffer)
						splitRangeZeroDB(returnBuffer: &returnBuffer, upperBound: curBound)
					} else {
						skip = true
					}
				case .idList:
					guard let numIDs = queryBuffer.readInteger(endianness:.big, as:EncodedUInt64.RAW_native_type.self) else {
						throw InternalFatalError()
					}
					var theirIDs = Set<MDB_db_key_type>()
					for _ in 0..<numIDs {
						guard let idBytes = queryBuffer.readBytes(length:MemoryLayout<MDB_db_key_type>.size) else {
							throw InternalFatalError()
						}
						let id = MDB_db_key_type(RAW_staticbuff:idBytes)
						if isInitiator {
							theirIDs.insert(id)
						}
					}
					
					if isInitiator {
						skip = true
						
						for id in theirIDs {
							needIDs.update(with: id)
						}
					} else {
						var responseIds = ByteBuffer()
						doSkip(&skip, prevBound, returnBuffer: &returnBuffer)
						
						write(bound: curBound, writeBuffer: &returnBuffer)
						write(mode: .idList, writeBuffer: &returnBuffer)
						write(numElements: 0, writeBuffer: &returnBuffer)
						returnBuffer.writeBuffer(&responseIds)
					}
			}
			prevBound = curBound
		}
	}
}

extension NegentropyDatabaseStrict{
	internal func splitRange(buckets:Int, returnBuffer: inout ByteBuffer, lower:UnsafePointer<MDB_val>, upper:UnsafePointer<MDB_val>?, upperBound:Bound<MDB_db_key_type>, cursor: MDB_db_cursor_type) throws {
		func getMinimalBound(prev:MDB_val, cur:MDB_val) -> Bound<MDB_db_key_type> {
			var sharedPrefixBytes:UInt8 = 0
			var returnKey = MDB_db_key_type.RAW_comparable_fixed_theoretical_min()
			returnKey.RAW_access_mutating { retKey in
				copyLoop: for i in 0..<min(cur.mv_size, prev.mv_size) {
					retKey[i] = cur.mv_data.assumingMemoryBound(to:UInt8.self)[i]
					sharedPrefixBytes += 1
					if cur.mv_data.assumingMemoryBound(to:UInt8.self)[i] != prev.mv_data.assumingMemoryBound(to:UInt8.self)[i] {
						break copyLoop
					}
				}
			}
			return Bound<MDB_db_key_type>(length:RAW_byte(RAW_native:sharedPrefixBytes).RAW_native(), identifier:returnKey)
		}
		
		let numElements:Int = (upper == nil) ? try cursor.countEntries(begin:lower) : try cursor.countEntries(begin:lower, end:upper!)
		if (numElements < buckets * 2) {
			// | Bound | idList (0x2) | numIds (i.e. 20) | ID1 | ID2 | ... | ID20 |
			write(bound: upperBound, writeBuffer: &returnBuffer)
			write(mode: .idList, writeBuffer: &returnBuffer)
			write(numElements: numElements, writeBuffer: &returnBuffer)
			if(upper == nil) {
				try cursor.iterate(begin:lower, { id in
					write(identifier: id.pointee, writeBuffer: &returnBuffer)
					return true
				})
			} else {
				try cursor.iterate(begin:lower, end:upper!, { id in
					write(identifier: id.pointee, writeBuffer: &returnBuffer)
					return true
				})
			}
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
				var bound:Bound<MDB_db_key_type> = upperBound
				if(i != buckets - 1) {
					let startNextBucket = try cursor.opNext(returning:(key:MDB_val, value:MDB_val).self).key
					bound = getMinimalBound(prev:endCurrBucket, cur:startNextBucket)
				} else {
					bound = upperBound
				}
				write(bound: bound, writeBuffer: &returnBuffer)
				write(mode: .fingerprint, writeBuffer: &returnBuffer)
				write(fingerprint: ourFingerprint, writeBuffer: &returnBuffer)
			}
		}
	}
	
	internal func splitRangeZeroDB(returnBuffer: inout ByteBuffer, upperBound:Bound<MDB_db_key_type>) {
		let numElements:Int = 0
		// | Bound | idList (0x2) | numIds (i.e. 20) | ID1 | ID2 | ... | ID20 |
		write(bound: upperBound, writeBuffer: &returnBuffer)
		write(mode: .idList, writeBuffer: &returnBuffer)
		write(numElements: numElements, writeBuffer: &returnBuffer)
	}
}

