// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NoteIt",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NoteIt", targets: ["NoteIt"])
    ],
    targets: [
        .executableTarget(
            name: "NoteIt",
            path: "Sources/NoteIt"
        )
    ]
)
