import RAW
import NIO
import QuickLMDB

// See ReconcileStrict for documentation

extension NegentropyDatabase {
	internal func getDBSignature() -> String {
		var ret = ""
		if(dbName() != nil) {
			ret += dbName()!
		}
		ret += String(describing: self)
		ret += String(describing: MDB_val.self)
		ret += String(describing: MDB_db_val_type.self)
		return ret
	}
	
	internal func initiate(buckets:Int, tx:borrowing Transaction) throws -> ByteBuffer  {
		var returnBuffer = ByteBufferAllocator().buffer(capacity: 0)
		
		let ptr = UnsafeMutableRawPointer.allocate(byteCount: 20, alignment: 1)
		ptr.initializeMemory(as: UInt8.self, repeating: UInt8.max, count: 20)
		defer { ptr.deallocate() }
		let upper = MDB_val(mv_size: 20, mv_data: ptr)
		
		if try dbStatistics(tx: tx).ms_entries == 0 {
			splitRangeZeroDB(returnBuffer: &returnBuffer, upperBound: upper)
		} else {
			try cursor(tx: tx) { cursor in
				var lower = try cursor.opFirst(returning:(key:MDB_val, value:MDB_val).self).key
				try splitRange(buckets: buckets, returnBuffer: &returnBuffer, lower: &lower, upper: nil, upperBound: upper, cursor:cursor)
			}
		}
		encodeNegentropyHeader(into: &returnBuffer, type: .responder)
		return returnBuffer
	}
	
	internal func reconcile(query: consuming ByteBuffer, buckets:Int, tx:borrowing Transaction) throws -> ByteBuffer {
		var returnBuffer = ByteBufferAllocator().buffer(capacity: 5)
		var haveIds = Set<ByteBuffer>()
		var needIds = Set<ByteBuffer>()
		try cursor(tx: tx) { cursor in
			if try dbStatistics(tx: tx).ms_entries == 0 {
				try reconcileAuxZeroDB(isInitiator: false, buckets: buckets, queryBuffer: &query, returnBuffer: &returnBuffer, haveIDs: &haveIds, needIDs: &needIds, cursor: cursor, tx: tx)
			} else {
				try reconcileAux(isInitiator: false, buckets: buckets, queryBuffer: &query, returnBuffer: &returnBuffer, haveIDs: &haveIds, needIDs: &needIds, cursor: cursor, tx:tx)
			}
		}
		encodeNegentropyHeader(into: &returnBuffer, type: .initiator)
		return returnBuffer
	}
	
	
	internal func reconcile(query: consuming ByteBuffer, haveIds: inout Set<ByteBuffer>, needIds: inout Set<ByteBuffer>, buckets:Int, tx:borrowing Transaction) throws -> ByteBuffer? {
		var returnBuffer = ByteBufferAllocator().buffer(capacity: 5)
		try cursor(tx: tx) { cursor in
			if try dbStatistics(tx: tx).ms_entries == 0 {
				try reconcileAuxZeroDB(isInitiator: true, buckets: buckets, queryBuffer: &query, returnBuffer: &returnBuffer, haveIDs: &haveIds, needIDs: &needIds, cursor: cursor, tx: tx)
			} else {
				try reconcileAux(isInitiator: true, buckets: buckets, queryBuffer: &query, returnBuffer: &returnBuffer, haveIDs: &haveIds, needIDs: &needIds, cursor: cursor, tx:tx)
			}
		}
		if returnBuffer.readableBytes == 0 {
			return nil
		}
		encodeNegentropyHeader(into: &returnBuffer, type: .responder)
		return returnBuffer
	}
}
