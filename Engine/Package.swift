// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AcornEngine",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "AcornMath",
            targets: ["AcornMath"]
        ),
        .library(
            name: "AcornEngine",
            targets: ["AcornEngine"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "AcornMath",
            path: "Sources/AcornMath"
        ),
        .target(
            name: "AcornEngine",
            dependencies: [
                "box2d",
                "AcornGLTF",
                "AcornRHI",
                "AcornMath",
                "AcornMapGeometry"
            ],
            exclude: [
                "Renderer/Shaders"
            ],
            resources: [
                .copy("Renderer/CompiledShaders")
            ],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
        .testTarget(
            name: "AcornMathTests",
            dependencies: ["AcornMath"]
        ),
        .testTarget(
            name: "AcornEngineTests",
            dependencies: [
                "AcornEngine",
                "AcornMapGeometry"
            ],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
        .target(
            name: "box2d",
            publicHeadersPath: "include"
        ),
        .target(
            name: "simdjson",
            path: "Dependencies/simdjson",
            publicHeadersPath: "."
        ),
        .target(
            name: "fastgltf",
            dependencies: ["simdjson"],
            path: "Dependencies/fastgltf",
            exclude: [
                "CMakeLists.txt", "README.md", "LICENSE.md", "docs", "examples", "cmake", "tests", ".github", ".gitignore", ".readthedocs.yaml", ".gitmodules", "src/fastgltf.ixx"
            ],
            sources: ["src"],
            publicHeadersPath: "include"
        ),
        .target(
            name: "AcornGLTF",
            dependencies: ["fastgltf"],
            path: "Sources/AcornGLTF",
            publicHeadersPath: "include",
            cxxSettings: [
                .define("DEBUG", to: "1", .when(configuration: .debug))
            ]
        ),
        .binaryTarget(
            name: "NoGraphicsAPI",
            path: "Binaries/NoGraphicsAPI.xcframework"
        ),
        .target(
            name: "AcornRHI",
            dependencies: ["NoGraphicsAPI"],
            path: "Sources/AcornRHI",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("../../Dependencies/NoGraphicsAPI/include"),
                .headerSearchPath("../../Dependencies/NoGraphicsAPI/utility/include"),
                .define("DEBUG", to: "1", .when(configuration: .debug))
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("Foundation")
            ]
        ),
        .target(
            name: "Clipper2",
            path: "Dependencies/clipper2/CPP/Clipper2Lib",
            sources: ["src"],
            publicHeadersPath: "include"
        ),
        .target(
            name: "AcornMapGeometry",
            dependencies: ["Clipper2"],
            path: "Sources/AcornMapGeometry",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("../../Dependencies/earcut/include"),
                .headerSearchPath("../../Dependencies/protozero/include"),
                .headerSearchPath("../../Dependencies/vtzero/include"),
                .headerSearchPath("../../Dependencies/clipper2/CPP/Clipper2Lib/include")
            ],
            linkerSettings: [
                .linkedLibrary("z")
            ]
        ),
    ],
    swiftLanguageModes: [.v6],
    cxxLanguageStandard: .cxx20
)
