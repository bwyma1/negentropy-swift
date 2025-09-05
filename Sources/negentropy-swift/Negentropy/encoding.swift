import Foundation
public func encodeVarInt(_ n: Int) -> [UInt8] {
	guard n != 0 else { return [0] }
	var temp: [UInt8] = []
	var value = n
	while value > 0 {
		temp.append(UInt8(value & 0x7F))
		value >>= 7
	}
	temp.reverse()
	for i in 0..<(temp.count - 1) {
		temp[i] |= 0x80
	}
	return temp
}

public func decodeVarInt(_ data: inout [UInt8]) throws -> UInt64 {
	var result: UInt64 = 0
	while true {
		guard !data.isEmpty else { throw NegentropyError.prematureEndOfVarInt }
		let byte = UInt64(data[data.startIndex])
		data = Array(data.dropFirst())
		result = (result << 7) | (byte & 0b0111_1111)
		if (byte & 0b1000_0000) == 0 { break }
	}
	return result
}



func getByte(_ encoded: inout ArraySlice<UInt8>) throws -> UInt8 {
	guard !encoded.isEmpty else { throw NegentropyError.parseEndsPrematurely }

	let byte = encoded[encoded.startIndex]
	encoded = encoded.dropFirst()          // advance by one byte
	return byte
}

func getBytes(_ encoded: inout [UInt8], _ n: Int) throws -> [UInt8] {
	guard encoded.count >= n else { throw NegentropyError.parseEndsPrematurely }

	let slice = encoded.prefix(n)          // the first `n` bytes
	encoded.removeFirst(n)         // advance the slice

	return Array(slice)                    // copy into a normal array
}
