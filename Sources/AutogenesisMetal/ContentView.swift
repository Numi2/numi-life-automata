import SwiftUI

struct ContentView: View {
    @StateObject private var store = EvolutionStore()

    var body: some View {
        ZStack(alignment: .topLeading) {
            MetalEvolutionView(store: store)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                commandBar
                Spacer()
                causalDock
            }

            HStack(spacing: 0) {
                Spacer()
                inspectorPanel
            }
            .padding(.top, 58)
            .padding(.bottom, 112)

            if let error = store.errorMessage {
                ContentUnavailableView(
                    "Metal unavailable",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(error)
                )
                .frame(maxWidth: 440)
                .padding(24)
                .background(Color.black.opacity(0.90), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .background(Color.black)
        .frame(minWidth: 1060, minHeight: 680)
        .preferredColorScheme(.dark)
    }

    private var commandBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.cyan.opacity(0.16))
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.cyan.opacity(0.52), lineWidth: 1)
                    Text("N")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(.cyan)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 0) {
                    Text("NUMI")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text("AUTOMATA")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 154, alignment: .leading)

            commandDivider

            controlGroup {
                numiIconButton(
                    store.isRunning ? "pause.fill" : "play.fill",
                    help: store.isRunning ? "Pause evolution" : "Resume evolution",
                    isSelected: store.isRunning
                ) {
                    store.isRunning.toggle()
                }

                numiIconButton("arrow.counterclockwise", help: "Restart from the spinor") {
                    store.restart()
                }

                numiIconButton("plus", help: "Introduce an external founder", tint: .mint) {
                    store.addColony()
                }
            }

            commandDivider

            Menu {
                Picker("View", selection: $store.displayMode) {
                    ForEach(FieldDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                    Text(store.displayMode.label)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 9)
                .frame(width: 126, height: 32)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .help("Choose which measured fields are visible")

            Picker("Speed", selection: $store.stepsPerFrame) {
                Text("1x").tag(1)
                Text("2x").tag(3)
                Text("4x").tag(6)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 92)
            .help("Evolution speed")

            controlGroup {
                numiIconButton("minus.magnifyingglass", help: "Zoom out") {
                    store.zoom(by: 1 / 1.8, around: .init(repeating: 0.5), aspect: 1)
                }
                numiIconButton("viewfinder", help: "Return to spinor origin") {
                    store.resetCamera()
                }
                numiIconButton("plus.magnifyingglass", help: "Zoom in") {
                    store.zoom(by: 1.8, around: .init(repeating: 0.5), aspect: 1)
                }
            }

            controlGroup {
                numiIconButton("chevron.left", help: "Previous organism") {
                    store.followAdjacentOrganism(direction: -1)
                }
                .disabled(store.observableAgentCount < 2)
                numiIconButton(
                    "scope",
                    help: "Follow a random organism",
                    isSelected: store.followedAgentID != nil,
                    tint: .cyan
                ) {
                    store.followRandomOrganism()
                }
                numiIconButton("chevron.right", help: "Next organism") {
                    store.followAdjacentOrganism(direction: 1)
                }
                .disabled(store.observableAgentCount < 2)
            }

            Spacer(minLength: 8)

            statusValue("SCALE", value: "0\(activeObservationStop + 1)")
            statusValue("GEN", value: "\(store.snapshot.generation)")
            statusValue("AGENTS", value: "\(max(store.snapshot.organismCount, store.observableAgentCount))")
            statusValue("MAG", value: zoomLabel)
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .background(Color.black.opacity(0.78))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
        }
    }

    private var inspectorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: observationStops[activeObservationStop].symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(scaleAccent)
                        .frame(width: 30, height: 30)
                        .background(scaleAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(scaleName.uppercased())
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        Text("STAGE 0\(activeObservationStop + 1) OF 06")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 5) {
                        Circle()
                            .fill(store.isRunning ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text(store.isRunning ? "LIVE" : "HOLD")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(worldHeadline)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(worldSummary)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: 9) {
                    Rectangle()
                        .fill(scaleAccent)
                        .frame(width: 2, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        sectionLabel("CROSS-SCALE COUPLING")
                        Text(scaleRelation)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)

                inspectorMetrics

                Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)

                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("MEASURED EVENTS")
                    if store.events.isEmpty {
                        Text("Awaiting B >= 0.055, E >= 0.006, M >= 0.003, and catalyst >= 0.030 at a local score maximum.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(store.events.prefix(5)) { event in
                            eventRow(event)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        .frame(width: 326)
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.74))
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1)
        }
    }

    @ViewBuilder
    private var inspectorMetrics: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("LIVE MEASURES")
            if store.observationZoom >= 160 {
                observerMetric("Spinor norm Σρ", value: quantumNormLabel, tint: .cyan, values: store.history.map(\.quantumNorm))
                observerMetric("Mean stored E", value: decimal(store.snapshot.metrics.energyDensity), tint: .yellow, values: store.history.map(\.metrics.energyDensity))
                observerMetric("∇B × membrane", value: decimal(store.snapshot.metrics.boundaryCoherence), tint: .mint, values: store.history.map(\.metrics.boundaryCoherence))
                observerMetric("Occupied agents", value: "\(max(store.snapshot.organismCount, store.observableAgentCount))/384", tint: .pink, values: store.history.map { Double($0.organismCount) })
            } else if store.observationZoom >= 64 {
                observerMetric("Mean stored E", value: decimal(store.snapshot.metrics.energyDensity), tint: .yellow, values: store.history.map(\.metrics.energyDensity))
                observerMetric("∇B × membrane", value: decimal(store.snapshot.metrics.boundaryCoherence), tint: .mint, values: store.history.map(\.metrics.boundaryCoherence))
                observerMetric("Mean |ΔB|", value: decimal(store.snapshot.metrics.temporalActivity), tint: .orange, values: store.history.map(\.metrics.temporalActivity))
                observerMetric("Spinor norm Σρ", value: quantumNormLabel, tint: .cyan, values: store.history.map(\.quantumNorm))
            } else if store.observationZoom >= 18 {
                let tissueCount = max(store.snapshot.organismCount, store.observableAgentCount)
                observerMetric("Population cells", value: "\(store.snapshot.cellCount) in \(tissueCount) organisms", tint: .cyan, values: store.history.map { Double($0.cellCount) })
                observerMetric("Mean cellular ATP", value: decimal(store.snapshot.meanCellATP), tint: .yellow, values: store.history.map(\.meanCellATP))
                observerMetric("Membrane integrity", value: decimal(store.snapshot.meanCellIntegrity), tint: .mint, values: store.history.map(\.meanCellIntegrity))
                observerMetric("Dividing / stressed", value: "\(store.snapshot.dividingCellCount) / \(decimal(store.snapshot.meanCellStress))", tint: .pink, values: store.history.map { Double($0.dividingCellCount) })
            } else if store.observationZoom >= 6 {
                observerMetric("Occupied agents", value: "\(max(store.snapshot.organismCount, store.observableAgentCount))/384", tint: .mint, values: store.history.map { Double($0.organismCount) })
                observerMetric("Lineage bins", value: "\(lineageEstimate)/32", tint: .pink, values: store.history.map { Double($0.organismLineageCount) })
                observerMetric("Mean |v|", value: speedLabel, tint: .cyan, values: store.history.map(\.meanOrganismSpeed))
                observerMetric("Predatory trait", value: "\(store.snapshot.hunterCount) agents", tint: .red, values: store.history.map { Double($0.hunterCount) })
            } else {
                observerMetric("Occupied agents", value: "\(max(store.snapshot.organismCount, store.observableAgentCount))/384", tint: .mint, values: store.history.map { Double($0.organismCount) })
                observerMetric("Mean free R", value: resourceLabel, tint: .cyan, values: store.history.map(\.metrics.resourceDensity))
                observerMetric("Mean |ΔB|", value: activityLabel, tint: .orange, values: store.history.map(\.metrics.temporalActivity))
                observerMetric("Predatory trait", value: "\(store.snapshot.hunterCount) agents", tint: .red, values: store.history.map { Double($0.hunterCount) })
            }
        }
    }

    private var causalDock: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                sectionLabel("OBSERVATION SCALE")
                Text(scaleName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(zoomLabel)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(scaleAccent)
            }
            .frame(width: 132, alignment: .leading)

            observationScaleRail
                .frame(maxWidth: 520)

            Spacer(minLength: 0)

            ViewThatFits(in: .horizontal) {
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel(legendTitle.uppercased())
                    HStack(spacing: 10) {
                        ForEach(legendItems.prefix(4), id: \.label) { item in
                            HStack(spacing: 4) {
                                Circle().fill(item.color).frame(width: 6, height: 6)
                                Text(item.label)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                sectionLabel(legendTitle.uppercased())
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 344)
        .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 112)
        .background(Color.black.opacity(0.78))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
        }
    }

    private var observationScaleRail: some View {
        HStack(spacing: 0) {
            ForEach(Array(observationStops.enumerated()), id: \.element.id) { index, stop in
                Button {
                    if (index == 3 || index == 4), store.followedAgentID == nil {
                        store.followRandomOrganism()
                    }
                    store.zoom(to: stop.magnification, aspect: 1)
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: stop.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(height: 16)
                        Text(stop.label)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(index == activeObservationStop ? scaleAccent : Color.secondary)
                    .frame(width: 64, height: 54)
                    .background(
                        index == activeObservationStop ? scaleAccent.opacity(0.11) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(index == activeObservationStop ? scaleAccent : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .help("Jump to \(stop.label.lowercased()) scale")

                if index < observationStops.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.22))
                        .frame(width: 14)
                }
            }
        }
    }

    private func observerMetric(
        _ label: String,
        value: String,
        tint: Color,
        values: [Double]
    ) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
            }
            .frame(width: 116, alignment: .leading)

            MetricSparkline(values: values, color: tint)
                .frame(height: 28)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func eventRow(_ event: EvolutionEvent) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: eventSymbol(event.kind))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(eventColor(event.kind))
                .frame(width: 22, height: 22)
                .background(eventColor(event.kind).opacity(0.13), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(event.title)
                        .font(.system(size: 11, weight: .semibold))
                    Spacer(minLength: 4)
                    Text("GEN \(event.generation)")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Text(event.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func numiIconButton(
        _ symbol: String,
        help: String,
        isSelected: Bool = false,
        tint: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? tint : Color.primary)
                .frame(width: 30, height: 30)
                .background(
                    isSelected ? tint.opacity(0.14) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func controlGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 1, content: content)
            .padding(1)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
    }

    private var commandDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: 28)
    }

    private func statusValue(_ label: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .contentTransition(.numericText())
        }
        .frame(minWidth: 52, alignment: .trailing)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
    }

    private var worldHeadline: String {
        let zoom = store.observationZoom
        if zoom >= 512 { return "Two-component coined quantum walk" }
        if zoom >= 160 { return "Probability density, phase, and probability current" }
        if zoom >= 64 { return "Molecular reaction and spinor coupling" }
        if zoom >= 18 { return "Cell mechanics, metabolism, signaling, and division" }
        if zoom >= 6 { return "Multicellular organisms with inherited traits" }
        return "Spatial eco-evolutionary dynamics"
    }

    private var worldSummary: String {
        let zoom = store.observationZoom
        let life = max(store.snapshot.organismCount, store.observableAgentCount)
        if zoom >= 512 {
            return "ψ = (ψ₀, ψ₁) is stored as four real components on a 1024² periodic lattice. Each update applies a local coin rotation and alternates conditional shifts along x and y. Measured Σρ = \(quantumNormValue)."
        }
        if zoom >= 160 {
            return "ρ = |ψ₀|² + |ψ₁|². Component overlap contributes to the catalyst source term; local resource, biomass, membrane, toxin, and inherited trait fields modify the coin angle and phase potential."
        }
        if zoom >= 64 {
            return "The 193² lattice stores resource A, biomass B, energy E, membrane M, resource B, detritus, toxin, and catalyst. Founder nucleation requires B ≥ 0.055, E ≥ 0.006, M ≥ 0.003, and catalyst ≥ 0.030 at a local score maximum."
        }
        if zoom >= 18 {
            return "\(store.snapshot.cellCount) persistent cells are active across \(life) organisms. Each cell stores local position and velocity, ATP, biomass, cell-cycle phase, membrane integrity, adhesion, contractility, two uptake phenotypes, two morphogens, stress, and apoptosis activation. Contact mechanics, metabolite exchange, contact inhibition, division, and death are evaluated on the GPU."
        }
        if zoom >= 6 {
            return life == 0
                ? "No agent slot is occupied. Nucleation remains gated by the measured chemistry thresholds, not by elapsed time."
                : "Each organism owns up to 24 persistent cells. Organism energy and survival receive cellular viability and stress feedback; steering combines resource gradients, hazard avoidance, separation, prey pursuit, and threat avoidance."
        }
        let occupied = percent(store.snapshot.metrics.occupiedFraction)
        return "\(life)/384 agent slots are occupied; \(lineageEstimate)/32 agent-lineage bins are represented; occupied-cell fraction is \(occupied). Mean free-resource density is \(resourceLabel), and \(store.snapshot.hunterCount) agents exceed the predation-trait threshold."
    }

    private var scaleRelation: String {
        switch activeObservationStop {
        case 0: "ρ and normalized component overlap define quantumOrder, which enters the catalyst-production term in reactWorld."
        case 1: "Matter changes coin angle θ and local phase V; spinor density and overlap change catalyst and stored-energy production."
        case 2: "Reaction fields determine cellular resource uptake and stress; spinor overlap modifies catalyst and energy production in the same persistent environment."
        case 3: "Cell ATP and membrane integrity alter organism maintenance and damage. Contact inhibition regulates cell-cycle progression; division and apoptosis alter morphology."
        case 4: "Reproduction requires E ≥ 1.06 and age ≥ 720 steps. Offspring inherit mutated trait vectors and initialize a seven-cell founder tissue."
        default: "Resources, detritus, toxin, rock permeability, predation, and crowding generate spatially varying differential fitness without a global agent fitness function."
        }
    }

    private var scaleAccent: Color {
        switch activeObservationStop {
        case 0: .cyan
        case 1: .pink
        case 2: .purple
        case 3: .mint
        case 4: .orange
        default: .green
        }
    }

    private var resourceLabel: String {
        decimal(store.snapshot.metrics.resourceDensity)
    }

    private var quantumNormLabel: String {
        guard store.snapshot.quantumNorm > 0 else { return "pending" }
        return quantumNormValue
    }

    private var quantumNormValue: String {
        String(format: "%.4f", max(store.snapshot.quantumNorm, 0))
    }

    private var activityLabel: String {
        decimal(store.snapshot.metrics.temporalActivity)
    }

    private var speedLabel: String {
        let speed = store.snapshot.meanOrganismSpeed
        return String(format: "%.2e world/step", max(speed, 0))
    }

    private var lineageEstimate: Int {
        if store.snapshot.organismLineageCount > 0 {
            return store.snapshot.organismLineageCount
        }
        let entropy = min(max(store.snapshot.metrics.lineageDiversity, 0), 1)
        return max(1, min(16, Int(pow(16, entropy).rounded())))
    }

    private var zoomLabel: String {
        let zoom = store.observationZoom
        if zoom >= 1_000_000_000 {
            return String(format: "%.0fGx", zoom / 1_000_000_000)
        }
        if zoom >= 1_000_000 {
            return String(format: "%.0fMx", zoom / 1_000_000)
        }
        if zoom >= 1_000 {
            return String(format: "%.1fkx", zoom / 1_000)
        }
        if zoom >= 10 {
            return String(format: "%.0fx", zoom)
        }
        if zoom >= 0.01 {
            return String(format: "%.2fx", zoom)
        }
        return String(format: "%.0e", zoom)
    }

    private var fieldSpanLabel: String {
        let span = store.worldScale
        if span >= 1_000_000_000 { return String(format: "%.0fGx", span / 1_000_000_000) }
        if span >= 1_000_000 { return String(format: "%.0fMx", span / 1_000_000) }
        if span >= 1_000 { return String(format: "%.0fkx", span / 1_000) }
        return String(format: "%.0fx", span)
    }

    private var scaleName: String {
        let zoom = store.observationZoom
        if zoom < 6 { return "Ecological field" }
        if zoom < 18 { return "Organism morphology" }
        if zoom < 64 { return "Cellular tissue" }
        if zoom < 160 { return "Molecular reaction field" }
        if zoom < 512 { return "Wave observables" }
        return "Spinor field"
    }

    private var observationStops: [ObservationStop] {
        [
            ObservationStop(label: "Spinor", symbol: "atom", magnification: 900),
            ObservationStop(label: "Wave", symbol: "waveform.path", magnification: 240),
            ObservationStop(label: "Molecule", symbol: "scope", magnification: 96),
            ObservationStop(label: "Cell", symbol: "circle.hexagonpath.fill", magnification: 36),
            ObservationStop(label: "Organism", symbol: "microbe.fill", magnification: 10),
            ObservationStop(label: "Ecology", symbol: "circle.hexagongrid.fill", magnification: 1)
        ]
    }

    private var activeObservationStop: Int {
        let zoom = store.observationZoom
        if zoom >= 512 { return 0 }
        if zoom >= 160 { return 1 }
        if zoom >= 64 { return 2 }
        if zoom >= 18 { return 3 }
        if zoom >= 6 { return 4 }
        return 5
    }

    private var statusColor: Color {
        guard store.snapshot.generation > 0 else { return scaleAccent }
        if store.snapshot.metrics.temporalActivity > 0.03 { return .orange }
        if store.snapshot.metrics.occupiedFraction > 0.75,
           store.snapshot.metrics.temporalActivity < 0.003 { return .cyan }
        if store.snapshot.fitness.diversification > 0.35 { return .pink }
        return .green
    }

    private var legendItems: [(label: String, color: Color)] {
        if store.observationZoom >= 512 {
            return [("Spin +", .cyan), ("Spin -", .orange), ("Current", .white), ("Nodes", .purple)]
        }
        if store.observationZoom >= 160 {
            return [("Probability", .cyan), ("Phase", .pink), ("Current", .white), ("Potential", .mint)]
        }
        if store.observationZoom >= 64 {
            return [("Membrane", .mint), ("Energy", .yellow), ("Genome", .pink), ("Potential", .cyan)]
        }
        if store.observationZoom >= 18 {
            return [("Membrane", .mint), ("ATP", .yellow), ("Nucleus", .pink), ("Junction", .cyan), ("Stress", .red), ("Apoptosis", .purple)]
        }
        if store.displayMode == .ecology, store.observationZoom < 6 {
            return [("Life", .cyan), ("Nutrient", .green), ("Mineral", .yellow), ("Rock", .gray), ("Toxin", .red), ("Hunt", .orange)]
        }
        if store.displayMode == .ecology {
            return [("Lineage", .cyan), ("Energy", .yellow), ("Sensor", .white), ("Defense", .mint), ("Jaw", .red), ("Genome", .pink)]
        }
        switch store.displayMode {
        case .ecology:
            return []
        case .energy:
            return [("Resource A", .cyan), ("Resource B", .purple), ("Stored energy", .yellow), ("Detritus", .orange)]
        case .genome:
            return [("Metabolism", .red), ("Adhesion", .green), ("Division", .blue), ("Lineage", .pink)]
        case .niches:
            return [("Resource A", .red), ("Resource B", .green), ("Scavenging", .blue), ("Predation", .pink)]
        }
    }

    private var legendTitle: String {
        store.observationZoom >= 512 ? "Spinor components" :
            store.observationZoom >= 160 ? "Quantum observables" :
            store.observationZoom >= 64 ? "Molecular fields" :
            store.observationZoom >= 18 ? "Cell state" : store.displayMode.label
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", min(max(value, 0), 1) * 100)
    }

    private func decimal(_ value: Double) -> String {
        String(format: "%.4f", max(value, 0))
    }

    private func eventSymbol(_ kind: EvolutionEventKind) -> String {
        switch kind {
        case .founding: "sparkles"
        case .expansion: "arrow.up.right"
        case .branching: "arrow.triangle.branch"
        case .scarcity: "drop.triangle"
        case .disturbance: "waveform.path.ecg"
        case .equilibrium: "equal.circle"
        case .intervention: "plus"
        case .observation: "eye"
        }
    }

    private func eventColor(_ kind: EvolutionEventKind) -> Color {
        switch kind {
        case .founding, .expansion: .green
        case .branching: .pink
        case .scarcity: .orange
        case .disturbance: .red
        case .equilibrium: .cyan
        case .intervention: .mint
        case .observation: .secondary
        }
    }
}

private struct ObservationStop: Identifiable {
    let label: String
    let symbol: String
    let magnification: Double

    var id: String { label }
}

private struct MetricSparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else {
                let y = size.height * 0.5
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(color.opacity(0.35)), lineWidth: 1)
                return
            }

            let minimum = values.min() ?? 0
            let maximum = values.max() ?? 1
            let span = max(maximum - minimum, 0.000_001)
            var path = Path()
            for (index, value) in values.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
                let normalized = (value - minimum) / span
                let y = size.height * (1 - CGFloat(normalized) * 0.78 - 0.11)
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .background {
            Rectangle()
                .fill(.white.opacity(0.025))
        }
        .clipShape(Rectangle())
    }
}
