import AppKit

protocol SwitchOverlayRenderable: NSView {
    func play(completion: (() -> Void)?)
}
