import RAW
import RAW_blake2
import QuickLMDB
import NIO
import Logging

// See ReconcileAuxStrict for documentation

extension NegentropyDatabase {
	private func doSkip(_ skip:inout Bool, _ prevBound:MDB_val, returnBuffer:inout ByteBuffer) {
		if skip {
			skip = false
			write(val:prevBound, writeBuffer: &returnBuffer)
			write(mode: .skip, writeBuffer: &returnBuffer)
		}
	}
	
}

extension NegentropyDatabase {
	internal func reconcileAux(isInitiator:Bool, buckets:Int, queryBuffer:inout ByteBuffer, returnBuffer: inout ByteBuffer, haveIDs:inout Set<ByteBuffer>, needIDs:inout Set<ByteBuffer>, cursor:consuming MDB_db_cursor_type, tx:borrowing Transaction) throws {
		guard buckets > 0 else {
			fatalError("fatal developer usage error in \(#function) - `buckets` must be greater than 0 - \(#file):\(#line)")
		}
		
		let zeroPtr = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
		zeroPtr.storeBytes(of: UInt8(0), as: UInt8.self)
		defer { zeroPtr.deallocate() }
		var prevBound = MDB_val(mv_size: 1, mv_data: zeroPtr)
		
		var prevIndex = try cursor.opFirst(returning:(key:MDB_val, value:MDB_val).self).key
		var skip:Bool = false
		
		while queryBuffer.readableBytes > 0 {
			
			let dataLength = queryBuffer.readInteger(as:UInt8.self)!
			guard var readBytes = queryBuffer.readBytes(length:Int(dataLength)) else {
				throw InternalFatalError()
			}
			var curBound = readBytes.withUnsafeMutableBytes { ptr in
				return MDB_val(mv_size: ptr.count, mv_data: ptr.baseAddress!)
			}
			
			guard let modeByte = queryBuffer.readInteger(as:UInt8.self), let mode = Mode(rawValue:modeByte) else {
				throw InternalFatalError()
			}
			
			var lower = prevIndex
			
			var upper = try cursor.findLowerBound(begin: &prevIndex, value: &curBound)
			
			switch mode {
				case .skip:
					skip = true
				case .fingerprint:
					guard let fingerprintBytes = queryBuffer.readBytes(length:MemoryLayout<Fingerprint>.size) else {
						throw InternalFatalError()
					}
					let theirFingerprint = fingerprintBytes.withUnsafeBytes { Fingerprint(RAW_decode:$0)! }
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
					var theirIDs = Set<ByteBuffer>()
					for _ in 0..<numIDs {
						guard let idLength = queryBuffer.readInteger(as:UInt8.self) else {
							throw InternalFatalError()
						}
						guard let idBuffer = queryBuffer.readSlice(length:Int(idLength)) else {
							throw InternalFatalError()
						}
						
						if isInitiator {
							theirIDs.insert(idBuffer)
						}
					}
					
					if isInitiator {
						skip = true
						try cursor.iterate(begin:&lower, end:&upper) { id in
							let idBuffer = ByteBufferAllocator().buffer(
								bytes: UnsafeBufferPointer(
									start: id.pointee.mv_data.assumingMemoryBound(to: UInt8.self),
									count: id.pointee.mv_size
								)
							)
							if theirIDs.contains(idBuffer) {
								theirIDs.remove(idBuffer)
							} else {
								haveIDs.update(with:idBuffer)
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
							write(val: id.pointee, writeBuffer: &responseIds)
							return true
						}
						
						write(val: curBound, writeBuffer: &returnBuffer)
						write(mode: .idList, writeBuffer: &returnBuffer)
						write(numElements: idCount, writeBuffer: &returnBuffer)
						returnBuffer.writeBuffer(&responseIds)
					}
			}
			prevIndex = upper
			prevBound = curBound
		}
	}
	
	internal func reconcileAuxZeroDB(isInitiator:Bool, buckets:Int, queryBuffer:inout ByteBuffer, returnBuffer: inout ByteBuffer, haveIDs:inout Set<ByteBuffer>, needIDs:inout Set<ByteBuffer>, cursor:consuming MDB_db_cursor_type, tx:borrowing Transaction) throws {
		guard buckets > 0 else {
			fatalError("fatal developer usage error in \(#function) - `buckets` must be greater than 0 - \(#file):\(#line)")
		}
		let zeroPtr = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
		zeroPtr.storeBytes(of: UInt8(0), as: UInt8.self)
		defer { zeroPtr.deallocate() }
		var prevBound = MDB_val(mv_size: 1, mv_data: zeroPtr)
		
		var skip:Bool = false
		
		while queryBuffer.readableBytes > 0 {
			
			let dataLength = queryBuffer.readInteger(as:UInt8.self)!
			guard var readBytes = queryBuffer.readBytes(length:Int(dataLength)) else {
				throw InternalFatalError()
			}
			let curBound = readBytes.withUnsafeMutableBytes { ptr in
				return MDB_val(mv_size: ptr.count, mv_data: ptr.baseAddress!)
			}
			
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
					let theirFingerprint = fingerprintBytes.withUnsafeBytes { Fingerprint(RAW_decode:$0)! }
					let ourFingerprint = zeroedFingerprint()
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
					var theirIDs = Set<ByteBuffer>()
					for _ in 0..<numIDs {
						guard let idLength = queryBuffer.readInteger(as:UInt8.self) else {
							throw InternalFatalError()
						}
						guard let idBuffer = queryBuffer.readSlice(length:Int(idLength)) else {
							throw InternalFatalError()
						}
						if isInitiator {
							theirIDs.insert(idBuffer)
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
						
						write(val: curBound, writeBuffer: &returnBuffer)
						write(mode: .idList, writeBuffer: &returnBuffer)
						write(numElements: 0, writeBuffer: &returnBuffer)
						returnBuffer.writeBuffer(&responseIds)
					}
			}
			prevBound = curBound
		}
	}
}

extension NegentropyDatabase {
	internal func splitRange(buckets:Int, returnBuffer: inout ByteBuffer, lower:UnsafePointer<MDB_val>, upper:UnsafePointer<MDB_val>?, upperBound:MDB_val, cursor: MDB_db_cursor_type) throws {
		let numElements:Int = (upper == nil) ? try cursor.countEntries(begin:lower) : try cursor.countEntries(begin:lower, end:upper!)
		if (numElements < buckets * 2) {
			// | Bound | idList (0x2) | numIds (i.e. 20) | ID1 | ID2 | ... | ID20 |
			write(val: upperBound, writeBuffer: &returnBuffer)
			write(mode: .idList, writeBuffer: &returnBuffer)
			write(numElements: numElements, writeBuffer: &returnBuffer)
			if(upper == nil) {
				try cursor.iterate(begin:lower, { id in
					write(val: id.pointee, writeBuffer: &returnBuffer)
					return true
				})
			} else {
				try cursor.iterate(begin:lower, end:upper!, { id in
					write(val: id.pointee, writeBuffer: &returnBuffer)
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
				if(i != buckets - 1) {
					let startNextBucket = try cursor.opNext(returning:(key:MDB_val, value:MDB_val).self).key
					write(val: startNextBucket, writeBuffer: &returnBuffer)
				} else {
					write(val: upperBound, writeBuffer: &returnBuffer)
				}
				write(mode: .fingerprint, writeBuffer: &returnBuffer)
				write(fingerprint: ourFingerprint, writeBuffer: &returnBuffer)
			}
		}
	}
	
	internal func splitRangeZeroDB(returnBuffer: inout ByteBuffer, upperBound:MDB_val) {
		let numElements:Int = 0
		// | Bound | idList (0x2) | numIds (i.e. 20) | ID1 | ID2 | ... | ID20 |
		write(val: upperBound, writeBuffer: &returnBuffer)
		write(mode: .idList, writeBuffer: &returnBuffer)
		write(numElements: numElements, writeBuffer: &returnBuffer)
	}
}

