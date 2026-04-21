import Foundation

final class SplitScrollBridge: ObservableObject {
    private var sourceScrollHandler: ((Double) -> Void)?
    private var previewScrollHandler: ((Double) -> Void)?
    private var suppressSourceCallback = false
    private var suppressPreviewCallback = false
    private var lastSourceProgress = 0.0
    private var lastPreviewProgress = 0.0
    private var preferredProgressSource: Side = .preview

    func registerSourceScrollHandler(_ handler: @escaping (Double) -> Void) {
        sourceScrollHandler = handler
        applyCurrentProgress(to: .source)
    }

    func registerPreviewScrollHandler(_ handler: @escaping (Double) -> Void) {
        previewScrollHandler = handler
        applyCurrentProgress(to: .preview)
    }

    func unregisterSourceScrollHandler() {
        sourceScrollHandler = nil
    }

    func unregisterPreviewScrollHandler() {
        previewScrollHandler = nil
    }

    func reset() {
        lastSourceProgress = 0
        lastPreviewProgress = 0
        preferredProgressSource = .preview
        suppressSourceCallback = false
        suppressPreviewCallback = false
    }

    func sourceDidScroll(to progress: Double) {
        let clamped = clamp(progress)
        lastSourceProgress = clamped

        if suppressSourceCallback {
            suppressSourceCallback = false
            return
        }

        preferredProgressSource = .source
        guard let previewScrollHandler else { return }
        suppressPreviewCallback = true
        previewScrollHandler(clamped)
    }

    func previewDidScroll(to progress: Double) {
        let clamped = clamp(progress)
        lastPreviewProgress = clamped

        if suppressPreviewCallback {
            suppressPreviewCallback = false
            return
        }

        preferredProgressSource = .preview
        guard let sourceScrollHandler else { return }
        suppressSourceCallback = true
        sourceScrollHandler(clamped)
    }

    private func applyCurrentProgress(to side: Side) {
        let currentProgress = preferredProgressSource == .source ? lastSourceProgress : lastPreviewProgress

        switch side {
        case .source:
            guard let sourceScrollHandler else { return }
            suppressSourceCallback = true
            sourceScrollHandler(currentProgress)
        case .preview:
            guard let previewScrollHandler else { return }
            suppressPreviewCallback = true
            previewScrollHandler(currentProgress)
        }
    }

    private func clamp(_ progress: Double) -> Double {
        min(max(progress, 0), 1)
    }

    private enum Side {
        case source
        case preview
    }
}
