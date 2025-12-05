import bedrock_pthread
import RAW_dh25519
import bedrock_fifo
import QuickLMDB
import NIO
import Logging
import wireguard_userspace_nio

extension NegentropyDatabaseStrict {
	/// The primary listen function used in the sync pthread.
	/// The function reads incoming Negentropy packets and strips the Negentropy header for the type of packet.
	/// - `.responder`: Reconciles the packet's data content and sends the corresponding response to the sync thread.
	/// - `.dataQuery`: Finds the corresponding value for the data query key and sends it to the sync thread.
	/// - `.data`: Adds the data's key and value to the database. Does not send a response to the sync thread.
	/// - `.finish`: Breaks the receive loop.
	fileprivate func listen(channel:Channel, fifo:FIFO<ByteBuffer, Swift.Error>, publicKey:PublicKey, buckets:Int, tx:borrowing Transaction, cliLogger:Logger) throws {
		var buffer = ByteBufferAllocator().buffer(capacity: MemoryLayout<MDB_db_key_type>.size)
				
		let iterator = fifo.makeSyncConsumerBlocking()
		syncLoop: while(true) {
			// Wait to receive message of data
			if let incomingData = try iterator.next() {
				
				guard incomingData.readableBytes > 0 else {
				   throw NegentropyError.expectedNegentropyData
				}
				var type = MessageType.finish
				var verifiedData = try incomingData.withUnsafeReadableBytes { ptr in
				   guard let negData = NegentropyData(RAW_decode: ptr.baseAddress!, count: ptr.count) else {
					   throw NegentropyError.expectedNegentropyData
				   }
				   type = negData.type
				   guard type != .initiator else {
					   throw NegentropyError.expectedNonInitiatorMessage
				   }
				   
				   return negData.data
				}

				switch type {
					case .responder:
						let newMsg = try reconcile(query: verifiedData, buckets: buckets, tx: tx)
						try WGInterface<KCPChannels>.write(channel: channel, publicKey: publicKey, data: newMsg)
					case .dataQuery:
						let key = try verifiedData.withUnsafeReadableBytes { ptr in
							guard ptr.count >= MemoryLayout<MDB_db_key_type>.size else { throw NegentropyError.undecodableMDBKey }
							return MDB_db_key_type(RAW_staticbuff: ptr.baseAddress!)
						}
						
						buffer.writeBuffer(&verifiedData)
						let value = try loadEntry(key: key, tx: tx)
						_ = value.RAW_access { ptr in
							buffer.writeBytes(ptr)
						}
						encodeNegentropyHeader(into: &buffer, type: .data)
						try WGInterface<KCPChannels>.write(channel: channel, publicKey: publicKey, data: buffer)
						buffer.clear(minimumCapacity: MemoryLayout<MDB_db_key_type>.size)
					case .data:
						let key = try verifiedData.withUnsafeReadableBytes { ptr in
							guard ptr.count >= MemoryLayout<MDB_db_key_type>.size else { throw NegentropyError.undecodableMDBKey }
							return MDB_db_key_type(RAW_staticbuff: ptr.baseAddress!)
						}
						var valueSlice = verifiedData
						valueSlice.moveReaderIndex(forwardBy: MemoryLayout<MDB_db_key_type>.size)

						var valueBuffer = ByteBufferAllocator().buffer(capacity: valueSlice.readableBytes)
						valueBuffer.writeBuffer(&valueSlice)

						let value = try valueBuffer.withUnsafeReadableBytes { ptr -> MDB_db_val_type in
							guard let ret = MDB_db_val_type(RAW_decode: UnsafeRawPointer(ptr.baseAddress!), count: ptr.count) else {
								throw NegentropyError.undecodableMDBValue
							}
							return ret
						}
						try cursor(tx:tx) { cursor in
							try cursor.setEntry(key:key, value:value, flags:[])
						}
					case .finish:
						break syncLoop
					default:
						continue
				}
			}
		}
	}
}

extension NegentropyDatabase {
	/// See NegentropyDatabaseStrict.listen()
	fileprivate func listen(channel:Channel, fifo:FIFO<ByteBuffer, Swift.Error>, publicKey:PublicKey, buckets:Int, tx:borrowing Transaction, cliLogger:Logger) throws {
		var buffer = ByteBufferAllocator().buffer(capacity: 0)
				
		let iterator = fifo.makeSyncConsumerBlocking()
		syncLoop: while(true) {
			// Wait to receive message of data
			if let incomingData = try iterator.next() {
				
				guard incomingData.readableBytes > 0 else {
				   throw NegentropyError.expectedNegentropyData
				}
				var type = MessageType.finish
				var verifiedData = try incomingData.withUnsafeReadableBytes { ptr in
				   guard let negData = NegentropyData(RAW_decode: ptr.baseAddress!, count: ptr.count) else {
					   throw NegentropyError.expectedNegentropyData
				   }
				   type = negData.type
				   guard type != .initiator else {
					   throw NegentropyError.expectedNonInitiatorMessage
				   }
				   
				   return negData.data
				}

				switch type {
					case .responder:
						let newMsg = try reconcile(query: verifiedData, buckets: buckets, tx: tx)
						try WGInterface<KCPChannels>.write(channel: channel, publicKey: publicKey, data: newMsg)
					case .dataQuery:
						try verifiedData.withUnsafeMutableReadableBytes { ptr in
							let key = MDB_val(mv_size: ptr.count, mv_data: ptr.baseAddress!)
							write(val: key, writeBuffer: &buffer)
							let value = try loadEntry(key: key, tx: tx)
							buffer.writeBytes(UnsafeRawBufferPointer(start: value.mv_data, count: value.mv_size))
							encodeNegentropyHeader(into: &buffer, type: .data)
							try WGInterface<KCPChannels>.write(channel: channel, publicKey: publicKey, data: buffer)
							buffer.clear(minimumCapacity: 0)
						}
					case .data:
						let keyLength = verifiedData.readInteger(as:UInt8.self)!
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
					case .finish:
						break syncLoop
					default:
						continue
				}
			}
		}
	}
}

public struct NegentropyListenThread:PThreadWork {
	private let mdbBasicArray:[any NegentropyDatabase]
	private let mdbStrictArray:[any NegentropyDatabaseStrict]
	private let channel:Channel
	private let fifo:FIFO<ByteBuffer, Swift.Error>
	private let publicKey:PublicKey
	private var dbSignatures:ByteBuffer
	private let buckets:Int
	private var cliLogger:Logger
	
	public init(_ env:consuming ([any NegentropyDatabase], [any NegentropyDatabaseStrict], Channel, FIFO<ByteBuffer, Swift.Error>, PublicKey, ByteBuffer)) {
		cliLogger = Logger(label: "ng.listener")
		cliLogger.logLevel = .debug
		self.mdbBasicArray = env.0
		self.mdbStrictArray = env.1
		self.channel = env.2
		self.fifo = env.3
		self.publicKey = env.4
		self.dbSignatures = env.5
		self.buckets = 20
	}
	/// Receives the database signatures from the sync thread and stores the corresponding databases.
	/// All databases must be in the same environment.
	/// The listener thread databases MUST contain the sync threads databases.
	/// individually listen on all databases until syncing is complete.
	public func pthreadWork() throws -> Void {
		guard mdbStrictArray.count + mdbBasicArray.count > 0 else { throw NegentropyError.noDatabases }
		
		var sortedBasicArray:[any NegentropyDatabase] = []
		var sortedStrictArray:[any NegentropyDatabaseStrict] = []
		var dbSignatures = self.dbSignatures
		while dbSignatures.readableBytes > 0 {
			guard let signatureLength = dbSignatures.readInteger(endianness:.big, as:EncodedUInt64.RAW_native_type.self) else {
				throw InternalFatalError()
			}
			if let signature = dbSignatures.readString(length: Int(signatureLength)) {
				for storage in mdbBasicArray {
					if(storage.getDBSignature() == signature) {
						sortedBasicArray.append(storage)
						break
					}
				}
				for storage in mdbStrictArray {
					if(storage.getDBSignature() == signature) {
						sortedStrictArray.append(storage)
						break
					}
				}
			}
		}
		
		var env:Environment
		if(!mdbBasicArray.isEmpty) {
			env = mdbBasicArray[0].dbEnvironment()
		}
		else {
			env = mdbStrictArray[0].dbEnvironment()
		}
		
		let syncTransaction = try Transaction(env:env, readOnly:false)
		
		// Syncing for ALL storages
		for storage in sortedBasicArray {
			// put into a fileprivate extension
			try storage.listen(channel: channel, fifo: fifo, publicKey: publicKey, buckets: buckets, tx: syncTransaction, cliLogger: cliLogger)
		}
		for storage in sortedStrictArray {
			// put into a fileprivate extension
			try storage.listen(channel: channel, fifo: fifo, publicKey: publicKey, buckets: buckets, tx: syncTransaction, cliLogger: cliLogger)
		}
		try syncTransaction.commit()
	}
}


