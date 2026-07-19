# Numi Automata Metal Architecture

## Product Contract

Numi Automata opens at spinor scale with a persistent `1024 x 1024` two-component complex field, one `193 x 193` chemical and geological substrate, zero organisms, and zero organism-owned cells. Spinor coherence must first produce catalyst, stored energy, and a closed membrane. A locally self-maintaining membrane can atomically claim slot zero as the first founder and initialize its seven-cell tissue. Up to 384 later organisms live in independent GPU slots; each owns 24 stable cell slots. Additional organism and cell slots are claimed only by inherited reproduction, cell division, or an explicit **Add colony** action. Camera movement and rendering never create state.

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

`CellState` is an 80-byte record containing organism-relative position and velocity plus four state vectors:

- Physiology: ATP, biomass, cell-cycle phase, membrane integrity.
- Phenotype: adhesion, contractility, resource-A uptake, resource-B uptake.
- Signals: central morphogen, peripheral morphogen, stress, apoptosis activation.
- Interaction: nearest-contact direction, metabolite-exchange magnitude, contact conflict.

The owner of cell slot `i` is `i / 24`. This fixed block layout removes allocator contention and gives each cell kernel a bounded 24-cell interaction neighborhood. `evolveOrganismCells` computes pairwise exclusion, adhesion, contact exchange, crowding, uptake, maintenance, stress, membrane damage and repair, morphogen relaxation, phenotype differentiation, cycle progression, motion, and death. `divideAndReduceOrganismCells` selects at most one completed-cycle parent per organism and initializes a daughter only when energy and capacity permit. Capacity-saturated cells decay to a quiescent cycle range.

The second kernel reduces each tissue into a 32-byte `CellAggregate`: active count, mean ATP, mean membrane integrity, mean stress, centroid, RMS radius, and dividing fraction. `evolveAgents` consumes the previous aggregate, while the organism vertex stage consumes the current aggregate. This one-step delayed feedback avoids a global CPU synchronization point while preserving the causal sequence:

```text
substrate chemistry -> cell physiology -> tissue aggregate -> organism survival and morphology
```

## Physical Scale

The finite backing textures can expand while the observed world remains continuous. `worldScale` records how much physical territory a normalized backing texture represents. Physical magnification is:

```text
observationZoom = cameraZoom / worldScale
```

When the backing world doubles, old ecology is copied into the central half, agent positions and velocity are halved, and `cameraZoom` and `worldScale` double together. Agent radius, speed, birth distance, separation, and hunting distance are divided by `worldScale`. This preserves identity, apparent size, spacing, and behavior before and after expansion.

The follow camera consumes ring-buffered GPU observations and tracks one stable slot. At organism scale and deeper, non-selected organisms are hidden by the observer renderer so nearby bodies cannot visually merge with the subject. Their simulation continues unchanged. Previous, next, and horizontal trackpad navigation replace only the tracked ID.

## Environment

Persistent geology defines localized nutrient beds, mineral deposits, toxic vents, and rock obstacles, with large empty regions between them. Resources regenerate only near matching deposits. Rocks reduce permeability and block local opportunity; toxic vents continuously impose damage. Agents sense this same field when choosing movement.

## Science Layers

Zoom is one continuous camera transform over one coupled system, ordered from cause to consequence:

1. **Spinor lattice** separates both complex components and their phasors at lattice resolution.
2. **Quantum wave** resolves probability, phase, current, nodes, and matter-induced potential.
3. **Molecular reaction field** shows catalyst becoming stored energy, membrane, and heritable metabolism.
4. **Cellular tissue** resolves persistent cell boundaries, ATP, nuclei, contact junctions, cycle state, differentiation, stress, and apoptosis.
5. **Organism morphology** resolves inherited traits as constrained by cellular viability and tissue geometry.
6. **Ecology** shows descendants competing across resources, hazards, obstacles, and trophic interactions.

The same full-screen camera renders every level; there is no duplicated canvas. The field evolves through a two-dimensional unitary quantum walk. Matter changes its coin angle and phase potential, while spinor probability and component coherence drive catalyst production in the substrate. This bidirectional loop is the causal bridge between scales.

## GPU Frame

Each active frame performs:

1. `reactWorld` samples the spinor and evolves catalyst, stored energy, membranes, inherited fields, and substrate ecology.
2. `nucleateAutogenicFounder` atomically promotes one viable local maximum into the first persistent organism.
3. `evolveAgents` updates persistent decisions, movement, feeding, danger, and conflict.
4. `spawnAgents` performs energy-gated inherited reproduction and initializes each offspring's seven-cell tissue.
5. `evolveOrganismCells` advances mechanics, metabolism, regulatory signals, phenotype, and cell fate over 9,216 fixed slots.
6. `divideAndReduceOrganismCells` performs bounded cell division and emits one aggregate per organism.
7. `evolveQuantumField` advances the spinor under feedback from matter.
8. A scale-specialized full-screen pipeline renders quantum, molecular, cellular, or ecological fields without duplicating state.
9. Instanced organism and cell passes render 384 organism slots and 9,216 cell slots with occupancy rejection.
10. Triple-buffered compact observations publish stable organism positions for camera following without stalling the GPU.

Periodic asynchronous reductions measure viability, activity, recovery, inherited variation, niche differentiation, trophic activity, quantum norm, cell count, division count, ATP, membrane integrity, and cellular stress. These measurements inform the observer; they do not overwrite genomes or select a globally prescribed body.
