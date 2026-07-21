import AutogenesisCore
import SwiftUI

private struct ProcessPathNode: Identifiable {
    let label: String
    let value: String
    let symbol: String
    let tint: Color

    var id: String { label }
}

private struct ProcessPathwayView: View {
    let nodes: [ProcessPathNode]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MEASURED PROCESS CHAIN")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    nodeView(node)
                    if index < nodes.count - 1 {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(nodes[index + 1].tint)
                            .frame(width: 20)
                    }
                }
            }
        }
    }

    private func nodeView(_ node: ProcessPathNode) -> some View {
        VStack(spacing: 3) {
            Image(systemName: node.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(node.tint)
                .frame(width: 24, height: 24)
                .background(node.tint.opacity(0.12), in: Circle())
            Text(node.label)
                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(node.value)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 44)
    }
}

struct ContentView: View {
    @StateObject private var store = EvolutionStore()
    @State private var showsInspector = ProcessInfo.processInfo.environment[
        "NUMI_SHOW_INSPECTOR"
    ] == "1"
    @State private var showsScientificDefinition = false

    private var inspectorWidth: CGFloat { 352 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            MetalEvolutionView(store: store)
                .offset(x: showsInspector ? -(inspectorWidth + 24) * 0.5 : 0)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                commandBar
                Spacer()
                compactContextHUD
            }
            .padding(12)

            HStack(spacing: 0) {
                Spacer()
                if showsInspector {
                    inspectorPanel
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.top, 72)
            .padding(.trailing, 12)
            .padding(.bottom, 76)

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
        .frame(minWidth: 900, minHeight: 620)
        .preferredColorScheme(.dark)
        .animation(.snappy(duration: 0.22), value: showsInspector)
        .onChange(of: activeObservationStop) { _, index in
            store.displayMode = observationStops[index].displayMode
        }
    }

    private var commandBar: some View {
        HStack(spacing: 5) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.cyan.opacity(0.16))
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.cyan.opacity(0.52), lineWidth: 1)
                    Text("N")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.cyan)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 0) {
                    Text("NUMI")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    Text("AUTOMATA")
                        .font(.system(size: 7, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 112, alignment: .leading)

            commandDivider

            numiIconButton(
                store.isRunning ? "pause.fill" : "play.fill",
                help: store.isRunning ? "Pause evolution" : "Resume evolution",
                isSelected: store.isRunning,
                tint: .cyan
            ) {
                store.isRunning.toggle()
            }

            numiIconButton("plus", help: "Introduce an external founder", tint: .mint) {
                store.addColony()
            }

            numiIconButton("arrow.counterclockwise", help: "Restart from the spinor") {
                store.restart()
            }

            numiIconButton(
                "waveform.path.ecg",
                help: store.mechanosensingBlocked
                    ? "Restore mechanical input to voltage and Ca* gating"
                    : "Ablate mechanical input to voltage and Ca* gating",
                isSelected: store.mechanosensingBlocked,
                tint: .red
            ) {
                store.toggleMechanosensingIntervention()
            }

            commandDivider

            observationScaleRail

            commandDivider

            Picker("Speed", selection: $store.stepsPerFrame) {
                Text("1x").tag(1)
                Text("3x").tag(3)
                Text("6x").tag(6)
                Text("24x").tag(24)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 126)
            .help("Exact biological solver steps per rendered frame")

            commandDivider

            numiIconButton("minus.magnifyingglass", help: "Zoom out") {
                store.zoom(by: 1 / 1.8, around: .init(repeating: 0.5), aspect: 1)
            }
            numiIconButton("viewfinder", help: "Reset camera") {
                store.resetCamera()
            }
            numiIconButton("plus.magnifyingglass", help: "Zoom in") {
                store.zoom(by: 1.8, around: .init(repeating: 0.5), aspect: 1)
            }

            commandDivider

            numiIconButton("chevron.left", help: "Previous biological unit") {
                store.followAdjacentOrganism(direction: -1)
            }
            .disabled(store.observableAgentCount < 2)
            numiIconButton(
                "scope",
                help: "Follow a random cell or tissue",
                isSelected: store.followedAgentID != nil,
                tint: .cyan
            ) {
                store.followRandomOrganism()
            }
            numiIconButton("chevron.right", help: "Next biological unit") {
                store.followAdjacentOrganism(direction: 1)
            }
            .disabled(store.observableAgentCount < 2)

            Spacer(minLength: 2)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 3) {
                    statusValue("STEP", value: "\(store.runtimeTelemetry.scientificallyCommittedStep)")
                    statusValue("SPS", value: String(format: "%.0f", store.runtimeTelemetry.stepsPerSecond))
                    statusValue("Q", value: "\(store.runtimeTelemetry.unfinishedCommandBuffers)/\(store.runtimeTelemetry.maximumCommandBuffers)")
                    statusValue("CHK", value: "\(store.runtimeTelemetry.checkpointStep)")
                    statusValue("REC", value: "\(store.runtimeTelemetry.recoveryCount)")
                    statusValue(
                        "CDEP",
                        value: "G\(store.maximumLivingLineageGeneration)"
                    )
                    statusValue("COMP", value: "\(store.observableAgentCount)")
                    statusValue("IND", value: "\(store.resolvedIndividualCount)")
                    statusValue("MAG", value: zoomLabel)
                }
                statusValue("COMP", value: "\(store.observableAgentCount)")
            }

            commandDivider

            numiIconButton(
                "sidebar.right",
                help: showsInspector ? "Close scientific inspector" : "Open scientific inspector",
                isSelected: showsInspector,
                tint: scaleAccent
            ) {
                showsInspector.toggle()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 48)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .background(Color.black.opacity(0.70), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.34), radius: 16, y: 6)
    }

    private var inspectorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: observationStops[activeObservationStop].symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(scaleAccent)
                        .frame(width: 30, height: 30)
                        .background(scaleAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(scaleName.uppercased())
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        Text("SCALE 0\(activeObservationStop + 1) OF 06")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(store.mechanosensingBlocked ? Color.red : Color.cyan)
                                .frame(width: 6, height: 6)
                            Text(store.mechanosensingBlocked ? "MECH BLOCKED" : "MECH ACTIVE")
                        }
                        HStack(spacing: 5) {
                            Circle()
                                .fill(store.isRunning ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)
                            Text(store.isRunning ? "LIVE" : "HOLD")
                        }
                    }
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))

                    numiIconButton("xmark", help: "Close scientific inspector") {
                        showsInspector = false
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(worldHeadline)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(inspectorSummary)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)

                if activeObservationStop == 2 {
                    molecularReactionPathway
                } else {
                    scaleProcessPathway
                }

                Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)

                if store.observationZoom >= 6,
                   store.observationZoom < 18,
                   store.observableAgentCount > 0 || recordedFissionCount > 0 {
                    evolutionAfterFormationPanel
                }

                if store.observationZoom < 64 {
                    individualityPanel
                }

                if store.observationZoom >= 6, store.observationZoom < 18 {
                    autonomyObservablesPanel
                }

                DisclosureGroup(isExpanded: $showsScientificDefinition) {
                    Text(scientificDefinitionText)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                } label: {
                    sectionLabel("METHOD AND ASSUMPTIONS")
                }
                .tint(scaleAccent)

                Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)

                inspectorMetrics

                Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)

                runtimeReliabilityPanel

                Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)

                if store.observationZoom < 18, !store.lineageBranches.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("RECORDED LINEAGE TREE")
                        ForEach(store.lineageBranches.prefix(6)) { branch in
                            lineageRow(branch)
                        }
                    }
                    Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
                }

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
        .frame(width: inspectorWidth)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .background(Color.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.38), radius: 18, x: -5, y: 7)
    }

    @ViewBuilder
    private var inspectorMetrics: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("LIVE MEASURES")
            if store.observationZoom >= 512 {
                observerMetric("Spinor norm Σρ", value: quantumNormLabel, tint: .cyan, values: store.history.map(\.quantumNorm))
                observerMetric("Mean spinor order Q", value: decimal(store.snapshot.meanQuantumOrder), tint: .pink, values: store.history.map(\.meanQuantumOrder))
                observerMetric("Q, mechanics → ΔC", value: scientific(store.snapshot.meanCatalystProduction), tint: .purple, values: store.history.map(\.meanCatalystProduction))
                observerMetric("C, Q → ΔE", value: scientific(store.snapshot.meanPrebioticEnergyProduction), tint: .yellow, values: store.history.map(\.meanPrebioticEnergyProduction))
            } else if store.observationZoom >= 160 {
                observerMetric("Spinor norm Σρ", value: quantumNormLabel, tint: .cyan, values: store.history.map(\.quantumNorm))
                observerMetric("Mean spinor order Q", value: decimal(store.snapshot.meanQuantumOrder), tint: .pink, values: store.history.map(\.meanQuantumOrder))
                observerMetric("Chemical affinity A·B", value: decimal(store.snapshot.meanChemicalAffinity), tint: .blue, values: store.history.map(\.meanChemicalAffinity))
                observerMetric("Catalyst synthesis ΔC", value: scientific(store.snapshot.meanCatalystProduction), tint: .purple, values: store.history.map(\.meanCatalystProduction))
                observerMetric("Energy synthesis ΔE", value: scientific(store.snapshot.meanPrebioticEnergyProduction), tint: .yellow, values: store.history.map(\.meanPrebioticEnergyProduction))
            } else if store.observationZoom >= 64 {
                observerMetric("Substrate A / B", value: molecularResourcePairLabel, tint: .cyan, values: store.history.map { $0.metrics.resourceDensity * 2 })
                observerMetric("Catalyst C / stored E", value: "\(decimal(store.snapshot.meanMolecularCatalyst)) / \(decimal(store.snapshot.metrics.energyDensity))", tint: .pink, values: store.history.map(\.meanMolecularCatalyst))
                observerMetric("Membrane M / toxin", value: "\(decimal(store.snapshot.meanMolecularMembrane)) / \(decimal(store.snapshot.meanMolecularToxin))", tint: .mint, values: store.history.map(\.meanMolecularMembrane))
                observerMetric("Q order / A·B affinity", value: "\(decimal(store.snapshot.meanQuantumOrder)) / \(decimal(store.snapshot.meanChemicalAffinity))", tint: .purple, values: store.history.map(\.meanQuantumOrder))
                observerMetric("ΔC / ΔE per step", value: "\(scientific(store.snapshot.meanCatalystProduction)) / \(scientific(store.snapshot.meanPrebioticEnergyProduction))", tint: .yellow, values: store.history.map(\.meanPrebioticEnergyProduction))
                observerMetric("ΔM / recycle per step", value: "\(scientific(store.snapshot.meanMembraneAssembly)) / \(scientific(store.snapshot.meanDetritalMineralization))", tint: .orange, values: store.history.map(\.meanMembraneAssembly))
                observerMetric("Detritus pool", value: decimal(store.snapshot.metrics.detritusDensity), tint: .orange, values: store.history.map(\.metrics.detritusDensity))
            } else if store.observationZoom >= 18, store.displayMode == .causality {
                let tissueCount = max(store.snapshot.organismCount, store.observableAgentCount)
                observerMetric("Cells / components", value: "\(store.snapshot.cellCount) / \(tissueCount)", tint: .cyan, values: store.history.map { Double($0.cellCount) })
                observerMetric("Components / inferred individuals", value: individualityCountLabel, tint: .mint, values: store.history.map { Double($0.organismCount) })
                observerMetric("Mean / max component", value: "\(decimal(store.snapshot.meanCellsPerOrganism)) / \(store.snapshot.largestTissueCellCount)", tint: .green, values: store.history.map(\.meanCellsPerOrganism))
                observerMetric("Global cell pool", value: percent(store.snapshot.cellPoolUtilization), tint: .blue, values: store.history.map(\.cellPoolUtilization))
                observerMetric("Heritable programs", value: "\(store.snapshot.heritableProgramCount) / 4096", tint: .purple, values: store.history.map(\.heritableProgramPoolUtilization))
                observerMetric("Mixed-program cells", value: percent(store.snapshot.meanMixedProgramCellFraction), tint: .orange, values: store.history.map(\.meanMixedProgramCellFraction))
                observerMetric("Program richness", value: "\(store.snapshot.maximumProgramRichness)", tint: .pink, values: store.history.map { Double($0.maximumProgramRichness) })
                observerMetric("Recognition match", value: store.snapshot.meanProgramRecognitionCompatibility >= 0 ? decimal(store.snapshot.meanProgramRecognitionCompatibility) : "n/a", tint: .cyan, values: store.history.map { max($0.meanProgramRecognitionCompatibility, 0) })
                observerMetric("ATP exchange x1M", value: scaledRate(store.snapshot.meanProgramATPExchange, by: 1_000_000), tint: .mint, values: store.history.map(\.meanProgramATPExchange))
                observerMetric("Rejection load", value: decimal(store.snapshot.meanProgramRejection), tint: .red, values: store.history.map(\.meanProgramRejection))
                observerMetric("Program net x1M", value: scaledRate(store.snapshot.meanProgramNetContribution, by: 1_000_000), tint: .yellow, values: store.history.map(\.meanProgramNetContribution))
                observerMetric("Direct ΔVₘ ×1k", value: causalRate(store.snapshot.meanMechanotransductionEffect), tint: .cyan, values: store.history.map(\.meanMechanotransductionEffect))
                observerMetric("Ca* / ERK* state", value: signalStateLabel, tint: .pink, values: store.history.map(\.meanCalciumActivity))
                observerMetric("Mechanics → Ca* ×1k", value: causalRate(store.snapshot.meanMechanicsCalciumEffect), tint: .cyan, values: store.history.map(\.meanMechanicsCalciumEffect))
                observerMetric("Ca* → ERK* ×1k", value: causalRate(store.snapshot.meanCalciumERKEffect), tint: .pink, values: store.history.map(\.meanCalciumERKEffect))
                observerMetric("ERK* → traction ×10k", value: scaledRate(store.snapshot.meanERKTractionEffect, by: 10_000), tint: .mint, values: store.history.map(\.meanERKTractionEffect))
                observerMetric("Env f / match", value: "\(scaledRate(store.snapshot.meanEnvironmentalFrequency, by: 1_000)) / \(percent(store.snapshot.meanFrequencyMatch))", tint: .cyan, values: store.history.map(\.meanFrequencyMatch))
                observerMetric("Barrier load", value: percent(store.snapshot.meanBarrierLoad), tint: .orange, values: store.history.map(\.meanBarrierLoad))
                observerMetric("Armor / predatory", value: "\(decimal(store.snapshot.meanArmorConstruction)) / \(decimal(store.snapshot.meanPredatoryConstruction))", tint: .red, values: store.history.map(\.meanArmorConstruction))
                observerMetric("Signal ATP cost ×10k", value: scaledRate(store.snapshot.cellularSignalingCost, by: 10_000), tint: .orange, values: store.history.map(\.cellularSignalingCost))
                observerMetric("Substrate → ATP", value: "\(decimal(store.snapshot.auditedSubstrateEnergy)) / \(decimal(store.snapshot.auditedATPHarvest))", tint: .yellow, values: store.history.map(\.auditedATPHarvest))
                observerMetric("Conservation residual", value: signedDecimal(store.snapshot.energyConservationResidual), tint: .white, values: store.history.map { abs($0.energyConservationResidual) })
                observerMetric("Cell force |F| ×10k", value: scaledRate(store.snapshot.meanCellGeneratedForce, by: 10_000), tint: .green, values: store.history.map(\.meanCellGeneratedForce))
                observerMetric("Contact load ×1k", value: scaledRate(store.snapshot.cellularContactLoad, by: 1_000), tint: .red, values: store.history.map(\.cellularContactLoad))
                observerMetric("Trophic gain / loss ×10k", value: "\(scaledRate(store.snapshot.cellularTrophicGain, by: 10_000)) / \(scaledRate(store.snapshot.cellularTrophicLoss, by: 10_000))", tint: .yellow, values: store.history.map(\.cellularTrophicGain))
                observerMetric("Contact Δcycle ×1k", value: causalRate(store.snapshot.meanContactSuppression), tint: .mint, values: store.history.map(\.meanContactSuppression))
                observerMetric("Obs Δstrain → ΔVₘ", value: strainVoltageAssociationLabel, tint: .pink, values: store.history.map(\.meanTissueStrain))
                observerMetric("Obs ΔCa* → ΔERK*", value: calciumERKAssociationLabel, tint: .purple, values: store.history.map(\.meanCalciumActivity))
                observerMetric("Obs Δmatch → Δtraction", value: frequencyTractionAssociationLabel, tint: .cyan, values: store.history.map(\.meanFrequencyMatch))
            } else if store.observationZoom >= 18 {
                let tissueCount = max(store.snapshot.organismCount, store.observableAgentCount)
                observerMetric("Cells / components", value: "\(store.snapshot.cellCount) / \(tissueCount)", tint: .cyan, values: store.history.map { Double($0.cellCount) })
                observerMetric("Components / inferred individuals", value: individualityCountLabel, tint: .mint, values: store.history.map { Double($0.organismCount) })
                observerMetric("GRN nodes / edges", value: developmentalTopologyLabel, tint: .mint, values: store.history.map(\.meanDevelopmentalEdgeCount))
                observerMetric("Morphogen A / B", value: "\(decimal(store.snapshot.meanMorphogenActivator)) / \(decimal(store.snapshot.meanMorphogenInhibitor))", tint: .cyan, values: store.history.map(\.meanMorphogenActivator))
                observerMetric("Differentiation / fate", value: "\(decimal(store.snapshot.meanMorphogenDifferentiation)) / \(decimal(store.snapshot.meanDevelopmentalFateMemory))", tint: .pink, values: store.history.map(\.meanMorphogenDifferentiation))
                observerMetric("Junction transport / polarity", value: "\(decimal(store.snapshot.meanJunctionMorphogenTransport)) / \(percent(store.snapshot.meanDevelopmentalPolarityCoherence))", tint: .mint, values: store.history.map(\.meanJunctionMorphogenTransport))
                observerMetric("Morphogen source / work", value: "\(scientific(store.snapshot.meanMorphogenSynthesisRate)) / \(scientific(store.snapshot.meanMorphogenTransportWork))", tint: .orange, values: store.history.map(\.meanMorphogenSynthesisRate))
                observerMetric("Membrane A / P", value: membraneGeometryLabel, tint: .blue, values: store.history.map(\.meanMembraneShapeIndex))
                observerMetric("Tissue e / exposed P", value: "\(decimal(store.snapshot.meanTissueElongation)) / \(decimal(store.snapshot.meanExposedMembraneLength))", tint: .cyan, values: store.history.map(\.meanTissueElongation))
                observerMetric("Cell |F| / tissue |τ| ×10k", value: "\(scaledRate(store.snapshot.meanCellGeneratedForce, by: 10_000)) / \(scaledRate(store.snapshot.meanTissueTorque, by: 10_000))", tint: .green, values: store.history.map(\.meanCellGeneratedForce))
                observerMetric("Resonance f₀ / ζ", value: resonanceTuningLabel, tint: .pink, values: store.history.map(\.meanResonanceFrequency))
                observerMetric("Response / junction F", value: resonanceResponseLabel, tint: .orange, values: store.history.map(\.meanResonanceAmplitude))
                observerMetric("Env f / match", value: "\(scaledRate(store.snapshot.meanEnvironmentalFrequency, by: 1_000)) / \(percent(store.snapshot.meanFrequencyMatch))", tint: .cyan, values: store.history.map(\.meanFrequencyMatch))
                observerMetric("Barrier load", value: percent(store.snapshot.meanBarrierLoad), tint: .orange, values: store.history.map(\.meanBarrierLoad))
                observerMetric("Armor / predatory", value: "\(decimal(store.snapshot.meanArmorConstruction)) / \(decimal(store.snapshot.meanPredatoryConstruction))", tint: .red, values: store.history.map(\.meanArmorConstruction))
                observerMetric("Ca* / ERK* / refractory", value: signalStateLabel, tint: .pink, values: store.history.map(\.meanCalciumActivity))
                observerMetric("Inherited gₘ꜀ / g꜀ₑ", value: "\(decimal(store.snapshot.meanMechanicsCalciumGain)) / \(decimal(store.snapshot.meanCalciumERKGain))", tint: .cyan, values: store.history.map(\.meanMechanicsCalciumGain))
                observerMetric("Inherited gⱼ / r", value: "\(decimal(store.snapshot.meanJunctionTransmissionGain)) / \(decimal(store.snapshot.meanRefractoryRecoveryGain))", tint: .mint, values: store.history.map(\.meanJunctionTransmissionGain))
                observerMetric("Detach θ / investment", value: "\(decimal(store.snapshot.meanDetachmentThreshold)) / \(decimal(store.snapshot.meanPropaguleInvestment))", tint: .yellow, values: store.history.map(\.meanDetachmentScore))
                observerMetric("ATP / Vₘ", value: "\(decimal(store.snapshot.meanCellATP)) / \(signedDecimal(store.snapshot.meanMembraneVoltage))", tint: .yellow, values: store.history.map(\.meanCellATP))
                observerMetric("Substrate → ATP", value: "\(decimal(store.snapshot.auditedSubstrateEnergy)) / \(decimal(store.snapshot.auditedATPHarvest))", tint: .yellow, values: store.history.map(\.auditedATPHarvest))
                observerMetric("Work / resonant work", value: "\(decimal(store.snapshot.auditedActiveWork)) / \(decimal(store.snapshot.auditedFrequencyWork))", tint: .green, values: store.history.map(\.auditedActiveWork))
                observerMetric("Heat / detritus E", value: "\(decimal(store.snapshot.auditedHeatExport)) / \(decimal(store.snapshot.auditedDetritusReturn))", tint: .orange, values: store.history.map(\.auditedHeatExport))
                observerMetric("Conservation residual", value: signedDecimal(store.snapshot.energyConservationResidual), tint: .white, values: store.history.map { abs($0.energyConservationResidual) })
            } else if store.observationZoom >= 6 {
                if store.displayMode == .causality {
                    observerMetric("Direct ΔVₘ ×1k", value: causalRate(store.snapshot.meanMechanotransductionEffect), tint: .cyan, values: store.history.map(\.meanMechanotransductionEffect))
                    observerMetric("Mechanics → Ca* ×1k", value: causalRate(store.snapshot.meanMechanicsCalciumEffect), tint: .cyan, values: store.history.map(\.meanMechanicsCalciumEffect))
                    observerMetric("Ca* → ERK* ×1k", value: causalRate(store.snapshot.meanCalciumERKEffect), tint: .pink, values: store.history.map(\.meanCalciumERKEffect))
                    observerMetric("ERK* → traction ×10k", value: scaledRate(store.snapshot.meanERKTractionEffect, by: 10_000), tint: .mint, values: store.history.map(\.meanERKTractionEffect))
                    observerMetric("Signal ATP cost ×10k", value: scaledRate(store.snapshot.cellularSignalingCost, by: 10_000), tint: .orange, values: store.history.map(\.cellularSignalingCost))
                    observerMetric("Obs Δstrain → ΔVₘ", value: strainVoltageAssociationLabel, tint: .pink, values: store.history.map(\.meanTissueStrain))
                    observerMetric("Obs ΔCa* → ΔERK*", value: calciumERKAssociationLabel, tint: .purple, values: store.history.map(\.meanCalciumActivity))
                } else {
                    observerMetric("Components / inferred individuals", value: individualityCountLabel, tint: .mint, values: store.history.map { Double($0.organismCount) })
                    observerMetric("Cells / component", value: "\(store.snapshot.cellCount) / \(decimal(store.snapshot.meanCellsPerOrganism))", tint: .blue, values: store.history.map { Double($0.cellCount) })
                    observerMetric("GRN nodes / edges", value: developmentalTopologyLabel, tint: .pink, values: store.history.map(\.meanDevelopmentalEdgeCount))
                    if store.displayMode == .development {
                        observerMetric("Morphogen A / B", value: "\(decimal(store.snapshot.meanMorphogenActivator)) / \(decimal(store.snapshot.meanMorphogenInhibitor))", tint: .cyan, values: store.history.map(\.meanMorphogenActivator))
                        observerMetric("Differentiation / fate", value: "\(decimal(store.snapshot.meanMorphogenDifferentiation)) / \(decimal(store.snapshot.meanDevelopmentalFateMemory))", tint: .pink, values: store.history.map(\.meanMorphogenDifferentiation))
                        observerMetric("Transport / polarity", value: "\(decimal(store.snapshot.meanJunctionMorphogenTransport)) / \(percent(store.snapshot.meanDevelopmentalPolarityCoherence))", tint: .mint, values: store.history.map(\.meanJunctionMorphogenTransport))
                    }
                    observerMetric("Mean |v|", value: speedLabel, tint: .cyan, values: store.history.map(\.meanOrganismSpeed))
                    observerMetric("Elongation / exposed P", value: "\(decimal(store.snapshot.meanTissueElongation)) / \(decimal(store.snapshot.meanExposedMembraneLength))", tint: .orange, values: store.history.map(\.meanTissueElongation))
                    observerMetric("Force / torque ×10k", value: "\(scaledRate(store.snapshot.meanCellGeneratedForce, by: 10_000)) / \(scaledRate(store.snapshot.meanTissueTorque, by: 10_000))", tint: .green, values: store.history.map(\.meanCellGeneratedForce))
                    observerMetric("Trophic gain / loss ×10k", value: "\(scaledRate(store.snapshot.cellularTrophicGain, by: 10_000)) / \(scaledRate(store.snapshot.cellularTrophicLoss, by: 10_000))", tint: .red, values: store.history.map(\.cellularTrophicGain))
                    observerMetric("Persistent clades", value: "\(store.snapshot.persistentCladeCount)", tint: .orange, values: store.history.map { Double($0.persistentCladeCount) })
                }
            } else {
                observerMetric("Components / inferred individuals", value: individualityCountLabel, tint: .mint, values: store.history.map { Double($0.organismCount) })
                observerMetric("Mean free R", value: resourceLabel, tint: .cyan, values: store.history.map(\.metrics.resourceDensity))
                observerMetric("Substrate forcing", value: decimal(store.snapshot.metrics.substrateFluctuation), tint: .cyan, values: store.history.map(\.metrics.substrateFluctuation))
                observerMetric("Detritus density", value: decimal(store.snapshot.metrics.detritusDensity), tint: .orange, values: store.history.map(\.metrics.detritusDensity))
                observerMetric("Barrier area", value: percent(store.snapshot.metrics.barrierFraction), tint: .gray, values: store.history.map(\.metrics.barrierFraction))
                observerMetric("Mechanical drive", value: decimal(store.snapshot.metrics.environmentalMechanicalDrive), tint: .pink, values: store.history.map(\.metrics.environmentalMechanicalDrive))
                observerMetric("Mean |ΔB|", value: activityLabel, tint: .orange, values: store.history.map(\.metrics.temporalActivity))
                observerMetric("Predatory trait", value: "\(store.snapshot.hunterCount) units", tint: .red, values: store.history.map { Double($0.hunterCount) })
                observerMetric("Persistent clades", value: "\(store.snapshot.persistentCladeCount)", tint: .pink, values: store.history.map { Double($0.persistentCladeCount) })
                observerMetric("Energy residual", value: signedDecimal(store.snapshot.energyConservationResidual), tint: .white, values: store.history.map { abs($0.energyConservationResidual) })
            }
        }
    }

    private var individualityPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("OBSERVER INFERENCE — NONCAUSAL")
            HStack(spacing: 10) {
                evidenceCount("COMP", value: store.observableAgentCount, tint: .cyan)
                evidenceCount("IND", value: store.resolvedIndividualCount, tint: .mint)
                evidenceCount("CDEP", value: Int(store.maximumLivingLineageGeneration), tint: .orange)
                evidenceCount("PGEN", value: Int(store.maximumProgramReplicationGeneration), tint: .pink)
            }
            evidenceRow("AUTONOMY", claim: store.individualityEvidence.mechanochemicalAutonomy)
            evidenceRow("PHYSICAL DESCENT", claim: store.individualityEvidence.physicalDescent)
            evidenceRow("HERITABLE VARIATION", claim: store.individualityEvidence.heritableVariation)
            evidenceRow("DIFF TRANSMISSION", claim: store.individualityEvidence.differentialTransmission)
            evidenceRow("DARWINIAN EVOLUTION", claim: store.individualityEvidence.darwinianEvolution)
            evidenceRow("COLLECTIVE LEVEL", claim: store.individualityEvidence.collectiveLevelIndividuality)
        }
    }

    private var evolutionAfterFormationPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionLabel("PHYSICAL TRANSMISSION")
            HStack(spacing: 0) {
                evolutionClockValue(
                    "C DEPTH",
                    "G\(store.maximumLivingLineageGeneration)"
                )
                evolutionClockValue("P GEN", "G\(store.maximumProgramReplicationGeneration)")
                evolutionClockValue("FISSIONS", "\(recordedFissionCount)")
                evolutionClockValue("DESC", "\(store.livingDescendantCount)")
                evolutionClockValue("D IND", "\(store.resolvedDescendantCount)")
            }

            Text(evolutionaryStateSummary)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)

            Text("Solver steps are dimensionless. Component descent advances at physical separation; program generation advances only when cell division creates a mutated program. Observer claims never alter either process.")
                .font(.system(size: 8, weight: .regular))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func evolutionClockValue(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 6, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var recordedFissionCount: Int {
        store.lineageBranches.count { $0.parentID != nil }
    }

    private var evolutionaryStateSummary: String {
        guard recordedFissionCount > 0 else {
            return "No membrane-disconnected descendant has yet transmitted its already-present cell programs."
        }
        return "\(recordedFissionCount) physical separations have produced \(store.livingDescendantCount) living descendants containing \(store.livingDescendantCellCount) cells. Component depth is G\(store.maximumLivingLineageGeneration); cell-division program replication is G\(store.maximumProgramReplicationGeneration)."
    }

    private var autonomyObservablesPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("MEASURED AUTONOMY VARIABLES")
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading)
                ],
                alignment: .leading,
                spacing: 8
            ) {
                measuredAutonomyValue(
                    "RESOLVED PARTITIONS",
                    value: "cell \(store.resolvedCellIndividualCount) / collective \(store.resolvedCollectiveIndividualCount)",
                    tint: .cyan
                )
                measuredAutonomyValue(
                    "ENERGETIC INDEPENDENCE",
                    value: percent(meanAutonomy(\.energeticIndependence)),
                    tint: .yellow
                )
                measuredAutonomyValue(
                    "BOUNDARY MAINTENANCE",
                    value: percent(meanAutonomy(\.boundaryMaintenance)),
                    tint: .mint
                )
                measuredAutonomyValue(
                    "MECHANOCHEMICAL CLOSURE",
                    value: decimal(meanAutonomy(\.mechanochemicalClosure)),
                    tint: .pink
                )
                measuredAutonomyValue(
                    "ENDOGENOUS INFORMATION",
                    value: compactScientific(meanAutonomy(\.endogenousDetermination)),
                    tint: .cyan
                )
                measuredAutonomyValue(
                    "COOPERATION / CONFLICT",
                    value: "\(decimal(meanAutonomy(\.cooperation))) / \(decimal(meanAutonomy(\.conflict)))",
                    tint: .orange
                )
                measuredAutonomyValue(
                    "HEREDITY",
                    value: decimal(meanAutonomy(\.heredity)),
                    tint: .green
                )
                measuredAutonomyValue(
                    "AUTOCORRELATION TIME",
                    value: String(format: "%.1f samples", store.individualityEvidence.autocorrelationTime),
                    tint: .secondary
                )
                measuredAutonomyValue(
                    "PRICE BETWEEN / WITHIN",
                    value: "\(compactScientific(store.individualityEvidence.selection.betweenComponentSelection)) / \(compactScientific(store.individualityEvidence.selection.withinComponentSelection))",
                    tint: .orange
                )
                measuredAutonomyValue(
                    "TRANSMISSION CHANGE",
                    value: compactScientific(store.individualityEvidence.selection.transmissionChange),
                    tint: .pink
                )
                measuredAutonomyValue(
                    "COLLECTIVE HERITABILITY",
                    value: confidenceLabel(
                        store.individualityEvidence.selection.collectiveHeritability
                    ),
                    tint: .green
                )
                measuredAutonomyValue(
                    "TRANSMITTED COMPONENTS",
                    value: "\(store.individualityEvidence.selection.independentDescendantCount)",
                    tint: .cyan
                )
                measuredAutonomyValue(
                    "TRANSMITTED VARIANTS",
                    value: "\(store.individualityEvidence.selection.transmittedVariantCount)",
                    tint: .pink
                )
                measuredAutonomyValue(
                    "CROSS-COMPONENT CONTACT",
                    value: "\(store.snapshot.crossComponentContactSamples)",
                    tint: .cyan
                )
                measuredAutonomyValue(
                    "BREACH / RESIST",
                    value: "\(store.snapshot.membraneBreachSamples) / \(store.snapshot.resistedAttackSamples)",
                    tint: .red
                )
                measuredAutonomyValue(
                    "TROPHIC TRANSFER",
                    value: "\(store.snapshot.trophicTransferSamples) / \(compactScientific(store.snapshot.transferredEnergy)) E",
                    tint: .yellow
                )
                measuredAutonomyValue(
                    "FUSION CONTACT / JOIN",
                    value: "\(store.snapshot.fusionContactSamples) / \(store.snapshot.successfulFusionContactSamples)",
                    tint: .mint
                )
            }
            Text("Population-weighted measurements are copied from the GPU. Observer inference uses autocorrelation-adjusted windows, block-shuffled nulls, and bootstrap intervals and is never returned to a causal kernel.")
                .font(.system(size: 8, weight: .regular))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func confidenceLabel(_ interval: ConfidenceInterval?) -> String {
        guard let interval else { return "unresolved" }
        return String(
            format: "%.3g [%.3g, %.3g]",
            interval.estimate,
            interval.lower,
            interval.upper
        )
    }

    private var runtimeReliabilityPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("METAL EXECUTION STATE")
            HStack(spacing: 0) {
                evolutionClockValue("SCHEDULED", "\(store.runtimeTelemetry.scheduledStep)")
                evolutionClockValue("GPU DONE", "\(store.runtimeTelemetry.gpuCompletedStep)")
                evolutionClockValue("COMMITTED", "\(store.runtimeTelemetry.scientificallyCommittedStep)")
            }
            HStack(spacing: 0) {
                evolutionClockValue("CHECKPOINT", "\(store.runtimeTelemetry.checkpointStep)")
                evolutionClockValue(
                    "QUEUE",
                    "\(store.runtimeTelemetry.unfinishedCommandBuffers)/\(store.runtimeTelemetry.maximumCommandBuffers)"
                )
                evolutionClockValue("RECOVERIES", "\(store.runtimeTelemetry.recoveryCount)")
            }
            if let error = store.runtimeTelemetry.lastError {
                Text(error)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func measuredAutonomyValue(
        _ label: String,
        value: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(value)
                    .foregroundStyle(.primary)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func meanAutonomy(_ keyPath: KeyPath<AutonomyVector, Double>) -> Double {
        guard !store.autonomyVectors.isEmpty else { return 0 }
        return store.autonomyVectors.reduce(0) { $0 + $1[keyPath: keyPath] } /
            Double(store.autonomyVectors.count)
    }

    private func evidenceCount(_ label: String, value: Int, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func evidenceRow(_ label: String, claim: EvidenceClaim) -> some View {
        HStack(spacing: 7) {
            Circle().fill(evidenceColor(claim.state)).frame(width: 6, height: 6)
            Text(label)
            Spacer()
            Text(claim.state.rawValue.uppercased())
        }
        .font(.system(size: 8, weight: .semibold, design: .monospaced))
        .foregroundStyle(.secondary)
        .help(claim.reason)
    }

    private func evidenceColor(_ state: EvidenceState) -> Color {
        switch state {
        case .supported: .green
        case .inconclusive: .orange
        case .notSupported: .red
        }
    }

    private var molecularReactionPathway: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("MEASURED REACTION PATH")
            HStack(spacing: 4) {
                molecularPathNode(
                    label: "A + B",
                    value: molecularResourceCompactLabel,
                    symbol: "circle.grid.2x2.fill",
                    tint: .cyan
                )
                molecularPathArrow(rate: store.snapshot.meanCatalystProduction, tint: .pink)
                molecularPathNode(
                    label: "CATALYST",
                    value: decimal(store.snapshot.meanMolecularCatalyst),
                    symbol: "aqi.medium",
                    tint: .pink
                )
                molecularPathArrow(rate: store.snapshot.meanPrebioticEnergyProduction, tint: .yellow)
                molecularPathNode(
                    label: "STORED E",
                    value: decimal(store.snapshot.metrics.energyDensity),
                    symbol: "bolt.fill",
                    tint: .yellow
                )
                molecularPathArrow(rate: store.snapshot.meanMembraneAssembly, tint: .mint)
                molecularPathNode(
                    label: "MEMBRANE",
                    value: decimal(store.snapshot.meanMolecularMembrane),
                    symbol: "circle.hexagongrid.fill",
                    tint: .mint
                )
            }
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading)
                ],
                alignment: .leading,
                spacing: 5
            ) {
                molecularGate("Q ORDER", value: store.snapshot.meanQuantumOrder, tint: .purple)
                molecularGate("A·B AFFINITY", value: store.snapshot.meanChemicalAffinity, tint: .blue)
                molecularGate("TOXIN", value: store.snapshot.meanMolecularToxin, tint: .red)
                molecularGate("RECYCLE", value: store.snapshot.meanDetritalMineralization, tint: .orange, scientific: true)
            }
        }
    }

    private var scaleProcessPathway: some View {
        ProcessPathwayView(nodes: processPathNodes)
    }

    private var processPathNodes: [ProcessPathNode] {
        switch activeObservationStop {
        case 0:
            return [
                .init(label: "NORM", value: quantumNormLabel, symbol: "waveform.path", tint: .cyan),
                .init(label: "ORDER Q", value: decimal(store.snapshot.meanQuantumOrder), symbol: "circle.grid.cross", tint: .purple),
                .init(label: "DELTA C", value: compactScientific(store.snapshot.meanCatalystProduction), symbol: "aqi.medium", tint: .pink),
                .init(label: "DELTA E", value: compactScientific(store.snapshot.meanPrebioticEnergyProduction), symbol: "bolt.fill", tint: .yellow)
            ]
        case 1:
            return [
                .init(label: "ORDER Q", value: decimal(store.snapshot.meanQuantumOrder), symbol: "waveform.path", tint: .cyan),
                .init(label: "A·B GATE", value: decimal(store.snapshot.meanChemicalAffinity), symbol: "point.3.connected.trianglepath.dotted", tint: .blue),
                .init(label: "DELTA C", value: compactScientific(store.snapshot.meanCatalystProduction), symbol: "aqi.medium", tint: .pink),
                .init(label: "DELTA E", value: compactScientific(store.snapshot.meanPrebioticEnergyProduction), symbol: "bolt.fill", tint: .yellow)
            ]
        case 3:
            return [
                .init(label: "SUBSTRATE", value: compactScientific(store.snapshot.auditedSubstrateEnergy), symbol: "circle.grid.2x2.fill", tint: .cyan),
                .init(label: "ATP", value: decimal(store.snapshot.meanCellATP), symbol: "bolt.fill", tint: .yellow),
                .init(label: "CA*/ERK*", value: signalCompactLabel, symbol: "waveform.path.ecg", tint: .pink),
                .init(label: "FORCE", value: compactScientific(store.snapshot.meanCellGeneratedForce), symbol: "arrow.up.right", tint: .mint)
            ]
        case 4:
            return [
                .init(label: "CELLS", value: "\(store.snapshot.cellCount)", symbol: "circle.hexagonpath.fill", tint: .cyan),
                .init(label: "EXPOSED P", value: decimal(store.snapshot.meanExposedMembraneLength), symbol: "circle.dashed", tint: .mint),
                .init(label: "NET FORCE", value: compactScientific(store.snapshot.meanCellGeneratedForce), symbol: "arrow.up.right", tint: .green),
                .init(label: "MOTION", value: compactScientific(store.snapshot.meanOrganismSpeed), symbol: "location.north.fill", tint: .orange)
            ]
        default:
            return [
                .init(label: "RESOURCE", value: decimal(store.snapshot.metrics.resourceDensity), symbol: "drop.fill", tint: .cyan),
                .init(label: "ATP", value: compactScientific(store.snapshot.auditedATPHarvest), symbol: "bolt.fill", tint: .yellow),
                .init(label: "WORK", value: compactScientific(ecologicalWork), symbol: "waveform.path", tint: .green),
                .init(label: "DETRITUS", value: decimal(store.snapshot.metrics.detritusDensity), symbol: "arrow.triangle.2.circlepath", tint: .orange)
            ]
        }
    }

    private func molecularPathNode(
        label: String,
        value: String,
        symbol: String,
        tint: Color
    ) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12), in: Circle())
            Text(label)
                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 44)
    }

    private func molecularPathArrow(rate: Double, tint: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint)
            Text(compactScientific(rate))
                .font(.system(size: 6, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 20)
    }

    private func molecularGate(
        _ label: String,
        value: Double,
        tint: Color,
        scientific: Bool = false
    ) -> some View {
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 5, height: 5)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 6, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(scientific ? self.scientific(value) : decimal(value))
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
            }
        }
    }

    private var compactContextHUD: some View {
        HStack(spacing: 12) {
            Image(systemName: observationStops[activeObservationStop].symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(scaleAccent)
                .frame(width: 30, height: 30)
                .background(scaleAccent.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(scaleName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text("\(zoomLabel) · scale 0\(activeObservationStop + 1)")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(scaleAccent)
            }

            commandDivider

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    ForEach(legendItems.prefix(6), id: \.label) { item in
                        HStack(spacing: 4) {
                            Circle().fill(item.color).frame(width: 6, height: 6)
                            Text(item.label)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Text(legendTitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .background(Color.black.opacity(0.66), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.30), radius: 12, y: 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var observationScaleRail: some View {
        HStack(spacing: 1) {
            ForEach(Array(observationStops.enumerated()), id: \.element.id) { index, stop in
                Button {
                    if (index == 3 || index == 4), store.followedAgentID == nil {
                        store.followRandomOrganism()
                    }
                    store.displayMode = stop.displayMode
                    store.zoom(to: stop.magnification, aspect: 1)
                } label: {
                    Image(systemName: stop.symbol)
                        .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(index == activeObservationStop ? scaleAccent : Color.secondary)
                    .frame(width: 28, height: 32)
                    .background(
                        index == activeObservationStop ? scaleAccent.opacity(0.15) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 5)
                    )
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(index == activeObservationStop ? scaleAccent : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .help("Jump to \(stop.label.lowercased()) scale")
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
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .contentTransition(.numericText())
            }
            .frame(width: 148, alignment: .leading)

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
                    Text("\(eventCoordinateLabel(event.kind)) \(event.generation)")
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

    private func lineageRow(_ branch: ObservedLineageBranch) -> some View {
        HStack(spacing: 9) {
            Image(systemName: branch.deathStep == nil ? "point.3.connected.trianglepath.dotted" : "xmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(branch.deathStep == nil ? Color.cyan : Color.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(branch.parentID.map { "birth #\(branch.id) ← #\($0)" } ?? "founder #\(branch.id)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                Text(String(
                    format: "step %u · topology %08X · Δ %.3f · f₀ %.2f/1k",
                    branch.birthStep,
                    branch.topologyHash,
                    branch.mutationDistance,
                    branch.resonanceFrequency * 1_000
                ))
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
        if store.displayMode == .causality, zoom < 64 {
            return zoom >= 18
                ? "Counterfactual mechanochemical pathways"
                : "Causal activity across cells, tissues, and organisms"
        }
        if zoom >= 512 { return "Two-component coined quantum walk" }
        if zoom >= 160 { return "Probability density, phase, and probability current" }
        if zoom >= 64 {
            return store.displayMode == .causality
                ? "Mechanistic reaction-source terms"
                : "Catalyst-mediated reaction flux and membrane assembly"
        }
        if zoom >= 18 {
            return store.displayMode == .development
                ? "Junction-coupled morphogen development"
                : "Cell-derived geometry and mechanochemical control"
        }
        if zoom >= 6 {
            return store.resolvedIndividualCount > 0
                ? "Observer-resolved autonomous tissue"
                : "Membrane-connected component dynamics"
        }
        return "Contact-mediated trophic and vibrational niches"
    }

    private var inspectorSummary: String {
        guard store.observationZoom >= 6, store.observationZoom < 18 else {
            return worldSummary
        }
        let components = max(store.snapshot.organismCount, store.observableAgentCount)
        return "\(store.snapshot.cellCount) persistent cells form \(components) membrane-connected component\(components == 1 ? "" : "s"); the noncausal observer resolves \(store.resolvedIndividualCount) persistent information-local maximum\(store.resolvedIndividualCount == 1 ? "" : "s"). Exposed perimeter is \(decimal(store.snapshot.meanExposedMembraneLength)); cell-generated force \(compactScientific(store.snapshot.meanCellGeneratedForce)) produces translation \(compactScientific(store.snapshot.meanOrganismSpeed))."
    }

    private var scientificDefinitionText: String {
        if store.observationZoom >= 6, store.observationZoom < 18 {
            return worldSummary + "\n\n" + scaleRelation
        }
        return scaleRelation
    }

    private var worldSummary: String {
        let zoom = store.observationZoom
        let units = max(store.snapshot.organismCount, store.observableAgentCount)
        if store.displayMode == .causality, zoom < 64 {
            let edgeState = store.mechanosensingBlocked ? "ablated (gain = 0)" : "active (gain = 1)"
            return "Mechanics→Ca* and Ca*→ERK* are factual-minus-single-edge-zero update differences. ERK*→traction and signaling ATP cost are direct equation terms. Mean values are \(causalRate(store.snapshot.meanMechanicsCalciumEffect)) ×10⁻³, \(causalRate(store.snapshot.meanCalciumERKEffect)) ×10⁻³, and \(scaledRate(store.snapshot.meanERKTractionEffect, by: 10_000)) ×10⁻⁴ for the first three terms. Ca* and ERK* are dimensionless excitable-state variables, not resolved molecular concentrations. Mechanics gating is \(edgeState). Observational rows use predeclared one-sample-lag first-difference correlations with autocorrelation-adjusted 95% intervals; they are not causal effects."
        }
        if zoom >= 512 {
            return "ψ = (ψ₀, ψ₁) is stored as four real components on a 1024² periodic lattice. Each update applies a local coin rotation and alternates conditional shifts along x and y. Measured Σρ = \(quantumNormValue)."
        }
        if zoom >= 160 {
            return "ρ = |ψ₀|² + |ψ₁|². Component overlap contributes to the catalyst source term. Mint-to-amber feedback contours evaluate the same local resource, biomass, membrane, toxin, and inherited-trait terms that modify phase potential and coin angle in the quantum update; they are diagnostics, not additional forces."
        }
        if zoom >= 64 {
            return "The 193² reaction lattice stores substrate A, biomass, energy E, membrane precursor M, substrate B, detritus, toxin, and catalyst C. The canvas maps concentrations to species glyphs and maps the exact local source terms to moving flux pulses; glyphs are field markers, not atom-resolved particles. Spinor order and mechanical activity produce C, C gates E production, E and C gate M assembly, and catalyst accelerates detrital recycling."
        }
        if zoom >= 18 {
            if store.displayMode == .development {
                return "Morphogen A and B are synthesized and degraded using inherited kinetic constants, then diffuse only through recent persistent cell junctions. Their receptor-weighted imbalance updates continuous fate memory and tissue polarity, which alter division axes, membrane allocation, traction, feeding, and defense. Mean A/B is \(decimal(store.snapshot.meanMorphogenActivator))/\(decimal(store.snapshot.meanMorphogenInhibitor)); differentiation is \(decimal(store.snapshot.meanMorphogenDifferentiation))."
            }
            return "\(store.snapshot.cellCount) persistent cells are active across \(units) physical components. Exposed membrane arcs determine covariance axes, elongation, polarity, and boundary length. Cell-local chemistry, Ca*/ERK* signaling, adhesion, and traction produce component force and torque; observer labels do not alter these equations."
        }
        if zoom >= 6 {
            return units == 0
                ? "No biological component is active. Founder nucleation remains driven by measured biomass, stored energy, membrane precursor, and catalyst concentrations."
                : "Every nonempty membrane-connected component has an independent handle immediately after separation. IND = \(store.resolvedIndividualCount) is inferred from persistent conditional self-predictive information relative to block-shuffled nulls; it never unlocks survival, division, or reproduction."
        }
        let occupied = percent(store.snapshot.metrics.occupiedFraction)
        return "\(units) physical components and \(store.resolvedIndividualCount) observer-resolved individuals are present; \(store.snapshot.persistentCladeCount) genealogically and morphologically persistent clades are resolved; occupied-field fraction is \(occupied). These measurements are distinct and none is a programmed fitness value."
    }

    private var scaleRelation: String {
        if store.displayMode == .causality, store.observationZoom < 64 {
            return "Mechanical strain drives the inherited resonator, membrane voltage, and mechanogated Ca*-like influx. Inherited gains scale Ca* and ERK* contact propagation, refractory recovery, signaling cost, and traction. Exposed cells combine local substrate gradients, ERK* wave direction, and developmental polarity into external force; the tissue reduction converts summed force and torque into organism motion. The intervention sets direct mechanics→voltage and mechanics→Ca* gains to zero while leaving neighbor propagation and downstream dynamics active."
        }
        return switch activeObservationStop {
        case 0: "ρ and normalized component overlap define quantumOrder, which enters the catalyst-production term in reactWorld."
        case 1: "Matter changes coin angle θ and local phase V; spinor density and overlap change catalyst and stored-energy production."
        case 2: "Local chemical affinity is sqrt(A·B) times permeability and toxin inhibition. Quantum order and mechanical activity add catalyst; catalyst then gates stored-energy production. Quantum order, catalyst, and E set the membrane target, while catalyst-dependent mineralization returns detritus to both substrates. Cells consume these fields for ATP and return mechanical work and detritus, closing the cross-scale loop."
        case 3: "A bounded sparse graph maps eight local inputs into proliferation, adhesion, contraction, repair, permeability, secretion, apoptosis suppression, and motility. Cell-cycle and biomass dynamics use measured substrate harvest relative to maintenance, work, and dissipation together with ATP reserve, exposed membrane, crowding, stress, and inherited regulation. Inherited morphogen source, decay, receptor, and diffusivity parameters operate across persistent junctions; their local imbalance updates fate memory and polarity. Exposed membrane edges define geometry, and cell-local gradients, ERK* state, and developmental polarity generate external traction."
        case 4: "GPU union-find labels membrane-connected cells independently of storage position. Every detached nonempty component receives a handle immediately. Cross-owner fusion follows membrane contact and reciprocal ligand-receptor mechanics. Fission transmits programs already present in cells without mutation; mutation occurs only during ATP-funded cell division. Permanent cell IDs and acquired states persist through ownership changes."
        default: "Resources and hazards act through cell-local uptake, stress, and traction. Hunting requires specialized exposed cells to make physical contact; membrane support must fail locally before ATP and biomass transfer. Differential survival and reproduction therefore arise without an organism-level fitness function."
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

    private var signalCompactLabel: String {
        String(
            format: "%.2f/%.2f",
            max(store.snapshot.meanCalciumActivity, 0),
            max(store.snapshot.meanERKActivity, 0)
        )
    }

    private var ecologicalWork: Double {
        max(store.snapshot.auditedActiveWork + store.snapshot.auditedFrequencyWork, 0)
    }

    private func compactStep(_ step: UInt64) -> String {
        if step >= 1_000_000 {
            return String(format: "%.1fM", Double(step) / 1_000_000)
        }
        if step >= 1_000 {
            return String(format: "%.1fk", Double(step) / 1_000)
        }
        return "\(step)"
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
        if zoom < 18 {
            return store.resolvedIndividualCount > 0
                ? "Observer-resolved tissue morphology" : "Component morphology"
        }
        if zoom < 64 { return "Cellular tissue" }
        if zoom < 160 { return "Molecular reaction chemistry" }
        if zoom < 512 { return "Wave observables" }
        return "Spinor field"
    }

    private var observationStops: [ObservationStop] {
        [
            ObservationStop(
                label: "Spinor", symbol: "atom", magnification: 900,
                displayMode: .ecology
            ),
            ObservationStop(
                label: "Wave", symbol: "waveform.path", magnification: 240,
                displayMode: .ecology
            ),
            ObservationStop(
                label: "Molecule", symbol: "scope", magnification: 96,
                displayMode: .energy
            ),
            ObservationStop(
                label: "Cell", symbol: "circle.hexagonpath.fill", magnification: 36,
                displayMode: .development
            ),
            ObservationStop(
                label: "Morphology", symbol: "microbe.fill", magnification: 10,
                displayMode: .genome
            ),
            ObservationStop(
                label: "Ecology", symbol: "circle.hexagongrid.fill", magnification: 1,
                displayMode: .ecology
            )
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
        if store.displayMode == .causality, store.observationZoom < 64 {
            return [("Mechanics→Ca*", .cyan), ("Ca*→ERK*", .pink), ("ERK*→traction", .mint), ("Signal ATP", .orange)]
        }
        if store.observationZoom >= 512 {
            return [("Spin +", .cyan), ("Spin -", .orange), ("Current", .white), ("Nodes", .purple)]
        }
        if store.observationZoom >= 160 {
            return [("Probability", .cyan), ("Phase", .pink), ("Current", .white), ("Matter feedback", .mint)]
        }
        if store.observationZoom >= 64 {
            return switch store.displayMode {
            case .ecology:
                [("Resource A", .cyan), ("Resource B", .purple), ("Catalyst", .pink), ("Stored E", .yellow), ("Membrane", .mint), ("Toxin", .red)]
            case .energy:
                [("Resource A", .cyan), ("Resource B", .purple), ("Catalyst", .pink), ("Stored E", .yellow), ("Membrane", .mint), ("Detritus", .orange)]
            case .genome:
                [("Metabolism", .red), ("Membrane", .green), ("Dispersal", .blue), ("Predation", .pink)]
            case .niches:
                [("Resource A", .cyan), ("Resource B", .purple), ("Detritus", .orange), ("Toxin", .red)]
            case .development:
                [("Catalyst", .pink), ("Stored E", .yellow), ("Membrane", .mint), ("Assembly", .green)]
            case .causality:
                [("Q×affinity→C", .cyan), ("C,Q→E", .pink), ("E,C→M", .mint), ("Detritus→A+B", .orange)]
            }
        }
        if store.observationZoom >= 18 {
            if store.displayMode == .development {
                return [
                    ("Morphogen A", .cyan), ("Morphogen B", .pink),
                    ("Fate", .mint), ("Polarity", .white), ("Junction flux", .blue)
                ]
            }
            return [("Ca*", .cyan), ("ERK*", .pink), ("Traction", .mint), ("ATP", .orange), ("Vₘ", .red), ("Membrane", .blue)]
        }
        if store.observationZoom >= 6 {
            return [
                ("Exposed membrane", .white), ("Cell identity", .cyan),
                ("Nucleus / ERK*", .pink), ("Junction", .mint),
                ("ATP", .yellow), ("Traction", .green)
            ]
        }
        if store.displayMode == .ecology {
            return [("Organisms", .cyan), ("Substrate A", .green), ("Substrate B", .yellow), ("Barrier", .gray), ("Toxin", .red), ("Forcing", .pink)]
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
        case .development:
            return [("Proliferate", .yellow), ("Adhesive", .mint), ("Contractile", .pink), ("Repair", .blue)]
        case .causality:
            return [("Mechanics→Ca*", .cyan), ("Ca*→ERK*", .pink), ("ERK*→traction", .mint), ("Signal ATP", .orange)]
        }
    }

    private var legendTitle: String {
        if store.displayMode == .causality, store.observationZoom < 64 {
            return "One-edge-zero causal terms"
        }
        if store.displayMode == .development, store.observationZoom >= 18,
           store.observationZoom < 64 {
            return "Junction-coupled development"
        }
        return store.observationZoom >= 512 ? "Spinor components" :
            store.observationZoom >= 160 ? "Quantum observables" :
            store.observationZoom >= 64 ? "Reaction pools and flux" :
            store.observationZoom >= 18 ? "Electromechanical cell state" : store.displayMode.label
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", min(max(value, 0), 1) * 100)
    }

    private func decimal(_ value: Double) -> String {
        String(format: "%.4f", max(value, 0))
    }

    private func signedDecimal(_ value: Double) -> String {
        String(format: "%+.3f", value)
    }

    private func scientific(_ value: Double) -> String {
        String(format: "%.2e", max(value, 0))
    }

    private func compactScientific(_ value: Double) -> String {
        String(format: "%.0e", max(value, 0))
    }

    private var molecularResourcePairLabel: String {
        "\(decimal(store.snapshot.metrics.resourceDensity * 2)) / " +
            decimal(store.snapshot.meanMolecularResourceB)
    }

    private var molecularResourceCompactLabel: String {
        String(
            format: "%.2f/%.2f",
            max(store.snapshot.metrics.resourceDensity * 2, 0),
            max(store.snapshot.meanMolecularResourceB, 0)
        )
    }

    private func causalRate(_ value: Double) -> String {
        String(format: "%+.3f", value * 1_000)
    }

    private func scaledRate(_ value: Double, by scale: Double) -> String {
        String(format: "%+.3f", value * scale)
    }

    private var strainVoltageAssociationLabel: String {
        laggedAssociation(
            cause: { $0.meanTissueStrain },
            effect: { $0.meanMembraneVoltage }
        )
    }

    private var calciumERKAssociationLabel: String {
        laggedAssociation(
            cause: { $0.meanCalciumActivity },
            effect: { $0.meanERKActivity }
        )
    }

    private var frequencyTractionAssociationLabel: String {
        laggedAssociation(
            cause: { $0.meanFrequencyMatch },
            effect: { $0.meanCellGeneratedForce }
        )
    }

    private func laggedAssociation(
        cause: (EvolutionSnapshot) -> Double,
        effect: (EvolutionSnapshot) -> Double
    ) -> String {
        guard let estimate = CausalAnalysis.laggedDifferenceAssociation(
            cause: store.history.map(cause),
            effect: store.history.map(effect)
        ) else { return store.history.count < 10 ? "collecting n≥8" : "zero variance" }
        guard let lower = estimate.confidenceLower,
              let upper = estimate.confidenceUpper else {
            return String(
                format: "rΔ₁ %+.2f · nₑ %.1f",
                estimate.correlation,
                estimate.effectiveSampleCount
            )
        }
        return String(
            format: "rΔ₁ %+.2f [%+.2f,%+.2f] nₑ%.1f",
            estimate.correlation,
            lower,
            upper,
            estimate.effectiveSampleCount
        )
    }

    private var membraneGeometryLabel: String {
        String(
            format: "%.3f / %.3f (S %.2f)",
            store.snapshot.meanMembraneArea,
            store.snapshot.meanMembranePerimeter,
            store.snapshot.meanMembraneShapeIndex
        )
    }

    private var resonanceTuningLabel: String {
        String(
            format: "%.2f/1k / %.2f",
            store.snapshot.meanResonanceFrequency * 1_000,
            store.snapshot.meanResonanceDamping
        )
    }

    private var resonanceResponseLabel: String {
        String(
            format: "%.4f / %.2e",
            store.snapshot.meanResonanceAmplitude,
            store.snapshot.meanJunctionForce
        )
    }

    private var signalStateLabel: String {
        String(
            format: "%.3f / %.3f / %.3f",
            store.snapshot.meanCalciumActivity,
            store.snapshot.meanERKActivity,
            store.snapshot.meanSignalRefractory
        )
    }

    private var developmentalTopologyLabel: String {
        String(
            format: "%.1f / %.1f",
            store.snapshot.meanDevelopmentalNodeCount,
            store.snapshot.meanDevelopmentalEdgeCount
        )
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
        case .fusion: "link"
        case .emergence: "point.3.connected.trianglepath.dotted"
        case .cellDivision: "arrow.triangle.2.circlepath"
        case .programMutation: "point.3.filled.connected.trianglepath.dotted"
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
        case .fusion: .cyan
        case .emergence: .green
        case .cellDivision: .cyan
        case .programMutation: .pink
        }
    }

    private func eventCoordinateLabel(_ kind: EvolutionEventKind) -> String {
        switch kind {
        case .branching, .fusion: "CDEP"
        case .cellDivision, .programMutation: "PGEN"
        default: "EPOCH"
        }
    }

    private var individualityCountLabel: String {
        "\(store.observableAgentCount) / C\(store.resolvedCollectiveIndividualCount) + S\(store.resolvedCellIndividualCount)"
    }
}

private struct ObservationStop: Identifiable {
    let label: String
    let symbol: String
    let magnification: Double
    let displayMode: FieldDisplayMode

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
