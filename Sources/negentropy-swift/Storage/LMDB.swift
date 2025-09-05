//import RAW
//import RAW_blake2
//import QuickLMDB
//
//extension MDB_db_strict where Self: StorageBase, Self.MDB_db_key_type: StorageItem {
//	
//	func size() -> Int {
//		let env = dbEnvironment()
//		let trans = try! Transaction(env: env, readOnly: true)
//		return try! dbStatistics(tx: trans).ms_entries
//	}
//
//	func getItem(_ i: Int) -> Item {
//		
//		return Item()
//	}
//
//	func iterate(begin: Int, end: Int, cb: (Item, Int) -> Void) {
//		
//	}
//
//	func findLowerBound(begin: Int, end: Int, value: Bound) -> Int {
//		return 0
//	}
//
//	func fingerprint(begin: Int, end: Int) -> Fingerprint {
//		return
//	}
//}
