import NIO
import RAW
import QuickLMDB

/// Encodes a `Bound<K>` into the writeBuffer
internal func write<K>(bound:borrowing Bound<K>, writeBuffer:inout ByteBuffer) where K:DatabaseIndexVector {
	let expectedSize = bound.length
	writeBuffer.writeInteger(UInt8(expectedSize), as:UInt8.self)
	bound.identifier.RAW_access_immutable(UnsafeBufferPointer<UInt8>.self) { ptr in
		_ = writeBuffer.writeBytes(ptr.prefix(Int(expectedSize)))
	}
}
/// Encodes a `Fingerprint` into the writeBuffer
internal func write(fingerprint:Fingerprint, writeBuffer:inout ByteBuffer) {
	fingerprint.RAW_access_immutable(UnsafeBufferPointer<UInt8>.self) { fingerprint in
		_ = writeBuffer.writeBytes(fingerprint)
	}
}
/// Encodes a `type DatabaseIndexVector` into the writeBuffer
internal func write<I>(identifier:I, writeBuffer:inout ByteBuffer) where I:DatabaseIndexVector {
	identifier.RAW_access_immutable(UnsafeBufferPointer<UInt8>.self) { key in
		_ = writeBuffer.writeBytes(key)
	}
}
/// Encodes a `MDB_val` into the writeBuffer
internal func write(identifier:MDB_val, writeBuffer:inout ByteBuffer) {
	_ = writeBuffer.writeBytes(identifier)
}
/// Encodes a `Mode` into the writeBuffer
internal func write(mode:Mode, writeBuffer:inout ByteBuffer) {
	writeBuffer.writeInteger(mode.rawValue, as:UInt8.self)
}
/// Encodes a `Int` into the writeBuffer
internal func write(numElements:Int, writeBuffer:inout ByteBuffer) {
	writeBuffer.writeInteger(numElements)
}
/// Encodes a `String` and its length (length then `String`) into the writeBuffer
internal func write(dbSignature:String, writeBuffer:inout ByteBuffer) {
	let len = EncodedUInt64(RAW_native: UInt64(dbSignature.count))
	writeBuffer.writeInteger(len.RAW_native())
	writeBuffer.writeString(dbSignature)
}
/// Encodes a `MDB_val` and its length (length then `MDB_val`) into the writeBuffer
internal func write(val:MDB_val, writeBuffer:inout ByteBuffer) {
	writeBuffer.writeInteger(UInt8(val.mv_size), as:UInt8.self)
	writeBuffer.writeBytes(UnsafeRawBufferPointer(start: val.mv_data, count: val.mv_size))
}
/// Encodes a `ByteBuffer` and its length (length then `ByteBuffer`) into the writeBuffer
internal func write(buffer: inout ByteBuffer, writeBuffer: inout ByteBuffer) {
	writeBuffer.writeInteger(UInt8(buffer.readableBytes), as:UInt8.self)
	writeBuffer.writeBuffer(&buffer)
}
