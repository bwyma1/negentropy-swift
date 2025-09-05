import Testing
import RAW
@testable import negentropy_swift

@Suite("WG Swift Tests", .serialized)
struct NegentropySwiftTests {}

@Test func encodeDecodeBound() async throws {
	let id:ID = try generateSecureRandomBytes(as: ID.self)
	let item = try Item(timestamp: UInt64(100), id: id)
	let bound = Bound(item: item)
	
	let vecA = VectorStorage()
	
	var ne1 = try Negentropy(storage: vecA, frameSizeLimit: 20_000)
	
	var encoded = ne1.encodeBound(bound)
	
	let decoded = try ne1.decodeBound(encoded: &encoded)

	#expect(decoded == bound)
}

@Test func testWithSameData() async throws {
	var vecA = VectorStorage()
	var vecB = VectorStorage()
	for i in 0..<1000 {
		let id:ID = try generateSecureRandomBytes(as: ID.self)
		let item = try Item(timestamp: UInt64(i+1), id: id)
		vecA.insertItem(item)
		vecB.insertItem(item)
	}
	
	try vecA.sort()
	try vecB.sort()
	
	var ne1 = try Negentropy(storage: vecA, frameSizeLimit: 20_000)
	var ne2 = try Negentropy(storage: vecB, frameSizeLimit: 20_000)
	
	var msg = try ne1.initiate()
	
	while(true) {
		msg = try ne2.reconcile(query: msg)
		
		var have:[ID] = []
		var need:[ID] = []
		let newMsg = try ne1.reconcile(query: msg, haveIds: &have, needIds: &need)
		
		#expect(have.count == 0)
		#expect(need.count == 0)
		
		if(newMsg == nil) { break }
		else { msg = newMsg! }
	}
}

@Test func testWithDifferentData() async throws {
	var vecA = VectorStorage()
	var vecB = VectorStorage()
	for i in 0..<1000 {
		let id1:ID = try generateSecureRandomBytes(as: ID.self)
		let item1 = try Item(timestamp: UInt64(i+1), id: id1)
		vecA.insertItem(item1)
		let id2:ID = try generateSecureRandomBytes(as: ID.self)
		let item2 = try Item(timestamp: UInt64(i+1), id: id2)
		vecB.insertItem(item2)
	}
	
	try vecA.sort()
	try vecB.sort()
	
	var ne1 = try Negentropy(storage: vecA, frameSizeLimit: 20_000)
	var ne2 = try Negentropy(storage: vecB, frameSizeLimit: 20_000)
	
	var msg = try ne1.initiate()
	
	while(true) {
		msg = try ne2.reconcile(query: msg)
		
		var have:[ID] = []
		var need:[ID] = []
		let newMsg = try ne1.reconcile(query: msg, haveIds: &have, needIds: &need)
		
		for id in need {
			// Find the item for the id and insert into the other vector
			if let item = vecB.itemFor(id: id) {
				vecA.insertItem(item)
			}
		}
		
		for id in have {
			if let item = vecA.itemFor(id: id) {
				vecB.insertItem(item)
			}
		}
		
		if(newMsg == nil) { break }
		else { msg = newMsg! }
	}
	
	try vecA.sort()
	try vecB.sort()
	
	#expect(vecA.size() == vecB.size())
	for i in 0..<vecA.size() {
		#expect(vecA.getItem(i) == vecB.getItem(i))
	}
}

@Test func testWithPartialDataDifferences() async throws {
	var vecA = VectorStorage()
	var vecB = VectorStorage()
	// Same items
	for i in 0..<1000 {
		let id:ID = try generateSecureRandomBytes(as: ID.self)
		let item = try Item(timestamp: UInt64(i+1), id: id)
		vecA.insertItem(item)
		vecB.insertItem(item)
	}
	// Different items
	for i in 0..<1000 {
		let id1:ID = try generateSecureRandomBytes(as: ID.self)
		let item1 = try Item(timestamp: UInt64(i+1001), id: id1)
		vecA.insertItem(item1)
		let id2:ID = try generateSecureRandomBytes(as: ID.self)
		let item2 = try Item(timestamp: UInt64(i+1001), id: id2)
		vecB.insertItem(item2)
	}
	// Same items
	for i in 0..<1000 {
		let id:ID = try generateSecureRandomBytes(as: ID.self)
		let item = try Item(timestamp: UInt64(i+2001), id: id)
		vecA.insertItem(item)
		vecB.insertItem(item)
	}
	
	try vecA.sort()
	try vecB.sort()
	
	var ne1 = try Negentropy(storage: vecA, frameSizeLimit: 20_000)
	var ne2 = try Negentropy(storage: vecB, frameSizeLimit: 20_000)
	
	var msg = try ne1.initiate()
	
	while(true) {
		msg = try ne2.reconcile(query: msg)
		
		var have:[ID] = []
		var need:[ID] = []
		let newMsg = try ne1.reconcile(query: msg, haveIds: &have, needIds: &need)
		
		for id in need {
			// Find the item for the id and insert into the other vector
			if let item = vecB.itemFor(id: id) {
				vecA.insertItem(item)
			}
		}
		
		for id in have {
			if let item = vecA.itemFor(id: id) {
				vecB.insertItem(item)
			}
		}
		
		if(newMsg == nil) { break }
		else { msg = newMsg! }
	}
	
	try vecA.sort()
	try vecB.sort()
	
	#expect(vecA.size() == vecB.size())
	#expect(vecA.size() == 4000)
	for i in 0..<vecA.size() {
		#expect(vecA.getItem(i) == vecB.getItem(i))
	}
}

@Test func testWithDuplicateTimestamps() async throws {
	var vecA = VectorStorage()
	var vecB = VectorStorage()
	for i in 0..<100 {
		let id1:ID = try generateSecureRandomBytes(as: ID.self)
		let item1 = try Item(timestamp: UInt64(i+1), id: id1)
		vecA.insertItem(item1)
		let id2:ID = try generateSecureRandomBytes(as: ID.self)
		let item2 = try Item(timestamp: UInt64(i+1), id: id2)
		vecB.insertItem(item2)
	}
	// Another set of items with the same timestamps as the previous set
	for i in 0..<100 {
		let id1:ID = try generateSecureRandomBytes(as: ID.self)
		let item1 = try Item(timestamp: UInt64(i+1), id: id1)
		vecA.insertItem(item1)
		let id2:ID = try generateSecureRandomBytes(as: ID.self)
		let item2 = try Item(timestamp: UInt64(i+1), id: id2)
		vecB.insertItem(item2)
	}
	
	try vecA.sort()
	try vecB.sort()
	
	var ne1 = try Negentropy(storage: vecA, frameSizeLimit: 20_000)
	var ne2 = try Negentropy(storage: vecB, frameSizeLimit: 20_000)
	
	var msg = try ne1.initiate()
	
	while(true) {
		msg = try ne2.reconcile(query: msg)
		
		var have:[ID] = []
		var need:[ID] = []
		let newMsg = try ne1.reconcile(query: msg, haveIds: &have, needIds: &need)
		
		for id in need {
			// Find the item for the id and insert into the other vector
			if let item = vecB.itemFor(id: id) {
				vecA.insertItem(item)
			}
		}
		
		for id in have {
			if let item = vecA.itemFor(id: id) {
				vecB.insertItem(item)
			}
		}
		
		if(newMsg == nil) { break }
		else { msg = newMsg! }
	}
	
	try vecA.sort()
	try vecB.sort()
	
	#expect(vecA.size() == vecB.size())
	for i in 0..<vecA.size() {
		#expect(vecA.getItem(i) == vecB.getItem(i))
	}
}
