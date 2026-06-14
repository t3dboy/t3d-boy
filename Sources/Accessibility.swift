// T3d Boy — accessibility helpers.
//
// The UI is built from custom NSViews, which are invisible to VoiceOver unless we
// give them roles, labels, values and a press action. This file centralises the small
// shared pieces: a reduce-motion check, a VoiceOver announcement helper, and a reusable
// accessibility child element for composite controls (e.g. the segmented tab bar).

import Cocoa

enum A11y {
    /// Whether the user has asked for reduced motion. Honour this for big transitions
    /// (the launch zoom, drawer slide) by snapping instead of animating.
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Speak a message through VoiceOver (if running), e.g. an achievement unlock.
    static func announce(_ message: String, priority: NSAccessibilityPriorityLevel = .high) {
        let target: Any = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp as Any
        NSAccessibility.post(element: target, notification: .announcementRequested, userInfo: [
            .announcement: message,
            .priority: priority.rawValue,
        ])
    }
}

/// Base class for the custom NSView controls so keyboard-only users (Full Keyboard
/// Access) can Tab to them, see a system focus ring, and activate with Space/Return.
/// Subclasses override `activate()` (and may handle extra keys in `keyDown`).
class FocusableControl: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .exterior
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        focusRingType = .exterior
    }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    /// Corner radius for the focus ring shape — match the control's own rounding.
    var focusRingCornerRadius: CGFloat { layer?.cornerRadius ?? 6 }

    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: focusRingCornerRadius,
                     yRadius: focusRingCornerRadius).fill()
    }
    override func becomeFirstResponder() -> Bool { noteFocusRingMaskChanged(); return super.becomeFirstResponder() }
    override func resignFirstResponder() -> Bool { noteFocusRingMaskChanged(); return super.resignFirstResponder() }

    /// The Space/Return action. Subclasses override.
    @objc func activate() {}

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49, 36, 76: activate() // space, return, keypad-enter
        default: super.keyDown(with: event)
        }
    }
}
