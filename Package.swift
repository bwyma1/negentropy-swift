// swift-tools-version: 6.1
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
		.package(url:"https://github.com/tannerdsilva/rawdog.git", revision:"b249e367e35c0ea05ae7b7dc0046074b5b05c604"),
		.package(url:"https://github.com/tannerdsilva/QuickLMDB.git", from: "13.0.0")
	],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "negentropy-swift",
			dependencies: [.product(name:"RAW", package:"rawdog"),
						   .product(name:"RAW_blake2", package:"rawdog"),
						   .product(name:"QuickLMDB", package:"QuickLMDB")]
		),
        .testTarget(
            name: "negentropy-swiftTests",
            dependencies: ["negentropy-swift"]
        ),
    ]
)
