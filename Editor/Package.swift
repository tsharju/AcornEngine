// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "AcornEditor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(
            name: "AcornEditor",
            targets: ["AcornEditor"]
        ),
    ],
    dependencies: [
        .package(path: "../Engine")
    ],
    targets: [
        .target(
            name: "ImGui",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("include")
            ],
            linkerSettings: [
                .linkedFramework("GameController")
            ]
        ),
        .executableTarget(
            name: "AcornEditor",
            dependencies: [
                "ImGui",
                .product(name: "AcornEngine", package: "Engine")
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
