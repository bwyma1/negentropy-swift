import NIO
import RAW
import QuickLMDB


// encode bound
internal func write<K>(bound:borrowing Bound<K>, writeBuffer:inout ByteBuffer) where K:DatabaseIndexVector {
	let expectedSize = MemoryLayout<K>.size
	writeBuffer.writeInteger(UInt8(expectedSize), as:UInt8.self)
	bound.identifier.RAW_access {
		_ = writeBuffer.writeBytes($0)
	}
}
// encode fingerprint
internal func write(fingerprint:Fingerprint, writeBuffer:inout ByteBuffer) {
	fingerprint.RAW_access { fingerprint in
		_ = writeBuffer.writeBytes(fingerprint)
	}
}
// encode identifier
internal func write<I>(identifier:I, writeBuffer:inout ByteBuffer) where I:DatabaseIndexVector {
	identifier.RAW_access { key in
		_ = writeBuffer.writeBytes(key)
	}
}
// encode identifier as MDB_val
internal func write(identifier:MDB_val, writeBuffer:inout ByteBuffer) {
	_ = writeBuffer.writeBytes(identifier)
}
// encode mode
internal func write(mode:Mode, writeBuffer:inout ByteBuffer) {
	writeBuffer.writeInteger(mode.rawValue, as:UInt8.self)
}

internal func write(numElements:Int, writeBuffer:inout ByteBuffer) {
	writeBuffer.writeInteger(numElements)
}
