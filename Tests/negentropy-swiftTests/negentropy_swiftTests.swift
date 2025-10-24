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
@testable import negentropy_swift

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
		
//		private let logger:Logger
//		private let env:Environment
//		private let testDB:Database.Strict<TestingID, Data>
//		
//		init() throws {
//			let base = Path(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path)
//			let finalPath = base.appendingPathComponent("test-db1.mdb")
//			let memoryMapSize = size_t(finalPath.getFileSize() + 5 * 1024 * 1024) // add 5mb to the file
//			env = try Environment(path:finalPath.path(), flags:[.noSubDir], mapSize:memoryMapSize, maxReaders:16, maxDBs:1, mode:[.ownerReadWriteExecute, .groupReadExecute, .otherReadExecute])
//			let newTrans = try Transaction(env:env, readOnly:false)
//			testDB = try! Database.Strict<TestingID, Data>(env:env, name:nil, flags:[.create], tx:newTrans)
//			try testDB.deleteAllEntries(tx:newTrans)
//			var makelogger = Logger(label: "negentropy-swift-tests")
//			makelogger.logLevel = .debug
//			logger = makelogger
//			try testDB.cursor(tx:newTrans) { cursor in
//				for i in 1..<11 {
//					// Make key
//					let id:TestingID = TestingID(RAW_native: UInt64(i * 10))
//					
//					logger.trace("writing example data")
//					try cursor.setEntry(key:id, value:Data(RAW_native: UInt64(i)), flags:[])
//				}
//			}
//			try newTrans.commit()
//		}
		@Test func newTest() {
			let idmin:TestingID = TestingID.RAW_comparable_fixed_theoretical_min()
			let idmax:TestingID = TestingID.RAW_comparable_fixed_theoretical_max()
			idmin.MDB_access { (mdbvalmin:consuming MDB_val) in
				idmax.MDB_access { (mdbvalmax:consuming MDB_val) in
					#expect(TestingID.MDB_compare_f(&mdbvalmin, &mdbvalmax) < 0)
				}
			}
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
		private let aliceDB:Database.Strict<TestingID, Data>
		
		private let bobEnv:Environment
		private let bobDB:Database.Strict<TestingID, Data>
		
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
			aliceEnv = try Environment(path:finalPath.path(), flags:[.noSubDir], mapSize:memoryMapSize, maxReaders:16, maxDBs:1, mode:[.ownerReadWriteExecute, .groupReadExecute, .otherReadExecute])
			var newTrans = try Transaction(env:aliceEnv, readOnly:false)
			aliceDB = try! Database.Strict<TestingID, Data>(env:aliceEnv, name:nil, flags:[.create], tx:newTrans)
			try aliceDB.deleteAllEntries(tx:newTrans)
			
			try newTrans.commit()
			
			finalPath = base.appendingPathComponent("bobDB.mdb")
			bobEnv = try Environment(path:finalPath.path(), flags:[.noSubDir], mapSize:memoryMapSize, maxReaders:16, maxDBs:1, mode:[.ownerReadWriteExecute, .groupReadExecute, .otherReadExecute])
			newTrans = try Transaction(env:bobEnv, readOnly:false)
			bobDB = try! Database.Strict<TestingID, Data>(env:bobEnv, name:nil, flags:[.create], tx:newTrans)
			try bobDB.deleteAllEntries(tx:newTrans)
			
			try newTrans.commit()
			
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
		
		// Helper write func
		func initDB(db1Size:Int, db2Size:Int, random:Bool = true) throws {
			if(random) {
				var newTrans = try Transaction(env:aliceEnv, readOnly:false)
				try aliceDB.deleteAllEntries(tx:newTrans)
				try aliceDB.cursor(tx:newTrans) { cursor in
					for i in 0..<db1Size {
						// Make key
						let id:TestingID = try generateSecureRandomBytes(as: TestingID.self)
//						let id:TestingID = TestingID(RAW_native: UInt64(i * 10))
						logID(id: id)
						try cursor.setEntry(key:id, value:Data(RAW_native: UInt64(i)), flags:[])
					}
				}
				try newTrans.commit()
				newTrans = try Transaction(env:bobEnv, readOnly:false)
				try bobDB.deleteAllEntries(tx:newTrans)
				try bobDB.cursor(tx:newTrans) { cursor in
					for i in 0..<db2Size {
						// Make key
						let id:TestingID = try generateSecureRandomBytes(as: TestingID.self)
//						let id:TestingID = TestingID(RAW_native: UInt64(i * 10))
						logID(id: id)
						try cursor.setEntry(key:id, value:Data(RAW_native: UInt64(i)), flags:[])
					}
				}
				try newTrans.commit()
			} else {
				let newTrans1 = try Transaction(env:aliceEnv, readOnly:false)
				let newTrans2 = try Transaction(env:bobEnv, readOnly:false)
				try aliceDB.deleteAllEntries(tx:newTrans1)
				try bobDB.deleteAllEntries(tx:newTrans2)
				try aliceDB.cursor(tx:newTrans1) { cursor1 in
					try aliceDB.cursor(tx:newTrans2) { cursor2 in
						for i in 0..<db1Size {
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
			}
		}
		
//	    Helper sync function for testing storages
		func sync() async throws {
			
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
				
				let syncThread = await NegentropySyncThread(([aliceDB], try aliceInterface.getChannel(), bobFifo, bobPublicKey))
				
				let listenThread = await NegentropyListenThread(([bobDB], try bobInterface.getChannel(), aliceFifo, alicePublicKey))
				
				foo.addTask {
					try syncThread.pthreadWork()
				}
				
				try listenThread.pthreadWork()
				
				foo.cancelAll()
				try await foo.waitForAll()
				return
			})
		}
		
		@Test func syncRandomData() async throws {
			let aliceSize = 9000
			let bobSize = 1
			try initDB(db1Size: aliceSize, db2Size:bobSize, random:true)
			
			try await sync()
//			let aliceTrans = try Transaction(env:aliceEnv, readOnly:false)
//			let bobTrans = try Transaction(env:bobEnv, readOnly:false)
//			
//			#expect(try dbStatistics(tx: aliceTrans).ms_entries == db1Size + db2Size)
//			#expect(try dbStatistics(tx: bobTrans).ms_entries == db1Size + db2Size)
//			aliceTrans.commit()
//			bobTrans.commit()
		}
		
//		@Test func syncSameData() async throws {
//			let db1Size = 100_000
//			let db2Size = 100_000
//			try initDB(db1Size: db1Size, db2Size:db2Size, random:false)
//			#expect(try aliceDB.size() == db1Size)
//			#expect(try bobDB.size() == db2Size)
//			
//			try sync()
//			#expect(try aliceDB.size() == db1Size)
//			#expect(try bobDB.size() == db2Size)
//		}
//		
//		@Test func syncRandomDataRandomSize() async throws {
//			let db1Size = 57295
//			let db2Size = 1294
//			try initDB(db1Size: db1Size, db2Size:db2Size, random:true)
//			#expect(try aliceDB.size() == db1Size)
//			#expect(try bobDB.size() == db2Size)
//			
//			try sync()
//			#expect(try aliceDB.size() == db1Size + db2Size)
//			#expect(try bobDB.size() == db1Size + db2Size)
//		}
//		
//		@Test func syncWithEmptyDB() async throws {
//			let db1Size = 0
//			let db2Size = 0
//			try initDB(db1Size: db1Size, db2Size:db2Size, random:true)
//			#expect(try aliceDB.size() == db1Size)
//			#expect(try bobDB.size() == db2Size)
//			
//			try sync()
//			print(try aliceDB.size())
//			print(try bobDB.size())
//			#expect(try aliceDB.size() == db1Size + db2Size)
//			#expect(try bobDB.size() == db1Size + db2Size)
//		}
	}
}
