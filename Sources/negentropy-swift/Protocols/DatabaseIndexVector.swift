import RAW
import RAW_blake2
import QuickLMDB

/// Primary protocol that the key type of the MDB strict database must follow.
/// Negentropy sync only works on MDB strict databases with a key type conforming to the DatabaseIndexVector protocol.
public protocol DatabaseIndexVector:RAW_staticbuff, MDB_comparable, Equatable, Comparable, Hashable {}
