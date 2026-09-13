import AppKit
import OctronTelegram
import TGUIKit

@main
@MainActor
enum InputOwnershipProof {
    static func main() {
        guard CommandLine.arguments.count == 2,
              let loaded = Bundle(for: OctronTelegramHost.self).executableURL,
              loaded.resolvingSymlinksInPath() == URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath()
        else {
            print("The input check loaded a different Telegram framework")
            exit(1)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var checks: [String: Bool] = ["loadedFrameworkMatchesRequestedArtifact": true]
        let nativeWindow = OctronTelegramHost.makeWindow(
            withContentRect: NSRect(x: -10000, y: -10000, width: 600, height: 400))
        nativeWindow.isReleasedWhenClosed = false
        let window = nativeWindow as! Window
        var priorScopeCalls = 0
        var priorAllows = true
        var priorResponders: [ObjectIdentifier?] = []
        window.handlerScope = { _ in priorScopeCalls += 1; return priorAllows }
        window.firstResponderFilter = { responder in
            priorResponders.append(responder.map(ObjectIdentifier.init))
            return responder
        }
        let host = OctronTelegramHost(window: window)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        window.contentView = root
        host.chatView.frame = NSRect(x: 0, y: 0, width: 380, height: 400)
        root.addSubview(host.chatView)
        let nativeField = NSTextField(frame: NSRect(x: 20, y: 200, width: 240, height: 28))
        let foreignField = NSTextField(frame: NSRect(x: 410, y: 200, width: 170, height: 28))
        host.chatView.addSubview(nativeField)
        root.addSubview(foreignField)
        let foreignPointer = PointerSink(frame: NSRect(x: 410, y: 40, width: 170, height: 80))
        root.addSubview(foreignPointer)
        let identity = NSObject()
        var keys = 0
        var releases = 0
        var pushToTalk = 0
        var mouseDowns = 0
        var drags = 0
        var mouseUps = 0
        window.set(responder: { nativeField }, with: identity, priority: .high)
        window.set(handler: { _ in keys += 1; return .invoked }, with: identity,
                   for: .All, priority: .supreme)
        window.keyUpHandler = { _ in releases += 1 }
        window.isPushToTalkEquaivalent = { _ in pushToTalk += 1; return false }
        window.set(mouseHandler: { _ in
            mouseDowns += 1
            _ = window.makeFirstResponder(nativeField)
            return .invoked
        }, with: identity, for: .leftMouseDown)
        window.set(mouseHandler: { _ in drags += 1; return .invoked },
                   with: identity, for: .leftMouseDragged)
        window.set(mouseHandler: { _ in mouseUps += 1; return .invoked },
                   with: identity, for: .leftMouseUp)

        _ = window.makeFirstResponder(foreignField)
        let foreignEditor = foreignField.currentEditor() as? NSTextView
        foreignEditor?.string = "Foreign draft"
        _ = window.makeFirstResponder(nativeField)
        checks["inactiveNativeFocusRejected"] = foreignField.currentEditor() === foreignEditor
        host.setActive(true)
        if let close = window.standardWindowButton(.closeButton) {
            let point = close.convert(NSPoint(x: close.bounds.midX, y: close.bounds.midY), to: nil)
            checks["nativeWindowControlIsNotTelegramInput"] = window.handlerScope?(
                mouse(.leftMouseDown, point: point, window: window)) == false
        } else { checks["nativeWindowControlIsNotTelegramInput"] = false }
        window.applyResponderIfNeeded()
        checks["implicitResponderPreservesForeignEditor"] = foreignEditor != nil
            && window.firstResponder === foreignEditor && foreignField.currentEditor() === foreignEditor
        let down = key(.keyDown, window: window)
        let up = key(.keyUp, window: window)
        _ = window.performKeyEquivalent(with: down)
        window.sendEvent(down)
        window.sendEvent(up)
        checks["foreignTypingBypassesNativeHandlers"] = keys == 0 && releases == 0 && pushToTalk == 0
            && window.firstResponder === foreignEditor

        _ = window.makeFirstResponder(nativeField)
        let nativeEditor = nativeField.currentEditor() as? NSTextView
        nativeEditor?.string = "Native draft"
        _ = window.performKeyEquivalent(with: down)
        window.sendEvent(down)
        window.applyResponderIfNeeded(down)
        checks["repeatedNativeKeyPredicateKeepsOneAction"] = nativeEditor != nil
            && keys == 1 && pushToTalk == 1 && window.firstResponder === nativeEditor
        _ = window.makeFirstResponder(foreignField)
        window.sendEvent(up)
        window.sendEvent(up)
        checks["ownedKeyReleaseCompletesOnlyOnceAcrossFocusChange"] = releases == 1
            && window.firstResponder === foreignField.currentEditor()

        let nativePoint = nativeField.convert(NSPoint(x: 10, y: 10), to: nil)
        let foreignPoint = foreignPointer.convert(NSPoint(x: 10, y: 10), to: nil)
        window.sendEvent(mouse(.leftMouseDown, point: nativePoint, window: window))
        checks["pointerEntersNativePanelFromForeignEditor"] = mouseDowns == 1
            && nativeField.currentEditor() != nil
        window.sendEvent(mouse(.leftMouseDragged, point: foreignPoint, window: window))
        window.sendEvent(mouse(.leftMouseUp, point: foreignPoint, window: window))
        window.sendEvent(mouse(.leftMouseUp, point: foreignPoint, window: window))
        checks["ownedDragEndsOnceOutsidePanel"] = drags == 1 && mouseUps == 1
        window.sendEvent(mouse(.leftMouseDown, point: foreignPoint, window: window))
        window.sendEvent(mouse(.leftMouseDragged, point: nativePoint, window: window))
        checks["foreignPointerDoesNotBecomeNativeMidDrag"] = mouseDowns == 1 && drags == 1

        checkScrolling(window: window, nativePoint: nativePoint, foreignPoint: foreignPoint, checks: &checks)
        checkSidebarInput(host: host, window: window, root: root, chatField: nativeField, checks: &checks)

        _ = window.makeFirstResponder(nativeField)
        nativeField.isHidden = true
        let afterHiding = window.firstResponder
        _ = window.makeFirstResponder(nativeField)
        window.applyResponderIfNeeded()
        checks["hiddenNativeInputCannotReacquireFocus"] = nativeField.currentEditor() == nil
            && window.firstResponder === afterHiding
        nativeField.isHidden = false
        let modalField = NSSecureTextField(frame: NSRect(x: 20, y: 280, width: 240, height: 28))
        host.chatView.addSubview(modalField)
        _ = window.makeFirstResponder(modalField)
        checks["nativeModalFieldRemainsOwned"] = modalField.currentEditor() != nil
            && window.handlerScope?(down) == true
        host.setActive(false)
        checks["deactivationClearsNativeSharedFieldEditor"] = modalField.currentEditor() == nil
        _ = window.makeFirstResponder(modalField)
        checks["inactiveSharedFieldEditorCannotReenter"] = modalField.currentEditor() == nil
        host.setActive(true)
        _ = window.makeFirstResponder(nativeField)
        priorAllows = false
        checks["priorScopeRejectionPreserved"] = window.handlerScope?(down) == false
        host.stop()
        let beforeStopScope = priorScopeCalls
        priorAllows = true
        checks["stopRestoresPriorScope"] = window.handlerScope?(down) == true
            && priorScopeCalls == beforeStopScope + 1
        let beforeStopResponder = priorResponders.count
        _ = window.makeFirstResponder(nativeField)
        checks["stopRestoresPriorResponderFilter"] = nativeField.currentEditor().map { editor in
            Array(priorResponders.dropFirst(beforeStopResponder)) == [
                ObjectIdentifier(nativeField), ObjectIdentifier(editor),
            ]
        } ?? false
        checks["retainedNativeViews"] = host.chatView.superview === root
        checkNavigationBackground(window: window, checks: &checks)
        checks["neverDisplayedOrActivated"] = !window.isVisible && !app.isActive
        window.close()
        checks["foregroundUnchanged"] = NSWorkspace.shared.frontmostApplication?.processIdentifier == foreground
        let result: [String: Any] = ["checks": checks, "passed": !checks.values.contains(false)]
        let data = try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        exit(checks.values.contains(false) ? 1 : 0)
    }

    private static func checkNavigationBackground(window: Window, checks: inout [String: Bool]) {
        let resources = Bundle(for: OctronTelegramHost.self)
        for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_NavigationBack"] {
            guard let image = resources.image(forResource: name) else {
                checks["navigationResource_" + name] = false
                return
            }
            image.setName(name)
        }
        let page = GenericViewController<View>()
        let navigation = NavigationViewController(page, window)
        navigation.applyAppearOnLoad = false
        navigation.drawsBackground = false
        _ = navigation.view
        checks["embeddedNavigationStartsTransparent"] = navigation.backgroundColor.alphaComponent == 0
            && navigation.navigationBar.backgroundColor.alphaComponent == 0
            && navigation.navigationBar.layer?.isOpaque == false
        for _ in 0..<3 {
            navigation.backgroundColor = .black
            navigation.updateLocalizationAndTheme(theme: presentation)
            page.leftBarView.updateLocalizationAndTheme(theme: presentation)
            page.centerBarView.updateLocalizationAndTheme(theme: presentation)
            page.rightBarView.updateLocalizationAndTheme(theme: presentation)
        }
        checks["embeddedNavigationSurvivesThemeRepaint"] = navigation.backgroundColor.alphaComponent == 0
            && navigation.view.layer?.isOpaque == false
            && navigation.navigationBar.backgroundColor.alphaComponent == 0
        checks["embeddedNavigationHeadersRemainTransparent"] = [page.leftBarView, page.centerBarView, page.rightBarView]
            .allSatisfy { $0.backgroundColor.alphaComponent == 0 && $0.layer?.isOpaque == false }
        checks["embeddedHeaderPreservesForeground"] = page.barPresentation.foregroundColor
            == navigationButtonStyle.foregroundColor
        navigation.drawsBackground = true
        page.centerBarView.updateLocalizationAndTheme(theme: presentation)
        checks["ordinaryNavigationKeepsItsMaterial"] = navigation.backgroundColor == presentation.colors.background
            && navigation.navigationBar.backgroundColor == presentation.colors.background
            && page.centerBarView.backgroundColor == presentation.colors.background
    }

    private static func checkSidebarInput(
        host: OctronTelegramHost, window: Window, root: NSView,
        chatField: NSTextField, checks: inout [String: Bool]
    ) {
        let sidebar = host.sidebarView
        let frame = NSRect(x: 400, y: 260, width: 180, height: 100)
        sidebar.frame = frame
        root.addSubview(sidebar)
        let field = NSTextField(frame: NSRect(x: 12, y: 12, width: 156, height: 28))
        field.stringValue = "Retained sidebar draft"
        sidebar.addSubview(field)
        let point = field.convert(NSPoint(x: 10, y: 10), to: root)
        let down = mouse(.leftMouseDown, point: root.convert(point, to: nil), window: window)
        _ = window.makeFirstResponder(field)
        checks["sidebarInitiallyReceivesFocusAndPointer"] = field.currentEditor() != nil
            && sidebar.hitTest(point) != nil && window.handlerScope?(down) == true
        host.setSidebarInputEnabled(false)
        checks["disablingSidebarRevokesSharedEditor"] = field.currentEditor() == nil
        checks["disabledSidebarRejectsDirectHitAndNativePointer"] = sidebar.hitTest(point) == nil
            && window.handlerScope?(down) == false
        _ = window.makeFirstResponder(chatField)
        let chatEditor = chatField.currentEditor()
        checks["disabledSidebarPreservesVisibleChatFocus"] = chatEditor != nil
            && window.handlerScope?(nil) == true && window.handlersEnabled
        _ = window.makeFirstResponder(field)
        checks["disabledSidebarCannotReacquireFocus"] = field.currentEditor() == nil
            && chatField.currentEditor() === chatEditor && window.firstResponder === chatEditor
        checks["disablingSidebarPreservesPaintAndIdentity"] = host.sidebarView === sidebar
            && sidebar.superview === root && sidebar.frame == frame && !sidebar.isHidden
            && sidebar.alphaValue == 1 && field.superview === sidebar
        host.setSidebarInputEnabled(true)
        _ = window.makeFirstResponder(field)
        checks["reenabledSidebarRestoresInputAndDraft"] = field.currentEditor() != nil
            && field.stringValue == "Retained sidebar draft" && sidebar.hitTest(point) != nil
        _ = window.makeFirstResponder(chatField)
    }

    private static func checkScrolling(
        window: Window, nativePoint: NSPoint, foreignPoint: NSPoint, checks: inout [String: Bool]
    ) {
        let scroll = ScrollFixture(window: window, point: nativePoint, phase: .began)
        checks["nativeScrollBegins"] = window.handlerScope?(scroll) == true
        scroll.point = foreignPoint
        scroll.currentPhase = .changed
        checks["nativeScrollContinuesAcrossPanelBoundary"] = window.handlerScope?(scroll) == true
        scroll.currentPhase = .ended
        checks["nativeScrollEnd"] = window.handlerScope?(scroll) == true
        scroll.currentPhase = []
        scroll.currentMomentum = .began
        checks["nativeMomentumKeepsItsOriginalOwner"] = window.handlerScope?(scroll) == true
        scroll.currentMomentum = .ended
        checks["nativeMomentumEnds"] = window.handlerScope?(scroll) == true
        scroll.currentMomentum = []
        scroll.currentPhase = .began
        checks["foreignScrollRejected"] = window.handlerScope?(scroll) == false
        scroll.point = nativePoint
        scroll.currentPhase = .changed
        checks["foreignScrollCannotEnterNativeMidGesture"] = window.handlerScope?(scroll) == false

    }

    private static func key(_ type: NSEvent.EventType, window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                        windowNumber: window.windowNumber, context: nil, characters: "a",
                        charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
    }

    private static func mouse(_ type: NSEvent.EventType, point: NSPoint, window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                          windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                          clickCount: 1, pressure: 1)!
    }
}

private final class PointerSink: NSView {
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
}

private final class ScrollFixture: NSEvent {
    private let owner: NSWindow
    var point: NSPoint
    var currentPhase: Phase
    var currentMomentum: Phase = []
    init(window: NSWindow, point: NSPoint, phase: Phase) {
        owner = window
        self.point = point
        currentPhase = phase
        super.init()
    }
    override var type: EventType { .scrollWheel }
    override var window: NSWindow? { owner }
    override var locationInWindow: NSPoint { point }
    override var phase: Phase { currentPhase }
    override var momentumPhase: Phase { currentMomentum }
    required init?(coder: NSCoder) { fatalError("Unused fixture decoder") }
}
