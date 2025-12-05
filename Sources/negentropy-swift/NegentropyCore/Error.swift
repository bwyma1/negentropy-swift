
internal enum NegentropyError: Error {	
	// Header errors
	case expectedNonInitiatorMessage
	case expectedNonResponderMessage
	case expectedNegentropyData
	
	// Sync thread
	case noDatabases
	case undecodableMDBKey
	case undecodableMDBValue
}
