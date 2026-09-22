import SpriteKit
import SwiftUI

/// Hosts the SpriteKit scene in a transparent SKView so the camera preview shows through.
public struct GameCanvasView: NSViewRepresentable {
    public let scene: GameScene
    public var debug: Bool

    public init(scene: GameScene, debug: Bool) { self.scene = scene; self.debug = debug }

    public func makeNSView(context: Context) -> SKView {
        let v = SKView()
        v.allowsTransparency = true
        v.ignoresSiblingOrder = true
        v.preferredFramesPerSecond = 60
        v.shouldCullNonVisibleNodes = true
        v.presentScene(scene)
        return v
    }

    public func updateNSView(_ v: SKView, context: Context) {
        v.showsFPS = debug
        v.showsNodeCount = debug
        v.showsDrawCount = debug
        if v.scene !== scene { v.presentScene(scene) }
    }
}
