import bedrock_pthread
import RAW_dh25519
import bedrock_fifo
import QuickLMDB
import NIO
import Logging
import wireguard_userspace_nio

public protocol NegentropyDatabase:MDB_db_strict, Sendable where Self.MDB_db_key_type:DatabaseIndexVector {}

extension NegentropyDatabase {
	fileprivate func listen(channel:Channel, fifo:FIFO<ByteBuffer, Swift.Error>, publicKey:PublicKey, buckets:Int, tx:borrowing Transaction, cliLogger:Logger) throws {
		var buffer = ByteBufferAllocator().buffer(capacity: MemoryLayout<MDB_db_key_type>.size)
				
		let iterator = fifo.makeSyncConsumerBlocking()
		syncLoop: while(true) {
			// Wait to receive message of data
			rcvData: do {
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
							try WGInterface<[UInt8]>.write(channel: channel, publicKey: publicKey, data: newMsg)
						case .dataQuery:
							let date = try verifiedData.withUnsafeReadableBytes { ptr in
								guard ptr.count >= MemoryLayout<MDB_db_key_type>.size else { throw NegentropyError.undecodableIdentifier }
								return MDB_db_key_type(RAW_staticbuff: ptr.baseAddress!)
							}
							
							buffer.writeBuffer(&verifiedData)
							let value = try loadEntry(key: date, tx: tx)
							_ = value.RAW_access { ptr in
								buffer.writeBytes(ptr)
							}
							encodeNegentropyHeader(into: &buffer, type: .data)
							try WGInterface<[UInt8]>.write(channel: channel, publicKey: publicKey, data: buffer)
							buffer.clear(minimumCapacity: MemoryLayout<MDB_db_key_type>.size)
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
						case .finish:
							break syncLoop
						default:
							continue
					}
				}
			}
		}
	}
}

public struct NegentropyListenThread:PThreadWork {
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
		let syncTransaction = try Transaction(env:env, readOnly:true)
		
		// Syncing for ALL storages
		for storage in mdbDBArray {
			// put into a fileprivate extension
			try storage.listen(channel: channel, fifo: fifo, publicKey: publicKey, buckets: buckets, tx: syncTransaction, cliLogger: cliLogger)
		}
		try syncTransaction.commit()
	}
}


