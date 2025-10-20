import NIO
import RAW
import QuickLMDB

extension Channel {
	// encode bound
	internal func write<K>(bound:borrowing Bound<K>, writeBuffer:inout ByteBuffer, promise:borrowing EventLoopPromise<Void>?) where K:DatabaseIndexVector {
		let expectedSize = MemoryLayout<K>.size
		writeBuffer.clear(minimumCapacity:1 + expectedSize)
		writeBuffer.writeInteger(UInt8(expectedSize), as:UInt8.self)
		bound.identifier.RAW_access {
			_ = writeBuffer.writeBytes($0)
		}
		write(writeBuffer, promise:promise)
	}
	// encode fingerprint
	internal func write(fingerprint:Fingerprint, writeBuffer:inout ByteBuffer, promise:borrowing EventLoopPromise<Void>?) {
		writeBuffer.clear(minimumCapacity:MemoryLayout<Fingerprint>.size)
		fingerprint.RAW_access { fingerprint in
			_ = writeBuffer.writeBytes(fingerprint)
		}
		write(writeBuffer, promise:promise)
	}
	// encode identifier
	internal func write<I>(identifier:I, writeBuffer:inout ByteBuffer, promise:borrowing EventLoopPromise<Void>?) where I:DatabaseIndexVector {
		writeBuffer.clear(minimumCapacity:MemoryLayout<I>.size)
		identifier.RAW_access { key in
			_ = writeBuffer.writeBytes(key)
		}
		write(writeBuffer, promise:promise)
	}
	// encode identifier as MDB_val
	internal func write(identifier:MDB_val, writeBuffer:inout ByteBuffer, promise:borrowing EventLoopPromise<Void>?) {
		writeBuffer.clear(minimumCapacity:identifier.mv_size)
		_ = writeBuffer.writeBytes(identifier)
		write(writeBuffer, promise:promise)
	}
	// encode mode
	internal func write(mode:Mode, writeBuffer:inout ByteBuffer, promise:borrowing EventLoopPromise<Void>?) {
		writeBuffer.clear(minimumCapacity:1)
		writeBuffer.writeInteger(mode.rawValue, as:UInt8.self)
		write(writeBuffer, promise:promise)
	}
}