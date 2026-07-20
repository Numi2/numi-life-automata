# Numi Automata Metal Architecture

## Product Contract

Numi Automata opens at spinor scale with a persistent `1024 x 1024` two-component complex field, one `193 x 193` chemical and geological substrate, zero organisms, and zero organism-owned cells. Spinor coherence must first produce catalyst, stored energy, and a closed membrane. A locally self-maintaining membrane can atomically claim slot zero as the first founder and initialize exactly one cell. Up to 384 later organisms live in independent GPU slots; each owns 24 stable cell slots and one inherited developmental genome. Additional organism and cell slots are claimed only by inherited reproduction, cell division, or an explicit **Add colony** action. Camera movement and rendering never create state.

The UI exposes observation rather than simulation configuration: pause, restart, add a founder, choose speed or diagnostic mode, navigate physical scale, and follow or browse organisms. Population, hunters, resources, turnover, events, and quantum norm are measured from live state.

## Persistent Organisms

Each `AgentState` stores:

- Stable slot identity and occupancy.
- World-space position and velocity.
- Three inherited four-component gene vectors.
- Last measured pursuit, attack-contact, and threat behavior.
- Energy, biomass, age, and generation.

`nucleateAutogenicFounder` accepts only a local maximum with enough biomass, stored energy, catalyst, and membrane. Its inherited phase and metabolic biases come from the local spinor and chemistry rather than a predefined founder genome. `evolveAgents` then uses resource gradients, mineral gradients, hazard avoidance, bounded turning, inertia, separation, prey pursuit, and threat avoidance. `spawnAgents` atomically claims a free slot, mutates the parent's genome, places the child beside the parent, and charges the parent an energy cost. No frame or lattice tile synthesizes an organism.

The visible body uses a common rendering scaffold so viewers can read individuals, but length, width, locomotion, lineage color, internal texture, defense rim, sensory point, and predatory jaw are inherited. Live cellular occupancy, tissue radius, ATP, integrity, and stress further alter body proportions and condition. This visual grammar is not a species registry.

## Persistent Cells

`CellState` is a 224-byte record containing organism-relative position and velocity plus thirteen state vectors:

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

The owner of cell slot `i` is `i / 24`. This fixed block layout removes allocator contention and gives each cell kernel a bounded 24-cell interaction neighborhood. `evolveOrganismCells` computes symmetric center-level exclusion and adhesion, contact exchange, voltage coupling, directed phase coupling, resonant strain sensing, contact-propagated mechanochemical signaling, ATP accounting, sparse graph dynamics, phenotype differentiation, cycle progression, motion, and death. `evolveCellMembranes` advances twelve explicit vertices per occupied cell from edge elasticity, discrete bending, area pressure, contraction, local integrity, polygon contact, and adhesion. `divideAndReduceOrganismCells` selects at most one completed-cycle parent per organism, initializes a daughter polygon, copies sixteen cell-local graph activities with asymmetric perturbations, and emits tissue measurements.

Each organism has a 64-byte developmental header, sixteen 32-byte node slots, and forty-eight 32-byte directed-edge slots. A node stores bias, response rate, sensor coupling, actuator coupling, sensor index, actuator mask, innovation ID, and activity. An edge stores weight, strain-dependent plasticity, endpoints, innovation ID, and activity. Eight inputs carry ATP, voltage, strain, contact density, morphogen polarity, local opportunity minus stress, resonant response, and membrane deformation plus junction force. Eight output channels control proliferation, adhesion, contraction, repair, permeability, secretion, apoptosis suppression, and motility.

Reproduction mutates numerical parameters and can duplicate or silence nodes and add, remove, or reconnect edges. Every new structural record receives a monotonic innovation ID. The header retains active counts, topology hash, cumulative and last branch mutation distance, and structural-mutation count. The graph capacity is bounded, but active dimensionality is no longer fixed at four nodes. Founders and offspring start from one cell, so inherited developmental rules produce tissue state rather than copying parent anatomy.

Each organism also carries eight inherited resonance parameters: natural frequency, damping ratio, input gain, response threshold, bandwidth, adaptation rate, phase delay, and directional preference. Cells integrate a damped second-order response to extracellular strain rate. Its signed thresholded amplitude enters voltage, Ca* gating, phase, and the regulatory graph. Frequency can adapt only within the inherited bandwidth; reproduction mutates the tuning parameters.

Ca* and ERK* are dimensionless active-state variables, not concentrations. Contact-weighted neighboring Ca*/ERK* produces junctional propagation. Mechanical resonance, local strain, and transmitted junction force gate Ca* entry; Ca* drives ERK*; ERK* drives evolved motility-dependent traction opposite its local gradient. A refractory state suppresses repeated Ca* entry and propagation. The active states and both edge contributions consume ATP. For every update, the kernel evaluates factual Ca*/ERK* results and a local result with the selected incoming edge set to zero while holding the pre-update state fixed. It retains mechanics-to-Ca* and Ca*-to-ERK* factual-minus-edge-zero differences, ERK*-traction magnitude, and signaling work. These values are model-internal direct terms, not estimates from trajectory covariance.

The reduction kernel emits a 192-byte `CellAggregate`: physiology, morphology, voltage and phase statistics, mechanics, energy terms, both four-channel actuator vectors, four original direct equation terms, resonance statistics, polygon geometry, mechanochemical state, and four mechanochemical causal/work terms. `evolveAgents` consumes the previous aggregate, while organism rendering consumes the current aggregate. This one-step delayed feedback avoids a global CPU synchronization point while preserving the causal sequence:

```text
substrate chemistry -> cell-local regulation/electrophysiology -> division and tissue mechanics -> organism survival and morphology
```

Each cell accumulates a signed fixed-point contraction impulse into a `193 x 193 x 2` private atomic buffer. `evolveMechanicalField` consumes and zeros the impulse with relaxed atomic exchange while advancing a damped vector wave over a ping-pong `RGBA16Float` texture pair. Displacement gradients feed cell strain; velocity contributes dissipation; strain changes voltage and reaction chemistry; vibration gradients alter organism steering. This is a closed feedback cycle, not a render-only effect.

The mechanics-to-voltage and mechanics-to-Ca* edges share one intervention gain in `SimulationUniforms`. The normal value is `1`; the ECG control sets it to `0` without stopping mechanics or resonance. The next metric reduction records the single-trajectory change in mean voltage, Ca*, ERK*, and dividing fraction. The UI also computes lagged Pearson correlations from historical metrics, but labels them observational because temporal covariance is not an intervention effect. The **Causal terms** renderer uses cyan for mechanics-to-Ca*, magenta for Ca*-to-ERK*, green for ERK*-traction, and orange for signaling ATP cost. The original mechanics-to-voltage, cycle-drive, contact-suppression, and repair terms remain available in organism state.

Cells produced by division receive perturbed oscillator phases, frequencies, graph activities, resonator state, and polygon state. Contact phase coupling depends separately on sender and receiver phenotype, so it is generally nonreciprocal; center-level mechanical force remains symmetric. Reproduction requires at least five developed cells, sufficient ATP and integrity, nonzero phase coherence, and bounded cellular power deficit. A child receives one newly initialized cell plus mutated developmental and resonance genomes instead of copying the parent's instantaneous tissue state.

## Permanent Genealogy

Agent slots are reusable storage, not biological identity. Every founder and offspring atomically acquires a monotonic `birthID`; inherited offspring store `parentBirthID`. Birth and death transitions append sequence-numbered 64-byte records to a 4,096-entry private GPU ring. Each record includes step, generation, genome and topology hashes, branch mutation distance, resonance frequency, energy, and a compact morphology descriptor.

Observation commands copy the event ring and its monotonic write counter into a triple-buffered shared ring. Swift reconstructs the parent-ID graph and computes path distance to the lowest common predecessor plus normalized morphology distance. A clade is reported only after combined genealogical, topology, and morphology separation persists for at least 1,200 steps. This observer analysis does not feed simulation state and is not called a species count because the asexual model has no reproductive-isolation criterion.

## Physical Scale

The finite backing textures can expand while the observed world remains continuous. `worldScale` records how much physical territory a normalized backing texture represents. Physical magnification is:

```text
observationZoom = cameraZoom / worldScale
```

When the backing world doubles, old ecology is copied into the central half, agent positions and velocity are halved, and `cameraZoom` and `worldScale` double together. Agent radius, speed, birth distance, separation, and hunting distance are divided by `worldScale`. This preserves identity, apparent size, spacing, and behavior before and after expansion.

The follow camera consumes ring-buffered GPU observations and tracks a permanent birth ID while translating it to the currently occupied storage slot for rendering. Slot reuse cannot transfer the camera to an unrelated organism. Previous, next, and horizontal trackpad navigation replace only the tracked birth ID.

## Environment

Persistent geology defines localized nutrient beds, mineral deposits, toxic vents, and rock obstacles, with large empty regions between them. Resources regenerate only near matching deposits. Rocks reduce permeability and block local opportunity; toxic vents continuously impose damage. Agents sense this same field when choosing movement.

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

1. `reactWorld` samples the spinor and the previous mechanical field, then evolves catalyst, stored energy, membranes, inherited fields, and substrate ecology.
2. `nucleateAutogenicFounder` atomically promotes one viable local maximum into the first persistent organism.
3. `evolveAgents` updates persistent decisions, movement, feeding, danger, and conflict.
4. `spawnAgents` performs energy-gated reproduction, mutates organism traits, sparse graph structure, and resonance tuning, allocates permanent identity, and initializes each offspring as one cell.
5. `evolveOrganismCells` advances ATP, voltage, Ca*/ERK* signaling, refractory dynamics, phase, resonance, sixteen-node cell-local graph state, phenotype, and fate over 9,216 fixed slots while accumulating contraction impulses.
6. `evolveCellMembranes` advances 110,592 membrane vertices and records polygon geometry and transmitted contact force.
7. `divideAndReduceOrganismCells` performs bounded cell division, initializes daughter graph and polygon state, and emits one aggregate per organism.
8. `evolveMechanicalField` consumes and clears contraction impulses, advances displacement and velocity, and swaps the mechanical texture pair.
9. `evolveQuantumField` advances the spinor under feedback from matter.
10. A scale-specialized full-screen pipeline renders quantum, molecular, cellular, organismal, or ecological observables without duplicating state.
11. `compactVisibleCells` rejects dead and scale-invisible cell slots, writes compacted source indices, and atomically writes an indirect instance count entirely on the GPU.
12. Cell rendering submits only compacted living twelve-triangle polygons. Below `14x`, its coarse fragment path preserves lineage, ATP, voltage, Ca*, ERK*, and causal encodings while omitting subpixel intracellular structure. Organism submission is omitted where its analytic visibility is zero.
13. Triple-buffered observations publish stable organism positions, morphology, dynamics, and exact lineage transitions without stalling private state.

Periodic asynchronous reductions measure viability, activity, recovery, inherited variation, niche differentiation, trophic activity, quantum norm, cell count, division count, ATP, membrane integrity, voltage, Ca*, ERK*, refractory state, mechanochemical edge effects, signaling cost, phase coherence, resonance, strain, membrane area, perimeter, shape index, junction force, energy terms, actuator activity, graph size, and lineage mutation distance. These measurements inform the observer; they do not overwrite genomes or select a globally prescribed body.

Two-dimensional compute dispatches query each pipeline's `threadExecutionWidth` and allocate up to eight rows without exceeding `maxTotalThreadsPerThreadgroup`. One-dimensional agent and cell dispatches use execution-width-aligned groups up to 256 threads. Dispatch geometry therefore follows the compiled pipeline and device instead of embedding one assumed Metal GPU width.

The hot `reactWorld` pass precomputes four periodic coordinates and composes its cardinal and diagonal neighborhoods without integer modulo. It reads a neighbor's three genome textures only after confirming nonzero biomass; for exactly zero biomass, every skipped occupancy, colonization, prey, and attack term is mathematically zero. At deep spinor scale, nearest-cell sampling preserves exact lattice state instead of interpolating adjacent amplitudes. These are equation-preserving execution changes. Cell-render compaction is observation-only and cannot modify occupancy or biological state.
