import AppKit
import SwiftUI

private final class ObservingScrollView: NSScrollView {
    var onScroll: (() -> Void)?

    override func reflectScrolledClipView(_ cView: NSClipView) {
        super.reflectScrolledClipView(cView)
        onScroll?()
    }
}

struct SourceTextView: NSViewRepresentable {
    let text: String
    let fontSize: Double
    let isEditable: Bool
    let scrollBridge: SplitScrollBridge?
    let onTextChange: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = ObservingScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.underPageBackgroundColor

        let textView = NSTextView(frame: .zero)
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.usesFindBar = true
        textView.usesFontPanel = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true
        context.coordinator.attach(scrollView: scrollView, bridge: scrollBridge)
        scrollView.onScroll = { [weak coordinator = context.coordinator] in
            Task { @MainActor [weak coordinator] in
                coordinator?.handleScrollEvent()
            }
        }
        update(textView, in: scrollView, coordinator: context.coordinator)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.attach(scrollView: scrollView, bridge: scrollBridge)
        guard let textView = scrollView.documentView as? NSTextView else { return }
        update(textView, in: scrollView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    private func update(_ textView: NSTextView, in scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.onTextChange = onTextChange

        if coordinator.lastText != text {
            textView.string = text.isEmpty ? "No document selected." : text
            coordinator.lastText = text
            coordinator.scrollToProgress(0, in: scrollView)
        }

        if coordinator.lastFontSize != fontSize {
            textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
            coordinator.lastFontSize = fontSize
        }

        textView.isEditable = isEditable
        textView.textColor = .textColor
        textView.insertionPointColor = .clear
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var lastText = ""
        var lastFontSize = 0.0
        var onTextChange: ((String) -> Void)?
        private weak var scrollView: NSScrollView?
        private weak var scrollBridge: SplitScrollBridge?

        func attach(scrollView: NSScrollView, bridge: SplitScrollBridge?) {
            let scrollViewChanged = self.scrollView !== scrollView
            if self.scrollView !== scrollView {
                self.scrollView = scrollView
            }

            let bridgeChanged = self.scrollBridge !== bridge
            self.scrollBridge = bridge

            if bridgeChanged || scrollViewChanged {
                bridge?.registerSourceScrollHandler { [weak self] progress in
                    guard let self, let scrollView = self.scrollView else { return }
                    self.scrollToProgress(progress, in: scrollView)
                }
            }
        }

        func detach() {
            scrollBridge?.unregisterSourceScrollHandler()
            if let scrollView = scrollView as? ObservingScrollView {
                scrollView.onScroll = nil
            }
            scrollView = nil
            scrollBridge = nil
        }

        func scrollToProgress(_ progress: Double, in scrollView: NSScrollView) {
            guard let documentView = scrollView.documentView else { return }
            let maxOffset = max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
            let offset = maxOffset * min(max(progress, 0), 1)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: offset))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        func handleScrollEvent() {
            guard let scrollView, let documentView = scrollView.documentView else { return }
            let maxOffset = max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
            let progress: Double

            if maxOffset > 0 {
                progress = min(max(scrollView.contentView.bounds.origin.y / maxOffset, 0), 1)
            } else {
                progress = 0
            }

            scrollBridge?.sourceDidScroll(to: progress)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let updatedText = textView.string
            guard updatedText != lastText else { return }
            lastText = updatedText
            onTextChange?(updatedText)
        }
    }
}
