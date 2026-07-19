import AppKit
import MetalKit
import SwiftUI
import simd

final class InteractiveMetalView: MTKView {
    var panHandler: ((SIMD2<Float>, Float) -> Void)?
    var zoomHandler: ((Double, SIMD2<Float>, Float) -> Void)?
    var resetCameraHandler: (() -> Void)?
    var cycleOrganismHandler: ((Int) -> Void)?
    private var lastDragPosition: SIMD2<Float>?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            resetCameraHandler?()
            lastDragPosition = nil
            return
        }
        let position = normalizedPosition(for: event)
        lastDragPosition = position
    }

    override func mouseDragged(with event: NSEvent) {
        let position = normalizedPosition(for: event)
        guard let previous = lastDragPosition else {
            lastDragPosition = position
            return
        }
        let delta = position - previous
        lastDragPosition = position
        panHandler?(delta, aspect)
    }

    override func mouseUp(with event: NSEvent) {
        lastDragPosition = nil
    }

    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY), abs(event.scrollingDeltaX) > 1.5 {
            cycleOrganismHandler?(event.scrollingDeltaX < 0 ? -1 : 1)
            return
        }
        let sensitivity = event.hasPreciseScrollingDeltas ? 0.012 : 0.08
        let factor = exp(Double(-event.scrollingDeltaY) * sensitivity)
        zoomHandler?(factor, normalizedPosition(for: event), aspect)
    }

    override func magnify(with event: NSEvent) {
        zoomHandler?(max(0.05, 1 + Double(event.magnification)), normalizedPosition(for: event), aspect)
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
            renderer.onAgentObservations = { observations in
                Task { @MainActor in
                    store.applyAgentObservations(observations)
                }
            }
            context.coordinator.renderer = renderer
            view.delegate = renderer
            view.panHandler = { [weak coordinator = context.coordinator] delta, aspect in
                coordinator?.pan(by: delta, aspect: aspect)
            }
            view.zoomHandler = { [weak coordinator = context.coordinator] factor, anchor, aspect in
                coordinator?.zoom(by: factor, around: anchor, aspect: aspect)
            }
            view.resetCameraHandler = { [weak coordinator = context.coordinator] in
                coordinator?.store.resetCamera()
            }
            view.cycleOrganismHandler = { [weak coordinator = context.coordinator] direction in
                coordinator?.store.followAdjacentOrganism(direction: direction)
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

        init(store: EvolutionStore) {
            self.store = store
        }

        func pan(by delta: SIMD2<Float>, aspect: Float) {
            store.pan(by: delta, aspect: aspect)
        }

        func zoom(by factor: Double, around anchor: SIMD2<Float>, aspect: Float) {
            store.zoom(by: factor, around: anchor, aspect: aspect)
        }
    }
}
