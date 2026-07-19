# Numi Automata Metal Architecture

## Product Contract

Numi Automata opens at spinor scale with a persistent `1024 x 1024` two-component complex field, one `193 x 193` chemical and geological substrate, and zero organisms. Spinor coherence must first produce catalyst, stored energy, and a closed membrane. A locally self-maintaining membrane can atomically claim slot zero as the first founder. Up to 384 later organisms live in independent GPU slots. Additional slots are claimed only by inherited reproduction or an explicit **Add colony** action; camera movement and rendering never create organisms.

The UI exposes observation rather than simulation configuration: pause, restart, add a founder, choose speed or diagnostic mode, navigate physical scale, and follow or browse organisms. Population, hunters, resources, turnover, events, and quantum norm are measured from live state.

## Persistent Organisms

Each `AgentState` stores:

- Stable slot identity and occupancy.
- World-space position and velocity.
- Three inherited four-component gene vectors.
- Energy, biomass, age, and generation.

`nucleateAutogenicFounder` accepts only a local maximum with enough biomass, stored energy, catalyst, and membrane. Its inherited phase and metabolic biases come from the local spinor and chemistry rather than a predefined founder genome. `evolveAgents` then uses resource gradients, mineral gradients, hazard avoidance, bounded turning, inertia, separation, prey pursuit, and threat avoidance. `spawnAgents` atomically claims a free slot, mutates the parent's genome, places the child beside the parent, and charges the parent an energy cost. No frame or lattice tile synthesizes an organism.

The visible body uses a common rendering scaffold so viewers can read individuals, but length, width, locomotion, lineage color, internal texture, defense rim, sensory point, and predatory jaw are inherited. This visual grammar is not a species registry.

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
3. **Cell chemistry** shows catalyst becoming stored energy, membrane, and heritable metabolism.
4. **Organism** resolves inherited morphology, energy, sensors, defense, genome core, and metabolic channels.
5. **World** shows descendants competing across resources, hazards, and obstacles.

The same full-screen camera renders every level; there is no duplicated canvas. The field evolves through a two-dimensional unitary quantum walk. Matter changes its coin angle and phase potential, while spinor probability and component coherence drive catalyst production in the substrate. This bidirectional loop is the causal bridge between scales.

## GPU Frame

Each active frame performs:

1. `reactWorld` samples the spinor and evolves catalyst, stored energy, membranes, inherited fields, and substrate ecology.
2. `nucleateAutogenicFounder` atomically promotes one viable local maximum into the first persistent organism.
3. `evolveAgents` updates persistent decisions, movement, feeding, danger, and conflict.
4. `spawnAgents` performs energy-gated inherited reproduction with mostly small and occasionally larger inherited variation.
5. `evolveQuantumField` advances the spinor under feedback from matter.
6. A scale-specialized full-screen pipeline renders either quantum/cell structure or the world field without duplicating state.
7. Instanced `agentVertex` and `agentFragment` render each occupied agent slot.
8. A ring-buffered blit publishes stable agent positions for camera following without stalling the GPU.

Periodic reduction kernels measure viability, activity, recovery, inherited variation, niche differentiation, trophic activity, and quantum norm. These measurements inform the observer; they do not overwrite genomes or select a globally prescribed body.
