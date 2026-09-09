import RAW
import NIO

internal enum MessageType:UInt8 {
	case initiator = 0
	case responder = 1
	case dataQuery = 2
	case data = 3
	case finish = 4
}

internal struct NegentropyData {
	let magicNumber:NegentropyMagicNumber
	let type:MessageType
	var data:ByteBuffer
	init(type:consuming MessageType, data:consuming ByteBuffer) {
		self.magicNumber = NegentropyMagicNumber()
		self.type = type
		self.data = data
	}
}

// MARK: RAW_decodable
extension NegentropyData:RAW_decodable {
	init?(RAW_decode buffer:UnsafeRawBufferPointer) {
		let headerSize = MemoryLayout<NegentropyMagicNumber>.size + 1
		guard buffer.count >= headerSize else { return nil }
		var seekPtr = buffer.baseAddress!
		// read the magic number
		self.magicNumber = NegentropyMagicNumber(RAW_staticbuff_seeking:&seekPtr)
		// read the type
		guard let validType = MessageType(rawValue:seekPtr.assumingMemoryBound(to:UInt8.self).pointee) else {
			return nil
		}
		self.type = validType
		// remaining bytes become the negentropy payload
		let remainingCount = buffer.count - headerSize
		var decodedData = ByteBufferAllocator().buffer(capacity: remainingCount)
		if remainingCount > 0 {
			decodedData.writeBytes(UnsafeRawBufferPointer(start: seekPtr + 1, count: remainingCount))
		}
		self.data = decodedData
	}
}

// MARK: Encoding
extension NegentropyData {
	// encode header onto existing bytebuffer
	mutating func encode() -> ByteBuffer {
		var headerData = ByteBufferAllocator().buffer(capacity: 5 + data.readableBytes)
		_ = magicNumber.RAW_access_immutable(UnsafeBufferPointer<UInt8>.self) { ptr in
			headerData.writeBytes(ptr)
		}
		headerData.writeBytes([type.rawValue])
		headerData.writeBuffer(&data)
		return headerData
	}
}

// MARK: Encode Header
extension NegentropyDatabaseStrict {
	internal func encodeNegentropyHeader(into data: inout ByteBuffer, type: MessageType) {
		var negData = NegentropyData(type: type, data: data)
		data = negData.encode()
	}
}

extension NegentropyDatabase {
	internal func encodeNegentropyHeader(into data: inout ByteBuffer, type: MessageType) {
		var negData = NegentropyData(type: type, data: data)
		data = negData.encode()
	}
}
