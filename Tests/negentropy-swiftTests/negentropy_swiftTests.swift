import Testing
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
	struct LMDBExtensionTests { }
}

extension NegentropySwiftTests {
	@Suite("Negentropy Live LMDB Tests",
		   .serialized
	)
	struct LiveNegentropyTests {
		
		private let logger:Logger
		private let aliceEnv:Environment
		private var aliceDBs:[Database.Strict<TestingID, Data>] = []
		
		private let bobEnv:Environment
		private var bobDBs:[Database.Strict<TestingID, Data>] = []
		
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
		
		mutating func addDBAlice(aliceDBSize:Int, dbName:String) throws {
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
			aliceDBs.append(aliceDB)
		}
		
		mutating func addDBBob(bobDBSize:Int, dbName:String) throws {
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
			bobDBs.append(bobDB)
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
			aliceDBs.append(aliceDB)
			bobDBs.append(bobDB)
		}
		
//	    Helper sync function for testing storages
		func sync(oneWaySync:Bool) async throws {
			
			_ = try await withThrowingTaskGroup(body: { foo in
				let bobFifo = FIFO<ByteBuffer, Swift.Error>()
				let alicePeers = [(PeerInfo(publicKey: bobPublicKey, ipAddress: "127.0.0.1", port: 36000, internalKeepAlive: .seconds(20)), bobFifo)]
				let aliceInterface = try WGInterface<[UInt8]>(staticPrivateKey:alicePrivateKey, mtu:1400, initialConfiguration:alicePeers, logLevel:.info, listeningPort: 36001)
				
				let aliceFifo = FIFO<ByteBuffer, Swift.Error>()
				let bobPeers = [(PeerInfo(publicKey: alicePublicKey, ipAddress: "127.0.0.1", port: 36001, internalKeepAlive: .seconds(20)), aliceFifo)]
				let bobInterface = try WGInterface<[UInt8]>(staticPrivateKey:bobPrivateKey, mtu:1400, initialConfiguration:bobPeers, logLevel:.info, listeningPort: 36000)
				
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
				
				let syncThread = await NegentropySyncThread((aliceDBs, try aliceInterface.getChannel(), bobFifo, bobPublicKey, oneWaySync:oneWaySync))
				
				
				
				foo.addTask {
					try syncThread.pthreadWork()
				}
				
				let iterator = aliceFifo.makeSyncConsumerBlocking()
				// Wait to listener initiation
				if let incomingData = try iterator.next() {
					let listenThread = await NegentropyListenThread((bobDBs, try bobInterface.getChannel(), aliceFifo, alicePublicKey, incomingData))
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
		
		@Test mutating func syncRandomData() async throws {
			let aliceSize = 10_000
			let bobSize = 10_000
			try addDBAlice(aliceDBSize: aliceSize, dbName: "testDB")
			try addDBBob(bobDBSize: bobSize, dbName: "testDB")
			
			try await sync(oneWaySync: false)
			try checkSize(aliceDB: aliceDBs[0], bobDB: bobDBs[0], aliceSize: aliceSize + bobSize, bobSize: aliceSize + bobSize)
		}
		
		@Test mutating func syncSameData() async throws {
			let size = 100_000
			try addIdenticalDBs(dbSize: size, dbName: "testDB")
			
			try await sync(oneWaySync: false)
			try checkSize(aliceDB: aliceDBs[0], bobDB: bobDBs[0], aliceSize: size, bobSize: size)
		}
		
		@Test mutating func syncRandomDataDifferentDBSize() async throws {
			let aliceSize = 57_832
			let bobSize = 1_974
			try addDBAlice(aliceDBSize: aliceSize, dbName: "testDB")
			try addDBBob(bobDBSize: bobSize, dbName: "testDB")
			
			try await sync(oneWaySync: false)
			try checkSize(aliceDB: aliceDBs[0], bobDB: bobDBs[0], aliceSize: aliceSize + bobSize, bobSize: aliceSize + bobSize)
		}
		
		@Test mutating func syncAllDBsWithMultipleDatabases() async throws {
			let aliceSizeA = 1234
			let bobSizeA = 1234
			let aliceSizeB = 5678
			let bobSizeB = 5678
			try addDBAlice(aliceDBSize: aliceSizeA, dbName: "testDB_A")
			try addDBBob(bobDBSize: bobSizeA, dbName: "testDB_A")
			try addDBAlice(aliceDBSize: aliceSizeB, dbName: "testDB_B")
			try addDBBob(bobDBSize: bobSizeB, dbName: "testDB_B")
			
			try await sync(oneWaySync: false)
			try checkSize(aliceDB: aliceDBs[0], bobDB: bobDBs[0], aliceSize: aliceSizeA + bobSizeA, bobSize: aliceSizeA + bobSizeA)
			try checkSize(aliceDB: aliceDBs[1], bobDB: bobDBs[1], aliceSize: aliceSizeB + bobSizeB, bobSize: aliceSizeB + bobSizeB)
		}
		
		@Test mutating func syncWithEmptyDB() async throws {
			let aliceSizeA = 1234
			let bobSizeA = 0
			let aliceSizeB = 0
			let bobSizeB = 5678
			try addDBAlice(aliceDBSize: aliceSizeA, dbName: "testDB_A")
			try addDBBob(bobDBSize: bobSizeA, dbName: "testDB_A")
			try addDBAlice(aliceDBSize: aliceSizeB, dbName: "testDB_B")
			try addDBBob(bobDBSize: bobSizeB, dbName: "testDB_B")
			
			try await sync(oneWaySync: false)
			try checkSize(aliceDB: aliceDBs[0], bobDB: bobDBs[0], aliceSize: aliceSizeA + bobSizeA, bobSize: aliceSizeA + bobSizeA)
			try checkSize(aliceDB: aliceDBs[1], bobDB: bobDBs[1], aliceSize: aliceSizeB + bobSizeB, bobSize: aliceSizeB + bobSizeB)
		}
		
		@Test mutating func syncRandomDataOneWay() async throws {
			let aliceSize = 10_000
			let bobSize = 10_000
			try addDBAlice(aliceDBSize: aliceSize, dbName: "testDB")
			try addDBBob(bobDBSize: bobSize, dbName: "testDB")
			
			try await sync(oneWaySync: true)
			try checkSize(aliceDB: aliceDBs[0], bobDB: bobDBs[0], aliceSize: aliceSize + bobSize, bobSize: bobSize)
		}
	}
}
