import RAW

@RAW_staticbuff(bytes: 4)
struct NegentropyMagicNumber:Sendable {
	init() {
		let magicBytes = Array("NEGT".utf8)
		self = Self(RAW_staticbuff:magicBytes)
	}
}

@RAW_staticbuff(bytes:8)
@RAW_staticbuff_fixedwidthinteger_type<UInt64>(bigEndian:true)
internal struct EncodedUInt64:Sendable, ExpressibleByIntegerLiteral {}