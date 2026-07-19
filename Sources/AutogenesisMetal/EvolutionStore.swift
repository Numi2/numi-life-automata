import AutogenesisCore
import Combine
import Foundation
import simd

enum FieldDisplayMode: UInt32, CaseIterable, Identifiable {
    case ecology
    case energy
    case genome
    case niches

    var id: UInt32 { rawValue }

    var label: String {
        switch self {
        case .ecology: "State fields"
        case .energy: "Resource / energy"
        case .genome: "Trait vectors"
        case .niches: "Resource-use traits"
        }
    }
}

enum EvolutionEventKind: Sendable, Equatable {
    case founding
    case expansion
    case branching
    case scarcity
    case disturbance
    case equilibrium
    case intervention
    case observation
}

struct EvolutionEvent: Identifiable, Sendable, Equatable {
    let id: UInt64
    let generation: Int
    let kind: EvolutionEventKind
    let title: String
    let detail: String
}

struct EvolutionSnapshot: Sendable, Equatable {
    var generation: Int = 0
    var totalSteps: UInt64 = 0
    var selectedWorld: Int = 0
    var archiveCount: Int = 0
    var quantumNorm: Double = 0
    var organismCount: Int = 0
    var hunterCount: Int = 0
    var organismLineageCount: Int = 0
    var meanOrganismSpeed: Double = 0
    var metrics: WorldMetrics = .empty
    var fitness = FitnessVector(viability: 0, adaptiveComplexity: 0, recovery: 0, novelty: 0)

    init(
        generation: Int = 0,
        totalSteps: UInt64 = 0,
        selectedWorld: Int = 0,
        archiveCount: Int = 0,
        quantumNorm: Double = 0,
        organismCount: Int = 0,
        hunterCount: Int = 0,
        organismLineageCount: Int = 0,
        meanOrganismSpeed: Double = 0,
        metrics: WorldMetrics = .empty,
        fitness: FitnessVector = FitnessVector(viability: 0, adaptiveComplexity: 0, recovery: 0, novelty: 0)
    ) {
        self.generation = generation
        self.totalSteps = totalSteps
        self.selectedWorld = selectedWorld
        self.archiveCount = archiveCount
        self.quantumNorm = quantumNorm
        self.organismCount = organismCount
        self.hunterCount = hunterCount
        self.organismLineageCount = organismLineageCount
        self.meanOrganismSpeed = meanOrganismSpeed
        self.metrics = metrics
        self.fitness = fitness
    }
}

struct RendererSettings: Sendable {
    var isRunning: Bool
    var stepsPerFrame: Int
    var resourceFlux: Float
    var mutationScale: Float
    var transportScale: Float
    var displayMode: UInt32
    var trackedAgentID: UInt32
    var cameraCenter: SIMD2<Float>
    var cameraZoom: Float
    var worldScale: Float
    var addColonyPosition: SIMD2<Float>
    var addColonyToken: UInt64
    var expansionToken: UInt64
    var resetToken: UInt64
}

@MainActor
final class EvolutionStore: ObservableObject {
    private static let spinorOrigin = SIMD2<Float>(repeating: 0.500_488_281_25)

    @Published var isRunning = true
    @Published var stepsPerFrame = 3
    @Published var resourceFlux: Double = 1.0
    @Published var mutationScale: Double = 1.0
    @Published var transportScale: Double = 1.0
    @Published var displayMode: FieldDisplayMode = .ecology
    @Published private(set) var cameraCenter = spinorOrigin
    @Published private(set) var cameraZoom: Double = 900
    @Published private(set) var snapshot = EvolutionSnapshot()
    @Published private(set) var history: [EvolutionSnapshot] = []
    @Published private(set) var events: [EvolutionEvent] = []
    @Published private(set) var founderCount = 0
    @Published private(set) var followedAgentID: Int?
    @Published private(set) var observableAgentCount = 0
    @Published private(set) var worldScale: Double = 1
    @Published private(set) var errorMessage: String?
    private var addColonyPosition = SIMD2<Float>(repeating: 0.5)
    private var addColonyToken: UInt64 = 0
    private var addedColonyCount = 0
    private var resetToken: UInt64 = 1
    private var expansionToken: UInt64 = 0
    private var nextEventID: UInt64 = 1
    private var lastRecordedGeneration = 0
    private var observedAgents: [AgentObservation] = []
    private var hasObservedFirstOrganism = false

    var rendererSettings: RendererSettings {
        RendererSettings(
            isRunning: isRunning,
            stepsPerFrame: stepsPerFrame,
            resourceFlux: Float(resourceFlux),
            mutationScale: Float(mutationScale),
            transportScale: Float(transportScale),
            displayMode: displayMode.rawValue,
            trackedAgentID: followedAgentID.map(UInt32.init) ?? .max,
            cameraCenter: cameraCenter,
            cameraZoom: Float(cameraZoom),
            worldScale: Float(worldScale),
            addColonyPosition: addColonyPosition,
            addColonyToken: addColonyToken,
            expansionToken: expansionToken,
            resetToken: resetToken
        )
    }

    func restart() {
        resetToken &+= 1
        snapshot = EvolutionSnapshot()
        history.removeAll(keepingCapacity: true)
        events.removeAll(keepingCapacity: true)
        addedColonyCount = 0
        founderCount = 0
        worldScale = 1
        expansionToken = 0
        lastRecordedGeneration = 0
        hasObservedFirstOrganism = false
        resetCamera()
    }

    func addColony() {
        let angle = Float(addedColonyCount) * 2.3999632
        let visibleRadius = Float(min(0.24 / max(cameraZoom, 0.001), 0.24))
        let offset = SIMD2<Float>(cos(angle), sin(angle)) * visibleRadius
        addColonyPosition = textureCoordinate(cameraCenter + offset)
        addedColonyCount += 1
        founderCount += 1
        hasObservedFirstOrganism = true
        addColonyToken &+= 1
        recordEvent(
            generation: snapshot.generation,
            kind: .intervention,
            title: "External agent slot initialized",
            detail: "Founder \(founderCount) received three sampled four-component trait vectors at the camera position."
        )
        objectWillChange.send()
    }

    func zoom(by factor: Double, around anchor: SIMD2<Float>, aspect: Float) {
        let oldZoom = cameraZoom
        let newZoom = min(max(oldZoom * factor, 0.000_001), 1.0e24)
        guard newZoom != oldZoom else { return }
        let scale = aspectScale(for: aspect)
        let effectiveAnchor = followedAgentID == nil ? anchor : SIMD2<Float>(repeating: 0.5)
        let anchorOffset = (effectiveAnchor - SIMD2<Float>(repeating: 0.5)) * scale
        cameraCenter += anchorOffset * Float((1 / oldZoom) - (1 / newZoom))
        cameraZoom = newZoom
        expandWorldIfNeeded(aspect: aspect)
    }

    func zoom(to magnification: Double, aspect: Float) {
        let target = min(max(magnification, 1), 1.0e24)
        zoom(
            by: target / max(observationZoom, 0.000_001),
            around: SIMD2<Float>(repeating: 0.5),
            aspect: aspect
        )
    }

    func pan(by screenDelta: SIMD2<Float>, aspect: Float) {
        followedAgentID = nil
        let worldDelta = screenDelta * aspectScale(for: aspect) / Float(cameraZoom)
        cameraCenter -= worldDelta
        expandWorldIfNeeded(aspect: aspect)
    }

    func resetCamera() {
        followedAgentID = nil
        cameraCenter = Self.spinorOrigin
        cameraZoom = worldScale * 900
    }

    func followRandomOrganism() {
        guard let agent = observedAgents.randomElement() else { return }
        follow(agent)
    }

    func followAdjacentOrganism(direction: Int) {
        guard !observedAgents.isEmpty else { return }
        let ordered = observedAgents.sorted { $0.id < $1.id }
        guard let followedAgentID,
              let current = ordered.firstIndex(where: { $0.id == followedAgentID }) else {
            follow(ordered.first!)
            return
        }
        let offset = direction < 0 ? -1 : 1
        let next = (current + offset + ordered.count) % ordered.count
        follow(ordered[next])
    }

    func applyAgentObservations(_ agents: [AgentObservation]) {
        observedAgents = agents
        observableAgentCount = agents.count
        if !hasObservedFirstOrganism, let founder = agents.first {
            hasObservedFirstOrganism = true
            founderCount = 1
            recordEvent(
                generation: snapshot.generation,
                kind: .founding,
                title: "Founder-state thresholds satisfied",
                detail: String(
                    format: "Agent slot %d initialized at (%.4f, %.4f) after local biomass, energy, membrane, and catalyst thresholds were met.",
                    founder.id,
                    founder.position.x,
                    founder.position.y
                )
            )
#if DEBUG
            print("autogenic_founder id=\(founder.id) position=\(founder.position)")
#endif
        }
        guard let followedAgentID else { return }
        if let followed = agents.first(where: { $0.id == followedAgentID }) {
            cameraCenter = followed.position
        } else if let replacement = agents.first {
            follow(replacement)
        } else {
            self.followedAgentID = nil
        }
    }

    private func follow(_ agent: AgentObservation) {
        followedAgentID = agent.id
        cameraCenter = agent.position
    }

    var effectiveZoom: Double {
        cameraZoom / worldScale
    }

    var observationZoom: Double {
        effectiveZoom
    }

    func apply(_ newSnapshot: EvolutionSnapshot) {
        snapshot = newSnapshot
        guard newSnapshot.generation > lastRecordedGeneration else { return }

        let previous = history.last
        history.append(newSnapshot)
        if history.count > 120 {
            history.removeFirst(history.count - 120)
        }
        lastRecordedGeneration = newSnapshot.generation
        observeChange(from: previous, to: newSnapshot)
        if newSnapshot.metrics.occupiedFraction > 0.72 {
            expandBackingWorld()
        }
    }

    func report(error: Error) {
        errorMessage = error.localizedDescription
        isRunning = false
    }

    private func aspectScale(for aspect: Float) -> SIMD2<Float> {
        aspect >= 1
            ? SIMD2<Float>(1, 1 / max(aspect, 0.001))
            : SIMD2<Float>(max(aspect, 0.001), 1)
    }

    private func textureCoordinate(_ position: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2<Float>(
            position.x - floor(position.x),
            position.y - floor(position.y)
        )
    }

    private func expandWorldIfNeeded(aspect: Float) {
        let scale = aspectScale(for: aspect)
        var iterations = 0
        while iterations < 64 {
            let halfView = scale * (0.5 / Float(cameraZoom))
            let exposesEdge = cameraZoom < 1 ||
                cameraCenter.x - halfView.x < 0 || cameraCenter.x + halfView.x > 1 ||
                cameraCenter.y - halfView.y < 0 || cameraCenter.y + halfView.y > 1
            guard exposesEdge else { return }
            expandBackingWorld()
            iterations += 1
        }
    }

    private func expandBackingWorld() {
        cameraCenter = SIMD2<Float>(repeating: 0.25) + cameraCenter * 0.5
        cameraZoom *= 2
        worldScale *= 2
        expansionToken &+= 1
    }

    private func observeChange(from previous: EvolutionSnapshot?, to current: EvolutionSnapshot) {
        guard let previous else {
            recordEvent(
                generation: current.generation,
                kind: .founding,
                title: "First metric reduction completed",
                detail: "Occupied-cell fraction \(percent(current.metrics.occupiedFraction)); mean biomass density \(decimal(current.metrics.biomassDensity))."
            )
            return
        }

        let occupancyDelta = current.metrics.occupiedFraction - previous.metrics.occupiedFraction
        let currentBranches = lineageEstimate(current.metrics.lineageDiversity)
        let previousBranches = lineageEstimate(previous.metrics.lineageDiversity)
        var recordedMajorEvent = false

        if let milestone = crossedOccupancyMilestone(
            from: previous.metrics.occupiedFraction,
            to: current.metrics.occupiedFraction
        ) {
            recordEvent(
                generation: current.generation,
                kind: .expansion,
                title: "Occupied-cell fraction crossed \(percent(milestone))",
                detail: "Current occupied-cell fraction: \(percent(current.metrics.occupiedFraction))."
            )
            recordedMajorEvent = true
        } else if occupancyDelta < -0.025 {
            recordEvent(
                generation: current.generation,
                kind: .disturbance,
                title: "Occupied-cell fraction decreased",
                detail: "Reduction between metric samples: \(percentagePoints(-occupancyDelta))."
            )
            recordedMajorEvent = true
        }

        if currentBranches >= previousBranches + 2 {
            recordEvent(
                generation: current.generation,
                kind: .branching,
                title: "Occupied lineage-bin count increased",
                detail: "The 16-bin lineage estimator increased from \(previousBranches) to \(currentBranches)."
            )
            recordedMajorEvent = true
        }

        if current.metrics.resourceDensity < 0.015,
           previous.metrics.resourceDensity >= 0.015 {
            recordEvent(
                generation: current.generation,
                kind: .scarcity,
                title: "Mean resource density crossed below 0.015",
                detail: "Measured free-resource density: \(decimal(current.metrics.resourceDensity))."
            )
            recordedMajorEvent = true
        }

        if current.generation >= 9, (current.generation - 1).isMultiple(of: 8) {
            recordEvent(
                generation: current.generation,
                kind: .disturbance,
                title: "Post-perturbation recovery sampled",
                detail: "Recovered biomass divided by pre-perturbation biomass: \(percent(current.metrics.recovery))."
            )
            recordedMajorEvent = true
        }

        if current.metrics.occupiedFraction > 0.75,
           current.metrics.temporalActivity < 0.003,
           previous.metrics.temporalActivity >= 0.003 {
            recordEvent(
                generation: current.generation,
                kind: .equilibrium,
                title: "High-occupancy, low-activity condition detected",
                detail: "Occupied-cell fraction > 0.75 and temporal activity < 0.003."
            )
            recordedMajorEvent = true
        }

        if !recordedMajorEvent, current.generation.isMultiple(of: 5) {
            recordEvent(
                generation: current.generation,
                kind: .observation,
                title: observationTitle(for: current),
                detail: observationDetail(for: current)
            )
        }
    }

    private func recordEvent(
        generation: Int,
        kind: EvolutionEventKind,
        title: String,
        detail: String
    ) {
        if let matchingEvent = events.first(where: { $0.title == title }),
           generation - matchingEvent.generation < 12 {
            return
        }
        let event = EvolutionEvent(
            id: nextEventID,
            generation: generation,
            kind: kind,
            title: title,
            detail: detail
        )
        nextEventID &+= 1
        events.insert(event, at: 0)
        if events.count > 12 {
            events.removeLast(events.count - 12)
        }
    }

    private func observationTitle(for snapshot: EvolutionSnapshot) -> String {
        if snapshot.metrics.temporalActivity > 0.03 { return "Temporal activity exceeds 0.030" }
        if snapshot.fitness.diversification > 0.35 { return "Diversification score exceeds 0.35" }
        if snapshot.metrics.occupiedFraction > 0.72 { return "Occupied-cell fraction exceeds 0.72" }
        return "Periodic metric reduction completed"
    }

    private func crossedOccupancyMilestone(from previous: Double, to current: Double) -> Double? {
        [0.90, 0.75, 0.50, 0.30, 0.15, 0.05]
            .first { previous < $0 && current >= $0 }
    }

    private func observationDetail(for snapshot: EvolutionSnapshot) -> String {
        "Occupied \(percent(snapshot.metrics.occupiedFraction)); " +
            "lineage bins \(lineageEstimate(snapshot.metrics.lineageDiversity))/16; " +
            "mean temporal activity \(decimal(snapshot.metrics.temporalActivity))."
    }

    private func lineageEstimate(_ entropy: Double) -> Int {
        max(1, min(16, Int(pow(16, min(max(entropy, 0), 1)).rounded())))
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", min(max(value, 0), 1) * 100)
    }

    private func percentagePoints(_ value: Double) -> String {
        String(format: "%.1f points", min(max(value, 0), 1) * 100)
    }

    private func decimal(_ value: Double) -> String {
        String(format: "%.4f", max(value, 0))
    }
}
