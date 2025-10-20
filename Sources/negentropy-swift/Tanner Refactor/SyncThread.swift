import bedrock_pthread
import QuickLMDB

public struct NegentropyThread:PThreadWork {
	private let mdbEnvironment:Environment
	private let channel:Channel
	public init(_ env:consuming (Environment, Channel, FIFO)) {
		self.mdbEnvironment = env.1
		self.channel = env.2
	}
	public func pthreadWork() throws -> Void {
		let syncTransaction = try Transaction(env:mdbEnvironment, readOnly:true)

		try syncTransaction.commit()
	}
}