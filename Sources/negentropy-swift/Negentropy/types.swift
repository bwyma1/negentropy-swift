import Foundation
import RAW

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

@RAW_staticbuff(concat: ID.self, TimeStamp.self)
public struct Item:Sendable, Equatable, Comparable {
	var id:ID
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

// Bound for checking against items
public struct Bound: Equatable, Comparable {
	public var item:Item
	public var idLen:Int
	
	/// `Bound(timestamp:idSlice:)`
	init(timestamp:TimeStamp = TimeStamp(RAW_native: 0), idSlice:[UInt8] = []) throws {
		let suppliedLen = idSlice.count
		guard suppliedLen <= ID_SIZE else {
			throw NegentropyError.badIDSize
		}
		
		self.idLen = idSlice.count
		self.item = Item(timestamp: timestamp.RAW_native())
		
		self.item.RAW_access_mutating({ myStructBuff in
			for i in 0..<idSlice.count {
				myStructBuff[i] = idSlice[i]
			}
		})
		
	}
	
	/// `Bound(item:)`
	init(item: Item) {
		var constructedItem: Item? = nil
		item.RAW_access_staticbuff({ myStructBuff in
			constructedItem = Item(RAW_staticbuff: myStructBuff)
		})
		self.item = constructedItem!
		self.idLen = ID_SIZE
	}
	
	static public func == (lhs: Bound, rhs: Bound) -> Bool {
		lhs.item == rhs.item
	}

	static public func < (lhs: Bound, rhs: Bound) -> Bool {
		lhs.item < rhs.item
	}
}

@RAW_staticbuff(bytes: 16)
public struct Fingerprint: Sendable { }

