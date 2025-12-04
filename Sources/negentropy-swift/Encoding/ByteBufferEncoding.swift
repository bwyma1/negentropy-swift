import NIO
import RAW
import QuickLMDB


// encode bound
internal func write<K>(bound:borrowing Bound<K>, writeBuffer:inout ByteBuffer) where K:DatabaseIndexVector {
	let expectedSize = bound.length
	writeBuffer.writeInteger(UInt8(expectedSize), as:UInt8.self)
	bound.identifier.RAW_access { ptr in
		_ = writeBuffer.writeBytes(ptr.prefix(Int(expectedSize)))
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
// encode numElements
internal func write(numElements:Int, writeBuffer:inout ByteBuffer) {
	writeBuffer.writeInteger(numElements)
}
// encode DB Signature
internal func write(dbSignature:String, writeBuffer:inout ByteBuffer) {
	let len = EncodedUInt64(RAW_native: UInt64(dbSignature.count))
	writeBuffer.writeInteger(len.RAW_native())
	writeBuffer.writeString(dbSignature)
}
// encode MDB_val
internal func write(val:MDB_val, writeBuffer:inout ByteBuffer) {
	writeBuffer.writeInteger(UInt8(val.mv_size), as:UInt8.self)
	writeBuffer.writeBytes(UnsafeRawBufferPointer(start: val.mv_data, count: val.mv_size))
}

internal func write(buffer: inout ByteBuffer, writeBuffer: inout ByteBuffer) {
	writeBuffer.writeInteger(UInt8(buffer.readableBytes), as:UInt8.self)
	writeBuffer.writeBuffer(&buffer)
}
