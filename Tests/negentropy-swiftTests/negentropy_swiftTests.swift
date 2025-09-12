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

extension NegentropySwiftTests {
	@Suite("Negentropy LMDB Tests",
		   .serialized
	)
	struct LMDBExtensionTests {
		
		private let logger:Logger
		private let env:Environment
		private let testDB:Database.Strict<Item, Data>
		
		init() throws {
			let base = Path(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path)
			let finalPath = base.appendingPathComponent("test-db1.mdb")
			let memoryMapSize = size_t(finalPath.getFileSize() + 5 * 1024 * 1024) // add 5mb to the file
			env = try Environment(path:finalPath.path(), flags:[.noSubDir], mapSize:memoryMapSize, maxReaders:16, maxDBs:1, mode:[.ownerReadWriteExecute, .groupReadExecute, .otherReadExecute])
			let newTrans = try Transaction(env:env, readOnly:false)
			testDB = try! Database.Strict<Item, Data>(env:env, name:nil, flags:[.create], tx:newTrans)
			try testDB.deleteAllEntries(tx:newTrans)
			var makelogger = Logger(label: "negentropy-swift-tests")
			makelogger.logLevel = .debug
			logger = makelogger
			try testDB.cursor(tx:newTrans) { cursor in
				for i in 1..<11 {
					// Make key
					let id:ID = try generateSecureRandomBytes(as: ID.self)
					let item = try Item(timestamp: UInt64(i*100), id: id)
					
					logger.trace("writing example data")
					try cursor.setEntry(key:item, value:Data(RAW_native: UInt64(i)), flags:[])
				}
			}
			try newTrans.commit()
		}
		
		@Test func size() throws {
			#expect(try testDB.size() == 10)
		}
		
		@Test func first() throws {
			#expect(try testDB.first().timestamp.RAW_native() == 100)
		}
		
		@Test func last() throws {
			#expect(try testDB.last().timestamp.RAW_native() == 1000)
		}
		
		@Test func shift() throws {
			let curr = try testDB.first()
			#expect(try testDB.shift(curr:curr, amount:0).timestamp.RAW_native() == 100)
			#expect(try testDB.shift(curr:curr, amount:3).timestamp.RAW_native() == 400)
			#expect(try testDB.shift(curr:curr, amount:7).timestamp.RAW_native() == 800)
		}
		
		@Test func prev() throws {
			let curr = try testDB.last()
			#expect(try testDB.prev(curr:curr).timestamp.RAW_native() == 900)
			#expect(try testDB.prev(curr:testDB.prev(curr:curr)).timestamp.RAW_native() == 800)
		}
		
		@Test func numElements() throws {
			let key1 = try testDB.first()
			var key2 = try testDB.last()
			
			#expect(try testDB.numElements(begin:key1, end:key1) == 1)
			#expect(try testDB.numElements(begin:key1, end:key2) == 10)
			
			key2 = try testDB.prev(curr:key2)
			#expect(try testDB.numElements(begin:key1, end:key2) == 9)
		}
		
		@Test func findLowerBound() throws {
			let key1 = try testDB.first()
			let key2 = try testDB.last()
			
			let id:ID = try generateSecureRandomBytes(as: ID.self)
			var item = try Item(timestamp: UInt64(450), id: id)
			#expect(try testDB.findLowerBound(begin:key1, end:key2, value:item).timestamp.RAW_native() == 500)
			
			item = try Item(timestamp: UInt64(670), id: id)
			#expect(try testDB.findLowerBound(begin:key1, end:key2, value:item).timestamp.RAW_native() == 700)
		}
		
		@Test func fingerPrint() throws {
			let key1 = try testDB.first()
			let key2 = try testDB.last()
			let key3 = try testDB.shift(curr:key1, amount:5)
			
			#expect(try testDB.fingerprint(begin:key1, end:key2) != testDB.fingerprint(begin:key1, end:key3))
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
		private let testDB1:Database.Strict<Item, Data>
		
		private let env2:Environment
		private let testDB2:Database.Strict<Item, Data>
		
		init() throws {
			let base = Path(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path)
			var finalPath = base.appendingPathComponent("test-db1.mdb")
			let memoryMapSize = size_t(finalPath.getFileSize() + 5 * 1024 * 1024) // add 5mb to the file
			env1 = try Environment(path:finalPath.path(), flags:[.noSubDir], mapSize:memoryMapSize, maxReaders:16, maxDBs:1, mode:[.ownerReadWriteExecute, .groupReadExecute, .otherReadExecute])
			var newTrans = try Transaction(env:env1, readOnly:false)
			testDB1 = try! Database.Strict<Item, Data>(env:env1, name:nil, flags:[.create], tx:newTrans)
			try testDB1.deleteAllEntries(tx:newTrans)
			
			try newTrans.commit()
			
			finalPath = base.appendingPathComponent("test-db2.mdb")
			env2 = try Environment(path:finalPath.path(), flags:[.noSubDir], mapSize:memoryMapSize, maxReaders:16, maxDBs:1, mode:[.ownerReadWriteExecute, .groupReadExecute, .otherReadExecute])
			newTrans = try Transaction(env:env2, readOnly:false)
			testDB2 = try! Database.Strict<Item, Data>(env:env2, name:nil, flags:[.create], tx:newTrans)
			try testDB2.deleteAllEntries(tx:newTrans)
			
			try newTrans.commit()
			
			var makelogger = Logger(label: "negentropy-swift-tests")
			makelogger.logLevel = .debug
			logger = makelogger
		}
		
		// Helper write func
		func initDB(size:Int, random:Bool = true) throws {
			if(random) {
				var newTrans = try Transaction(env:env1, readOnly:false)
				try testDB1.deleteAllEntries(tx:newTrans)
				try testDB1.cursor(tx:newTrans) { cursor in
					for i in 0..<size {
						// Make key
						let id:ID = try generateSecureRandomBytes(as: ID.self)
						let item = try Item(timestamp: UInt64(100), id: id)
						try cursor.setEntry(key:item, value:Data(RAW_native: UInt64(i)), flags:[])
					}
				}
				try newTrans.commit()
				newTrans = try Transaction(env:env2, readOnly:false)
				try testDB2.deleteAllEntries(tx:newTrans)
				try testDB2.cursor(tx:newTrans) { cursor in
					for i in 0..<size {
						// Make key
						let id:ID = try generateSecureRandomBytes(as: ID.self)
						let item = try Item(timestamp: UInt64(100), id: id)
						try cursor.setEntry(key:item, value:Data(RAW_native: UInt64(i)), flags:[])
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
						for i in 0..<size {
							// Make key
							let id:ID = try generateSecureRandomBytes(as: ID.self)
							let item = try Item(timestamp: UInt64(100), id: id)
							try cursor1.setEntry(key:item, value:Data(RAW_native: UInt64(i)), flags:[])
							try cursor2.setEntry(key:item, value:Data(RAW_native: UInt64(i)), flags:[])
						}
					}
				}
				try newTrans1.commit()
				try newTrans2.commit()
			}
		}
		
//	    Helper sync function for testing storages
		func sync() throws {
			var ne1 = try Negentropy(storage: testDB1, frameSizeLimit: 20_000)
			var ne2 = try Negentropy(storage: testDB2, frameSizeLimit: 20_000)
			
			var msg = try ne1.initiate()

			while(true) {
				msg = try ne2.reconcile(query: msg)
				
				var have:[ID] = []
				var need:[ID] = []
				let newMsg = try ne1.reconcile(query: msg, haveIds: &have, needIds: &need)
				
				for id in need {
					// Find the item for the id and insert into the other vector
					if let item = try testDB2.itemFor(id) {
						let newTrans = try Transaction(env:env1, readOnly:false)
						try testDB1.cursor(tx:newTrans) { cursor in
							try cursor.setEntry(key:item, value:Data(RAW_native: UInt64(1)), flags:[])
						}
						try newTrans.commit()
					}
				}
				
				for id in have {
					// Find the item for the id and insert into the other vector
					if let item = try testDB1.itemFor(id) {
						let newTrans = try Transaction(env:env2, readOnly:false)
						try testDB2.cursor(tx:newTrans) { cursor in
							try cursor.setEntry(key:item, value:Data(RAW_native: UInt64(1)), flags:[])
						}
						try newTrans.commit()
					}
				}
				
				if(newMsg == nil) { break }
				else { msg = newMsg! }
			}
		}
		
		@Test func syncRandomData() async throws {
			try initDB(size:50)
			#expect(try testDB1.size() == 50)
			#expect(try testDB2.size() == 50)
			
			try sync()
		}
	}
}
