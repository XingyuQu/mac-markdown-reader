import AppKit
import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    let navigationRequest: PreviewNavigationRequest?
    let scrollBridge: SplitScrollBridge?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "readerScrollSync")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        context.coordinator.attach(webView: webView, bridge: scrollBridge)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.attach(webView: webView, bridge: scrollBridge)
        let currentHTML = context.coordinator.lastHTML
        let currentBasePath = context.coordinator.lastBaseURL?.path
        let newBasePath = baseURL?.path
        let needsReload = currentHTML != html || currentBasePath != newBasePath

        if needsReload {
            context.coordinator.lastHTML = html
            context.coordinator.lastBaseURL = baseURL
            context.coordinator.isDocumentReady = false
            context.coordinator.pendingTargetID = navigationRequest?.targetID
            if let requestID = navigationRequest?.id {
                context.coordinator.lastNavigationRequestID = requestID
            }
            webView.loadHTMLString(html, baseURL: baseURL)
            return
        }

        guard let navigationRequest else { return }
        guard context.coordinator.lastNavigationRequestID != navigationRequest.id else { return }
        context.coordinator.lastNavigationRequestID = navigationRequest.id
        context.coordinator.scrollToAnchor(navigationRequest.targetID, in: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "readerScrollSync")
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastHTML = ""
        var lastBaseURL: URL?
        var lastNavigationRequestID: PreviewNavigationRequest.ID?
        var pendingTargetID: String?
        var pendingScrollProgress: Double?
        var isDocumentReady = false
        private weak var webView: WKWebView?
        private weak var scrollBridge: SplitScrollBridge?

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
            }
            return nil
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
                return .allow
            }

            if url.fragment != nil, (url.scheme == nil || url.scheme == "file") {
                return .allow
            }

            NSWorkspace.shared.open(url)
            return .cancel
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isDocumentReady = true

            if let pendingScrollProgress {
                self.pendingScrollProgress = nil
                applyScrollProgress(pendingScrollProgress, in: webView)
            }

            guard let pendingTargetID else { return }
            self.pendingTargetID = nil
            scrollToAnchor(pendingTargetID, in: webView)
        }

        func scrollToAnchor(_ targetID: String, in webView: WKWebView) {
            guard !targetID.isEmpty else { return }
            guard isDocumentReady else {
                pendingTargetID = targetID
                return
            }

            let quotedTargetID = targetID
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let script = """
            window.codexMarkdownJumpToAnchor && window.codexMarkdownJumpToAnchor("\(quotedTargetID)");
            """
            webView.evaluateJavaScript(script)
        }

        func attach(webView: WKWebView, bridge: SplitScrollBridge?) {
            let webViewChanged = self.webView !== webView
            self.webView = webView
            let bridgeChanged = self.scrollBridge !== bridge
            self.scrollBridge = bridge

            if bridgeChanged || webViewChanged {
                bridge?.registerPreviewScrollHandler { [weak self] progress in
                    guard let self, let webView = self.webView else { return }
                    self.applyScrollProgress(progress, in: webView)
                }
            }
        }

        func detach() {
            scrollBridge?.unregisterPreviewScrollHandler()
            webView = nil
            scrollBridge = nil
            pendingScrollProgress = nil
        }

        private func applyScrollProgress(_ progress: Double, in webView: WKWebView) {
            guard isDocumentReady else {
                pendingScrollProgress = progress
                return
            }

            let clamped = min(max(progress, 0), 1)
            if
                let nativeScrollView = scrollView(for: webView),
                let documentView = nativeScrollView.documentView
            {
                let maxOffset = max(0, documentView.bounds.height - nativeScrollView.contentView.bounds.height)
                let offset = maxOffset * clamped
                nativeScrollView.contentView.scroll(to: NSPoint(x: 0, y: offset))
                nativeScrollView.reflectScrolledClipView(nativeScrollView.contentView)
            }

            let script = """
            window.codexSetScrollProgress && window.codexSetScrollProgress(\(clamped));
            """
            webView.evaluateJavaScript(script)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "readerScrollSync" else { return }
            let progress: Double
            if let number = message.body as? NSNumber {
                progress = number.doubleValue
            } else if let value = message.body as? Double {
                progress = value
            } else {
                return
            }
            scrollBridge?.previewDidScroll(to: progress)
        }

        private func scrollView(for webView: WKWebView) -> NSScrollView? {
            findScrollView(in: webView)
        }

        private func findScrollView(in view: NSView) -> NSScrollView? {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }

            for subview in view.subviews {
                if let scrollView = findScrollView(in: subview) {
                    return scrollView
                }
            }

            return nil
        }
    }
}
