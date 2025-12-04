// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "negentropy-swift",
	platforms:[
		.macOS(.v15)
	],
    products: [
        .library(
            name: "negentropy-swift",
            targets: ["negentropy-swift"]),
    ],
	dependencies:[
		.package(url:"https://github.com/tannerdsilva/rawdog", revision:"ba588bc9e3b824c8e0e1d7868a3b7cf9dd876b81"),
		.package(url:"https://github.com/tannerdsilva/wireguard-swift", revision:"082c17b60c4a31b13fb0c36bba921953f47ae22f"),
//		.package(url:"https://github.com/tannerdsilva/QuickLMDB.git", "14.0.0"..<"15.0.0"),
		.package(name:"QuickLMDB", path:"../QuickLMDB"),
		.package(url:"https://github.com/tannerdsilva/bedrock.git", "7.1.0"..<"8.0.0"),
		.package(url:"http://github.com/apple/swift-nio.git", "2.84.0"..<"3.0.0"),
		.package(url:"https://github.com/apple/swift-log.git", "1.6.4"..<"2.0.0"),
	],
    targets: [
        .target(
            name: "negentropy-swift",
			dependencies: [
				.product(name:"RAW", package:"rawdog"),
				.product(name:"RAW_blake2", package:"rawdog"),
				.product(name:"RAW_dh25519", package:"rawdog"),
				.product(name:"wireguard-userspace-nio", package:"wireguard-swift"),
				.product(name:"QuickLMDB", package:"QuickLMDB"),
				.product(name:"bedrock", package:"bedrock"),
				.product(name:"NIO", package:"swift-nio"),
				.product(name:"bedrock_pthread", package:"bedrock"),
				.product(name:"bedrock_fifo", package:"bedrock"),
				.product(name:"Logging", package:"swift-log")
			]
		),
        .testTarget(
            name: "negentropy-swiftTests",
            dependencies: [
				"negentropy-swift",
				.product(name:"bedrock", package:"bedrock"),
				.product(name:"RAW_base64", package:"rawdog"),
				.product(name:"RAW_dh25519", package:"rawdog")
			]
        ),
    ]
)
