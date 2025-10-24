import bedrock_pthread
import RAW_dh25519
import bedrock_fifo
import QuickLMDB
import NIO
import Logging
import wireguard_userspace_nio

extension NegentropyDatabase {
	fileprivate func sync(channel:Channel, fifo:FIFO<ByteBuffer, Swift.Error>, publicKey:PublicKey, buckets:Int, tx:borrowing Transaction, cliLogger:Logger) throws {
		var buffer = ByteBufferAllocator().buffer(capacity: MemoryLayout<MDB_db_key_type>.size)
		
		let msg = try initiate(buckets: buckets, tx: tx)
		try WGInterface<[UInt8]>.write(channel: channel, publicKey: publicKey, data: msg)
		cliLogger.debug("Sent initial Negentropy Sync message")
		
		var allHave = Set<MDB_db_key_type>()
		var allNeed = Set<MDB_db_key_type>()
		var breakCount = Int.max
		
		let iterator = fifo.makeSyncConsumerBlocking()
		syncLoop: while(true) {
			// Wait to receive message of data
			if(breakCount <= 0) {
				// Send stop signal to listener
				encodeNegentropyHeader(into: &buffer, type: .finish)
				try WGInterface<[UInt8]>.write(channel: channel, publicKey: publicKey, data: buffer)
				break syncLoop
			}
			if let incomingData = try iterator.next() {
				
				guard incomingData.readableBytes > 0 else {
				   throw NegentropyError.expectedNegentropyData
				}
				var type = MessageType.finish
				let verifiedData = try incomingData.withUnsafeReadableBytes { ptr in
				   guard let negData = NegentropyData(RAW_decode: ptr.baseAddress!, count: ptr.count) else {
					   throw NegentropyError.expectedNegentropyData
				   }
				   type = negData.type
				   guard type != .responder else {
					   throw NegentropyError.expectedNonResponderMessage
				   }
				   
				   return negData.data
				}
				
				switch type {
					case .initiator:
						var have = Set<MDB_db_key_type>()
						var need = Set<MDB_db_key_type>()
						let newMsg = try reconcile(query: verifiedData, haveIds: &have, needIds: &need, buckets: buckets, tx: tx)
						allHave.formUnion(have)
						allNeed.formUnion(need)
						
						if(newMsg != nil) {
							try WGInterface<[UInt8]>.write(channel: channel, publicKey: publicKey, data: newMsg!)
						} else {
							cliLogger.info("Negentropy messaging complete. Sending data/query messages.")
							// Send all of the data for the ID's we have
							for date in allHave {
								_ = date.RAW_access { ptr in
									buffer.writeBytes(ptr)
								}
								let value = try loadEntry(key: date, tx: tx)
								_ = value.RAW_access { ptr in
									buffer.writeBytes(ptr)
								}
								encodeNegentropyHeader(into: &buffer, type: .data)
								try WGInterface<[UInt8]>.write(channel: channel, publicKey: publicKey, data: buffer)
								buffer.clear(minimumCapacity: MemoryLayout<MDB_db_key_type>.size)
							}
							// Send data query messages for the ID's we need
							breakCount = allNeed.count
							for date in allNeed {
								_ = date.RAW_access { ptr in
									buffer.writeBytes(ptr)
								}
								encodeNegentropyHeader(into: &buffer, type: .dataQuery)
								try WGInterface<[UInt8]>.write(channel: channel, publicKey: publicKey, data: buffer)
								buffer.clear(minimumCapacity: MemoryLayout<MDB_db_key_type>.size)
							}
						}
					case .data:
						let date = try verifiedData.withUnsafeReadableBytes { ptr in
							guard ptr.count >= MemoryLayout<MDB_db_key_type>.size else { throw NegentropyError.undecodableIdentifier }
							return MDB_db_key_type(RAW_staticbuff: ptr.baseAddress!)
						}
						var valueSlice = verifiedData
						valueSlice.moveReaderIndex(forwardBy: MemoryLayout<MDB_db_key_type>.size)

						var valueBuffer = ByteBufferAllocator().buffer(capacity: valueSlice.readableBytes)
						valueBuffer.writeBuffer(&valueSlice)

						let value = try valueBuffer.withUnsafeReadableBytes { ptr -> MDB_db_val_type in
							guard let ret = MDB_db_val_type(RAW_decode: UnsafeRawPointer(ptr.baseAddress!), count: ptr.count) else {
								throw NegentropyError.undecodableValue
							}
							return ret
						}
						try cursor(tx:tx) { cursor in
							try cursor.setEntry(key:date, value:value, flags:[])
						}
						breakCount -= 1
					default:
						continue
				}
			}
		}
	}
}


public struct NegentropySyncThread:PThreadWork {
	private let mdbDBArray:[any NegentropyDatabase]
	private let channel:Channel
	private let fifo:FIFO<ByteBuffer, Swift.Error>
	private let publicKey:PublicKey
	private let buckets:Int
	private var cliLogger:Logger
	
	public init(_ env:consuming ([any NegentropyDatabase], Channel, FIFO<ByteBuffer, Swift.Error>, PublicKey)) {
		cliLogger = Logger(label: "ng.syncer")
		cliLogger.logLevel = .debug
		self.mdbDBArray = env.0
		self.channel = env.1
		self.fifo = env.2
		self.publicKey = env.3
		self.buckets = 20
	}
	public func pthreadWork() throws -> Void {
		guard mdbDBArray.count > 0 else { throw NegentropyError.noDatabases }
		let env = mdbDBArray[0].dbEnvironment()
		let syncTransaction = try Transaction(env:env, readOnly:false)
		
		// Syncing for ALL storages
		for storage in mdbDBArray {
			try storage.sync(channel: channel, fifo: fifo, publicKey: publicKey, buckets: buckets, tx: syncTransaction, cliLogger: cliLogger)
		}
		try syncTransaction.commit()
	}
}
