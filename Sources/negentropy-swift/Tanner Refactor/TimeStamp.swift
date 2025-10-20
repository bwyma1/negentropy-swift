import RAW

@RAW_staticbuff(bytes: 8)
@RAW_staticbuff_fixedwidthinteger_type<UInt64>(bigEndian: true)
public struct Timestamp: Sendable, Equatable, Comparable {}

