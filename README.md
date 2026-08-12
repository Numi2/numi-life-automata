# Numi Automata

Numi Automata is an Apple-native artificial-life world built with Swift, SwiftUI, and Metal 4. It runs one continuously evolving ecology. Story and Research are two views of the same GPU state; neither changes the mechanics.

The project is a dimensionless simulation, not a calibrated account of biological abiogenesis and not a quantum computer. Its 1024 x 1024 spinor field is a classical unitary quantum-walk model. Quantum state can bias activation barriers, pathway choice, and nucleation probability, but all matter and usable energy still enter audited physical and chemical ledgers.

## What exists in the world

- Eight dense conserved basis-material fields.
- Eight sparse molecule slots per tile and an immutable registry of up to 65,536 species.
- Molecular definitions with basis composition, free energy, diffusion, charge, polarity, stability, affinity, and catalytic behavior.
- Physical cells with twelve-vertex membranes, local damage, contact impulses, junctions, voltage, mechanochemical signals, and lifetime memory.
- Up to 4,096 live genome headers backed by a shared 16 MB arena of 65,536 immutable 256-byte pages.
- Mutable elevation, solid fraction, moisture, temperature, and flow.
- Persistent constructed material with stiffness, porosity, permeability, adhesion, conductivity, storage, erosion resistance, and retained mass.

Sparse-molecule overflow is conservative: the least-abundant packet is decomposed into its basis materials and free energy becomes heat. A molecule is never silently dropped.

## Origin and metabolism

`nucleateProtocells` scans local chemistry for closed autocatalytic conditions. A successful origin consumes exact local molecule and basis-material amounts, creates a physical membrane cell, initializes linked genome pages, and records the origin. Multiple independent origins can occur.

Add Life uses the same constructor. The difference is provenance: supplied matter and energy are entered as an external intervention before the protocell is built.

Cell metabolism is deterministic across an ordered GPU pipeline:

1. Every cell senses its tile and publishes at most four uptake and four output intents.
2. Each tile settles its finite chemistry in permanent-cell-ID order.
3. Templates compete for finite transcript and protein pools; only folded products become active.
4. Expressed enzymes run reversible, basis-balanced intracellular reactions against finite molecular stock.
5. Pumps, channels, and paid internal membranes establish electrochemical organization.
6. Cells receive the remaining settlement and update ATP, biomass, work, heat, damage, memory, membrane growth, and secretion.

No scalar fitness, ranking, archive, selected world, or observer output participates in settlement, survival, or reproduction.

## Genomes without a fixed graph ceiling

Genome pages encode regulation, reactions, transporters, receptors, material recipes, junction behavior, electrical dynamics, and plasticity. Offspring share unchanged page chains. Duplication, deletion, splitting, mutation, and recombination allocate only changed overlays. If the arena is full, the mutation is skipped and audited; reproduction is not killed.

Reaction pages use a basis-balanced grammar. Mutation may change kinetics, control, and declared energy coupling, but product composition is rebuilt from reactant composition and usable work cannot exceed the declared chemical or external source.

The older fixed gene vectors and 16-node/48-edge graph are not part of the causal runtime.

## Templates must become molecules

Genome pages do not directly command physiology. Every living cell has eight
finite transcript slots and sixteen finite protein slots. Templates compete for
those pools; transcription, translation, membrane pumping, folding assistance,
and damaged-protein removal request ATP work that is reserved before optional
cell activity. Products decay and are rebuilt, so inherited sequence alone is
not an active capability.

Folded proteins contribute continuous physical effects: catalysis, transport,
regulation, structural assembly, receptor binding, chaperoning, proteolysis,
and pump/channel balance. Promoter binding changes transcription rather than
writing directly into physiology. Expressed reaction proteins catalyze forward
and reverse flux using finite intracellular reactants, products, activation
barriers, and chemical free-energy differences. Downhill reactions can capture
bounded work and reject heat; uphill reactions consume ATP.

Expressed structural and transport proteins can build an internal membrane only
by consuming intracellular basis material. Its mass, permeability, selectivity,
and integrity alter molecular retention and electrochemical coupling without a
named organelle catalogue. Dividing cells physically partition molecules,
membrane material, proteins, and transcripts rather than recreating them from
genome values.

Sustained enclosure after membrane breach can retain a foreign immutable genome
page chain. The retained lineage receives no role label and no free-energy
allowance: it can persist, replicate, conflict, or export work only by running
its own balanced reactions on molecules present inside the host. Division
partitions the retained population, permitting vertical transmission and later
observer inference of an endosymbiotic relationship.

Founders carry duplicate reaction and regulation templates plus neutral pages.
Copy number affects expression, duplicate copies can diverge, and mutation can
delete, split, pseudogenize, locally invert, recombine, or recruit neutral
sequence. Multiple pages of the same kind contribute; there is no first-page
shortcut.

## Bodies and complete lives

The runtime has no juvenile, adult, reproductive-maturity, or senescence switch. Each cell carries only causal state:

- chronological age and replication burden;
- ATP, biomass, membrane integrity, stress, and local damage;
- proteostasis burden and paid repair allocation;
- voltage, signaling, regulatory activity, and lifetime memory;
- membrane thickness, stiffness, toughness, adhesion, permeability, conductivity, receptor density, and catalytic coating.

Development follows inherited page activation plus local chemistry, voltage, mechanics, and contact. Division, budding, mixed-lineage fusion, propagules, and multicellular fission occur only when local regulation and physical state produce them. Aging is accumulated damage and turnover cost. Regeneration is renewed growth and patterning after injury. Death returns matter through persistent corpse structure, molecules, basis material, and heat.

Story may describe a life stage or functional cell type only after behavior is observed. Those labels are interpretations, never causal state.

## Ecology without preset roles

Organisms do not receive predator, prey, parasite, builder, armor, sensor, or locomotor classes.

- Predation is inferred from directional membrane damage, breach, digestion, and measured uptake.
- Toxicity is ordinary receptor binding or reaction damage; resistance is receptor and reaction chemistry.
- Construction is paid deposition of material packets. Their physical properties may later function as trails, shelters, reefs, reservoirs, conductive paths, or shared catalytic surfaces.
- Structures persist after builders die, erode, store and release molecules, redirect flow, and transmit chemistry or voltage.
- Seeded floods, erosion, vents, fires, blooms, and seasonal external-energy changes transport or transform matter rather than deleting organisms.
- Adhesion, enclosure, junctions, and reciprocal matter and energy flow form a cross-lineage interaction graph.

A separated collective is recognized as a higher-level individual only after observer windows find sustained energetic autonomy, boundary maintenance, mechanochemical closure, endogenous predictability, and parent-organization resemblance. Recognition never changes the world.

## Observation and interface

The read-only `WorldObservation` exposes six grouped views:

- `ChemistryObservation`
- `PopulationObservation`
- `InteractionObservation`
- `IndividualityObservation`
- `OpenEndednessObservation`
- `RuntimeObservation`

Open-endedness is measured across increasing windows using persistent inherited novelty, functional and interaction diversity, program complexity, ecological turnover, lineage divergence, individuality change, and saturation. There is no composite fitness score.

Story uses plain language and a chronological sidebar. It requires persistent evidence before reporting ecological candidates, and it explicitly withholds causal claims until paired ablations exist. Research exposes Chemistry, Materials, Physiology, Signals, Interactions, and Lineages over the same live world.

Journal schema 19 adds persistent lineage biographies for development, injury, regeneration, physical separation, independence, reproduction, senescence, death, exact material release, and source-specific material reuse. Older journals remain files on disk, but obsolete world state is not replayed.

Cells carry an eight-basis `CellMaterialLedger`; ATP and biomass are fast caches reconciled to those conserved pools. Up to four paid internal membrane domains can grow, divide, fuse, leak, and decay from expressed molecular rules. Lifecycle names exist only in the observer: the solver contains causal age, replication, damage, turnover, chemistry, voltage, contacts, membrane state, and inherited regulation—not maturity, senescence, regeneration, germline, soma, or role flags.

## GPU architecture

Metal owns quantum evolution, chemistry, cells, contact, topology, observation reduction, and rendering. Swift schedules command buffers, owns presentation, reads bounded observation rings, and manages checkpoint recovery.

The shader source is divided into shared modules for the open-ecology ABI,
genome pages, molecular expression, contact/topology, and unified ecology, then
compiled into one Metal library. Causal state is private GPU memory. Permanent
cell IDs make chemistry settlement and ancestry stable across allocation order.
Active-cell and active-component lists avoid whole-pool work where possible.

Audits cover quantum norm, eight basis materials, external matter and energy, chemical free energy, ATP work, heat, momentum, sparse overflow, tile overflow, skipped genome mutation, and protocell origins. Recovery checkpoints preserve causal buffers and observer history separately.

See [Docs/AUTOGENESIS_ARCHITECTURE.md](Docs/AUTOGENESIS_ARCHITECTURE.md) for dispatch and ownership details.

## Build and install

Requirements: an Apple Silicon Mac with macOS 26, Xcode command-line tools, Swift 6.2, and Metal 4 tooling.

```sh
./Scripts/build-metal4-assets.sh
swift build -c release --product NumiAutomata --jobs 4
./Scripts/install-macos-app.sh
```

The installer builds Metal assets and the release executable, signs the app locally, installs it at `~/Applications/Numi Automata.app`, and registers it with Launch Services. Pass `--no-open` to install without launching.

For a bounded deterministic command-line run:

```sh
swift run NumiAutomata experiment \
  --steps 2000 \
  --seed 1 \
  --sample-every 100 \
  --audit-every 100 \
  --external-energy-flux 1 \
  --output /tmp/numi-automata-smoke.jsonl
```

Long multi-seed evolutionary and performance studies should run on a suitably cooled Apple Silicon desktop. The MacBook release gate is compilation, conservation and observer unit tests, a smoke simulation capped at 2,000 steps or 30 seconds, release signing, installation, and nonvisual bundle verification.

## Evidence boundaries

A successful build proves compilation. A launched app proves startup. Short runs can verify deterministic dispatch, ABI checks, conservation plumbing, and checkpoint operation. Claims about long-term novelty, complete life histories, ecological succession, chemical arms races, or collective heredity require the longer paired and multi-seed protocols; the interface does not promote short-run correlations into those claims.
