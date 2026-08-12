# Unified Runtime Architecture

Numi Automata has one causal world. Story and Research consume the same observation stream and never select different mechanics.

## Authority

Metal owns all causal simulation state:

- unitary quantum field and matter feedback;
- dense basis material and sparse molecules;
- physical cells, membrane vertices, junctions, contact, damage, and topology;
- immutable genome headers and pages;
- environment, constructed material, and disturbances;
- conservation and invariant counters.

Swift owns scheduling, controls, read-only observation, journaling, checkpoint coordination, and rendering presentation. Observer values are never rebound to a simulation kernel.

## Causal memory

The 1024 x 1024 quantum field remains unitary apart from explicitly audited coupling. World chemistry uses two RGBA textures for eight dense basis materials and eight `MoleculePacket` records per tile. `SpeciesDefinition` records are immutable after publication.

Physical organisms occupy a shared pool of 9,216 cells. Every cell has a permanent ID independent of storage slot, a parent-cell ID, a component owner, a union-find root, twelve membrane vertices, physiology, signaling, memory, life-history burdens, and membrane physical and chemical properties. Each cell also owns eight finite transcript slots and sixteen finite protein slots; the pools are checkpointed causal state.

Up to 4,096 `GenomeHeader` records point into a 65,536-page arena. A `GenomePage` is 256 bytes and names its type, next page, innovation/module ID, and generation. Headers and pages are copy-on-write: unchanged ancestry is shared, while mutation publishes immutable overlays. Arena exhaustion increments `skippedGenomeMutationCount` and leaves reproduction viable with the inherited chain.

Constructed tiles store stiffness, porosity, permeability, adhesion, conductivity, storage, erosion resistance, and retained mass. Environment tiles store elevation, solid fraction, moisture, temperature, and flow.

## Chemistry and origin

Quantum amplitudes alter activation barriers and pathway probability. They do not mint matter or free energy. External forcing is recorded in `ChemistryAuditState`.

Each chemistry update:

1. transports eight basis fields and sparse molecule packets;
2. applies stability, diffusion, reactions, environmental work, and heat;
3. decomposes sparse overflow into exact basis composition plus heat;
4. evolves terrain, flow, and persistent constructed properties;
5. searches for chemically closed autocatalytic origin sites.

`nucleateProtocells` and `injectProtocell` both call the same physical constructor. Natural origin debits local chemistry. Intervention first credits explicit external matter and energy, then performs the same debit and construction. Both initialize a membrane cell and linked genome pages; neither creates a pixel organism.

## Deterministic metabolism

Metabolism and expression have four phases:

1. `publishCellChemistryIntents` emits four requested uptakes and four outputs per living cell.
2. `buildTileCellLists` groups cells by tile, and `settleTileChemistry` processes each tile in permanent-ID order against finite molecule packets.
3. `evolveMolecularExpression` transcribes finite templates, translates and folds proteins, resolves binding competition, turns over damage, and updates paid membrane gradients.
4. `evolveOrganismCells` consumes only the settled chemistry and folded molecular capabilities, then pays ATP, work, repair, growth, signaling, secretion, and heat.

This removes order-dependent chemical claims. Delayed material and energy ledgers remain explicit so production and recycling can be audited at the next chemistry step.

## Genome expression

Page types are regulation, reactions, transporters, receptors, material recipes, junctions, electrical dynamics, plasticity, and noncoding sequence. Expression traverses linked pages with a bounded corruption guard, not a biological graph-size ceiling. Multiple matching pages contribute with bounded copy-number dosage; the first matching page has no privileged causal shortcut.

Mutation can duplicate, delete, split, pseudogenize, locally invert, overlay, and recombine page chains. Reaction overlays are normalized after mutation: product basis composition equals reactant composition, and requested work is capped by the declared source. Lifetime memory and learned weights live in cells, not genome pages.

Genome pages do not directly actuate physiology. Eight transcript slots and sixteen protein slots impose finite expression competition. Protein concentration, folding, damage, binding competition, localization, chaperoning, and proteolysis gate catalysis, transport, regulation, structure, receptor activity, and pump/channel balance. Expression work is reserved before discretionary ATP use.

## Cells, bodies, and life histories

Cells integrate local settled chemistry, ATP, biomass, membrane integrity, damage, proteostasis, age, replication burden, voltage, contacts, morphogens, mechanics, and memory. Regulation produces continuous replication, maintenance, signaling, construction, adhesion, contraction, repair, permeability, secretion, apoptosis suppression, and motility activity.

There is no stage gate. A cell divides only when its local cycle, biomass, ATP, integrity, stress, and regulation physically permit it. Fission follows loss of membrane connectivity. Fusion follows direct support contact, receptor-ligand compatibility, membrane chemistry, adhesion, integrity, and paid junction formation. Mixed-lineage cells retain their own genome headers.

Damage accumulates locally. Paid maintenance lowers damage and proteostasis burden; inadequate repair increases turnover and death. Injury can reopen growth and pattern activity. Cell death leaves persistent structure and returns conserved material and free energy through molecule, basis, and heat channels.

Membrane construction has no named role. The causal vectors are:

- thickness, stiffness, toughness, adhesion;
- permeability, conductivity, receptor density, catalytic coating.

Directional expression of those values can deform membranes or change contact, uptake, signaling, and chemistry. Any later description as defense, sensing, movement, hunting, or another function is observer inference.

## Contact, topology, and ecology

A spatial grid identifies membrane support pairs. Canonical pair processing applies equal-and-opposite impulses, vertex damage, breach, finite matter transfer, junction renewal, ligand-receptor binding, and connectivity candidates. Union-find rebuilds membrane-connected components and assigns owners deterministically from permanent IDs.

Material packets alter tile mechanics and transport and remain after builders die. Molecules bind and react without toxin labels. Trophic relationships are measured from breach and matter/energy flow. Cross-lineage graphs are assembled from adhesion, enclosures, junctions, and reciprocal exchange.

Seeded disturbances modify environment and chemistry conservatively:

- floods move water, molecules, and loose material;
- erosion moves solid and constructed matter;
- vents add audited external matter and energy;
- fires transform chemical free energy into reaction products and heat;
- blooms arise from transport and reaction conditions;
- seasonal forcing changes external energy input.

## Observation

GPU reductions are copied through bounded readback rings into `WorldObservation`. Its grouped projections are chemistry, population, interactions, individuality, open-endedness, and runtime.

The individuality observer tests candidate partitions over autocorrelation-adjusted windows. A collective reproduction event requires a physically separated descendant plus sustained energy capture, boundary repair, mechanochemical closure, endogenous predictability, and parent-organization resemblance.

Story evidence is conservative. Construction, reciprocal exchange, chemical conflict, and repair must persist across at least three observation windows. Correlation is called a candidate. Causal language requires a paired intervention and sham/control result. Research exposes raw channels and uncertainty.

The open-endedness observer tracks several dimensions across short, medium, and long windows. It can warn about saturation; it cannot terminate a run, rank worlds, choose parents, or modify the simulation.

## Dispatch outline

One biological step is scheduled on a single ordered Metal command-buffer timeline:

1. quantum evolution and normalization audit;
2. basis/molecule/environment evolution;
3. physical protocell nucleation when chemistry permits;
4. cell intent publication, tile-list construction, and deterministic settlement;
5. finite transcription, translation, folding, molecular competition, and electrochemical pumping;
6. protein-gated cell physiology, learning, membrane chemistry, and death;
7. membrane vertex dynamics and contact-pair resolution;
8. junction maintenance, union-find, fission/fusion, and division;
9. constructed-material and delayed-ledger publication;
10. active compaction, observer reductions, and rendering.

Checkpoint copies happen at a committed step boundary. Recovery restores causal buffers and deterministic counters; observer history is rolled back to the same committed step.

## Verification tiers

MacBook release checks are intentionally bounded:

- Swift and Metal compilation;
- ABI preconditions and conservation unit tests;
- deterministic smoke execution capped at 2,000 steps or 30 seconds;
- release asset build, signing, install, launch, and Story/Research inspection.

Long multi-seed runs belong on a desktop Apple Silicon system. They are required for claims about quantum/mass/free-energy closure over time, spontaneous origin frequency, complete life histories, paired ecological ablations, collective heredity, exact replay, memory stability, and performance regression. A regression above 15 percent requires a Metal trace and written justification.
