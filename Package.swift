// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacAttack",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacAttackCore", targets: ["MacAttackCore"]),
        .executable(name: "MacAttack", targets: ["MacAttack"]),
        // Loaded by macOS's screensaver host; scripts/build_saver.sh wraps it into MacAttack.saver.
        .library(name: "MacAttackSaver", type: .dynamic, targets: ["MacAttackSaver"]),
    ],
    targets: [
        // Pure game logic: no camera, Vision or SpriteKit. Phase 2's screensaver reuses this.
        .target(name: "MacAttackCore"),
        // Camera, Vision and the SpriteKit renderer: shared by the app and the screensaver.
        .target(name: "MacAttackKit", dependencies: ["MacAttackCore"]),
        .executableTarget(name: "MacAttack", dependencies: ["MacAttackKit"]),
        .target(name: "MacAttackSaver", dependencies: ["MacAttackKit"]),
        .testTarget(name: "MacAttackCoreTests", dependencies: ["MacAttackCore"]),
    ],
    swiftLanguageModes: [.v5]
)
