import RAW
import NIO
import QuickLMDB

extension NegentropyDatabase {
	internal func getDBSignature() -> String {
		var ret = ""
		if(dbName() != nil) {
			ret += dbName()!
		}
		ret += String(describing: MDB_db_key_type.self)
		ret += String(describing: MDB_db_val_type.self)
		return ret
	}
	
	internal func initiate(buckets:Int, tx:borrowing Transaction) throws -> ByteBuffer  {
		var returnBuffer = ByteBufferAllocator().buffer(capacity: 0)
		
		let upperBound = Bound<MDB_db_key_type>(length:UInt8(MemoryLayout<MDB_db_key_type>.size), identifier:MDB_db_key_type.RAW_comparable_fixed_theoretical_max())
		
		if try dbStatistics(tx: tx).ms_entries == 0 {
			let upper = Bound(length: RAW_byte(RAW_native:UInt8(MemoryLayout<MDB_db_key_type>.size)).RAW_native(), identifier: MDB_db_key_type.RAW_comparable_fixed_theoretical_max())
			splitRangeZeroDB(returnBuffer: &returnBuffer, upperBound: upper)
		} else {
			try cursor(tx: tx) { cursor in
				var lower = try cursor.opFirst(returning:(key:MDB_val, value:MDB_val).self).key
				try splitRange(buckets: buckets, returnBuffer: &returnBuffer, lower: &lower, upper: nil, upperBound: upperBound, cursor: cursor)
			}
		}
		encodeNegentropyHeader(into: &returnBuffer, type: .responder)
		return returnBuffer
	}
	
	internal func reconcile(query: consuming ByteBuffer, buckets:Int, tx:borrowing Transaction) throws -> ByteBuffer {
		var returnBuffer = ByteBufferAllocator().buffer(capacity: 5)
		var haveIds = Set<MDB_db_key_type>()
		var needIds = Set<MDB_db_key_type>()
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
	
	
	internal func reconcile(query: consuming ByteBuffer, haveIds: inout Set<MDB_db_key_type>, needIds: inout Set<MDB_db_key_type>, buckets:Int, tx:borrowing Transaction) throws -> ByteBuffer? {
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
