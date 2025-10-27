import RAW

internal struct Bound<BoundIdentifierType:RAW_staticbuff>:Sendable {
	internal let length:UInt8
	internal let identifier:BoundIdentifierType
	internal init(length:UInt8, identifier:BoundIdentifierType) {
		self.length = length
		self.identifier = identifier
	}
}