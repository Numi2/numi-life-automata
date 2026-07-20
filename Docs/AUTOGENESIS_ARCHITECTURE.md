# Numi Automata Metal Architecture

## Product Contract

Numi Automata opens at spinor scale with a persistent `1024 x 1024` two-component complex field, one `193 x 193` chemical and geological substrate, zero organisms, and zero organism-owned cells. Spinor coherence must first produce catalyst, stored energy, and a closed membrane. A locally self-maintaining membrane can atomically claim slot zero as the first founder, claim one generation-tagged heritable-program slot, and initialize exactly one cell. Up to 384 simultaneous component identities share one global pool of 9,216 persistent cells and a recyclable pool of 4,096 live inherited programs. Cell storage position does not determine organism membership, and component ownership does not determine inherited-program identity. Additional organism and cell records are claimed only by connectivity-derived reproduction, cell division, or an explicit **Add colony** action. Camera movement and rendering never create state.

The UI exposes observation rather than simulation configuration: pause, restart, add a founder, choose speed or diagnostic mode, navigate physical scale, and follow or browse organisms. Population, hunters, resources, turnover, events, and quantum norm are measured from live state.

## Persistent Organisms

Each `AgentState` stores:

- Stable slot identity and occupancy.
- World-space position and velocity.
- Three inherited four-component gene vectors.
- Last measured pursuit, attack-contact, and threat behavior.
- Energy, biomass, age, and generation.
- The dominant inherited-program index used for organism-level summaries.

`nucleateAutogenicFounder` accepts only a local maximum with enough biomass, stored energy, catalyst, and membrane. Its inherited phase and metabolic biases come from the local spinor and chemistry rather than a predefined founder genome. `evolveAgents` integrates only force, torque, mass, and moment of inertia reduced from cells during the previous update. GPU union-find can allocate a descendant only after a viable membrane-connected cellular component has physically disconnected from the parent's primary component. No frame, lattice tile, agent energy threshold, or random birth draw synthesizes an organism.

There is no separate organism body shader. Ecology, organism, and cellular views submit the same GPU-compacted living cells and construct a tissue contour from their simulated membrane vertices. Predatory protrusions, armor, sensors, and locomotor extensions become visible only where exposed cells physically deform their membranes under the corresponding inherited regulatory output. Lineage color and physiological overlays describe those cells; they do not instantiate anatomy or assign a species.

## Persistent Cells

`CellState` is a 272-byte record containing organism-relative position and velocity plus sixteen state vectors:

- Physiology: ATP, biomass, cell-cycle phase, membrane integrity.
- Phenotype: adhesion, contractility, resource-A uptake, resource-B uptake.
- Signals: central morphogen, peripheral morphogen, stress, apoptosis activation.
- Interaction: nearest-contact direction, contact-cycle brake, direct mechanics-to-voltage contribution.
- Dynamics: membrane voltage, excitable recovery, oscillator phase, intrinsic frequency.
- Mechanics: contractile activation, extracellular strain, wave speed, local phase coherence.
- Energetics: harvest, maintenance, active work, dissipation.
- Regulation: proliferation, adhesive-core fate, contractile-edge fate, repair.
- Regulation B: permeability, secretion, apoptosis suppression, motility.
- Resonance: resonator displacement, velocity, response amplitude, previous strain input.
- Membrane: polygon area, perimeter, shape index, transmitted junction force.
- Signaling: dimensionless calcium-like activity, ERK-like activity, refractory state, neighbor signal input.
- Signal causality: mechanics-to-Ca* edge effect, Ca*-to-ERK* edge effect, ERK*-traction magnitude, signaling ATP cost.
- Tissue geometry: vertex-derived outward normal, exposed membrane fraction, physical detachment score.
- Tissue force: local traction/contact force, contact damage, signed trophic transfer.
- Environment: substrate forcing, barrier load, environmental forcing frequency, frequency match.

Each cell has a hot 32-byte identity record containing its current physical component owner, inherited-program index and slot generation, monotonic permanent cell ID, and current union-find root. Parent-cell ID remains persistent in a separate 4-byte cold genealogy buffer written only at founder creation and division. A separate 16-byte cold interaction vector stores signed ATP transfer, incompatible-program rejection, reciprocal recognition compatibility, and local net energetic contribution without expanding the 272-byte hot cell record. All 9,216 cells share one atomic allocation pool. Per-owner and per-root segmented linked lists are rebuilt on the GPU, so tissues need not occupy contiguous records and component-specific work does not rescan the complete cell pool. `evolveOrganismCells` validates the generation-tagged program reference, then reads developmental topology, mechanochemical gains, resonant tuning, recognition coordinates, and social-control coefficients. It computes program-specific ATP sharing and rejection, voltage and phase coupling, resonant strain sensing, contact-propagated mechanochemical signaling, exact substrate claims, ATP accounting, sparse graph dynamics, phenotype differentiation, cycle progression, and traction. `evolveCellMembranes` advances twelve explicit vertices per occupied cell. A GPU spatial hash resolves same-owner and cross-owner membrane support, persistent junctions, equal-and-opposite pair impulses, localized damage, breach-gated trophic transfer, and local connectivity candidates. `measureCellMembraneExposure` tests every physical edge against nearby same-owner polygons. `divideAndReduceOrganismCells` claims global free cells for division and reduces only those measured exposed segments into covariance, axes, extents, polarity, force, torque, contact, trophic state, inherited-program composition, recognition, rejection, exchange, contribution, and environmental forcing.

Each 96-byte inherited-program payload stores three trait vectors, two ligand coordinates, two receptor coordinates, fusion investment, ATP-sharing gain, incompatible-cell rejection gain, propagule-transmission gain, and genome/provenance hashes. Its independent 16-byte slot state stores occupancy, living-cell reference count, slot generation, and lineage hash. Every program read validates `(index, generation)`. Division retains the reference; cell death releases it; owner reassignment retains the descendant before releasing the source. A zero reference count atomically returns the payload slot to the free pool. Permanent ancestry remains in the immutable 64-byte lineage-event ring rather than pinning dead program payloads.

A live program references a 96-byte developmental header, sixteen 32-byte node slots, forty-eight 32-byte directed-edge slots, and one 32-byte resonance record. A node stores bias, response rate, sensor coupling, actuator coupling, sensor index, actuator mask, innovation ID, and activity. An edge stores weight, strain-dependent plasticity, endpoints, innovation ID, and activity. Eight inputs carry ATP, voltage, strain, contact density, morphogen polarity, local opportunity minus stress, resonant response, and membrane deformation plus junction force. Eight output channels control proliferation, adhesion, contraction, repair, permeability, secretion, apoptosis suppression, and motility. The header additionally stores heritable mechanics-to-Ca*, junction, Ca*-to-ERK*, refractory recovery, signaling-cost, traction, detachment-threshold, and propagule-investment coefficients. Recognition and social variables are dimensionless model controls, not molecular identities or calibrated immune kinetics.

Propagule separation traverses the root-indexed segmented cell list, enumerates distinct source programs, independently claims one recyclable slot per source, and maps each source to an independently mutated descendant. Partial allocation rolls back all claimed slots. Numerical mutation includes trait vectors, recognition coordinates, social controls, mechanochemical gains, and resonance. Structural mutation can duplicate or silence nodes and add, remove, or reconnect edges. Every new structural record receives a monotonic innovation ID. The header retains active counts, topology hash, cumulative and last branch mutation distance, and structural-mutation count. Founders start from one cell. Descendants receive the exact separated cells, membrane vertices, and acquired regulatory activities while each cell receives only the mapped descendant of its own source program. One propagule can transmit at most sixteen distinct programs; exceeding that explicit hardware bound prevents reproduction rather than collapsing program identity.

Each program also carries eight inherited resonance parameters: natural frequency, damping ratio, input gain, response threshold, bandwidth, adaptation rate, phase delay, and directional preference. Cells integrate a damped second-order response to extracellular strain rate. Its signed thresholded amplitude enters voltage, Ca* gating, phase, and the regulatory graph. Frequency can adapt only within the inherited bandwidth; reproduction mutates the tuning parameters.

Each reaction tile publishes fixed-point availability for resource A, resource B, and detritus. Cells claim those reservoirs with compare-and-swap; claimed substrate is converted to ATP with an inherited bounded efficiency, and the conversion loss is exported as heat. ATP pays maintenance, signaling, contraction, electrical activity, rejection, stress dissipation, and a frequency-dependent resonator cost proportional to `(v^2 + omega^2 x^2)(0.00042 + 0.075 f)(0.58 + 0.82 g)`. Maintenance returns 34% to detritus and 66% to heat; biomass loss and death return 72% to detritus and 28% to heat. `reactWorld` debits the exact claims and restores detritus on the following update. A ten-channel signed fixed-point audit records substrate input, ATP harvest, ATP-plus-biomass storage change, active work, frequency work, maintenance, heat, detrital energy, internal ATP sharing, and the global conservation residual. No organism-level proxy participates in this ledger.

Ca* and ERK* are dimensionless active-state variables, not concentrations. Contact-weighted neighboring Ca*/ERK* produces junctional propagation. Mechanical resonance, local strain, and transmitted junction force gate Ca* entry; Ca* drives ERK*; ERK* drives evolved motility-dependent traction opposite its local gradient. A refractory state suppresses repeated Ca* entry and propagation. The active states and both edge contributions consume ATP. For every update, the kernel evaluates factual Ca*/ERK* results and a local result with the selected incoming edge set to zero while holding the pre-update state fixed. It retains mechanics-to-Ca* and Ca*-to-ERK* factual-minus-edge-zero differences, ERK*-traction magnitude, and signaling work. These values are model-internal direct terms, not estimates from trajectory covariance.

The reduction kernel emits a 304-byte `CellAggregate`: physiology, morphology, voltage and phase statistics, mechanics, energy terms, actuator vectors, direct equation terms, resonance, polygon geometry, mechanochemical state, exposed-edge covariance axes and extents, polarity, boundary length, net force, torque, contact load, trophic flux, detachment readiness, dominant/non-dominant program fractions, hashed program-richness lower bound, dominant-program index, mean absolute ATP exchange, rejection load, recognition compatibility, net program contribution, substrate forcing, barrier load, environmental frequency, and frequency match. Boundary covariance is the analytic line integral over exposed polygon segments, and extents project the segment endpoints rather than cell centers or a synthetic envelope. `evolveAgents` consumes the previous aggregate, while the renderer directly consumes current cells and membrane vertices. This one-step delayed physical feedback avoids a CPU synchronization point while preserving the causal sequence:

```text
substrate chemistry -> cell-local signaling and traction -> membrane geometry and contact -> tissue force and torque -> organism motion and reproduction
```

Each cell accumulates a signed fixed-point contraction impulse into a `193 x 193 x 2` private atomic buffer. `evolveMechanicalField` consumes and zeros the impulse with relaxed atomic exchange while advancing a damped vector wave over a ping-pong `RGBA16Float` texture pair. Displacement gradients feed cell strain; velocity contributes dissipation; strain changes voltage and reaction chemistry. Cells respond locally through inherited resonance and traction; there is no agent-level vibration steering. This is a closed feedback cycle, not a render-only effect.

The mechanics-to-voltage and mechanics-to-Ca* edges share one intervention gain in `SimulationUniforms`. The normal value is `1`; the ECG control sets it to `0` without stopping mechanics or resonance. The next metric reduction records a single-trajectory response and does not label it a controlled effect. Observational diagnostics use a predeclared one-sample lag between first differences and report Pearson `r`, an effective sample count adjusted by the two series' lag-one autocorrelation, and a Fisher-transformed 95% interval. The effective-count adjustment is an AR(1)-style approximation and does not cover arbitrary long-memory or nonlinear dependence. This remains predictive association rather than causal identification. The **Causal terms** renderer uses cyan for mechanics-to-Ca*, magenta for Ca*-to-ERK*, green for ERK*-traction, and orange for signaling ATP cost. The original mechanics-to-voltage, cycle-drive, contact-suppression, and repair terms remain available in organism state.

Cells produced by division receive a new permanent cell ID, their parent's cell ID, the same inherited-program index and generation, and perturbed oscillator phases, frequencies, graph activities, resonator state, and polygon state. Contact phase coupling depends separately on sender and receiver phenotype, so it is generally nonreciprocal. Mechanical contact is reciprocal: each canonical pair computes actual support vertices once and accumulates equal-and-opposite fixed-point center and vertex impulses. Same-owner adhesive pairs acquire persistent rest distance, strength, age, and load in the junction hash. Unlike-program neighbors compute reciprocal ligand/receptor compatibility. Compatibility gates bilateral ATP sharing; incompatibility and inherited rejection gain impose ATP cost, stress, apoptosis activation, and membrane loss. Atomic union-find labels connected components from membrane support, adhesion, and integrity. Different owners can join only under direct support contact, high reciprocal adhesion and integrity, low stress and predatory investment, reciprocal recognition compatibility, bilateral fusion investment, and `fusionDrive > 0.38`. Union roots are ordered by permanent cell ID; the component containing the oldest participating cell anchors physical ownership independent of thread scheduling. The transition appends a fusion event with both birth IDs. Reframed cells retain their own programs and acquired state, permitting mixed-program tissue without rewriting cellular inheritance. This is a dimensionless fusion rule, not a calibrated biological fusion, histocompatibility, or symbiosis model.

For same-owner fragmentation, the largest component retains identity. Any other component must maintain mean ATP of at least `0.48`, mean integrity of at least `0.58`, exceed the detachment threshold modulated by inherited propagule-transmission gain, claim a free component slot, and claim one recyclable program slot per transmitted source program. Its existing cells retain their records and acquired state while receiving a new owner; each program group receives its independently mutated trait, recognition, social-control, developmental, mechanochemical, and resonance parameters. Disconnected nonviable fragments are removed instead of sharing the parent's dynamics.

## Permanent Genealogy

Agent slots are reusable storage, not biological identity. Every founder and offspring atomically acquires a monotonic `birthID`; inherited offspring store `parentBirthID`. Birth, death, and physical-fusion transitions append sequence-numbered 64-byte records to a 4,096-entry private GPU ring. Fusion records use `birthID` for the persistent component and `parentBirthID` for the incorporated component. Each record includes step, generation, genome and topology hashes, branch mutation distance, resonance frequency, energy, and a compact morphology descriptor.

Observation commands copy the event ring and its monotonic write counter into a triple-buffered shared ring. Swift reconstructs the parent-ID graph and computes path distance to the lowest common predecessor plus normalized morphology distance. A clade is reported only after combined genealogical, topology, and morphology separation persists for at least 1,200 steps. This observer analysis does not feed simulation state and is not called a species count because the asexual model has no reproductive-isolation criterion.

## Physical Scale

The finite backing textures can expand while the observed world remains continuous. `worldScale` records how much physical territory a normalized backing texture represents. Physical magnification is:

```text
observationZoom = cameraZoom / worldScale
```

When the backing world doubles, old ecology is copied into the central half, agent positions and velocity are halved, and `cameraZoom` and `worldScale` double together. The one cell-local-to-world length unit is divided by `worldScale`; therefore membrane radii, tissue extents, contact distance, translation, and separated-component position preserve physical scale without rescaling stored cell geometry.

The follow camera consumes ring-buffered GPU observations and tracks a permanent birth ID while translating it to the currently occupied storage slot for rendering. Slot reuse cannot transfer the camera to an unrelated organism. Previous, next, and horizontal trackpad navigation replace only the tracked birth ID.

## Environment

Persistent geology defines localized nutrient beds, mineral deposits, toxic vents, and rock obstacles, with large empty regions between them. Deposit supply is modulated by deterministic local phase and frequency fields rather than constant regeneration. Exact fixed-point cellular claims can exceed local replenishment and therefore generate persistent depletion gradients. Catalyst-dependent mineralization transfers bounded detrital fractions back into both substrate reservoirs; toxin and low permeability suppress that recycling.

Rock produces a local outward cell force, velocity damping, stress, and dissipative ATP cost. It also lowers field-level permeability. The extracellular mechanical equation receives deterministic geological oscillators with continuously varying local frequency and amplitude. Cells compare that frequency with their inherited resonator frequency and bandwidth. Mismatch under finite drive adds stress and dissipation. Constructed armor, predatory lobes, sensors, and locomotor extensions consume ATP; armor also increases reduced tissue mass/drag and lowers uptake. Contact attack and defense use the actual contacted arc and its directional construction, not a genome value alone.

These equations create resource-time, recycling, barrier, mechanical-spectrum, offense, and defense constraints without assigning a species or niche identifier. The corresponding observer channels are substrate forcing, detritus density, barrier fraction, environmental mechanical drive, per-cell barrier load, environmental frequency, frequency match, armor construction, and predatory construction.

## Long-Duration Experiments And Invariants

`NumiAutomata experiment` uses `EvolutionRenderer.encodeSimulationStep` without drawable acquisition or render encoding. One UInt32 seed enters initial geology and spinor phase; all later stochastic transitions derive from seeded state, integer simulation step, permanent identity, and local coordinates. A configurable number of biological steps is encoded per command buffer. Quantum evolution defaults to one update per three biological updates, matching the interactive default. Epoch generation and perturbation cadence are preserved.

The standard JSONL journal has four record types: configuration header, exact lineage event, periodic state sample, and terminal summary. Samples include current trophic transfer, program-slot generations and recycling count, membrane-derived morphology, energy residual, junction count/load, cell-weighted ATP, integrity, stress, voltage, Ca*, ERK*, division, traction, frequency match, and cumulative event counts. A parent-bearing birth event is also classified as physical fission. Ring overflow is an error rather than a silent loss of scientific records.

`NumiAutomata causal-experiment` performs replicated paired interventions. SplitMix64 derives at least four distinct replicate seeds from one master seed. For each derived seed, control and treatment execute gain `1` through the configured intervention boundary. Control retains gain `1`; treatment changes to `0`. A forced boundary readback must match exactly over the recorded outcome vector before the pair is accepted. Final outcomes are differenced within seed, pairs carrying any invariant flag are excluded, and the summary reports paired means and two-sided 95% paired-*t* intervals across valid seeds. These per-endpoint intervals are marginal and unadjusted for multiplicity. The JSON header records seed derivation, exclusion, interval, and multiplicity rules. This identifies only the specified model intervention under the pseudorandom seeded initial-world distribution. It does not convert the reduced equations into a calibrated biological causal model.

Invariant enforcement is a sequence of GPU reductions:

1. `clearInvariantScratch` zeros current audit reductions.
2. `auditContactMomentum` sums the unresolved fixed-point pair impulses before application.
3. `accumulateSimulationInvariants` independently recounts living program references and validates owners, component roots, membrane polygons, and persistent junction endpoints/fingerprints/age.
4. `finalizeSimulationInvariants` compares every program slot with the independent recount and evaluates contact-momentum and energy-residual tolerances.

The persistent 20-channel audit stores a bit set, exact first failure step, audit count, per-class violation counts, maximum contact residual, maximum energy residual, and current cell/program/junction statistics. Strict experiments terminate nonzero at the next command-buffer synchronization after a flag is set. The first failing simulation step remains exact even when multiple steps are batched.

## Science Layers

Zoom is one continuous camera transform over one coupled system, ordered from cause to consequence:

1. **Spinor lattice** separates both complex components and their phasors at lattice resolution.
2. **Quantum wave** resolves probability, phase, current, nodes, and matter-induced potential.
3. **Molecular reaction field** shows catalyst becoming stored energy, membrane, and heritable metabolism.
4. **Cellular tissue** resolves persistent cell boundaries, ATP, voltage, Ca*/ERK* fronts, refractory state, oscillator phase, strain, nuclei, contact junctions, cycle state, differentiation, stress, and apoptosis.
5. **Organism morphology** resolves inherited traits as constrained by cellular power, mechanochemical signaling, phase coherence, contractility, viability, and tissue geometry.
6. **Ecology** shows descendants competing across resources, hazards, obstacles, trophic interactions, and a shared vibration field.

The same full-screen camera renders every level; there is no duplicated canvas. The field evolves through a two-dimensional unitary quantum walk. Matter changes its coin angle and phase potential, while spinor probability and component coherence drive catalyst production in the substrate. This bidirectional loop is the causal bridge between scales.

## GPU Frame

Each active frame performs:

1. `reactWorld` samples the spinor and previous mechanical field, settles the previous cellular substrate claims and detrital returns, republishes fixed-point resource reservoirs, and evolves catalyst, stored energy, membranes, inherited fields, and substrate ecology.
2. `nucleateAutogenicFounder` atomically promotes one viable local maximum into the first persistent organism.
3. `evolveAgents` integrates translation and rotation from the previous cellular force/torque aggregate and removes identity only after tissue loss.
4. `evolveOrganismCells` atomically claims local A/B/detritus, closes ATP/work/heat/detritus accounting, advances voltage, inherited Ca*/ERK* signaling, refractory dynamics, resonance, sparse graph state, phenotype, fate, and traction over 9,216 slots.
5. `evolveCellMembranes` advances 110,592 membrane vertices, including regulatory construction forces for predatory, armor, sensory, and locomotor structures, and records polygon geometry and local integrity.
6. `clearCellSpatialHash` and `buildCellSpatialHash` construct a 16,384-bucket broad phase and dynamic per-owner cell lists entirely in private GPU memory.
7. `resolveMembraneContacts` computes actual membrane-support gaps, persistent same-owner junction forces, equal-and-opposite pair impulses, specialized attack, local defense, breach state, and trophic transfer; `applyCellContactEffects` applies the accumulated fixed-point effects to centers and the exact contacted vertices.
8. `measureCellMembraneExposure` classifies each physical membrane edge by point-in-polygon tests against nearby same-owner cells and writes exposed length, outward normal, detachment state, and per-edge render markers.
9. `initializeCellComponents`, `unionCellComponents`, and `compressCellComponents` label membrane-connected cells with atomic union-find, including strictly compatible cross-owner fusion. `buildCellComponentLists` constructs root-indexed segments; `accumulateCellComponents` measures count, centroid, ATP, integrity, and detachment readiness.
10. `selectPrimaryCellComponents` preserves continuity for the largest same-owner component, while permanent-cell ordering resolves cross-owner fusion ownership. `assignCellComponentOwners` traverses each root segment, records fusion transitions or validates separation, claims and mutates one recyclable descendant slot per transmitted program, and allocates permanent organism identity; `reassignCellComponents` retains each descendant reference before releasing its source while transforming the cell into the new component frame.
11. Owner traversal lists are rebuilt after reassignment, then `divideAndReduceOrganismCells` claims global free cells for division and emits actual exposed-edge geometry, force, torque, contact, trophic, signaling, and energetic aggregates. The spatial contact hash remains valid only for the pre-fission contact phase and is rebuilt on the next simulation step.
12. `evolveMechanicalField` consumes and clears contraction impulses, advances displacement and velocity, and swaps the mechanical texture pair.
13. At the configured scientific-audit cadence, GPU reductions validate contact momentum, energy closure, program references, junctions, membranes, live roots, and the one-connectivity-root-per-owner condition before publishing a compact persistent failure state.
14. `evolveQuantumField` advances the spinor under feedback from matter.
15. A scale-specialized full-screen pipeline renders quantum, molecular, cellular, organismal, or ecological observables without duplicating state.
16. `compactVisibleCells` rejects dead and scale-invisible cell records, writes compacted source indices, and atomically writes an indirect instance count entirely on the GPU.
17. One contour renderer submits only compacted living membranes from ecological overview through cell scale. It exposes actual edge classification, traction, constructed protrusions and armor, contact damage, and trophic flux; there is no predefined organism submission.
18. Triple-buffered observations publish stable organism positions, membrane-derived morphology, dynamics, energy-conservation channels, birth/death transitions, and cross-owner physical-fusion transitions without stalling private state.

Periodic asynchronous reductions measure viability, activity, recovery, inherited variation, niche differentiation, trophic activity, quantum norm, cell count, division count, ATP, integrity, voltage, Ca*, ERK*, refractory state, mechanochemical edge effects, signaling cost, phase coherence, resonance, strain, membrane area, perimeter, shape index, junction force, exposed boundary, elongation, cell force, tissue torque, contact load, trophic gain/loss, detachment score, all eight inherited pathway gains, cellular substrate input, ATP harvest, ATP-plus-biomass storage change, active work, frequency work, heat export, detrital return, global conservation residual, actuator activity, graph size, lineage mutation distance, live program-slot count, mixed-program cell fraction, a 32-bit hashed lower bound on component program richness, mean ATP exchange, rejection load, reciprocal recognition compatibility, and net program contribution. A 384-thread gather writes only generation-valid active developmental and resonance records into the metric ring. These measurements inform the observer; they do not overwrite inherited programs or select a globally prescribed body.

Two-dimensional compute dispatches query each pipeline's `threadExecutionWidth` and allocate up to eight rows without exceeding `maxTotalThreadsPerThreadgroup`. One-dimensional agent and cell dispatches use execution-width-aligned groups up to 256 threads. Dispatch geometry therefore follows the compiled pipeline and device instead of embedding one assumed Metal GPU width. Per-owner cell links are reconstructed in ascending cell-slot order; floating-point tissue reductions therefore receive a stable operand order instead of inheriting nondeterministic atomic insertion order.

The hot `reactWorld` pass precomputes four periodic coordinates and composes its cardinal and diagonal neighborhoods without integer modulo. It reads a neighbor's three genome textures only after confirming nonzero biomass; for exactly zero biomass, every skipped occupancy, colonization, prey, and attack term is mathematically zero. At deep spinor scale, nearest-cell sampling preserves exact lattice state instead of interpolating adjacent amplitudes. These are equation-preserving execution changes. Cell-render compaction is observation-only and cannot modify occupancy or biological state.
