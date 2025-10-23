import NIO
import QuickLMDB

extension NegentropyDatabase {
	internal func encodeNegentropyHeader(into data: inout ByteBuffer, type: MessageType) {
		var negData = NegentropyData(type: type, data: data)
		data = negData.encode()
	}
	
	public func initiate(buckets:Int, tx:borrowing Transaction) throws -> ByteBuffer  {
		var returnBuffer = ByteBufferAllocator().buffer(capacity: 0)
		
		let upperBound = Bound<MDB_db_key_type>(length:UInt8(MemoryLayout<MDB_db_key_type>.size), identifier:MDB_db_key_type.RAW_comparable_fixed_theoretical_max())
		
		try cursor(tx: tx) { cursor in
			var lower = try cursor.opFirst(returning:(key:MDB_val, value:MDB_val).self).key
			try splitRange(buckets: buckets, returnBuffer: &returnBuffer, lower: &lower, upperBound: upperBound, cursor: cursor)
		}
		var negData = NegentropyData(type: .responder, data: returnBuffer)
		returnBuffer = negData.encode()
		return returnBuffer
	}
	
	public func reconcile(query: consuming ByteBuffer, buckets:Int, tx:borrowing Transaction) throws -> ByteBuffer {
		var returnBuffer = ByteBufferAllocator().buffer(capacity: 5)
		var haveIds = Set<MDB_db_key_type>()
		var needIds = Set<MDB_db_key_type>()
		try cursor(tx: tx) { cursor in
			try reconcileAux(isInitiator: true, buckets: buckets, queryBuffer: &query, returnBuffer: &returnBuffer, haveIDs: &haveIds, needIDs: &needIds, cursor: cursor)
		}
		encodeNegentropyHeader(into: &returnBuffer, type: .initiator)
		return returnBuffer
	}
	
	
	public func reconcile(query: consuming ByteBuffer, haveIds: inout Set<MDB_db_key_type>, needIds: inout Set<MDB_db_key_type>, buckets:Int, tx:borrowing Transaction) throws -> ByteBuffer? {
		var returnBuffer = ByteBufferAllocator().buffer(capacity: 5)
		try cursor(tx: tx) { cursor in
			try reconcileAux(isInitiator: true, buckets: buckets, queryBuffer: &query, returnBuffer: &returnBuffer, haveIDs: &haveIds, needIDs: &needIds, cursor: cursor)
		}
		if returnBuffer.readableBytes == 0 {
			return nil
		}
		encodeNegentropyHeader(into: &returnBuffer, type: .responder)
		return returnBuffer
	}
}
