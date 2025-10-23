// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.
import PackageDescription

let package = Package(
    name: "negentropy-swift",
	platforms:[
		.macOS(.v15)
	],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "negentropy-swift",
            targets: ["negentropy-swift"]),
    ],
	dependencies:[
		.package(url:"https://github.com/tannerdsilva/rawdog", revision:"ba588bc9e3b824c8e0e1d7868a3b7cf9dd876b81"),
		.package(url:"https://github.com/tannerdsilva/wireguard-swift", revision:"e27b8dc8e80b8157d6bb31cf107e858ff90a484e"),
		.package(url:"https://github.com/tannerdsilva/QuickLMDB.git", "14.0.0"..<"14.1.0"),
		.package(url:"https://github.com/tannerdsilva/bedrock.git", "7.1.0"..<"8.0.0"),
		.package(url:"http://github.com/apple/swift-nio.git", "2.84.0"..<"3.0.0"),
		.package(url:"https://github.com/apple/swift-log.git", "1.6.4"..<"2.0.0"),
	],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
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
