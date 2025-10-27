import RAW
import RAW_blake2
import QuickLMDB

public protocol DatabaseIndexVector:RAW_staticbuff, MDB_comparable, Equatable, Comparable, Hashable {}
