import Foundation
import RAW
import RAW_blake2
import QuickLMDB
public typealias WGHasher<K> = RAW_blake2.Hasher<S, K> where K:RAW_staticbuff

let ID_SIZE:Int = 6
let FINGERPRINT_SIZE:Int = 16

enum Mode: UInt8 {
	case skip = 0
	case fingerprint = 1
	case idList = 2
}

protocol StorageID: Sendable, Equatable, Comparable, MDB_comparable, Hashable
where Self: RAW_staticbuff, Self:Equatable, Self:Comparable { }

@RAW_staticbuff(bytes: 6)
@MDB_comparable
public struct StoredIDExample:StorageID, Sendable, Hashable { }

@RAW_staticbuff(bytes: 16)
public struct Fingerprint: Sendable, Equatable { }
