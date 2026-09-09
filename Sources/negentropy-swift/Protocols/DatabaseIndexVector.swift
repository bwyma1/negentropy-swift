import RAW
import RAW_blake2
import QuickLMDB

/// Primary protocol that the key type of the MDB strict database must follow.
/// Negentropy sync only works on MDB strict databases with a key type conforming to the DatabaseIndexVector protocol.
public protocol DatabaseIndexVector:RAW_staticbuff, MDB_comparable, Equatable, Comparable, Hashable {}

extension DatabaseIndexVector {
	/// Reconstructs a full-size key value from wire bytes.
	/// Negentropy bound identifiers are transmitted as a *prefix* (the shared key
	/// prefix between bucket boundaries; see `write(bound:)`). The fixed-size key is
	/// rebuilt by copying the received prefix and zero-padding the remainder, matching
	/// the all-zeros `theoretical_min` base used by the encoder (`getMinimalBound`).
	internal static func fromBindingBytes(_ bytes:UnsafeRawBufferPointer) -> Self {
		var key = Self.RAW_comparable_fixed_theoretical_min()
		key.RAW_access_mutable(UnsafeMutableBufferPointer<UInt8>.self) { buf in
			for i in 0..<min(bytes.count, buf.count) {
				buf[i] = bytes[i]
			}
		}
		return key
	}
}
