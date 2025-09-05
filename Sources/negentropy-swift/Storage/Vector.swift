import RAW
import RAW_blake2
public typealias WGHasher<K> = RAW_blake2.Hasher<S, K> where K:RAW_staticbuff

struct VectorStorage: StorageBase {
	public private(set) var items: [Item] = []

	public init() {}
	public init(_ items: [Item]) { self.items = items }
	
	public mutating func insertItem(_ item: Item) {
		items.append(item)
	}
	
	public mutating func sort() throws {
		// sort items
		items.sort()
		
		for i in 1..<items.count {
			if (items[i-1] == items[i]) { throw NegentropyError.duplicateItemsInStorage }
		}
	}
	
	public func size() -> Int {
		return items.count
	}

	public func getItem(_ i: Int) -> Item {
		precondition(0..<items.count ~= i, "index out of bounds")
		return items[i]
	}

	public func iterate(begin: Int, end: Int, cb: (Item, Int) -> Void) {
		guard begin < end && begin >= 0 && end <= items.count else { return }
		for idx in begin..<end {
			cb(items[idx], idx)
		}
	}

	public func findLowerBound(begin: Int, end: Int, value: Bound) -> Int {
		guard begin < end && begin >= 0 && end <= items.count else { return end }

		for idx in begin..<end {
			let itm = items[idx]
			if value.item <= itm {      // value <= itm → stop
				return idx
			}
		}
		return end   // nothing found → we’re at the end of the range
	}

	public func fingerprint(begin: Int, end: Int) -> Fingerprint {
		do {
			guard begin < end && begin >= 0 && end <= items.count else {
				return Fingerprint(RAW_staticbuff: Fingerprint.RAW_staticbuff_zeroed())
			}
			var hasher = try WGHasher<ID>()
			
			for idx in begin..<end {
				try hasher.update(items[idx].id)
			}
			let h = try hasher.finish()
			var fingerprint:Fingerprint? = nil
			h.RAW_access { ptr in
				let first16 = ptr.prefix(16) 
				fingerprint = Fingerprint(RAW_accessed: UnsafeBufferPointer(rebasing: first16))
			}
			return fingerprint!
		} catch {
			fatalError()
		}
	}
	
	public func itemFor(id: ID) -> Item? {
		var lo = 0
		var hi = items.count

		while lo < hi {
			let mid = (lo + hi) / 2
			let midId = items[mid].id

			if midId == id {
				return items[mid]
			} else if midId < id {
				// The id we’re looking for is larger – skip left half.
				lo = mid + 1
			} else {
				// id is smaller – skip right half.
				hi = mid
			}
		}

		// Not found – linear fallback (this branch is rarely executed).
		for itm in items {
			if itm.id == id {
				return itm
			}
		}
		return nil
	}

	public mutating func clear() {
		items.removeAll(keepingCapacity: true)
	}
}
