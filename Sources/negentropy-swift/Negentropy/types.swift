import Foundation
import RAW
import RAW_blake2
import QuickLMDB
public typealias WGHasher<K> = RAW_blake2.Hasher<S, K> where K:RAW_staticbuff

let ID_SIZE:Int = 32
let FINGERPRINT_SIZE:Int = 16

enum Mode: Int {
	case skip = 0
	case fingerprint = 1
	case idList = 2
}

@RAW_staticbuff(bytes: 32)
public struct ID: Sendable, Equatable, Comparable {}

@RAW_staticbuff(bytes: 8)
@RAW_staticbuff_fixedwidthinteger_type<UInt64>(bigEndian: true)
public struct TimeStamp: Sendable, Equatable, Comparable {}

protocol StorageItem: Sendable, Equatable, Comparable, MDB_comparable
where StoredIdType: RAW_staticbuff, StoredIdType:Equatable, StoredIdType:Comparable, StoredIdType.RAW_staticbuff_storetype == ID.RAW_staticbuff_storetype,
	  StoredTimeStampType: RAW_staticbuff, StoredTimeStampType: Equatable, StoredTimeStampType: Comparable, StoredTimeStampType.RAW_staticbuff_storetype == TimeStamp.RAW_staticbuff_storetype {
	
	associatedtype StoredIdType
	associatedtype StoredTimeStampType
	var id:StoredIdType { get }
	var timestamp:StoredTimeStampType { get }
	
	init(timestamp: UInt64)
	
	init(timestamp: UInt64, id: StoredIdType) throws
	
	func getId() -> [UInt8]
}

@RAW_staticbuff(concat: ID.self, TimeStamp.self)
public struct Item:Sendable, StorageItem {
	public static let MDB_compare_f:MDB_compare_ftype = { a, b in
		guard let a, let b else { return 0 }
		
		let ida = ID(RAW_staticbuff: a.pointee.mv_data)
		let tsa = TimeStamp(RAW_staticbuff: a.pointee.mv_data.advanced(by: 32))
		
		let idb = ID(RAW_staticbuff: b.pointee.mv_data)
		let tsb = TimeStamp(RAW_staticbuff: b.pointee.mv_data.advanced(by: 32))
		
		if(tsa != tsb) {
			if(tsa < tsb) {
				return -1
			} else {
				return 1
			}
		} else {
			if(ida < idb) {
				return -1
			} else if (ida > idb) {
				return 1
			}
		}
		return 0
	}
	
	typealias StoredIdType = ID
	typealias StoredTimeStampType = TimeStamp
	
	let id:ID
	let timestamp:TimeStamp
	
	
	init(timestamp: UInt64 = 0) {
		self.timestamp = TimeStamp(RAW_native: timestamp)
		self.id = ID(RAW_staticbuff: ID.RAW_staticbuff_zeroed())
	}
	
	init(timestamp: UInt64, id: ID) throws {
		self.timestamp = TimeStamp(RAW_native: timestamp)
		var constructedId:ID? = nil
		id.RAW_access_staticbuff({ myStructBuff in
			constructedId = ID(RAW_staticbuff: myStructBuff)
		})
		self.id = constructedId!
	}
	
	public func getId() -> [UInt8] {
		id.RAW_access( { myStructBuff in
			return Array(UnsafeBufferPointer(start: myStructBuff.baseAddress!, count: ID_SIZE))
		})
	}
	
	static public func ==(lhs: Item, rhs: Item) -> Bool {
		return lhs.timestamp == rhs.timestamp &&
			lhs.id == rhs.id
	}
	
	static public func < (lhs: Item, rhs: Item) -> Bool {
		if lhs.timestamp != rhs.timestamp {
			return lhs.timestamp < rhs.timestamp
		} else {
			return lhs.id < rhs.id
		}
	}
}

@RAW_staticbuff(bytes: 16)
public struct Fingerprint: Sendable, Comparable, Equatable { }

