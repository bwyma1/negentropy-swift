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
	init?(RAW_decode inputPtr:UnsafeRawPointer, count:RAW.size_t) {
		var seekPtr = inputPtr
		// read the magic number
		guard count >= MemoryLayout<NegentropyMagicNumber>.size else {
			return nil
		}
		self.magicNumber = NegentropyMagicNumber(RAW_staticbuff_seeking:&seekPtr)
		// read the type
		guard count >= MemoryLayout<NegentropyMagicNumber>.size + 1 else { return nil }
		guard let validType = MessageType(rawValue:seekPtr.assumingMemoryBound(to:UInt8.self).pointee) else {
			return nil
		}
		self.type = validType
		seekPtr = seekPtr + 1
		// read any remaining data (assuming a fatal state if the count is invalid)
		let remainingCount = count - MemoryLayout<NegentropyMagicNumber>.size - 1
		guard remainingCount >= 0 else { fatalError("critical internal error \(#file):\(#line)") }
		// Decode the remaining count into a byteBuffer
		var decodedData = ByteBufferAllocator().buffer(capacity: remainingCount)
		if remainingCount > 0 {
			decodedData.writeBytes(
				UnsafeRawBufferPointer(start: seekPtr, count: remainingCount)
			)
		}
		self.data = decodedData
	}
}

// MARK: Encoding
extension NegentropyData {
	// encode header onto existing bytebuffer
	mutating func encode() -> ByteBuffer {
		var headerData = ByteBufferAllocator().buffer(capacity: 5 + data.readableBytes)
		_ = magicNumber.RAW_access { ptr in
			headerData.writeBytes(ptr)
		}
		headerData.writeBytes([type.rawValue])
		headerData.writeBuffer(&data)
		return headerData
	}
}

// MARK: Encode Header
extension NegentropyDatabase {
	internal func encodeNegentropyHeader(into data: inout ByteBuffer, type: MessageType) {
		var negData = NegentropyData(type: type, data: data)
		data = negData.encode()
	}
}
