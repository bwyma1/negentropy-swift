import Testing
import Foundation
import RAW
import class Foundation.FileManager
import Logging
import QuickLMDB
import bedrock
import RAW_base64
import RAW_dh25519
import wireguard_userspace_nio
import bedrock_fifo
import NIO
import negentropy_swift

@RAW_staticbuff(bytes: 8)
@RAW_staticbuff_fixedwidthinteger_type<UInt64>(bigEndian: true)
public struct Data: Sendable, Equatable, Comparable {}

@Suite("Negentropy Swift Tests", .serialized)
struct NegentropySwiftTests {}

@RAW_staticbuff(bytes: 8)
@RAW_staticbuff_fixedwidthinteger_type<UInt64>(bigEndian: true)
@MDB_comparable
public struct TestingID: Sendable, DatabaseIndexVector {}

extension NegentropySwiftTests {
	@Suite("Negentropy LMDB Tests",
		   .serialized
	)
	struct LMDBExtensionTests {
		private let aliceEnv:Environment
		private var aliceDB:Database
		
		init() throws {
			let base = Path(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path)
			var finalPath = base.appendingPathComponent("aliceDBtesting.mdb")
			let memoryMapSize = size_t(finalPath.getFileSize() + 5 * 1024 * 1024 * 1024) // add 5mb to the file
			aliceEnv = try Environment(path:finalPath.path(), flags:[.noSubDir], mapSize:memoryMapSize, maxReaders:16, maxDBs:3, mode:[.ownerReadWriteExecute, .groupReadExecute, .otherReadExecute])
			let newTrans = try Transaction(env:aliceEnv, readOnly:false)

			aliceDB = try! Database(env:aliceEnv, name:nil, flags:[.create], tx:newTrans)
			try aliceDB.deleteAllEntries(tx:newTrans)
			
			var keyarray = [1,2,3,4]
			var valarray = [5,6,7,8]
			var valarray2 = [5,6,7,8, 9, 10]
			try aliceDB.cursor(tx:newTrans) { cursor in
				try keyarray.withUnsafeMutableBytes { keyPtr in
					try valarray.withUnsafeMutableBytes { valPtr in
						try valarray2.withUnsafeMutableBytes { valPtr2 in
							let key:MDB_val = MDB_val(mv_size: keyPtr.count, mv_data: keyPtr.baseAddress!)
							let val:MDB_val = MDB_val(mv_size: valPtr.count, mv_data: valPtr.baseAddress!)
							let val2:MDB_val = MDB_val(mv_size: valPtr2.count, mv_data: valPtr2.baseAddress!)
							try cursor.setEntry(key:key, value:val, flags:[])
							try cursor.setEntry(key:key, value:val2, flags:[])
						}
					}
				}
			}
			
			try newTrans.commit()
		}
	}
}

extension NegentropySwiftTests {
	@Suite("Negentropy LMDB Tests",
		   .serialized
	)
	struct Randomtests {
		private let aliceEnv:Environment
		private var aliceDB:Database.DupSort<TestingID, TestingID>
		
		init() throws {
			let base = Path(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path)
			var finalPath = base.appendingPathComponent("aliceDBtesting2.mdb")
			let memoryMapSize = size_t(finalPath.getFileSize() + 5 * 1024 * 1024 * 1024) // add 5mb to the file
			aliceEnv = try Environment(path:finalPath.path(), flags:[.noSubDir], mapSize:memoryMapSize, maxReaders:16, maxDBs:3, mode:[.ownerReadWriteExecute, .groupReadExecute, .otherReadExecute])
			let newTrans = try Transaction(env:aliceEnv, readOnly:false)

			aliceDB = try! Database.DupSort<TestingID, TestingID>(env:aliceEnv, name:nil, flags:[.create], tx:newTrans)
			try aliceDB.deleteAllEntries(tx:newTrans)
			
			try aliceDB.cursor(tx:newTrans) { cursor in
				let key1:TestingID = try generateSecureRandomBytes(as: TestingID.self)
				let key2:TestingID = try generateSecureRandomBytes(as: TestingID.self)
				let val1:TestingID = try generateSecureRandomBytes(as: TestingID.self)
				let val2:TestingID = try generateSecureRandomBytes(as: TestingID.self)
				try cursor.setEntry(key:key1, value:val1, flags:[])
				try cursor.setEntry(key:key1, value:val2, flags:[])
			}
			
			try newTrans.commit()
		}
	}
}

extension NegentropySwiftTests {
	@Suite("Negentropy Live LMDB Tests",
		   .serialized
	)
	struct LiveNegentropyTests {
		
		private let logger:Logger
		private let aliceEnv:Environment
		private var aliceBasicDBs:[Database] = []
		private var aliceStrictDBs:[Database.Strict<TestingID, Data>] = []
		
		private let bobEnv:Environment
		private var bobBasicDBs:[Database] = []
		private var bobStrictDBs:[Database.Strict<TestingID, Data>] = []
		
		
		static let aliceStaticPrivateKey = MemoryGuarded<PrivateKey>(RAW_decode:try! RAW_base64.decode("8DFnI7tPWLl4WmuEp4T5KVuKMW6iyjRdTb3IVaDe+kI="), count:32)!
		static let bobStaticPrivateKey = MemoryGuarded<PrivateKey>(RAW_decode:try! RAW_base64.decode("SD/y8yQa/DgiYRnDI9vJEiGezNn4yLd/4yL9OLnej0A="), count:32)!

		let alicePublicKey:PublicKey
		let alicePrivateKey:MemoryGuarded<PrivateKey>
		
		let bobPublicKey:PublicKey
		let bobPrivateKey:MemoryGuarded<PrivateKey>
		
		init() throws {
			let base = Path(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path)
			var finalPath = base.appendingPathComponent("aliceDB.mdb")
			let memoryMapSize = size_t(finalPath.getFileSize() + 5 * 1024 * 1024 * 1024) // add 5mb to the file
			aliceEnv = try Environment(path:finalPath.path(), flags:[.noSubDir], mapSize:memoryMapSize, maxReaders:16, maxDBs:3, mode:[.ownerReadWriteExecute, .groupReadExecute, .otherReadExecute])
			
			finalPath = base.appendingPathComponent("bobDB.mdb")
			bobEnv = try Environment(path:finalPath.path(), flags:[.noSubDir], mapSize:memoryMapSize, maxReaders:16, maxDBs:3, mode:[.ownerReadWriteExecute, .groupReadExecute, .otherReadExecute])
			
			var makelogger = Logger(label: "negentropy-swift-tests")
			makelogger.logLevel = .notice
			logger = makelogger
			
			(alicePublicKey, alicePrivateKey) = (PublicKey(privateKey:Self.aliceStaticPrivateKey), Self.aliceStaticPrivateKey)
			(bobPublicKey, bobPrivateKey) = (PublicKey(privateKey:Self.bobStaticPrivateKey), Self.bobStaticPrivateKey)
		}
		
		func logID(id:TestingID) {
			id.RAW_access({ptr in
				logger.trace("\(Array(UnsafeBufferPointer(start: ptr.baseAddress!, count: ptr.count)))")
			})
		}
		
		mutating func addStrictDBAlice(aliceDBSize:Int, dbName:String) throws {
			let newTrans = try Transaction(env:aliceEnv, readOnly:false)

			let aliceDB = try! Database.Strict<TestingID, Data>(env:aliceEnv, name:dbName, flags:[.create], tx:newTrans)
			try aliceDB.deleteAllEntries(tx:newTrans)
			
			try aliceDB.cursor(tx:newTrans) { cursor in
				for i in 0..<aliceDBSize {
					let id:TestingID = try generateSecureRandomBytes(as: TestingID.self)
					logID(id: id)
					try cursor.setEntry(key:id, value:Data(RAW_native: UInt64(i)), flags:[])
				}
			}
			
			try newTrans.commit()
			aliceStrictDBs.append(aliceDB)
		}
		
		func generateMDBVal(count n: Int) -> MDB_val {
			let size = Int.random(in: 1...n)
			var arr = (0..<size).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }
			return arr.withUnsafeMutableBytes { ptr in
				return MDB_val(mv_size: ptr.count, mv_data: ptr.baseAddress!)
			}
		}
		
		mutating func addBasicDBAlice(aliceDBSize:Int, dbName:String) throws {
			let newTrans = try Transaction(env:aliceEnv, readOnly:false)

			let aliceDB = try! Database(env:aliceEnv, name:dbName, flags:[.create], tx:newTrans)
			try aliceDB.deleteAllEntries(tx:newTrans)
			
			try aliceDB.cursor(tx:newTrans) { cursor in
				for i in 0..<aliceDBSize {
					let keyptr = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<Int>.size,
															   alignment: MemoryLayout<Int>.alignment)
					keyptr.storeBytes(of: i*2, as: Int.self)
					defer { keyptr.deallocate() }
					let key = MDB_val(mv_size: MemoryLayout<Int>.size , mv_data: keyptr)
					let valptr = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<Int>.size,
															   alignment: MemoryLayout<Int>.alignment)
					valptr.storeBytes(of: i, as: Int.self)
					defer { valptr.deallocate() }
					let val = MDB_val(mv_size: MemoryLayout<Int>.size , mv_data: valptr)
					try cursor.setEntry(key:key, value:val, flags:[])
				}
			}
			
			try newTrans.commit()
			aliceBasicDBs.append(aliceDB)
		}
		
		mutating func addStrictDBBob(bobDBSize:Int, dbName:String) throws {
			let newTrans = try Transaction(env:bobEnv, readOnly:false)
			let bobDB = try! Database.Strict<TestingID, Data>(env:bobEnv, name:dbName, flags:[.create], tx:newTrans)
			try bobDB.deleteAllEntries(tx:newTrans)
			
			try bobDB.cursor(tx:newTrans) { cursor in
				for i in 0..<bobDBSize {
					let id:TestingID = try generateSecureRandomBytes(as: TestingID.self)
					logID(id: id)
					try cursor.setEntry(key:id, value:Data(RAW_native: UInt64(i)), flags:[])
				}
			}
			
			try newTrans.commit()
			bobStrictDBs.append(bobDB)
		}
		
		mutating func addBasicDBBob(bobDBSize:Int, dbName:String) throws {
			let newTrans = try Transaction(env:bobEnv, readOnly:false)

			let bobDB = try! Database(env:bobEnv, name:dbName, flags:[.create], tx:newTrans)
			try bobDB.deleteAllEntries(tx:newTrans)
			
			try bobDB.cursor(tx:newTrans) { cursor in
				for i in 0..<bobDBSize {
					let keyptr = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<Int>.size,
															   alignment: MemoryLayout<Int>.alignment)
					keyptr.storeBytes(of: i*2+1, as: Int.self)
					defer { keyptr.deallocate() }
					let key = MDB_val(mv_size: MemoryLayout<Int>.size , mv_data: keyptr)
					let valptr = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<Int>.size,
															   alignment: MemoryLayout<Int>.alignment)
					valptr.storeBytes(of: i, as: Int.self)
					defer { valptr.deallocate() }
					let val = MDB_val(mv_size: MemoryLayout<Int>.size , mv_data: valptr)
					try cursor.setEntry(key:key, value:val, flags:[.noOverwrite])
				}
			}
			
			try newTrans.commit()
			bobBasicDBs.append(bobDB)
		}
		
		mutating func addIdenticalDBs(dbSize:Int, dbName:String) throws {
			let newTrans1 = try Transaction(env:aliceEnv, readOnly:false)
			let newTrans2 = try Transaction(env:bobEnv, readOnly:false)
			let aliceDB = try! Database.Strict<TestingID, Data>(env:aliceEnv, name:dbName, flags:[.create], tx:newTrans1)
			try aliceDB.deleteAllEntries(tx:newTrans1)
			let bobDB = try! Database.Strict<TestingID, Data>(env:bobEnv, name:dbName, flags:[.create], tx:newTrans2)
			try bobDB.deleteAllEntries(tx:newTrans2)
			
			try aliceDB.deleteAllEntries(tx:newTrans1)
			try bobDB.deleteAllEntries(tx:newTrans2)
			try aliceDB.cursor(tx:newTrans1) { cursor1 in
				try aliceDB.cursor(tx:newTrans2) { cursor2 in
					for i in 0..<dbSize {
						// Make key
						let id:TestingID = try generateSecureRandomBytes(as: TestingID.self)
						logID(id: id)
						try cursor1.setEntry(key:id, value:Data(RAW_native: UInt64(i)), flags:[])
						try cursor2.setEntry(key:id, value:Data(RAW_native: UInt64(i)), flags:[])
					}
				}
			}

			try newTrans1.commit()
			try newTrans2.commit()
			aliceStrictDBs.append(aliceDB)
			bobStrictDBs.append(bobDB)
		}
		
		/// The primary way to sync databases using the listen and sync threads.
		/// - `Create WireGuard Interfaces`: Create the WireGuard interfaces which will be used to transfer the data.
		/// - `Create Sync Thread`: Create the sync thread on the initiators side. Add the strict/basic databases. Pass in the WireGaurd channel, data Fifo, and peer public key. Add/remove one-way sync.
		/// 	- Run the sync thread. When the sync thread finishes running, the sync is complete.
		/// - `Listen Thread`: Capture the first piece of incoming data (the database signatures to sync). Then create the listen thread on the responders side. Add the strict/basic databases. Pass in the WireGaurd channel, data Fifo, and peer public key.
		///  	- Run the listen thread. When the listen thread finishes running, the sync is complete.
		func sync(oneWaySync:Bool) async throws {
			
			_ = try await withThrowingTaskGroup(body: { foo in
				let bobFifo = FIFO<ByteBuffer, Swift.Error>()
				let alicePeers = [(PeerInfo(publicKey: bobPublicKey, ipAddress: "127.0.0.1", port: 36000, internalKeepAlive: .seconds(20), inboundData: bobFifo))]
				let aliceInterface = try WGInterface<KCPChannels>(staticPrivateKey:alicePrivateKey, mtu:1400, initialConfiguration:alicePeers, logLevel:.info, listeningPort: 36001)
				
				let aliceFifo = FIFO<ByteBuffer, Swift.Error>()
				let bobPeers = [(PeerInfo(publicKey: alicePublicKey, ipAddress: "127.0.0.1", port: 36001, internalKeepAlive: .seconds(20), inboundData: aliceFifo))]
				let bobInterface = try WGInterface<KCPChannels>(staticPrivateKey:bobPrivateKey, mtu:1400, initialConfiguration:bobPeers, logLevel:.info, listeningPort: 36000)
				
				foo.addTask {
					try await aliceInterface.run()
				}
				foo.addTask {
					try await bobInterface.run()
				}
				
				logger.info("waiting for alice's interface to initialize...")
				try await aliceInterface.waitForChannelInit()
				
				logger.info("waiting for bob's interface to initialize...")
				try await bobInterface.waitForChannelInit()
				
				let syncThread = await NegentropySyncThread((aliceBasicDBs, aliceStrictDBs, try aliceInterface.getChannel(), bobFifo, bobPublicKey, oneWaySync:oneWaySync))
				
				foo.addTask {
					try syncThread.pthreadWork()
				}
				
				let iterator = aliceFifo.makeSyncConsumerBlocking()
				// Wait to listener initiation
				if let incomingData = try iterator.next() {
					let listenThread = await NegentropyListenThread((bobBasicDBs, bobStrictDBs, try bobInterface.getChannel(), aliceFifo, alicePublicKey, incomingData))
					try listenThread.pthreadWork()
				}
				
				foo.cancelAll()
				try await foo.waitForAll()
				return
			})
		}
		
		func checkSize(aliceDB:Database.Strict<TestingID, Data>, bobDB:Database.Strict<TestingID, Data>, aliceSize:Int, bobSize:Int) throws  {
			let aliceTrans = try Transaction(env:aliceEnv, readOnly:false)
			let bobTrans = try Transaction(env:bobEnv, readOnly:false)
			
			#expect(try aliceDB.dbStatistics(tx: aliceTrans).ms_entries == aliceSize)
			#expect(try bobDB.dbStatistics(tx: bobTrans).ms_entries == bobSize)
			try aliceTrans.commit()
			try bobTrans.commit()
		}
		func checkSize(aliceDB:Database, bobDB:Database, aliceSize:Int, bobSize:Int) throws  {
			let aliceTrans = try Transaction(env:aliceEnv, readOnly:false)
			let bobTrans = try Transaction(env:bobEnv, readOnly:false)
			
			#expect(try aliceDB.dbStatistics(tx: aliceTrans).ms_entries == aliceSize)
			#expect(try bobDB.dbStatistics(tx: bobTrans).ms_entries == bobSize)
			try aliceTrans.commit()
			try bobTrans.commit()
		}
		
		@Test mutating func syncRandomDataBasic() async throws {
			let aliceSize = 10_000
			let bobSize = 10_000
			try addBasicDBAlice(aliceDBSize: aliceSize, dbName: "testDB")
			try addBasicDBBob(bobDBSize: bobSize, dbName: "testDB")
			
			try await sync(oneWaySync: false)
			try checkSize(aliceDB: aliceBasicDBs[0], bobDB: bobBasicDBs[0], aliceSize: aliceSize + bobSize, bobSize: aliceSize + bobSize)
		}
		
		@Test mutating func syncRandomDataStrict() async throws {
			let aliceSize = 10_000
			let bobSize = 10_000
			try addStrictDBAlice(aliceDBSize: aliceSize, dbName: "testDB")
			try addStrictDBBob(bobDBSize: bobSize, dbName: "testDB")
			
			try await sync(oneWaySync: false)
			try checkSize(aliceDB: aliceStrictDBs[0], bobDB: bobStrictDBs[0], aliceSize: aliceSize + bobSize, bobSize: aliceSize + bobSize)
		}
		
		@Test mutating func syncRandomDataStrictAndBasic() async throws {
			let aliceSize = 10_000
			let bobSize = 10_000
			try addBasicDBAlice(aliceDBSize: aliceSize, dbName: "testDBBasic")
			try addBasicDBBob(bobDBSize: bobSize, dbName: "testDBBasic")
			try addStrictDBAlice(aliceDBSize: aliceSize, dbName: "testDBStrict")
			try addStrictDBBob(bobDBSize: bobSize, dbName: "testDBStrict")
			
			
			try await sync(oneWaySync: false)
			try checkSize(aliceDB: aliceStrictDBs[0], bobDB: bobStrictDBs[0], aliceSize: aliceSize + bobSize, bobSize: aliceSize + bobSize)
			try checkSize(aliceDB: aliceBasicDBs[0], bobDB: bobBasicDBs[0], aliceSize: aliceSize + bobSize, bobSize: aliceSize + bobSize)
		}
		
		@Test mutating func syncSameData() async throws {
			let size = 100_000
			try addIdenticalDBs(dbSize: size, dbName: "testDB")
			
			try await sync(oneWaySync: false)
			try checkSize(aliceDB: aliceStrictDBs[0], bobDB: bobStrictDBs[0], aliceSize: size, bobSize: size)
		}
		
		@Test mutating func syncRandomDataDifferentDBSize() async throws {
			let aliceSize = 57_832
			let bobSize = 1_974
			try addStrictDBAlice(aliceDBSize: aliceSize, dbName: "testDB")
			try addStrictDBBob(bobDBSize: bobSize, dbName: "testDB")
			
			try await sync(oneWaySync: false)
			try checkSize(aliceDB: aliceStrictDBs[0], bobDB: bobStrictDBs[0], aliceSize: aliceSize + bobSize, bobSize: aliceSize + bobSize)
		}
		
		@Test mutating func syncAllDBsWithMultipleDatabases() async throws {
			let aliceSizeA = 1234
			let bobSizeA = 1234
			let aliceSizeB = 5678
			let bobSizeB = 5678
			try addStrictDBAlice(aliceDBSize: aliceSizeA, dbName: "testDB_A")
			try addStrictDBBob(bobDBSize: bobSizeA, dbName: "testDB_A")
			try addStrictDBAlice(aliceDBSize: aliceSizeB, dbName: "testDB_B")
			try addStrictDBBob(bobDBSize: bobSizeB, dbName: "testDB_B")
			
			try await sync(oneWaySync: false)
			try checkSize(aliceDB: aliceStrictDBs[0], bobDB: bobStrictDBs[0], aliceSize: aliceSizeA + bobSizeA, bobSize: aliceSizeA + bobSizeA)
			try checkSize(aliceDB: aliceStrictDBs[1], bobDB: bobStrictDBs[1], aliceSize: aliceSizeB + bobSizeB, bobSize: aliceSizeB + bobSizeB)
		}
		
		@Test mutating func syncWithEmptyDB() async throws {
			let aliceSizeA = 1234
			let bobSizeA = 0
			let aliceSizeB = 0
			let bobSizeB = 5678
			try addStrictDBAlice(aliceDBSize: aliceSizeA, dbName: "testDB_A")
			try addStrictDBBob(bobDBSize: bobSizeA, dbName: "testDB_A")
			try addStrictDBAlice(aliceDBSize: aliceSizeB, dbName: "testDB_B")
			try addStrictDBBob(bobDBSize: bobSizeB, dbName: "testDB_B")
			
			try await sync(oneWaySync: false)
			try checkSize(aliceDB: aliceStrictDBs[0], bobDB: bobStrictDBs[0], aliceSize: aliceSizeA + bobSizeA, bobSize: aliceSizeA + bobSizeA)
			try checkSize(aliceDB: aliceStrictDBs[1], bobDB: bobStrictDBs[1], aliceSize: aliceSizeB + bobSizeB, bobSize: aliceSizeB + bobSizeB)
		}
		
		@Test mutating func syncRandomDataOneWay() async throws {
			let aliceSize = 10_000
			let bobSize = 10_000
			try addStrictDBAlice(aliceDBSize: aliceSize, dbName: "testDB")
			try addStrictDBBob(bobDBSize: bobSize, dbName: "testDB")
			
			try await sync(oneWaySync: true)
			try checkSize(aliceDB: aliceStrictDBs[0], bobDB: bobStrictDBs[0], aliceSize: aliceSize + bobSize, bobSize: bobSize)
		}
	}
}
