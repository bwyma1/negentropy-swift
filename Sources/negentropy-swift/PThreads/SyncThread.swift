import bedrock_pthread
import RAW_dh25519
import bedrock_fifo
import QuickLMDB
import NIO
import Logging
import wireguard_userspace_nio

extension NegentropyDatabaseStrict {
	/// The primary sync function used in the sync pthread.
	/// The function reads incoming Negentropy packets and strips the Negentropy header for the type of packet.
	/// - `.initiator`: Reconciles the packet's data content. If the returned message is nil, then start to sync the data. If it's not nil. the send the message to the listener.
	/// - `.data`: Adds the data's key and value to the database. Does not send a response to the sync thread.
	fileprivate func sync(channel:Channel, fifo:FIFO<ByteBuffer, Swift.Error>, publicKey:PublicKey, buckets:Int, tx:borrowing Transaction, cliLogger:Logger, oneWaySync:Bool) throws {
		var buffer = ByteBufferAllocator().buffer(capacity: MemoryLayout<MDB_db_key_type>.size)
		
		let msg = try initiate(buckets: buckets, tx: tx)
		try WGInterface<KCPChannels>.write(channel: channel, publicKey: publicKey, data: msg)
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
				try WGInterface<KCPChannels>.write(channel: channel, publicKey: publicKey, data: buffer)
				break syncLoop
			}
			if let incomingData = try iterator.next() {
				
				guard incomingData.readableBytes > 0 else {
				   throw NegentropyError.expectedNegentropyData
				}
				var type = MessageType.finish
				let verifiedData = try incomingData.withUnsafeReadableBytes { ptr in
				   guard let negData = NegentropyData(RAW_decode: ptr) else {
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
							try WGInterface<KCPChannels>.write(channel: channel, publicKey: publicKey, data: newMsg!)
						} else {
							cliLogger.info("Negentropy messaging complete. Sending data/query messages.")
							// Send all of the data for the ID's we have
							if(oneWaySync == false) {
								for key in allHave {
									_ = key.RAW_access_immutable(UnsafeBufferPointer<UInt8>.self) { ptr in
										buffer.writeBytes(ptr)
									}
									let value = try loadEntry(key: key, tx: tx)
									_ = value.RAW_access_immutable(UnsafeBufferPointer<UInt8>.self) { ptr in
										buffer.writeBytes(ptr)
									}
									encodeNegentropyHeader(into: &buffer, type: .data)
									try WGInterface<KCPChannels>.write(channel: channel, publicKey: publicKey, data: buffer)
									buffer.clear(minimumCapacity: MemoryLayout<MDB_db_key_type>.size)
								}
							}
							// Send data query messages for the ID's we need
							breakCount = allNeed.count
							for key in allNeed {
								_ = key.RAW_access_immutable(UnsafeBufferPointer<UInt8>.self) { ptr in
									buffer.writeBytes(ptr)
								}
								encodeNegentropyHeader(into: &buffer, type: .dataQuery)
								try WGInterface<KCPChannels>.write(channel: channel, publicKey: publicKey, data: buffer)
								buffer.clear(minimumCapacity: MemoryLayout<MDB_db_key_type>.size)
							}
						}
					case .data:
						let key = try verifiedData.withUnsafeReadableBytes { ptr in
							guard ptr.count >= MemoryLayout<MDB_db_key_type>.size else { throw NegentropyError.undecodableMDBKey }
							return MDB_db_key_type.fromBindingBytes(ptr)
						}
						var valueSlice = verifiedData
						valueSlice.moveReaderIndex(forwardBy: MemoryLayout<MDB_db_key_type>.size)

						var valueBuffer = ByteBufferAllocator().buffer(capacity: valueSlice.readableBytes)
						valueBuffer.writeBuffer(&valueSlice)

						let value = try valueBuffer.withUnsafeReadableBytes { ptr -> MDB_db_val_type in
							guard let ret = MDB_db_val_type(RAW_decode: ptr) else {
								throw NegentropyError.undecodableMDBValue
							}
							return ret
						}
						try cursor(tx:tx) { cursor in
							try cursor.setEntry(key: key, value:value, flags:[])
						}
						breakCount -= 1
					default:
						continue
				}
			}
		}
	}
}

extension NegentropyDatabase {
	/// See NegentropyDatabaseStrict.sync()
	fileprivate func sync(channel:Channel, fifo:FIFO<ByteBuffer, Swift.Error>, publicKey:PublicKey, buckets:Int, tx:borrowing Transaction, cliLogger:Logger, oneWaySync:Bool) throws {
		var buffer = ByteBufferAllocator().buffer(capacity: 0)
		
		let msg = try initiate(buckets: buckets, tx: tx)
		try WGInterface<KCPChannels>.write(channel: channel, publicKey: publicKey, data: msg)
		cliLogger.debug("Sent initial Negentropy Sync message")
		
		var allHave = Set<ByteBuffer>()
		var allNeed = Set<ByteBuffer>()
		var breakCount = Int.max
		
		let iterator = fifo.makeSyncConsumerBlocking()
		syncLoop: while(true) {
			// Wait to receive message of data
			if(breakCount <= 0) {
				// Send stop signal to listener
				encodeNegentropyHeader(into: &buffer, type: .finish)
				try WGInterface<KCPChannels>.write(channel: channel, publicKey: publicKey, data: buffer)
				break syncLoop
			}
			if let incomingData = try iterator.next() {
				
				guard incomingData.readableBytes > 0 else {
				   throw NegentropyError.expectedNegentropyData
				}
				var type = MessageType.finish
				var verifiedData = try incomingData.withUnsafeReadableBytes { ptr in
				   guard let negData = NegentropyData(RAW_decode: ptr) else {
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
						var have = Set<ByteBuffer>()
						var need = Set<ByteBuffer>()
						let newMsg = try reconcile(query: verifiedData, haveIds: &have, needIds: &need, buckets: buckets, tx: tx)

						allHave.formUnion(have)
						allNeed.formUnion(need)
						
						if(newMsg != nil) {
							try WGInterface<KCPChannels>.write(channel: channel, publicKey: publicKey, data: newMsg!)
						} else {
							cliLogger.info("Negentropy messaging complete. Sending data/query messages.")
							// Send all of the data for the ID's we have
							if(oneWaySync == false) {
								for var keyBuffer in allHave {
									try keyBuffer.withUnsafeMutableReadableBytes { ptr in
										let key = MDB_val(mv_size: ptr.count, mv_data: ptr.baseAddress!)
										write(val: key, writeBuffer: &buffer)
										let value = try loadEntry(key: key, tx: tx)
										buffer.writeBytes(UnsafeRawBufferPointer(start: value.mv_data, count: value.mv_size))
										encodeNegentropyHeader(into: &buffer, type: .data)
										try WGInterface<KCPChannels>.write(channel: channel, publicKey: publicKey, data: buffer)
										buffer.clear(minimumCapacity: 0)
									}
								}
							}
							// Send data query messages for the ID's we need
							breakCount = allNeed.count
							for var keyBuffer in allNeed {
								try keyBuffer.withUnsafeMutableReadableBytes { ptr in
									let key = MDB_val(mv_size: ptr.count, mv_data: ptr.baseAddress!)
									buffer.writeBytes(UnsafeRawBufferPointer(start: key.mv_data, count: key.mv_size))
									encodeNegentropyHeader(into: &buffer, type: .dataQuery)
									try WGInterface<KCPChannels>.write(channel: channel, publicKey: publicKey, data: buffer)
									buffer.clear(minimumCapacity: MemoryLayout<MDB_db_key_type>.size)
								}
							}
						}
					case .data:
						guard let keyLength = verifiedData.readInteger(as:UInt8.self) else {
							throw InternalFatalError()
						}
						guard var keyBytes = verifiedData.readBytes(length:Int(keyLength)) else {
							throw InternalFatalError()
						}
						guard var valBytes = verifiedData.readBytes(length:verifiedData.readableBytes) else {
							throw InternalFatalError()
						}
						try keyBytes.withUnsafeMutableBytes { keyPtr in
							try valBytes.withUnsafeMutableBytes { valPtr in
								let key = MDB_val(mv_size: keyPtr.count, mv_data: keyPtr.baseAddress!)
								let val = MDB_val(mv_size: valPtr.count, mv_data: valPtr.baseAddress!)
								try cursor(tx:tx) { cursor in
									try cursor.setEntry(key:key, value:val, flags:[])
								}
							}
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
	private let mdbBasicArray:[any NegentropyDatabase]
	private let mdbStrictArray:[any NegentropyDatabaseStrict]
	private let channel:Channel
	private let fifo:FIFO<ByteBuffer, Swift.Error>
	private let publicKey:PublicKey
	private let oneWaySync:Bool
	private let buckets:Int
	private var cliLogger:Logger
	
	public init(_ env:consuming ([any NegentropyDatabase], [any NegentropyDatabaseStrict], Channel, FIFO<ByteBuffer, Swift.Error>, PublicKey, Bool)) {
		cliLogger = Logger(label: "ng.listener")
		cliLogger.logLevel = .debug
		self.mdbBasicArray = env.0
		self.mdbStrictArray = env.1
		self.channel = env.2
		self.fifo = env.3
		self.publicKey = env.4
		self.oneWaySync = env.5
		
		self.buckets = 20
	}
	/// Sends the database signatures of all databases awaiting a sync to the listener.
	/// All databases must be in the same environment.
	/// The sync thread databases MUST be a subset of the listener thread databases.
	/// individually sync on all databases until syncing is complete.
	public func pthreadWork() throws -> Void {
		guard mdbStrictArray.count + mdbBasicArray.count > 0 else { throw NegentropyError.noDatabases }
		
		var buffer = ByteBufferAllocator().buffer(capacity: 64)
		for storage in mdbBasicArray {
			let dbSignature = storage.getDBSignature()
			write(dbSignature: dbSignature, writeBuffer: &buffer)
		}
		for storage in mdbStrictArray {
			let dbSignature = storage.getDBSignature()
			write(dbSignature: dbSignature, writeBuffer: &buffer)
		}
		try WGInterface<KCPChannels>.write(channel: channel, publicKey: publicKey, data: buffer)
		
		var env:Environment
		if(!mdbBasicArray.isEmpty) {
			env = mdbBasicArray[0].dbEnvironment()
		}
		else {
			env = mdbStrictArray[0].dbEnvironment()
		}
		
		let syncTransaction = try Transaction(env:env, readOnly:false)
		
		// Syncing for ALL storages
		for storage in mdbBasicArray {
			try storage.sync(channel: channel, fifo: fifo, publicKey: publicKey, buckets: buckets, tx: syncTransaction, cliLogger: cliLogger, oneWaySync:oneWaySync)
		}
		for storage in mdbStrictArray {
			try storage.sync(channel: channel, fifo: fifo, publicKey: publicKey, buckets: buckets, tx: syncTransaction, cliLogger: cliLogger, oneWaySync:oneWaySync)
		}
		try syncTransaction.commit()
	}
}
