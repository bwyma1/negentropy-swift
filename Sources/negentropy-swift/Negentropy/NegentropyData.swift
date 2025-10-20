import RAW

struct NegentropyData<ByteContainerType:Sequence & Sendable>:Sendable where ByteContainerType.Element == UInt8 {
	let magicNumber:NegentropyMagicNumber
	let type:MessageType
	let data:ByteContainerType
	init(type:consuming MessageType, data:consuming ByteContainerType) {
		self.magicNumber = NegentropyMagicNumber()
		self.type = type
		self.data = data
	}
}

// MARK: RAW_decodable
extension NegentropyData:RAW_decodable where ByteContainerType:RAW_decodable {
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
		guard let decodedData = ByteContainerType(RAW_decode:seekPtr, count:remainingCount) else { return nil }
		self.data = decodedData
	}
}

// MARK: RAW_encodable
extension NegentropyData:RAW_encodable where ByteContainerType:RAW_encodable {
	func RAW_encode(count: inout RAW.size_t) {
		magicNumber.RAW_encode(count:&count)
		count += 1
		data.RAW_encode(count:&count)
	}
	func RAW_encode(dest: UnsafeMutablePointer<UInt8>) -> UnsafeMutablePointer<UInt8> {
		var dest = magicNumber.RAW_encode(dest:dest)
		dest.pointee = type.rawValue
		dest = dest + 1
		dest = data.RAW_encode(dest:dest)
		return dest
	}
}
