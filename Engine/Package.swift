// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AcornEngine",
    defaultLocalization: "en",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "AcornEngine",
            targets: ["AcornEngine"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "AcornEngine",
            dependencies: ["box2d", "AcornMetal"],
            resources: [
                .process("Renderer/Shaders.metal")
            ],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
        .testTarget(
            name: "AcornEngineTests",
            dependencies: ["AcornEngine"],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
        .target(
            name: "box2d",
            publicHeadersPath: "include"
        ),
        .target(
            name: "simdjson",
            path: "Dependencies/simdjson",
            publicHeadersPath: ".",
            cxxSettings: [.unsafeFlags(["-std=c++17"])]
        ),
        .target(
            name: "fastgltf",
            dependencies: ["simdjson"],
            path: "Dependencies/fastgltf",
            exclude: [
                "CMakeLists.txt", "README.md", "LICENSE.md", "docs", "examples", "cmake", "tests", ".github", ".gitignore", ".readthedocs.yaml", ".gitmodules", "src/fastgltf.ixx"
            ],
            sources: ["src"],
            publicHeadersPath: "include",
            cxxSettings: [.unsafeFlags(["-std=c++17"])]
        ),
        .target(
            name: "AcornMetal",
            dependencies: ["fastgltf"],
            path: "Sources/AcornMetal",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("../../Dependencies/metal-cpp"),
                .unsafeFlags(["-std=c++17"]),
                .define("DEBUG", to: "1", .when(configuration: .debug))
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
