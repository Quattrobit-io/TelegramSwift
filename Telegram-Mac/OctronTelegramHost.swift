import AppKit
import ApiCredentials
import ColorPalette
import TGUIKit

@objc(OctronTelegramHost)
public final class OctronTelegramHost: NSObject {
    let window: Window
    private let sidebar = OctronTelegramContainer()
    private let chat = OctronTelegramContainer()
    private var application: AppDelegate?
    private var previousResponderFilter: ((NSResponder?) -> NSResponder?)?
    private var previousHandlerScope: ((NSEvent?) -> Bool)?
    private var mouseButtons: Set<Int> = []
    private var keys: Set<UInt16> = []
    private var scrolling = false
    private(set) var active = false
    private(set) var palette: ColorPalette?

    @objc public static func makeWindow(contentRect: NSRect) -> NSWindow {
        let window = Window(contentRect: contentRect,
               styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
               backing: .buffered, defer: false)
        window.handlersEnabled = false
        return window
    }

    @objc public init(window: NSWindow) {
        precondition(window is Window, "Telegram requires its native window factory")
        self.window = window as! Window
        super.init()
        sidebar.layer?.isOpaque = false
        chat.minimumWidth = 380
        attachInput()
    }

    @objc public var sidebarView: NSView { sidebar }
    @objc public var chatView: NSView { chat }

    @objc public func start() throws {
        guard application == nil else { return }
        try ApiEnvironment.initialize()
        window.modalContainer = chat
        attachInput()
        let application = AppDelegate(embedded: self)
        self.application = application
        application.launchEmbedded()
    }

    private func attachInput() {
        guard previousResponderFilter == nil else { return }
        let previousFilter = window.firstResponderFilter
        let previousScope = window.handlerScope
        previousResponderFilter = previousFilter
        previousHandlerScope = previousScope
        window.handlerScope = { [weak self] event in
            guard previousScope?(event) != false else { return false }
            return self?.accepts(event) ?? true
        }
        window.firstResponderFilter = { [weak self] responder in
            guard let self else { return previousFilter(responder) }
            if let view = self.ownedView(for: responder), !self.active || !self.acceptsInput(in: view) {
                return self.window.firstResponder
            }
            return previousFilter(responder)
        }
    }

    @objc public func setActive(_ active: Bool) {
        guard self.active != active else { return }
        self.active = active
        window.handlersEnabled = active
        if !active {
            mouseButtons.removeAll()
            keys.removeAll()
            scrolling = false
        }
        application?.setEmbeddedActive(active)
        if !active && ownedView(for: window.firstResponder) != nil {
            window.makeFirstResponder(nil)
        }
    }

    @objc public func setSidebarInputEnabled(_ enabled: Bool) {
        guard sidebar.inputEnabled != enabled else { return }
        sidebar.inputEnabled = enabled
        if !enabled, let view = ownedView(for: window.firstResponder),
           view === sidebar || view.isDescendant(of: sidebar) {
            window.makeFirstResponder(nil)
        }
    }

    @objc public func applyTheme(background: NSColor, sidebarBackground: NSColor,
                                 textPrimary: NSColor, textInactive: NSColor,
                                 textDisabled: NSColor, accent: NSColor) {
        // The native palette reads RGB/HSB components, including for grayscale themes.
        func rgb(_ color: NSColor) -> NSColor {
            guard let converted = color.usingColorSpace(.sRGB) else {
                preconditionFailure("Telegram theme requires solid RGB-compatible colors")
            }
            return converted
        }
        let updated = darkPalette.withAccentColor(PaletteAccentColor(rgb(accent)))
            .withUpdatedName("Octron", background: rgb(background),
                sidebarBackground: rgb(sidebarBackground), text: rgb(textPrimary),
                grayText: rgb(textInactive), disabledText: rgb(textDisabled))
        guard palette != updated else { return }
        palette = updated
        application?.applyEmbeddedTheme()
    }

    @objc public func prepareForTermination() {
        _ = application?.applicationShouldTerminate(NSApplication.shared)
    }

    @objc public func stop() {
        setActive(false)
        prepareForTermination()
        closeAllModals(window: window)
        closeAllPopovers(for: window)
        application?.stopEmbedded()
        application = nil
        window.modalContainer = nil
        if let previousResponderFilter {
            window.firstResponderFilter = previousResponderFilter
            window.handlerScope = previousHandlerScope
            self.previousResponderFilter = nil
            previousHandlerScope = nil
        }
        sidebar.mount(nil)
        chat.mount(nil)
        setLocked(false)
    }

    func setLocked(_ locked: Bool) {
        sidebar.isHidden = locked
        chat.contentHidden = locked
        if ownedView(for: window.firstResponder)?.isHiddenOrHasHiddenAncestor == true {
            window.makeFirstResponder(nil)
        }
    }

    private func ownedView(for responder: NSResponder?) -> NSView? {
        let view: NSView?
        if let editor = responder as? NSTextView, editor.isFieldEditor {
            let control = editor.delegate as? NSControl
            view = control?.currentEditor() === editor ? control : nil
        } else {
            view = responder as? NSView
        }
        guard let view, view === sidebar || view === chat
                || view.isDescendant(of: sidebar) || view.isDescendant(of: chat) else {
            return nil
        }
        return view
    }

    private func accepts(_ event: NSEvent?) -> Bool {
        guard active, window.attachedSheet == nil,
              NSApp.modalWindow == nil || NSApp.modalWindow === window else { return false }
        let responder = window.firstResponder
        let ownsFocus = ownedView(for: responder).map { acceptsInput(in: $0) }
            ?? (responder == nil || responder === window || responder === window.contentView)
        guard let event else { return ownsFocus }
        guard event.window === window else { return false }
        switch event.type {
        case .keyDown:
            if ownsFocus { keys.insert(event.keyCode) }
            return ownsFocus
        case .keyUp:
            return keys.remove(event.keyCode) != nil
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            let ownsPoint = ownsPoint(event.locationInWindow)
            if ownsPoint { mouseButtons.insert(event.buttonNumber) }
            else { mouseButtons.remove(event.buttonNumber) }
            return ownsPoint
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return mouseButtons.contains(event.buttonNumber)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return mouseButtons.remove(event.buttonNumber) != nil
        case .scrollWheel:
            if event.phase.isEmpty && event.momentumPhase.isEmpty {
                return ownsPoint(event.locationInWindow)
            }
            if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
                scrolling = ownsPoint(event.locationInWindow)
            }
            let ownsGesture = scrolling
            if event.phase.contains(.cancelled) || event.momentumPhase.contains(.ended)
                || event.momentumPhase.contains(.cancelled) { scrolling = false }
            return ownsGesture
        case .mouseMoved, .mouseEntered, .mouseExited, .cursorUpdate:
            return ownsPoint(event.locationInWindow)
        default:
            return ownsFocus
        }
    }

    private func ownsPoint(_ location: NSPoint) -> Bool {
        guard let content = window.contentView else { return false }
        let root = content.superview ?? content
        let point = root.superview?.convert(location, from: nil) ?? location
        guard let view = ownedView(for: root.hitTest(point)) else { return false }
        return acceptsInput(in: view)
    }

    private func acceptsInput(in view: NSView) -> Bool {
        !view.isHiddenOrHasHiddenAncestor
            && (sidebar.inputEnabled || !(view === sidebar || view.isDescendant(of: sidebar)))
    }

    func mount(sidebar: NSView?, chat: NSView?) {
        self.sidebar.mount(sidebar)
        self.chat.mount(chat)
    }
}

private final class OctronTelegramContainer: View {
    private weak var mountedView: NSView?
    var inputEnabled = true
    var minimumWidth: CGFloat = 0
    var contentHidden = false {
        didSet { mountedView?.isHidden = contentHidden }
    }

    private var contentFrame: NSRect {
        NSRect(x: bounds.minX, y: bounds.minY,
               width: max(minimumWidth, bounds.width), height: bounds.height)
    }

    func mount(_ view: NSView?) {
        guard mountedView !== view else { return }
        mountedView?.removeFromSuperview()
        mountedView = view
        if let view {
            view.frame = contentFrame
            view.isHidden = contentHidden
            addSubview(view)
        }
    }

    override func layout() {
        super.layout()
        mountedView?.frame = contentFrame
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        inputEnabled ? super.hitTest(point) : nil
    }
}
