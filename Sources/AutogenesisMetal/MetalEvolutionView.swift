import AppKit
import MetalKit
import SwiftUI
import simd

final class InteractiveMetalView: MTKView {
    var panHandler: ((SIMD2<Float>, Float) -> Void)?
    var zoomHandler: ((Double, SIMD2<Float>, Float) -> Void)?
    var resetCameraHandler: (() -> Void)?
    var cycleOrganismHandler: ((Int) -> Void)?
    var selectOrganismHandler: ((SIMD2<Float>, Float) -> Void)?
    private var lastDragPosition: SIMD2<Float>?
    private var mouseDownPosition: SIMD2<Float>?
    private var hasDragged = false
    private var pendingZoomLog = 0.0
    private var pendingZoomAnchor = SIMD2<Float>(repeating: 0.5)
    private var pendingZoomAspect: Float = 1
    private var zoomFlushTimer: Timer?
    private var lastAppliedZoomDirection = 0.0
    private var lastZoomApplicationTime = 0.0
    private var horizontalGestureConsumed = false
    private var lastHorizontalCycleTime = 0.0

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            resetCameraHandler?()
            lastDragPosition = nil
            mouseDownPosition = nil
            return
        }
        let position = normalizedPosition(for: event)
        lastDragPosition = position
        mouseDownPosition = position
        hasDragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        let position = normalizedPosition(for: event)
        guard let previous = lastDragPosition else {
            lastDragPosition = position
            return
        }
        let delta = position - previous
        if simd_length(position - (mouseDownPosition ?? position)) > 0.006 {
            hasDragged = true
        }
        lastDragPosition = position
        panHandler?(delta, aspect)
    }

    override func mouseUp(with event: NSEvent) {
        if !hasDragged, event.clickCount == 1 {
            selectOrganismHandler?(normalizedPosition(for: event), aspect)
        }
        lastDragPosition = nil
        mouseDownPosition = nil
        hasDragged = false
    }

    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY), abs(event.scrollingDeltaX) > 1.5 {
            handleHorizontalScroll(event)
            return
        }
        guard event.scrollingDeltaY.isFinite else { return }
        let sensitivity = event.hasPreciseScrollingDeltas ? 0.0024 : 0.018
        let momentumScale = event.momentumPhase.isEmpty ? 1.0 : 0.32
        let rawLogDelta = Double(-event.scrollingDeltaY) * sensitivity * momentumScale
        let eventLimit = event.hasPreciseScrollingDeltas ? 0.020 : 0.030
        enqueueZoom(
            logDelta: tanh(rawLogDelta / eventLimit) * eventLimit,
            anchor: normalizedPosition(for: event),
            aspect: aspect
        )
    }

    override func magnify(with event: NSEvent) {
        guard event.magnification.isFinite else { return }
        let boundedMagnification = min(max(Double(event.magnification), -0.20), 0.20)
        enqueueZoom(
            logDelta: log1p(boundedMagnification) * 0.72,
            anchor: normalizedPosition(for: event),
            aspect: aspect
        )
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            cancelPendingZoom()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func cancelPendingZoomForCommand() {
        cancelPendingZoom()
    }

    private func enqueueZoom(logDelta initialLogDelta: Double, anchor: SIMD2<Float>, aspect: Float) {
        guard initialLogDelta.isFinite, abs(initialLogDelta) >= 0.000_05 else { return }
        var logDelta = min(max(initialLogDelta, -0.025), 0.025)
        let now = ProcessInfo.processInfo.systemUptime
        let direction = logDelta.sign == .minus ? -1.0 : 1.0

        if lastAppliedZoomDirection != 0,
           direction != lastAppliedZoomDirection,
           now - lastZoomApplicationTime < 0.14 {
            logDelta *= 0.35
            pendingZoomLog *= 0.25
        } else if pendingZoomLog * logDelta < 0 {
            pendingZoomLog *= 0.25
            logDelta *= 0.50
        }

        // Log-space accumulation keeps equal inward and outward impulses reciprocal.
        pendingZoomLog = min(max(pendingZoomLog + logDelta, -0.022), 0.022)
        pendingZoomAnchor = anchor
        pendingZoomAspect = aspect
        guard zoomFlushTimer == nil else { return }

        let timer = Timer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(flushPendingZoom),
            userInfo: nil,
            repeats: false
        )
        zoomFlushTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func flushPendingZoom() {
        zoomFlushTimer = nil
        let logDelta = pendingZoomLog
        pendingZoomLog = 0
        guard abs(logDelta) >= 0.000_05 else { return }

        lastAppliedZoomDirection = logDelta.sign == .minus ? -1.0 : 1.0
        lastZoomApplicationTime = ProcessInfo.processInfo.systemUptime
        zoomHandler?(exp(logDelta), pendingZoomAnchor, pendingZoomAspect)
    }

    private func cancelPendingZoom() {
        zoomFlushTimer?.invalidate()
        zoomFlushTimer = nil
        pendingZoomLog = 0
    }

    private func handleHorizontalScroll(_ event: NSEvent) {
        if event.phase == .began {
            horizontalGestureConsumed = false
        }
        defer {
            if event.phase == .ended || event.phase == .cancelled {
                horizontalGestureConsumed = false
            }
        }
        guard event.momentumPhase.isEmpty else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let gestureHasPhase = !event.phase.isEmpty
        guard !horizontalGestureConsumed,
              now - lastHorizontalCycleTime >= 0.24 else { return }
        cycleOrganismHandler?(event.scrollingDeltaX < 0 ? -1 : 1)
        lastHorizontalCycleTime = now
        if gestureHasPhase {
            horizontalGestureConsumed = true
        }
    }

    private var aspect: Float {
        bounds.height > 0 ? Float(bounds.width / bounds.height) : 1
    }

    private func normalizedPosition(for event: NSEvent) -> SIMD2<Float> {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.width > 0, bounds.height > 0 else { return SIMD2<Float>(repeating: 0.5) }
        return SIMD2<Float>(
            Float(min(max(point.x / bounds.width, 0), 1)),
            Float(min(max(1 - point.y / bounds.height, 0), 1))
        )
    }
}

struct MetalEvolutionView: NSViewRepresentable {
    @ObservedObject var store: EvolutionStore

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeNSView(context: Context) -> InteractiveMetalView {
        let view = InteractiveMetalView(frame: .zero)
        view.autoresizingMask = [.width, .height]
        do {
            let renderer = try EvolutionRenderer(view: view)
            renderer.onSnapshot = { snapshot in
                Task { @MainActor in
                    store.apply(snapshot)
                }
            }
            renderer.onObservationBatch = { events, observations, cellObservations in
                Task { @MainActor in
                    if !events.isEmpty {
                        store.applyLineageEvents(events)
                    }
                    store.applyAgentObservations(
                        observations,
                        cellObservations: cellObservations
                    )
                }
            }
            renderer.onRuntimeTelemetry = { telemetry in
                Task { @MainActor in store.applyRuntimeTelemetry(telemetry) }
            }
            context.coordinator.renderer = renderer
            context.coordinator.startBackgroundTick(for: view)
            view.delegate = renderer
            view.panHandler = { [weak coordinator = context.coordinator] delta, aspect in
                coordinator?.pan(by: delta, aspect: aspect)
            }
            view.zoomHandler = { [weak coordinator = context.coordinator] factor, anchor, aspect in
                coordinator?.zoom(by: factor, around: anchor, aspect: aspect)
            }
            view.resetCameraHandler = { [weak coordinator = context.coordinator, weak view] in
                view?.cancelPendingZoomForCommand()
                coordinator?.store.resetCamera()
            }
            view.cycleOrganismHandler = { [weak coordinator = context.coordinator] direction in
                coordinator?.store.followAdjacentOrganism(direction: direction)
            }
            view.selectOrganismHandler = { [weak coordinator = context.coordinator] position, aspect in
                coordinator?.store.followOrganism(at: position, aspect: aspect)
            }
        } catch {
            store.report(error: error)
        }
        return view
    }

    func updateNSView(_ view: InteractiveMetalView, context: Context) {
        context.coordinator.store = store
        context.coordinator.renderer?.update(settings: store.rendererSettings)
    }

    @MainActor
    final class Coordinator {
        var store: EvolutionStore
        var renderer: EvolutionRenderer?
        private var backgroundTimer: Timer?
        private var activationObserver: NSObjectProtocol?

        init(store: EvolutionStore) {
            self.store = store
        }

        isolated deinit {
            backgroundTimer?.invalidate()
            if let activationObserver {
                NotificationCenter.default.removeObserver(activationObserver)
            }
        }

        func startBackgroundTick(for view: InteractiveMetalView) {
            backgroundTimer?.invalidate()
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) {
                [weak view] _ in
                Task { @MainActor [weak view] in
                    guard let view,
                          view.window?.occlusionState.contains(.visible) != true else { return }
                    view.draw()
                }
            }
            backgroundTimer = timer
            RunLoop.main.add(timer, forMode: .common)
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak view] _ in
                Task { @MainActor [weak view] in
                    view?.isPaused = false
                    view?.setNeedsDisplay(view?.bounds ?? .zero)
                }
            }
        }

        func pan(by delta: SIMD2<Float>, aspect: Float) {
            store.pan(by: delta, aspect: aspect)
        }

        func zoom(by factor: Double, around anchor: SIMD2<Float>, aspect: Float) {
            store.zoom(by: factor, around: anchor, aspect: aspect)
        }
    }
}
