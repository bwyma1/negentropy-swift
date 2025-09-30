import Testing
import RAW
import class Foundation.FileManager
import Logging
import QuickLMDB
import bedrock
@testable import negentropy_swift

@RAW_staticbuff(bytes: 8)
@RAW_staticbuff_fixedwidthinteger_type<UInt64>(bigEndian: true)
public struct Data: Sendable, Equatable, Comparable {}

@Suite("Negentropy Swift Tests", .serialized)
struct NegentropySwiftTests {}

@RAW_staticbuff(bytes: 8)
@RAW_staticbuff_fixedwidthinteger_type<UInt64>(bigEndian: true)
@MDB_comparable
public struct TestingID: Sendable, StorageID {}

extension NegentropySwiftTests {
	@Suite("Negentropy LMDB Tests",
		   .serialized
	)
	struct LMDBExtensionTests {
		
		private let logger:Logger
		private let env:Environment
		private let testDB:Database.Strict<TestingID, Data>
		
		init() throws {
			let base = Path(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path)
			let finalPath = base.appendingPathComponent("test-db1.mdb")
			let memoryMapSize = size_t(finalPath.getFileSize() + 5 * 1024 * 1024) // add 5mb to the file
			env = try Environment(path:finalPath.path(), flags:[.noSubDir], mapSize:memoryMapSize, maxReaders:16, maxDBs:1, mode:[.ownerReadWriteExecute, .groupReadExecute, .otherReadExecute])
			let newTrans = try Transaction(env:env, readOnly:false)
			testDB = try! Database.Strict<TestingID, Data>(env:env, name:nil, flags:[.create], tx:newTrans)
			try testDB.deleteAllEntries(tx:newTrans)
			var makelogger = Logger(label: "negentropy-swift-tests")
			makelogger.logLevel = .debug
			logger = makelogger
			try testDB.cursor(tx:newTrans) { cursor in
				for i in 1..<11 {
					// Make key
					let id:TestingID = TestingID(RAW_native: UInt64(i * 10))
					
					logger.trace("writing example data")
					try cursor.setEntry(key:id, value:Data(RAW_native: UInt64(i)), flags:[])
				}
			}
			try newTrans.commit()
		}
		
		@Test func size() throws {
			#expect(try testDB.size() == 10)
		}
		
		@Test func first() throws {
			#expect(try testDB.first().RAW_native() == 10)
		}
		
		@Test func last() throws {
			#expect(try testDB.last().RAW_native() == 100)
		}
		
		@Test func shift() throws {
			let curr = try testDB.first()
			#expect(try testDB.shift(curr:curr, amount:0)!.RAW_native() == 10)
			#expect(try testDB.shift(curr:curr, amount:3)!.RAW_native() == 40)
			#expect(try testDB.shift(curr:curr, amount:7)!.RAW_native() == 80)
			#expect(try testDB.shift(curr:curr, amount:10) == nil)
		}
		
		@Test func prev() throws {
			let curr = try testDB.last()
			#expect(try testDB.prev(curr:curr).RAW_native() == 90)
			#expect(try testDB.prev(curr:testDB.prev(curr:curr)).RAW_native() == 80)
		}
		
		@Test func numElements() throws {
			let key1 = try testDB.first()
			var key2 = try testDB.last()
			
			#expect(try testDB.numElements(begin:key1, end:key1) == 0)
			#expect(try testDB.numElements(begin:key1, end:key2) == 9)
			
			key2 = try testDB.prev(curr:key2)
			#expect(try testDB.numElements(begin:key1, end:key2) == 8)
		}
		
		@Test func findLowerBound() throws {
			let key1 = try testDB.first()
			let key2 = try testDB.last()
			
			let id1:TestingID = TestingID(RAW_native: 45)
			#expect(try testDB.findLowerBound(begin:key1, end:key2, value:id1)!.RAW_native() == 50)
			
			let id2:TestingID = TestingID(RAW_native: 67)
			#expect(try testDB.findLowerBound(begin:key1, end:key2, value:id2)!.RAW_native() == 70)
		}
		
		@Test func fingerPrint() throws {
			let key1 = try testDB.first()
			let key2 = try testDB.last()
			let key3 = try testDB.shift(curr:key1, amount:5)
			
			#expect(try testDB.fingerprint(begin:key1, end:key2) != testDB.fingerprint(begin:key1, end:key3))
			#expect(try testDB.fingerprint(begin:key1, end:key2) != testDB.fingerprint(begin:key1, end:nil))
		}
	}
}

extension NegentropySwiftTests {
	@Suite("Negentropy Live LMDB Tests",
		   .serialized
	)
	struct LiveNegentropyTests {
		
		private let logger:Logger
		private let env1:Environment
		private let testDB1:Database.Strict<StoredIDExample, Data>
		
		private let env2:Environment
		private let testDB2:Database.Strict<StoredIDExample, Data>
		
		init() throws {
			let base = Path(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path)
			var finalPath = base.appendingPathComponent("test-db1.mdb")
			let memoryMapSize = size_t(finalPath.getFileSize() + 5 * 1024 * 1024 * 1024) // add 5mb to the file
			env1 = try Environment(path:finalPath.path(), flags:[.noSubDir], mapSize:memoryMapSize, maxReaders:16, maxDBs:1, mode:[.ownerReadWriteExecute, .groupReadExecute, .otherReadExecute])
			var newTrans = try Transaction(env:env1, readOnly:false)
			testDB1 = try! Database.Strict<StoredIDExample, Data>(env:env1, name:nil, flags:[.create], tx:newTrans)
			try testDB1.deleteAllEntries(tx:newTrans)
			
			try newTrans.commit()
			
			finalPath = base.appendingPathComponent("test-db2.mdb")
			env2 = try Environment(path:finalPath.path(), flags:[.noSubDir], mapSize:memoryMapSize, maxReaders:16, maxDBs:1, mode:[.ownerReadWriteExecute, .groupReadExecute, .otherReadExecute])
			newTrans = try Transaction(env:env2, readOnly:false)
			testDB2 = try! Database.Strict<StoredIDExample, Data>(env:env2, name:nil, flags:[.create], tx:newTrans)
			try testDB2.deleteAllEntries(tx:newTrans)
			
			try newTrans.commit()
			
			var makelogger = Logger(label: "negentropy-swift-tests")
			makelogger.logLevel = .notice
			logger = makelogger
		}
		
		func logID(id:StoredIDExample) {
			id.RAW_access({ptr in
				logger.trace("\(Array(UnsafeBufferPointer(start: ptr.baseAddress!, count: ptr.count)))")
			})
		}
		
		// Helper write func
		func initDB(db1Size:Int, db2Size:Int, random:Bool = true) throws {
			if(random) {
				var newTrans = try Transaction(env:env1, readOnly:false)
				try testDB1.deleteAllEntries(tx:newTrans)
				try testDB1.cursor(tx:newTrans) { cursor in
					for i in 0..<db1Size {
						// Make key
						let id:StoredIDExample = try generateSecureRandomBytes(as: StoredIDExample.self)
						logID(id: id)
						try cursor.setEntry(key:id, value:Data(RAW_native: UInt64(i)), flags:[])
					}
				}
				try newTrans.commit()
				newTrans = try Transaction(env:env2, readOnly:false)
				try testDB2.deleteAllEntries(tx:newTrans)
				try testDB2.cursor(tx:newTrans) { cursor in
					for i in 0..<db2Size {
						// Make key
						let id:StoredIDExample = try generateSecureRandomBytes(as: StoredIDExample.self)
						logID(id: id)
						try cursor.setEntry(key:id, value:Data(RAW_native: UInt64(i)), flags:[])
					}
				}
				try newTrans.commit()
			} else {
				let newTrans1 = try Transaction(env:env1, readOnly:false)
				let newTrans2 = try Transaction(env:env2, readOnly:false)
				try testDB1.deleteAllEntries(tx:newTrans1)
				try testDB2.deleteAllEntries(tx:newTrans2)
				try testDB1.cursor(tx:newTrans1) { cursor1 in
					try testDB1.cursor(tx:newTrans2) { cursor2 in
						for i in 0..<db1Size {
							// Make key
							let id:StoredIDExample = try generateSecureRandomBytes(as: StoredIDExample.self)
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
		func sync() throws {
			var ne1 = try Negentropy(storage: testDB1, frameSizeLimit: 20_000, buckets: 20, logLevel:.notice)
			var ne2 = try Negentropy(storage: testDB2, frameSizeLimit: 20_000, buckets: 20, logLevel:.notice)
			
			var msg = try ne1.initiate()

			while(true) {
				msg = try ne2.reconcile(query: msg)
				
				var have:[StoredIDExample] = []
				var need:[StoredIDExample] = []
				let newMsg = try ne1.reconcile(query: msg, haveIds: &have, needIds: &need)
				
				for id in need {
					logID(id: id)
					// Find the item for the id and insert into the other vector
					let tx2 = try Transaction(env:env2, readOnly:false)
					let value = try testDB2.loadEntry(key: id, tx: tx2)
					
					let tx1 = try Transaction(env:env1, readOnly:false)
					try testDB1.cursor(tx:tx1) { cursor in
						try cursor.setEntry(key:id, value:value, flags:[])
					}
					try tx1.commit()
				}
				
				for id in have {
					logID(id: id)
					// Find the item for the id and insert into the other vector
					let tx1 = try Transaction(env:env1, readOnly:false)
					let value = try testDB1.loadEntry(key: id, tx: tx1)
					
					let tx2 = try Transaction(env:env2, readOnly:false)
					try testDB2.cursor(tx:tx2) { cursor in
						try cursor.setEntry(key:id, value:value, flags:[])
					}
					try tx2.commit()
				}
				
				if(newMsg == nil) { break }
				else { msg = newMsg! }
			}
		}
		
		// nlog(n) run time
		@Test func syncRandomData() async throws {
			let db1Size = 100_000
			let db2Size = 100_000
			try initDB(db1Size: db1Size, db2Size:db2Size, random:true)
			#expect(try testDB1.size() == db1Size)
			#expect(try testDB2.size() == db2Size)
			
			try sync()
			#expect(try testDB1.size() == db1Size + db2Size)
			#expect(try testDB2.size() == db1Size + db2Size)
		}
		
		@Test func syncSameData() async throws {
			let db1Size = 100_000
			let db2Size = 100_000
			try initDB(db1Size: db1Size, db2Size:db2Size, random:false)
			#expect(try testDB1.size() == db1Size)
			#expect(try testDB2.size() == db2Size)
			
			try sync()
			#expect(try testDB1.size() == db1Size)
			#expect(try testDB2.size() == db2Size)
		}
		
		@Test func syncRandomDataRandomSize() async throws {
			let db1Size = 57295
			let db2Size = 1294
			try initDB(db1Size: db1Size, db2Size:db2Size, random:true)
			#expect(try testDB1.size() == db1Size)
			#expect(try testDB2.size() == db2Size)
			
			try sync()
			#expect(try testDB1.size() == db1Size + db2Size)
			#expect(try testDB2.size() == db1Size + db2Size)
		}
	}
}
