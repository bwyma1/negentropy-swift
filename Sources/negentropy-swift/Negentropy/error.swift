
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
	
	// Header errors
	case expectedNonInitiatorMessage
	case expectedNonResponderMessage
	case expectedNegentropyData
	
	// Sync thread
	case noDatabases
	case undecodableIdentifier
	case undecodableValue
}
