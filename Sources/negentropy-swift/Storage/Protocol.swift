protocol StorageBase {

	func size() -> Int

	func getItem(_ i: Int) -> Item

	func iterate(begin: Int, end: Int, cb: (Item, Int) -> Void)

	func findLowerBound(begin: Int, end: Int, value: Bound) -> Int

	func fingerprint(begin: Int, end: Int) -> Fingerprint
}
