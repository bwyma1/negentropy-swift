
internal enum NegentropyError: Error {
	// Negentropy errors
	case frameSizeTooSmall
	case unexpectedMode
	case wrongInitiator
	
	// Type/Encoding Errors
	case badIDSize
	case prematureEndOfVarInt
	case parseEndsPrematurely
	
	// Storage Errors
	case duplicateItemsInStorage
}
