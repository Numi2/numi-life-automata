#include <metal_stdlib>
using namespace metal;

struct SimulationUniforms {
    uint width;
    uint height;
    uint worldCount;
    uint step;
    float dt;
    float resourceFlux;
    float mutationScale;
    float transportScale;
    uint displayMode;
    uint trackedAgentID;
    uint generation;
    uint epochSteps;
    uint damageStep;
    uint seed;
    float2 brushPosition;
    float brushRadius;
    float brushStrength;
    float2 cameraCenter;
    float cameraZoom;
    float worldScale;
    float viewportAspect;
    float4 intervention;
};

struct PostProcessUniforms {
    float2 sourceSize;
    float exposure;
    float bloomIntensity;
    float observationZoom;
    uint frameIndex;
};

constant uint metricCount = 46;
constant float metricScale = 4096.0;
constant uint quantumGridSize = 1024u;
constant uint maxCellCount = 9216u;
constant uint maxAgentCount = maxCellCount;
constant uint maxHeritableProgramCount = 4096u;
constant uint maxProgramsPerPropagule = 16u;
constant uint mixedComponentOwner = maxAgentCount + 1u;
constant float referenceTissueCellCount = 24.0;
constant uint regulatoryNodeCapacity = 16u;
constant uint regulatoryEdgeCapacity = 48u;
constant uint membraneVertexCount = 12u;
constant uint membraneRenderSubdivision = 4u;
constant uint membraneRenderSegmentCount = membraneVertexCount * membraneRenderSubdivision;
constant uint lineageEventCapacity = 4096u;
constant uint cellSpatialHashBucketCount = 16384u;
constant uint cellSpatialHashAxisResolution = 128u;
constant uint membraneContactPairCapacity = 524288u;
constant uint componentTopologyReconciliationStride = 256u;
constant uint cellJunctionCapacity = 32768u;
constant uint cellJunctionMask = cellJunctionCapacity - 1u;
// Substrate/energy exchange occupies channels 0...7. Channels 8...13 carry
// cell-produced developmental matter into the next extracellular-field step:
// ligand A, ligand B, matrix deposition, wound/remodeling cue, catalyst
// secretion, and toxin neutralization.
constant uint worldExchangeChannelCount = 14u;
constant uint componentMulticellularFlag = 1u << 0u;
constant uint componentRegeneratedFlag = 1u << 1u;
constant uint componentHomeostaticFlag = 1u << 2u;
constant uint componentChallengedFlag = 1u << 3u;
constant uint componentQualificationTargetFlag = 1u << 4u;
constant uint reservedCellJunctionEntry = 0u;
constant uint emptySpatialHashEntry = 0xffffffffu;
constant int mechanicalForceScale = 1048576;
constant int cellContactForceScale = 268435456;
constant int cellContactScalarScale = 1048576;
constant uint substrateFixedScale = 268435456u;
constant int energyAuditScale = 1048576;
constant uint invariantStateCount = 20u;
constant uint invariantScratchHeaderCount = 16u;
constant uint invariantOwnerRootOffset = invariantScratchHeaderCount + maxHeritableProgramCount;
constant uint invariantScratchCount = invariantOwnerRootOffset + maxAgentCount;
constant uint invariantContactMomentum = 1u << 0u;
constant uint invariantEnergyDrift = 1u << 1u;
constant uint invariantStaleProgram = 1u << 2u;
constant uint invariantReferenceCount = 1u << 3u;
constant uint invariantOrphanedJunction = 1u << 4u;
constant uint invariantInvalidMembrane = 1u << 5u;
constant uint invariantDisconnectedOwnership = 1u << 6u;
constant uint invariantContactPairOverflow = 1u << 7u;
struct AgentState {
    float2 position;
    float2 velocity;
    float4 behavior;
    float4 geneA;
    float4 geneB;
    float4 geneC;
    // Ligand coordinates followed by receptor coordinates.
    float4 recognition;
    // Fusion investment, ATP sharing, incompatible-cell rejection, propagule transmission.
    float4 social;
    float energy;
    float biomass;
    float age;
    uint generation;
    uint birthID;
    uint parentBirthID;
    uint genomeHash;
    uint birthStep;
    float mutationDistance;
    float lastMutationDistance;
    uint lineageFlags;
    uint dominantProgramIndex;
    uint dominantProgramGeneration;
    uint componentPersistenceSteps;
    uint programReplicationGeneration;
    uint componentFlags;
    // Tissue orientation, angular velocity, contact load, and damage-recovery observation window.
    float4 tissueKinematics;
};

struct CellState {
    float2 position;
    float2 velocity;
    // ATP, biomass, cell-cycle phase, membrane integrity.
    float4 physiology;
    // Adhesion, contractility, resource-A uptake, resource-B uptake.
    float4 phenotype;
    // Morphogen A, morphogen B, stress, apoptosis activation.
    float4 signals;
    // Nearest-contact direction, contact-cycle brake, mechanics-to-voltage contribution.
    float4 interaction;
    // Membrane voltage, recovery variable, oscillator phase [0, 1), natural frequency cycles/step.
    float4 dynamics;
    // Contractile activation, extracellular strain, wave speed, local phase coherence.
    float4 mechanics;
    // Harvested energy, maintenance, active mechanical/electrical work, dissipation.
    float4 energetics;
    // Proliferation, adhesive-core, contractile-edge, and repair regulatory activities.
    float4 regulation;
    // Permeability, secretion, apoptosis suppression, and motility regulatory activities.
    float4 regulationB;
    // Resonator displacement, velocity, response amplitude, and previous strain input.
    float4 resonance;
    // Polygon area, perimeter, shape index, and transmitted junction force.
    float4 membrane;
    // Calcium-like activity, ERK-like activity, refractory state, and neighbor signal input.
    float4 signaling;
    // One-step deltas: mechanics->Ca, Ca->ERK, ERK->traction, and signaling ATP cost.
    float4 signalCausality;
    // Vertex-derived outward normal, exposed perimeter fraction, and detachment score.
    float4 tissueGeometry;
    // Local traction/contact force, membrane contact damage, and signed trophic transfer.
    float4 tissueForce;
    // Substrate forcing, barrier load, environmental frequency, and frequency match.
    float4 environment;
    // Persistent tissue polarity, fate memory, and junction morphogen transport.
    float4 development;
};

struct CellIdentity {
    // Physical component ownership is independent of the inherited control program.
    uint owner;
    uint programIndex;
    uint persistentID;
    uint componentRoot;
    uint programGeneration;
    uint identityPadding0;
    uint identityPadding1;
    uint identityPadding2;
};

struct HeritableProgram {
    float4 geneA;
    float4 geneB;
    float4 geneC;
    float4 recognition;
    float4 social;
    uint genomeHash;
    uint parentGenomeHash;
    uint originBirthID;
    uint generation;
    // Exact immutable parent identity: generation-tagged recyclable slot handle.
    uint parentProgramIndex;
    uint parentProgramGeneration;
    // Crossbred programs retain the second immutable parent as well.
    uint secondParentGenomeHash;
    uint secondParentProgramIndex;
    uint secondParentProgramGeneration;
    uint ancestryFlags;
};

struct ProgramSlotState {
    // 0 is free, 2 is claimed for writing, and 1 is published.
    atomic_uint occupied;
    atomic_uint referenceCount;
    atomic_uint generation;
    uint lineageHash;
    // Q32 accumulated replication hazard. Unsigned overflow schedules one
    // mutation for the next successfully copied daughter program.
    atomic_uint mutationHazard;
    uint mutationHazardPadding0;
    uint mutationHazardPadding1;
    uint mutationHazardPadding2;
};

struct CellJunctionState {
    atomic_uint pairKey;
    atomic_uint lastSeenStep;
    uint persistentFingerprint;
    uint flags;
    float restDistance;
    float strength;
    float age;
    float load;
    // Normal stiffness, viscous damping, transport permeability, cortical tension.
    float4 material;
    // Target rest distance, strain memory, ATP investment, polarity alignment.
    float4 remodeling;
};

struct CellAggregate {
    // Active cell count, mean ATP, mean membrane integrity, mean stress.
    float4 physiology;
    // Mean biomass, mean cell-cycle state, root-mean-square radius, dividing-cell fraction.
    float4 morphology;
    // Mean voltage, phase coherence, mean frequency, circular mean phase.
    float4 dynamics;
    // Mean strain, mean contractility, mean wave speed, net cellular power.
    float4 mechanics;
    // Total harvest, maintenance, active work, and dissipation per step.
    float4 energetics;
    // Mean developmental regulatory activities across viable cells.
    float4 regulation;
    // Mean permeability, secretion, apoptosis-suppression, and motility activities.
    float4 regulationB;
    // Direct per-step terms: mechanics->voltage, cycle drive, contact brake, repair->integrity.
    float4 causality;
    // Mean resonator displacement, amplitude, inherited frequency, and damping ratio.
    float4 resonance;
    // Mean membrane area, perimeter, shape index, and junction force.
    float4 shape;
    // Mean calcium-like activity, ERK-like activity, refractory state, and neighbor signal input.
    float4 signaling;
    // Mean one-step mechanochemical causal terms and signaling ATP cost.
    float4 signalCausality;
    // Principal tissue axis and covariance-derived major/minor extents.
    float4 geometryAxes;
    // Vertex-derived polarity, elongation, and exposed membrane length.
    float4 geometryBoundary;
    // Net local cell force, torque, and mean force magnitude.
    float4 tissueMotion;
    // Contact load, acquired biomass, lost biomass, and maximum detachment score.
    float4 trophic;
    // Dominant-program fraction, non-dominant fraction, hashed richness lower bound, program index.
    float4 inheritance;
    // Mean absolute ATP exchange, rejection load, recognition compatibility, and net contribution.
    float4 programEcology;
    // Mean substrate forcing, barrier load, environmental frequency, and frequency match.
    float4 environment;
    // Mean morphogen A, morphogen B, fate memory, and junction transport.
    float4 development;
    // Morphogen differentiation, polarity coherence, synthesis, and transport work.
    float4 developmentCausality;
};

struct QualificationTargetMeasurement {
    // Owner slot, permanent birth ID, current cell count, and component flags.
    uint4 identity;
    // Extracellular ligand A/B, matrix density, and wound cue at the target centroid.
    float4 developmental;
};

struct DevelopmentalGenome {
    // Active nodes, active edges, topology hash, and cumulative structural mutations.
    uint4 topology;
    // Cumulative distance, last mutation distance, node rate, and edge rate.
    float4 mutation;
    // Basal drive for the eight stable actuator channels.
    float4 actuatorBiasA;
    float4 actuatorBiasB;
    // Mechanics->Ca gain, junction transmission, Ca->ERK gain, refractory recovery.
    float4 mechanochemistryA;
    // Signaling ATP cost, traction gain, detachment threshold, propagule investment.
    float4 mechanochemistryB;
    // Basal production A/B and first-order decay A/B.
    float4 morphogenKinetics;
    // Receptor sensitivity A/B and junction diffusivity A/B.
    float4 morphogenTransport;
    // Junction adhesion expression, cortical tension, viscous damping, permeability.
    float4 junctionMaterial;
    // Toxin tolerance, detrital scavenging, shear anchoring, starvation quiescence.
    float4 ecologicalResponse;
};

struct RegulatoryNode {
    float bias;
    float responseRate;
    float sensorWeight;
    float outputWeight;
    uint sensorIndex;
    uint actuatorMask;
    uint innovationID;
    uint flags;
};

struct RegulatoryEdge {
    float weight;
    float plasticity;
    float delay;
    float reserved;
    uint source;
    uint target;
    uint innovationID;
    uint flags;
};

struct ResonanceGenome {
    // Natural frequency, damping ratio, sensor gain, and response threshold.
    float4 mechanics;
    // Bandwidth, adaptation rate, phase delay, and directional preference.
    float4 tuning;
};

struct ProgramMetricRecord {
    DevelopmentalGenome developmental;
    ResonanceGenome resonance;
};

struct MembraneVertex {
    float2 position;
    float2 velocity;
    // Rest edge length, local integrity, contact pressure, and local strain.
    float4 mechanics;
};

struct MembraneSupportSample {
    float2 point;
    float integrity;
    uint vertexIndex;
};

struct AgentObservationRecord {
    float2 position;
    uint generation;
    uint flags;
    uint birthID;
    uint parentBirthID;
    uint genomeHash;
    uint topologyHash;
    float4 morphology;
    float4 dynamics;
    float mutationDistance;
    float3 padding;
    // Harvest/import, repair/integrity, damage/perimeter, and ATP closure terms.
    float4 energeticBoundary;
    // Exposed perimeter, damage, turnover demand, and membrane integrity.
    float4 boundary;
    // Measured strain->Ca, Ca->ERK, ERK->traction, and traction->strain terms.
    float4 mechanochemical;
    // ATP sharing, rejection, junction transmission, and program conflict.
    float4 social;
    // Substrate forcing, barrier load, environmental frequency, and frequency match.
    float4 environment;
};

struct CellObservationRecord {
    // World position, membrane perimeter, and exposed perimeter fraction.
    float4 geometry;
    // Persistent cell ID, component handle, component birth ID, program replication generation.
    uint4 identity;
    // Genome hash, parent genome hash, slot generation, and slot index.
    uint4 programLineage;
    // Exact current and parent program handles: index, generation, index, generation.
    uint4 programAncestry;
    // Inherited mechanochemical-loop trait, signaling cost, detachment, investment.
    float4 inheritedTraits;
    // Harvested ATP, imported ATP, repair flux, and membrane integrity.
    float4 energetic;
    // Exposed perimeter, damage, membrane turnover, and ATP state.
    float4 boundary;
    // Strain->Ca, Ca->ERK, ERK->traction, and traction->strain.
    float4 mechanochemical;
    // ATP sharing, rejection, junction transmission, and program conflict.
    float4 social;
    float4 environment;
};

struct LineageEventRecord {
    uint sequence;
    uint kind;
    uint birthID;
    uint parentBirthID;
    uint step;
    uint generation;
    uint genomeHash;
    uint topologyHash;
    float mutationDistance;
    float resonanceFrequency;
    float morphologyDistance;
    float energy;
    float4 morphology;
    uint4 programAncestry;
};

inline uint hash32(uint value) {
    value ^= value >> 16;
    value *= 0x7feb352du;
    value ^= value >> 15;
    value *= 0x846ca68bu;
    value ^= value >> 16;
    return value;
}

inline float random01(uint value) {
    return float(hash32(value)) / 4294967295.0;
}

inline float signedRandom(uint value) {
    return random01(value) * 2.0 - 1.0;
}

inline float4 crossoverFloat4(float4 primary, float4 secondary, uint seed) {
    return float4(
        random01(seed) < 0.5 ? primary.x : secondary.x,
        random01(seed + 1u) < 0.5 ? primary.y : secondary.y,
        random01(seed + 2u) < 0.5 ? primary.z : secondary.z,
        random01(seed + 3u) < 0.5 ? primary.w : secondary.w
    );
}

inline float cellularFluxAdequacy(float4 energetics) {
    float demand = energetics.y + energetics.z + energetics.w;
    return clamp(energetics.x / max(demand, 0.000001), 0.0, 1.5);
}

inline float cellularEnergySupport(float atp, float4 energetics) {
    float reserveSupport = smoothstep(0.12, 0.36, atp);
    float fluxSupport = smoothstep(0.62, 1.06, cellularFluxAdequacy(energetics));
    return saturate(reserveSupport * 0.58 + fluxSupport * 0.42);
}

inline float cellularRepairUrgency(
    float integrity,
    float stress,
    float woundCue,
    float contactDamage
) {
    // Repair is driven only by state available to the cell at its local boundary.
    // As integrity and stress recover, urgency falls continuously to zero.
    return saturate(
        max(1.0 - saturate(integrity), 0.0) * 1.34 +
        max(saturate(stress) - 0.10, 0.0) * 0.44 +
        saturate(woundCue) * 0.72 + saturate(contactDamage) * 0.48
    );
}

inline float repairAdjustedATPPotential(float atp, float repairUrgency) {
    // A damaged cell behaves like a lower chemical potential across a junction.
    // Pairwise differences remain antisymmetric, so support does not create ATP.
    return atp - saturate(repairUrgency) * 0.14;
}

inline float detachmentReadinessScore(
    float exposure,
    float isolation,
    float atp,
    float integrity,
    float adhesivePhenotype,
    float propaguleInvestment
) {
    // A geometric mean keeps the inherited threshold on the same 0...1 scale as
    // the four local physical and physiological readiness factors. Component-frame
    // position is deliberately absent: a cell can detach only through its measured
    // boundary, contacts, energy, integrity, and inherited adhesion program.
    float readinessProduct = saturate(exposure) * saturate(isolation) *
        saturate(atp) * saturate(integrity);
    float readiness = pow(max(readinessProduct, 0.0000001), 0.25);
    float adhesionRelease = mix(1.08, 0.72, saturate(adhesivePhenotype));
    float investmentGain = mix(
        0.72, 1.12, saturate(propaguleInvestment / 1.80)
    );
    return saturate(readiness * adhesionRelease * investmentGain);
}

inline float cellCycleDrive(
    float atp,
    float biomass,
    float4 energetics,
    float proliferationProgram,
    float stress,
    float membraneExposure
) {
    float energySupport = cellularEnergySupport(atp, energetics);
    float massCompetence = smoothstep(0.20, 0.46, biomass);
    float boundaryAccess = mix(0.24, 1.0, saturate(membraneExposure));
    return 0.00135 * energySupport * massCompetence * boundaryAccess *
        mix(0.12, 1.62, proliferationProgram) * (1.0 - saturate(stress));
}

inline float cellCycleQuiescenceDecay(
    float energySupport,
    float contactBrake,
    float stress
) {
    float starvation = 1.0 - smoothstep(0.10, 0.34, energySupport);
    float severeCrowding = smoothstep(0.72, 0.96, contactBrake);
    float damageArrest = smoothstep(0.62, 0.88, saturate(stress));
    return starvation * 0.000018 + severeCrowding * 0.000050 +
        damageArrest * 0.000030;
}

inline float4 randomSigned4(uint seed) {
    return float4(
        signedRandom(seed), signedRandom(seed + 1u),
        signedRandom(seed + 2u), signedRandom(seed + 3u)
    );
}

inline float conservativeDivisionDelta(float concentration, float proposedDelta) {
    float available = min(saturate(concentration), 1.0 - saturate(concentration));
    return clamp(proposedDelta, -available, available);
}

inline uint substrateToFixed(float value);
inline float substrateFromFixed(uint value);

inline DevelopmentalGenome emptyDevelopmentalGenome() {
    DevelopmentalGenome genome;
    genome.topology = uint4(0u);
    genome.mutation = float4(0.0, 0.0, 0.018, 0.032);
    genome.actuatorBiasA = float4(-0.20, -0.08, -0.16, -0.05);
    genome.actuatorBiasB = float4(-0.22, -0.28, -0.30, -0.18);
    genome.mechanochemistryA = float4(1.0, 1.0, 1.0, 1.0);
    genome.mechanochemistryB = float4(1.0, 1.0, 0.42, 1.0);
    genome.morphogenKinetics = float4(0.34, 0.30, 0.22, 0.20);
    genome.morphogenTransport = float4(1.0, 1.0, 0.42, 0.34);
    genome.junctionMaterial = float4(0.72, 0.42, 0.46, 0.52);
    genome.ecologicalResponse = float4(0.28, 0.24, 0.30, 0.36);
    return genome;
}

inline RegulatoryNode emptyRegulatoryNode() {
    RegulatoryNode node;
    node.bias = 0.0;
    node.responseRate = 0.02;
    node.sensorWeight = 0.0;
    node.outputWeight = 0.0;
    node.sensorIndex = 8u;
    node.actuatorMask = 0u;
    node.innovationID = 0u;
    node.flags = 0u;
    return node;
}

inline RegulatoryEdge emptyRegulatoryEdge() {
    RegulatoryEdge edge;
    edge.weight = 0.0;
    edge.plasticity = 0.0;
    edge.delay = 0.0;
    edge.reserved = 0.0;
    edge.source = 0u;
    edge.target = 0u;
    edge.innovationID = 0u;
    edge.flags = 0u;
    return edge;
}

inline ResonanceGenome emptyResonanceGenome() {
    ResonanceGenome genome;
    genome.mechanics = float4(0.0032, 0.24, 0.68, 0.004);
    genome.tuning = float4(0.0018, 0.0012, 0.0, 0.0);
    return genome;
}

inline HeritableProgram emptyHeritableProgram() {
    HeritableProgram program;
    program.geneA = float4(0.0);
    program.geneB = float4(0.0);
    program.geneC = float4(0.0);
    program.recognition = float4(0.0);
    program.social = float4(0.0);
    program.genomeHash = 0u;
    program.parentGenomeHash = 0u;
    program.originBirthID = 0u;
    program.generation = 0u;
    program.parentProgramIndex = maxHeritableProgramCount;
    program.parentProgramGeneration = 0u;
    program.secondParentGenomeHash = 0u;
    program.secondParentProgramIndex = maxHeritableProgramCount;
    program.secondParentProgramGeneration = 0u;
    program.ancestryFlags = 0u;
    return program;
}

inline AgentState agentWithHeritableProgram(
    AgentState agent,
    HeritableProgram program
) {
    agent.geneA = program.geneA;
    agent.geneB = program.geneB;
    agent.geneC = program.geneC;
    agent.recognition = program.recognition;
    agent.social = program.social;
    agent.genomeHash = program.genomeHash;
    return agent;
}

inline AgentState agentWithCellProgram(
    AgentState agent,
    uint programIndex,
    device const HeritableProgram* programs
) {
    if (programIndex < maxHeritableProgramCount &&
        programIndex != agent.dominantProgramIndex) {
        return agentWithHeritableProgram(agent, programs[programIndex]);
    }
    return agent;
}

inline HeritableProgram heritableProgramFromAgent(
    AgentState agent,
    uint parentGenomeHash,
    uint parentProgramIndex,
    uint parentProgramGeneration
) {
    HeritableProgram program;
    program.geneA = agent.geneA;
    program.geneB = agent.geneB;
    program.geneC = agent.geneC;
    program.recognition = agent.recognition;
    program.social = agent.social;
    program.genomeHash = agent.genomeHash;
    program.parentGenomeHash = parentGenomeHash;
    program.originBirthID = agent.birthID;
    program.generation = agent.programReplicationGeneration;
    program.parentProgramIndex = parentProgramIndex;
    program.parentProgramGeneration = parentProgramGeneration;
    program.secondParentGenomeHash = 0u;
    program.secondParentProgramIndex = maxHeritableProgramCount;
    program.secondParentProgramGeneration = 0u;
    program.ancestryFlags = 0u;
    return program;
}

inline float4 founderRecognition(AgentState agent, uint seed) {
    float2 ligand = fract(float2(
        agent.geneA.x * 0.61 + agent.geneB.w * 0.39 + random01(seed + 31u) * 0.16,
        agent.geneA.y * 0.47 + agent.geneC.y * 0.53 + random01(seed + 37u) * 0.16
    ));
    float2 receptor = clamp(
        ligand + float2(signedRandom(seed + 41u), signedRandom(seed + 43u)) * 0.055,
        0.0, 1.0
    );
    return float4(ligand, receptor);
}

inline float4 founderSocialControl(AgentState agent, uint seed) {
    return clamp(float4(
        0.24 + agent.geneA.y * 0.58 + signedRandom(seed + 47u) * 0.08,
        0.18 + agent.geneB.x * 0.54 + signedRandom(seed + 53u) * 0.08,
        0.12 + agent.geneA.w * 0.62 + signedRandom(seed + 59u) * 0.08,
        0.24 + agent.geneB.z * 0.58 + signedRandom(seed + 61u) * 0.08
    ), 0.0, 1.0);
}

inline float recognitionCompatibility(AgentState a, AgentState b) {
    float reciprocalMismatch = 0.5 * (
        length(a.recognition.xy - b.recognition.zw) +
        length(b.recognition.xy - a.recognition.zw)
    );
    return saturate(1.0 - reciprocalMismatch * 0.92);
}

inline ResonanceGenome founderResonanceGenome(AgentState agent, uint seed) {
    ResonanceGenome genome;
    float frequency = 0.0014 + agent.geneB.z * 0.0042 + random01(seed + 3u) * 0.0010;
    genome.mechanics = float4(
        clamp(frequency, 0.0008, 0.0090),
        clamp(0.12 + (1.0 - agent.geneA.z) * 0.30 + signedRandom(seed + 5u) * 0.04, 0.06, 0.62),
        clamp(0.42 + agent.geneA.z * 0.72 + signedRandom(seed + 7u) * 0.10, 0.12, 1.40),
        clamp(0.002 + random01(seed + 9u) * 0.018, 0.0, 0.08)
    );
    genome.tuning = float4(
        clamp(0.0010 + random01(seed + 11u) * 0.0032, 0.0004, 0.0060),
        clamp(0.0004 + random01(seed + 13u) * 0.0022, 0.0001, 0.0040),
        signedRandom(seed + 15u) * 0.22,
        signedRandom(seed + 17u)
    );
    return genome;
}

inline uint topologyHash(
    device const RegulatoryNode* nodes,
    device const RegulatoryEdge* edges,
    uint owner
) {
    uint value = 0x811c9dc5u;
    uint nodeBase = owner * regulatoryNodeCapacity;
    uint edgeBase = owner * regulatoryEdgeCapacity;
    for (uint index = 0u; index < regulatoryNodeCapacity; ++index) {
        RegulatoryNode node = nodes[nodeBase + index];
        if ((node.flags & 1u) == 0u) { continue; }
        value = hash32(value ^ node.innovationID ^ node.sensorIndex * 16777619u ^ node.actuatorMask);
    }
    for (uint index = 0u; index < regulatoryEdgeCapacity; ++index) {
        RegulatoryEdge edge = edges[edgeBase + index];
        if ((edge.flags & 1u) == 0u) { continue; }
        value = hash32(value ^ edge.innovationID ^ edge.source * 374761393u ^ edge.target * 668265263u);
    }
    return value;
}

inline uint agentGenomeHash(
    AgentState agent,
    uint regulatoryHash,
    ResonanceGenome resonance,
    DevelopmentalGenome development
) {
    uint value = regulatoryHash;
    value = hash32(value ^ as_type<uint>(agent.geneA.x) ^ as_type<uint>(agent.geneA.y));
    value = hash32(value ^ as_type<uint>(agent.geneB.z) ^ as_type<uint>(agent.geneC.w));
    value = hash32(value ^ as_type<uint>(agent.recognition.x) ^ as_type<uint>(agent.recognition.y));
    value = hash32(value ^ as_type<uint>(agent.recognition.z) ^ as_type<uint>(agent.recognition.w));
    value = hash32(value ^ as_type<uint>(agent.social.x) ^ as_type<uint>(agent.social.y));
    value = hash32(value ^ as_type<uint>(agent.social.z) ^ as_type<uint>(agent.social.w));
    value = hash32(value ^ as_type<uint>(resonance.mechanics.x) ^ as_type<uint>(resonance.mechanics.y));
    value = hash32(value ^ as_type<uint>(development.mechanochemistryA.x) ^
        as_type<uint>(development.mechanochemistryA.z));
    value = hash32(value ^ as_type<uint>(development.mechanochemistryB.y) ^
        as_type<uint>(development.mechanochemistryB.z));
    value = hash32(value ^ as_type<uint>(development.morphogenKinetics.x) ^
        as_type<uint>(development.morphogenKinetics.w));
    value = hash32(value ^ as_type<uint>(development.morphogenTransport.y) ^
        as_type<uint>(development.morphogenTransport.z));
    value = hash32(value ^ as_type<uint>(development.junctionMaterial.x) ^
        hash32(as_type<uint>(development.junctionMaterial.y)) ^
        hash32(as_type<uint>(development.junctionMaterial.z)) ^
        as_type<uint>(development.junctionMaterial.w));
    value = hash32(value ^ as_type<uint>(development.ecologicalResponse.x) ^
        hash32(as_type<uint>(development.ecologicalResponse.y)) ^
        hash32(as_type<uint>(development.ecologicalResponse.z)) ^
        as_type<uint>(development.ecologicalResponse.w));
    return value;
}

inline void initializeFounderRegulatoryGenome(
    device DevelopmentalGenome* genomes,
    device RegulatoryNode* nodes,
    device RegulatoryEdge* edges,
    device atomic_uint* identityCounters,
    uint programIndex,
    AgentState agent,
    uint seed
) {
    uint nodeBase = programIndex * regulatoryNodeCapacity;
    uint edgeBase = programIndex * regulatoryEdgeCapacity;
    for (uint index = 0u; index < regulatoryNodeCapacity; ++index) {
        nodes[nodeBase + index] = emptyRegulatoryNode();
    }
    for (uint index = 0u; index < regulatoryEdgeCapacity; ++index) {
        edges[edgeBase + index] = emptyRegulatoryEdge();
    }

    for (uint index = 0u; index < 12u; ++index) {
        RegulatoryNode node = emptyRegulatoryNode();
        node.bias = -0.42 + random01(seed + index * 17u) * 0.54;
        node.responseRate = clamp(0.012 + random01(seed + index * 19u + 1u) * 0.050, 0.004, 0.095);
        node.sensorWeight = 0.52 + random01(seed + index * 23u + 2u) * 0.92;
        if (index == 2u || index == 3u || index == 10u) { node.sensorWeight *= -0.72; }
        node.outputWeight = 0.72 + random01(seed + index * 29u + 3u) * 0.52;
        node.sensorIndex = index;
        node.actuatorMask = 1u << (index & 7u);
        if (index >= 8u) {
            node.actuatorMask = 1u << (hash32(seed + 37u * index) & 7u);
        }
        if (index == 0u) { node.actuatorMask |= 1u << 4u; }
        if (index == 2u) { node.actuatorMask |= 1u << 7u; }
        node.innovationID = atomic_fetch_add_explicit(&identityCounters[1], 1u, memory_order_relaxed);
        node.flags = 1u;
        nodes[nodeBase + index] = node;
    }

    for (uint index = 0u; index < 20u; ++index) {
        RegulatoryEdge edge = emptyRegulatoryEdge();
        edge.source = index % 12u;
        edge.target = (index * 5u + 1u) % 12u;
        edge.weight = signedRandom(seed + 101u + index * 7u) * 1.18;
        if (index < 4u) { edge.weight = 0.42 + random01(seed + 201u + index) * 0.72; }
        edge.plasticity = signedRandom(seed + 301u + index) * 0.025;
        edge.innovationID = atomic_fetch_add_explicit(&identityCounters[1], 1u, memory_order_relaxed);
        edge.flags = 1u;
        edges[edgeBase + index] = edge;
    }

    DevelopmentalGenome genome = emptyDevelopmentalGenome();
    genome.topology = uint4(12u, 20u, 0u, 0u);
    genome.mutation.z = 0.010 + agent.geneB.y * 0.26;
    genome.mutation.w = 0.016 + agent.geneB.y * 0.38;
    genome.actuatorBiasA += randomSigned4(seed + 401u) * 0.08;
    genome.actuatorBiasB += randomSigned4(seed + 405u) * 0.08;
    genome.mechanochemistryA = clamp(
        float4(
            0.74 + agent.geneA.z * 0.58,
            0.68 + agent.geneA.y * 0.64,
            0.72 + agent.geneA.x * 0.56,
            0.68 + agent.geneA.w * 0.66
        ) + randomSigned4(seed + 409u) * 0.10,
        float4(0.25), float4(2.25)
    );
    genome.mechanochemistryB = float4(
        clamp(0.72 + agent.geneB.x * 0.54 + signedRandom(seed + 413u) * 0.10, 0.30, 2.20),
        clamp(0.64 + agent.geneA.z * 0.82 + signedRandom(seed + 417u) * 0.12, 0.20, 2.50),
        clamp(0.24 + agent.geneA.y * 0.26 + signedRandom(seed + 421u) * 0.06, 0.18, 0.62),
        clamp(0.66 + agent.geneB.z * 0.62 + signedRandom(seed + 425u) * 0.10, 0.30, 1.80)
    );
    genome.morphogenKinetics = clamp(
        float4(
            0.22 + agent.geneA.y * 0.30,
            0.20 + agent.geneA.z * 0.30,
            0.12 + agent.geneB.x * 0.24,
            0.11 + agent.geneB.z * 0.24
        ) + randomSigned4(seed + 429u) * 0.045,
        float4(0.035), float4(0.85)
    );
    genome.morphogenTransport = clamp(
        float4(
            0.60 + agent.geneC.x * 0.75,
            0.60 + agent.geneC.y * 0.75,
            0.20 + agent.geneA.y * 0.55,
            0.16 + agent.geneA.z * 0.55
        ) + randomSigned4(seed + 433u) * 0.075,
        float4(0.05), float4(1.80)
    );
    genome.junctionMaterial = clamp(
        float4(
            0.38 + agent.geneA.y * 0.62,
            0.22 + agent.geneA.z * 0.56,
            0.20 + agent.geneB.x * 0.58,
            0.24 + agent.social.y * 0.62
        ) + randomSigned4(seed + 437u) * 0.08,
        float4(0.05), float4(1.40)
    );
    genome.ecologicalResponse = clamp(
        float4(
            0.12 + agent.geneA.w * 0.58,
            0.10 + agent.geneC.z * 0.64,
            0.10 + agent.geneA.z * 0.60,
            0.14 + agent.geneB.x * 0.58
        ) + randomSigned4(seed + 441u) * 0.08,
        float4(0.0), float4(1.0)
    );
    genomes[programIndex] = genome;
    genome.topology.z = topologyHash(nodes, edges, programIndex);
    genomes[programIndex] = genome;
}

inline float mutateScalar(float value, uint seed, float amount, float lower, float upper) {
    return clamp(value + signedRandom(seed) * amount, lower, upper);
}

inline uint activeRegulatoryNodeAtOrdinal(
    device const RegulatoryNode* nodes,
    uint base,
    uint ordinal
) {
    uint activeOrdinal = 0u;
    for (uint index = 0u; index < regulatoryNodeCapacity; ++index) {
        if ((nodes[base + index].flags & 1u) == 0u) { continue; }
        if (activeOrdinal == ordinal) { return index; }
        activeOrdinal += 1u;
    }
    return regulatoryNodeCapacity;
}

inline uint activeRegulatoryEdgeAtOrdinal(
    device const RegulatoryEdge* edges,
    uint base,
    uint ordinal
) {
    uint activeOrdinal = 0u;
    for (uint index = 0u; index < regulatoryEdgeCapacity; ++index) {
        if ((edges[base + index].flags & 1u) == 0u) { continue; }
        if (activeOrdinal == ordinal) { return index; }
        activeOrdinal += 1u;
    }
    return regulatoryEdgeCapacity;
}

inline uint firstInactiveRegulatoryNode(
    device const RegulatoryNode* nodes,
    uint base
) {
    for (uint index = 0u; index < regulatoryNodeCapacity; ++index) {
        if ((nodes[base + index].flags & 1u) == 0u) { return index; }
    }
    return regulatoryNodeCapacity;
}

inline uint firstInactiveRegulatoryEdge(
    device const RegulatoryEdge* edges,
    uint base
) {
    for (uint index = 0u; index < regulatoryEdgeCapacity; ++index) {
        if ((edges[base + index].flags & 1u) == 0u) { return index; }
    }
    return regulatoryEdgeCapacity;
}

inline void mutateDevelopmentalGenome(
    device const DevelopmentalGenome* genomes,
    device DevelopmentalGenome* mutableGenomes,
    device const RegulatoryNode* nodes,
    device RegulatoryNode* mutableNodes,
    device const RegulatoryEdge* edges,
    device RegulatoryEdge* mutableEdges,
    device atomic_uint* identityCounters,
    uint parentOwner,
    uint childOwner,
    uint seed,
    float mutation,
    bool branchMutation
) {
    uint parentNodeBase = parentOwner * regulatoryNodeCapacity;
    uint childNodeBase = childOwner * regulatoryNodeCapacity;
    uint parentEdgeBase = parentOwner * regulatoryEdgeCapacity;
    uint childEdgeBase = childOwner * regulatoryEdgeCapacity;
    float numericalDistance = 0.0;
    for (uint index = 0u; index < regulatoryNodeCapacity; ++index) {
        RegulatoryNode node = nodes[parentNodeBase + index];
        if ((node.flags & 1u) != 0u) {
            float oldBias = node.bias;
            float oldRate = node.responseRate;
            node.bias = mutateScalar(node.bias, seed + index * 13u, 0.018 + mutation * 1.6, -3.0, 3.0);
            node.responseRate = mutateScalar(
                node.responseRate, seed + index * 17u + 1u, 0.001 + mutation * 0.12, 0.002, 0.14
            );
            node.sensorWeight = mutateScalar(
                node.sensorWeight, seed + index * 19u + 2u, 0.025 + mutation * 1.8, -3.0, 3.0
            );
            node.outputWeight = mutateScalar(
                node.outputWeight, seed + index * 23u + 3u, 0.018 + mutation * 1.4, -2.5, 2.5
            );
            numericalDistance += abs(node.bias - oldBias) * 0.018 + abs(node.responseRate - oldRate) * 0.6;
        }
        mutableNodes[childNodeBase + index] = node;
    }
    for (uint index = 0u; index < regulatoryEdgeCapacity; ++index) {
        RegulatoryEdge edge = edges[parentEdgeBase + index];
        if ((edge.flags & 1u) != 0u) {
            float oldWeight = edge.weight;
            edge.weight = mutateScalar(edge.weight, seed + 401u + index * 29u, 0.025 + mutation * 2.1, -3.2, 3.2);
            edge.plasticity = mutateScalar(
                edge.plasticity, seed + 503u + index * 31u, 0.002 + mutation * 0.08, -0.12, 0.12
            );
            numericalDistance += abs(edge.weight - oldWeight) * 0.012;
        }
        mutableEdges[childEdgeBase + index] = edge;
    }

    DevelopmentalGenome child = genomes[parentOwner];
    child.actuatorBiasA = clamp(child.actuatorBiasA + randomSigned4(seed + 701u) * (0.008 + mutation), -1.5, 1.5);
    child.actuatorBiasB = clamp(child.actuatorBiasB + randomSigned4(seed + 705u) * (0.008 + mutation), -1.5, 1.5);
    float4 oldMechanochemistryA = child.mechanochemistryA;
    float4 oldMechanochemistryB = child.mechanochemistryB;
    float4 oldMorphogenKinetics = child.morphogenKinetics;
    float4 oldMorphogenTransport = child.morphogenTransport;
    float4 oldJunctionMaterial = child.junctionMaterial;
    float4 oldEcologicalResponse = child.ecologicalResponse;
    child.mechanochemistryA = clamp(
        child.mechanochemistryA + randomSigned4(seed + 709u) * (0.010 + mutation * 1.25),
        float4(0.12), float4(3.0)
    );
    child.mechanochemistryB.xy = clamp(
        child.mechanochemistryB.xy + randomSigned4(seed + 713u).xy * (0.010 + mutation * 1.30),
        float2(0.12), float2(3.0)
    );
    child.mechanochemistryB.z = mutateScalar(
        child.mechanochemistryB.z, seed + 715u, 0.004 + mutation * 0.42, 0.12, 0.78
    );
    child.mechanochemistryB.w = mutateScalar(
        child.mechanochemistryB.w, seed + 717u, 0.010 + mutation * 1.15, 0.15, 2.5
    );
    child.morphogenKinetics = clamp(
        child.morphogenKinetics + randomSigned4(seed + 718u) * (0.006 + mutation * 0.82),
        float4(0.02), float4(1.20)
    );
    child.morphogenTransport.xy = clamp(
        child.morphogenTransport.xy + randomSigned4(seed + 720u).xy *
            (0.010 + mutation * 1.05),
        float2(0.04), float2(2.40)
    );
    child.morphogenTransport.zw = clamp(
        child.morphogenTransport.zw + randomSigned4(seed + 722u).zw *
            (0.008 + mutation * 0.95),
        float2(0.015), float2(1.80)
    );
    child.junctionMaterial = clamp(
        child.junctionMaterial + randomSigned4(seed + 724u) * (0.008 + mutation * 1.08),
        float4(0.035), float4(1.60)
    );
    child.ecologicalResponse = clamp(
        child.ecologicalResponse + randomSigned4(seed + 726u) * (0.006 + mutation * 0.88),
        float4(0.0), float4(1.0)
    );
    numericalDistance += length(child.mechanochemistryA - oldMechanochemistryA) * 0.020 +
        length(child.mechanochemistryB - oldMechanochemistryB) * 0.020 +
        length(child.morphogenKinetics - oldMorphogenKinetics) * 0.026 +
        length(child.morphogenTransport - oldMorphogenTransport) * 0.022 +
        length(child.junctionMaterial - oldJunctionMaterial) * 0.024 +
        length(child.ecologicalResponse - oldEcologicalResponse) * 0.022;
    uint structuralChanges = 0u;
    bool structuralMutation = branchMutation;
    if (structuralMutation) {
        uint operation = hash32(seed + 727u) % 5u;
        if (operation == 0u) {
            uint activeNodeOrdinal = hash32(seed + 733u) % max(child.topology.x, 1u);
            uint sourceSlot = activeRegulatoryNodeAtOrdinal(
                mutableNodes, childNodeBase, activeNodeOrdinal
            );
            uint targetSlot = firstInactiveRegulatoryNode(mutableNodes, childNodeBase);
            if (targetSlot < regulatoryNodeCapacity &&
                sourceSlot < regulatoryNodeCapacity) {
                RegulatoryNode duplicate = mutableNodes[childNodeBase + sourceSlot];
                duplicate.bias = mutateScalar(duplicate.bias, seed + 739u, 0.22, -3.0, 3.0);
                duplicate.sensorIndex = random01(seed + 743u) < 0.54
                    ? duplicate.sensorIndex : (hash32(seed + 745u) & 15u);
                duplicate.actuatorMask = random01(seed + 747u) < 0.60
                    ? duplicate.actuatorMask : (1u << (hash32(seed + 751u) & 7u));
                duplicate.innovationID = atomic_fetch_add_explicit(
                    &identityCounters[1], 1u, memory_order_relaxed
                );
                mutableNodes[childNodeBase + targetSlot] = duplicate;

                // Preserve a small connected subgraph around a duplicated node.
                // The inherited paths make the copy immediately functional while
                // its new innovation IDs allow subsequent independent divergence.
                uint duplicateIncomingSlot = regulatoryEdgeCapacity;
                uint duplicateOutgoingSlot = regulatoryEdgeCapacity;
                uint incomingRank = 0xffffffffu;
                uint outgoingRank = 0xffffffffu;
                for (uint index = 0u; index < regulatoryEdgeCapacity; ++index) {
                    RegulatoryEdge candidate = mutableEdges[childEdgeBase + index];
                    if ((candidate.flags & 1u) == 0u) { continue; }
                    if (candidate.target == sourceSlot) {
                        uint rank = hash32(candidate.innovationID ^ seed ^ 0x68bc21ebu);
                        if (rank < incomingRank) {
                            incomingRank = rank;
                            duplicateIncomingSlot = index;
                        }
                    }
                    if (candidate.source == sourceSlot) {
                        uint rank = hash32(candidate.innovationID ^ seed ^ 0x02e5be93u);
                        if (rank < outgoingRank) {
                            outgoingRank = rank;
                            duplicateOutgoingSlot = index;
                        }
                    }
                }
                if (duplicateIncomingSlot < regulatoryEdgeCapacity) {
                    uint freeEdgeSlot = firstInactiveRegulatoryEdge(
                        mutableEdges, childEdgeBase
                    );
                    if (freeEdgeSlot < regulatoryEdgeCapacity) {
                        RegulatoryEdge copiedEdge =
                            mutableEdges[childEdgeBase + duplicateIncomingSlot];
                        bool selfLoop = copiedEdge.source == sourceSlot;
                        copiedEdge.source = selfLoop ? targetSlot : copiedEdge.source;
                        copiedEdge.target = targetSlot;
                        copiedEdge.weight = mutateScalar(
                            copiedEdge.weight, seed + 752u, 0.12, -3.2, 3.2
                        );
                        copiedEdge.innovationID = atomic_fetch_add_explicit(
                            &identityCounters[1], 1u, memory_order_relaxed
                        );
                        mutableEdges[childEdgeBase + freeEdgeSlot] = copiedEdge;
                        numericalDistance += 0.018;
                    }
                }
                if (duplicateOutgoingSlot < regulatoryEdgeCapacity &&
                    duplicateOutgoingSlot != duplicateIncomingSlot) {
                    uint freeEdgeSlot = firstInactiveRegulatoryEdge(
                        mutableEdges, childEdgeBase
                    );
                    if (freeEdgeSlot < regulatoryEdgeCapacity) {
                        RegulatoryEdge copiedEdge =
                            mutableEdges[childEdgeBase + duplicateOutgoingSlot];
                        copiedEdge.source = targetSlot;
                        copiedEdge.weight = mutateScalar(
                            copiedEdge.weight, seed + 754u, 0.12, -3.2, 3.2
                        );
                        copiedEdge.innovationID = atomic_fetch_add_explicit(
                            &identityCounters[1], 1u, memory_order_relaxed
                        );
                        mutableEdges[childEdgeBase + freeEdgeSlot] = copiedEdge;
                        numericalDistance += 0.018;
                    }
                }
                structuralChanges += 1u;
            }
        } else if (operation == 1u && child.topology.x > 4u) {
            uint activeNodeOrdinal = hash32(seed + 757u) % child.topology.x;
            uint slot = activeRegulatoryNodeAtOrdinal(
                mutableNodes, childNodeBase, activeNodeOrdinal
            );
            if (slot < regulatoryNodeCapacity) {
                mutableNodes[childNodeBase + slot].flags = 0u;
                structuralChanges += 1u;
            }
        } else if (operation == 2u) {
            uint slot = firstInactiveRegulatoryEdge(mutableEdges, childEdgeBase);
            if (slot < regulatoryEdgeCapacity && child.topology.x > 0u) {
                uint sourceOrdinal = hash32(seed + 769u) % child.topology.x;
                uint targetOrdinal = hash32(seed + 773u) % child.topology.x;
                RegulatoryEdge edge = emptyRegulatoryEdge();
                edge.source = activeRegulatoryNodeAtOrdinal(
                    mutableNodes, childNodeBase, sourceOrdinal
                );
                edge.target = activeRegulatoryNodeAtOrdinal(
                    mutableNodes, childNodeBase, targetOrdinal
                );
                if (edge.source < regulatoryNodeCapacity &&
                    edge.target < regulatoryNodeCapacity) {
                    edge.weight = signedRandom(seed + 779u) * 1.4;
                    edge.plasticity = signedRandom(seed + 787u) * 0.04;
                    edge.innovationID = atomic_fetch_add_explicit(
                        &identityCounters[1], 1u, memory_order_relaxed
                    );
                    edge.flags = 1u;
                    structuralChanges += 1u;
                }
                mutableEdges[childEdgeBase + slot] = edge;
            }
        } else if (operation == 3u && child.topology.y > 0u) {
            uint activeEdgeOrdinal = hash32(seed + 761u) % child.topology.y;
            uint slot = activeRegulatoryEdgeAtOrdinal(
                mutableEdges, childEdgeBase, activeEdgeOrdinal
            );
            if (slot < regulatoryEdgeCapacity) {
                RegulatoryEdge edge = mutableEdges[childEdgeBase + slot];
                edge.flags = 0u;
                mutableEdges[childEdgeBase + slot] = edge;
                structuralChanges += 1u;
            }
        } else if (operation == 4u && child.topology.y > 0u &&
            child.topology.x > 0u) {
            uint activeEdgeOrdinal = hash32(seed + 761u) % child.topology.y;
            uint slot = activeRegulatoryEdgeAtOrdinal(
                mutableEdges, childEdgeBase, activeEdgeOrdinal
            );
            if (slot < regulatoryEdgeCapacity) {
                RegulatoryEdge edge = mutableEdges[childEdgeBase + slot];
                uint sourceOrdinal = hash32(seed + 797u) % child.topology.x;
                uint targetOrdinal = hash32(seed + 809u) % child.topology.x;
                uint reconnectedSource = activeRegulatoryNodeAtOrdinal(
                    mutableNodes, childNodeBase, sourceOrdinal
                );
                uint reconnectedTarget = activeRegulatoryNodeAtOrdinal(
                    mutableNodes, childNodeBase, targetOrdinal
                );
                if (reconnectedSource == edge.source &&
                    reconnectedTarget == edge.target && child.topology.x > 1u) {
                    targetOrdinal = (targetOrdinal + 1u) % child.topology.x;
                    reconnectedTarget = activeRegulatoryNodeAtOrdinal(
                        mutableNodes, childNodeBase, targetOrdinal
                    );
                }
                edge.source = reconnectedSource;
                edge.target = reconnectedTarget;
                edge.innovationID = atomic_fetch_add_explicit(
                    &identityCounters[1], 1u, memory_order_relaxed
                );
                structuralChanges += 1u;
                mutableEdges[childEdgeBase + slot] = edge;
            }
        }
    }

    uint activeNodes = 0u;
    uint activeEdges = 0u;
    for (uint index = 0u; index < regulatoryNodeCapacity; ++index) {
        activeNodes += mutableNodes[childNodeBase + index].flags & 1u;
    }
    for (uint index = 0u; index < regulatoryEdgeCapacity; ++index) {
        RegulatoryEdge edge = mutableEdges[childEdgeBase + index];
        if ((edge.flags & 1u) != 0u &&
            (mutableNodes[childNodeBase + edge.source].flags & 1u) != 0u &&
            (mutableNodes[childNodeBase + edge.target].flags & 1u) != 0u) {
            activeEdges += 1u;
        } else if ((edge.flags & 1u) != 0u) {
            edge.flags = 0u;
            mutableEdges[childEdgeBase + index] = edge;
        }
    }
    float lastDistance = numericalDistance + float(structuralChanges) * 0.12;
    child.topology = uint4(activeNodes, activeEdges, 0u, child.topology.w + structuralChanges);
    child.mutation.x += lastDistance;
    child.mutation.y = lastDistance;
    child.mutation.zw = clamp(
        child.mutation.zw + float2(signedRandom(seed + 821u), signedRandom(seed + 823u)) * 0.002,
        float2(0.002), float2(0.18)
    );
    mutableGenomes[childOwner] = child;
    child.topology.z = topologyHash(mutableNodes, mutableEdges, childOwner);
    mutableGenomes[childOwner] = child;
}

struct RegulatoryOutputs {
    float4 a;
    float4 b;
};

inline RegulatoryOutputs evolveDevelopmentalProgram(
    device const DevelopmentalGenome* genomes,
    device const RegulatoryNode* nodes,
    device const RegulatoryEdge* edges,
    device float* nodeStates,
    uint owner,
    uint cellIndex,
    thread const float* sensors
) {
    DevelopmentalGenome genome = genomes[owner];
    uint nodeBase = owner * regulatoryNodeCapacity;
    uint edgeBase = owner * regulatoryEdgeCapacity;
    uint stateBase = cellIndex * regulatoryNodeCapacity;
    float previous[regulatoryNodeCapacity];
    float drive[regulatoryNodeCapacity];
    for (uint index = 0u; index < regulatoryNodeCapacity; ++index) {
        RegulatoryNode node = nodes[nodeBase + index];
        previous[index] = nodeStates[stateBase + index];
        // Generic positive state feedback gives the inherited network persistent
        // attractors. Which attractor is occupied remains a consequence of the
        // local sensors, graph, and inherited weights rather than a cell-type table.
        float centeredPrevious = previous[index] * 2.0 - 1.0;
        drive[index] = node.bias + centeredPrevious *
            (1.64 + min(abs(node.outputWeight), 2.0) * 0.10);
        if ((node.flags & 1u) != 0u && node.sensorIndex < 16u) {
            drive[index] += sensors[node.sensorIndex] * node.sensorWeight;
        }
    }
    for (uint index = 0u; index < regulatoryEdgeCapacity; ++index) {
        RegulatoryEdge edge = edges[edgeBase + index];
        if ((edge.flags & 1u) == 0u || edge.source >= regulatoryNodeCapacity ||
            edge.target >= regulatoryNodeCapacity) { continue; }
        float activity = previous[edge.source] * 2.0 - 1.0;
        drive[edge.target] += activity * edge.weight + activity * sensors[2] * edge.plasticity;
    }

    float actuators[8] = {
        genome.actuatorBiasA.x, genome.actuatorBiasA.y, genome.actuatorBiasA.z, genome.actuatorBiasA.w,
        genome.actuatorBiasB.x, genome.actuatorBiasB.y, genome.actuatorBiasB.z, genome.actuatorBiasB.w
    };
    float actuatorWeight[8] = { 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 };
    for (uint index = 0u; index < regulatoryNodeCapacity; ++index) {
        RegulatoryNode node = nodes[nodeBase + index];
        if ((node.flags & 1u) == 0u) {
            nodeStates[stateBase + index] = 0.0;
            continue;
        }
        float target = saturate(0.5 + 0.5 * tanh(drive[index] * 0.62));
        float updated = mix(previous[index], target, clamp(node.responseRate, 0.002, 0.14));
        nodeStates[stateBase + index] = updated;
        for (uint actuator = 0u; actuator < 8u; ++actuator) {
            if ((node.actuatorMask & (1u << actuator)) == 0u) { continue; }
            actuators[actuator] += (updated * 2.0 - 1.0) * node.outputWeight;
            actuatorWeight[actuator] += abs(node.outputWeight);
        }
    }
    for (uint actuator = 0u; actuator < 8u; ++actuator) {
        actuators[actuator] = saturate(0.5 + 0.5 * tanh(actuators[actuator] / actuatorWeight[actuator]));
    }
    RegulatoryOutputs output;
    output.a = float4(actuators[0], actuators[1], actuators[2], actuators[3]);
    output.b = float4(actuators[4], actuators[5], actuators[6], actuators[7]);
    return output;
}

inline void recordLineageEvent(
    device LineageEventRecord* events,
    device atomic_uint* identityCounters,
    uint kind,
    AgentState agent,
    DevelopmentalGenome genome,
    ResonanceGenome resonance,
    CellAggregate aggregate,
    uint step
) {
    uint sequence = atomic_fetch_add_explicit(&identityCounters[2], 1u, memory_order_relaxed) + 1u;
    uint slot = (sequence - 1u) % lineageEventCapacity;
    LineageEventRecord event;
    event.sequence = sequence;
    event.kind = kind;
    event.birthID = agent.birthID;
    event.parentBirthID = agent.parentBirthID;
    event.step = step;
    event.generation = agent.generation;
    event.genomeHash = agent.genomeHash;
    event.topologyHash = genome.topology.z;
    event.mutationDistance = agent.lastMutationDistance;
    event.resonanceFrequency = resonance.mechanics.x;
    event.morphologyDistance = 0.0;
    event.energy = agent.energy;
    event.morphology = float4(
        aggregate.physiology.x / referenceTissueCellCount,
        aggregate.morphology.z,
        aggregate.shape.z,
        aggregate.dynamics.y
    );
    event.programAncestry = uint4(
        agent.dominantProgramIndex, agent.dominantProgramGeneration,
        maxHeritableProgramCount, 0u
    );
    events[slot] = event;
}

inline void recordCellLineageEvent(
    device LineageEventRecord* events,
    device atomic_uint* identityCounters,
    uint kind,
    CellIdentity childIdentity,
    uint parentPersistentID,
    CellState child,
    HeritableProgram program,
    DevelopmentalGenome genome,
    ResonanceGenome resonance,
    float mutationDistance,
    uint step
) {
    uint sequence = atomic_fetch_add_explicit(&identityCounters[2], 1u, memory_order_relaxed) + 1u;
    uint slot = (sequence - 1u) % lineageEventCapacity;
    LineageEventRecord event;
    event.sequence = sequence;
    event.kind = kind;
    event.birthID = childIdentity.persistentID;
    event.parentBirthID = parentPersistentID;
    event.step = step;
    event.generation = program.generation;
    event.genomeHash = program.genomeHash;
    event.topologyHash = genome.topology.z;
    event.mutationDistance = mutationDistance;
    event.resonanceFrequency = resonance.mechanics.x;
    event.morphologyDistance = 0.0;
    event.energy = child.physiology.x;
    event.morphology = float4(
        child.physiology.y,
        child.physiology.w,
        child.signals.z,
        child.physiology.z
    );
    bool secondaryParentEvent = kind == 6u &&
        (program.ancestryFlags & 1u) != 0u &&
        program.secondParentProgramIndex < maxHeritableProgramCount;
    event.programAncestry = uint4(
        childIdentity.programIndex, childIdentity.programGeneration,
        secondaryParentEvent
            ? program.secondParentProgramIndex : program.parentProgramIndex,
        secondaryParentEvent
            ? program.secondParentProgramGeneration : program.parentProgramGeneration
    );
    events[slot] = event;
}

inline int2 wrapped(int2 position, uint width, uint height) {
    int x = position.x % int(width);
    int y = position.y % int(height);
    return int2(x < 0 ? x + int(width) : x, y < 0 ? y + int(height) : y);
}

inline float2 toroidalDelta(float2 a, float2 b) {
    float2 delta = abs(a - b);
    return min(delta, 1.0 - delta);
}

inline float2 signedToroidalDelta(float2 from, float2 to) {
    float2 delta = to - from;
    return delta - round(delta);
}

inline float2 tissueHeading(AgentState agent) {
    float angle = agent.tissueKinematics.x;
    return float2(cos(angle), sin(angle));
}

inline float2 rotateTissueToWorld(float2 localVector, AgentState agent) {
    float2 heading = tissueHeading(agent);
    return heading * localVector.x + float2(-heading.y, heading.x) * localVector.y;
}

inline float2 rotateWorldToTissue(float2 worldVector, AgentState agent) {
    float2 heading = tissueHeading(agent);
    return float2(dot(worldVector, heading), dot(worldVector, float2(-heading.y, heading.x)));
}

inline float cellWorldScale(constant SimulationUniforms& uniforms) {
    return 0.0140 / max(uniforms.worldScale, 1.0);
}

inline float2 cellWorldPosition(
    AgentState agent,
    float2 tissuePosition,
    constant SimulationUniforms& uniforms
) {
    return agent.position + rotateTissueToWorld(tissuePosition, agent) * cellWorldScale(uniforms);
}

inline uint2 spatialHashCoordinate(float2 worldPosition) {
    return min(
        uint2(clamp(worldPosition, float2(0.0), float2(0.999999)) *
            float(cellSpatialHashAxisResolution)),
        uint2(cellSpatialHashAxisResolution - 1u)
    );
}

inline uint cellSpatialHash(uint2 coordinate) {
    // The 128 x 128 coordinate space exactly matches the 16,384-head table.
    // Direct addressing removes randomized collisions and the per-cell
    // duplicate-bucket scan; the narrow phase still decides physical contact.
    return coordinate.x + coordinate.y * cellSpatialHashAxisResolution;
}

inline uint findCellComponentRoot(
    device const atomic_uint* parents,
    uint index
) {
    uint current = index;
    for (uint iteration = 0u; iteration < 64u; ++iteration) {
        uint parent = atomic_load_explicit(&parents[current], memory_order_relaxed);
        if (parent == current || parent == emptySpatialHashEntry) { return parent; }
        current = parent;
    }
    return current;
}

inline void unionCellComponentPair(
    device atomic_uint* parents,
    device const CellIdentity* identities,
    uint indexA,
    uint indexB
) {
    for (uint iteration = 0u; iteration < 32u; ++iteration) {
        uint rootA = findCellComponentRoot(parents, indexA);
        uint rootB = findCellComponentRoot(parents, indexB);
        if (rootA == rootB || rootA == emptySpatialHashEntry || rootB == emptySpatialHashEntry) {
            return;
        }
        uint persistentA = identities[rootA].persistentID;
        uint persistentB = identities[rootB].persistentID;
        bool aPrecedesB = persistentA < persistentB ||
            (persistentA == persistentB && rootA < rootB);
        uint winner = aPrecedesB ? rootA : rootB;
        uint loser = aPrecedesB ? rootB : rootA;
        uint expected = loser;
        if (atomic_compare_exchange_weak_explicit(
            &parents[loser], &expected, winner,
            memory_order_relaxed, memory_order_relaxed
        )) { return; }
    }
}

inline float2 membraneSupport(
    device const MembraneVertex* membraneVertices,
    uint cellIndex,
    float2 direction
) {
    float2 unitDirection = length(direction) > 0.000001 ? normalize(direction) : float2(1.0, 0.0);
    float support = 0.0;
    float integrity = 1.0;
    uint base = cellIndex * membraneVertexCount;
    for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
        MembraneVertex membranePoint = membraneVertices[base + vertexIndex];
        float projection = dot(membranePoint.position, unitDirection);
        if (projection > support) {
            support = projection;
            integrity = membranePoint.mechanics.y;
        }
    }
    return float2(max(support, 0.035), saturate(integrity));
}

inline MembraneSupportSample membraneSupportSample(
    device const MembraneVertex* membraneVertices,
    uint cellIndex,
    float2 direction
) {
    float2 unitDirection = length(direction) > 0.000001
        ? normalize(direction) : float2(1.0, 0.0);
    MembraneSupportSample sample;
    sample.point = unitDirection * 0.035;
    sample.integrity = 1.0;
    sample.vertexIndex = 0u;
    float bestProjection = -INFINITY;
    uint base = cellIndex * membraneVertexCount;
    for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
        MembraneVertex membranePoint = membraneVertices[base + vertexIndex];
        float projection = dot(membranePoint.position, unitDirection);
        if (projection > bestProjection) {
            bestProjection = projection;
            sample.point = membranePoint.position;
            sample.integrity = saturate(membranePoint.mechanics.y);
            sample.vertexIndex = vertexIndex;
        }
    }
    return sample;
}

inline bool pointInsideMembrane(
    device const MembraneVertex* membraneVertices,
    uint cellIndex,
    float2 point
) {
    bool inside = false;
    uint base = cellIndex * membraneVertexCount;
    float2 previous = membraneVertices[base + membraneVertexCount - 1u].position;
    for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
        float2 current = membraneVertices[base + vertexIndex].position;
        bool crosses = (current.y > point.y) != (previous.y > point.y);
        if (crosses) {
            float crossingX = (previous.x - current.x) * (point.y - current.y) /
                max(abs(previous.y - current.y), 0.0000001) *
                sign(previous.y - current.y) + current.x;
            if (point.x < crossingX) { inside = !inside; }
        }
        previous = current;
    }
    return inside;
}

inline float4 traitA(uint lineage, uint seed) {
    uint base = hash32(seed ^ lineage * 0x85ebca6bu);
    return float4(
        0.28 + 0.66 * random01(base + 1u),
        0.12 + 0.82 * random01(base + 2u),
        0.08 + 0.84 * random01(base + 3u),
        0.14 + 0.80 * random01(base + 4u)
    );
}

inline float4 traitB(uint lineage, uint seed) {
    uint base = hash32(seed ^ lineage * 0x27d4eb2fu);
    return float4(
        0.12 + 0.78 * random01(base + 5u),
        0.006 + 0.075 * random01(base + 6u),
        0.12 + 0.82 * random01(base + 7u),
        random01(base + 8u)
    );
}

inline float4 traitC(uint lineage, uint seed) {
    uint base = hash32(seed ^ lineage * 0xd3a2646cu);
    float3 enzymes = pow(float3(
        0.08 + 0.92 * random01(base + 9u),
        0.08 + 0.92 * random01(base + 10u),
        0.08 + 0.92 * random01(base + 11u)
    ), float3(1.45));
    return float4(enzymes, 0.015 + 0.72 * pow(random01(base + 12u), 2.4));
}

inline float4 quantumCoin(float4 spinor, float theta) {
    float c = cos(theta);
    float s = sin(theta);
    float2 a = spinor.xy;
    float2 b = spinor.zw;
    return float4(
        c * a.x + s * b.y,
        c * a.y - s * b.x,
        s * a.y + c * b.x,
        -s * a.x + c * b.y
    );
}

inline float4 quantumCoinPrepared(float4 spinor, float2 coin) {
    float2 a = spinor.xy;
    float2 b = spinor.zw;
    return float4(
        coin.x * a.x + coin.y * b.y,
        coin.x * a.y - coin.y * b.x,
        coin.y * a.y + coin.x * b.x,
        -coin.y * a.x + coin.x * b.y
    );
}

kernel void initializeQuantumField(
    texture2d<float, access::write> quantumOut [[texture(0)]],
    constant SimulationUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= quantumGridSize || gid.y >= quantumGridSize) { return; }

    float2 uv = (float2(gid) + 0.5) / float(quantumGridSize);
    float sigma = 0.065;
    float2 leftCenter = float2(0.445, 0.5);
    float2 rightCenter = float2(0.555, 0.5);
    float leftPacket = exp(-dot(uv - leftCenter, uv - leftCenter) / (2.0 * sigma * sigma));
    float rightPacket = exp(-dot(uv - rightCenter, uv - rightCenter) / (2.0 * sigma * sigma));
    float normalization = 1.0 / (sqrt(2.0 * M_PI_F) * sigma * float(quantumGridSize));
    float seedPhase = random01(hash32(uniforms.seed ^ 0x7f4a7c15u)) * 2.0 * M_PI_F;
    float carrier = (uv.x * 31.0 + uv.y * 17.0) * M_PI_F + seedPhase;
    float relativePhase = (uv.y - 0.5) * 22.0 * M_PI_F;
    float2 leftAmplitude = leftPacket * float2(cos(carrier), sin(carrier));
    float2 rightAmplitude = rightPacket * float2(
        cos(carrier + relativePhase),
        sin(carrier + relativePhase)
    );
    float2 superposition = (leftAmplitude + rightAmplitude) * normalization;
    quantumOut.write(float4(superposition * 0.9238795, superposition * 0.3826834), gid);
}

kernel void prepareQuantumCoupling(
    texture2d_array<float, access::read> state [[texture(0)]],
    texture2d_array<float, access::read> genomeA [[texture(1)]],
    texture2d_array<float, access::read> ecology [[texture(2)]],
    texture2d<float, access::write> coupling [[texture(3)]],
    constant SimulationUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height) { return; }
    float4 localState = state.read(gid, 0);
    float4 localGenome = genomeA.read(gid, 0);
    float4 localEcology = ecology.read(gid, 0);
    float theta = 0.18 + 0.16 * saturate(localState.w * 4.0) +
        0.06 * localGenome.y;
    float potential = 0.012 * (
        localState.x + localEcology.x * 0.8 + localState.y * 2.2 +
        localState.w * 3.0 + localEcology.z * 1.4
    );
    coupling.write(float4(cos(theta), sin(theta), cos(potential), sin(potential)), gid);
}

kernel void evolveQuantumField(
    texture2d<float, access::read> quantumIn [[texture(0)]],
    texture2d<float, access::read> coupling [[texture(1)]],
    texture2d<float, access::write> quantumOut [[texture(2)]],
    constant SimulationUniforms& uniforms [[buffer(0)]],
    constant uint& quantumStep [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= quantumGridSize || gid.y >= quantumGridSize) { return; }

    uint2 direction = (quantumStep & 1u) == 0u ? uint2(1, 0) : uint2(0, 1);
    uint2 quantumMask = uint2(quantumGridSize - 1u);
    uint2 sourceA = (gid - direction) & quantumMask;
    uint2 sourceB = (gid + direction) & quantumMask;
    uint2 biologicalSize = uint2(uniforms.width, uniforms.height);
    uint2 biologicalMax = biologicalSize - 1u;
    uint2 bioA = min(
        sourceA * biologicalSize / quantumGridSize,
        biologicalMax
    );
    uint2 bioB = min(
        sourceB * biologicalSize / quantumGridSize,
        biologicalMax
    );
    float4 couplingA = coupling.read(bioA);
    float4 couplingB = coupling.read(bioB);
    float4 coinA = quantumCoinPrepared(quantumIn.read(sourceA), couplingA.xy);
    float4 coinB = quantumCoinPrepared(quantumIn.read(sourceB), couplingB.xy);
    float4 shifted = float4(coinA.xy, coinB.zw);

    uint2 bio = min(
        gid * biologicalSize / quantumGridSize,
        biologicalMax
    );
    float2 phase = coupling.read(bio).zw;
    float phaseCosine = phase.x;
    float phaseSine = phase.y;
    shifted = float4(
        phaseCosine * shifted.x + phaseSine * shifted.y,
        phaseCosine * shifted.y - phaseSine * shifted.x,
        phaseCosine * shifted.z + phaseSine * shifted.w,
        phaseCosine * shifted.w - phaseSine * shifted.z
    );
    quantumOut.write(shifted, gid);
}

kernel void measureQuantumField(
    texture2d<float, access::read> quantum [[texture(0)]],
    device atomic_uint* norm [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= quantumGridSize || gid.y >= quantumGridSize) { return; }
    float4 wave = quantum.read(gid);
    float probability = dot(wave.xy, wave.xy) + dot(wave.zw, wave.zw);
    uint fixedProbability = uint(min(max(probability, 0.0) * 1000000000.0, 1000000.0));
    atomic_fetch_add_explicit(norm, fixedProbability, memory_order_relaxed);
}

inline float4 geologyAt(float2 uv, uint geologicalEpoch) {
    float epoch = float(geologicalEpoch % 97u);
    float nutrientDeposit = 0.0;
    float mineralDeposit = 0.0;
    float toxicVent = 0.0;
    float rock = 0.0;
    for (uint objectIndex = 0; objectIndex < 30u; ++objectIndex) {
        float index = float(objectIndex + 1u);
        float2 center = fract(float2(
            index * 0.61803398875 + epoch * 0.071,
            index * 0.41421356237 + epoch * 0.113
        ));
        float radius = 0.032 + 0.034 * (0.5 + 0.5 * sin(index * 2.39996323 + epoch));
        float distance = length(toroidalDelta(uv, center));
        float influence = 1.0 - smoothstep(radius * 0.44, radius, distance);
        uint objectType = objectIndex % 6u;
        if (objectType == 0u) {
            nutrientDeposit = max(nutrientDeposit, influence);
            mineralDeposit = max(mineralDeposit, influence * 0.78);
        } else if (objectType == 1u || objectType == 2u) {
            nutrientDeposit = max(nutrientDeposit, influence);
        } else if (objectType == 3u) {
            mineralDeposit = max(mineralDeposit, influence);
        } else if (objectType == 4u) {
            mineralDeposit = max(mineralDeposit, influence * 0.64);
            toxicVent = max(toxicVent, influence);
        } else {
            rock = max(rock, influence);
        }
    }

    // Continuous strata connect the existing local deposits into ridges,
    // channels, pockets, and broad transition zones without biome labels.
    float warp = sin(2.0 * M_PI_F * (
        uv.x * 1.17 - uv.y * 0.83 + epoch * 0.0061
    )) * 0.18;
    float ridgeCarrier = sin(2.0 * M_PI_F * (
        uv.x * 2.15 + uv.y * 1.31 + warp + epoch * 0.0037
    ));
    float channelCarrier = sin(2.0 * M_PI_F * (
        uv.x * 1.42 - uv.y * 2.24 + warp * 0.61 - epoch * 0.0049
    ));
    float pocketCarrier = 0.5 + 0.5 * sin(2.0 * M_PI_F * (
        uv.x * 0.73 + uv.y * 0.91 + epoch * 0.0023
    ));
    float ridge = smoothstep(0.78, 0.98, abs(ridgeCarrier));
    float channel = 1.0 - smoothstep(0.055, 0.30, abs(channelCarrier));
    float softPocket = smoothstep(0.30, 0.82, pocketCarrier) * (1.0 - ridge);
    nutrientDeposit = max(
        nutrientDeposit,
        channel * (0.24 + softPocket * 0.58) * (1.0 - ridge * 0.42)
    );
    mineralDeposit = max(
        mineralDeposit,
        ridge * (0.34 + (1.0 - softPocket) * 0.46)
    );
    toxicVent = max(
        toxicVent,
        ridge * channel * (0.16 + (1.0 - softPocket) * 0.30)
    );
    rock = max(rock, ridge * ridge * (0.44 + (1.0 - channel) * 0.34));

    float centralDeposit = exp(-dot(uv - 0.5, uv - 0.5) / 0.0018);
    nutrientDeposit = max(nutrientDeposit, centralDeposit * 0.88);
    mineralDeposit = max(mineralDeposit, centralDeposit * 0.62);
    toxicVent *= 1.0 - centralDeposit;
    rock *= (1.0 - centralDeposit) * (1.0 - saturate(max(nutrientDeposit, mineralDeposit) * 0.82));
    return saturate(float4(nutrientDeposit, mineralDeposit, toxicVent, rock));
}

inline float2 environmentalDisturbanceCenter(uint eventEpoch) {
    float eventIndex = float(eventEpoch + 1u);
    return fract(float2(
        sin(eventIndex * 12.9898 + 0.37),
        sin(eventIndex * 78.233 + 1.91)
    ) * 43758.5453);
}

inline float environmentalDisturbance(float2 uv, uint step) {
    if (step < 24000u) { return 0.0; }
    uint eventTime = step - 24000u;
    uint eventPhase = eventTime % 48000u;
    if (eventPhase >= 1200u) { return 0.0; }
    uint eventEpoch = eventTime / 48000u;
    float distance = length(toroidalDelta(
        uv, environmentalDisturbanceCenter(eventEpoch)
    ));
    float spatialEnvelope = 1.0 - smoothstep(0.025, 0.080, distance);
    float temporalEnvelope = sin(
        M_PI_F * float(eventPhase) / 1200.0
    );
    return spatialEnvelope * temporalEnvelope * temporalEnvelope;
}

inline float environmentalPhase(float2 uv, float4 geology) {
    float2 stratum = floor(uv * 29.0);
    float stratumNoise = fract(
        sin(dot(stratum + float2(geology.x, geology.y) * 7.0,
            float2(12.9898, 78.233))) * 43758.5453
    );
    return fract(
        stratumNoise * 0.47 + uv.x * 0.31 + uv.y * 0.23 +
        dot(geology, float4(0.17, 0.29, 0.41, 0.11))
    );
}

inline float environmentalFrequency(float2 uv, float4 geology) {
    float spectralCoordinate = saturate(
        0.08 + geology.x * 0.16 + geology.y * 0.42 +
        geology.z * 0.62 + geology.w * 0.24 + environmentalPhase(uv, geology) * 0.28
    );
    return mix(0.0010, 0.0084, spectralCoordinate);
}

inline float2 substrateForcing(float2 uv, float4 geology, uint step) {
    float phase = environmentalPhase(uv, geology);
    float frequency = environmentalFrequency(uv, geology);
    float time = float(step);
    float pulseA = 0.5 + 0.5 * sin(
        2.0 * M_PI_F * (time * frequency * 0.43 + phase + uv.x * 1.7)
    );
    float pulseB = 0.5 + 0.5 * sin(
        2.0 * M_PI_F * (time * frequency * 0.61 + phase * 1.37 - uv.y * 1.9)
    );
    float envelopeA = smoothstep(0.18, 0.82, 0.5 + 0.5 * sin(
        2.0 * M_PI_F * (time * frequency * 0.071 + phase * 0.61)
    ));
    float envelopeB = smoothstep(0.16, 0.84, 0.5 + 0.5 * sin(
        2.0 * M_PI_F * (time * frequency * 0.053 + phase * 0.83 + 0.31)
    ));
    float2 burst = pow(float2(pulseA, pulseB), float2(1.45)) *
        mix(float2(0.20), float2(1.0), float2(envelopeA, envelopeB));
    float2 season = 0.70 + 0.30 * float2(
        sin(2.0 * M_PI_F * (time / 24000.0 + phase)),
        sin(2.0 * M_PI_F * (time / 24000.0 + phase + 0.43))
    );
    float disturbance = environmentalDisturbance(uv, step);
    return (0.045 + 0.955 * burst) * season * mix(1.0, 0.64, disturbance);
}

inline float environmentalMechanicalAmplitude(float4 geology) {
    float source = saturate(
        geology.y * 0.48 + geology.z * 0.92 + geology.w * 0.20 * (1.0 - geology.x)
    );
    return 0.000004 + source * 0.00017;
}

inline float2 environmentalMechanicalDrive(
    float2 uv,
    float4 geology,
    uint step
) {
    float phase = environmentalPhase(uv, geology);
    float frequency = environmentalFrequency(uv, geology);
    float angle = 2.0 * M_PI_F * fract(phase + geology.z * 0.23 + geology.w * 0.11);
    float2 direction = float2(cos(angle), sin(angle));
    float carrier = sin(2.0 * M_PI_F * (float(step) * frequency + phase));
    float envelope = 0.58 + 0.42 * sin(
        2.0 * M_PI_F * (float(step) * frequency * 0.13 + phase * 0.73)
    );
    float disturbance = environmentalDisturbance(uv, step);
    uint eventEpoch = step >= 24000u ? (step - 24000u) / 48000u : 0u;
    float2 eventDelta = toroidalDelta(
        uv, environmentalDisturbanceCenter(eventEpoch)
    );
    float2 eventDirection = length(eventDelta) > 0.000001
        ? normalize(float2(-eventDelta.y, eventDelta.x) + eventDelta * 0.36)
        : direction;
    return direction * carrier * envelope * environmentalMechanicalAmplitude(geology) +
        eventDirection * disturbance * 0.00012;
}

kernel void initializeWorld(
    texture2d_array<float, access::write> stateOut [[texture(0)]],
    texture2d_array<float, access::write> genomeAOut [[texture(1)]],
    texture2d_array<float, access::write> genomeBOut [[texture(2)]],
    texture2d_array<float, access::write> ecologyOut [[texture(3)]],
    texture2d_array<float, access::write> genomeCOut [[texture(4)]],
    texture2d_array<float, access::write> eventOut [[texture(5)]],
    texture2d_array<float, access::write> environmentOut [[texture(6)]],
    texture2d_array<float, access::write> developmentalOut [[texture(7)]],
    constant SimulationUniforms& uniforms [[buffer(0)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height || gid.z >= uniforms.worldCount) { return; }

    float2 uv = (float2(gid.xy) + 0.5) / float2(uniforms.width, uniforms.height);
    float4 geneA = float4(0.50);
    float4 geneB = float4(0.50, 0.012, 0.50, 0.50);
    float4 geneC = float4(0.40, 0.40, 0.20, 0.02);
    float4 geology = geologyAt(uv, uniforms.seed ^ gid.z * 13u);
    float resourceA = 0.006 + geology.x * 0.94;
    float resourceB = 0.004 + geology.y * 0.82;

    stateOut.write(float4(resourceA, 0.0, 0.0, 0.0), gid.xy, gid.z);
    genomeAOut.write(geneA, gid.xy, gid.z);
    genomeBOut.write(geneB, gid.xy, gid.z);
    ecologyOut.write(float4(resourceB, 0.008, geology.z * 0.10, 0.0), gid.xy, gid.z);
    genomeCOut.write(geneC, gid.xy, gid.z);
    eventOut.write(float4(0.0), gid.xy, gid.z);
    environmentOut.write(geology, gid.xy, gid.z);
    developmentalOut.write(float4(0.0), gid.xy, gid.z);
}

kernel void expandWorld(
    texture2d_array<float, access::read> stateIn [[texture(0)]],
    texture2d_array<float, access::read> genomeAIn [[texture(1)]],
    texture2d_array<float, access::read> genomeBIn [[texture(2)]],
    texture2d_array<float, access::read> ecologyIn [[texture(3)]],
    texture2d_array<float, access::read> genomeCIn [[texture(4)]],
    texture2d_array<float, access::read> eventIn [[texture(5)]],
    texture2d_array<float, access::write> stateOut [[texture(6)]],
    texture2d_array<float, access::write> genomeAOut [[texture(7)]],
    texture2d_array<float, access::write> genomeBOut [[texture(8)]],
    texture2d_array<float, access::write> ecologyOut [[texture(9)]],
    texture2d_array<float, access::write> genomeCOut [[texture(10)]],
    texture2d_array<float, access::write> eventOut [[texture(11)]],
    texture2d_array<float, access::read> environmentIn [[texture(12)]],
    texture2d_array<float, access::write> environmentOut [[texture(13)]],
    texture2d_array<float, access::read> developmentalIn [[texture(14)]],
    texture2d_array<float, access::write> developmentalOut [[texture(15)]],
    constant SimulationUniforms& uniforms [[buffer(0)]],
    constant uint& expansionLevel [[buffer(1)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height || gid.z >= uniforms.worldCount) { return; }

    float2 uv = (float2(gid.xy) + 0.5) / float2(uniforms.width, uniforms.height);
    bool containsPreviousWorld = all(uv >= float2(0.25)) && all(uv < float2(0.75));
    if (containsPreviousWorld) {
        float2 oldUV = (uv - 0.25) * 2.0;
        uint2 source = min(
            uint2(oldUV * float2(uniforms.width, uniforms.height)),
            uint2(uniforms.width - 1u, uniforms.height - 1u)
        );
        stateOut.write(stateIn.read(source, gid.z), gid.xy, gid.z);
        genomeAOut.write(genomeAIn.read(source, gid.z), gid.xy, gid.z);
        genomeBOut.write(genomeBIn.read(source, gid.z), gid.xy, gid.z);
        ecologyOut.write(ecologyIn.read(source, gid.z), gid.xy, gid.z);
        genomeCOut.write(genomeCIn.read(source, gid.z), gid.xy, gid.z);
        eventOut.write(eventIn.read(source, gid.z) * 0.72, gid.xy, gid.z);
        environmentOut.write(environmentIn.read(source, gid.z), gid.xy, gid.z);
        developmentalOut.write(
            developmentalIn.read(source, gid.z) * float4(0.82, 0.82, 0.94, 0.76),
            gid.xy, gid.z
        );
        return;
    }

    uint seed = hash32(
        gid.x * 73856093u ^ gid.y * 19349663u ^
        expansionLevel * 83492791u ^ gid.z * 2654435761u ^ uniforms.seed
    );
    float4 geology = geologyAt(
        uv, uniforms.seed ^ expansionLevel * 17u ^ gid.z * 13u
    );
    float resourceA = 0.006 + geology.x * 0.94;
    float resourceB = 0.004 + geology.y * 0.82;
    stateOut.write(float4(resourceA, 0.0, 0.0, 0.0), gid.xy, gid.z);
    genomeAOut.write(float4(0.5), gid.xy, gid.z);
    genomeBOut.write(float4(0.5, 0.02, 0.5, random01(seed + 3u)), gid.xy, gid.z);
    ecologyOut.write(float4(resourceB, 0.008, geology.z * 0.10, 0.0), gid.xy, gid.z);
    genomeCOut.write(float4(0.5, 0.5, 0.5, 0.0), gid.xy, gid.z);
    eventOut.write(float4(0.0), gid.xy, gid.z);
    environmentOut.write(geology, gid.xy, gid.z);
    developmentalOut.write(float4(0.0), gid.xy, gid.z);
}

kernel void initializeMechanicalField(
    texture2d_array<float, access::write> mechanicalOut [[texture(0)]],
    constant SimulationUniforms& uniforms [[buffer(0)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height || gid.z >= uniforms.worldCount) { return; }
    mechanicalOut.write(float4(0.0), gid.xy, gid.z);
}

kernel void expandMechanicalField(
    texture2d_array<float, access::read> mechanicalIn [[texture(0)]],
    texture2d_array<float, access::write> mechanicalOut [[texture(1)]],
    constant SimulationUniforms& uniforms [[buffer(0)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height || gid.z >= uniforms.worldCount) { return; }
    float2 uv = (float2(gid.xy) + 0.5) / float2(uniforms.width, uniforms.height);
    bool containsPreviousWorld = all(uv >= float2(0.25)) && all(uv < float2(0.75));
    if (!containsPreviousWorld) {
        mechanicalOut.write(float4(0.0), gid.xy, gid.z);
        return;
    }
    float2 oldUV = (uv - 0.25) * 2.0;
    uint2 source = min(
        uint2(oldUV * float2(uniforms.width, uniforms.height)),
        uint2(uniforms.width - 1u, uniforms.height - 1u)
    );
    mechanicalOut.write(mechanicalIn.read(source, gid.z) * float4(0.5, 0.5, 0.5, 0.5), gid.xy, gid.z);
}

kernel void evolveMechanicalField(
    texture2d_array<float, access::read> mechanicalIn [[texture(0)]],
    texture2d_array<float, access::write> mechanicalOut [[texture(1)]],
    texture2d_array<float, access::read> environment [[texture(2)]],
    texture2d_array<float, access::read> developmentalField [[texture(3)]],
    device atomic_int* forcing [[buffer(0)]],
    constant SimulationUniforms& uniforms [[buffer(1)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height || gid.z >= uniforms.worldCount) { return; }
    int2 p = int2(gid.xy);
    int2 size = int2(uniforms.width, uniforms.height);
    int2 cardinal[4] = { int2(-1, 0), int2(1, 0), int2(0, -1), int2(0, 1) };
    float4 center = mechanicalIn.read(gid.xy, gid.z);
    float2 displacementLaplacian = float2(0.0);
    for (uint index = 0u; index < 4u; ++index) {
        int2 neighbor = clamp(p + cardinal[index], int2(0), size - 1);
        displacementLaplacian += mechanicalIn.read(uint2(neighbor), gid.z).xy - center.xy;
    }

    uint forceIndex = ((gid.z * uniforms.height + gid.y) * uniforms.width + gid.x) * 2u;
    float2 activeForce = float2(
        atomic_exchange_explicit(&forcing[forceIndex], 0, memory_order_relaxed),
        atomic_exchange_explicit(&forcing[forceIndex + 1u], 0, memory_order_relaxed)
    ) / float(mechanicalForceScale);
    float2 uv = (float2(gid.xy) + 0.5) / float2(uniforms.width, uniforms.height);
    float4 geology = environment.read(gid.xy, gid.z);
    float4 extracellular = developmentalField.read(gid.xy, gid.z);
    float obstacle = smoothstep(0.45, 0.88, geology.w);
    float mineralSupport = smoothstep(0.18, 0.82, geology.y);
    float matrixSupport = smoothstep(0.025, 0.42, extracellular.z);
    float stiffness = clamp(
        0.082 + obstacle * 0.036 + mineralSupport * 0.020 + matrixSupport * 0.026,
        0.075, 0.158
    );
    float damping = clamp(
        0.968 - obstacle * 0.120 - mineralSupport * 0.035 - matrixSupport * 0.055,
        0.76, 0.97
    );
    float2 geologicalDrive = environmentalMechanicalDrive(uv, geology, uniforms.step);
    float2 velocity = (
        center.zw + displacementLaplacian * stiffness +
        activeForce * mix(0.24, 0.31, matrixSupport) +
        geologicalDrive
    ) * damping;
    float edgeDistance = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    velocity *= mix(0.72, 1.0, smoothstep(0.0, 0.055, edgeDistance));
    velocity = clamp(velocity, float2(-0.018), float2(0.018));
    float2 displacement = clamp((center.xy + velocity) * 0.9975, float2(-0.070), float2(0.070));
    mechanicalOut.write(float4(displacement, velocity), gid.xy, gid.z);
}

kernel void expandQuantumField(
    texture2d<float, access::read> quantumIn [[texture(0)]],
    texture2d<float, access::write> quantumOut [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= quantumGridSize || gid.y >= quantumGridSize) { return; }
    bool containsPreviousWorld = gid.x >= quantumGridSize / 4u && gid.x < quantumGridSize * 3u / 4u &&
        gid.y >= quantumGridSize / 4u && gid.y < quantumGridSize * 3u / 4u;
    if (!containsPreviousWorld) {
        quantumOut.write(float4(0.0), gid);
        return;
    }
    uint2 source = min(
        (gid - quantumGridSize / 4u) * 2u,
        uint2(quantumGridSize - 1u)
    );
    quantumOut.write(quantumIn.read(source) * 2.0, gid);
}

kernel void reactWorld(
    texture2d_array<float, access::read> stateIn [[texture(0)]],
    texture2d_array<float, access::read> genomeAIn [[texture(1)]],
    texture2d_array<float, access::read> genomeBIn [[texture(2)]],
    texture2d_array<float, access::read> ecologyIn [[texture(3)]],
    texture2d_array<float, access::read> genomeCIn [[texture(4)]],
    texture2d_array<float, access::write> stateOut [[texture(5)]],
    texture2d_array<float, access::write> genomeAOut [[texture(6)]],
    texture2d_array<float, access::write> genomeBOut [[texture(7)]],
    texture2d_array<float, access::write> ecologyOut [[texture(8)]],
    texture2d_array<float, access::write> genomeCOut [[texture(9)]],
    texture2d_array<float, access::read> eventIn [[texture(10)]],
    texture2d_array<float, access::write> eventOut [[texture(11)]],
    texture2d_array<float, access::read> environmentIn [[texture(12)]],
    texture2d<float, access::read> quantum [[texture(13)]],
    texture2d_array<float, access::read> mechanicalField [[texture(14)]],
    texture2d_array<float, access::read> developmentalIn [[texture(15)]],
    texture2d_array<float, access::write> developmentalOut [[texture(16)]],
    constant SimulationUniforms& uniforms [[buffer(0)]],
    device atomic_uint* cellEnergyExchange [[buffer(1)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height || gid.z >= uniforms.worldCount) { return; }

    uint layer = gid.z;
    uint left = gid.x > 0u ? gid.x - 1u : uniforms.width - 1u;
    uint right = gid.x + 1u < uniforms.width ? gid.x + 1u : 0u;
    uint down = gid.y > 0u ? gid.y - 1u : uniforms.height - 1u;
    uint up = gid.y + 1u < uniforms.height ? gid.y + 1u : 0u;
    float4 center = stateIn.read(gid.xy, layer);
    float4 chemistry = ecologyIn.read(gid.xy, layer);
    float4 geneA = genomeAIn.read(gid.xy, layer);
    float4 geneB = genomeBIn.read(gid.xy, layer);
    float4 geneC = genomeCIn.read(gid.xy, layer);
    float4 priorEvents = eventIn.read(gid.xy, layer);
    float4 geology = environmentIn.read(gid.xy, layer);
    float4 mechanical = mechanicalField.read(gid.xy, layer);
    float4 extracellular = developmentalIn.read(gid.xy, layer);
    uint2 cardinalCoordinates[4] = {
        uint2(left, gid.y), uint2(right, gid.y), uint2(gid.x, down), uint2(gid.x, up)
    };

    float resourceLaplacian = 0.0;
    float4 chemistryLaplacian = float4(0.0);
    float4 eventLaplacian = float4(0.0);
    float4 developmentalLaplacian = float4(0.0);
    for (uint index = 0; index < 4; ++index) {
        uint2 coordinate = cardinalCoordinates[index];
        resourceLaplacian += stateIn.read(coordinate, layer).x - center.x;
        chemistryLaplacian += ecologyIn.read(coordinate, layer) - chemistry;
        eventLaplacian += eventIn.read(coordinate, layer) - priorEvents;
        developmentalLaplacian +=
            developmentalIn.read(coordinate, layer) - extracellular;
    }

    float2 uv = (float2(gid.xy) + 0.5) / float2(uniforms.width, uniforms.height);
    float2 substratePulse = substrateForcing(uv, geology, uniforms.step);
    float obstacle = smoothstep(0.48, 0.84, geology.w);
    float mineralPacking = smoothstep(0.20, 0.86, geology.y);
    float matrixPacking = smoothstep(0.035, 0.58, extracellular.z);
    float basePermeability = 1.0 - obstacle * 0.88;
    float permeability = basePermeability *
        mix(1.0, 0.82, mineralPacking) * mix(1.0, 0.56, matrixPacking);
    float retention = 1.0 + geology.x * 0.16 + geology.y * 0.24 +
        matrixPacking * 0.55;
    float resourceA = max(0.0, center.x + uniforms.dt * 0.18 * permeability * resourceLaplacian);
    float resourceB = max(0.0, chemistry.x + uniforms.dt * 0.15 * permeability * chemistryLaplacian.x);
    float detritus = max(0.0, chemistry.y + uniforms.dt * 0.10 * chemistryLaplacian.y);
    float toxin = max(0.0, chemistry.z + uniforms.dt * 0.16 * chemistryLaplacian.z);
    float catalyst = max(0.0, chemistry.w + uniforms.dt * 0.08 * chemistryLaplacian.w);
    float resourceCapacityA = (0.08 + geology.x * 1.02) * retention;
    float resourceCapacityB = (0.06 + geology.y * 0.98) * retention;
    float sourceAccess = permeability * mix(1.0, 1.32, saturate(retention - 1.0));
    resourceA += uniforms.dt * uniforms.resourceFlux * substratePulse.x *
        (0.00003 + geology.x * 0.0068) * sourceAccess *
        max(resourceCapacityA - resourceA, 0.0);
    resourceB += uniforms.dt * uniforms.resourceFlux * substratePulse.y *
        (0.000025 + geology.y * 0.0062) * sourceAccess *
        max(resourceCapacityB - resourceB, 0.0);
    toxin += uniforms.dt * (
        geology.z * 0.0045 + environmentalDisturbance(uv, uniforms.step) * 0.00065
    );
    toxin *= 1.0 - uniforms.dt *
        (0.052 + (1.0 - geology.z) * 0.040) * mix(1.0, 0.45, matrixPacking);
    catalyst *= 1.0 - uniforms.dt * 0.032 / retention;

    uint energyTileBase = ((layer * uniforms.height + gid.y) * uniforms.width + gid.x) *
        worldExchangeChannelCount;
    float consumedResourceA = substrateFromFixed(atomic_exchange_explicit(
        &cellEnergyExchange[energyTileBase + 3u], 0u, memory_order_relaxed
    ));
    float consumedResourceB = substrateFromFixed(atomic_exchange_explicit(
        &cellEnergyExchange[energyTileBase + 4u], 0u, memory_order_relaxed
    ));
    float consumedDetritus = substrateFromFixed(atomic_exchange_explicit(
        &cellEnergyExchange[energyTileBase + 5u], 0u, memory_order_relaxed
    ));
    float returnedDetritus = substrateFromFixed(atomic_exchange_explicit(
        &cellEnergyExchange[energyTileBase + 6u], 0u, memory_order_relaxed
    ));
    atomic_exchange_explicit(
        &cellEnergyExchange[energyTileBase + 7u], 0u, memory_order_relaxed
    );
    float secretedLigandA = substrateFromFixed(atomic_exchange_explicit(
        &cellEnergyExchange[energyTileBase + 8u], 0u, memory_order_relaxed
    ));
    float secretedLigandB = substrateFromFixed(atomic_exchange_explicit(
        &cellEnergyExchange[energyTileBase + 9u], 0u, memory_order_relaxed
    ));
    float depositedMatrix = substrateFromFixed(atomic_exchange_explicit(
        &cellEnergyExchange[energyTileBase + 10u], 0u, memory_order_relaxed
    ));
    float woundRemodelingCue = substrateFromFixed(atomic_exchange_explicit(
        &cellEnergyExchange[energyTileBase + 11u], 0u, memory_order_relaxed
    ));
    float secretedCatalyst = substrateFromFixed(atomic_exchange_explicit(
        &cellEnergyExchange[energyTileBase + 12u], 0u, memory_order_relaxed
    ));
    float neutralizedToxin = substrateFromFixed(atomic_exchange_explicit(
        &cellEnergyExchange[energyTileBase + 13u], 0u, memory_order_relaxed
    ));

    // Ligands diffuse and turn over, matrix persists locally, and the wound cue
    // spreads fastest but decays rapidly. No component identity enters this field.
    float2 extracellularLigands = max(
        extracellular.xy + uniforms.dt * permeability *
            float2(0.105, 0.078) * developmentalLaplacian.xy +
            float2(secretedLigandA, secretedLigandB) -
            extracellular.xy * uniforms.dt * float2(0.020, 0.016),
        float2(0.0)
    );
    float matrixDensity = max(
        extracellular.z + uniforms.dt * 0.004 * permeability *
            developmentalLaplacian.z + depositedMatrix -
            extracellular.z * uniforms.dt * 0.00045 -
            woundRemodelingCue * (0.18 + extracellular.w * 0.22),
        0.0
    );
    float woundCue = max(
        extracellular.w + uniforms.dt * 0.145 * permeability *
            developmentalLaplacian.w + woundRemodelingCue -
            extracellular.w * uniforms.dt * 0.072,
        0.0
    );
    resourceA = max(resourceA - consumedResourceA, 0.0);
    resourceB = max(resourceB - consumedResourceB, 0.0);
    detritus = max(detritus - consumedDetritus + returnedDetritus, 0.0);
    catalyst += secretedCatalyst;
    toxin = max(toxin - neutralizedToxin, 0.0);
    float mineralization = min(
        detritus,
        uniforms.dt * detritus * (0.00035 + catalyst * 0.0056) *
            permeability * (1.0 - saturate(toxin) * 0.72)
    );
    detritus -= mineralization;
    resourceA += mineralization * (0.16 + substratePulse.x * 0.10);
    resourceB += mineralization * (0.13 + substratePulse.y * 0.09);
    catalyst += mineralization * 0.045;

    float biomass = max(center.y, 0.0);
    float energy = max(center.z, 0.0);
    float membrane = max(center.w, 0.0);
    uint2 quantumCoordinate = min(
        gid.xy * quantumGridSize / uint2(uniforms.width, uniforms.height),
        uint2(quantumGridSize - 1u)
    );
    float4 spinor = quantum.read(quantumCoordinate);
    float probabilityA = dot(spinor.xy, spinor.xy);
    float probabilityB = dot(spinor.zw, spinor.zw);
    float probability = probabilityA + probabilityB;
    float quantumDensity = 1.0 - exp(-probability * 285000.0);
    float componentCoherence = abs(dot(spinor.xy, spinor.zw)) /
        max(sqrt(probabilityA * probabilityB), 0.0000000001);
    float quantumOrder = quantumDensity * (0.24 + 0.76 * saturate(componentCoherence));
    float chemicalAffinity = sqrt(saturate(resourceA) * saturate(resourceB)) *
        permeability * (1.0 - saturate(toxin));
    float mechanicalActivity = saturate(length(mechanical.xy) * 18.0 + length(mechanical.zw) * 75.0);
    catalyst += uniforms.dt * quantumOrder * chemicalAffinity * 0.0090;
    catalyst += uniforms.dt * mechanicalActivity * chemicalAffinity * 0.00032;
    float prebioticCapacity = 0.012 + catalyst * 0.20;
    energy += uniforms.dt * quantumOrder * catalyst *
        (0.015 + 0.035 * saturate(resourceA + resourceB)) * permeability;
    energy += uniforms.dt * mechanicalActivity * catalyst * 0.00018;
    energy = min(energy, prebioticCapacity);
    float prebioticOrder = smoothstep(0.018, 0.065, catalyst) *
        smoothstep(0.002, 0.015, energy) * quantumOrder;
    float prebioticMembraneTarget = prebioticOrder * 0.035;
    membrane += uniforms.dt * 0.22 * (prebioticMembraneTarget - membrane);
    bool wasAlive = biomass > 0.018;
    bool born = false;
    bool replaced = false;
    float mutationPulse = 0.0;
    uint2 neighborCoordinates[8] = {
        uint2(left, gid.y), uint2(right, gid.y), uint2(gid.x, down), uint2(gid.x, up),
        uint2(left, down), uint2(right, down), uint2(left, up), uint2(right, up)
    };
    float4 parentState = float4(0.0);
    float4 parentA = geneA;
    float4 parentB = geneB;
    float4 parentC = geneC;
    float bestPressure = 0.0;
    float neighborOccupancy = 0.0;
    float preyOpportunity = 0.0;
    float incomingAttack = 0.0;

    for (uint index = 0; index < 8; ++index) {
        uint2 coordinate = neighborCoordinates[index];
        float4 neighborState = stateIn.read(coordinate, layer);
        // Empty sites contribute zero to every neighbor term and require no genome reads.
        if (neighborState.y <= 0.0) { continue; }
        float4 neighborA = genomeAIn.read(coordinate, layer);
        float4 neighborB = genomeBIn.read(coordinate, layer);
        float4 neighborC = genomeCIn.read(coordinate, layer);
        float active = smoothstep(0.035, 0.16, neighborState.y);
        neighborOccupancy += active * 0.125;
        float resourceMatch = saturate(neighborC.x * resourceA + neighborC.y * resourceB + neighborC.z * detritus);
        float energyRatio = saturate(neighborState.z / max(neighborState.y * 0.16, 0.001));
        uint jitterSeed = hash32(uniforms.step + gid.x * 73856093u + gid.y * 19349663u + index * 83492791u);
        float pressure = active * (0.25 + 0.75 * energyRatio) *
            (0.45 + 0.55 * neighborB.x) * (0.45 + 0.55 * resourceMatch) *
            (0.88 + 0.24 * random01(jitterSeed));
        if (pressure > bestPressure) {
            bestPressure = pressure;
            parentState = neighborState;
            parentA = neighborA;
            parentB = neighborB;
            parentC = neighborC;
        }
        float difference = saturate(length(geneC - neighborC) * 0.70 + length(geneA - neighborA) * 0.20);
        preyOpportunity += neighborState.y * difference *
            (1.0 - neighborA.w * 0.72) * 0.125;
        incomingAttack += active * neighborC.w * difference * 0.125;
    }

    uint eventSeed = hash32(
        uniforms.step * 747796405u ^ gid.x * 2891336453u ^ gid.y * 1181783497u ^ layer * 277803737u
    );
    bool alive = biomass > 0.018;
    float localOpportunity = saturate(parentC.x * resourceA + parentC.y * resourceB + parentC.z * detritus) * permeability;
    float colonizationChance = bestPressure * localOpportunity *
        (0.00035 + 0.0016 * parentA.z + 0.0011 * parentB.x);

    bool abiogenesis = !alive && bestPressure <= 0.08 && quantumOrder > 0.38 &&
        catalyst > 0.032 && energy > 0.0055 && membrane > 0.0025 &&
        resourceA + resourceB > 0.30 && toxin < 0.72;
    if (abiogenesis) {
        float2 combinedAmplitude = spinor.xy + spinor.zw;
        float inheritedPhase = fract(
            atan2(combinedAmplitude.y, combinedAmplitude.x) / (2.0 * M_PI_F) + 1.0
        );
        float polarization = (probabilityA - probabilityB) / max(probability, 0.0000000001);
        float resourceTotal = max(resourceA + resourceB + detritus, 0.0001);
        geneA = clamp(float4(
            0.54 + quantumOrder * 0.24,
            0.46 + componentCoherence * 0.28,
            0.40 + (1.0 - abs(polarization)) * 0.26,
            0.52 + (1.0 - toxin) * 0.24
        ), 0.0, 1.0);
        geneB = float4(
            0.46 + quantumOrder * 0.22,
            0.008 + (1.0 - componentCoherence) * 0.028,
            0.44 + abs(polarization) * 0.28,
            inheritedPhase
        );
        geneC = clamp(float4(
            resourceA / resourceTotal,
            resourceB / resourceTotal,
            max(detritus / resourceTotal, 0.12),
            0.018 + (1.0 - componentCoherence) * 0.045
        ), 0.0, 1.0);
        biomass = 0.045 + 0.035 * quantumOrder;
        energy = max(energy, biomass * 0.18);
        membrane = max(membrane, biomass * geneA.y * 0.13);
        resourceA = max(0.0, resourceA - biomass * 0.030);
        resourceB = max(0.0, resourceB - biomass * 0.022);
        alive = true;
        born = true;
    }

    if (!alive && bestPressure > 0.08 && random01(eventSeed) < colonizationChance) {
        float mutation = uniforms.mutationScale * (0.003 + 0.24 * parentB.y);
        if (random01(eventSeed + 1u) < 0.012 + parentB.y * 0.22) {
            mutation += 0.055 + 0.045 * random01(eventSeed + 2u);
        }
        float4 deltaA = float4(
            signedRandom(eventSeed + 3u), signedRandom(eventSeed + 4u),
            signedRandom(eventSeed + 5u), signedRandom(eventSeed + 6u)
        ) * mutation;
        float4 deltaB = float4(
            signedRandom(eventSeed + 7u), signedRandom(eventSeed + 8u),
            signedRandom(eventSeed + 9u), signedRandom(eventSeed + 10u)
        ) * mutation;
        float4 deltaC = float4(
            signedRandom(eventSeed + 11u), signedRandom(eventSeed + 12u),
            signedRandom(eventSeed + 13u), signedRandom(eventSeed + 14u)
        ) * mutation;
        geneA = clamp(parentA + deltaA, 0.0, 1.0);
        geneB.xyz = clamp(parentB.xyz + deltaB.xyz, float3(0.0), float3(1.0));
        geneB.y = clamp(geneB.y, 0.001, 0.12);
        geneB.w = fract(parentB.w + deltaB.w * 2.5);
        geneC = clamp(parentC + deltaC, 0.0, 1.0);
        mutationPulse = saturate(mutation * 10.0);
        biomass = 0.075 + 0.055 * random01(eventSeed + 15u);
        energy = biomass * (0.18 + 0.12 * parentA.x);
        membrane = biomass * geneA.y * 0.18;
        resourceA = max(0.0, resourceA - biomass * 0.035);
        resourceB = max(0.0, resourceB - biomass * 0.025);
        alive = true;
        born = true;
    }

    if (alive) {
        float enzymeBudget = geneC.x + geneC.y + geneC.z;
        float interference = 1.0 / (1.0 + 0.85 * max(enzymeBudget - 1.15, 0.0));
        float structuralPermeability = 1.0 / (1.0 + geneA.w * geneA.w * 0.42);
        float uptakeRate = (0.018 + 0.075 * geneA.x) * interference *
            structuralPermeability * (1.0 + catalyst * 0.14);
        float uptakeA = min(resourceA, uniforms.dt * uptakeRate * geneC.x * biomass * resourceA / (0.08 + resourceA));
        float uptakeB = min(resourceB, uniforms.dt * uptakeRate * geneC.y * biomass * resourceB / (0.08 + resourceB));
        float uptakeD = min(detritus, uniforms.dt * uptakeRate * geneC.z * biomass * detritus / (0.06 + detritus));
        resourceA -= uptakeA;
        resourceB -= uptakeB;
        detritus -= uptakeD;
        energy += uptakeA * (0.78 + 0.30 * geneA.w);
        energy += uptakeB * (0.90 + 0.28 * geneA.w);
        energy += uptakeD * (0.62 + 0.22 * geneA.w);
        energy += uniforms.dt * geneC.w * preyOpportunity * 0.0035;

        float maintenance = uniforms.dt * biomass * (
            0.0020 + 0.0015 * geneA.z + 0.0012 * enzymeBudget + 0.0016 * geneC.w +
            0.0030 * neighborOccupancy + 0.0024 * geneA.w * geneA.w +
            0.0026 * geneC.w * geneC.w
        );
        energy = max(energy - maintenance, 0.0);
        float reserve = biomass * (0.025 + 0.10 * geneB.x);
        float habitatCapacity = 1.20 * permeability * structuralPermeability;
        float growth = min(max(energy - reserve, 0.0) * 0.15, max(0.0, habitatCapacity - biomass) * 0.025);
        biomass += growth;
        energy = max(energy - growth * 0.52, 0.0);

        float energyRatio = energy / max(biomass, 0.001);
        float starvation = 1.0 - smoothstep(0.008, 0.08, energyRatio);
        float crowding = smoothstep(0.92, 1.20, biomass);
        float scarcity = 1.0 - smoothstep(0.025, 0.22, resourceA + resourceB + detritus);
        float habitatPressure = pow(neighborOccupancy, 4.0);
        float attackStress = incomingAttack * (1.0 - 0.82 * geneA.w);
        float toxinStress = (toxin + geology.z * 0.42) * (1.0 - 0.88 * geneA.w);
        float collisionStress = obstacle * (0.35 + 0.65 * biomass);
        float deathRate = 0.00025 + 0.0022 * starvation + 0.040 * crowding +
            0.0090 * scarcity + 0.0100 * habitatPressure +
            0.012 * attackStress + 0.012 * toxinStress + 0.018 * collisionStress;
        float decay = min(biomass, uniforms.dt * deathRate * biomass);
        biomass -= decay;
        detritus += decay * 0.90;

        float boundaryExposure = 1.0 - neighborOccupancy;
        float membraneTarget = biomass * geneA.y * boundaryExposure *
            (0.72 + mechanicalActivity * 0.045);
        membrane += uniforms.dt * (0.08 + 0.24 * geneA.w) * (membraneTarget - membrane);
        catalyst += uniforms.dt * biomass * geneA.y * geneA.w * 0.0015;
        toxin += uniforms.dt * biomass * geneC.w * 0.0012;

        float ownMatch = saturate(geneC.x * resourceA + geneC.y * resourceB + geneC.z * detritus);
        float ownPressure = smoothstep(0.035, 0.16, biomass) *
            (0.4 + 0.6 * saturate(energyRatio * 8.0)) * (0.45 + 0.55 * ownMatch);
        float parentDifference = length(geneC - parentC) + 0.5 * length(geneA - parentA);
        float replacementChance = (0.0002 + 0.0025 * parentC.w + 0.0012 * parentA.z) *
            saturate(bestPressure - ownPressure);
        if (parentDifference > 0.16 && bestPressure > ownPressure * 1.18 &&
            random01(eventSeed + 16u) < replacementChance) {
            geneA = mix(geneA, parentA, 0.82);
            geneB = mix(geneB, parentB, 0.82);
            geneB.w = parentB.w;
            geneC = mix(geneC, parentC, 0.82);
            biomass *= 0.88;
            energy = max(energy, parentState.z * 0.20);
            replaced = true;
        }
    }

    if (biomass < 0.004) {
        detritus += biomass * 0.75;
        biomass = 0.0;
        energy = min(energy * (1.0 - uniforms.dt * 0.012), prebioticCapacity);
        membrane *= 1.0 - uniforms.dt * 0.018;
    }
    energy = min(energy, max(biomass * 0.35, prebioticCapacity));

    float eventDecay = exp(-uniforms.dt * 0.035);
    float4 visibleEvents = max(priorEvents * eventDecay + uniforms.dt * 0.012 * eventLaplacian, 0.0);
    float biomassLoss = max(center.y - biomass, 0.0);
    float deathPulse = saturate(biomassLoss * 18.0 + (wasAlive && biomass <= 0.004 ? 1.0 : 0.0));
    float huntingPulse = geneC.w * preyOpportunity * 4.5;
    float conflictPulse = saturate(incomingAttack * 2.6 + huntingPulse + (replaced ? 1.0 : 0.0));
    visibleEvents.x = max(visibleEvents.x, born ? 1.0 : 0.0);
    visibleEvents.y = max(visibleEvents.y, mutationPulse);
    visibleEvents.z = max(visibleEvents.z, conflictPulse);
    visibleEvents.w = max(visibleEvents.w, deathPulse);

    stateOut.write(float4(min(resourceA, 2.0), biomass, energy, min(membrane, 1.5)), gid.xy, layer);
    genomeAOut.write(geneA, gid.xy, layer);
    genomeBOut.write(geneB, gid.xy, layer);
    ecologyOut.write(float4(min(resourceB, 2.0), min(detritus, 2.0), min(toxin, 2.0), min(catalyst, 2.0)), gid.xy, layer);
    genomeCOut.write(geneC, gid.xy, layer);
    eventOut.write(min(visibleEvents, 1.0), gid.xy, layer);
    developmentalOut.write(float4(
        min(extracellularLigands, float2(2.0)),
        min(matrixDensity, 2.0), min(woundCue, 2.0)
    ), gid.xy, layer);
    atomic_store_explicit(
        &cellEnergyExchange[energyTileBase], substrateToFixed(resourceA), memory_order_relaxed
    );
    atomic_store_explicit(
        &cellEnergyExchange[energyTileBase + 1u], substrateToFixed(resourceB), memory_order_relaxed
    );
    atomic_store_explicit(
        &cellEnergyExchange[energyTileBase + 2u], substrateToFixed(detritus), memory_order_relaxed
    );
}

inline float2 damageCenter(uint world, uint generation) {
    uint seed = hash32(world * 0x9e3779b9u + generation * 0x85ebca6bu + 71u);
    return float2(0.2 + 0.6 * random01(seed + 1u), 0.2 + 0.6 * random01(seed + 2u));
}

kernel void damageWorld(
    texture2d_array<float, access::read_write> state [[texture(0)]],
    texture2d_array<float, access::read_write> ecology [[texture(1)]],
    texture2d_array<float, access::read_write> events [[texture(2)]],
    texture2d_array<float, access::read_write> developmentalField [[texture(3)]],
    constant SimulationUniforms& uniforms [[buffer(0)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height || gid.z >= uniforms.worldCount) { return; }
    float2 uv = (float2(gid.xy) + 0.5) / float2(uniforms.width, uniforms.height);
    float radius = 0.065 + 0.025 * random01(hash32(gid.z + uniforms.generation * 31u));
    float impact = 1.0 - smoothstep(
        radius * 0.55, radius,
        length(toroidalDelta(uv, damageCenter(gid.z, uniforms.generation)))
    );
    if (impact <= 0.0) { return; }
    float4 value = state.read(gid.xy, gid.z);
    float removed = value.y * impact * 0.82;
    value.x = min(2.0, value.x + removed * 0.35);
    value.y -= removed;
    value.z *= 1.0 - impact * 0.85;
    value.w *= 1.0 - impact;
    float4 chemistry = ecology.read(gid.xy, gid.z);
    chemistry.y = min(2.0, chemistry.y + removed * 0.88);
    state.write(value, gid.xy, gid.z);
    ecology.write(chemistry, gid.xy, gid.z);
    float4 visibleEvents = events.read(gid.xy, gid.z);
    visibleEvents.w = max(visibleEvents.w, saturate(impact));
    events.write(visibleEvents, gid.xy, gid.z);
    float4 extracellular = developmentalField.read(gid.xy, gid.z);
    extracellular.z *= 1.0 - impact * 0.72;
    extracellular.w = max(extracellular.w, impact);
    developmentalField.write(extracellular, gid.xy, gid.z);
}

kernel void damageOrganismCells(
    device const AgentState* agents [[buffer(0)]],
    device const atomic_uint* agentOccupancy [[buffer(1)]],
    device CellState* cells [[buffer(2)]],
    device const atomic_uint* cellOccupancy [[buffer(3)]],
    device const CellIdentity* cellIdentities [[buffer(4)]],
    device MembraneVertex* membraneVertices [[buffer(5)]],
    constant SimulationUniforms& uniforms [[buffer(6)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= maxCellCount ||
        atomic_load_explicit(&cellOccupancy[gid], memory_order_relaxed) == 0u) { return; }
    uint owner = cellIdentities[gid].owner;
    if (owner >= maxAgentCount ||
        atomic_load_explicit(&agentOccupancy[owner], memory_order_relaxed) == 0u) { return; }
    float2 worldPosition = cellWorldPosition(agents[owner], cells[gid].position, uniforms);
    float radius = 0.065 + 0.025 * random01(hash32(uniforms.generation * 31u));
    float2 fromImpact = signedToroidalDelta(
        damageCenter(0u, uniforms.generation), worldPosition
    );
    float impact = 1.0 - smoothstep(radius * 0.42, radius, length(fromImpact));
    if (impact <= 0.0) { return; }

    CellState cell = cells[gid];
    cell.physiology.w = clamp(cell.physiology.w - impact * 0.28, 0.0, 1.0);
    cell.signals.z = saturate(cell.signals.z + impact * 0.52);
    cell.signals.w = saturate(cell.signals.w + impact * 0.055);
    cell.signaling.x = saturate(cell.signaling.x + impact * 0.34);
    cell.tissueForce.z = max(cell.tissueForce.z, impact * 0.28);
    float2 impactDirectionWorld = length(fromImpact) > 0.000001
        ? normalize(fromImpact) : float2(1.0, 0.0);
    float2 impactDirectionLocal = rotateWorldToTissue(
        impactDirectionWorld, agents[owner]
    );
    uint membraneBase = gid * membraneVertexCount;
    for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
        MembraneVertex membranePoint = membraneVertices[membraneBase + vertexIndex];
        float directionalExposure = saturate(
            0.35 + 0.65 * dot(normalize(membranePoint.position + float2(0.000001)),
                -impactDirectionLocal)
        );
        float localDamage = impact * directionalExposure;
        membranePoint.mechanics.y = clamp(
            membranePoint.mechanics.y - localDamage * 0.38, 0.0, 1.0
        );
        membranePoint.mechanics.z += localDamage * 0.22;
        membranePoint.velocity += impactDirectionLocal * localDamage * 0.00032;
        membraneVertices[membraneBase + vertexIndex] = membranePoint;
    }
    cells[gid] = cell;
}

kernel void markDamagedComponents(
    device AgentState* agents [[buffer(0)]],
    device const atomic_uint* occupancy [[buffer(1)]],
    device const CellState* cells [[buffer(2)]],
    device const atomic_uint* cellOccupancy [[buffer(3)]],
    device const CellIdentity* cellIdentities [[buffer(4)]],
    device const atomic_uint* ownerCellHeads [[buffer(5)]],
    device const uint* ownerCellNext [[buffer(6)]],
    constant SimulationUniforms& uniforms [[buffer(7)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= maxAgentCount ||
        atomic_load_explicit(&occupancy[gid], memory_order_relaxed) == 0u) { return; }
    AgentState agent = agents[gid];
    float radius = 0.065 + 0.025 * random01(hash32(uniforms.generation * 31u));
    float2 center = damageCenter(0u, uniforms.generation);
    bool struck = false;
    uint cellIndex = atomic_load_explicit(
        &ownerCellHeads[gid], memory_order_relaxed
    );
    for (uint visited = 0u;
         visited < maxCellCount && cellIndex != emptySpatialHashEntry;
         ++visited) {
        if (cellIndex >= maxCellCount) { break; }
        uint nextCell = ownerCellNext[cellIndex];
        if (atomic_load_explicit(&cellOccupancy[cellIndex], memory_order_relaxed) != 0u &&
            cellIdentities[cellIndex].owner == gid) {
            float2 worldPosition = cellWorldPosition(
                agent, cells[cellIndex].position, uniforms
            );
            float impact = 1.0 - smoothstep(
                radius * 0.42, radius,
                length(signedToroidalDelta(center, worldPosition))
            );
            if (impact > 0.0) {
                struck = true;
                break;
            }
        }
        cellIndex = nextCell;
    }
    if (!struck) { return; }
    agent.componentFlags = (agent.componentFlags | componentChallengedFlag) &
        ~componentHomeostaticFlag;
    // This component-local coordinate stores the recovery observation window.
    // It affects no cell dynamics or survival decision.
    agent.tissueKinematics.w = 1.0;
    agents[gid] = agent;
}

kernel void selectRegenerativeQualificationTarget(
    device AgentState* agents [[buffer(0)]],
    device const atomic_uint* agentOccupancy [[buffer(1)]],
    device const atomic_uint* cellOccupancy [[buffer(2)]],
    device const CellIdentity* cellIdentities [[buffer(3)]],
    device const atomic_uint* ownerCellHeads [[buffer(4)]],
    device uint* targetState [[buffer(5)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid != 0u) { return; }
    uint selectedOwner = maxAgentCount;
    uint selectedCell = maxCellCount;
    uint selectedBirthID = 0xffffffffu;
    for (uint owner = 0u; owner < maxAgentCount; ++owner) {
        if (atomic_load_explicit(&agentOccupancy[owner], memory_order_relaxed) == 0u) {
            continue;
        }
        AgentState candidate = agents[owner];
        bool eligible = candidate.generation > 0u &&
            (candidate.componentFlags & componentRegeneratedFlag) != 0u &&
            (candidate.componentFlags & componentMulticellularFlag) != 0u;
        if (!eligible) { continue; }
        uint anchorCell = atomic_load_explicit(
            &ownerCellHeads[owner], memory_order_relaxed
        );
        if (anchorCell >= maxCellCount ||
            atomic_load_explicit(&cellOccupancy[anchorCell], memory_order_relaxed) == 0u ||
            cellIdentities[anchorCell].owner != owner) { continue; }
        if (candidate.birthID < selectedBirthID ||
            (candidate.birthID == selectedBirthID && owner < selectedOwner)) {
            selectedOwner = owner;
            selectedCell = anchorCell;
            selectedBirthID = candidate.birthID;
        }
    }
    targetState[0] = selectedOwner;
    targetState[1] = selectedCell;
    targetState[2] = selectedBirthID;
    targetState[3] = selectedOwner < maxAgentCount ? 1u : 0u;
    if (selectedOwner < maxAgentCount) {
        AgentState selected = agents[selectedOwner];
        selected.componentFlags |= componentQualificationTargetFlag;
        agents[selectedOwner] = selected;
    }
}

kernel void damageSelectedTargetWorld(
    texture2d_array<float, access::read_write> state [[texture(0)]],
    texture2d_array<float, access::read_write> ecology [[texture(1)]],
    texture2d_array<float, access::read_write> events [[texture(2)]],
    texture2d_array<float, access::read_write> developmentalField [[texture(3)]],
    device const uint* targetState [[buffer(0)]],
    device const AgentState* agents [[buffer(1)]],
    device const CellState* cells [[buffer(2)]],
    constant SimulationUniforms& uniforms [[buffer(3)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height || gid.z >= uniforms.worldCount ||
        targetState[3] != 2u || targetState[0] >= maxAgentCount ||
        targetState[1] >= maxCellCount) { return; }
    float2 center = cellWorldPosition(
        agents[targetState[0]], cells[targetState[1]].position, uniforms
    );
    float2 uv = (float2(gid.xy) + 0.5) / float2(uniforms.width, uniforms.height);
    float radius = 0.072;
    float impact = 1.0 - smoothstep(
        radius * 0.50, radius, length(toroidalDelta(uv, center))
    );
    if (impact <= 0.0) { return; }
    float4 value = state.read(gid.xy, gid.z);
    float removed = value.y * impact * 0.82;
    value.x = min(2.0, value.x + removed * 0.35);
    value.y -= removed;
    value.z *= 1.0 - impact * 0.85;
    value.w *= 1.0 - impact;
    float4 chemistry = ecology.read(gid.xy, gid.z);
    chemistry.y = min(2.0, chemistry.y + removed * 0.88);
    state.write(value, gid.xy, gid.z);
    ecology.write(chemistry, gid.xy, gid.z);
    float4 visibleEvents = events.read(gid.xy, gid.z);
    visibleEvents.w = max(visibleEvents.w, saturate(impact));
    events.write(visibleEvents, gid.xy, gid.z);
    float4 extracellular = developmentalField.read(gid.xy, gid.z);
    extracellular.z *= 1.0 - impact * 0.72;
    extracellular.w = max(extracellular.w, impact);
    developmentalField.write(extracellular, gid.xy, gid.z);
}

kernel void damageSelectedTargetCells(
    device const AgentState* agents [[buffer(0)]],
    device CellState* cells [[buffer(1)]],
    device const atomic_uint* cellOccupancy [[buffer(2)]],
    device const CellIdentity* cellIdentities [[buffer(3)]],
    device MembraneVertex* membraneVertices [[buffer(4)]],
    device const uint* targetState [[buffer(5)]],
    constant SimulationUniforms& uniforms [[buffer(6)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= maxCellCount || targetState[3] != 2u ||
        targetState[0] >= maxAgentCount || targetState[1] >= maxCellCount ||
        atomic_load_explicit(&cellOccupancy[gid], memory_order_relaxed) == 0u ||
        cellIdentities[gid].owner != targetState[0]) { return; }
    uint owner = targetState[0];
    float2 center = cellWorldPosition(
        agents[owner], cells[targetState[1]].position, uniforms
    );
    float2 worldPosition = cellWorldPosition(agents[owner], cells[gid].position, uniforms);
    float2 fromImpact = signedToroidalDelta(center, worldPosition);
    float radius = 0.072;
    float impact = 1.0 - smoothstep(radius * 0.42, radius, length(fromImpact));
    if (impact <= 0.0) { return; }

    CellState cell = cells[gid];
    cell.physiology.w = clamp(cell.physiology.w - impact * 0.28, 0.0, 1.0);
    cell.signals.z = saturate(cell.signals.z + impact * 0.52);
    cell.signals.w = saturate(cell.signals.w + impact * 0.055);
    cell.signaling.x = saturate(cell.signaling.x + impact * 0.34);
    cell.tissueForce.z = max(cell.tissueForce.z, impact * 0.28);
    float2 impactDirectionWorld = length(fromImpact) > 0.000001
        ? normalize(fromImpact) : float2(1.0, 0.0);
    float2 impactDirectionLocal = rotateWorldToTissue(
        impactDirectionWorld, agents[owner]
    );
    uint membraneBase = gid * membraneVertexCount;
    for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
        MembraneVertex membranePoint = membraneVertices[membraneBase + vertexIndex];
        float directionalExposure = saturate(
            0.35 + 0.65 * dot(normalize(membranePoint.position + float2(0.000001)),
                -impactDirectionLocal)
        );
        float localDamage = impact * directionalExposure;
        membranePoint.mechanics.y = clamp(
            membranePoint.mechanics.y - localDamage * 0.38, 0.0, 1.0
        );
        membranePoint.mechanics.z += localDamage * 0.22;
        membranePoint.velocity += impactDirectionLocal * localDamage * 0.00032;
        membraneVertices[membraneBase + vertexIndex] = membranePoint;
    }
    cells[gid] = cell;
}

kernel void markSelectedTargetChallenged(
    device AgentState* agents [[buffer(0)]],
    device const atomic_uint* agentOccupancy [[buffer(1)]],
    device uint* targetState [[buffer(2)]],
    device const atomic_uint* cellOccupancy [[buffer(3)]],
    device const CellIdentity* cellIdentities [[buffer(4)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid != 0u || targetState[3] != 1u || targetState[0] >= maxAgentCount ||
        targetState[1] >= maxCellCount) { return; }
    uint owner = targetState[0];
    if (atomic_load_explicit(&agentOccupancy[owner], memory_order_relaxed) == 0u ||
        agents[owner].birthID != targetState[2] ||
        atomic_load_explicit(
            &cellOccupancy[targetState[1]], memory_order_relaxed
        ) == 0u || cellIdentities[targetState[1]].owner != owner) {
        targetState[3] = 0u;
        return;
    }
    AgentState agent = agents[owner];
    agent.componentFlags = (agent.componentFlags | componentQualificationTargetFlag |
        componentChallengedFlag) & ~componentHomeostaticFlag;
    agent.tissueKinematics.w = 1.0;
    agents[owner] = agent;
    targetState[3] = 2u;
}

kernel void measureQualificationTarget(
    device const AgentState* agents [[buffer(0)]],
    device const atomic_uint* agentOccupancy [[buffer(1)]],
    device const CellAggregate* aggregates [[buffer(2)]],
    device const uint* targetState [[buffer(3)]],
    device const CellState* cells [[buffer(4)]],
    device const atomic_uint* cellOccupancy [[buffer(5)]],
    device const CellIdentity* cellIdentities [[buffer(6)]],
    device QualificationTargetMeasurement* measurement [[buffer(7)]],
    texture2d_array<float, access::read> developmentalField [[texture(0)]],
    constant SimulationUniforms& uniforms [[buffer(8)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid != 0u) { return; }
    QualificationTargetMeasurement output;
    output.identity = uint4(0xffffffffu, 0xffffffffu, 0u, 0u);
    output.developmental = float4(0.0);
    uint owner = targetState[0];
    if (targetState[3] != 0u && owner < maxAgentCount &&
        atomic_load_explicit(&agentOccupancy[owner], memory_order_relaxed) != 0u &&
        agents[owner].birthID == targetState[2] &&
        (agents[owner].componentFlags & componentQualificationTargetFlag) != 0u) {
        AgentState agent = agents[owner];
        float2 measurementPosition = agent.position;
        uint anchorCell = targetState[1];
        if (anchorCell < maxCellCount &&
            atomic_load_explicit(&cellOccupancy[anchorCell], memory_order_relaxed) != 0u &&
            cellIdentities[anchorCell].owner == owner) {
            measurementPosition = cellWorldPosition(
                agent, cells[anchorCell].position, uniforms
            );
        }
        uint2 coordinate = min(
            uint2(measurementPosition * float2(uniforms.width, uniforms.height)),
            uint2(uniforms.width - 1u, uniforms.height - 1u)
        );
        output.identity = uint4(
            owner, agent.birthID,
            uint(max(aggregates[owner].physiology.x, 0.0)), agent.componentFlags
        );
        output.developmental = developmentalField.read(coordinate, 0);
    }
    measurement[0] = output;
}

kernel void applyBrush(
    texture2d_array<float, access::read_write> state [[texture(0)]],
    texture2d_array<float, access::read_write> genomeA [[texture(1)]],
    texture2d_array<float, access::read_write> genomeB [[texture(2)]],
    texture2d_array<float, access::read_write> ecology [[texture(3)]],
    texture2d_array<float, access::read_write> genomeC [[texture(4)]],
    texture2d_array<float, access::read_write> events [[texture(5)]],
    constant SimulationUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height) { return; }
    float2 uv = (float2(gid) + 0.5) / float2(uniforms.width, uniforms.height);
    float influence = 1.0 - smoothstep(
        uniforms.brushRadius * 0.35, uniforms.brushRadius,
        length(toroidalDelta(uv, uniforms.brushPosition))
    );
    if (influence <= 0.0) { return; }

    uint colonySeed = hash32(
        uint(uniforms.brushPosition.x * 65535.0) ^
        uint(uniforms.brushPosition.y * 65535.0) * 19349663u ^ uniforms.step * 83492791u
    );
    float4 a = traitA(colonySeed & 255u, colonySeed);
    float4 b = traitB(colonySeed & 255u, colonySeed);
    float4 c = traitC(colonySeed & 255u, colonySeed);
    float4 cell = state.read(gid, 0);
    float seededBiomass = influence * uniforms.brushStrength * 0.52;
    if (seededBiomass > cell.y) {
        cell.y = seededBiomass;
        cell.z = seededBiomass * (0.18 + 0.12 * a.x);
        cell.w = seededBiomass * a.y * 0.14;
        genomeA.write(a, gid, 0);
        genomeB.write(b, gid, 0);
        genomeC.write(c, gid, 0);
        float4 visibleEvents = events.read(gid, 0);
        visibleEvents.x = max(visibleEvents.x, influence);
        visibleEvents.y = max(visibleEvents.y, influence * 0.85);
        events.write(visibleEvents, gid, 0);
    }
    state.write(cell, gid, 0);
}

inline void addMetric(
    threadgroup atomic_uint* metrics,
    uint metric,
    float value,
    uint laneIndex
) {
    uint fixedValue = uint(clamp(value, 0.0, 1.0) * metricScale);
    uint simdValue = simd_sum(fixedValue);
    if (laneIndex == 0u) {
        atomic_fetch_add_explicit(&metrics[metric], simdValue, memory_order_relaxed);
    }
}

inline void addBinnedMetric(threadgroup atomic_uint* metrics, uint metric, float value) {
    uint fixedValue = uint(clamp(value, 0.0, 1.0) * metricScale);
    atomic_fetch_add_explicit(&metrics[metric], fixedValue, memory_order_relaxed);
}

kernel void measureWorld(
    texture2d_array<float, access::read> state [[texture(0)]],
    texture2d_array<float, access::read> checkpoint [[texture(1)]],
    texture2d_array<float, access::read> genomeA [[texture(2)]],
    texture2d_array<float, access::read> ecology [[texture(3)]],
    texture2d_array<float, access::read> genomeB [[texture(4)]],
    texture2d_array<float, access::read> genomeC [[texture(5)]],
    texture2d_array<float, access::read> environment [[texture(6)]],
    texture2d_array<float, access::read> mechanicalField [[texture(7)]],
    texture2d<float, access::read> quantum [[texture(8)]],
    device atomic_uint* metrics [[buffer(0)]],
    constant SimulationUniforms& uniforms [[buffer(1)]],
    uint3 gid [[thread_position_in_grid]],
    uint threadIndex [[thread_index_in_threadgroup]],
    uint laneIndex [[thread_index_in_simdgroup]],
    uint3 threadsPerThreadgroup [[threads_per_threadgroup]]
) {
    threadgroup atomic_uint groupMetrics[metricCount];
    uint groupThreadCount = threadsPerThreadgroup.x * threadsPerThreadgroup.y * threadsPerThreadgroup.z;
    for (uint metric = threadIndex; metric < metricCount; metric += groupThreadCount) {
        atomic_store_explicit(&groupMetrics[metric], 0u, memory_order_relaxed);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (gid.x >= uniforms.width || gid.y >= uniforms.height || gid.z >= uniforms.worldCount) { return; }
    int2 p = int2(gid.xy);
    uint layer = gid.z;
    float4 current = state.read(gid.xy, layer);
    float4 previous = checkpoint.read(gid.xy, layer);
    float active = smoothstep(0.018, 0.12, current.y);
    float activity = min(abs(current.y - previous.y) * 3.0, 1.0);

    float leftBio = state.read(uint2(wrapped(p + int2(-1, 0), uniforms.width, uniforms.height)), layer).y;
    float rightBio = state.read(uint2(wrapped(p + int2(1, 0), uniforms.width, uniforms.height)), layer).y;
    float downBio = state.read(uint2(wrapped(p + int2(0, -1), uniforms.width, uniforms.height)), layer).y;
    float upBio = state.read(uint2(wrapped(p + int2(0, 1), uniforms.width, uniforms.height)), layer).y;
    float boundary = min(length(float2(rightBio - leftBio, upBio - downBio)) * 2.6, 1.0);
    float coherence = boundary * min(current.w * 3.0, 1.0);

    float medium = 0.2 * (current.y +
        state.read(uint2(wrapped(p + int2(3, 0), uniforms.width, uniforms.height)), layer).y +
        state.read(uint2(wrapped(p + int2(-3, 0), uniforms.width, uniforms.height)), layer).y +
        state.read(uint2(wrapped(p + int2(0, 3), uniforms.width, uniforms.height)), layer).y +
        state.read(uint2(wrapped(p + int2(0, -3), uniforms.width, uniforms.height)), layer).y);
    float coarse = 0.2 * (current.y +
        state.read(uint2(wrapped(p + int2(9, 0), uniforms.width, uniforms.height)), layer).y +
        state.read(uint2(wrapped(p + int2(-9, 0), uniforms.width, uniforms.height)), layer).y +
        state.read(uint2(wrapped(p + int2(0, 9), uniforms.width, uniforms.height)), layer).y +
        state.read(uint2(wrapped(p + int2(0, -9), uniforms.width, uniforms.height)), layer).y);
    float multiscale = min((abs(current.y - medium) + abs(medium - coarse)) * 2.4, 1.0);

    float2 uv = (float2(gid.xy) + 0.5) / float2(uniforms.width, uniforms.height);
    float radius = 0.065 + 0.025 * random01(hash32(layer + uniforms.generation * 31u));
    float inDamage = length(toroidalDelta(uv, damageCenter(layer, uniforms.generation))) < radius ? 1.0 : 0.0;
    float recoveryTarget = min(previous.y, 1.0) * inDamage;
    float recovered = min(current.y, previous.y) * inDamage;

    float4 gene = genomeA.read(gid.xy, layer);
    float4 neighborGene = genomeA.read(uint2(wrapped(p + int2(1, 0), uniforms.width, uniforms.height)), layer);
    float4 niche = genomeC.read(gid.xy, layer);
    float4 neighborNiche = genomeC.read(uint2(wrapped(p + int2(1, 0), uniforms.width, uniforms.height)), layer);
    float geneDifference = min(length(gene - neighborGene) * 0.75, 1.0) * active;
    float nicheDifference = min(length(niche - neighborNiche) * 0.80, 1.0) * active;
    float enzymeTotal = max(niche.x + niche.y + niche.z, 0.0001);
    float3 enzymeShare = niche.xyz / enzymeTotal;
    float specialization = saturate((dot(enzymeShare, enzymeShare) - (1.0 / 3.0)) * 1.5) * active;
    float4 localChemistry = ecology.read(gid.xy, layer);
    float4 localGeology = environment.read(gid.xy, layer);
    float2 localSubstrateDrive = substrateForcing(uv, localGeology, uniforms.step);
    float substrateDrive = (localSubstrateDrive.x + localSubstrateDrive.y) * 0.5;
    float barrierFraction = smoothstep(0.30, 0.82, localGeology.w);
    float4 localMechanical = mechanicalField.read(gid.xy, layer);
    float environmentalDrive = saturate(
        environmentalMechanicalAmplitude(localGeology) * 8.0 +
        length(localMechanical.zw) * 42.0
    );
    float trophicActivity = active * saturate(niche.w * 0.7 + niche.z * localChemistry.y * 0.8 + localChemistry.z * 0.2);
    uint lineageBin = min(uint(fract(genomeB.read(gid.xy, layer).w) * 16.0), 15u);
    uint2 quantumCoordinate = min(
        gid.xy * quantumGridSize / uint2(uniforms.width, uniforms.height),
        uint2(quantumGridSize - 1u)
    );
    float4 spinor = quantum.read(quantumCoordinate);
    float probabilityA = dot(spinor.xy, spinor.xy);
    float probabilityB = dot(spinor.zw, spinor.zw);
    float probability = probabilityA + probabilityB;
    float quantumDensity = 1.0 - exp(-probability * 285000.0);
    float componentCoherence = abs(dot(spinor.xy, spinor.zw)) /
        max(sqrt(probabilityA * probabilityB), 0.0000000001);
    float quantumOrder = quantumDensity *
        (0.24 + 0.76 * saturate(componentCoherence));
    float obstacle = smoothstep(0.48, 0.84, localGeology.w);
    float permeability = 1.0 - obstacle * 0.88;
    float resourceA = max(current.x, 0.0);
    float resourceB = max(localChemistry.x, 0.0);
    float detritus = max(localChemistry.y, 0.0);
    float toxin = max(localChemistry.z, 0.0);
    float catalyst = max(localChemistry.w, 0.0);
    float mechanicalActivity = saturate(
        length(localMechanical.xy) * 18.0 + length(localMechanical.zw) * 75.0
    );
    float chemicalAffinity = sqrt(saturate(resourceA) * saturate(resourceB)) *
        permeability * (1.0 - saturate(toxin));
    float catalystProduction = uniforms.dt * chemicalAffinity *
        (quantumOrder * 0.0090 + mechanicalActivity * 0.00032);
    float energyProduction = uniforms.dt * catalyst * permeability *
        (quantumOrder * (0.015 + 0.035 * saturate(resourceA + resourceB)) +
            mechanicalActivity * 0.00018);
    float prebioticOrder = smoothstep(0.018, 0.065, catalyst) *
        smoothstep(0.002, 0.015, max(current.z, 0.0)) * quantumOrder;
    float membraneTarget = prebioticOrder * 0.035;
    float membraneAssembly = max(
        uniforms.dt * 0.22 * (membraneTarget - max(current.w, 0.0)),
        0.0
    );
    float mineralization = min(
        detritus,
        uniforms.dt * detritus * (0.00035 + catalyst * 0.0032) *
            permeability * (1.0 - saturate(toxin) * 0.72)
    );

    addMetric(groupMetrics, 0, min(current.y, 1.0), laneIndex);
    addMetric(groupMetrics, 1, min(current.x * 0.5, 1.0), laneIndex);
    addMetric(groupMetrics, 2, min(current.z, 1.0), laneIndex);
    addMetric(groupMetrics, 3, active, laneIndex);
    addMetric(groupMetrics, 4, activity, laneIndex);
    addMetric(groupMetrics, 5, coherence, laneIndex);
    addMetric(groupMetrics, 6, multiscale * active, laneIndex);
    addMetric(groupMetrics, 7, recovered, laneIndex);
    addMetric(groupMetrics, 8, recoveryTarget, laneIndex);
    addMetric(groupMetrics, 9, geneDifference, laneIndex);
    addMetric(groupMetrics, 10, uv.x * min(current.y, 1.0), laneIndex);
    addMetric(groupMetrics, 11, uv.y * min(current.y, 1.0), laneIndex);
    addMetric(groupMetrics, 12, nicheDifference, laneIndex);
    addMetric(groupMetrics, 13, specialization, laneIndex);
    addMetric(groupMetrics, 14, trophicActivity, laneIndex);
    addMetric(groupMetrics, 15, active * saturate(current.x), laneIndex);
    addMetric(groupMetrics, 16, substrateDrive, laneIndex);
    addMetric(groupMetrics, 17, saturate(localChemistry.y), laneIndex);
    addMetric(groupMetrics, 18, barrierFraction, laneIndex);
    addMetric(groupMetrics, 19, environmentalDrive, laneIndex);
    addBinnedMetric(groupMetrics, 20 + lineageBin, active);
    addMetric(groupMetrics, 36, saturate(resourceB), laneIndex);
    addMetric(groupMetrics, 37, saturate(catalyst), laneIndex);
    addMetric(groupMetrics, 38, saturate(toxin), laneIndex);
    addMetric(groupMetrics, 39, saturate(current.w), laneIndex);
    addMetric(groupMetrics, 40, quantumOrder, laneIndex);
    addMetric(groupMetrics, 41, chemicalAffinity, laneIndex);
    addMetric(groupMetrics, 42, catalystProduction * 100.0, laneIndex);
    addMetric(groupMetrics, 43, energyProduction * 100.0, laneIndex);
    addMetric(groupMetrics, 44, membraneAssembly * 100.0, laneIndex);
    addMetric(groupMetrics, 45, mineralization * 100.0, laneIndex);

    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint metric = threadIndex; metric < metricCount; metric += groupThreadCount) {
        atomic_fetch_add_explicit(
            &metrics[layer * metricCount + metric],
            atomic_load_explicit(&groupMetrics[metric], memory_order_relaxed),
            memory_order_relaxed
        );
    }
}

inline CellState emptyCell() {
    CellState cell;
    cell.position = float2(0.0);
    cell.velocity = float2(0.0);
    cell.physiology = float4(0.0);
    cell.phenotype = float4(0.0);
    cell.signals = float4(0.0);
    cell.interaction = float4(0.0);
    cell.dynamics = float4(0.0);
    cell.mechanics = float4(0.0);
    cell.energetics = float4(0.0);
    cell.regulation = float4(0.0);
    cell.regulationB = float4(0.0);
    cell.resonance = float4(0.0);
    cell.membrane = float4(0.0);
    cell.signaling = float4(0.0);
    cell.signalCausality = float4(0.0);
    cell.tissueGeometry = float4(0.0);
    cell.tissueForce = float4(0.0);
    cell.environment = float4(0.0);
    cell.development = float4(1.0, 0.0, 0.5, 0.0);
    return cell;
}

inline MembraneVertex emptyMembraneVertex() {
    MembraneVertex state;
    state.position = float2(0.0);
    state.velocity = float2(0.0);
    state.mechanics = float4(0.0);
    return state;
}

inline CellState founderCell(AgentState agent, ResonanceGenome resonanceGenome, uint seed) {
    CellState cell;
    cell.position = float2(0.0);
    cell.velocity = float2(0.0);
    cell.physiology = float4(
        clamp(0.70 + agent.energy * 0.16 + signedRandom(seed + 23u) * 0.025, 0.58, 0.94),
        clamp(0.72 + agent.biomass * 0.16, 0.72, 0.90),
        0.18 + random01(seed + 29u) * 0.12,
        clamp(0.76 + agent.geneA.w * 0.20, 0.70, 0.98)
    );
    cell.phenotype = float4(
        0.38 + agent.geneA.y * 0.18,
        0.20 + agent.geneA.z * 0.16,
        0.28 + agent.geneC.x * 0.28,
        0.28 + agent.geneC.y * 0.28
    );
    cell.signals = float4(0.52, 0.48, 0.02 + random01(seed + 31u) * 0.025, 0.0);
    cell.interaction = float4(0.0);
    float naturalFrequency = resonanceGenome.mechanics.x;
    cell.dynamics = float4(
        -0.28 + signedRandom(seed + 37u) * 0.04,
        0.12 + random01(seed + 41u) * 0.03,
        fract(agent.geneB.w + signedRandom(seed + 43u) * 0.045),
        naturalFrequency * (0.80 + random01(seed + 47u) * 0.40)
    );
    cell.mechanics = float4(0.0, 0.0, 0.0, 0.92);
    cell.energetics = float4(0.0);
    cell.regulation = float4(0.54, 0.52, 0.46, 0.56);
    cell.regulationB = float4(0.48, 0.42, 0.58, 0.44);
    cell.resonance = float4(0.0);
    cell.membrane = float4(M_PI_F * 0.0144, 2.0 * M_PI_F * 0.12, 1.0, 0.0);
    cell.signaling = float4(
        0.025 + random01(seed + 53u) * 0.012,
        0.018 + random01(seed + 59u) * 0.010,
        0.0,
        0.0
    );
    cell.signalCausality = float4(0.0);
    cell.tissueGeometry = float4(1.0, 0.0, 1.0, 0.0);
    cell.tissueForce = float4(0.0);
    cell.environment = float4(0.0);
    float founderPolarityAngle = random01(seed + 61u) * 2.0 * M_PI_F;
    cell.development = float4(
        cos(founderPolarityAngle), sin(founderPolarityAngle), 0.5, 0.0
    );
    return cell;
}

inline uint claimFreeCell(
    device atomic_uint* cellOccupancy,
    uint seed
) {
    uint searchStart = hash32(seed) % maxCellCount;
    for (uint offset = 0u; offset < maxCellCount; ++offset) {
        uint candidate = (searchStart + offset) % maxCellCount;
        uint expected = 0u;
        if (atomic_compare_exchange_weak_explicit(
            &cellOccupancy[candidate], &expected, 1u,
            memory_order_relaxed, memory_order_relaxed
        )) { return candidate; }
    }
    return maxCellCount;
}

inline bool programSlotMatches(
    device const ProgramSlotState* programSlots,
    uint programIndex,
    uint programGeneration
) {
    return programIndex < maxHeritableProgramCount && programGeneration != 0u &&
        atomic_load_explicit(
            &programSlots[programIndex].occupied, memory_order_relaxed
        ) == 1u &&
        atomic_load_explicit(
            &programSlots[programIndex].generation, memory_order_relaxed
        ) == programGeneration;
}

inline uint claimHeritableProgram(
    device ProgramSlotState* programSlots,
    device atomic_uint* identityCounters,
    uint seed,
    thread uint& programGeneration
) {
    uint searchStart = hash32(seed) % maxHeritableProgramCount;
    for (uint offset = 0u; offset < maxHeritableProgramCount; ++offset) {
        uint candidate = (searchStart + offset) % maxHeritableProgramCount;
        uint expected = 0u;
        if (atomic_compare_exchange_weak_explicit(
            &programSlots[candidate].occupied, &expected, 2u,
            memory_order_relaxed, memory_order_relaxed
        )) {
            uint nextGeneration = atomic_fetch_add_explicit(
                &programSlots[candidate].generation, 1u, memory_order_relaxed
            ) + 1u;
            if (nextGeneration == 0u) {
                atomic_store_explicit(
                    &programSlots[candidate].generation, 1u, memory_order_relaxed
                );
                nextGeneration = 1u;
            }
            atomic_store_explicit(
                &programSlots[candidate].referenceCount, 0u, memory_order_relaxed
            );
            programSlots[candidate].lineageHash = 0u;
            atomic_store_explicit(
                &programSlots[candidate].mutationHazard,
                hash32(seed ^ nextGeneration * 0x9e3779b9u),
                memory_order_relaxed
            );
            programSlots[candidate].mutationHazardPadding0 = 0u;
            programSlots[candidate].mutationHazardPadding1 = 0u;
            programSlots[candidate].mutationHazardPadding2 = 0u;
            atomic_fetch_add_explicit(&identityCounters[4], 1u, memory_order_relaxed);
            programGeneration = nextGeneration;
            return candidate;
        }
    }
    programGeneration = 0u;
    return maxHeritableProgramCount;
}

inline void publishHeritableProgram(
    device ProgramSlotState* programSlots,
    uint programIndex,
    uint lineageHash
) {
    if (programIndex >= maxHeritableProgramCount) { return; }
    programSlots[programIndex].lineageHash = lineageHash;
    atomic_store_explicit(
        &programSlots[programIndex].occupied, 1u, memory_order_relaxed
    );
}

inline bool retainHeritableProgram(
    device ProgramSlotState* programSlots,
    uint programIndex,
    uint programGeneration
) {
    if (!programSlotMatches(programSlots, programIndex, programGeneration)) { return false; }
    atomic_fetch_add_explicit(
        &programSlots[programIndex].referenceCount, 1u, memory_order_relaxed
    );
    return true;
}

inline void releaseHeritableProgram(
    device ProgramSlotState* programSlots,
    device atomic_uint* identityCounters,
    uint programIndex,
    uint programGeneration
) {
    if (!programSlotMatches(programSlots, programIndex, programGeneration)) { return; }
    uint references = atomic_load_explicit(
        &programSlots[programIndex].referenceCount, memory_order_relaxed
    );
    if (references == 0u) { return; }
    uint previous = atomic_fetch_sub_explicit(
        &programSlots[programIndex].referenceCount, 1u, memory_order_relaxed
    );
    if (previous == 1u) {
        uint expected = 1u;
        if (atomic_compare_exchange_weak_explicit(
            &programSlots[programIndex].occupied, &expected, 0u,
            memory_order_relaxed, memory_order_relaxed
        )) {
            atomic_fetch_sub_explicit(&identityCounters[4], 1u, memory_order_relaxed);
        }
    }
}

inline void abandonHeritableProgram(
    device ProgramSlotState* programSlots,
    device atomic_uint* identityCounters,
    uint programIndex
) {
    if (programIndex >= maxHeritableProgramCount) { return; }
    uint occupied = atomic_exchange_explicit(
        &programSlots[programIndex].occupied, 0u, memory_order_relaxed
    );
    atomic_store_explicit(
        &programSlots[programIndex].referenceCount, 0u, memory_order_relaxed
    );
    atomic_store_explicit(
        &programSlots[programIndex].mutationHazard, 0u, memory_order_relaxed
    );
    if (occupied != 0u) {
        atomic_fetch_sub_explicit(&identityCounters[4], 1u, memory_order_relaxed);
    }
}

inline bool accrueProgramMutationHazard(
    device ProgramSlotState* programSlots,
    uint programIndex,
    uint programGeneration,
    float probability
) {
    if (!programSlotMatches(programSlots, programIndex, programGeneration)) {
        return false;
    }
    uint increment = uint(clamp(probability, 0.0, 0.99999994) * 4294967295.0);
    if (increment == 0u) { return false; }
    uint previous = atomic_fetch_add_explicit(
        &programSlots[programIndex].mutationHazard, increment, memory_order_relaxed
    );
    uint accumulated = previous + increment;
    return accumulated < previous;
}

inline uint substrateToFixed(float value) {
    return uint(clamp(value, 0.0, 2.0) * float(substrateFixedScale));
}

inline float substrateFromFixed(uint value) {
    return float(value) / float(substrateFixedScale);
}

inline float claimSubstrate(
    device atomic_uint* reservoir,
    float requested
) {
    uint requestedFixed = substrateToFixed(requested);
    if (requestedFixed == 0u) { return 0.0; }
    uint available = atomic_load_explicit(reservoir, memory_order_relaxed);
    for (uint attempt = 0u; attempt < 32u && available > 0u; ++attempt) {
        uint claimed = min(available, requestedFixed);
        uint expected = available;
        if (atomic_compare_exchange_weak_explicit(
            reservoir, &expected, available - claimed,
            memory_order_relaxed, memory_order_relaxed
        )) {
            return substrateFromFixed(claimed);
        }
        available = expected;
    }
    return 0.0;
}

inline void addEnergyAudit(
    device atomic_int* energyAudit,
    uint channel,
    float value
) {
    int fixed = int(clamp(
        value * float(energyAuditScale), -134217728.0, 134217728.0
    ));
    atomic_fetch_add_explicit(&energyAudit[channel], fixed, memory_order_relaxed);
}

inline void addEnergyExchange(
    device atomic_uint* cellEnergyExchange,
    uint tileBase,
    uint channel,
    float value
) {
    uint fixed = substrateToFixed(value);
    if (fixed > 0u) {
        atomic_fetch_add_explicit(
            &cellEnergyExchange[tileBase + channel], fixed, memory_order_relaxed
        );
    }
}

inline AgentState mutateCellProgram(
    device DevelopmentalGenome* developmentalGenomes,
    device RegulatoryNode* regulatoryNodes,
    device RegulatoryEdge* regulatoryEdges,
    device ResonanceGenome* resonanceGenomes,
    device HeritableProgram* heritablePrograms,
    device ProgramSlotState* programSlots,
    device atomic_uint* identityCounters,
    AgentState parentComponent,
    uint parentProgramIndex,
    uint childProgramIndex,
    uint childProgramGeneration,
    uint childBirthID,
    uint childGeneration,
    uint seed,
    float mutationScale,
    bool branchMutation
) {
    AgentState parent = agentWithCellProgram(
        parentComponent, parentProgramIndex, heritablePrograms
    );
    float mutation = mutationScale * (0.006 + parent.geneB.y * 0.18);
    if (branchMutation) {
        mutation += mutationScale * (0.035 + 0.055 * random01(seed + 32u));
    }
    AgentState child = parent;
    child.geneA = clamp(parent.geneA + randomSigned4(seed + 1u) * mutation, 0.0, 1.0);
    child.geneB.xyz = clamp(
        parent.geneB.xyz + randomSigned4(seed + 5u).xyz * mutation, 0.0, 1.0
    );
    child.geneB.y = clamp(child.geneB.y, 0.001, 0.12);
    child.geneB.w = fract(parent.geneB.w + signedRandom(seed + 8u) * mutation * 2.8);
    child.geneC = clamp(parent.geneC + randomSigned4(seed + 9u) * mutation, 0.0, 1.0);
    child.recognition = clamp(
        parent.recognition + randomSigned4(seed + 13u) * (0.006 + mutation * 0.92),
        0.0, 1.0
    );
    child.social = clamp(
        parent.social + randomSigned4(seed + 21u) * (0.005 + mutation * 0.74),
        0.0, 1.0
    );
    child.generation = childGeneration;
    child.birthID = childBirthID;
    child.parentBirthID = parentComponent.birthID;
    child.birthStep = parentComponent.birthStep;
    child.lineageFlags = branchMutation ? 2u : 0u;
    child.dominantProgramIndex = childProgramIndex;
    child.dominantProgramGeneration = childProgramGeneration;
    child.componentPersistenceSteps = parentComponent.componentPersistenceSteps;
    child.programReplicationGeneration = childGeneration;
    child.componentFlags = parentComponent.componentFlags;

    ResonanceGenome childResonance = resonanceGenomes[parentProgramIndex];
    float resonanceMutation = 0.012 + mutation * (branchMutation ? 1.8 : 0.65);
    childResonance.mechanics.x = mutateScalar(
        childResonance.mechanics.x, seed + 901u,
        resonanceMutation * 0.020, 0.0008, 0.0090
    );
    childResonance.mechanics.y = mutateScalar(
        childResonance.mechanics.y, seed + 907u,
        resonanceMutation * 0.32, 0.04, 0.72
    );
    childResonance.mechanics.z = mutateScalar(
        childResonance.mechanics.z, seed + 911u,
        resonanceMutation * 0.62, 0.08, 1.60
    );
    childResonance.mechanics.w = mutateScalar(
        childResonance.mechanics.w, seed + 919u,
        resonanceMutation * 0.08, 0.0, 0.12
    );
    childResonance.tuning = clamp(
        childResonance.tuning + randomSigned4(seed + 929u) * resonanceMutation *
            float4(0.024, 0.020, 0.80, 1.20),
        float4(0.0003, 0.00005, -0.48, -1.0),
        float4(0.0080, 0.0060, 0.48, 1.0)
    );
    resonanceGenomes[childProgramIndex] = childResonance;
    mutateDevelopmentalGenome(
        developmentalGenomes, developmentalGenomes,
        regulatoryNodes, regulatoryNodes, regulatoryEdges, regulatoryEdges,
        identityCounters, parentProgramIndex, childProgramIndex, seed ^ 0x5e2d58d1u,
        mutation, branchMutation
    );
    child.lastMutationDistance = developmentalGenomes[childProgramIndex].mutation.y +
        resonanceMutation * 0.12;
    child.mutationDistance = parentComponent.mutationDistance + child.lastMutationDistance;
    child.genomeHash = agentGenomeHash(
        child, developmentalGenomes[childProgramIndex].topology.z,
        childResonance, developmentalGenomes[childProgramIndex]
    );
    heritablePrograms[childProgramIndex] = heritableProgramFromAgent(
        child, heritablePrograms[parentProgramIndex].genomeHash,
        parentProgramIndex,
        atomic_load_explicit(
            &programSlots[parentProgramIndex].generation, memory_order_relaxed
        )
    );
    publishHeritableProgram(programSlots, childProgramIndex, child.genomeHash);
    return child;
}

inline float recombineDevelopmentalPrograms(
    device DevelopmentalGenome* developmentalGenomes,
    device RegulatoryNode* regulatoryNodes,
    device RegulatoryEdge* regulatoryEdges,
    uint primaryProgramIndex,
    uint secondaryProgramIndex,
    uint childProgramIndex,
    uint seed
) {
    uint primaryNodeBase = primaryProgramIndex * regulatoryNodeCapacity;
    uint secondaryNodeBase = secondaryProgramIndex * regulatoryNodeCapacity;
    uint childNodeBase = childProgramIndex * regulatoryNodeCapacity;
    uint primaryEdgeBase = primaryProgramIndex * regulatoryEdgeCapacity;
    uint secondaryEdgeBase = secondaryProgramIndex * regulatoryEdgeCapacity;
    uint childEdgeBase = childProgramIndex * regulatoryEdgeCapacity;

    for (uint index = 0u; index < regulatoryNodeCapacity; ++index) {
        RegulatoryNode inheritedNode;
        if (random01(seed + index * 17u) < 0.5) {
            inheritedNode = regulatoryNodes[primaryNodeBase + index];
        } else {
            inheritedNode = regulatoryNodes[secondaryNodeBase + index];
        }
        regulatoryNodes[childNodeBase + index] = inheritedNode;
    }
    for (uint index = 0u; index < regulatoryEdgeCapacity; ++index) {
        RegulatoryEdge inheritedEdge;
        if (random01(seed + 401u + index * 23u) < 0.5) {
            inheritedEdge = regulatoryEdges[primaryEdgeBase + index];
        } else {
            inheritedEdge = regulatoryEdges[secondaryEdgeBase + index];
        }
        regulatoryEdges[childEdgeBase + index] = inheritedEdge;
    }

    uint activeNodes = 0u;
    for (uint index = 0u; index < regulatoryNodeCapacity; ++index) {
        activeNodes += regulatoryNodes[childNodeBase + index].flags & 1u;
    }
    uint activeEdges = 0u;
    for (uint index = 0u; index < regulatoryEdgeCapacity; ++index) {
        RegulatoryEdge inheritedEdge = regulatoryEdges[childEdgeBase + index];
        bool validEdge = (inheritedEdge.flags & 1u) != 0u &&
            inheritedEdge.source < regulatoryNodeCapacity &&
            inheritedEdge.target < regulatoryNodeCapacity &&
            (regulatoryNodes[childNodeBase + inheritedEdge.source].flags & 1u) != 0u &&
            (regulatoryNodes[childNodeBase + inheritedEdge.target].flags & 1u) != 0u;
        if (validEdge) {
            activeEdges += 1u;
        } else if ((inheritedEdge.flags & 1u) != 0u) {
            inheritedEdge.flags = 0u;
            regulatoryEdges[childEdgeBase + index] = inheritedEdge;
        }
    }

    DevelopmentalGenome primary = developmentalGenomes[primaryProgramIndex];
    DevelopmentalGenome secondary = developmentalGenomes[secondaryProgramIndex];
    DevelopmentalGenome child = primary;
    child.actuatorBiasA = crossoverFloat4(
        primary.actuatorBiasA, secondary.actuatorBiasA, seed + 901u
    );
    child.actuatorBiasB = crossoverFloat4(
        primary.actuatorBiasB, secondary.actuatorBiasB, seed + 907u
    );
    child.mechanochemistryA = crossoverFloat4(
        primary.mechanochemistryA, secondary.mechanochemistryA, seed + 911u
    );
    child.mechanochemistryB = crossoverFloat4(
        primary.mechanochemistryB, secondary.mechanochemistryB, seed + 919u
    );
    child.morphogenKinetics = crossoverFloat4(
        primary.morphogenKinetics, secondary.morphogenKinetics, seed + 929u
    );
    child.morphogenTransport = crossoverFloat4(
        primary.morphogenTransport, secondary.morphogenTransport, seed + 937u
    );
    child.junctionMaterial = crossoverFloat4(
        primary.junctionMaterial, secondary.junctionMaterial, seed + 941u
    );
    child.ecologicalResponse = crossoverFloat4(
        primary.ecologicalResponse, secondary.ecologicalResponse, seed + 947u
    );
    float recombinationDistance =
        length(primary.actuatorBiasA - secondary.actuatorBiasA) * 0.010 +
        length(primary.actuatorBiasB - secondary.actuatorBiasB) * 0.010 +
        length(primary.mechanochemistryA - secondary.mechanochemistryA) * 0.014 +
        length(primary.mechanochemistryB - secondary.mechanochemistryB) * 0.014 +
        length(primary.morphogenKinetics - secondary.morphogenKinetics) * 0.012 +
        length(primary.morphogenTransport - secondary.morphogenTransport) * 0.012 +
        length(primary.junctionMaterial - secondary.junctionMaterial) * 0.012 +
        length(primary.ecologicalResponse - secondary.ecologicalResponse) * 0.012;
    child.mutation = float4(
        max(primary.mutation.x, secondary.mutation.x) + recombinationDistance,
        recombinationDistance,
        crossoverFloat4(primary.mutation, secondary.mutation, seed + 953u).zw
    );
    child.topology = uint4(
        activeNodes,
        activeEdges,
        0u,
        max(primary.topology.w, secondary.topology.w)
    );
    developmentalGenomes[childProgramIndex] = child;
    child.topology.z = topologyHash(
        regulatoryNodes, regulatoryEdges, childProgramIndex
    );
    developmentalGenomes[childProgramIndex] = child;
    return recombinationDistance;
}

inline AgentState recombineCellPrograms(
    device DevelopmentalGenome* developmentalGenomes,
    device RegulatoryNode* regulatoryNodes,
    device RegulatoryEdge* regulatoryEdges,
    device ResonanceGenome* resonanceGenomes,
    device HeritableProgram* heritablePrograms,
    device ProgramSlotState* programSlots,
    AgentState parentComponent,
    uint primaryProgramIndex,
    uint secondaryProgramIndex,
    uint childProgramIndex,
    uint childProgramGeneration,
    uint childBirthID,
    uint seed
) {
    AgentState primary = agentWithCellProgram(
        parentComponent, primaryProgramIndex, heritablePrograms
    );
    AgentState secondary = agentWithCellProgram(
        parentComponent, secondaryProgramIndex, heritablePrograms
    );
    AgentState child = primary;
    child.geneA = crossoverFloat4(primary.geneA, secondary.geneA, seed + 1u);
    child.geneB = crossoverFloat4(primary.geneB, secondary.geneB, seed + 7u);
    child.geneB.y = clamp(child.geneB.y, 0.001, 0.12);
    child.geneC = crossoverFloat4(primary.geneC, secondary.geneC, seed + 13u);
    child.recognition = crossoverFloat4(
        primary.recognition, secondary.recognition, seed + 19u
    );
    child.social = crossoverFloat4(primary.social, secondary.social, seed + 29u);
    child.birthID = childBirthID;
    child.parentBirthID = parentComponent.birthID;
    child.generation = max(
        heritablePrograms[primaryProgramIndex].generation,
        heritablePrograms[secondaryProgramIndex].generation
    ) + 1u;
    child.programReplicationGeneration = child.generation;
    child.dominantProgramIndex = childProgramIndex;
    child.dominantProgramGeneration = childProgramGeneration;
    child.lineageFlags = parentComponent.lineageFlags | 4u;

    float developmentalDistance = recombineDevelopmentalPrograms(
        developmentalGenomes, regulatoryNodes, regulatoryEdges,
        primaryProgramIndex, secondaryProgramIndex, childProgramIndex,
        seed ^ 0x6c8e9cf5u
    );
    ResonanceGenome primaryResonance = resonanceGenomes[primaryProgramIndex];
    ResonanceGenome secondaryResonance = resonanceGenomes[secondaryProgramIndex];
    ResonanceGenome childResonance;
    childResonance.mechanics = crossoverFloat4(
        primaryResonance.mechanics, secondaryResonance.mechanics, seed + 1103u
    );
    childResonance.tuning = crossoverFloat4(
        primaryResonance.tuning, secondaryResonance.tuning, seed + 1109u
    );
    resonanceGenomes[childProgramIndex] = childResonance;
    float traitDistance =
        length(primary.geneA - secondary.geneA) * 0.012 +
        length(primary.geneB - secondary.geneB) * 0.012 +
        length(primary.geneC - secondary.geneC) * 0.012 +
        length(primary.recognition - secondary.recognition) * 0.010 +
        length(primary.social - secondary.social) * 0.010 +
        length(primaryResonance.mechanics - secondaryResonance.mechanics) * 0.010 +
        length(primaryResonance.tuning - secondaryResonance.tuning) * 0.008;
    child.lastMutationDistance = developmentalDistance + traitDistance;
    child.mutationDistance = max(
        parentComponent.mutationDistance,
        child.lastMutationDistance
    ) + child.lastMutationDistance;
    child.genomeHash = agentGenomeHash(
        child,
        developmentalGenomes[childProgramIndex].topology.z,
        childResonance,
        developmentalGenomes[childProgramIndex]
    );
    HeritableProgram childProgram = heritableProgramFromAgent(
        child,
        heritablePrograms[primaryProgramIndex].genomeHash,
        primaryProgramIndex,
        atomic_load_explicit(
            &programSlots[primaryProgramIndex].generation, memory_order_relaxed
        )
    );
    childProgram.secondParentGenomeHash =
        heritablePrograms[secondaryProgramIndex].genomeHash;
    childProgram.secondParentProgramIndex = secondaryProgramIndex;
    childProgram.secondParentProgramGeneration = atomic_load_explicit(
        &programSlots[secondaryProgramIndex].generation, memory_order_relaxed
    );
    childProgram.ancestryFlags = 1u;
    heritablePrograms[childProgramIndex] = childProgram;
    publishHeritableProgram(programSlots, childProgramIndex, child.genomeHash);
    return child;
}

inline uint seedOrganismCells(
    device CellState* cells,
    device atomic_uint* cellOccupancy,
    device CellIdentity* cellIdentities,
    device uint* cellParentIDs,
    device CellAggregate* aggregates,
    device float* regulatoryStates,
    device MembraneVertex* membraneVertices,
    device float4* programInteractions,
    device ProgramSlotState* programSlots,
    device atomic_uint* identityCounters,
    uint owner,
    uint programIndex,
    uint programGeneration,
    AgentState agent,
    uint seed,
    ResonanceGenome resonanceGenome
) {
    uint cellIndex = claimFreeCell(cellOccupancy, seed ^ owner * 2246822519u);
    if (cellIndex == maxCellCount) { return maxCellCount; }
    cells[cellIndex] = founderCell(agent, resonanceGenome, seed);
    CellIdentity identity;
    identity.owner = owner;
    identity.programIndex = programIndex;
    identity.persistentID = atomic_fetch_add_explicit(
        &identityCounters[3], 1u, memory_order_relaxed
    );
    identity.componentRoot = cellIndex;
    identity.programGeneration = programGeneration;
    identity.identityPadding0 = 0u;
    identity.identityPadding1 = 0u;
    identity.identityPadding2 = 0u;
    if (!retainHeritableProgram(programSlots, programIndex, programGeneration)) {
        atomic_store_explicit(&cellOccupancy[cellIndex], 0u, memory_order_relaxed);
        return maxCellCount;
    }
    cellIdentities[cellIndex] = identity;
    cellParentIDs[cellIndex] = 0xffffffffu;
    uint stateBase = cellIndex * regulatoryNodeCapacity;
    for (uint node = 0u; node < regulatoryNodeCapacity; ++node) {
        regulatoryStates[stateBase + node] = 0.0;
    }
    uint membraneBase = cellIndex * membraneVertexCount;
    for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
    membraneVertices[membraneBase + vertexIndex] = emptyMembraneVertex();
    }
    programInteractions[cellIndex] = float4(0.0, 0.0, -1.0, 0.0);
    CellState founder = cells[cellIndex];
    CellAggregate aggregate;
    aggregate.physiology = float4(1.0, founder.physiology.x, founder.physiology.w, founder.signals.z);
    aggregate.morphology = float4(
        founder.physiology.y, founder.physiology.z, 0.0, 0.0
    );
    aggregate.dynamics = float4(founder.dynamics.x, 1.0, founder.dynamics.w, founder.dynamics.z);
    aggregate.mechanics = float4(0.0, 0.0, 0.0, 0.0);
    aggregate.energetics = float4(0.0);
    aggregate.regulation = founder.regulation;
    aggregate.regulationB = founder.regulationB;
    aggregate.causality = float4(0.0);
    aggregate.resonance = float4(0.0, 0.0, resonanceGenome.mechanics.x, resonanceGenome.mechanics.y);
    aggregate.shape = founder.membrane;
    aggregate.signaling = founder.signaling;
    aggregate.signalCausality = float4(0.0);
    aggregate.geometryAxes = float4(1.0, 0.0, 0.12, 0.12);
    aggregate.geometryBoundary = float4(1.0, 0.0, 0.0, founder.membrane.y);
    aggregate.tissueMotion = float4(0.0);
    aggregate.trophic = float4(0.0);
    aggregate.inheritance = float4(1.0, 0.0, 1.0, float(programIndex));
    aggregate.programEcology = float4(0.0, 0.0, -1.0, 0.0);
    aggregate.environment = float4(0.0);
    aggregate.development = float4(
        founder.signals.xy, founder.development.z, founder.development.w
    );
    aggregate.developmentCausality = float4(
        abs(founder.signals.x - founder.signals.y), 1.0, 0.0, 0.0
    );
    aggregates[owner] = aggregate;
    return cellIndex;
}

kernel void initializeAgents(
    device AgentState* agents [[buffer(0)]],
    device atomic_uint* occupancy [[buffer(1)]],
    constant SimulationUniforms& uniforms [[buffer(2)]],
    device CellState* cells [[buffer(3)]],
    device atomic_uint* cellOccupancy [[buffer(4)]],
    device CellAggregate* cellAggregates [[buffer(5)]],
    device DevelopmentalGenome* developmentalGenomes [[buffer(6)]],
    device RegulatoryNode* regulatoryNodes [[buffer(7)]],
    device RegulatoryEdge* regulatoryEdges [[buffer(8)]],
    device float* regulatoryStates [[buffer(9)]],
    device ResonanceGenome* resonanceGenomes [[buffer(10)]],
    device MembraneVertex* membraneVertices [[buffer(11)]],
    device atomic_uint* identityCounters [[buffer(12)]],
    device LineageEventRecord* lineageEvents [[buffer(13)]],
    device CellIdentity* cellIdentities [[buffer(14)]],
    device atomic_uint* ownerCellHeads [[buffer(15)]],
    device uint* ownerCellNext [[buffer(16)]],
    device atomic_uint* cellComponentParents [[buffer(17)]],
    device atomic_uint* cellComponentCounts [[buffer(18)]],
    device atomic_int* cellComponentAccumulation [[buffer(19)]],
    device atomic_uint* cellComponentOwners [[buffer(20)]],
    device atomic_uint* ownerPrimaryRoots [[buffer(21)]],
    device HeritableProgram* heritablePrograms [[buffer(22)]],
    device atomic_uint* cellComponentPrograms [[buffer(23)]],
    device uint* cellParentIDs [[buffer(24)]],
    device float4* programInteractions [[buffer(25)]],
    device ProgramSlotState* programSlots [[buffer(26)]],
    device atomic_uint* componentCellHeads [[buffer(27)]],
    device uint* componentCellNext [[buffer(28)]],
    device CellJunctionState* junctionStates [[buffer(29)]],
    device atomic_int* membraneContactEffects [[buffer(30)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= maxAgentCount) { return; }
    AgentState agent;
    agent.position = float2(0.5);
    agent.velocity = float2(0.0);
    agent.behavior = float4(0.0);
    agent.geneA = float4(0.76, 0.66, 0.48, 0.72);
    agent.geneB = float4(0.58, 0.032, 0.72, 0.42);
    agent.geneC = float4(0.72, 0.68, 0.34, 0.06);
    agent.recognition = float4(0.5);
    agent.social = float4(0.0);
    agent.energy = 0.0;
    agent.biomass = 0.0;
    agent.age = 0.0;
    agent.generation = 0u;
    agent.birthID = 0u;
    agent.parentBirthID = 0xffffffffu;
    agent.genomeHash = 0u;
    agent.birthStep = 0u;
    agent.mutationDistance = 0.0;
    agent.lastMutationDistance = 0.0;
    agent.lineageFlags = 0u;
    agent.dominantProgramIndex = maxHeritableProgramCount;
    agent.dominantProgramGeneration = 0u;
    agent.componentPersistenceSteps = 0u;
    agent.programReplicationGeneration = 0u;
    agent.componentFlags = 0u;
    agent.tissueKinematics = float4(0.0);
    agents[gid] = agent;
    atomic_store_explicit(&occupancy[gid], 0u, memory_order_relaxed);
    atomic_store_explicit(&ownerCellHeads[gid], emptySpatialHashEntry, memory_order_relaxed);
    atomic_store_explicit(&ownerPrimaryRoots[gid], emptySpatialHashEntry, memory_order_relaxed);
    for (uint cellIndex = gid; cellIndex < maxCellCount; cellIndex += maxAgentCount) {
        cells[cellIndex] = emptyCell();
        atomic_store_explicit(&cellOccupancy[cellIndex], 0u, memory_order_relaxed);
        CellIdentity identity;
        identity.owner = maxAgentCount;
        identity.programIndex = maxHeritableProgramCount;
        identity.persistentID = 0xffffffffu;
        identity.componentRoot = emptySpatialHashEntry;
        identity.programGeneration = 0u;
        identity.identityPadding0 = 0u;
        identity.identityPadding1 = 0u;
        identity.identityPadding2 = 0u;
        cellIdentities[cellIndex] = identity;
        cellParentIDs[cellIndex] = 0xffffffffu;
        programInteractions[cellIndex] = float4(0.0, 0.0, -1.0, 0.0);
        ownerCellNext[cellIndex] = emptySpatialHashEntry;
        componentCellNext[cellIndex] = emptySpatialHashEntry;
        atomic_store_explicit(
            &componentCellHeads[cellIndex], emptySpatialHashEntry, memory_order_relaxed
        );
        atomic_store_explicit(
            &cellComponentParents[cellIndex], emptySpatialHashEntry, memory_order_relaxed
        );
        atomic_store_explicit(&cellComponentCounts[cellIndex], 0u, memory_order_relaxed);
        atomic_store_explicit(
            &cellComponentOwners[cellIndex], emptySpatialHashEntry, memory_order_relaxed
        );
        atomic_store_explicit(
            &cellComponentPrograms[cellIndex], 0u, memory_order_relaxed
        );
        for (uint channel = 0u; channel < 5u; ++channel) {
            atomic_store_explicit(
                &cellComponentAccumulation[cellIndex * 5u + channel], 0,
                memory_order_relaxed
            );
        }
        uint stateBase = cellIndex * regulatoryNodeCapacity;
        for (uint node = 0u; node < regulatoryNodeCapacity; ++node) {
            regulatoryStates[stateBase + node] = 0.0;
        }
        uint membraneBase = cellIndex * membraneVertexCount;
        for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
            membraneVertices[membraneBase + vertexIndex] = emptyMembraneVertex();
            uint effectBase = (cellIndex * membraneVertexCount + vertexIndex) * 3u;
            atomic_store_explicit(&membraneContactEffects[effectBase], 0, memory_order_relaxed);
            atomic_store_explicit(&membraneContactEffects[effectBase + 1u], 0, memory_order_relaxed);
            atomic_store_explicit(&membraneContactEffects[effectBase + 2u], 0, memory_order_relaxed);
        }
    }
    CellAggregate aggregate;
    aggregate.physiology = float4(0.0);
    aggregate.morphology = float4(0.0);
    aggregate.dynamics = float4(0.0);
    aggregate.mechanics = float4(0.0);
    aggregate.energetics = float4(0.0);
    aggregate.regulation = float4(0.0);
    aggregate.regulationB = float4(0.0);
    aggregate.causality = float4(0.0);
    aggregate.resonance = float4(0.0);
    aggregate.shape = float4(0.0);
    aggregate.signaling = float4(0.0);
    aggregate.signalCausality = float4(0.0);
    aggregate.geometryAxes = float4(0.0);
    aggregate.geometryBoundary = float4(0.0);
    aggregate.tissueMotion = float4(0.0);
    aggregate.trophic = float4(0.0);
    aggregate.inheritance = float4(0.0);
    aggregate.programEcology = float4(0.0);
    aggregate.environment = float4(0.0);
    aggregate.development = float4(0.0);
    aggregate.developmentCausality = float4(0.0);
    cellAggregates[gid] = aggregate;
    for (uint programIndex = gid; programIndex < maxHeritableProgramCount;
         programIndex += maxAgentCount) {
        heritablePrograms[programIndex] = emptyHeritableProgram();
        atomic_store_explicit(&programSlots[programIndex].occupied, 0u, memory_order_relaxed);
        atomic_store_explicit(&programSlots[programIndex].referenceCount, 0u, memory_order_relaxed);
        atomic_store_explicit(&programSlots[programIndex].generation, 0u, memory_order_relaxed);
        programSlots[programIndex].lineageHash = 0u;
        atomic_store_explicit(
            &programSlots[programIndex].mutationHazard, 0u, memory_order_relaxed
        );
        programSlots[programIndex].mutationHazardPadding0 = 0u;
        programSlots[programIndex].mutationHazardPadding1 = 0u;
        programSlots[programIndex].mutationHazardPadding2 = 0u;
        developmentalGenomes[programIndex] = emptyDevelopmentalGenome();
        resonanceGenomes[programIndex] = emptyResonanceGenome();
        uint nodeBase = programIndex * regulatoryNodeCapacity;
        for (uint node = 0u; node < regulatoryNodeCapacity; ++node) {
            regulatoryNodes[nodeBase + node] = emptyRegulatoryNode();
        }
        uint edgeBase = programIndex * regulatoryEdgeCapacity;
        for (uint edge = 0u; edge < regulatoryEdgeCapacity; ++edge) {
            regulatoryEdges[edgeBase + edge] = emptyRegulatoryEdge();
        }
    }
    for (uint event = gid; event < lineageEventCapacity; event += maxAgentCount) {
        LineageEventRecord record;
        record.sequence = 0u;
        lineageEvents[event] = record;
    }
    for (uint junction = gid; junction < cellJunctionCapacity; junction += maxAgentCount) {
        atomic_store_explicit(
            &junctionStates[junction].pairKey, emptySpatialHashEntry, memory_order_relaxed
        );
        atomic_store_explicit(
            &junctionStates[junction].lastSeenStep, 0u, memory_order_relaxed
        );
        junctionStates[junction].persistentFingerprint = 0u;
        junctionStates[junction].flags = 0u;
        junctionStates[junction].restDistance = 0.0;
        junctionStates[junction].strength = 0.0;
        junctionStates[junction].age = 0.0;
        junctionStates[junction].load = 0.0;
        junctionStates[junction].material = float4(0.0);
        junctionStates[junction].remodeling = float4(0.0);
    }
    if (gid == 0u) {
        atomic_store_explicit(&identityCounters[0], 1u, memory_order_relaxed);
        atomic_store_explicit(&identityCounters[1], 1u, memory_order_relaxed);
        atomic_store_explicit(&identityCounters[2], 0u, memory_order_relaxed);
        atomic_store_explicit(&identityCounters[3], 1u, memory_order_relaxed);
        atomic_store_explicit(&identityCounters[4], 0u, memory_order_relaxed);
        for (uint counter = 5u; counter < 19u; ++counter) {
            atomic_store_explicit(&identityCounters[counter], 0u, memory_order_relaxed);
        }
    }
}

kernel void collectAgentObservations(
    device const AgentState* agents [[buffer(0)]],
    device const atomic_uint* occupancy [[buffer(1)]],
    device AgentObservationRecord* observations [[buffer(2)]],
    device const CellAggregate* cellAggregates [[buffer(3)]],
    device const DevelopmentalGenome* developmentalGenomes [[buffer(4)]],
    device const ResonanceGenome* resonanceGenomes [[buffer(5)]],
    device const ProgramSlotState* programSlots [[buffer(6)]],
    device const uint* activeComponents [[buffer(7)]],
    device const atomic_uint* activeComponentCount [[buffer(8)]],
    uint compactIndex [[thread_position_in_grid]]
) {
    if (compactIndex >= atomic_load_explicit(activeComponentCount, memory_order_relaxed)) { return; }
    uint gid = activeComponents[compactIndex];
    if (gid >= maxAgentCount) { return; }
    uint occupied = atomic_load_explicit(&occupancy[gid], memory_order_relaxed);
    AgentState agent = agents[gid];
    AgentObservationRecord observation;
    observation.position = agent.position;
    observation.generation = agent.generation;
    observation.flags = occupied != 0u
        ? (1u | (agent.geneC.w >= 0.08 ? 2u : 0u) |
            ((agent.componentFlags & componentRegeneratedFlag) != 0u ? 4u : 0u) |
            ((agent.componentFlags & componentHomeostaticFlag) != 0u ? 8u : 0u) |
            ((agent.componentFlags & componentChallengedFlag) != 0u ? 16u : 0u))
        : 0u;
    observation.birthID = agent.birthID;
    observation.parentBirthID = agent.parentBirthID;
    observation.genomeHash = agent.genomeHash;
    uint programIndex = agent.dominantProgramIndex;
    bool validProgram = programSlotMatches(
        programSlots, programIndex, agent.dominantProgramGeneration
    );
    DevelopmentalGenome development = validProgram
        ? developmentalGenomes[programIndex] : emptyDevelopmentalGenome();
    ResonanceGenome resonance = validProgram
        ? resonanceGenomes[programIndex] : emptyResonanceGenome();
    observation.topologyHash = development.topology.z;
    CellAggregate aggregate = cellAggregates[gid];
    observation.morphology = float4(
        aggregate.physiology.x / referenceTissueCellCount,
        aggregate.morphology.z,
        aggregate.shape.z,
        aggregate.morphology.w
    );
    observation.dynamics = float4(
        resonance.mechanics.x,
        aggregate.resonance.y,
        aggregate.dynamics.y,
        aggregate.mechanics.y
    );
    observation.mutationDistance = agent.mutationDistance;
    float energeticClosure = aggregate.energetics.x /
        max(aggregate.energetics.x + aggregate.energetics.y +
            aggregate.energetics.z + aggregate.energetics.w, 0.0000001);
    float mechanochemicalClosure = pow(max(
        aggregate.signalCausality.x * aggregate.signalCausality.y *
        aggregate.signalCausality.z * aggregate.mechanics.x *
        saturate(length(aggregate.tissueMotion.xy) /
            max(aggregate.tissueMotion.w * max(aggregate.physiology.x, 1.0), 0.0000001)),
        0.0
    ), 0.25);
    observation.padding = float3(
        saturate(energeticClosure),
        saturate(mechanochemicalClosure * 180.0),
        float(agent.programReplicationGeneration)
    );
    observation.energeticBoundary = float4(
        max(aggregate.energetics.x, 0.0),
        max(aggregate.programEcology.x, 0.0),
        max(aggregate.causality.w, 0.0),
        max(aggregate.physiology.y, 0.0)
    );
    observation.boundary = float4(
        max(aggregate.geometryBoundary.w, 0.0),
        max(aggregate.trophic.z, 0.0),
        max(aggregate.energetics.w, 0.0),
        saturate(aggregate.physiology.z)
    );
    observation.mechanochemical = float4(
        max(aggregate.signalCausality.x, 0.0),
        max(aggregate.signalCausality.y, 0.0),
        max(aggregate.signalCausality.z, 0.0),
        max(aggregate.mechanics.x, 0.0) * saturate(
            length(aggregate.tissueMotion.xy) /
                max(aggregate.tissueMotion.w * max(aggregate.physiology.x, 1.0), 0.0000001)
        )
    );
    observation.social = float4(
        max(aggregate.programEcology.x, 0.0),
        max(aggregate.programEcology.y, 0.0),
        max(aggregate.development.w, 0.0),
        max(aggregate.programEcology.w, 0.0)
    );
    observation.environment = aggregate.environment;
    observations[gid] = observation;
}

kernel void collectCellObservations(
    device const AgentState* agents [[buffer(0)]],
    device const atomic_uint* agentOccupancy [[buffer(1)]],
    device const CellState* cells [[buffer(2)]],
    device const atomic_uint* cellOccupancy [[buffer(3)]],
    device const CellIdentity* cellIdentities [[buffer(4)]],
    device const float4* programInteractions [[buffer(5)]],
    device const HeritableProgram* heritablePrograms [[buffer(6)]],
    device CellObservationRecord* observations [[buffer(7)]],
    constant SimulationUniforms& uniforms [[buffer(8)]],
    device const DevelopmentalGenome* developmentalGenomes [[buffer(9)]],
    device const ProgramSlotState* programSlots [[buffer(10)]],
    device const atomic_uint* activeCellCount [[buffer(29)]],
    device const uint* activeCellIndices [[buffer(30)]],
    uint compactIndex [[thread_position_in_grid]]
) {
    if (compactIndex >= atomic_load_explicit(activeCellCount, memory_order_relaxed)) { return; }
    uint gid = activeCellIndices[compactIndex];
    if (gid >= maxCellCount ||
        atomic_load_explicit(&cellOccupancy[gid], memory_order_relaxed) == 0u) { return; }
    CellIdentity identity = cellIdentities[gid];
    if (identity.owner >= maxAgentCount ||
        atomic_load_explicit(&agentOccupancy[identity.owner], memory_order_relaxed) == 0u) { return; }
    AgentState agent = agents[identity.owner];
    CellState cell = cells[gid];
    float4 interaction = programInteractions[gid];
    bool hasCurrentProgram = programSlotMatches(
        programSlots, identity.programIndex, identity.programGeneration
    );
    uint replicationGeneration = hasCurrentProgram
        ? heritablePrograms[identity.programIndex].generation : 0u;
    float exposedPerimeter = max(cell.membrane.y, 0.0) * saturate(cell.tissueGeometry.z);
    CellObservationRecord observation;
    observation.geometry = float4(
        cellWorldPosition(agent, cell.position, uniforms),
        max(cell.membrane.y, 0.0),
        saturate(cell.tissueGeometry.z)
    );
    observation.identity = uint4(
        identity.persistentID, identity.owner, agent.birthID, replicationGeneration
    );
    HeritableProgram program = hasCurrentProgram
        ? heritablePrograms[identity.programIndex] : emptyHeritableProgram();
    DevelopmentalGenome developmental = hasCurrentProgram
        ? developmentalGenomes[identity.programIndex] : emptyDevelopmentalGenome();
    observation.programLineage = uint4(
        program.genomeHash, program.parentGenomeHash,
        identity.programGeneration, identity.programIndex
    );
    observation.programAncestry = uint4(
        identity.programIndex, identity.programGeneration,
        program.parentProgramIndex, program.parentProgramGeneration
    );
    float4 inheritedGains = abs(float4(
        developmental.mechanochemistryA.x,
        developmental.mechanochemistryA.y,
        developmental.mechanochemistryA.z,
        developmental.mechanochemistryB.y
    ));
    inheritedGains /= 1.0 + inheritedGains;
    observation.inheritedTraits = float4(
        pow(max(inheritedGains.x * inheritedGains.y * inheritedGains.z *
            inheritedGains.w, 0.0), 0.25),
        developmental.mechanochemistryB.x,
        developmental.mechanochemistryB.z,
        developmental.mechanochemistryB.w
    );
    observation.energetic = float4(
        max(cell.energetics.x, 0.0),
        max(abs(interaction.x), 0.0),
        max(cell.regulation.w * cell.energetics.y, 0.0),
        saturate(cell.physiology.w)
    );
    observation.boundary = float4(
        exposedPerimeter,
        max(cell.tissueForce.z, 0.0),
        max(cell.regulationB.x * cell.energetics.y, 0.0),
        max(cell.physiology.x, 0.0)
    );
    observation.mechanochemical = float4(
        max(cell.signalCausality.x, 0.0),
        max(cell.signalCausality.y, 0.0),
        max(cell.signalCausality.z, 0.0),
        max(cell.mechanics.x * cell.mechanics.y, 0.0)
    );
    observation.social = float4(
        abs(interaction.x),
        max(interaction.y, 0.0),
        max(cell.development.w, 0.0),
        max(interaction.w, 0.0)
    );
    observation.environment = cell.environment;
    observations[gid] = observation;
}

kernel void collectProgramMetricRecords(
    device const AgentState* agents [[buffer(0)]],
    device const atomic_uint* occupancy [[buffer(1)]],
    device const DevelopmentalGenome* developmentalGenomes [[buffer(2)]],
    device const ResonanceGenome* resonanceGenomes [[buffer(3)]],
    device ProgramMetricRecord* records [[buffer(4)]],
    device const ProgramSlotState* programSlots [[buffer(5)]],
    device const uint* activeComponents [[buffer(6)]],
    device const atomic_uint* activeComponentCount [[buffer(7)]],
    uint compactIndex [[thread_position_in_grid]]
) {
    if (compactIndex >= atomic_load_explicit(activeComponentCount, memory_order_relaxed)) { return; }
    uint gid = activeComponents[compactIndex];
    if (gid >= maxAgentCount) { return; }
    uint programIndex = agents[gid].dominantProgramIndex;
    bool valid = atomic_load_explicit(&occupancy[gid], memory_order_relaxed) != 0u &&
        programSlotMatches(
            programSlots, programIndex, agents[gid].dominantProgramGeneration
        );
    ProgramMetricRecord record;
    record.developmental = valid
        ? developmentalGenomes[programIndex] : emptyDevelopmentalGenome();
    record.resonance = valid
        ? resonanceGenomes[programIndex] : emptyResonanceGenome();
    records[gid] = record;
}

kernel void nucleateAutogenicFounder(
    device AgentState* agents [[buffer(0)]],
    device atomic_uint* occupancy [[buffer(1)]],
    constant SimulationUniforms& uniforms [[buffer(2)]],
    device CellState* cells [[buffer(3)]],
    device atomic_uint* cellOccupancy [[buffer(4)]],
    device CellAggregate* cellAggregates [[buffer(5)]],
    device DevelopmentalGenome* developmentalGenomes [[buffer(6)]],
    device RegulatoryNode* regulatoryNodes [[buffer(7)]],
    device RegulatoryEdge* regulatoryEdges [[buffer(8)]],
    device float* regulatoryStates [[buffer(9)]],
    device ResonanceGenome* resonanceGenomes [[buffer(10)]],
    device atomic_uint* identityCounters [[buffer(11)]],
    device LineageEventRecord* lineageEvents [[buffer(12)]],
    device MembraneVertex* membraneVertices [[buffer(13)]],
    device CellIdentity* cellIdentities [[buffer(14)]],
    device HeritableProgram* heritablePrograms [[buffer(15)]],
    device uint* cellParentIDs [[buffer(16)]],
    device float4* programInteractions [[buffer(17)]],
    device ProgramSlotState* programSlots [[buffer(18)]],
    texture2d_array<float, access::read> state [[texture(0)]],
    texture2d_array<float, access::read> genomeA [[texture(1)]],
    texture2d_array<float, access::read> genomeB [[texture(2)]],
    texture2d_array<float, access::read> genomeC [[texture(3)]],
    texture2d_array<float, access::read> ecology [[texture(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height ||
        atomic_load_explicit(&occupancy[0], memory_order_relaxed) != 0u) { return; }

    float4 localState = state.read(gid, 0);
    float4 localEcology = ecology.read(gid, 0);
    if (localState.y < 0.055 || localState.z < 0.006 ||
        localState.w < 0.003 || localEcology.w < 0.030) { return; }

    float score = localState.y * 3.0 + localState.z * 5.0 +
        localState.w * 8.0 + localEcology.w * 2.0 - localEcology.z * 1.4;
    int2 p = int2(gid);
    int2 cardinal[4] = { int2(-1, 0), int2(1, 0), int2(0, -1), int2(0, 1) };
    for (uint index = 0; index < 4u; ++index) {
        uint2 neighbor = uint2(wrapped(p + cardinal[index], uniforms.width, uniforms.height));
        float4 neighborState = state.read(neighbor, 0);
        float4 neighborEcology = ecology.read(neighbor, 0);
        float neighborScore = neighborState.y * 3.0 + neighborState.z * 5.0 +
            neighborState.w * 8.0 + neighborEcology.w * 2.0 - neighborEcology.z * 1.4;
        if (neighborScore > score) { return; }
    }

    uint expected = 0u;
    if (!atomic_compare_exchange_weak_explicit(
        &occupancy[0], &expected, 1u, memory_order_relaxed, memory_order_relaxed
    )) { return; }

    AgentState founder;
    founder.position = (float2(gid) + 0.5) / float2(uniforms.width, uniforms.height);
    founder.geneA = genomeA.read(gid, 0);
    founder.geneB = genomeB.read(gid, 0);
    founder.geneC = genomeC.read(gid, 0);
    float heading = founder.geneB.w * 2.0 * M_PI_F;
    float spatialScale = 1.0 / max(uniforms.worldScale, 1.0);
    founder.velocity = float2(cos(heading), sin(heading)) *
        (0.000020 + 0.000050 * founder.geneB.z) * spatialScale;
    founder.behavior = float4(0.0);
    founder.energy = clamp(0.62 + localState.z * 8.0, 0.62, 1.02);
    founder.biomass = clamp(0.42 + localState.y * 1.8, 0.42, 0.70);
    founder.age = 0.0;
    founder.generation = 0u;
    uint founderSeed = hash32(gid.x * 2246822519u ^ gid.y * 3266489917u ^ uniforms.step);
    uint programGeneration = 0u;
    uint programIndex = claimHeritableProgram(
        programSlots, identityCounters, founderSeed ^ 0x4b1d5a77u, programGeneration
    );
    if (programIndex == maxHeritableProgramCount) {
        atomic_store_explicit(&occupancy[0], 0u, memory_order_relaxed);
        return;
    }
    founder.recognition = founderRecognition(founder, founderSeed);
    founder.social = founderSocialControl(founder, founderSeed);
    founder.birthID = atomic_fetch_add_explicit(&identityCounters[0], 1u, memory_order_relaxed);
    founder.parentBirthID = 0xffffffffu;
    founder.birthStep = uniforms.step;
    founder.mutationDistance = 0.0;
    founder.lastMutationDistance = 0.0;
    founder.lineageFlags = 1u;
    founder.dominantProgramIndex = programIndex;
    founder.dominantProgramGeneration = programGeneration;
    founder.componentPersistenceSteps = 0u;
    founder.programReplicationGeneration = 0u;
    founder.componentFlags = 0u;
    founder.tissueKinematics = float4(heading, 0.0, 0.0, 0.0);
    initializeFounderRegulatoryGenome(
        developmentalGenomes, regulatoryNodes, regulatoryEdges, identityCounters,
        programIndex, founder, founderSeed
    );
    ResonanceGenome resonance = founderResonanceGenome(founder, founderSeed ^ 0x92d68ca2u);
    resonanceGenomes[programIndex] = resonance;
    founder.genomeHash = agentGenomeHash(
        founder, developmentalGenomes[programIndex].topology.z, resonance,
        developmentalGenomes[programIndex]
    );
    heritablePrograms[programIndex] = heritableProgramFromAgent(
        founder, 0u, maxHeritableProgramCount, 0u
    );
    publishHeritableProgram(programSlots, programIndex, founder.genomeHash);
    agents[0] = founder;
    uint founderCellIndex = seedOrganismCells(
        cells, cellOccupancy, cellIdentities, cellParentIDs, cellAggregates, regulatoryStates,
        membraneVertices, programInteractions, programSlots, identityCounters,
        0u, programIndex, programGeneration, founder, founderSeed, resonance
    );
    if (founderCellIndex == maxCellCount) {
        abandonHeritableProgram(programSlots, identityCounters, programIndex);
        atomic_store_explicit(&occupancy[0], 0u, memory_order_relaxed);
        return;
    }
    recordLineageEvent(
        lineageEvents, identityCounters, 1u, founder, developmentalGenomes[programIndex],
        resonance, cellAggregates[0], uniforms.step
    );
}

kernel void evolveAgents(
    device const AgentState* agentsIn [[buffer(0)]],
    device AgentState* agentsOut [[buffer(1)]],
    device atomic_uint* occupancy [[buffer(2)]],
    constant SimulationUniforms& uniforms [[buffer(3)]],
    device const CellAggregate* cellAggregates [[buffer(4)]],
    device const DevelopmentalGenome* developmentalGenomes [[buffer(5)]],
    device const ResonanceGenome* resonanceGenomes [[buffer(6)]],
    device LineageEventRecord* lineageEvents [[buffer(7)]],
    device atomic_uint* identityCounters [[buffer(8)]],
    device const ProgramSlotState* programSlots [[buffer(9)]],
    device const uint* activeComponents [[buffer(10)]],
    device const atomic_uint* activeComponentCount [[buffer(11)]],
    texture2d_array<float, access::read> state [[texture(0)]],
    texture2d_array<float, access::read> ecology [[texture(1)]],
    texture2d_array<float, access::read> environment [[texture(2)]],
    texture2d_array<float, access::read> mechanicalField [[texture(3)]],
    uint compactIndex [[thread_position_in_grid]]
) {
    if (compactIndex >= atomic_load_explicit(activeComponentCount, memory_order_relaxed)) { return; }
    uint gid = activeComponents[compactIndex];
    if (gid >= maxAgentCount) { return; }
    AgentState agent = agentsIn[gid];
    if (atomic_load_explicit(&occupancy[gid], memory_order_relaxed) == 0u) {
        agentsOut[gid] = agent;
        return;
    }

    CellAggregate cellAggregate = cellAggregates[gid];
    bool dominantProgramValid = programSlotMatches(
        programSlots, agent.dominantProgramIndex, agent.dominantProgramGeneration
    );
    float cellCount = max(cellAggregate.physiology.x, 1.0);
    float tissueMass = max(cellCount * (0.58 + agent.biomass * 0.42), 1.0);
    float meanArmorConstruction = saturate(
        cellAggregate.regulation.y * cellAggregate.regulation.w * agent.geneA.w *
            cellAggregate.physiology.y
    );
    float meanPredatoryConstruction = saturate(
        cellAggregate.regulationB.y * cellAggregate.regulationB.w *
            saturate((agent.geneC.w - 0.025) * 2.2) * cellAggregate.physiology.y
    );
    tissueMass *= 1.0 + meanArmorConstruction * 0.85 +
        meanPredatoryConstruction * 0.28;
    float2 localForce = cellAggregate.tissueMotion.xy;
    float2 worldForce = rotateTissueToWorld(localForce, agent) * cellWorldScale(uniforms);
    float forceCoherence = saturate(
        length(localForce) /
            max(cellAggregate.tissueMotion.w * cellCount, 0.0000001)
    );
    float translationalMobility = mix(4.8, 2.2, saturate(cellCount / referenceTissueCellCount)) *
        mix(0.72, 1.22, cellAggregate.regulationB.w) /
        (1.0 + meanArmorConstruction * 0.90 + meanPredatoryConstruction * 0.24);
    translationalMobility *= mix(0.10, 1.0, forceCoherence);
    agent.velocity = agent.velocity * 0.91 +
        worldForce * (translationalMobility / tissueMass) * uniforms.transportScale;
    agent.velocity *= mix(1.0, 0.62, saturate(cellAggregate.environment.y));
    float maximumSpeed = 0.00018 / max(uniforms.worldScale, 1.0);
    float speed = length(agent.velocity);
    if (speed > maximumSpeed) { agent.velocity *= maximumSpeed / speed; }

    float momentOfInertia = max(
        tissueMass * (cellAggregate.geometryAxes.z * cellAggregate.geometryAxes.z +
            cellAggregate.geometryAxes.w * cellAggregate.geometryAxes.w),
        0.08
    );
    float angularAcceleration = cellAggregate.tissueMotion.z / momentOfInertia;
    agent.tissueKinematics.y = clamp(
        agent.tissueKinematics.y * 0.90 + angularAcceleration * 0.42,
        -0.018, 0.018
    );
    agent.tissueKinematics.x = atan2(
        sin(agent.tissueKinematics.x + agent.tissueKinematics.y * uniforms.transportScale),
        cos(agent.tissueKinematics.x + agent.tissueKinematics.y * uniforms.transportScale)
    );
    agent.position += agent.velocity * uniforms.transportScale;
    if (agent.position.x < 0.002 || agent.position.x > 0.998) {
        agent.velocity.x *= -0.42;
        agent.position.x = clamp(agent.position.x, 0.002, 0.998);
    }
    if (agent.position.y < 0.002 || agent.position.y > 0.998) {
        agent.velocity.y *= -0.42;
        agent.position.y = clamp(agent.position.y, 0.002, 0.998);
    }

    float forceMagnitude = length(localForce);
    float2 forceDirection = forceMagnitude > 0.000001
        ? normalize(worldForce) : tissueHeading(agent);
    agent.behavior = float4(
        forceDirection * saturate(forceMagnitude * 680.0),
        saturate(cellAggregate.trophic.y * 1200.0),
        saturate((cellAggregate.trophic.x + cellAggregate.trophic.z) * 420.0)
    );
    agent.tissueKinematics.z = mix(
        agent.tissueKinematics.z, cellAggregate.trophic.x, 0.18
    );
    agent.tissueKinematics.w = max(agent.tissueKinematics.w - 0.0015, 0.0);
    agent.energy = clamp(mix(agent.energy, cellAggregate.physiology.y, 0.018), 0.0, 1.2);
    float measuredBiomass = saturate(cellCount / referenceTissueCellCount);
    agent.biomass = clamp(mix(agent.biomass, measuredBiomass, 0.012), 0.02, 1.0);
    agent.componentPersistenceSteps = min(agent.componentPersistenceSteps + 1u, 0xfffffffeu);
    agent.componentFlags = (agent.componentFlags & ~componentMulticellularFlag) |
        (cellCount > 1.0 ? componentMulticellularFlag : 0u);
    bool regeneratedDescendant = agent.generation > 0u &&
        (agent.componentFlags & componentRegeneratedFlag) != 0u;
    bool completedChallengeWindow =
        (agent.componentFlags & componentChallengedFlag) != 0u &&
        agent.tissueKinematics.w <= 0.0;
    float homeostaticEnergySupport = cellularEnergySupport(
        cellAggregate.physiology.y, cellAggregate.energetics
    );
    bool stableHomeostasis = regeneratedDescendant && completedChallengeWindow &&
        cellCount > 1.0 &&
        homeostaticEnergySupport >= 0.32 &&
        cellAggregate.physiology.z >= 0.55 &&
        cellAggregate.physiology.w <= 0.55;
    if (stableHomeostasis) {
        agent.componentFlags |= componentHomeostaticFlag;
    }
    agent.age += 1.0;
    bool cellularFailure = cellAggregate.physiology.x < 0.5;
    if (cellularFailure) {
        recordLineageEvent(
            lineageEvents, identityCounters, 2u, agent,
            dominantProgramValid
                ? developmentalGenomes[agent.dominantProgramIndex] : emptyDevelopmentalGenome(),
            dominantProgramValid
                ? resonanceGenomes[agent.dominantProgramIndex] : emptyResonanceGenome(),
            cellAggregate, uniforms.step
        );
        agent.energy = 0.0;
        agent.biomass = 0.0;
        agent.behavior = float4(0.0);
        atomic_store_explicit(&occupancy[gid], 0u, memory_order_relaxed);
    }
    agentsOut[gid] = agent;
}

kernel void initializeCellComponents(
    device const atomic_uint* cellOccupancy [[buffer(0)]],
    device CellIdentity* cellIdentities [[buffer(1)]],
    device atomic_uint* componentParents [[buffer(2)]],
    device atomic_uint* componentCounts [[buffer(3)]],
    device atomic_int* componentAccumulation [[buffer(4)]],
    device atomic_uint* componentOwners [[buffer(5)]],
    device atomic_uint* ownerPrimaryRoots [[buffer(6)]],
    device atomic_uint* componentPrograms [[buffer(7)]],
    device atomic_uint* componentCellHeads [[buffer(8)]],
    device uint* componentCellNext [[buffer(9)]],
    device const atomic_uint* contactWorkState [[buffer(28)]],
    device const atomic_uint* activeCellCount [[buffer(29)]],
    device const uint* activeCellIndices [[buffer(30)]],
    uint compactIndex [[thread_position_in_grid]]
) {
    if (atomic_load_explicit(&contactWorkState[2], memory_order_relaxed) == 0u) { return; }
    if (compactIndex >= atomic_load_explicit(activeCellCount, memory_order_relaxed)) { return; }
    uint gid = activeCellIndices[compactIndex];
    if (gid >= maxCellCount) { return; }
    CellIdentity identity = cellIdentities[gid];
    if (atomic_load_explicit(&cellOccupancy[gid], memory_order_relaxed) != 0u &&
        identity.owner < maxAgentCount) {
        atomic_store_explicit(&componentParents[gid], gid, memory_order_relaxed);
        atomic_store_explicit(&componentCounts[gid], 0u, memory_order_relaxed);
        atomic_store_explicit(
            &componentOwners[gid], emptySpatialHashEntry, memory_order_relaxed
        );
        atomic_store_explicit(&componentPrograms[gid], 0u, memory_order_relaxed);
        atomic_store_explicit(
            &componentCellHeads[gid], emptySpatialHashEntry, memory_order_relaxed
        );
        componentCellNext[gid] = emptySpatialHashEntry;
        atomic_store_explicit(
            &ownerPrimaryRoots[identity.owner], emptySpatialHashEntry, memory_order_relaxed
        );
        for (uint channel = 0u; channel < 5u; ++channel) {
            atomic_store_explicit(
                &componentAccumulation[gid * 5u + channel], 0, memory_order_relaxed
            );
        }
        identity.componentRoot = gid;
        cellIdentities[gid] = identity;
    }
}

inline uint cellPairKey(uint indexA, uint indexB);
inline uint cellPairFingerprint(
    device const CellIdentity* identities,
    uint indexA,
    uint indexB
);
inline uint findOrCreateCellJunction(
    device CellJunctionState* junctionStates,
    uint pairKey,
    uint fingerprint,
    uint step,
    float restDistance,
    float targetStrength
);

kernel void unionCellComponents(
    device const AgentState* agents [[buffer(0)]],
    device const atomic_uint* agentOccupancy [[buffer(1)]],
    device const CellState* cells [[buffer(2)]],
    device const atomic_uint* cellOccupancy [[buffer(3)]],
    device const MembraneVertex* membraneVertices [[buffer(4)]],
    device const CellIdentity* cellIdentities [[buffer(5)]],
    device const uint2* contactPairs [[buffer(6)]],
    device const atomic_uint* contactWorkState [[buffer(7)]],
    device atomic_uint* componentParents [[buffer(8)]],
    constant SimulationUniforms& uniforms [[buffer(9)]],
    device const HeritableProgram* heritablePrograms [[buffer(10)]],
    device atomic_uint* identityCounters [[buffer(11)]],
    device CellJunctionState* junctionStates [[buffer(12)]],
    uint pairIndex [[thread_position_in_grid]]
) {
    if (atomic_load_explicit(&contactWorkState[2], memory_order_relaxed) == 0u ||
        pairIndex >= atomic_load_explicit(&contactWorkState[0], memory_order_relaxed)) { return; }
    uint2 pair = contactPairs[pairIndex];
    uint gid = pair.x;
    uint otherIndex = pair.y;
    if (gid >= maxCellCount || otherIndex >= maxCellCount ||
        atomic_load_explicit(&cellOccupancy[gid], memory_order_relaxed) == 0u ||
        atomic_load_explicit(&cellOccupancy[otherIndex], memory_order_relaxed) == 0u) { return; }
    uint owner = cellIdentities[gid].owner;
    uint otherOwner = cellIdentities[otherIndex].owner;
    if (owner >= maxAgentCount || otherOwner >= maxAgentCount ||
        atomic_load_explicit(&agentOccupancy[owner], memory_order_relaxed) == 0u ||
        atomic_load_explicit(&agentOccupancy[otherOwner], memory_order_relaxed) == 0u) { return; }

    AgentState agent = agents[owner];
    CellState cell = cells[gid];
    float scale = cellWorldScale(uniforms);
    float2 worldPosition = cellWorldPosition(agent, cell.position, uniforms);
    CellState other = cells[otherIndex];
                    AgentState otherAgent = agents[otherOwner];
                    float2 otherWorldPosition = cellWorldPosition(
                        otherAgent, other.position, uniforms
                    );
                    float2 delta = otherWorldPosition - worldPosition;
                    float distance = max(length(delta), 0.0000001);
                    float2 direction = delta / distance;
                    float2 localDirection = rotateWorldToTissue(direction, agent);
                    float2 otherLocalDirection = rotateWorldToTissue(-direction, otherAgent);
                    float2 supportA = membraneSupport(
                        membraneVertices, gid, localDirection
                    );
                    float2 supportB = membraneSupport(
                        membraneVertices, otherIndex, otherLocalDirection
                    );
                    float adhesion = min(cell.phenotype.x, other.phenotype.x);
                    float integrity = min(
                        min(cell.physiology.w, other.physiology.w),
                        min(supportA.y, supportB.y)
                    );
                    bool sameOwner = otherOwner == owner;
                    float fusionDrive = 0.0;
                    bool fusionEligible = false;
                    bool distinctProgramPair = false;
                    if (!sameOwner) {
                        uint programA = cellIdentities[gid].programIndex;
                        uint programB = cellIdentities[otherIndex].programIndex;
                        if (programA < maxHeritableProgramCount &&
                            programB < maxHeritableProgramCount) {
                            distinctProgramPair = programA != programB;
                            AgentState inheritedA = agentWithCellProgram(
                                agent, programA, heritablePrograms
                            );
                            AgentState inheritedB = agentWithCellProgram(
                                otherAgent, programB, heritablePrograms
                            );
                            float predation = max(inheritedA.geneC.w, inheritedB.geneC.w);
                            float pairDifference = saturate(
                                length(inheritedA.geneC - inheritedB.geneC) * 0.42 +
                                length(inheritedA.geneA - inheritedB.geneA) * 0.12
                            );
                            float adhesiveCommitment =
                                adhesion * 0.56 + min(cell.regulation.y, other.regulation.y) * 0.44;
                            // Reciprocal collision impulse is pressure, not hostile
                            // intent. Predatory construction defines aggression;
                            // contact stress and damage remain independent gates.
                            float nonAggression = 1.0 - saturate(predation * 1.8);
                            float stressTolerance = 1.0 -
                                saturate(max(cell.signals.z, other.signals.z));
                            float compatibility = recognitionCompatibility(inheritedA, inheritedB);
                            float bilateralFusionInvestment = min(
                                inheritedA.social.x, inheritedB.social.x
                            );
                            // Boundary isolation contributes to detachment readiness,
                            // so it cannot also be an absolute mating veto for free
                            // cells. It remains a strong reluctance penalty while
                            // reciprocal adhesion and investment provide commitment.
                            float detachmentPermission = 1.0 - smoothstep(
                                0.08, 0.72,
                                max(cell.tissueGeometry.w, other.tissueGeometry.w)
                            );
                            // A clonal fragment that is actively detaching must
                            // finish separating before it can heal back into its
                            // parent. Distinct programs retain a reluctance floor
                            // so compatible mating remains possible.
                            float localDetachmentGate = distinctProgramPair
                                ? mix(0.30, 1.0, detachmentPermission)
                                : detachmentPermission;
                            float2 velocityA = agent.velocity +
                                rotateTissueToWorld(cell.velocity, agent) * scale;
                            float2 velocityB = otherAgent.velocity +
                                rotateTissueToWorld(other.velocity, otherAgent) * scale;
                            float separatingSpeed = dot(velocityB - velocityA, direction);
                            // Connectivity runs after reciprocal contact impulses.
                            // The former upper edge (0.00018) matched the maximum
                            // two-cell rebound produced by that solver, classifying
                            // sustained compressive contact as escape. This wider
                            // band distinguishes bounded rebound from actual flight.
                            float compressiveContactGate = 1.0 - smoothstep(
                                -0.00001, 0.00036, separatingSpeed
                            );
                            fusionEligible = predation < 0.40 &&
                                compatibility > 0.35 &&
                                bilateralFusionInvestment > 0.20 &&
                                stressTolerance > 0.35 &&
                                localDetachmentGate > 0.28 &&
                                compressiveContactGate > 0.0;
                            fusionDrive = adhesiveCommitment * integrity * nonAggression *
                                mix(1.0, 0.72, pairDifference) * stressTolerance *
                                mix(0.22, 1.0, compatibility) *
                                mix(0.38, 1.24, bilateralFusionInvestment) *
                                localDetachmentGate * compressiveContactGate;
                        }
                    }
                    float junctionExtension = sameOwner
                        ? 0.050 * adhesion * integrity
                        : 0.018 * fusionDrive;
                    float junctionDistance = (supportA.x + supportB.x + junctionExtension) * scale;
                    // The heterotypic drive is the product of nine independent
                    // biological gates. A single-score cutoff made compatible fusion
                    // practically unreachable even across millions of direct
                    // contacts. Explicit eligibility prevents the lower product-space
                    // threshold from weakening recognition, investment, aggression,
                    // stress, detachment, compression, or membrane-contact gates.
                    bool connected = sameOwner
                        ? integrity > 0.10 && distance <= junctionDistance
                        : fusionEligible && fusionDrive > 0.008 &&
                            distance <= junctionDistance;
                    if (!sameOwner && distance <=
                        (supportA.x + supportB.x + 0.018) * scale) {
                        atomic_fetch_add_explicit(
                            &identityCounters[11], 1u, memory_order_relaxed
                        );
                        atomic_fetch_max_explicit(
                            &identityCounters[17],
                            uint(clamp(fusionDrive * 1000000.0, 0.0, 1000000.0)),
                            memory_order_relaxed
                        );
                        if (fusionEligible) {
                            atomic_fetch_add_explicit(
                                &identityCounters[16], 1u, memory_order_relaxed
                            );
                        }
                        if (connected) {
                            atomic_fetch_add_explicit(
                                &identityCounters[12], 1u, memory_order_relaxed
                            );
                            if (distinctProgramPair) {
                                atomic_fetch_add_explicit(
                                    &identityCounters[18], 1u, memory_order_relaxed
                                );
                            }
                        }
                    }
                    if (connected) {
                        if (!sameOwner) {
                            uint fusionJunction = findOrCreateCellJunction(
                                junctionStates,
                                cellPairKey(gid, otherIndex),
                                cellPairFingerprint(cellIdentities, gid, otherIndex),
                                uniforms.step,
                                distance / max(scale, 0.0000001),
                                clamp(
                                    0.20 + fusionDrive * 1.8 + adhesion * 0.24,
                                    0.20, 0.82
                                )
                            );
                            if (fusionJunction < cellJunctionCapacity) {
                                junctionStates[fusionJunction].flags = 3u;
                                junctionStates[fusionJunction].remodeling.z = integrity;
                            }
                        }
                        unionCellComponentPair(
                            componentParents, cellIdentities, gid, otherIndex
                        );
                    }
}

kernel void compressCellComponents(
    device const atomic_uint* cellOccupancy [[buffer(0)]],
    device atomic_uint* componentParents [[buffer(1)]],
    device CellIdentity* cellIdentities [[buffer(2)]],
    device const atomic_uint* contactWorkState [[buffer(28)]],
    device const atomic_uint* activeCellCount [[buffer(29)]],
    device const uint* activeCellIndices [[buffer(30)]],
    uint compactIndex [[thread_position_in_grid]]
) {
    if (atomic_load_explicit(&contactWorkState[2], memory_order_relaxed) == 0u) { return; }
    if (compactIndex >= atomic_load_explicit(activeCellCount, memory_order_relaxed)) { return; }
    uint gid = activeCellIndices[compactIndex];
    if (gid >= maxCellCount ||
        atomic_load_explicit(&cellOccupancy[gid], memory_order_relaxed) == 0u) { return; }
    uint root = findCellComponentRoot(componentParents, gid);
    atomic_store_explicit(&componentParents[gid], root, memory_order_relaxed);
    CellIdentity identity = cellIdentities[gid];
    identity.componentRoot = root;
    cellIdentities[gid] = identity;
}

kernel void buildCellComponentLists(
    device const atomic_uint* cellOccupancy [[buffer(0)]],
    device const CellIdentity* cellIdentities [[buffer(1)]],
    device atomic_uint* componentCellHeads [[buffer(2)]],
    device uint* componentCellNext [[buffer(3)]],
    device const atomic_uint* contactWorkState [[buffer(28)]],
    device const atomic_uint* activeCellCount [[buffer(29)]],
    device const uint* activeCellIndices [[buffer(30)]],
    uint compactIndex [[thread_position_in_grid]]
) {
    if (atomic_load_explicit(&contactWorkState[2], memory_order_relaxed) == 0u) { return; }
    if (compactIndex >= atomic_load_explicit(activeCellCount, memory_order_relaxed)) { return; }
    uint gid = activeCellIndices[compactIndex];
    if (gid >= maxCellCount ||
        atomic_load_explicit(&cellOccupancy[gid], memory_order_relaxed) == 0u) {
        if (gid < maxCellCount) { componentCellNext[gid] = emptySpatialHashEntry; }
        return;
    }
    uint root = cellIdentities[gid].componentRoot;
    if (root >= maxCellCount) {
        componentCellNext[gid] = emptySpatialHashEntry;
        return;
    }
    componentCellNext[gid] = atomic_exchange_explicit(
        &componentCellHeads[root], gid, memory_order_relaxed
    );
}

kernel void accumulateCellComponents(
    device const CellState* cells [[buffer(0)]],
    device const atomic_uint* cellOccupancy [[buffer(1)]],
    device const CellIdentity* cellIdentities [[buffer(2)]],
    device atomic_uint* componentCounts [[buffer(3)]],
    device atomic_int* componentAccumulation [[buffer(4)]],
    device atomic_uint* componentOwners [[buffer(5)]],
    device const atomic_uint* contactWorkState [[buffer(28)]],
    device const atomic_uint* activeCellCount [[buffer(29)]],
    device const uint* activeCellIndices [[buffer(30)]],
    uint compactIndex [[thread_position_in_grid]]
) {
    if (atomic_load_explicit(&contactWorkState[2], memory_order_relaxed) == 0u) { return; }
    if (compactIndex >= atomic_load_explicit(activeCellCount, memory_order_relaxed)) { return; }
    uint gid = activeCellIndices[compactIndex];
    if (gid >= maxCellCount ||
        atomic_load_explicit(&cellOccupancy[gid], memory_order_relaxed) == 0u) { return; }
    uint root = cellIdentities[gid].componentRoot;
    if (root >= maxCellCount) { return; }
    uint owner = cellIdentities[gid].owner;
    uint observedOwner = atomic_load_explicit(
        &componentOwners[root], memory_order_relaxed
    );
    for (uint attempt = 0u; attempt < 8u; ++attempt) {
        if (observedOwner == mixedComponentOwner || observedOwner == owner) { break; }
        uint desiredOwner = observedOwner == emptySpatialHashEntry
            ? owner : mixedComponentOwner;
        uint expectedOwner = observedOwner;
        if (atomic_compare_exchange_weak_explicit(
            &componentOwners[root], &expectedOwner, desiredOwner,
            memory_order_relaxed, memory_order_relaxed
        )) { break; }
        observedOwner = expectedOwner;
    }
    CellState cell = cells[gid];
    atomic_fetch_add_explicit(&componentCounts[root], 1u, memory_order_relaxed);
    atomic_fetch_add_explicit(
        &componentAccumulation[root * 5u],
        int(clamp(cell.position.x * 65536.0, -131072.0, 131072.0)),
        memory_order_relaxed
    );
    atomic_fetch_add_explicit(
        &componentAccumulation[root * 5u + 1u],
        int(clamp(cell.position.y * 65536.0, -131072.0, 131072.0)),
        memory_order_relaxed
    );
    atomic_fetch_add_explicit(
        &componentAccumulation[root * 5u + 2u],
        int(clamp(cell.physiology.x * 65536.0, 0.0, 78643.0)),
        memory_order_relaxed
    );
    atomic_fetch_add_explicit(
        &componentAccumulation[root * 5u + 3u],
        int(clamp(cell.physiology.w * 65536.0, 0.0, 65536.0)),
        memory_order_relaxed
    );
    atomic_fetch_max_explicit(
        &componentAccumulation[root * 5u + 4u],
        int(clamp(cell.tissueGeometry.w * 65536.0, 0.0, 65536.0)),
        memory_order_relaxed
    );
}

kernel void selectPrimaryCellComponents(
    device const atomic_uint* agentOccupancy [[buffer(0)]],
    device const atomic_uint* ownerCellHeads [[buffer(1)]],
    device const uint* ownerCellNext [[buffer(2)]],
    device const CellIdentity* cellIdentities [[buffer(3)]],
    device const atomic_uint* componentCounts [[buffer(4)]],
    device atomic_uint* ownerPrimaryRoots [[buffer(5)]],
    device const uint* activeComponents [[buffer(6)]],
    device const atomic_uint* activeComponentCount [[buffer(7)]],
    device const atomic_uint* contactWorkState [[buffer(28)]],
    uint compactIndex [[thread_position_in_grid]]
) {
    if (atomic_load_explicit(&contactWorkState[2], memory_order_relaxed) == 0u) { return; }
    if (compactIndex >= atomic_load_explicit(activeComponentCount, memory_order_relaxed)) { return; }
    uint owner = activeComponents[compactIndex];
    if (owner >= maxAgentCount ||
        atomic_load_explicit(&agentOccupancy[owner], memory_order_relaxed) == 0u) { return; }
    uint bestRoot = emptySpatialHashEntry;
    uint bestCount = 0u;
    uint bestPersistentID = 0xffffffffu;
    uint index = atomic_load_explicit(&ownerCellHeads[owner], memory_order_relaxed);
    while (index != emptySpatialHashEntry) {
        uint nextIndex = ownerCellNext[index];
        uint root = cellIdentities[index].componentRoot;
        if (root < maxCellCount) {
            uint count = atomic_load_explicit(&componentCounts[root], memory_order_relaxed);
            uint persistentID = cellIdentities[root].persistentID;
            if (count > bestCount ||
                (count == bestCount && persistentID < bestPersistentID)) {
                bestCount = count;
                bestRoot = root;
                bestPersistentID = persistentID;
            }
        }
        index = nextIndex;
    }
    atomic_store_explicit(&ownerPrimaryRoots[owner], bestRoot, memory_order_relaxed);
}

kernel void assignCellComponentOwners(
    device AgentState* agents [[buffer(0)]],
    device atomic_uint* agentOccupancy [[buffer(1)]],
    constant SimulationUniforms& uniforms [[buffer(2)]],
    device const CellIdentity* cellIdentities [[buffer(3)]],
    device const atomic_uint* componentCounts [[buffer(4)]],
    device const atomic_int* componentAccumulation [[buffer(5)]],
    device atomic_uint* componentOwners [[buffer(6)]],
    device const atomic_uint* ownerPrimaryRoots [[buffer(7)]],
    device CellAggregate* cellAggregates [[buffer(8)]],
    device DevelopmentalGenome* developmentalGenomes [[buffer(9)]],
    device RegulatoryNode* regulatoryNodes [[buffer(10)]],
    device RegulatoryEdge* regulatoryEdges [[buffer(11)]],
    device ResonanceGenome* resonanceGenomes [[buffer(12)]],
    device atomic_uint* identityCounters [[buffer(13)]],
    device LineageEventRecord* lineageEvents [[buffer(14)]],
    device atomic_uint* componentProgramCounts [[buffer(15)]],
    device HeritableProgram* heritablePrograms [[buffer(16)]],
    device const atomic_uint* cellOccupancy [[buffer(17)]],
    device uint* componentProgramSources [[buffer(18)]],
    device uint* componentProgramTargets [[buffer(19)]],
    device const atomic_uint* componentCellHeads [[buffer(20)]],
    device const uint* componentCellNext [[buffer(21)]],
    device ProgramSlotState* programSlots [[buffer(22)]],
    device const atomic_uint* contactWorkState [[buffer(28)]],
    device const atomic_uint* activeCellCount [[buffer(29)]],
    device const uint* activeCellIndices [[buffer(30)]],
    uint compactIndex [[thread_position_in_grid]]
) {
    if (atomic_load_explicit(&contactWorkState[2], memory_order_relaxed) == 0u) { return; }
    if (compactIndex >= atomic_load_explicit(activeCellCount, memory_order_relaxed)) { return; }
    uint root = activeCellIndices[compactIndex];
    if (root >= maxCellCount) { return; }
    uint componentCount = atomic_load_explicit(&componentCounts[root], memory_order_relaxed);
    if (componentCount == 0u) { return; }
    uint parentOwner = cellIdentities[root].owner;
    if (parentOwner >= maxAgentCount ||
        atomic_load_explicit(&agentOccupancy[parentOwner], memory_order_relaxed) != 1u) { return; }
    uint primaryRoot = atomic_load_explicit(
        &ownerPrimaryRoots[parentOwner], memory_order_relaxed
    );
    bool crossOwnerFusion = atomic_load_explicit(
        &componentOwners[root], memory_order_relaxed
    ) == mixedComponentOwner;
    if (crossOwnerFusion) {
        atomic_store_explicit(&componentOwners[root], parentOwner, memory_order_relaxed);
        uint mappingBase = root * maxProgramsPerPropagule;
        uint absorbedOwnerCount = 0u;
        uint cellIndex = atomic_load_explicit(
            &componentCellHeads[root], memory_order_relaxed
        );
        while (cellIndex != emptySpatialHashEntry) {
            uint following = componentCellNext[cellIndex];
            if (atomic_load_explicit(&cellOccupancy[cellIndex], memory_order_relaxed) == 0u) {
                cellIndex = following;
                continue;
            }
            uint absorbedOwner = cellIdentities[cellIndex].owner;
            if (absorbedOwner != parentOwner && absorbedOwner < maxAgentCount) {
                bool observed = false;
                for (uint index = 0u; index < absorbedOwnerCount; ++index) {
                    observed = observed ||
                        componentProgramSources[mappingBase + index] == absorbedOwner;
                }
                if (!observed && absorbedOwnerCount < maxProgramsPerPropagule) {
                    componentProgramSources[mappingBase + absorbedOwnerCount++] = absorbedOwner;
                }
            }
            cellIndex = following;
        }
        AgentState survivor = agents[parentOwner];
        uint survivorProgram = survivor.dominantProgramIndex;
        for (uint index = 0u; index < absorbedOwnerCount; ++index) {
            uint absorbedOwner = componentProgramSources[mappingBase + index];
            if (atomic_load_explicit(
                &agentOccupancy[absorbedOwner], memory_order_relaxed
            ) == 0u) { continue; }
            AgentState fusionRecord = survivor;
            fusionRecord.parentBirthID = agents[absorbedOwner].birthID;
            recordLineageEvent(
                lineageEvents, identityCounters, 3u, fusionRecord,
                survivorProgram < maxHeritableProgramCount
                    ? developmentalGenomes[survivorProgram] : emptyDevelopmentalGenome(),
                survivorProgram < maxHeritableProgramCount
                    ? resonanceGenomes[survivorProgram] : emptyResonanceGenome(),
                cellAggregates[parentOwner], uniforms.step
            );
        }
        return;
    }
    if (root == primaryRoot) {
        atomic_store_explicit(&componentOwners[root], parentOwner, memory_order_relaxed);
        return;
    }
    // Every physically disconnected nonempty root becomes a component immediately.
    atomic_store_explicit(
        &componentOwners[root], emptySpatialHashEntry, memory_order_relaxed
    );

    float inverseCount = 1.0 / float(componentCount);
    float2 centroid = float2(
        atomic_load_explicit(&componentAccumulation[root * 5u], memory_order_relaxed),
        atomic_load_explicit(&componentAccumulation[root * 5u + 1u], memory_order_relaxed)
    ) / 65536.0 * inverseCount;
    float meanATP = float(atomic_load_explicit(
        &componentAccumulation[root * 5u + 2u], memory_order_relaxed
    )) / 65536.0 * inverseCount;
    float meanIntegrity = float(atomic_load_explicit(
        &componentAccumulation[root * 5u + 3u], memory_order_relaxed
    )) / 65536.0 * inverseCount;
    uint parentProgramIndex = cellIdentities[root].programIndex;
    if (!programSlotMatches(
        programSlots, parentProgramIndex, cellIdentities[root].programGeneration
    )) { return; }
    AgentState parentComponent = agents[parentOwner];
    AgentState parent = agentWithCellProgram(
        parentComponent, parentProgramIndex, heritablePrograms
    );
    uint mappingBase = root * maxProgramsPerPropagule;
    componentProgramSources[mappingBase] = parentProgramIndex;
    uint sourceProgramCount = 1u;
    uint dominantCellCount = 0u;
    uint cellIndex = atomic_load_explicit(
        &componentCellHeads[root], memory_order_relaxed
    );
    while (cellIndex != emptySpatialHashEntry) {
        uint following = componentCellNext[cellIndex];
        if (atomic_load_explicit(&cellOccupancy[cellIndex], memory_order_relaxed) == 0u) {
            cellIndex = following;
            continue;
        }
        uint sourceProgram = cellIdentities[cellIndex].programIndex;
        if (!programSlotMatches(
            programSlots, sourceProgram, cellIdentities[cellIndex].programGeneration
        )) { return; }
        dominantCellCount += sourceProgram == parentProgramIndex ? 1u : 0u;
        bool observed = false;
        for (uint index = 0u; index < sourceProgramCount; ++index) {
            observed = observed ||
                componentProgramSources[mappingBase + index] == sourceProgram;
        }
        if (observed) {
            cellIndex = following;
            continue;
        }
        // The mapping cache is bounded, but an already-valid source program
        // does not need cloning to remain attached to its cell. Keep scanning
        // when more than sixteen programs coexist; unmapped cells retain their
        // generation-valid program identity during coordinate reassignment.
        if (sourceProgramCount < maxProgramsPerPropagule) {
            componentProgramSources[mappingBase + sourceProgramCount++] = sourceProgram;
        }
        cellIndex = following;
    }

    uint birthSeed = hash32(
        parentOwner * 2246822519u ^ root * 3266489917u ^
        uniforms.step * 668265263u ^ parent.birthID
    );
    uint target = maxAgentCount;
    uint searchStart = hash32(birthSeed + 17u) % maxAgentCount;
    for (uint offset = 0u; offset < maxAgentCount; ++offset) {
        uint candidate = (searchStart + offset) % maxAgentCount;
        if (candidate == parentOwner) { continue; }
        uint expected = 0u;
        if (atomic_compare_exchange_weak_explicit(
            &agentOccupancy[candidate], &expected, 2u,
            memory_order_relaxed, memory_order_relaxed
        )) {
            target = candidate;
            break;
        }
    }
    if (target == maxAgentCount) { return; }

    uint childBirthID = atomic_fetch_add_explicit(
        &identityCounters[0], 1u, memory_order_relaxed
    );
    uint childGeneration = parentComponent.generation + 1u;
    AgentState child = parent;
    uint childProgramIndex = parentProgramIndex;
    uint childProgramGeneration = cellIdentities[root].programGeneration;
    for (uint index = 0u; index < sourceProgramCount; ++index) {
        uint sourceProgramIndex = componentProgramSources[mappingBase + index];
        componentProgramSources[mappingBase + index] = sourceProgramIndex;
        componentProgramTargets[mappingBase + index] = sourceProgramIndex;
    }
    atomic_store_explicit(
        &componentProgramCounts[root], sourceProgramCount, memory_order_relaxed
    );
    child.position = clamp(
        cellWorldPosition(parent, centroid, uniforms), float2(0.002), float2(0.998)
    );
    child.velocity = parent.velocity;
    child.behavior = float4(0.0);
    child.energy = meanATP;
    child.biomass = saturate(float(componentCount) / referenceTissueCellCount);
    child.age = 0.0;
    child.generation = childGeneration;
    child.birthID = childBirthID;
    child.parentBirthID = parentComponent.birthID;
    child.birthStep = uniforms.step;
    child.lineageFlags = 0u;
    child.dominantProgramIndex = childProgramIndex;
    child.dominantProgramGeneration = childProgramGeneration;
    child.componentPersistenceSteps = 0u;
    child.programReplicationGeneration = heritablePrograms[childProgramIndex].generation;
    child.componentFlags = componentCount > 1u ? componentMulticellularFlag : 0u;
    child.lastMutationDistance = 0.0;
    child.tissueKinematics = float4(parent.tissueKinematics.x, parent.tissueKinematics.y, 0.0, 0.0);
    ResonanceGenome childResonance = resonanceGenomes[childProgramIndex];

    CellAggregate childAggregate = cellAggregates[parentOwner];
    childAggregate.physiology.x = float(componentCount);
    childAggregate.physiology.y = meanATP;
    childAggregate.physiology.z = meanIntegrity;
    childAggregate.morphology = float4(0.0);
    childAggregate.tissueMotion = float4(0.0);
    childAggregate.trophic = float4(0.0);
    float dominantFraction = float(dominantCellCount) / float(componentCount);
    childAggregate.inheritance = float4(
        dominantFraction, 1.0 - dominantFraction,
        float(sourceProgramCount), float(childProgramIndex)
    );
    childAggregate.programEcology = float4(0.0, 0.0, -1.0, 0.0);
    cellAggregates[target] = childAggregate;
    agents[target] = child;
    atomic_store_explicit(&componentOwners[root], target, memory_order_relaxed);
    recordLineageEvent(
        lineageEvents, identityCounters, 1u, child,
        developmentalGenomes[childProgramIndex],
        childResonance, childAggregate, uniforms.step
    );
    atomic_store_explicit(&agentOccupancy[target], 1u, memory_order_relaxed);
}

inline void invalidateCellJunctions(
    device CellJunctionState* junctionStates,
    device const atomic_uint* cellOccupancy,
    device const CellIdentity* cellIdentities,
    device const atomic_uint* ownerCellHeads,
    device const uint* ownerCellNext,
    uint owner,
    uint cellIndex,
    uint retainedComponentRoot
);

kernel void reassignCellComponents(
    device const AgentState* agents [[buffer(0)]],
    device CellState* cells [[buffer(1)]],
    device atomic_uint* cellOccupancy [[buffer(2)]],
    device CellIdentity* cellIdentities [[buffer(3)]],
    device const atomic_uint* componentOwners [[buffer(4)]],
    constant SimulationUniforms& uniforms [[buffer(5)]],
    device const atomic_uint* ownerPrimaryRoots [[buffer(6)]],
    device const atomic_uint* componentProgramCounts [[buffer(7)]],
    device const uint* componentProgramSources [[buffer(8)]],
    device const uint* componentProgramTargets [[buffer(9)]],
    device ProgramSlotState* programSlots [[buffer(10)]],
    device atomic_uint* identityCounters [[buffer(11)]],
    device CellJunctionState* junctionStates [[buffer(12)]],
    device const atomic_uint* ownerCellHeads [[buffer(13)]],
    device const uint* ownerCellNext [[buffer(14)]],
    device const atomic_uint* contactWorkState [[buffer(28)]],
    device const atomic_uint* activeCellCount [[buffer(29)]],
    device const uint* activeCellIndices [[buffer(30)]],
    uint compactIndex [[thread_position_in_grid]]
) {
    if (atomic_load_explicit(&contactWorkState[2], memory_order_relaxed) == 0u) { return; }
    if (compactIndex >= atomic_load_explicit(activeCellCount, memory_order_relaxed)) { return; }
    uint gid = activeCellIndices[compactIndex];
    if (gid >= maxCellCount ||
        atomic_load_explicit(&cellOccupancy[gid], memory_order_relaxed) == 0u) { return; }
    CellIdentity identity = cellIdentities[gid];
    uint root = identity.componentRoot;
    if (root >= maxCellCount) { return; }
    uint newOwner = atomic_load_explicit(&componentOwners[root], memory_order_relaxed);
    uint oldOwner = identity.owner;
    if (oldOwner >= maxAgentCount) { return; }
    if (newOwner >= maxAgentCount) {
        // Allocation is bookkeeping, not a viability criterion. Preserve the
        // cell under its previous owner and retry component assignment on the
        // next connectivity pass rather than deleting a physical fragment.
        return;
    }
    uint programCount = atomic_load_explicit(
        &componentProgramCounts[root], memory_order_relaxed
    );
    uint mappingBase = root * maxProgramsPerPropagule;
    uint previousProgramIndex = identity.programIndex;
    uint previousProgramGeneration = identity.programGeneration;
    if (newOwner != oldOwner) {
        invalidateCellJunctions(
            junctionStates, cellOccupancy, cellIdentities,
            ownerCellHeads, ownerCellNext, oldOwner, gid, root
        );
    }
    for (uint index = 0u; index < min(programCount, maxProgramsPerPropagule); ++index) {
        if (componentProgramSources[mappingBase + index] == identity.programIndex) {
            uint targetProgram = componentProgramTargets[mappingBase + index];
            uint targetGeneration = targetProgram < maxHeritableProgramCount
                ? atomic_load_explicit(
                    &programSlots[targetProgram].generation, memory_order_relaxed
                ) : 0u;
            if (targetProgram != previousProgramIndex) {
                if (!retainHeritableProgram(
                    programSlots, targetProgram, targetGeneration
                )) {
                    return;
                }
                identity.programIndex = targetProgram;
                identity.programGeneration = targetGeneration;
                releaseHeritableProgram(
                    programSlots, identityCounters,
                    previousProgramIndex, previousProgramGeneration
                );
            }
            break;
        }
    }
    if (newOwner == oldOwner) {
        cellIdentities[gid] = identity;
        return;
    }
    AgentState oldAgent = agents[oldOwner];
    AgentState newAgent = agents[newOwner];
    CellState cell = cells[gid];
    float scale = cellWorldScale(uniforms);
    float2 worldPosition = cellWorldPosition(oldAgent, cell.position, uniforms);
    float2 worldVelocity = rotateTissueToWorld(cell.velocity, oldAgent);
    cell.position = rotateWorldToTissue(worldPosition - newAgent.position, newAgent) /
        max(scale, 0.0000001);
    cell.velocity = rotateWorldToTissue(worldVelocity, newAgent);
    cell.tissueForce = float4(0.0);
    // Ownership changes only the coordinate frame. Preserve the locally
    // produced detachment state so a newborn fragment cannot immediately
    // erase its separation drive and fuse back into its parent.
    identity.owner = newOwner;
    cells[gid] = cell;
    cellIdentities[gid] = identity;
}

kernel void finalizeCellTopology(
    device atomic_uint* contactWorkState [[buffer(0)]],
    device const atomic_uint* activeCellCount [[buffer(1)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid != 0u ||
        atomic_load_explicit(&contactWorkState[2], memory_order_relaxed) == 0u) { return; }
    atomic_store_explicit(
        &contactWorkState[3],
        atomic_load_explicit(activeCellCount, memory_order_relaxed),
        memory_order_relaxed
    );
    atomic_store_explicit(&contactWorkState[2], 0u, memory_order_relaxed);
}

kernel void injectFounder(
    device AgentState* agents [[buffer(0)]],
    device atomic_uint* occupancy [[buffer(1)]],
    constant SimulationUniforms& uniforms [[buffer(2)]],
    device CellState* cells [[buffer(3)]],
    device atomic_uint* cellOccupancy [[buffer(4)]],
    device CellAggregate* cellAggregates [[buffer(5)]],
    device DevelopmentalGenome* developmentalGenomes [[buffer(6)]],
    device RegulatoryNode* regulatoryNodes [[buffer(7)]],
    device RegulatoryEdge* regulatoryEdges [[buffer(8)]],
    device float* regulatoryStates [[buffer(9)]],
    device ResonanceGenome* resonanceGenomes [[buffer(10)]],
    device atomic_uint* identityCounters [[buffer(11)]],
    device LineageEventRecord* lineageEvents [[buffer(12)]],
    device MembraneVertex* membraneVertices [[buffer(13)]],
    device CellIdentity* cellIdentities [[buffer(14)]],
    device HeritableProgram* heritablePrograms [[buffer(15)]],
    device uint* cellParentIDs [[buffer(16)]],
    device float4* programInteractions [[buffer(17)]],
    device ProgramSlotState* programSlots [[buffer(18)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid != 0u) { return; }
    uint claimed = maxAgentCount;
    for (uint index = 0u; index < maxAgentCount; ++index) {
        uint expected = 0u;
        if (atomic_compare_exchange_weak_explicit(
            &occupancy[index], &expected, 1u, memory_order_relaxed, memory_order_relaxed
        )) {
            claimed = index;
            break;
        }
    }
    if (claimed == maxAgentCount) { return; }

    uint seed = hash32(uniforms.step ^ claimed * 2246822519u ^
        uint(uniforms.brushPosition.x * 65535.0) * 3266489917u);
    AgentState founder;
    founder.position = clamp(uniforms.brushPosition, float2(0.002), float2(0.998));
    float heading = random01(seed + 1u) * 2.0 * M_PI_F;
    founder.geneA = traitA(claimed + 17u, seed);
    founder.geneB = traitB(claimed + 17u, seed + 29u);
    founder.geneC = traitC(claimed + 17u, seed + 47u);
    founder.geneC.w = 0.03 + founder.geneC.w * 0.72;
    founder.recognition = founderRecognition(founder, seed);
    founder.social = founderSocialControl(founder, seed);
    float spatialScale = 1.0 / max(uniforms.worldScale, 1.0);
    founder.velocity = float2(cos(heading), sin(heading)) *
        (0.000020 + 0.000050 * founder.geneB.z) * spatialScale;
    founder.behavior = float4(0.0);
    founder.energy = 1.02;
    founder.biomass = 0.66;
    founder.age = 0.0;
    founder.generation = 0u;
    uint programGeneration = 0u;
    uint programIndex = claimHeritableProgram(
        programSlots, identityCounters, seed ^ 0x4b1d5a77u, programGeneration
    );
    if (programIndex == maxHeritableProgramCount) {
        atomic_store_explicit(&occupancy[claimed], 0u, memory_order_relaxed);
        return;
    }
    founder.birthID = atomic_fetch_add_explicit(&identityCounters[0], 1u, memory_order_relaxed);
    founder.parentBirthID = 0xffffffffu;
    founder.birthStep = uniforms.step;
    founder.mutationDistance = 0.0;
    founder.lastMutationDistance = 0.0;
    founder.lineageFlags = 1u;
    founder.dominantProgramIndex = programIndex;
    founder.dominantProgramGeneration = programGeneration;
    founder.componentPersistenceSteps = 0u;
    founder.programReplicationGeneration = 0u;
    founder.componentFlags = 0u;
    founder.tissueKinematics = float4(heading, 0.0, 0.0, 0.0);
    initializeFounderRegulatoryGenome(
        developmentalGenomes, regulatoryNodes, regulatoryEdges, identityCounters,
        programIndex, founder, seed
    );
    ResonanceGenome resonance = founderResonanceGenome(founder, seed ^ 0xe6f13a8bu);
    resonanceGenomes[programIndex] = resonance;
    founder.genomeHash = agentGenomeHash(
        founder, developmentalGenomes[programIndex].topology.z, resonance,
        developmentalGenomes[programIndex]
    );
    heritablePrograms[programIndex] = heritableProgramFromAgent(
        founder, 0u, maxHeritableProgramCount, 0u
    );
    publishHeritableProgram(programSlots, programIndex, founder.genomeHash);
    agents[claimed] = founder;
    uint founderCellIndex = seedOrganismCells(
        cells, cellOccupancy, cellIdentities, cellParentIDs, cellAggregates, regulatoryStates,
        membraneVertices, programInteractions, programSlots, identityCounters,
        claimed, programIndex, programGeneration, founder, seed ^ 0x63d83595u, resonance
    );
    if (founderCellIndex == maxCellCount) {
        abandonHeritableProgram(programSlots, identityCounters, programIndex);
        atomic_store_explicit(&occupancy[claimed], 0u, memory_order_relaxed);
        return;
    }
    recordLineageEvent(
        lineageEvents, identityCounters, 1u, founder, developmentalGenomes[programIndex],
        resonance, cellAggregates[claimed], uniforms.step
    );
}

inline uint cellPairKey(uint indexA, uint indexB);
inline uint cellPairFingerprint(
    device const CellIdentity* identities,
    uint indexA,
    uint indexB
);
inline uint findCellJunction(
    device const CellJunctionState* junctionStates,
    uint pairKey,
    uint fingerprint
);

inline void invalidateCellJunctions(
    device CellJunctionState* junctionStates,
    device const atomic_uint* cellOccupancy,
    device const CellIdentity* cellIdentities,
    device const atomic_uint* ownerCellHeads,
    device const uint* ownerCellNext,
    uint owner,
    uint cellIndex,
    uint retainedComponentRoot
) {
    uint otherIndex = atomic_load_explicit(
        &ownerCellHeads[owner], memory_order_relaxed
    );
    while (otherIndex != emptySpatialHashEntry) {
        uint nextIndex = ownerCellNext[otherIndex];
        bool occupied = otherIndex != cellIndex &&
            atomic_load_explicit(&cellOccupancy[otherIndex], memory_order_relaxed) != 0u;
        bool outsideRetainedComponent = retainedComponentRoot >= maxCellCount ||
            cellIdentities[otherIndex].componentRoot != retainedComponentRoot;
        if (occupied && outsideRetainedComponent) {
            uint pairKey = cellPairKey(cellIndex, otherIndex);
            uint fingerprint = cellPairFingerprint(
                cellIdentities, cellIndex, otherIndex
            );
            uint junctionIndex = findCellJunction(
                junctionStates, pairKey, fingerprint
            );
            if (junctionIndex < cellJunctionCapacity) {
                atomic_store_explicit(
                    &junctionStates[junctionIndex].pairKey,
                    emptySpatialHashEntry,
                    memory_order_relaxed
                );
            }
        }
        otherIndex = nextIndex;
    }
}

kernel void evolveOrganismCells(
    device const AgentState* agents [[buffer(0)]],
    device const atomic_uint* agentOccupancy [[buffer(1)]],
    device const CellState* cellsIn [[buffer(2)]],
    device CellState* cellsOut [[buffer(3)]],
    device atomic_uint* cellOccupancy [[buffer(4)]],
    constant SimulationUniforms& uniforms [[buffer(5)]],
    device atomic_int* mechanicalForcing [[buffer(6)]],
    device const DevelopmentalGenome* developmentalGenomes [[buffer(7)]],
    device const RegulatoryNode* regulatoryNodes [[buffer(8)]],
    device const RegulatoryEdge* regulatoryEdges [[buffer(9)]],
    device float* regulatoryStates [[buffer(10)]],
    device const ResonanceGenome* resonanceGenomes [[buffer(11)]],
    device CellIdentity* cellIdentities [[buffer(12)]],
    device const atomic_uint* ownerCellHeads [[buffer(13)]],
    device const uint* ownerCellNext [[buffer(14)]],
    device const HeritableProgram* heritablePrograms [[buffer(15)]],
    device float4* programInteractions [[buffer(16)]],
    device const CellAggregate* cellAggregates [[buffer(17)]],
    device ProgramSlotState* programSlots [[buffer(18)]],
    device atomic_uint* identityCounters [[buffer(19)]],
    device atomic_uint* cellEnergyExchange [[buffer(20)]],
    device atomic_int* energyAudit [[buffer(21)]],
    device CellJunctionState* cellJunctions [[buffer(22)]],
    device atomic_uint* contactWorkState [[buffer(23)]],
    device const atomic_uint* activeCellCount [[buffer(29)]],
    device const uint* activeCellIndices [[buffer(30)]],
    texture2d_array<float, access::read> state [[texture(0)]],
    texture2d_array<float, access::read> ecology [[texture(1)]],
    texture2d_array<float, access::read> environment [[texture(2)]],
    texture2d_array<float, access::read> events [[texture(3)]],
    texture2d_array<float, access::read> mechanicalField [[texture(4)]],
    texture2d_array<float, access::read> developmentalField [[texture(5)]],
    uint compactIndex [[thread_position_in_grid]]
) {
    if (compactIndex >= atomic_load_explicit(activeCellCount, memory_order_relaxed)) { return; }
    uint gid = activeCellIndices[compactIndex];
    if (gid >= maxCellCount) { return; }
    CellIdentity cellIdentity = cellIdentities[gid];
    uint owner = cellIdentity.owner;
    if (owner >= maxAgentCount) { return; }
    if (atomic_load_explicit(&agentOccupancy[owner], memory_order_relaxed) == 0u) {
        if (atomic_load_explicit(&cellOccupancy[gid], memory_order_relaxed) != 0u) {
            invalidateCellJunctions(
                cellJunctions, cellOccupancy, cellIdentities,
                ownerCellHeads, ownerCellNext, owner, gid, emptySpatialHashEntry
            );
            releaseHeritableProgram(
                programSlots, identityCounters,
                cellIdentity.programIndex, cellIdentity.programGeneration
            );
            atomic_store_explicit(&cellOccupancy[gid], 0u, memory_order_relaxed);
            atomic_store_explicit(&contactWorkState[2], 1u, memory_order_relaxed);
            cellIdentity.owner = maxAgentCount;
            cellIdentity.programIndex = maxHeritableProgramCount;
            cellIdentity.componentRoot = emptySpatialHashEntry;
            cellIdentity.programGeneration = 0u;
            cellIdentities[gid] = cellIdentity;
        }
        return;
    }
    if (atomic_load_explicit(&cellOccupancy[gid], memory_order_relaxed) == 0u) {
        return;
    }

    uint programIndex = cellIdentity.programIndex;
    if (!programSlotMatches(programSlots, programIndex, cellIdentity.programGeneration)) {
        invalidateCellJunctions(
            cellJunctions, cellOccupancy, cellIdentities,
            ownerCellHeads, ownerCellNext, owner, gid, emptySpatialHashEntry
        );
        atomic_store_explicit(&cellOccupancy[gid], 0u, memory_order_relaxed);
        atomic_store_explicit(&contactWorkState[2], 1u, memory_order_relaxed);
        cellIdentity.owner = maxAgentCount;
        cellIdentity.programIndex = maxHeritableProgramCount;
        cellIdentity.componentRoot = emptySpatialHashEntry;
        cellIdentity.programGeneration = 0u;
        cellIdentities[gid] = cellIdentity;
        return;
    }
    AgentState agent = agentWithCellProgram(
        agents[owner], programIndex, heritablePrograms
    );
    CellState cell = cellsIn[gid];
    DevelopmentalGenome development = developmentalGenomes[programIndex];
    ResonanceGenome resonanceGenome = resonanceGenomes[programIndex];
    bool mixedProgramTissue = cellAggregates[owner].inheritance.y > 0.0001;
    float preDetachmentProgram = saturate(
        cell.tissueGeometry.z * cell.regulationB.w * development.mechanochemistryB.w *
        mix(1.16, 0.28, cell.phenotype.x)
    );
    float detachmentRelease = saturate(cell.tissueGeometry.w + preDetachmentProgram * 0.56);
    // The component origin is a coordinate frame, not a biological attractor.
    // Cohesion is supplied by explicit membrane contacts and persistent junctions.
    float2 mechanicalForce = float2(0.0);
    float2 morphogenFlux = float2(0.0);
    float2 morphogenGradient = float2(0.0);
    float junctionConductance = 0.0;
    float junctionMaterialDemand = 0.0;
    float junctionStrainMemory = 0.0;
    float junctionPolarityAlignment = 0.0;
    float2 nearestContact = float2(0.0);
    float nearestDistance = 10.0;
    float contactCount = 0.0;
    float neighborVoltage = 0.0;
    float phaseCoupling = 0.0;
    float2 phaseVector = float2(0.0);
    float neighborCalcium = 0.0;
    float neighborERK = 0.0;
    float2 erkGradient = float2(0.0);
    float sharingContactWeight = 0.0;
    float mixedContactWeight = 0.0;
    float atpSharingPotential = 0.0;
    float incomingRejectionTotal = 0.0;
    float outgoingRejectionTotal = 0.0;
    float recognitionCompatibilityTotal = 0.0;
    float cellJunctionRepairUrgency = cellularRepairUrgency(
        cell.physiology.w,
        cell.signals.z,
        0.0,
        saturate(cell.tissueForce.z * 520.0)
    );
    float cellSupportPotential = repairAdjustedATPPotential(
        cell.physiology.x, cellJunctionRepairUrgency
    );
    uint otherIndex = atomic_load_explicit(&ownerCellHeads[owner], memory_order_relaxed);
    while (otherIndex != emptySpatialHashEntry) {
        uint nextIndex = ownerCellNext[otherIndex];
        if (otherIndex == gid ||
            atomic_load_explicit(&cellOccupancy[otherIndex], memory_order_relaxed) == 0u) {
            otherIndex = nextIndex;
            continue;
        }
        CellState other = cellsIn[otherIndex];
        float2 delta = other.position - cell.position;
        float distance = max(length(delta), 0.0001);
        float2 direction = delta / distance;
        if (distance < 0.58) {
            float weight = 1.0 - distance / 0.58;
            uint pairKey = cellPairKey(gid, otherIndex);
            uint fingerprint = cellPairFingerprint(cellIdentities, gid, otherIndex);
            uint junctionIndex = findCellJunction(cellJunctions, pairKey, fingerprint);
            if (junctionIndex < cellJunctionCapacity) {
                uint lastSeen = atomic_load_explicit(
                    &cellJunctions[junctionIndex].lastSeenStep, memory_order_relaxed
                );
                bool recent = uniforms.step >= lastSeen && uniforms.step - lastSeen <= 2u;
                if (recent) {
                    float maturity = smoothstep(
                        2.0, 36.0, cellJunctions[junctionIndex].age
                    );
                    float integrityGate = min(cell.physiology.w, other.physiology.w);
                    float loadGate = 1.0 / (
                        1.0 + max(cellJunctions[junctionIndex].load, 0.0) * 18.0
                    );
                    float4 junctionMaterial = max(
                        cellJunctions[junctionIndex].material, float4(0.0)
                    );
                    float conductance = max(
                        cellJunctions[junctionIndex].strength, 0.0
                    ) * junctionMaterial.z * maturity * integrityGate * loadGate * weight;
                    float2 difference = other.signals.xy - cell.signals.xy;
                    float2 transportedDifference = difference *
                        development.morphogenTransport.zw;
                    morphogenFlux += transportedDifference * conductance;
                    float receptorDifference =
                        difference.x * development.morphogenTransport.x -
                        difference.y * development.morphogenTransport.y;
                    morphogenGradient += direction * receptorDifference * conductance;
                    junctionConductance += conductance;
                    junctionMaterialDemand += maturity * weight * (
                        junctionMaterial.x * 0.30 + junctionMaterial.z * 0.24 +
                        junctionMaterial.w * 0.20
                    );
                    junctionStrainMemory += abs(
                        cellJunctions[junctionIndex].remodeling.y
                    ) * weight;
                    junctionPolarityAlignment +=
                        cellJunctions[junctionIndex].remodeling.w * weight;
                    uint transportProgramIndex = cellIdentities[otherIndex].programIndex;
                    AgentState transportProgram = agent;
                    float transportCompatibility = 1.0;
                    if (transportProgramIndex < maxHeritableProgramCount &&
                        transportProgramIndex != programIndex) {
                        transportProgram = agentWithCellProgram(
                            agents[owner], transportProgramIndex, heritablePrograms
                        );
                        transportCompatibility = recognitionCompatibility(
                            agent, transportProgram
                        );
                    }
                    float sharingGain = min(agent.social.y, transportProgram.social.y) *
                        transportCompatibility;
                    float otherRepairUrgency = cellularRepairUrgency(
                        other.physiology.w,
                        other.signals.z,
                        0.0,
                        saturate(other.tissueForce.z * 520.0)
                    );
                    float otherSupportPotential = repairAdjustedATPPotential(
                        other.physiology.x, otherRepairUrgency
                    );
                    atpSharingPotential +=
                        (otherSupportPotential - cellSupportPotential) *
                            sharingGain * conductance;
                    sharingContactWeight += conductance;
                }
            }
            neighborVoltage += other.dynamics.x * weight;
            float otherAngle = other.dynamics.z * 2.0 * M_PI_F;
            phaseVector += float2(cos(otherAngle), sin(otherAngle)) * weight;
            neighborCalcium += other.signaling.x * weight;
            neighborERK += other.signaling.y * weight;
            erkGradient += direction * (other.signaling.y - cell.signaling.y) * weight;
            float senderInfluence = 0.52 + other.phenotype.y * 0.72;
            float receiverSusceptibility = 0.48 + cell.phenotype.x * 0.62;
            float directedPhaseLag = (other.signals.y - cell.signals.y) * 0.52 +
                (other.phenotype.z - cell.phenotype.z) * 0.24;
            phaseCoupling += sin(
                (other.dynamics.z - cell.dynamics.z) * 2.0 * M_PI_F - directedPhaseLag
            ) * weight * senderInfluence * receiverSusceptibility;
            uint otherProgramIndex = mixedProgramTissue
                ? cellIdentities[otherIndex].programIndex : programIndex;
            if (otherProgramIndex < maxHeritableProgramCount && otherProgramIndex != programIndex) {
                AgentState otherProgram = agentWithCellProgram(
                    agents[owner], otherProgramIndex, heritablePrograms
                );
                float compatibility = recognitionCompatibility(agent, otherProgram);
                float incompatibility = 1.0 - compatibility;
                incomingRejectionTotal += otherProgram.social.z * incompatibility * weight;
                outgoingRejectionTotal += agent.social.z * incompatibility * weight;
                recognitionCompatibilityTotal += compatibility * weight;
                mixedContactWeight += weight;
            }
            contactCount += weight;
            if (distance < nearestDistance) {
                nearestDistance = distance;
                nearestContact = direction;
            }
        }
        otherIndex = nextIndex;
    }

    float inverseMixedContactWeight = 1.0 / max(mixedContactWeight, 0.0001);
    float atpSharingFlux = sharingContactWeight > 0.0001
        ? clamp(atpSharingPotential / sharingContactWeight * 0.00034, -0.0014, 0.0014)
        : 0.0;
    float incomingRejection = mixedContactWeight > 0.0001
        ? saturate(incomingRejectionTotal * inverseMixedContactWeight) : 0.0;
    float outgoingRejection = mixedContactWeight > 0.0001
        ? saturate(outgoingRejectionTotal * inverseMixedContactWeight) : 0.0;
    float meanRecognitionCompatibility = mixedContactWeight > 0.0001
        ? saturate(recognitionCompatibilityTotal * inverseMixedContactWeight) : -1.0;

    float2 heading = tissueHeading(agent);
    float2 lateral = float2(-heading.y, heading.x);
    float2 worldPosition = clamp(
        cellWorldPosition(agent, cell.position, uniforms),
        float2(0.0), float2(1.0)
    );
    uint2 coordinate = min(
        uint2(worldPosition * float2(uniforms.width, uniforms.height)),
        uint2(uniforms.width - 1u, uniforms.height - 1u)
    );
    float4 localState = state.read(coordinate, 0);
    float4 localEcology = ecology.read(coordinate, 0);
    float4 localEnvironment = environment.read(coordinate, 0);
    float4 localEvents = events.read(coordinate, 0);
    float4 localMechanical = mechanicalField.read(coordinate, 0);
    float4 localDevelopmentalField = developmentalField.read(coordinate, 0);
    uint2 coordinateLeft = uint2(max(int(coordinate.x) - 1, 0), coordinate.y);
    uint2 coordinateRight = uint2(min(coordinate.x + 1u, uniforms.width - 1u), coordinate.y);
    uint2 coordinateDown = uint2(coordinate.x, max(int(coordinate.y) - 1, 0));
    uint2 coordinateUp = uint2(coordinate.x, min(coordinate.y + 1u, uniforms.height - 1u));
    float2 nutrientGradientWorld = float2(
        state.read(coordinateRight, 0).x - state.read(coordinateLeft, 0).x,
        state.read(coordinateUp, 0).x - state.read(coordinateDown, 0).x
    );
    float2 mineralGradientWorld = float2(
        ecology.read(coordinateRight, 0).x - ecology.read(coordinateLeft, 0).x,
        ecology.read(coordinateUp, 0).x - ecology.read(coordinateDown, 0).x
    );
    float2 secondaryResourceGradientWorld = float2(
        ecology.read(coordinateRight, 0).y - ecology.read(coordinateLeft, 0).y,
        ecology.read(coordinateUp, 0).y - ecology.read(coordinateDown, 0).y
    );
    float2 dangerGradientWorld = float2(
        environment.read(coordinateRight, 0).z + environment.read(coordinateRight, 0).w -
            environment.read(coordinateLeft, 0).z - environment.read(coordinateLeft, 0).w,
        environment.read(coordinateUp, 0).z + environment.read(coordinateUp, 0).w -
            environment.read(coordinateDown, 0).z - environment.read(coordinateDown, 0).w
    );
    float2 rockGradientWorld = float2(
        environment.read(coordinateRight, 0).w - environment.read(coordinateLeft, 0).w,
        environment.read(coordinateUp, 0).w - environment.read(coordinateDown, 0).w
    );
    float2 extracellularLigandGradientWorld = float2(
        (developmentalField.read(coordinateRight, 0).x -
            developmentalField.read(coordinateLeft, 0).x) *
                development.morphogenTransport.x -
            (developmentalField.read(coordinateRight, 0).y -
                developmentalField.read(coordinateLeft, 0).y) *
                development.morphogenTransport.y,
        (developmentalField.read(coordinateUp, 0).x -
            developmentalField.read(coordinateDown, 0).x) *
                development.morphogenTransport.x -
            (developmentalField.read(coordinateUp, 0).y -
                developmentalField.read(coordinateDown, 0).y) *
                development.morphogenTransport.y
    );
    morphogenGradient += rotateWorldToTissue(
        extracellularLigandGradientWorld, agent
    ) * (0.42 + cell.tissueGeometry.z * 0.58);
    float barrierLoad = smoothstep(0.30, 0.82, localEnvironment.w) *
        saturate(uniforms.intervention.y);
    float2 barrierNormalWorld = length(rockGradientWorld) > 0.00001
        ? -normalize(rockGradientWorld)
        : -normalize(agent.velocity + heading * 0.000001);
    float2 barrierForceLocal = rotateWorldToTissue(
        barrierNormalWorld * barrierLoad *
            (0.000060 + saturate(length(agent.velocity) * 720.0) * 0.000115),
        agent
    );
    float2 localSubstrateForcing = substrateForcing(
        worldPosition, localEnvironment, uniforms.step
    );
    float localEnvironmentalFrequency = environmentalFrequency(
        worldPosition, localEnvironment
    );
    float environmentalDrive = environmentalMechanicalAmplitude(localEnvironment);
    float2 ecologicalGradientLocal = rotateWorldToTissue(
        nutrientGradientWorld * agent.geneC.x + mineralGradientWorld * agent.geneC.y +
            secondaryResourceGradientWorld * agent.geneC.z -
            dangerGradientWorld * (0.72 + agent.geneA.w * 1.18),
        agent
    );
    float2 displacementX = mechanicalField.read(coordinateRight, 0).xy -
        mechanicalField.read(coordinateLeft, 0).xy;
    float2 displacementY = mechanicalField.read(coordinateUp, 0).xy -
        mechanicalField.read(coordinateDown, 0).xy;
    float fieldStrain = saturate((length(displacementX) + length(displacementY)) * 18.0);
    float fieldWaveSpeed = saturate(length(localMechanical.zw) * 85.0);

    float oldVoltage = cell.dynamics.x;
    float recovery = cell.dynamics.y;
    float meanNeighborVoltage = contactCount > 0.001 ? neighborVoltage / contactCount : oldVoltage;
    float gapCoupling = (meanNeighborVoltage - oldVoltage) * (0.10 + cell.phenotype.x * 0.16);
    float phaseDrive = sin(cell.dynamics.z * 2.0 * M_PI_F);
    float directionalInput = dot(localMechanical.zw, heading) * resonanceGenome.tuning.w;
    float strainInput = fieldStrain + directionalInput * 4.2;
    float strainVelocity = clamp((strainInput - cell.resonance.w) * 18.0, -1.0, 1.0);
    float naturalFrequency = clamp(cell.dynamics.w, 0.0008, 0.0090);
    float angularFrequency = 2.0 * M_PI_F * naturalFrequency * 6.0;
    float resonatorDisplacement = cell.resonance.x;
    float resonatorVelocity = cell.resonance.y;
    float resonatorAcceleration = resonanceGenome.mechanics.z * strainVelocity -
        2.0 * resonanceGenome.mechanics.y * angularFrequency * resonatorVelocity -
        angularFrequency * angularFrequency * resonatorDisplacement;
    resonatorVelocity = clamp(resonatorVelocity + resonatorAcceleration * 0.055, -0.18, 0.18);
    resonatorDisplacement = clamp(resonatorDisplacement + resonatorVelocity, -0.42, 0.42);
    float resonantAmplitude = mix(
        cell.resonance.z,
        abs(resonatorVelocity) + abs(resonatorDisplacement) * angularFrequency,
        0.075
    );
    float responseThreshold = resonanceGenome.mechanics.w;
    float resonantResponse = sign(resonatorDisplacement) * smoothstep(
        responseThreshold,
        responseThreshold + max(resonanceGenome.tuning.x, 0.0004) * 18.0,
        resonantAmplitude
    );
    naturalFrequency = clamp(
        naturalFrequency * (1.0 + resonanceGenome.tuning.y * strainVelocity *
            sign(resonatorVelocity) * 0.12),
        max(resonanceGenome.mechanics.x - resonanceGenome.tuning.x, 0.0008),
        min(resonanceGenome.mechanics.x + resonanceGenome.tuning.x, 0.0090)
    );
    float tuningBandwidth = max(resonanceGenome.tuning.x, 0.0004);
    float frequencyMismatch = abs(naturalFrequency - localEnvironmentalFrequency);
    float frequencyMatch = 1.0 - smoothstep(
        tuningBandwidth, tuningBandwidth * 2.5, frequencyMismatch
    );
    float meanNeighborCalcium = contactCount > 0.001
        ? neighborCalcium / contactCount
        : cell.signaling.x;
    float meanNeighborERK = contactCount > 0.001
        ? neighborERK / contactCount
        : cell.signaling.y;
    float previousCalcium = saturate(cell.signaling.x);
    float previousERK = saturate(cell.signaling.y);
    float previousRefractory = saturate(cell.signaling.z);
    float signalingAvailability = (1.0 - previousRefractory) * (1.0 - previousRefractory);
    float junctionSignalGain = (0.30 + cell.phenotype.x * 0.54) *
        development.mechanochemistryA.y;
    float neighborCalciumDrive = max(meanNeighborCalcium - previousCalcium, 0.0) *
        junctionSignalGain * (1.0 - previousRefractory);
    float extrusionCalciumDrive = cell.signals.w * (0.10 + cell.physiology.w * 0.16);
    float calciumLoss = previousCalcium * (0.0090 + previousRefractory * 0.0140);
    float calciumWithoutMechanical = clamp(
        previousCalcium + neighborCalciumDrive * 0.018 + extrusionCalciumDrive * 0.012 - calciumLoss,
        0.0, 1.0
    );
    float mechanicalCalciumGate = saturate(
        abs(resonantResponse) * 0.58 + fieldStrain * 0.26 +
        saturate(junctionStrainMemory * 3.2) * 0.34 +
        saturate(cell.membrane.w * 8.0) * 0.14
    ) * signalingAvailability * saturate(uniforms.intervention.x) *
        development.mechanochemistryA.x;
    float calcium = clamp(
        calciumWithoutMechanical + mechanicalCalciumGate * (1.0 - previousCalcium) * 0.032,
        0.0, 1.0
    );
    float mechanicsToCalciumEffect = max(calcium - calciumWithoutMechanical, 0.0);

    float neighborERKDrive = max(meanNeighborERK - previousERK, 0.0) *
        (0.22 + cell.phenotype.x * 0.42) * development.mechanochemistryA.y;
    float erkLoss = previousERK * (0.0042 + previousRefractory * 0.010);
    float erkWithoutCalcium = clamp(
        previousERK + neighborERKDrive * 0.016 - erkLoss,
        0.0, 1.0
    );
    float calciumERKDrive = smoothstep(0.08, 0.46, calcium) * (1.0 - previousRefractory) *
        development.mechanochemistryA.z;
    float erk = clamp(
        erkWithoutCalcium + calciumERKDrive * (1.0 - previousERK) * 0.026,
        0.0, 1.0
    );
    float calciumToERKEffect = max(erk - erkWithoutCalcium, 0.0);
    float refractory = clamp(
        previousRefractory + erk * 0.0068 - previousRefractory * 0.0046 *
            development.mechanochemistryA.w,
        0.0, 1.0
    );
    float neighborSignalInput = saturate(max(meanNeighborCalcium, meanNeighborERK));
    float mechanosensoryDrive = resonantResponse * (0.10 + agent.geneA.z * 0.26) *
        saturate(uniforms.intervention.x);
    float metabolicDrive = (cell.physiology.x - 0.46) * 0.22;
    float calciumCurrent = max(calcium - 0.08, 0.0) * 0.065;
    float voltageDerivative = (
        oldVoltage - oldVoltage * oldVoltage * oldVoltage / 3.0 - recovery +
        0.19 + metabolicDrive + gapCoupling + mechanosensoryDrive + calciumCurrent +
        phaseDrive * 0.10
    ) * 0.020;
    float voltage = clamp(oldVoltage + voltageDerivative, -1.8, 1.8);
    recovery = clamp(recovery + 0.0038 * (voltage + 0.56 - recovery * 0.78), -0.8, 1.8);
    float phaseSynchronization = contactCount > 0.001 ? phaseCoupling / contactCount : 0.0;
    float phaseAdvance = naturalFrequency * (0.72 + cell.physiology.x * 0.42) +
        phaseSynchronization * (0.00035 + cell.phenotype.x * 0.0017) +
        mechanosensoryDrive * 0.0008 + voltageDerivative * 0.0015;
    float oscillatorPhase = fract(cell.dynamics.z + phaseAdvance + 1.0);
    float localCoherence = contactCount > 0.001
        ? saturate(length(phaseVector) / contactCount)
        : 1.0;
    float contractionPulse = pow(saturate(0.5 + 0.5 * sin(oscillatorPhase * 2.0 * M_PI_F)), 3.0);
    float contractility = mix(cell.mechanics.x,
        contractionPulse * cell.phenotype.y * saturate(cell.physiology.x) *
        (0.72 + max(voltage, 0.0) * 0.20) * (0.68 + erk * 0.62), 0.11);

    float membraneExposure = saturate(cell.tissueGeometry.z);
    float uptakePotential = 0.00125 * (
        localState.x * cell.phenotype.z + localEcology.x * cell.phenotype.w +
        localEcology.y * agent.geneC.z * 0.34
    );
    float extracellularAccess = pow(membraneExposure, 0.70);
    uptakePotential *= extracellularAccess;
    float metabolicReadiness = smoothstep(0.12, 0.46, cell.physiology.x);
    float maintenance = 0.000055 * (
        0.62 + cell.physiology.y * 0.48 + cell.phenotype.y * 0.28
    );
    float extracellularMatrixSupport = smoothstep(
        0.025, 0.42, localDevelopmentalField.z
    );
    float woundCue = saturate(localDevelopmentalField.w);
    float externalStress = saturate((
        localEnvironment.z * 0.72 + localEnvironment.w * 0.36 + localEcology.z * 0.58 +
        localEvents.z * 0.24 + max(contactCount - 4.5, 0.0) * 0.08 +
        incomingRejection * 0.44 + barrierLoad * 0.24 +
        environmentalDrive * (1.0 - frequencyMatch) * 0.30
    ) * mix(1.0, 0.78, extracellularMatrixSupport) + woundCue * 0.46);
    float resourceTotal = max(localState.x + localEcology.x + localEcology.y, 0.0001);
    float extracellularReceptorBalance =
        localDevelopmentalField.x * development.morphogenTransport.x -
        localDevelopmentalField.y * development.morphogenTransport.y;
    float regulatorySensors[16] = {
        clamp(cell.physiology.x * 2.0 - 1.0, -1.0, 1.0),
        clamp(voltage / 1.8, -1.0, 1.0),
        fieldStrain,
        saturate(contactCount / 4.2),
        clamp(
            cell.signals.x * development.morphogenTransport.x -
                cell.signals.y * development.morphogenTransport.y +
                extracellularReceptorBalance * 0.46 +
                (cell.development.z - 0.5) * 0.35,
            -1.0, 1.0
        ),
        clamp(uptakePotential * 1350.0 - externalStress - cell.signals.z * 0.35, -1.0, 1.0),
        clamp(resonantResponse, -1.0, 1.0),
        saturate(cell.membrane.w * 8.0 + abs(cell.membrane.z - 1.0)),
        clamp((cell.membrane.z - 1.0) * 1.8, -1.0, 1.0),
        saturate(cell.membrane.w * 6.0 + junctionStrainMemory * 2.0 + woundCue * 0.65),
        saturate(localEnvironment.z * 0.70 + localEcology.z * 0.85 +
            localEcology.y * 0.12 + woundCue * 0.72),
        clamp((localState.x - localEcology.x) / resourceTotal, -1.0, 1.0),
        saturate(incomingRejection + mixedContactWeight * 0.16),
        saturate(junctionConductance * 0.55 + junctionStrainMemory * 2.4),
        membraneExposure,
        clamp((cell.development.z - 0.5) * 1.4 +
            junctionPolarityAlignment / max(contactCount, 0.001), -1.0, 1.0)
    };
    RegulatoryOutputs regulatoryOutput = evolveDevelopmentalProgram(
        developmentalGenomes, regulatoryNodes, regulatoryEdges, regulatoryStates,
        programIndex, gid, regulatorySensors
    );
    float4 regulation = regulatoryOutput.a;
    float4 regulationB = regulatoryOutput.b;
    float proliferationProgram = regulation.x;
    float adhesiveProgram = regulation.y;
    float contractileProgram = regulation.z;
    float repairProgram = regulation.w;
    float permeabilityProgram = regulationB.x;
    float secretionProgram = regulationB.y;
    float apoptosisSuppression = regulationB.z;
    float motilityProgram = regulationB.w;
    float localContactDamage = saturate(cell.tissueForce.z * 520.0);
    float integrityDeficit = max(1.0 - saturate(cell.physiology.w), 0.0);
    float repairUrgency = cellularRepairUrgency(
        cell.physiology.w, cell.signals.z, woundCue, localContactDamage
    );
    float repairCommitment = saturate(
        repairProgram * (0.35 + repairUrgency * 0.85)
    );
    // Local damage reallocates activity rather than granting extra energy.
    // The allocation disappears continuously when the wound resolves.
    float recoveryAllocation = saturate(
        repairUrgency * mix(0.46, 1.0, repairProgram)
    );
    float discretionaryActivityScale = 1.0 - recoveryAllocation * 0.78;
    float ecologicalScarcity = 1.0 - smoothstep(0.035, 0.24, resourceTotal);
    float toxinLoad = saturate(localEnvironment.z * 0.72 + localEcology.z * 0.88);
    float toxinTolerance = development.ecologicalResponse.x * repairProgram;
    float detritalScavenging = development.ecologicalResponse.y * permeabilityProgram;
    float shearAnchoring = development.ecologicalResponse.z * adhesiveProgram;
    float starvationQuiescence = development.ecologicalResponse.w *
        (1.0 - proliferationProgram) * ecologicalScarcity;
    externalStress = saturate(
        externalStress - toxinLoad * toxinTolerance * 0.68 -
            environmentalDrive * shearAnchoring * 720.0
    );
    float2 previousMorphogens = saturate(cell.signals.xy);
    float activatorAutocatalysis = previousMorphogens.x * previousMorphogens.x /
        max(0.08 + previousMorphogens.x * previousMorphogens.x, 0.0001);
    float inhibitorSuppression = 1.0 / (
        1.0 + previousMorphogens.y * development.morphogenTransport.y * 1.4
    );
    float2 morphogenProduction = float2(
        development.morphogenKinetics.x * mix(0.34, 1.20, secretionProgram) *
            mix(0.42, 1.0, activatorAutocatalysis) * inhibitorSuppression * 0.00155,
        development.morphogenKinetics.y * mix(1.05, 0.46, secretionProgram) *
            (0.48 + previousMorphogens.x * development.morphogenTransport.x * 0.52) *
            0.00145
    ) * mix(0.28, 1.0, metabolicReadiness);
    float2 morphogenDecay = development.morphogenKinetics.zw *
        previousMorphogens * 0.00135;
    float2 morphogenDiffusion = clamp(
        morphogenFlux * 0.010, float2(-0.018), float2(0.018)
    );
    float2 extracellularLigandCoupling = clamp(
        (localDevelopmentalField.xy - previousMorphogens) *
            development.morphogenTransport.xy * membraneExposure * 0.0032,
        float2(-0.006), float2(0.006)
    );
    float2 nextMorphogens = clamp(
        previousMorphogens + morphogenProduction - morphogenDecay +
            morphogenDiffusion + extracellularLigandCoupling,
        float2(0.0), float2(1.0)
    );
    float receptorBalance =
        nextMorphogens.x * development.morphogenTransport.x -
        nextMorphogens.y * development.morphogenTransport.y;
    float fateTarget = saturate(
        0.5 + receptorBalance * 0.42 +
            (contractileProgram - adhesiveProgram) * 0.13 +
            (motilityProgram - repairProgram) * 0.07 +
            (membraneExposure - 0.5) * 0.18
    );
    float fateMemory = mix(
        saturate(cell.development.z), fateTarget,
        0.0035 + saturate(junctionConductance) * 0.0025
    );
    float2 previousPolarity = length(cell.development.xy) > 0.0001
        ? normalize(cell.development.xy)
        : float2(1.0, 0.0);
    float2 polarityTarget = length(morphogenGradient) > 0.0001
        ? normalize(morphogenGradient)
        : previousPolarity;
    float polarityResponse = 0.010 + saturate(length(morphogenGradient) * 4.0) * 0.035;
    float2 developmentalPolarity = normalize(
        mix(previousPolarity, polarityTarget, polarityResponse) + previousPolarity * 0.0001
    );
    float junctionTransport = abs(morphogenDiffusion.x) + abs(morphogenDiffusion.y);
    float morphogenWork =
        (morphogenProduction.x + morphogenProduction.y) * 0.018 +
        (abs(morphogenDiffusion.x) + abs(morphogenDiffusion.y)) * 0.006;
    float junctionTransportWork = abs(atpSharingFlux) * 0.040;
    float allocationContrast = saturate(abs(receptorBalance) * 0.82 + abs(fateMemory - 0.5));
    float predatoryConstruction = membraneExposure * secretionProgram * motilityProgram *
        saturate((agent.geneC.w - 0.025) * 2.2) * saturate(cell.physiology.x) *
        mix(0.62, 1.28, fateMemory) * metabolicReadiness * discretionaryActivityScale;
    float armorConstruction = membraneExposure * adhesiveProgram * repairProgram *
        agent.geneA.w * saturate(cell.physiology.x) * mix(1.24, 0.68, fateMemory) *
        metabolicReadiness * mix(0.72, 1.0, discretionaryActivityScale);
    float sensorConstruction = membraneExposure * permeabilityProgram * secretionProgram *
        (0.35 + saturate(resonantAmplitude * 5.0) * 0.65) *
        (0.70 + allocationContrast * 0.48) * metabolicReadiness *
        mix(0.74, 1.0, discretionaryActivityScale);
    float locomotorConstruction = membraneExposure * motilityProgram * erk *
        saturate(cell.physiology.x) * mix(0.72, 1.22, fateMemory) * metabolicReadiness *
        discretionaryActivityScale;
    float localMatrixNeed = 1.0 - extracellularMatrixSupport;
    float extracellularMatrixConstruction = membraneExposure * adhesiveProgram *
        repairProgram * saturate(cell.physiology.x) *
        (0.30 + woundCue * 0.74 + repairUrgency * 0.58) *
        (0.62 + localMatrixNeed * 0.38) * metabolicReadiness;
    float extracellularMatrixRemodeling = membraneExposure * motilityProgram *
        secretionProgram * extracellularMatrixSupport *
        (0.20 + woundCue * 0.80) * metabolicReadiness;
    float structuralDrag = 1.0 / (
        1.0 + armorConstruction * 1.50 + predatoryConstruction * 0.35 +
            sensorConstruction * 0.12
    );
    float uptakeGain = mix(0.66, 1.42, permeabilityProgram) *
        (1.0 - armorConstruction * 0.28);
    uint energyTileBase = (coordinate.y * uniforms.width + coordinate.x) *
        worldExchangeChannelCount;
    float requestedResourceA = localState.x * cell.phenotype.z * 0.00125 *
        uptakeGain * extracellularAccess;
    float requestedResourceB = localEcology.x * cell.phenotype.w * 0.00125 *
        uptakeGain * extracellularAccess;
    float requestedDetritus = localEcology.y * agent.geneC.z * 0.00043 *
        uptakeGain * (1.0 + detritalScavenging * 2.10) * extracellularAccess;
    float consumedResourceA = claimSubstrate(
        &cellEnergyExchange[energyTileBase], requestedResourceA
    );
    float consumedResourceB = claimSubstrate(
        &cellEnergyExchange[energyTileBase + 1u], requestedResourceB
    );
    float consumedDetritus = claimSubstrate(
        &cellEnergyExchange[energyTileBase + 2u], requestedDetritus
    );
    addEnergyExchange(cellEnergyExchange, energyTileBase, 3u, consumedResourceA);
    addEnergyExchange(cellEnergyExchange, energyTileBase, 4u, consumedResourceB);
    addEnergyExchange(cellEnergyExchange, energyTileBase, 5u, consumedDetritus);
    float substrateEnergy = consumedResourceA * 0.78 + consumedResourceB * 0.90 +
        consumedDetritus * 0.62;
    float conversionEfficiency = clamp(
        0.52 + agent.geneA.w * 0.28 - max(agent.geneC.x + agent.geneC.y +
            agent.geneC.z - 1.30, 0.0) * 0.08,
        0.34, 0.88
    );
    float uptake = substrateEnergy * conversionEfficiency;
    float conversionHeat = max(substrateEnergy - uptake, 0.0);
    contractility *= mix(0.52, 1.58, contractileProgram) * (1.0 + calcium * 0.18) *
        mix(0.22, 1.0, metabolicReadiness) *
        mix(0.44, 1.0, discretionaryActivityScale);
    maintenance *= (0.94 + repairProgram * 0.16 + proliferationProgram * 0.10) *
        mix(0.20, 1.0, metabolicReadiness) *
        mix(1.0, 0.48, starvationQuiescence);
    float signalingCost = (calcium * 0.000020 + erk * 0.000024 +
        (mechanicsToCalciumEffect + calciumToERKEffect) * 0.000080) *
        development.mechanochemistryB.x;
    float resonatorEnergy = resonatorVelocity * resonatorVelocity +
        angularFrequency * angularFrequency * resonatorDisplacement * resonatorDisplacement;
    float frequencyWork = resonatorEnergy * (0.00042 + naturalFrequency * 0.075) *
        (0.58 + resonanceGenome.mechanics.y * 0.82);
    float constructionWork = armorConstruction * 0.000070 +
        predatoryConstruction * 0.000060 + sensorConstruction * 0.000025 +
        locomotorConstruction * 0.000040 +
        extracellularMatrixConstruction * 0.000052 +
        extracellularMatrixRemodeling * 0.000030;
    float junctionMaterialWork = junctionMaterialDemand * 0.0000045 +
        junctionStrainMemory * 0.000016;
    float cellularCatalystSecretion = secretionProgram * agent.geneA.y *
        agent.geneA.w * membraneExposure * metabolicReadiness *
        (0.000002 + localEcology.y * 0.000014);
    float cellularToxinNeutralization = toxinTolerance * toxinLoad *
        membraneExposure * metabolicReadiness * 0.000018;
    float ecologicalResponseWork = toxinTolerance * toxinLoad * 0.000022 +
        detritalScavenging * consumedDetritus * 0.045 +
        shearAnchoring * environmentalDrive * 0.075 +
        development.ecologicalResponse.w * 0.0000025 +
        cellularCatalystSecretion * 0.85 + cellularToxinNeutralization * 0.72;
    float propagulePreparation = membraneExposure * motilityProgram *
        development.mechanochemistryB.w * (1.0 - adhesiveProgram) *
        smoothstep(0.16, 0.38, cell.physiology.x) * discretionaryActivityScale;
    float crossbreedingPreparation = mixedProgramTissue &&
        meanRecognitionCompatibility >= 0.0
        ? saturate(meanRecognitionCompatibility) * agent.social.w *
            saturate(junctionConductance) * metabolicReadiness *
            discretionaryActivityScale
        : 0.0;
    float requestedRepairWork = repairUrgency * repairCommitment * (
        0.00010 + integrityDeficit * 0.00050 + woundCue * 0.00010 +
        localContactDamage * 0.000055
    );
    float discretionaryActiveWork = (contractility * (0.000055 + fieldStrain * 0.000070) +
        abs(voltageDerivative) * 0.000070 + signalingCost + frequencyWork +
        constructionWork + propagulePreparation * 0.000060 + morphogenWork +
        crossbreedingPreparation * 0.000075 + junctionTransportWork +
        junctionMaterialWork + ecologicalResponseWork) *
        mix(0.16, 1.0, metabolicReadiness) * discretionaryActivityScale;
    float activeWork = discretionaryActiveWork + requestedRepairWork;
    float dissipation = externalStress * 0.00032 + fieldWaveSpeed * 0.000035 +
        dot(cell.velocity, cell.velocity) * 2.8 + barrierLoad *
            saturate(length(agent.velocity) * 860.0) * 0.00010;
    float rejectionCost = outgoingRejection * 0.000055;
    float rejectionDamage = incomingRejection * 0.00018;
    float plannedATPExpense = maintenance + activeWork + dissipation +
        rejectionCost + rejectionDamage;
    float availableATP = max(cell.physiology.x + uptake + atpSharingFlux, 0.0);
    float expenseScale = plannedATPExpense > 0.0
        ? min(availableATP / plannedATPExpense, 1.0) : 1.0;
    maintenance *= expenseScale;
    activeWork *= expenseScale;
    frequencyWork *= expenseScale;
    dissipation *= expenseScale;
    rejectionCost *= expenseScale;
    rejectionDamage *= expenseScale;
    float paidRepairWork = requestedRepairWork * expenseScale;
    float paidATPExpense = maintenance + activeWork + dissipation +
        rejectionCost + rejectionDamage;
    float unclampedATP = availableATP - paidATPExpense;
    float overflowHeat = max(unclampedATP - 1.2, 0.0);
    float atp = clamp(unclampedATP, 0.0, 1.2);
    float netProgramContribution = uptake - paidATPExpense;
    float detritusEnergy = maintenance * 0.34;
    float heatExport = conversionHeat + maintenance * 0.66 + dissipation +
        rejectionCost + rejectionDamage + overflowHeat;
    float detritusReturn = detritusEnergy / 0.62;
    addEnergyExchange(cellEnergyExchange, energyTileBase, 6u, detritusReturn);
    addEnergyExchange(cellEnergyExchange, energyTileBase, 7u, heatExport);
    float developmentalOutputScale = expenseScale * metabolicReadiness;
    addEnergyExchange(
        cellEnergyExchange, energyTileBase, 8u,
        morphogenProduction.x * secretionProgram * membraneExposure *
            developmentalOutputScale * 0.22
    );
    addEnergyExchange(
        cellEnergyExchange, energyTileBase, 9u,
        morphogenProduction.y * secretionProgram * membraneExposure *
            developmentalOutputScale * 0.22
    );
    addEnergyExchange(
        cellEnergyExchange, energyTileBase, 10u,
        extracellularMatrixConstruction * developmentalOutputScale * 0.00016
    );
    addEnergyExchange(
        cellEnergyExchange, energyTileBase, 11u,
        (extracellularMatrixRemodeling * 0.000060 +
            max(1.0 - cell.physiology.w, 0.0) * repairProgram * 0.000075) *
            developmentalOutputScale
    );
    addEnergyExchange(
        cellEnergyExchange, energyTileBase, 12u,
        cellularCatalystSecretion * expenseScale
    );
    addEnergyExchange(
        cellEnergyExchange, energyTileBase, 13u,
        cellularToxinNeutralization * expenseScale
    );
    float atpStorageDelta = atp - cell.physiology.x;
    float conservationResidual = substrateEnergy + atpSharingFlux -
        (atpStorageDelta + activeWork + detritusEnergy + heatExport);
    addEnergyAudit(energyAudit, 0u, substrateEnergy);
    addEnergyAudit(energyAudit, 1u, uptake);
    addEnergyAudit(energyAudit, 2u, atpStorageDelta);
    addEnergyAudit(energyAudit, 3u, activeWork);
    addEnergyAudit(energyAudit, 4u, frequencyWork);
    addEnergyAudit(energyAudit, 5u, maintenance);
    addEnergyAudit(energyAudit, 6u, heatExport);
    addEnergyAudit(energyAudit, 7u, detritusEnergy);
    addEnergyAudit(energyAudit, 8u, atpSharingFlux);
    addEnergyAudit(energyAudit, 9u, conservationResidual);
    float repairSatisfaction = requestedRepairWork > 0.0000001
        ? saturate(paidRepairWork / requestedRepairWork) : 1.0;
    float energyStrain = saturate(
        (1.0 - expenseScale) * 0.82 +
        (1.0 - smoothstep(0.025, 0.18, atp)) * 0.18
    );
    float unresolvedRepair = repairUrgency * (1.0 - repairSatisfaction);
    float stressTarget = saturate(
        externalStress + energyStrain * 0.46 + unresolvedRepair * 0.24
    );
    float stressResponse = stressTarget > cell.signals.z
        ? 0.026 : 0.012 + repairCommitment * repairSatisfaction * 0.024;
    float stress = mix(cell.signals.z, stressTarget, stressResponse);
    float apoptosis = clamp(
        cell.signals.w + max(stress - 0.72, 0.0) * 0.0024 - 0.00022 -
            repairProgram * 0.00030 - apoptosisSuppression * 0.00034 +
            incomingRejection * 0.00040,
        0.0, 1.0
    );
    float permeabilityTurnover = permeabilityProgram * 0.000024 *
        mix(0.18, 1.0, metabolicReadiness);
    float membraneRepairEfficiency = mix(1.20, 2.35, repairProgram) *
        (0.82 + extracellularMatrixSupport * 0.18);
    float membraneRepair = paidRepairWork * membraneRepairEfficiency +
        repairProgram * metabolicReadiness * 0.000018;
    float membraneATPSetpoint = mix(0.12, 0.27, metabolicReadiness);
    float membraneIntegrity = clamp(
        cell.physiology.w + (atp - membraneATPSetpoint) * 0.00020 + membraneRepair -
            stress * 0.00022 - apoptosis * 0.00031 - permeabilityTurnover -
            incomingRejection * 0.00026,
        0.0, 1.0
    );
    float energySupport = cellularEnergySupport(
        atp, float4(uptake, maintenance, activeWork, dissipation)
    );
    float anabolicDrive = energySupport * mix(0.50, 1.0, membraneExposure) *
        mix(0.42, 1.38, proliferationProgram);
    float catabolicDrive = (1.0 - energySupport) *
        mix(1.0, 0.58, smoothstep(0.08, 0.30, atp));
    float proposedBiomass = clamp(
        cell.physiology.y + anabolicDrive * 0.00018 - catabolicDrive * 0.000090,
        0.16, 1.08
    );
    float biomassDelta = proposedBiomass - cell.physiology.y;
    float biomassEnergyDelta = biomassDelta * 0.18;
    float biosynthesisCost = min(max(biomassEnergyDelta, 0.0), atp);
    float biomass = biomassDelta > 0.0
        ? cell.physiology.y + biosynthesisCost / 0.18
        : proposedBiomass;
    float atpBeforeBiomass = atp;
    atp -= biosynthesisCost;
    float releasedBiomassEnergy = max(-biomassEnergyDelta, 0.0);
    float catabolicATPShare = 0.52 * (1.0 - smoothstep(0.18, 0.46, atp));
    float biomassCatabolicATP = releasedBiomassEnergy * catabolicATPShare;
    float exportedBiomassEnergy = releasedBiomassEnergy - biomassCatabolicATP;
    float biomassDetritusEnergy = exportedBiomassEnergy * 0.64;
    float biomassHeat = exportedBiomassEnergy * 0.36;
    atp = min(atp + biomassCatabolicATP, 1.2);
    if (releasedBiomassEnergy > 0.0) {
        addEnergyExchange(
            cellEnergyExchange, energyTileBase, 6u, biomassDetritusEnergy / 0.62
        );
        addEnergyExchange(cellEnergyExchange, energyTileBase, 7u, biomassHeat);
    }
    float storageCorrection = (atp - atpBeforeBiomass) +
        (biomass - cell.physiology.y) * 0.18;
    addEnergyAudit(energyAudit, 2u, storageCorrection);
    addEnergyAudit(energyAudit, 6u, biomassHeat);
    addEnergyAudit(energyAudit, 7u, biomassDetritusEnergy);
    addEnergyAudit(
        energyAudit, 9u,
        -(storageCorrection + biomassHeat + biomassDetritusEnergy)
    );
    float contactInhibition = saturate(contactCount / (3.6 + cell.phenotype.x * 1.8));
    float unconstrainedCycleDrive = cellCycleDrive(
        atp, biomass, float4(uptake, maintenance, activeWork, dissipation),
        proliferationProgram, stress, membraneExposure
    );
    float contactBrake = contactInhibition * (0.62 + adhesiveProgram * 0.30);
    float cycleRate = unconstrainedCycleDrive * (1.0 - contactBrake) *
        (1.0 - starvationQuiescence * 0.88) *
        (1.0 - recoveryAllocation * 0.94);
    float cycleDecay = cellCycleQuiescenceDecay(energySupport, contactBrake, stress);
    float cycle = clamp(
        cell.physiology.z + cycleRate - cycleDecay,
        0.0, 1.2
    );

    cell.signals.xy = nextMorphogens;
    cell.signals.zw = float2(stress, apoptosis);
    float centralProgram = fateMemory;
    cell.phenotype.x = mix(cell.phenotype.x,
        clamp(0.14 + agent.geneA.y * 0.30 + centralProgram * 0.16 + adhesiveProgram * 0.42, 0.0, 1.0),
        0.0060);
    cell.phenotype.y = mix(cell.phenotype.y,
        clamp(0.10 + agent.geneA.z * 0.26 + (1.0 - centralProgram) * 0.18 + contractileProgram * 0.48,
            0.0, 1.0), 0.0060);
    cell.phenotype.z = mix(cell.phenotype.z,
        clamp(0.12 + agent.geneC.x * 0.50 + centralProgram * 0.12 + proliferationProgram * 0.16,
            0.0, 1.0), 0.0040);
    cell.phenotype.w = mix(cell.phenotype.w,
        clamp(0.12 + agent.geneC.y * 0.50 + (1.0 - centralProgram) * 0.12 + repairProgram * 0.16,
            0.0, 1.0), 0.0040);
    cell.physiology = float4(atp, biomass, cycle, membraneIntegrity);
    cell.dynamics = float4(voltage, recovery, oscillatorPhase, naturalFrequency);
    cell.mechanics = float4(contractility, fieldStrain, fieldWaveSpeed, localCoherence);
    cell.energetics = float4(uptake, maintenance, activeWork, dissipation);
    cell.regulation = regulation;
    cell.regulationB = regulationB;
    cell.resonance = float4(
        resonatorDisplacement, resonatorVelocity, resonantAmplitude, strainInput
    );
    cell.development = float4(
        developmentalPolarity, fateMemory, junctionTransport
    );

    float2 boundaryNormal = length(cell.tissueGeometry.xy) > 0.0001
        ? normalize(cell.tissueGeometry.xy)
        : developmentalPolarity;
    float exposure = saturate(cell.tissueGeometry.z);
    float2 antiWaveDirection = length(erkGradient) > 0.0001
        ? -normalize(erkGradient)
        : boundaryNormal;
    float starvationDrive = 1.0 - metabolicReadiness;
    float2 tractionDirection = ecologicalGradientLocal *
        (2.8 + permeabilityProgram * 2.2 + starvationDrive * 7.0) +
        antiWaveDirection * erk * (0.48 + motilityProgram * 0.86) *
            mix(0.34, 1.0, metabolicReadiness) +
        developmentalPolarity * (0.16 + allocationContrast * 0.18) *
            mix(0.38, 1.0, metabolicReadiness);
    if (length(erkGradient) > 0.0001) {
        tractionDirection += normalize(erkGradient) * repairProgram *
            saturate(junctionConductance) * (0.22 + (1.0 - membraneIntegrity) * 0.78);
    }
    tractionDirection = length(tractionDirection) > 0.0001
        ? normalize(tractionDirection)
        : boundaryNormal;
    float tractionGain = development.mechanochemistryB.y;
    float tractionActivation = exposure * motilityProgram *
        mix(0.22, 1.0, metabolicReadiness) *
        (0.16 + erk * 1.05);
    float2 activeTraction = tractionDirection * tractionActivation * tractionGain *
        (0.000045 + cell.phenotype.y * 0.000105) *
        (0.46 + adhesiveProgram * 0.54) *
        (1.0 + extracellularMatrixSupport * adhesiveProgram * 0.38) * structuralDrag;
    activeTraction += boundaryNormal * exposure * contractility * tractionGain *
        (0.000014 + adhesiveProgram * 0.000026) * structuralDrag;
    float2 localFieldMotion = rotateWorldToTissue(localMechanical.xy, agent);
    if (length(localFieldMotion) > 0.000001) {
        activeTraction -= normalize(localFieldMotion) * shearAnchoring *
            environmentalDrive * (0.08 + frequencyMatch * 0.10) *
            mix(0.30, 1.0, metabolicReadiness);
    }
    float propaguleDrive = exposure * motilityProgram * development.mechanochemistryB.w *
        (1.0 - adhesiveProgram) * smoothstep(0.16, 0.38, atp);
    activeTraction += boundaryNormal * propaguleDrive *
        (0.00018 + detachmentRelease * 0.00012) * structuralDrag;
    activeTraction *= expenseScale;
    mechanicalForce += activeTraction + barrierForceLocal;
    mechanicalForce += float2(
        dot(localMechanical.xy, heading),
        dot(localMechanical.xy, lateral)
    ) * (0.0008 + agent.geneA.z * 0.0014);
    cell.velocity = cell.velocity * mix(0.90, 0.62, barrierLoad) + mechanicalForce;
    float cellSpeed = length(cell.velocity);
    if (cellSpeed > 0.0024) { cell.velocity *= 0.0024 / cellSpeed; }
    cell.position += cell.velocity * uniforms.transportScale;

    cell.interaction = float4(
        nearestContact,
        contactBrake,
        mechanosensoryDrive * 0.020
    );
    cell.signaling = float4(calcium, erk, refractory, neighborSignalInput);
    cell.signalCausality = float4(
        mechanicsToCalciumEffect,
        calciumToERKEffect,
        length(activeTraction),
        signalingCost
    );
    cell.environment = float4(
        (localSubstrateForcing.x + localSubstrateForcing.y) * 0.5,
        barrierLoad,
        localEnvironmentalFrequency,
        frequencyMatch
    );
    programInteractions[gid] = float4(
        atpSharingFlux,
        incomingRejection,
        meanRecognitionCompatibility,
        netProgramContribution
    );
    float isolation = saturate(1.0 - contactCount / 0.72);
    float detachmentScore = detachmentReadinessScore(
        exposure,
        isolation,
        cell.physiology.x,
        cell.physiology.w,
        cell.phenotype.x,
        development.mechanochemistryB.w
    );
    cell.tissueForce = float4(activeTraction + barrierForceLocal, 0.0, 0.0);
    cell.tissueGeometry.w = saturate(detachmentScore);

    float2 localContractionDirection = exposure > 0.05
        ? -boundaryNormal
        : (nearestDistance < 10.0 ? nearestContact : developmentalPolarity);
    float2 worldActiveTraction = rotateTissueToWorld(activeTraction, agent);
    float2 worldContraction =
        (heading * localContractionDirection.x + lateral * localContractionDirection.y) *
            contractility * membraneIntegrity * 0.0082 * expenseScale +
        worldActiveTraction * 2.4;
    uint forcingIndex = (coordinate.y * uniforms.width + coordinate.x) * 2u;
    int forceX = int(clamp(worldContraction.x * float(mechanicalForceScale), -8192.0, 8192.0));
    int forceY = int(clamp(worldContraction.y * float(mechanicalForceScale), -8192.0, 8192.0));
    atomic_fetch_add_explicit(&mechanicalForcing[forcingIndex], forceX, memory_order_relaxed);
    atomic_fetch_add_explicit(&mechanicalForcing[forcingIndex + 1u], forceY, memory_order_relaxed);

    if (membraneIntegrity < 0.055 || apoptosis > 0.985 ||
        (atp < 0.008 && stress > 0.82)) {
        invalidateCellJunctions(
            cellJunctions, cellOccupancy, cellIdentities,
            ownerCellHeads, ownerCellNext, owner, gid, emptySpatialHashEntry
        );
        float terminalATP = max(atp, 0.0);
        float terminalBiomassEnergy = max(biomass, 0.0) * 0.18;
        float terminalEnergy = terminalATP + terminalBiomassEnergy;
        float terminalDetritusEnergy = terminalEnergy * 0.72;
        float terminalHeat = terminalEnergy * 0.28;
        addEnergyExchange(
            cellEnergyExchange, energyTileBase, 6u, terminalDetritusEnergy / 0.62
        );
        addEnergyExchange(cellEnergyExchange, energyTileBase, 7u, terminalHeat);
        addEnergyAudit(energyAudit, 2u, -terminalEnergy);
        addEnergyAudit(energyAudit, 6u, terminalHeat);
        addEnergyAudit(energyAudit, 7u, terminalDetritusEnergy);
        addEnergyAudit(
            energyAudit, 9u, terminalEnergy - terminalHeat - terminalDetritusEnergy
        );
        releaseHeritableProgram(
            programSlots, identityCounters, programIndex, cellIdentity.programGeneration
        );
        atomic_store_explicit(&cellOccupancy[gid], 0u, memory_order_relaxed);
        atomic_store_explicit(&contactWorkState[2], 1u, memory_order_relaxed);
        cellIdentity.owner = maxAgentCount;
        cellIdentity.programIndex = maxHeritableProgramCount;
        cellIdentity.componentRoot = emptySpatialHashEntry;
        cellIdentity.programGeneration = 0u;
        cellIdentities[gid] = cellIdentity;
    }
    cellsOut[gid] = cell;
}

kernel void evolveCellMembranes(
    device const CellState* cellsIn [[buffer(0)]],
    device CellState* cellsOut [[buffer(1)]],
    device const atomic_uint* cellOccupancy [[buffer(2)]],
    device MembraneVertex* membraneVertices [[buffer(3)]],
    constant SimulationUniforms& uniforms [[buffer(4)]],
    device const CellIdentity* cellIdentities [[buffer(5)]],
    device const AgentState* agents [[buffer(6)]],
    device const HeritableProgram* heritablePrograms [[buffer(7)]],
    device const ProgramSlotState* programSlots [[buffer(8)]],
    device const atomic_uint* activeCellCount [[buffer(29)]],
    device const uint* activeCellIndices [[buffer(30)]],
    uint compactIndex [[thread_position_in_grid]]
) {
    if (compactIndex >= atomic_load_explicit(activeCellCount, memory_order_relaxed)) { return; }
    uint gid = activeCellIndices[compactIndex];
    if (gid >= maxCellCount ||
        atomic_load_explicit(&cellOccupancy[gid], memory_order_relaxed) == 0u) { return; }

    CellState cell = cellsIn[gid];
    CellIdentity identity = cellIdentities[gid];
    uint owner = identity.owner;
    if (owner >= maxAgentCount) { return; }
    if (!programSlotMatches(
        programSlots, identity.programIndex, identity.programGeneration
    )) { return; }
    AgentState agent = agentWithCellProgram(
        agents[owner], identity.programIndex, heritablePrograms
    );
    uint membraneBase = gid * membraneVertexCount;
    float2 positions[membraneVertexCount];
    float2 velocities[membraneVertexCount];
    float localIntegrity[membraneVertexCount];
    float previousPressure[membraneVertexCount];
    bool uninitialized = membraneVertices[membraneBase].mechanics.x <= 0.0;
    float targetRadius = clamp(
        0.105 + cell.physiology.y * 0.014 - cell.mechanics.x * 0.008,
        0.085, 0.145
    );
    float restEdge = 2.0 * targetRadius * sin(M_PI_F / float(membraneVertexCount));
    for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
        MembraneVertex state = membraneVertices[membraneBase + vertexIndex];
        if (uninitialized) {
            float angle = (float(vertexIndex) / float(membraneVertexCount)) * 2.0 * M_PI_F +
                cell.dynamics.z * 0.26;
            state.position = float2(cos(angle), sin(angle)) * targetRadius;
            state.velocity = float2(0.0);
            state.mechanics = float4(restEdge, cell.physiology.w, 0.0, 0.0);
        }
        positions[vertexIndex] = state.position;
        velocities[vertexIndex] = state.velocity;
        localIntegrity[vertexIndex] = state.mechanics.y;
        previousPressure[vertexIndex] = max(state.mechanics.z, 0.0);
    }

    float exposure = saturate(cell.tissueGeometry.z);
    float2 boundaryNormal = length(cell.tissueGeometry.xy) > 0.0001
        ? normalize(cell.tissueGeometry.xy)
        : (length(cell.development.xy) > 0.0001
            ? normalize(cell.development.xy)
            : float2(cos(cell.dynamics.z * 2.0 * M_PI_F),
                sin(cell.dynamics.z * 2.0 * M_PI_F)));
    float2 tractionDirection = length(cell.tissueForce.xy) > 0.000001
        ? normalize(cell.tissueForce.xy) : boundaryNormal;
    float sensorAngle = cell.dynamics.z * 2.0 * M_PI_F +
        agent.geneB.w * M_PI_F + cell.resonance.x * 1.8;
    float2 sensorDirection = normalize(
        boundaryNormal * 0.52 + float2(cos(sensorAngle), sin(sensorAngle)) * 0.48
    );
    float predatoryConstruction = exposure * cell.regulationB.y * cell.regulationB.w *
        saturate((agent.geneC.w - 0.025) * 2.2) * saturate(cell.physiology.x);
    float armorConstruction = exposure * cell.regulation.y * cell.regulation.w *
        agent.geneA.w * saturate(cell.physiology.x);
    float sensorConstruction = exposure * cell.regulationB.x * cell.regulationB.y *
        (0.35 + saturate(cell.resonance.z * 5.0) * 0.65);
    float locomotorConstruction = exposure * cell.regulationB.w * cell.signaling.y *
        saturate(cell.physiology.x);

    float signedDoubleArea = 0.0;
    float perimeter = 0.0;
    for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
        uint next = (vertexIndex + 1u) % membraneVertexCount;
        signedDoubleArea += positions[vertexIndex].x * positions[next].y -
            positions[next].x * positions[vertexIndex].y;
        perimeter += length(positions[next] - positions[vertexIndex]);
    }
    float area = max(abs(signedDoubleArea) * 0.5, 0.0001);
    float targetArea = M_PI_F * targetRadius * targetRadius;
    float areaError = clamp((targetArea - area) / targetArea, -0.65, 0.65);
    float transmittedForce = 0.0;

    for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
        uint previous = (vertexIndex + membraneVertexCount - 1u) % membraneVertexCount;
        uint next = (vertexIndex + 1u) % membraneVertexCount;
        float2 current = positions[vertexIndex];
        float2 toPrevious = positions[previous] - current;
        float2 toNext = positions[next] - current;
        float previousLength = max(length(toPrevious), 0.0001);
        float nextLength = max(length(toNext), 0.0001);
        float radialLength = max(length(current), 0.0001);
        float2 radialNormal = current / radialLength;
        float predatoryLobe = pow(saturate(dot(radialNormal, boundaryNormal)), 6.0) *
            predatoryConstruction;
        float sensorLobe = pow(saturate(dot(radialNormal, sensorDirection)), 8.0) *
            sensorConstruction;
        float locomotorLobe = pow(saturate(dot(radialNormal, tractionDirection)), 4.0) *
            locomotorConstruction;
        float armorPlate = pow(saturate(dot(radialNormal, boundaryNormal)), 2.0) *
            armorConstruction;
        float vertexTargetRadius = targetRadius * (
            1.0 + predatoryLobe * 0.58 + sensorLobe * 0.34 +
            locomotorLobe * 0.24 + armorPlate * 0.10
        );
        float stiffness = mix(0.006, 0.026, saturate(cell.physiology.w *
            localIntegrity[vertexIndex])) * (1.0 + armorPlate * 0.92);
        float2 edgeForce = toPrevious / previousLength * (previousLength - restEdge) * stiffness +
            toNext / nextLength * (nextLength - restEdge) * stiffness;
        float bendingStiffness = mix(
            0.010,
            0.030 + cell.regulation.y * 0.022,
            saturate(localIntegrity[vertexIndex])
        );
        float2 bendingForce = (positions[previous] + positions[next] - current * 2.0) *
            bendingStiffness;
        float2 pressureForce = radialNormal * areaError *
            (0.0018 + cell.physiology.x * 0.0028);
        float2 morphogenesisForce = radialNormal *
            clamp(vertexTargetRadius - radialLength, -0.08, 0.12) *
            (0.0048 + cell.regulationB.w * 0.0042 + armorPlate * 0.0020);
        float2 contractileForce = -radialNormal * cell.mechanics.x *
            (0.00028 + cell.regulation.z * 0.00062);
        float contactPressure = previousPressure[vertexIndex] * 0.72;
        float integrityTarget = clamp(
            cell.physiology.w - contactPressure * 8.0 - cell.signals.z * 0.08,
            0.04, 1.0
        );
        float integrity = mix(
            localIntegrity[vertexIndex], integrityTarget, 0.012 + cell.regulation.w * 0.014
        );
        float2 force = edgeForce + bendingForce + pressureForce + morphogenesisForce +
            contractileForce;
        float2 velocity = velocities[vertexIndex] * (0.78 + integrity * 0.12) + force;
        float speed = length(velocity);
        if (speed > 0.006) { velocity *= 0.006 / speed; }
        float2 position = current + velocity * uniforms.transportScale;
        float radius = length(position);
        float neighborRadius = 0.5 * (length(positions[previous]) + length(positions[next]));
        float radialAllowance = targetRadius * mix(0.18, 0.34, 1.0 - integrity);
        float maximumRadius = min(
            targetRadius * 1.82,
            max(vertexTargetRadius * 1.08, neighborRadius + radialAllowance)
        );
        if (radius > maximumRadius) {
            position *= maximumRadius / radius;
            velocity *= 0.35;
        }
        MembraneVertex output;
        output.position = position;
        output.velocity = velocity;
        output.mechanics = float4(
            restEdge, integrity, contactPressure,
            abs(previousLength - restEdge) + abs(nextLength - restEdge)
        );
        membraneVertices[membraneBase + vertexIndex] = output;
        transmittedForce += contactPressure;
    }

    float2 membraneCentroid = float2(0.0);
    for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
        membraneCentroid += membraneVertices[membraneBase + vertexIndex].position;
    }
    membraneCentroid /= float(membraneVertexCount);
    float centroidShiftLength = length(membraneCentroid);
    float2 transferredShift = membraneCentroid;
    if (centroidShiftLength > 0.003) {
        transferredShift *= 0.003 / centroidShiftLength;
    }
    cell.position += transferredShift;
    cell.velocity = mix(
        cell.velocity,
        cell.velocity + transferredShift / max(uniforms.transportScale, 1.0),
        0.16
    );
    for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
        uint membraneIndex = membraneBase + vertexIndex;
        MembraneVertex membranePoint = membraneVertices[membraneIndex];
        membranePoint.position -= membraneCentroid;
        positions[vertexIndex] = membranePoint.position;
        membraneVertices[membraneIndex] = membranePoint;
    }

    float centeredDoubleArea = 0.0;
    for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
        uint next = (vertexIndex + 1u) % membraneVertexCount;
        centeredDoubleArea += positions[vertexIndex].x * positions[next].y -
            positions[next].x * positions[vertexIndex].y;
    }
    for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
        uint previous = (vertexIndex + membraneVertexCount - 1u) % membraneVertexCount;
        uint next = (vertexIndex + 1u) % membraneVertexCount;
        float2 curvatureAverage =
            (positions[previous] + positions[vertexIndex] * 2.0 + positions[next]) * 0.25;
        float fairing = mix(0.20, 0.38, saturate(localIntegrity[vertexIndex]));
        velocities[vertexIndex] = mix(positions[vertexIndex], curvatureAverage, fairing);
    }
    float fairedDoubleArea = 0.0;
    for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
        uint next = (vertexIndex + 1u) % membraneVertexCount;
        fairedDoubleArea += velocities[vertexIndex].x * velocities[next].y -
            velocities[next].x * velocities[vertexIndex].y;
    }
    float areaPreservingScale = sqrt(
        max(abs(centeredDoubleArea), 0.000001) / max(abs(fairedDoubleArea), 0.000001)
    );
    areaPreservingScale = clamp(areaPreservingScale, 0.92, 1.08);
    for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
        uint membraneIndex = membraneBase + vertexIndex;
        MembraneVertex membranePoint = membraneVertices[membraneIndex];
        membranePoint.position = velocities[vertexIndex] * areaPreservingScale;
        membraneVertices[membraneIndex] = membranePoint;
    }

    float preliminaryDoubleArea = 0.0;
    float preliminaryPerimeter = 0.0;
    for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
        uint next = (vertexIndex + 1u) % membraneVertexCount;
        float2 a = membraneVertices[membraneBase + vertexIndex].position;
        float2 b = membraneVertices[membraneBase + next].position;
        preliminaryDoubleArea += a.x * b.y - b.x * a.y;
        preliminaryPerimeter += length(b - a);
    }
    float preliminaryAreaRatio = abs(preliminaryDoubleArea) * 0.5 / targetArea;
    float targetPerimeter = 2.0 * M_PI_F * targetRadius;
    float collapseRecovery = saturate((0.55 - preliminaryAreaRatio) / 0.35) * 0.58;
    float stretchRecovery = saturate(
        (preliminaryPerimeter / max(targetPerimeter, 0.0001) - 1.72) / 0.55
    ) * 0.42;
    float inversionRecovery = preliminaryDoubleArea <= 0.0 ? 0.82 : 0.0;
    float geometryRecovery = max(inversionRecovery, max(collapseRecovery, stretchRecovery));
    if (geometryRecovery > 0.0) {
        float2 firstPosition = membraneVertices[membraneBase].position;
        float referenceAngle = length(firstPosition) > 0.0001
            ? atan2(firstPosition.y, firstPosition.x)
            : cell.dynamics.z * 2.0 * M_PI_F;
        for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
            uint membraneIndex = membraneBase + vertexIndex;
            MembraneVertex membranePoint = membraneVertices[membraneIndex];
            float angle = referenceAngle +
                (float(vertexIndex) / float(membraneVertexCount)) * 2.0 * M_PI_F;
            float2 regularPosition = float2(cos(angle), sin(angle)) * targetRadius;
            membranePoint.position = mix(
                membranePoint.position, regularPosition, geometryRecovery
            );
            membranePoint.velocity *= 1.0 - geometryRecovery * 0.72;
            membraneVertices[membraneIndex] = membranePoint;
        }
    }

    float updatedDoubleArea = 0.0;
    float updatedPerimeter = 0.0;
    for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
        uint next = (vertexIndex + 1u) % membraneVertexCount;
        float2 a = membraneVertices[membraneBase + vertexIndex].position;
        float2 b = membraneVertices[membraneBase + next].position;
        updatedDoubleArea += a.x * b.y - b.x * a.y;
        float edgeLength = length(b - a);
        updatedPerimeter += edgeLength;
    }
    float updatedArea = max(abs(updatedDoubleArea) * 0.5, 0.0001);
    float shapeIndex = updatedPerimeter * updatedPerimeter /
        max(4.0 * M_PI_F * updatedArea, 0.0001);
    cell.membrane = float4(
        updatedArea, updatedPerimeter, clamp(shapeIndex, 1.0, 3.5), transmittedForce
    );
    float previousExposure = saturate(cell.tissueGeometry.z);
    float2 previousBoundaryNormal = length(cell.tissueGeometry.xy) > 0.0001
        ? normalize(cell.tissueGeometry.xy)
        : (length(cell.development.xy) > 0.0001
            ? normalize(cell.development.xy)
            : float2(cos(cell.dynamics.z * 2.0 * M_PI_F),
                sin(cell.dynamics.z * 2.0 * M_PI_F)));
    float detachmentScore = detachmentReadinessScore(
        previousExposure,
        1.0 - cell.interaction.z,
        cell.physiology.x,
        cell.physiology.w,
        cell.phenotype.x,
        1.0
    );
    cell.tissueGeometry = float4(
        previousBoundaryNormal, previousExposure, saturate(detachmentScore)
    );
    cellsOut[gid] = cell;
}

kernel void clearCellSpatialHash(
    device atomic_uint* hashHeads [[buffer(0)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid < cellSpatialHashBucketCount) {
        atomic_store_explicit(&hashHeads[gid], emptySpatialHashEntry, memory_order_relaxed);
    }
}

kernel void clearActiveCellContactEffects(
    device atomic_int* contactEffects [[buffer(0)]],
    device atomic_int* membraneContactEffects [[buffer(1)]],
    device atomic_uint* topologySignatures [[buffer(2)]],
    device const atomic_uint* activeCellCount [[buffer(29)]],
    device const uint* activeCellIndices [[buffer(30)]],
    uint compactIndex [[thread_position_in_grid]]
) {
    if (compactIndex >= atomic_load_explicit(activeCellCount, memory_order_relaxed)) { return; }
    uint cellIndex = activeCellIndices[compactIndex];
    if (cellIndex >= maxCellCount) { return; }
    for (uint channel = 0u; channel < 4u; ++channel) {
        atomic_store_explicit(
            &contactEffects[cellIndex * 4u + channel], 0, memory_order_relaxed
        );
    }
    uint membraneBase = cellIndex * membraneVertexCount * 3u;
    for (uint channel = 0u; channel < membraneVertexCount * 3u; ++channel) {
        atomic_store_explicit(
            &membraneContactEffects[membraneBase + channel], 0, memory_order_relaxed
        );
    }
    uint topologyBase = cellIndex * 4u;
    atomic_store_explicit(&topologySignatures[topologyBase], 0u, memory_order_relaxed);
    atomic_store_explicit(&topologySignatures[topologyBase + 1u], 0u, memory_order_relaxed);
}

kernel void clearOwnerCellLists(
    device atomic_uint* ownerCellHeads [[buffer(0)]],
    device const uint* activeComponents [[buffer(1)]],
    device const atomic_uint* activeComponentCount [[buffer(2)]],
    uint compactIndex [[thread_position_in_grid]]
) {
    if (compactIndex >= atomic_load_explicit(activeComponentCount, memory_order_relaxed)) { return; }
    uint owner = activeComponents[compactIndex];
    if (owner < maxAgentCount) {
        atomic_store_explicit(
            &ownerCellHeads[owner], emptySpatialHashEntry, memory_order_relaxed
        );
    }
}

inline void insertOwnedCellSorted(
    device atomic_uint* ownerCellHeads,
    device atomic_uint* ownerCellNext,
    uint gid,
    uint owner
) {
    atomic_store_explicit(&ownerCellNext[gid], emptySpatialHashEntry, memory_order_relaxed);
    for (uint attempt = 0u; attempt < maxCellCount; ++attempt) {
        device atomic_uint* insertionLink = &ownerCellHeads[owner];
        uint successor = atomic_load_explicit(insertionLink, memory_order_relaxed);
        while (successor < gid) {
            insertionLink = &ownerCellNext[successor];
            successor = atomic_load_explicit(insertionLink, memory_order_relaxed);
        }
        if (successor == gid) { return; }
        atomic_store_explicit(&ownerCellNext[gid], successor, memory_order_relaxed);
        uint expectedSuccessor = successor;
        if (atomic_compare_exchange_weak_explicit(
            insertionLink,
            &expectedSuccessor,
            gid,
            memory_order_relaxed,
            memory_order_relaxed
        )) {
            return;
        }
    }
}

kernel void buildOwnerCellLists(
    device const atomic_uint* agentOccupancy [[buffer(0)]],
    device const atomic_uint* cellOccupancy [[buffer(1)]],
    device const CellIdentity* cellIdentities [[buffer(2)]],
    device atomic_uint* ownerCellHeads [[buffer(3)]],
    device atomic_uint* ownerCellNext [[buffer(4)]],
    device const atomic_uint* activeCellCount [[buffer(29)]],
    device const uint* activeCellIndices [[buffer(30)]],
    uint compactIndex [[thread_position_in_grid]]
) {
    if (compactIndex >= atomic_load_explicit(activeCellCount, memory_order_relaxed)) { return; }
    uint gid = activeCellIndices[compactIndex];
    if (gid >= maxCellCount) { return; }
    uint owner = cellIdentities[gid].owner;
    if (owner >= maxAgentCount ||
        atomic_load_explicit(&agentOccupancy[owner], memory_order_relaxed) == 0u ||
        atomic_load_explicit(&cellOccupancy[gid], memory_order_relaxed) == 0u) {
        atomic_store_explicit(
            &ownerCellNext[gid], emptySpatialHashEntry, memory_order_relaxed
        );
        return;
    }
    insertOwnedCellSorted(ownerCellHeads, ownerCellNext, gid, owner);
}

kernel void buildCellSpatialHash(
    device const AgentState* agents [[buffer(0)]],
    device const atomic_uint* agentOccupancy [[buffer(1)]],
    device const CellState* cells [[buffer(2)]],
    device const atomic_uint* cellOccupancy [[buffer(3)]],
    device atomic_uint* hashHeads [[buffer(4)]],
    device uint* hashNext [[buffer(5)]],
    constant SimulationUniforms& uniforms [[buffer(6)]],
    device const CellIdentity* cellIdentities [[buffer(7)]],
    device atomic_uint* ownerCellHeads [[buffer(8)]],
    device atomic_uint* ownerCellNext [[buffer(9)]],
    device const atomic_uint* activeCellCount [[buffer(29)]],
    device const uint* activeCellIndices [[buffer(30)]],
    uint compactIndex [[thread_position_in_grid]]
) {
    if (compactIndex >= atomic_load_explicit(activeCellCount, memory_order_relaxed)) { return; }
    uint gid = activeCellIndices[compactIndex];
    if (gid >= maxCellCount) { return; }
    uint owner = cellIdentities[gid].owner;
    if (owner >= maxAgentCount ||
        atomic_load_explicit(&agentOccupancy[owner], memory_order_relaxed) == 0u ||
        atomic_load_explicit(&cellOccupancy[gid], memory_order_relaxed) == 0u) {
        hashNext[gid] = emptySpatialHashEntry;
        atomic_store_explicit(
            &ownerCellNext[gid], emptySpatialHashEntry, memory_order_relaxed
        );
        return;
    }
    float2 worldPosition = cellWorldPosition(agents[owner], cells[gid].position, uniforms);
    uint bucket = cellSpatialHash(spatialHashCoordinate(worldPosition));
    hashNext[gid] = atomic_exchange_explicit(&hashHeads[bucket], gid, memory_order_relaxed);
    insertOwnedCellSorted(ownerCellHeads, ownerCellNext, gid, owner);
}

kernel void resetMembraneContactWork(
    device atomic_uint* contactWorkState [[buffer(0)]],
    device const atomic_uint* activeCellCount [[buffer(1)]],
    constant SimulationUniforms& uniforms [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid != 0u) { return; }
    uint livingCount = atomic_load_explicit(activeCellCount, memory_order_relaxed);
    uint previousCount = atomic_load_explicit(&contactWorkState[3], memory_order_relaxed);
    bool reconcile = atomic_load_explicit(
        &contactWorkState[2], memory_order_relaxed
    ) != 0u || livingCount != previousCount ||
        uniforms.step % componentTopologyReconciliationStride == 0u;
    atomic_store_explicit(&contactWorkState[0], 0u, memory_order_relaxed);
    atomic_store_explicit(&contactWorkState[1], 0u, memory_order_relaxed);
    atomic_store_explicit(&contactWorkState[2], reconcile ? 1u : 0u, memory_order_relaxed);
}

kernel void buildMembraneContactPairs(
    device const AgentState* agents [[buffer(0)]],
    device const atomic_uint* agentOccupancy [[buffer(1)]],
    device const CellState* cells [[buffer(2)]],
    device const atomic_uint* cellOccupancy [[buffer(3)]],
    device const atomic_uint* hashHeads [[buffer(4)]],
    device const uint* hashNext [[buffer(5)]],
    device const CellIdentity* cellIdentities [[buffer(6)]],
    device uint2* contactPairs [[buffer(7)]],
    device atomic_uint* contactWorkState [[buffer(8)]],
    constant SimulationUniforms& uniforms [[buffer(9)]],
    device const atomic_uint* activeCellCount [[buffer(29)]],
    device const uint* activeCellIndices [[buffer(30)]],
    uint compactIndex [[thread_position_in_grid]]
) {
    if (compactIndex >= atomic_load_explicit(activeCellCount, memory_order_relaxed)) { return; }
    uint gid = activeCellIndices[compactIndex];
    if (gid >= maxCellCount ||
        atomic_load_explicit(&cellOccupancy[gid], memory_order_relaxed) == 0u) { return; }
    uint owner = cellIdentities[gid].owner;
    if (owner >= maxAgentCount ||
        atomic_load_explicit(&agentOccupancy[owner], memory_order_relaxed) == 0u) { return; }

    float scale = max(cellWorldScale(uniforms), 0.0000001);
    float2 worldPosition = cellWorldPosition(agents[owner], cells[gid].position, uniforms);
    int2 baseCoordinate = int2(spatialHashCoordinate(worldPosition));
    for (int offsetY = -2; offsetY <= 2; ++offsetY) {
        for (int offsetX = -2; offsetX <= 2; ++offsetX) {
            int2 candidateCoordinate = baseCoordinate + int2(offsetX, offsetY);
            if (any(candidateCoordinate < int2(0)) ||
                any(candidateCoordinate >= int2(cellSpatialHashAxisResolution))) { continue; }
            uint bucket = cellSpatialHash(uint2(candidateCoordinate));
            uint otherIndex = atomic_load_explicit(&hashHeads[bucket], memory_order_relaxed);
            uint traversed = 0u;
            while (otherIndex != emptySpatialHashEntry && traversed < 96u) {
                uint nextIndex = hashNext[otherIndex];
                if (otherIndex > gid &&
                    atomic_load_explicit(&cellOccupancy[otherIndex], memory_order_relaxed) != 0u) {
                    uint otherOwner = cellIdentities[otherIndex].owner;
                    if (otherOwner < maxAgentCount &&
                        atomic_load_explicit(
                            &agentOccupancy[otherOwner], memory_order_relaxed
                        ) != 0u) {
                        float2 otherWorldPosition = cellWorldPosition(
                            agents[otherOwner], cells[otherIndex].position, uniforms
                        );
                        if (length(otherWorldPosition - worldPosition) / scale <= 0.72) {
                            uint pairIndex = atomic_fetch_add_explicit(
                                &contactWorkState[0], 1u, memory_order_relaxed
                            );
                            if (pairIndex < membraneContactPairCapacity) {
                                contactPairs[pairIndex] = uint2(gid, otherIndex);
                            }
                        }
                    }
                }
                otherIndex = nextIndex;
                traversed += 1u;
            }
        }
    }
}

kernel void prepareMembraneContactDispatch(
    device atomic_uint* contactWorkState [[buffer(0)]],
    device uint* dispatchArguments [[buffer(1)]],
    device atomic_uint* invariantState [[buffer(2)]],
    constant SimulationUniforms& uniforms [[buffer(3)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid != 0u) { return; }
    uint rawCount = atomic_load_explicit(&contactWorkState[0], memory_order_relaxed);
    uint pairCount = min(rawCount, membraneContactPairCapacity);
    bool overflow = rawCount > membraneContactPairCapacity;
    atomic_store_explicit(&contactWorkState[0], pairCount, memory_order_relaxed);
    atomic_store_explicit(&contactWorkState[1], overflow ? 1u : 0u, memory_order_relaxed);
    dispatchArguments[0] = (pairCount + 63u) / 64u;
    dispatchArguments[1] = 1u;
    dispatchArguments[2] = 1u;
    if (overflow) {
        atomic_fetch_or_explicit(
            &invariantState[0], invariantContactPairOverflow, memory_order_relaxed
        );
        atomic_fetch_min_explicit(&invariantState[1], uniforms.step, memory_order_relaxed);
        atomic_fetch_add_explicit(&invariantState[17], 1u, memory_order_relaxed);
    }
}

inline uint cellPairKey(uint indexA, uint indexB) {
    uint lower = min(indexA, indexB);
    uint upper = max(indexA, indexB);
    return lower * maxCellCount + upper + 1u;
}

inline uint cellPairFingerprint(
    device const CellIdentity* identities,
    uint indexA,
    uint indexB
) {
    uint lowerID = min(identities[indexA].persistentID, identities[indexB].persistentID);
    uint upperID = max(identities[indexA].persistentID, identities[indexB].persistentID);
    return hash32(lowerID ^ hash32(upperID + 0x9e3779b9u));
}

inline uint findOrCreateCellJunction(
    device CellJunctionState* junctionStates,
    uint pairKey,
    uint fingerprint,
    uint step,
    float restDistance,
    float targetStrength
) {
    uint start = hash32(pairKey) & cellJunctionMask;
    // Deletion leaves holes in this bounded open-addressed table. Always scan
    // the complete probe window for an existing key before reusing a hole;
    // otherwise a collision behind a cleared slot becomes unreachable and a
    // duplicate junction can survive component reassignment.
    for (uint probe = 0u; probe < 12u; ++probe) {
        uint slot = (start + probe) & cellJunctionMask;
        uint observedKey = atomic_load_explicit(
            &junctionStates[slot].pairKey, memory_order_relaxed
        );
        if (observedKey == pairKey &&
            junctionStates[slot].persistentFingerprint == fingerprint) {
            atomic_store_explicit(
                &junctionStates[slot].lastSeenStep, step, memory_order_relaxed
            );
            junctionStates[slot].age = min(junctionStates[slot].age + 1.0, 65535.0);
            junctionStates[slot].strength = mix(
                junctionStates[slot].strength, targetStrength, 0.08
            );
            return slot;
        }
    }
    for (uint probe = 0u; probe < 12u; ++probe) {
        uint slot = (start + probe) & cellJunctionMask;
        uint observedKey = atomic_load_explicit(
            &junctionStates[slot].pairKey, memory_order_relaxed
        );
        if (observedKey == reservedCellJunctionEntry) { continue; }
        uint lastSeen = atomic_load_explicit(
            &junctionStates[slot].lastSeenStep, memory_order_relaxed
        );
        bool stale = step > lastSeen && step - lastSeen > 180u;
        if (observedKey == emptySpatialHashEntry || stale ||
            (observedKey == pairKey &&
                junctionStates[slot].persistentFingerprint != fingerprint)) {
            uint expected = observedKey;
            if (atomic_compare_exchange_weak_explicit(
                &junctionStates[slot].pairKey, &expected, reservedCellJunctionEntry,
                memory_order_relaxed, memory_order_relaxed
            )) {
                junctionStates[slot].persistentFingerprint = fingerprint;
                junctionStates[slot].flags = 1u;
                junctionStates[slot].restDistance = restDistance;
                junctionStates[slot].strength = targetStrength;
                junctionStates[slot].age = 1.0;
                junctionStates[slot].load = 0.0;
                junctionStates[slot].material = float4(
                    max(targetStrength, 0.05), 0.35, 0.30, 0.25
                );
                junctionStates[slot].remodeling = float4(
                    restDistance, 0.0, 0.0, 0.0
                );
                atomic_store_explicit(
                    &junctionStates[slot].lastSeenStep, step, memory_order_relaxed
                );
                atomic_store_explicit(
                    &junctionStates[slot].pairKey, pairKey, memory_order_relaxed
                );
                return slot;
            }
        }
    }
    return cellJunctionCapacity;
}

inline uint findCellJunction(
    device const CellJunctionState* junctionStates,
    uint pairKey,
    uint fingerprint
) {
    uint start = hash32(pairKey) & cellJunctionMask;
    for (uint probe = 0u; probe < 12u; ++probe) {
        uint slot = (start + probe) & cellJunctionMask;
        uint observedKey = atomic_load_explicit(
            &junctionStates[slot].pairKey, memory_order_relaxed
        );
        if (observedKey == pairKey &&
            junctionStates[slot].persistentFingerprint == fingerprint) {
            return slot;
        }
    }
    return cellJunctionCapacity;
}

inline void accumulateMembraneContactForce(
    device atomic_int* membraneContactEffects,
    uint cellIndex,
    uint vertexIndex,
    float2 worldForce,
    float pressure
) {
    uint base = (cellIndex * membraneVertexCount + vertexIndex) * 3u;
    int forceX = int(clamp(
        worldForce.x * float(cellContactForceScale), -1048576.0, 1048576.0
    ));
    int forceY = int(clamp(
        worldForce.y * float(cellContactForceScale), -1048576.0, 1048576.0
    ));
    int fixedPressure = int(clamp(
        pressure * float(cellContactScalarScale), 0.0, 1048576.0
    ));
    atomic_fetch_add_explicit(
        &membraneContactEffects[base], forceX, memory_order_relaxed
    );
    atomic_fetch_add_explicit(
        &membraneContactEffects[base + 1u], forceY, memory_order_relaxed
    );
    atomic_fetch_add_explicit(
        &membraneContactEffects[base + 2u], fixedPressure, memory_order_relaxed
    );
}

kernel void resolveMembraneContacts(
    device const AgentState* agents [[buffer(0)]],
    device const atomic_uint* agentOccupancy [[buffer(1)]],
    device const CellState* cells [[buffer(2)]],
    device const atomic_uint* cellOccupancy [[buffer(3)]],
    device const MembraneVertex* membraneVertices [[buffer(4)]],
    device const uint2* contactPairs [[buffer(5)]],
    device atomic_uint* contactWorkState [[buffer(6)]],
    device atomic_int* contactEffects [[buffer(7)]],
    constant SimulationUniforms& uniforms [[buffer(8)]],
    device const CellIdentity* cellIdentities [[buffer(9)]],
    device const HeritableProgram* heritablePrograms [[buffer(10)]],
    device CellJunctionState* junctionStates [[buffer(11)]],
    device atomic_int* membraneContactEffects [[buffer(12)]],
    device const ProgramSlotState* programSlots [[buffer(13)]],
    device atomic_int* energyAudit [[buffer(14)]],
    device atomic_uint* identityCounters [[buffer(15)]],
    device atomic_uint* topologySignatures [[buffer(16)]],
    device const DevelopmentalGenome* developmentalGenomes [[buffer(17)]],
    uint pairIndex [[thread_position_in_grid]]
) {
    if (pairIndex >= atomic_load_explicit(&contactWorkState[0], memory_order_relaxed)) { return; }
    uint2 pair = contactPairs[pairIndex];
    uint gid = pair.x;
    uint otherIndex = pair.y;
    if (gid >= maxCellCount || otherIndex >= maxCellCount ||
        atomic_load_explicit(&cellOccupancy[gid], memory_order_relaxed) == 0u ||
        atomic_load_explicit(&cellOccupancy[otherIndex], memory_order_relaxed) == 0u) { return; }
    uint owner = cellIdentities[gid].owner;
    uint otherOwner = cellIdentities[otherIndex].owner;
    if (owner >= maxAgentCount || otherOwner >= maxAgentCount ||
        atomic_load_explicit(&agentOccupancy[owner], memory_order_relaxed) == 0u ||
        atomic_load_explicit(&agentOccupancy[otherOwner], memory_order_relaxed) == 0u) { return; }

    uint programIndex = cellIdentities[gid].programIndex;
    uint otherProgramIndex = cellIdentities[otherIndex].programIndex;
    if (!programSlotMatches(
        programSlots, programIndex, cellIdentities[gid].programGeneration
    ) || !programSlotMatches(
        programSlots, otherProgramIndex, cellIdentities[otherIndex].programGeneration
    )) { return; }
    AgentState agent = agentWithCellProgram(
        agents[owner], programIndex, heritablePrograms
    );
    AgentState otherAgent = agentWithCellProgram(
        agents[otherOwner], otherProgramIndex, heritablePrograms
    );
    CellState cell = cells[gid];
    CellState other = cells[otherIndex];
    DevelopmentalGenome cellDevelopment = developmentalGenomes[programIndex];
    DevelopmentalGenome otherDevelopment = developmentalGenomes[otherProgramIndex];
    float4 inheritedJunctionMaterial = sqrt(max(
        cellDevelopment.junctionMaterial * otherDevelopment.junctionMaterial,
        float4(0.0001)
    ));
    float scale = cellWorldScale(uniforms);
    float2 worldPosition = cellWorldPosition(agent, cell.position, uniforms);
                        float2 otherWorldPosition = cellWorldPosition(
                            otherAgent, other.position, uniforms
                        );
                        float2 delta = otherWorldPosition - worldPosition;
                        float distance = max(length(delta), 0.0000001);
                        float2 normalWorld = delta / distance;
                        float2 localDirection = rotateWorldToTissue(normalWorld, agent);
                        float2 otherLocalDirection = rotateWorldToTissue(-normalWorld, otherAgent);
                        MembraneSupportSample supportA = membraneSupportSample(
                            membraneVertices, gid, localDirection
                        );
                        MembraneSupportSample supportB = membraneSupportSample(
                            membraneVertices, otherIndex, otherLocalDirection
                        );
                        float2 supportWorldA = worldPosition +
                            rotateTissueToWorld(supportA.point, agent) * scale;
                        float2 supportWorldB = otherWorldPosition +
                            rotateTissueToWorld(supportB.point, otherAgent) * scale;
                        float supportGap = dot(supportWorldB - supportWorldA, normalWorld);
                        float localGap = supportGap / max(scale, 0.0000001);
                        bool sameOwner = otherOwner == owner;
                        float interactionRange = sameOwner ? 0.090 : 0.012;
                        float topologyIntegrity = min(
                            min(cell.physiology.w, other.physiology.w),
                            min(supportA.integrity, supportB.integrity)
                        );
                        float topologyAdhesion = min(cell.phenotype.x, other.phenotype.x) *
                            clamp(inheritedJunctionMaterial.x, 0.10, 1.50);
                        bool topologyConnected = sameOwner && topologyIntegrity > 0.10 &&
                            localGap <= 0.050 * topologyAdhesion * topologyIntegrity;
                        if (topologyConnected) {
                            uint topologyBase = gid * 4u;
                            uint otherTopologyBase = otherIndex * 4u;
                            atomic_fetch_add_explicit(
                                &topologySignatures[topologyBase], 1u, memory_order_relaxed
                            );
                            atomic_fetch_xor_explicit(
                                &topologySignatures[topologyBase + 1u],
                                hash32(cellIdentities[otherIndex].persistentID ^ 0xa511e9b3u),
                                memory_order_relaxed
                            );
                            atomic_fetch_add_explicit(
                                &topologySignatures[otherTopologyBase], 1u, memory_order_relaxed
                            );
                            atomic_fetch_xor_explicit(
                                &topologySignatures[otherTopologyBase + 1u],
                                hash32(cellIdentities[gid].persistentID ^ 0xa511e9b3u),
                                memory_order_relaxed
                            );
                        }
                        bool newSameOwnerConnection = topologyConnected &&
                            cellIdentities[gid].componentRoot !=
                                cellIdentities[otherIndex].componentRoot;
                        bool fusionCandidate = !sameOwner && localGap < 0.008 &&
                            min(agent.social.x, otherAgent.social.x) > 0.20 &&
                            recognitionCompatibility(agent, otherAgent) > 0.35 &&
                            max(agent.geneC.w, otherAgent.geneC.w) < 0.40;
                        if (newSameOwnerConnection || fusionCandidate) {
                            atomic_store_explicit(
                                &contactWorkState[2], 1u, memory_order_relaxed
                            );
                        }
                        if (localGap < interactionRange) {
                            if (!sameOwner) {
                                atomic_fetch_add_explicit(
                                    &identityCounters[5], 1u, memory_order_relaxed
                                );
                            }
                            float localOverlap = max(-localGap, 0.0);
                            float supportSpan = max(
                                length(supportA.point) + length(supportB.point), 0.0001
                            );
                            float overlapFraction = saturate(localOverlap / supportSpan);
                            float contactStrength = smoothstep(0.0, 0.20, overlapFraction);
                            float pairDifference = saturate(
                                length(agent.geneC - otherAgent.geneC) * 0.66 +
                                length(agent.geneA - otherAgent.geneA) * 0.18
                            );
                            float2 boundaryA = length(cell.tissueGeometry.xy) > 0.0001
                                ? normalize(cell.tissueGeometry.xy) : localDirection;
                            float2 boundaryB = length(other.tissueGeometry.xy) > 0.0001
                                ? normalize(other.tissueGeometry.xy) : otherLocalDirection;
                            float attackConstructionA = cell.tissueGeometry.z *
                                cell.regulationB.y * cell.regulationB.w *
                                saturate((agent.geneC.w - 0.025) * 2.2) *
                                saturate(cell.physiology.x) *
                                pow(saturate(dot(localDirection, boundaryA)), 6.0);
                            float attackConstructionB = other.tissueGeometry.z *
                                other.regulationB.y * other.regulationB.w *
                                saturate((otherAgent.geneC.w - 0.025) * 2.2) *
                                saturate(other.physiology.x) *
                                pow(saturate(dot(otherLocalDirection, boundaryB)), 6.0);
                            float armorConstructionA = cell.tissueGeometry.z *
                                cell.regulation.y * cell.regulation.w * agent.geneA.w *
                                saturate(cell.physiology.x) *
                                pow(saturate(dot(localDirection, boundaryA)), 2.0);
                            float armorConstructionB = other.tissueGeometry.z *
                                other.regulation.y * other.regulation.w * otherAgent.geneA.w *
                                saturate(other.physiology.x) *
                                pow(saturate(dot(otherLocalDirection, boundaryB)), 2.0);
                            float attackA = sameOwner ? 0.0 :
                                attackConstructionA * (0.20 + pairDifference * 0.80);
                            float attackB = sameOwner ? 0.0 :
                                attackConstructionB * (0.20 + pairDifference * 0.80);
                            float defenseA = saturate(
                                supportA.integrity * (0.50 + cell.phenotype.x * 0.24 +
                                    armorConstructionA * 0.62)
                            );
                            float defenseB = saturate(
                                supportB.integrity * (0.50 + other.phenotype.x * 0.24 +
                                    armorConstructionB * 0.62)
                            );
                            float damageToA = contactStrength * attackB * (1.12 - defenseA) * 0.010;
                            float damageToB = contactStrength * attackA * (1.12 - defenseB) * 0.010;
                            // Digestion follows failure at the contacted membrane support.
                            // Whole-cell integrity limits stores but is not a prerequisite
                            // for beginning a local breach.
                            float localFailureA = 1.0 - smoothstep(
                                0.42, 0.90, supportA.integrity
                            );
                            float localFailureB = 1.0 - smoothstep(
                                0.42, 0.90, supportB.integrity
                            );
                            float freshDamageA = smoothstep(0.0000001, 0.000004, damageToA);
                            float freshDamageB = smoothstep(0.0000001, 0.000004, damageToB);
                            float breachA = saturate(
                                localFailureA * 0.78 + freshDamageA * 0.42
                            ) * cell.tissueGeometry.z;
                            float breachB = saturate(
                                localFailureB * 0.78 + freshDamageB * 0.42
                            ) * other.tissueGeometry.z;
                            float availableFromA = min(
                                cell.physiology.x * 0.012 / 0.82,
                                max(cell.physiology.y - 0.16, 0.0) * 0.004 / 0.30
                            );
                            float availableFromB = min(
                                other.physiology.x * 0.012 / 0.82,
                                max(other.physiology.y - 0.16, 0.0) * 0.004 / 0.30
                            );
                            float transferFromA = min(
                                contactStrength * attackB * breachA * 0.012,
                                availableFromA
                            );
                            float transferFromB = min(
                                contactStrength * attackA * breachB * 0.012,
                                availableFromB
                            );
                            if (!sameOwner && attackA + attackB > 0.000001) {
                                bool breached = (attackB > 0.0 && breachA > 0.05) ||
                                    (attackA > 0.0 && breachB > 0.05);
                                atomic_fetch_add_explicit(
                                    &identityCounters[breached ? 6 : 7],
                                    1u, memory_order_relaxed
                                );
                                float transferred = transferFromA + transferFromB;
                                if (transferred > 0.0000001) {
                                    atomic_fetch_add_explicit(
                                        &identityCounters[8], 1u, memory_order_relaxed
                                    );
                                    atomic_fetch_add_explicit(
                                        &identityCounters[9],
                                        uint(min(transferred * 1048576.0, 4294967295.0)),
                                        memory_order_relaxed
                                    );
                                }
                                float deflected = contactStrength *
                                    (attackB * defenseA + attackA * defenseB);
                                atomic_fetch_add_explicit(
                                    &identityCounters[10],
                                    uint(min(deflected * 1048576.0, 4294967295.0)),
                                    memory_order_relaxed
                                );
                            }
                            float trophicA = transferFromB * 0.68 - transferFromA;
                            float trophicB = transferFromA * 0.68 - transferFromB;
                            float trophicLossHeat = max(
                                -(trophicA + trophicB) * (0.82 + 0.30 * 0.18), 0.0
                            );
                            addEnergyAudit(energyAudit, 6u, trophicLossHeat);
                            addEnergyAudit(energyAudit, 9u, -trophicLossHeat);
                            float impulseMagnitude = localOverlap *
                                (0.006 + min(defenseA, defenseB) * 0.010);

                            if (sameOwner) {
                                float2 polarityA = length(cell.development.xy) > 0.0001
                                    ? normalize(cell.development.xy) : localDirection;
                                float2 polarityB = length(other.development.xy) > 0.0001
                                    ? normalize(other.development.xy) : otherLocalDirection;
                                float polarityAlignment = clamp(
                                    0.5 * (dot(polarityA, localDirection) +
                                        dot(polarityB, otherLocalDirection)),
                                    -1.0, 1.0
                                );
                                float localRelease = saturate(max(
                                    cell.tissueGeometry.w + cell.signals.w * 0.42,
                                    other.tissueGeometry.w + other.signals.w * 0.42
                                ));
                                float metabolicInvestment = sqrt(max(
                                    cell.physiology.x * other.physiology.x, 0.0
                                ));
                                float pairAdhesion = min(cell.phenotype.x, other.phenotype.x) *
                                    sqrt(max(cell.physiology.w * other.physiology.w, 0.0)) *
                                    inheritedJunctionMaterial.x *
                                    (1.0 - localRelease * 0.88);
                                float pairDamping = inheritedJunctionMaterial.z *
                                    (0.28 + topologyIntegrity * 0.72);
                                float pairPermeability = inheritedJunctionMaterial.w *
                                    (0.22 + min(cell.regulationB.x, other.regulationB.x) * 0.78) *
                                    topologyIntegrity;
                                float pairCorticalTension = inheritedJunctionMaterial.y *
                                    (0.24 + 0.38 * (cell.regulation.z + other.regulation.z)) *
                                    (1.0 - localRelease * 0.58);
                                float4 targetMaterial = clamp(float4(
                                    pairAdhesion * (0.42 + metabolicInvestment * 0.76),
                                    pairDamping,
                                    pairPermeability,
                                    pairCorticalTension
                                ), float4(0.015), float4(1.80));
                                uint pairKey = cellPairKey(gid, otherIndex);
                                uint fingerprint = cellPairFingerprint(
                                    cellIdentities, gid, otherIndex
                                );
                                uint junction = findCellJunction(
                                    junctionStates, pairKey, fingerprint
                                );
                                if (junction == cellJunctionCapacity && localGap < 0.038 &&
                                    pairAdhesion > 0.16) {
                                    junction = findOrCreateCellJunction(
                                        junctionStates, pairKey, fingerprint, uniforms.step,
                                        distance / max(scale, 0.0000001), pairAdhesion
                                    );
                                } else if (junction < cellJunctionCapacity) {
                                    atomic_store_explicit(
                                        &junctionStates[junction].lastSeenStep,
                                        uniforms.step, memory_order_relaxed
                                    );
                                    junctionStates[junction].age = min(
                                        junctionStates[junction].age + 1.0, 65535.0
                                    );
                                    junctionStates[junction].strength = mix(
                                        junctionStates[junction].strength,
                                        pairAdhesion, 0.08
                                    );
                                }
                                if (junction < cellJunctionCapacity) {
                                    float localCenterDistance = distance / max(scale, 0.0000001);
                                    float investmentRate = 0.018 + metabolicInvestment * 0.065;
                                    float4 updatedMaterial = mix(
                                        junctionStates[junction].material,
                                        targetMaterial, investmentRate
                                    );
                                    float remodelingTarget = localCenterDistance * (
                                        1.0 - updatedMaterial.w *
                                            (0.006 + max(polarityAlignment, 0.0) * 0.010)
                                    );
                                    float4 updatedRemodeling = junctionStates[junction].remodeling;
                                    updatedRemodeling.x = mix(
                                        max(updatedRemodeling.x, 0.001),
                                        remodelingTarget,
                                        0.004 + metabolicInvestment * 0.018
                                    );
                                    float materialStrain = localCenterDistance -
                                        updatedRemodeling.x;
                                    updatedRemodeling.y = mix(
                                        updatedRemodeling.y, materialStrain, 0.045
                                    );
                                    updatedRemodeling.z = mix(
                                        updatedRemodeling.z,
                                        saturate(metabolicInvestment * pairAdhesion),
                                        0.025
                                    );
                                    updatedRemodeling.w = mix(
                                        updatedRemodeling.w, polarityAlignment, 0.040
                                    );
                                    float updatedStrength = mix(
                                        junctionStates[junction].strength, pairAdhesion,
                                        0.025 + metabolicInvestment * 0.055
                                    );
                                    float stretch = localCenterDistance -
                                        updatedRemodeling.x;
                                    float2 velocityA = rotateTissueToWorld(cell.velocity, agent);
                                    float2 velocityB = rotateTissueToWorld(other.velocity, otherAgent);
                                    float relativeNormalVelocity = dot(
                                        velocityB - velocityA, normalWorld
                                    );
                                    float junctionMagnitude = -stretch *
                                        updatedStrength * updatedMaterial.x * 0.0080 -
                                        relativeNormalVelocity *
                                            (0.018 + updatedMaterial.y * 0.070) -
                                        updatedMaterial.w *
                                            max(updatedRemodeling.w, 0.0) * 0.000035;
                                    junctionMagnitude = clamp(junctionMagnitude, -0.0028, 0.0028);
                                    impulseMagnitude += junctionMagnitude;
                                    junctionStates[junction].material = updatedMaterial;
                                    junctionStates[junction].remodeling = updatedRemodeling;
                                    junctionStates[junction].restDistance = updatedRemodeling.x;
                                    junctionStates[junction].strength = updatedStrength;
                                    junctionStates[junction].load = abs(junctionMagnitude);
                                } else if (localGap > 0.0) {
                                    impulseMagnitude -= pairAdhesion *
                                        (1.0 - saturate(localGap / interactionRange)) * 0.00022;
                                }
                            }
                            float2 impulse = normalWorld * impulseMagnitude;
                            int impulseX = int(clamp(
                                impulse.x * float(cellContactForceScale), -1048576.0, 1048576.0
                            ));
                            int impulseY = int(clamp(
                                impulse.y * float(cellContactForceScale), -1048576.0, 1048576.0
                            ));
                            atomic_fetch_add_explicit(
                                &contactEffects[gid * 4u], -impulseX, memory_order_relaxed
                            );
                            atomic_fetch_add_explicit(
                                &contactEffects[gid * 4u + 1u], -impulseY, memory_order_relaxed
                            );
                            atomic_fetch_add_explicit(
                                &contactEffects[gid * 4u + 2u],
                                int(damageToA * float(cellContactScalarScale)), memory_order_relaxed
                            );
                            atomic_fetch_add_explicit(
                                &contactEffects[gid * 4u + 3u],
                                int(trophicA * float(cellContactScalarScale)), memory_order_relaxed
                            );
                            atomic_fetch_add_explicit(
                                &contactEffects[otherIndex * 4u], impulseX, memory_order_relaxed
                            );
                            atomic_fetch_add_explicit(
                                &contactEffects[otherIndex * 4u + 1u], impulseY, memory_order_relaxed
                            );
                            atomic_fetch_add_explicit(
                                &contactEffects[otherIndex * 4u + 2u],
                                int(damageToB * float(cellContactScalarScale)), memory_order_relaxed
                            );
                            atomic_fetch_add_explicit(
                                &contactEffects[otherIndex * 4u + 3u],
                                int(trophicB * float(cellContactScalarScale)), memory_order_relaxed
                            );
                            float pressure = localOverlap *
                                (0.10 + min(defenseA, defenseB) * 0.18) +
                                abs(impulseMagnitude) * 2.0;
                            accumulateMembraneContactForce(
                                membraneContactEffects, gid, supportA.vertexIndex,
                                -impulse, pressure
                            );
                            accumulateMembraneContactForce(
                                membraneContactEffects, otherIndex, supportB.vertexIndex,
                                impulse, pressure
                            );
                        }
}

kernel void detectCellTopologyChanges(
    device atomic_uint* topologySignatures [[buffer(0)]],
    device atomic_uint* contactWorkState [[buffer(1)]],
    device const atomic_uint* activeCellCount [[buffer(29)]],
    device const uint* activeCellIndices [[buffer(30)]],
    uint compactIndex [[thread_position_in_grid]]
) {
    if (compactIndex >= atomic_load_explicit(activeCellCount, memory_order_relaxed)) { return; }
    uint cellIndex = activeCellIndices[compactIndex];
    if (cellIndex >= maxCellCount) { return; }
    uint base = cellIndex * 4u;
    uint currentCount = atomic_load_explicit(
        &topologySignatures[base], memory_order_relaxed
    );
    uint currentHash = atomic_load_explicit(
        &topologySignatures[base + 1u], memory_order_relaxed
    );
    uint previousCount = atomic_load_explicit(
        &topologySignatures[base + 2u], memory_order_relaxed
    );
    uint previousHash = atomic_load_explicit(
        &topologySignatures[base + 3u], memory_order_relaxed
    );
    if (currentCount != previousCount || currentHash != previousHash) {
        atomic_store_explicit(&contactWorkState[2], 1u, memory_order_relaxed);
    }
    atomic_store_explicit(
        &topologySignatures[base + 2u], currentCount, memory_order_relaxed
    );
    atomic_store_explicit(
        &topologySignatures[base + 3u], currentHash, memory_order_relaxed
    );
}

kernel void applyCellContactEffects(
    device const AgentState* agents [[buffer(0)]],
    device CellState* cells [[buffer(1)]],
    device const atomic_uint* cellOccupancy [[buffer(2)]],
    device MembraneVertex* membraneVertices [[buffer(3)]],
    device atomic_int* contactEffects [[buffer(4)]],
    device const CellIdentity* cellIdentities [[buffer(5)]],
    device atomic_int* membraneContactEffects [[buffer(6)]],
    device atomic_int* energyAudit [[buffer(7)]],
    device const atomic_uint* activeCellCount [[buffer(29)]],
    device const uint* activeCellIndices [[buffer(30)]],
    uint compactIndex [[thread_position_in_grid]]
) {
    if (compactIndex >= atomic_load_explicit(activeCellCount, memory_order_relaxed)) { return; }
    uint gid = activeCellIndices[compactIndex];
    if (gid >= maxCellCount) { return; }
    int rawX = atomic_exchange_explicit(&contactEffects[gid * 4u], 0, memory_order_relaxed);
    int rawY = atomic_exchange_explicit(&contactEffects[gid * 4u + 1u], 0, memory_order_relaxed);
    int rawDamage = atomic_exchange_explicit(&contactEffects[gid * 4u + 2u], 0, memory_order_relaxed);
    int rawTrophic = atomic_exchange_explicit(&contactEffects[gid * 4u + 3u], 0, memory_order_relaxed);
    if (atomic_load_explicit(&cellOccupancy[gid], memory_order_relaxed) == 0u) { return; }

    uint owner = cellIdentities[gid].owner;
    if (owner >= maxAgentCount) { return; }
    CellState cell = cells[gid];
    float2 worldImpulse = float2(rawX, rawY) / float(cellContactForceScale);
    float2 localImpulse = rotateWorldToTissue(worldImpulse, agents[owner]);
    float damage = max(float(rawDamage) / float(cellContactScalarScale), 0.0);
    float trophic = float(rawTrophic) / float(cellContactScalarScale);
    float previousATP = cell.physiology.x;
    float previousBiomass = cell.physiology.y;
    cell.velocity += localImpulse;
    float speed = length(cell.velocity);
    if (speed > 0.0032) { cell.velocity *= 0.0032 / speed; }
    cell.physiology.x = clamp(cell.physiology.x + trophic * 0.82, 0.0, 1.2);
    cell.physiology.y = clamp(cell.physiology.y + trophic * 0.30, 0.16, 1.12);
    cell.physiology.w = clamp(cell.physiology.w - damage, 0.0, 1.0);
    cell.signals.z = saturate(cell.signals.z + damage * 7.5 + max(-trophic, 0.0) * 4.0);
    float woundSignal = saturate(damage * 12.0);
    cell.signaling.x = saturate(cell.signaling.x + woundSignal * 0.48);
    cell.signaling.y = saturate(cell.signaling.y + woundSignal * 0.14);
    cell.dynamics.x = clamp(cell.dynamics.x + woundSignal * 0.16, -1.8, 1.8);
    cell.tissueForce.xy += localImpulse;
    cell.tissueForce.z = length(localImpulse) + damage;
    cell.tissueForce.w = trophic;

    float trophicStorageDelta = cell.physiology.x - previousATP +
        (cell.physiology.y - previousBiomass) * 0.18;
    addEnergyAudit(energyAudit, 2u, trophicStorageDelta);
    addEnergyAudit(energyAudit, 9u, -trophicStorageDelta);

    uint membraneBase = gid * membraneVertexCount;
    for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
        uint effectBase = (gid * membraneVertexCount + vertexIndex) * 3u;
        int vertexRawX = atomic_exchange_explicit(
            &membraneContactEffects[effectBase], 0, memory_order_relaxed
        );
        int vertexRawY = atomic_exchange_explicit(
            &membraneContactEffects[effectBase + 1u], 0, memory_order_relaxed
        );
        int vertexRawPressure = atomic_exchange_explicit(
            &membraneContactEffects[effectBase + 2u], 0, memory_order_relaxed
        );
        MembraneVertex membranePoint = membraneVertices[membraneBase + vertexIndex];
        float2 vertexWorldForce = float2(vertexRawX, vertexRawY) /
            float(cellContactForceScale);
        float2 vertexLocalForce = rotateWorldToTissue(vertexWorldForce, agents[owner]);
        membranePoint.velocity += vertexLocalForce * 0.72;
        float vertexSpeed = length(membranePoint.velocity);
        if (vertexSpeed > 0.0075) {
            membranePoint.velocity *= 0.0075 / vertexSpeed;
        }
        membranePoint.mechanics.z = mix(
            membranePoint.mechanics.z,
            max(float(vertexRawPressure) / float(cellContactScalarScale), 0.0),
            0.72
        );
        membraneVertices[membraneBase + vertexIndex] = membranePoint;
    }

    if (damage > 0.0 && length(localImpulse) > 0.000001) {
        float2 impactDirection = -normalize(localImpulse);
        for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
            MembraneVertex membranePoint = membraneVertices[membraneBase + vertexIndex];
            float2 radial = length(membranePoint.position) > 0.0001
                ? normalize(membranePoint.position) : impactDirection;
            float localization = smoothstep(0.05, 0.82, dot(radial, impactDirection));
            membranePoint.mechanics.y = clamp(
                membranePoint.mechanics.y - damage * (0.35 + localization * 1.65), 0.0, 1.0
            );
            membranePoint.mechanics.z += damage * localization;
            membraneVertices[membraneBase + vertexIndex] = membranePoint;
        }
    }
    cells[gid] = cell;
}

inline void recordInvariantFailure(
    device atomic_uint* invariantState,
    uint flag,
    uint counter,
    uint step
) {
    atomic_fetch_or_explicit(&invariantState[0], flag, memory_order_relaxed);
    atomic_fetch_min_explicit(&invariantState[1], step, memory_order_relaxed);
    atomic_fetch_add_explicit(&invariantState[counter], 1u, memory_order_relaxed);
}

kernel void initializeInvariantAudit(
    device atomic_uint* invariantState [[buffer(0)]],
    device atomic_int* scratch [[buffer(1)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid < invariantScratchCount) {
        atomic_store_explicit(&scratch[gid], 0, memory_order_relaxed);
    }
    if (gid < invariantStateCount) {
        atomic_store_explicit(&invariantState[gid], 0u, memory_order_relaxed);
    }
    if (gid == 0u) {
        atomic_store_explicit(&invariantState[1], 0xffffffffu, memory_order_relaxed);
    }
}

kernel void clearInvariantScratch(
    device atomic_int* scratch [[buffer(0)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid < invariantScratchCount) {
        atomic_store_explicit(&scratch[gid], 0, memory_order_relaxed);
    }
}

kernel void auditContactMomentum(
    device const atomic_int* contactEffects [[buffer(0)]],
    device atomic_int* scratch [[buffer(1)]],
    device const atomic_uint* activeCellCount [[buffer(29)]],
    device const uint* activeCellIndices [[buffer(30)]],
    uint compactIndex [[thread_position_in_grid]]
) {
    if (compactIndex >= atomic_load_explicit(activeCellCount, memory_order_relaxed)) { return; }
    uint gid = activeCellIndices[compactIndex];
    if (gid >= maxCellCount) { return; }
    atomic_fetch_add_explicit(
        &scratch[0], atomic_load_explicit(&contactEffects[gid * 4u], memory_order_relaxed),
        memory_order_relaxed
    );
    atomic_fetch_add_explicit(
        &scratch[1], atomic_load_explicit(&contactEffects[gid * 4u + 1u], memory_order_relaxed),
        memory_order_relaxed
    );
}

kernel void accumulateSimulationInvariants(
    device const atomic_uint* agentOccupancy [[buffer(0)]],
    device const CellState* cells [[buffer(1)]],
    device const atomic_uint* cellOccupancy [[buffer(2)]],
    device const CellIdentity* cellIdentities [[buffer(3)]],
    device const ProgramSlotState* programSlots [[buffer(4)]],
    device const MembraneVertex* membraneVertices [[buffer(5)]],
    device CellJunctionState* junctionStates [[buffer(6)]],
    device atomic_int* scratch [[buffer(7)]],
    device atomic_uint* invariantState [[buffer(8)]],
    constant SimulationUniforms& uniforms [[buffer(9)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid < maxCellCount &&
        atomic_load_explicit(&cellOccupancy[gid], memory_order_relaxed) != 0u) {
        atomic_fetch_add_explicit(&scratch[4], 1, memory_order_relaxed);
        CellIdentity identity = cellIdentities[gid];
        bool validOwner = identity.owner < maxAgentCount &&
            atomic_load_explicit(
                &agentOccupancy[identity.owner], memory_order_relaxed
            ) == 1u;
        bool validRoot = identity.componentRoot < maxCellCount &&
            atomic_load_explicit(
                &cellOccupancy[identity.componentRoot], memory_order_relaxed
            ) != 0u && cellIdentities[identity.componentRoot].owner == identity.owner;
        if (!validOwner || !validRoot) {
            recordInvariantFailure(
                invariantState, invariantDisconnectedOwnership, 9u, uniforms.step
            );
        } else {
            int encodedRoot = int(identity.componentRoot + 1u);
            int observedRoot = atomic_load_explicit(
                &scratch[invariantOwnerRootOffset + identity.owner], memory_order_relaxed
            );
            for (uint attempt = 0u; attempt < 8u && observedRoot == 0; ++attempt) {
                int expectedRoot = 0;
                if (atomic_compare_exchange_weak_explicit(
                    &scratch[invariantOwnerRootOffset + identity.owner],
                    &expectedRoot,
                    encodedRoot,
                    memory_order_relaxed,
                    memory_order_relaxed
                )) {
                    observedRoot = encodedRoot;
                    break;
                }
                observedRoot = expectedRoot;
            }
            if (observedRoot != encodedRoot) {
                recordInvariantFailure(
                    invariantState, invariantDisconnectedOwnership, 9u, uniforms.step
                );
            }
        }
        bool validProgram = programSlotMatches(
            programSlots, identity.programIndex, identity.programGeneration
        );
        if (!validProgram) {
            recordInvariantFailure(
                invariantState, invariantStaleProgram, 5u, uniforms.step
            );
        } else {
            atomic_fetch_add_explicit(
                &scratch[invariantScratchHeaderCount + identity.programIndex],
                1, memory_order_relaxed
            );
        }

        CellState cell = cells[gid];
        bool validState = all(isfinite(cell.position)) && all(isfinite(cell.velocity)) &&
            all(isfinite(cell.physiology)) && all(isfinite(cell.membrane)) &&
            all(isfinite(cell.development)) &&
            cell.physiology.w >= 0.0 && cell.physiology.w <= 1.0001;
        float signedDoubleArea = 0.0;
        float perimeter = 0.0;
        uint membraneBase = gid * membraneVertexCount;
        for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
            uint next = (vertexIndex + 1u) % membraneVertexCount;
            MembraneVertex membranePoint = membraneVertices[membraneBase + vertexIndex];
            MembraneVertex nextVertex = membraneVertices[membraneBase + next];
            validState = validState && all(isfinite(membranePoint.position)) &&
                all(isfinite(membranePoint.velocity)) && all(isfinite(membranePoint.mechanics)) &&
                membranePoint.mechanics.x > 0.0 && membranePoint.mechanics.y >= 0.0 &&
                membranePoint.mechanics.y <= 1.0001;
            signedDoubleArea += membranePoint.position.x * nextVertex.position.y -
                nextVertex.position.x * membranePoint.position.y;
            perimeter += length(nextVertex.position - membranePoint.position);
        }
        validState = validState && isfinite(signedDoubleArea) && isfinite(perimeter) &&
            signedDoubleArea > 0.00001 && perimeter > 0.08 && perimeter < 4.0;
        if (!validState) {
            recordInvariantFailure(
                invariantState, invariantInvalidMembrane, 8u, uniforms.step
            );
        }
    }

    if (gid < maxHeritableProgramCount) {
        uint occupied = atomic_load_explicit(
            &programSlots[gid].occupied, memory_order_relaxed
        );
        uint references = atomic_load_explicit(
            &programSlots[gid].referenceCount, memory_order_relaxed
        );
        if (occupied == 1u) {
            atomic_fetch_add_explicit(&scratch[5], 1, memory_order_relaxed);
        }
        atomic_fetch_add_explicit(&scratch[6], int(references), memory_order_relaxed);
    }

    if (gid < cellJunctionCapacity) {
        uint pairKey = atomic_load_explicit(
            &junctionStates[gid].pairKey, memory_order_relaxed
        );
        if (pairKey != emptySpatialHashEntry) {
            uint packedPair = pairKey - 1u;
            uint cellA = packedPair / maxCellCount;
            uint cellB = packedPair % maxCellCount;
            uint lastSeen = atomic_load_explicit(
                &junctionStates[gid].lastSeenStep, memory_order_relaxed
            );
            bool stale = uniforms.step > lastSeen && uniforms.step - lastSeen > 180u;
            if (stale) {
                atomic_store_explicit(
                    &junctionStates[gid].pairKey,
                    emptySpatialHashEntry,
                    memory_order_relaxed
                );
                return;
            }
            bool validPair = pairKey > 0u && cellA < maxCellCount && cellB < maxCellCount &&
                cellA < cellB &&
                atomic_load_explicit(&cellOccupancy[cellA], memory_order_relaxed) != 0u &&
                atomic_load_explicit(&cellOccupancy[cellB], memory_order_relaxed) != 0u &&
                cellIdentities[cellA].owner == cellIdentities[cellB].owner &&
                junctionStates[gid].persistentFingerprint ==
                    cellPairFingerprint(cellIdentities, cellA, cellB);
            bool validMaterial = all(isfinite(junctionStates[gid].material)) &&
                all(isfinite(junctionStates[gid].remodeling)) &&
                junctionStates[gid].restDistance > 0.0 &&
                all(junctionStates[gid].material >= float4(0.0)) &&
                all(junctionStates[gid].material <= float4(2.01)) &&
                abs(junctionStates[gid].remodeling.y) < 2.0 &&
                junctionStates[gid].remodeling.z >= 0.0 &&
                junctionStates[gid].remodeling.z <= 1.01 &&
                abs(junctionStates[gid].remodeling.w) <= 1.01;
            if (!validPair || !validMaterial) {
                recordInvariantFailure(
                    invariantState, invariantOrphanedJunction, 7u, uniforms.step
                );
            } else {
                atomic_fetch_add_explicit(&scratch[2], 1, memory_order_relaxed);
                atomic_fetch_add_explicit(
                    &scratch[3],
                    int(clamp(junctionStates[gid].load * 1048576.0, 0.0, 1048576.0)),
                    memory_order_relaxed
                );
            }
        }
    }
}

kernel void finalizeSimulationInvariants(
    device const ProgramSlotState* programSlots [[buffer(0)]],
    device const atomic_int* scratch [[buffer(1)]],
    device atomic_uint* invariantState [[buffer(2)]],
    device const atomic_int* energyAudit [[buffer(3)]],
    constant SimulationUniforms& uniforms [[buffer(4)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid < maxHeritableProgramCount) {
        uint occupied = atomic_load_explicit(
            &programSlots[gid].occupied, memory_order_relaxed
        );
        uint recordedReferences = atomic_load_explicit(
            &programSlots[gid].referenceCount, memory_order_relaxed
        );
        uint observedReferences = uint(max(atomic_load_explicit(
            &scratch[invariantScratchHeaderCount + gid], memory_order_relaxed
        ), 0));
        bool valid = occupied == 1u
            ? recordedReferences == observedReferences && recordedReferences > 0u
            : recordedReferences == 0u && observedReferences == 0u && occupied == 0u;
        if (!valid) {
            recordInvariantFailure(
                invariantState, invariantReferenceCount, 6u, uniforms.step
            );
        }
    }
    if (gid != 0u) { return; }

    int netX = atomic_load_explicit(&scratch[0], memory_order_relaxed);
    int netY = atomic_load_explicit(&scratch[1], memory_order_relaxed);
    uint momentumMagnitude = uint(abs(netX)) + uint(abs(netY));
    if (momentumMagnitude != 0u) {
        recordInvariantFailure(
            invariantState, invariantContactMomentum, 3u, uniforms.step
        );
    }
    int energyResidual = atomic_load_explicit(&energyAudit[9], memory_order_relaxed);
    uint absoluteEnergyResidual = uint(abs(energyResidual));
    if (absoluteEnergyResidual > 256u) {
        recordInvariantFailure(
            invariantState, invariantEnergyDrift, 4u, uniforms.step
        );
    }
    atomic_fetch_add_explicit(&invariantState[2], 1u, memory_order_relaxed);
    atomic_fetch_max_explicit(&invariantState[10], momentumMagnitude, memory_order_relaxed);
    atomic_store_explicit(
        &invariantState[11], uint(max(atomic_load_explicit(&scratch[2], memory_order_relaxed), 0)),
        memory_order_relaxed
    );
    atomic_store_explicit(
        &invariantState[12], uint(max(atomic_load_explicit(&scratch[3], memory_order_relaxed), 0)),
        memory_order_relaxed
    );
    atomic_store_explicit(
        &invariantState[13], uint(max(atomic_load_explicit(&scratch[4], memory_order_relaxed), 0)),
        memory_order_relaxed
    );
    atomic_store_explicit(
        &invariantState[14], uint(max(atomic_load_explicit(&scratch[5], memory_order_relaxed), 0)),
        memory_order_relaxed
    );
    atomic_store_explicit(
        &invariantState[15], uint(max(atomic_load_explicit(&scratch[6], memory_order_relaxed), 0)),
        memory_order_relaxed
    );
    atomic_fetch_max_explicit(
        &invariantState[16], absoluteEnergyResidual, memory_order_relaxed
    );
}

kernel void measureCellMembraneExposure(
    device const AgentState* agents [[buffer(0)]],
    device CellState* cells [[buffer(1)]],
    device const atomic_uint* cellOccupancy [[buffer(2)]],
    device MembraneVertex* membraneVertices [[buffer(3)]],
    device const atomic_uint* hashHeads [[buffer(4)]],
    device const uint* hashNext [[buffer(5)]],
    constant SimulationUniforms& uniforms [[buffer(6)]],
    device const CellIdentity* cellIdentities [[buffer(7)]],
    device const atomic_uint* agentOccupancy [[buffer(8)]],
    device const DevelopmentalGenome* developmentalGenomes [[buffer(9)]],
    device const ProgramSlotState* programSlots [[buffer(10)]],
    device const atomic_uint* activeCellCount [[buffer(29)]],
    device const uint* activeCellIndices [[buffer(30)]],
    uint compactIndex [[thread_position_in_grid]]
) {
    if (compactIndex >= atomic_load_explicit(activeCellCount, memory_order_relaxed)) { return; }
    uint gid = activeCellIndices[compactIndex];
    if (gid >= maxCellCount ||
        atomic_load_explicit(&cellOccupancy[gid], memory_order_relaxed) == 0u) { return; }
    uint owner = cellIdentities[gid].owner;
    if (owner >= maxAgentCount ||
        atomic_load_explicit(&agentOccupancy[owner], memory_order_relaxed) == 0u) { return; }

    AgentState agent = agents[owner];
    CellState cell = cells[gid];
    uint membraneBase = gid * membraneVertexCount;
    float perimeter = 0.0;
    float exposedPerimeter = 0.0;
    float2 exposedNormal = float2(0.0);
    float junctionLoad = 0.0;
    uint nearbySameOwnerCells[64];
    uint nearbyCellCount = 0u;
    int2 centerCoordinate = int2(spatialHashCoordinate(
        cellWorldPosition(agent, cell.position, uniforms)
    ));
    for (int offsetY = -2; offsetY <= 2 && nearbyCellCount < 64u; ++offsetY) {
        for (int offsetX = -2; offsetX <= 2 && nearbyCellCount < 64u; ++offsetX) {
            int2 candidateCoordinate = centerCoordinate + int2(offsetX, offsetY);
            if (any(candidateCoordinate < int2(0)) ||
                any(candidateCoordinate >= int2(cellSpatialHashAxisResolution))) { continue; }
            uint bucket = cellSpatialHash(uint2(candidateCoordinate));
            uint otherIndex = atomic_load_explicit(
                &hashHeads[bucket], memory_order_relaxed
            );
            uint traversed = 0u;
            while (otherIndex != emptySpatialHashEntry && traversed < 48u &&
                nearbyCellCount < 64u) {
                uint following = hashNext[otherIndex];
                if (otherIndex != gid &&
                    atomic_load_explicit(
                        &cellOccupancy[otherIndex], memory_order_relaxed
                    ) != 0u && cellIdentities[otherIndex].owner == owner) {
                    nearbySameOwnerCells[nearbyCellCount++] = otherIndex;
                }
                otherIndex = following;
                traversed += 1u;
            }
        }
    }
    for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
        uint next = (vertexIndex + 1u) % membraneVertexCount;
        MembraneVertex membraneA = membraneVertices[membraneBase + vertexIndex];
        MembraneVertex membraneB = membraneVertices[membraneBase + next];
        float2 edge = membraneB.position - membraneA.position;
        float edgeLength = length(edge);
        perimeter += edgeLength;
        junctionLoad += (membraneA.mechanics.z + membraneB.mechanics.z) *
            edgeLength * 0.5;
        float2 localMidpoint = (membraneA.position + membraneB.position) * 0.5;
        bool occluded = false;
        for (uint nearbyIndex = 0u;
            nearbyIndex < nearbyCellCount && !occluded; ++nearbyIndex) {
            uint otherIndex = nearbySameOwnerCells[nearbyIndex];
            CellState other = cells[otherIndex];
            // Same-owner cells already share this tissue coordinate frame.
            // The former world transform, subtraction, inverse rotation, and
            // scale division reduce algebraically to this local difference.
            float2 pointInOther = cell.position + localMidpoint - other.position;
            if (pointInsideMembrane(
                membraneVertices, otherIndex, pointInOther
            )) {
                occluded = true;
            }
        }
        if (!occluded && edgeLength > 0.000001) {
            exposedPerimeter += edgeLength;
            float2 outward = normalize(float2(edge.y, -edge.x));
            if (dot(outward, localMidpoint) < 0.0) { outward *= -1.0; }
            exposedNormal += outward * edgeLength;
        }
        MembraneVertex markedEdge = membraneVertices[membraneBase + vertexIndex];
        markedEdge.mechanics.w = (occluded ? -1.0 : 1.0) *
            (abs(markedEdge.mechanics.w) + 0.000001);
        membraneVertices[membraneBase + vertexIndex] = markedEdge;
    }
    float exposure = saturate(exposedPerimeter / max(perimeter, 0.0001));
    float2 boundaryNormal = length(exposedNormal) > 0.0001
        ? normalize(exposedNormal)
        : (length(cell.development.xy) > 0.0001
            ? normalize(cell.development.xy)
            : float2(cos(cell.dynamics.z * 2.0 * M_PI_F),
                sin(cell.dynamics.z * 2.0 * M_PI_F)));
    uint programIndex = cellIdentities[gid].programIndex;
    float propaguleInvestment = programSlotMatches(
        programSlots, programIndex, cellIdentities[gid].programGeneration
    ) ? developmentalGenomes[programIndex].mechanochemistryB.w : 0.0;
    float detachmentScore = detachmentReadinessScore(
        exposure,
        1.0 - cell.interaction.z,
        cell.physiology.x,
        cell.physiology.w,
        cell.phenotype.x,
        propaguleInvestment
    );
    cell.membrane.w = junctionLoad;
    cell.tissueGeometry = float4(
        boundaryNormal, exposure, saturate(detachmentScore)
    );
    cells[gid] = cell;
}

kernel void divideAndReduceOrganismCells(
    device AgentState* agents [[buffer(0)]],
    device const atomic_uint* agentOccupancy [[buffer(1)]],
    device CellState* cells [[buffer(2)]],
    device atomic_uint* cellOccupancy [[buffer(3)]],
    device CellAggregate* aggregates [[buffer(4)]],
    constant SimulationUniforms& uniforms [[buffer(5)]],
    device float* regulatoryStates [[buffer(6)]],
    device MembraneVertex* membraneVertices [[buffer(7)]],
    device ResonanceGenome* resonanceGenomes [[buffer(8)]],
    device CellIdentity* cellIdentities [[buffer(9)]],
    device atomic_uint* ownerCellHeads [[buffer(10)]],
    device uint* ownerCellNext [[buffer(11)]],
    device atomic_uint* identityCounters [[buffer(12)]],
    device uint* cellParentIDs [[buffer(13)]],
    device float4* programInteractions [[buffer(14)]],
    device ProgramSlotState* programSlots [[buffer(15)]],
    device DevelopmentalGenome* developmentalGenomes [[buffer(16)]],
    device RegulatoryNode* regulatoryNodes [[buffer(17)]],
    device RegulatoryEdge* regulatoryEdges [[buffer(18)]],
    device HeritableProgram* heritablePrograms [[buffer(19)]],
    device LineageEventRecord* lineageEvents [[buffer(20)]],
    device const uint* activeComponents [[buffer(21)]],
    device const atomic_uint* activeComponentCount [[buffer(22)]],
    device CellJunctionState* cellJunctions [[buffer(23)]],
    device atomic_uint* contactWorkState [[buffer(24)]],
    uint compactIndex [[thread_position_in_grid]]
) {
    if (compactIndex >= atomic_load_explicit(activeComponentCount, memory_order_relaxed)) { return; }
    uint owner = activeComponents[compactIndex];
    if (owner >= maxAgentCount ||
        atomic_load_explicit(&agentOccupancy[owner], memory_order_relaxed) == 0u) { return; }

    AgentState agent = agents[owner];
    uint index = atomic_load_explicit(&ownerCellHeads[owner], memory_order_relaxed);
    while (index != emptySpatialHashEntry) {
        uint nextIndex = ownerCellNext[index];
        if (atomic_load_explicit(&cellOccupancy[index], memory_order_relaxed) != 0u &&
            cellIdentities[index].owner == owner) {
            CellState candidate = cells[index];
            float cycle = candidate.physiology.z;
            uint candidateProgram = cellIdentities[index].programIndex;
            float propaguleInvestment = candidateProgram < maxHeritableProgramCount
                ? developmentalGenomes[candidateProgram].mechanochemistryB.w : 0.0;
            float developmentalIntegritySupport = saturate(propaguleInvestment);
            float divisionIntegrityThreshold = mix(
                0.52, 0.32, developmentalIntegritySupport
            );
            bool divisionCompetent = candidate.physiology.x >= 0.18 &&
                candidate.physiology.y >= 0.42 &&
                candidate.physiology.w >= divisionIntegrityThreshold &&
                candidate.signals.z <= 0.68;
            // Execution is serialized per component to keep its linked list stable,
            // but every pre-existing cell passes its own local checkpoint. There is
            // no component-wide winner and multiple cells may divide in one step.
            if (divisionCompetent && cycle >= 1.0) {
                uint divisionParent = index;
                uint divisionSeed = hash32(
                    owner * 2246822519u ^ divisionParent * 3266489917u ^ uniforms.step
                );
                uint divisionTarget = claimFreeCell(
                    cellOccupancy, divisionSeed ^ 0xa511e9b3u
                );
                if (divisionTarget == maxCellCount) {
                    index = nextIndex;
                    continue;
                }
            CellState parent = cells[divisionParent];
            CellIdentity parentIdentity = cellIdentities[divisionParent];
            uint recombinationDonor = maxCellCount;
            float recombinationScore = 0.0;
            uint donorIndex = atomic_load_explicit(
                &ownerCellHeads[owner], memory_order_relaxed
            );
            while (donorIndex != emptySpatialHashEntry) {
                uint followingDonor = ownerCellNext[donorIndex];
                if (donorIndex != divisionParent &&
                    atomic_load_explicit(
                        &cellOccupancy[donorIndex], memory_order_relaxed
                    ) != 0u && cellIdentities[donorIndex].owner == owner) {
                    CellIdentity donorIdentity = cellIdentities[donorIndex];
                    bool distinctProgram =
                        donorIdentity.programIndex != parentIdentity.programIndex &&
                        programSlotMatches(
                            programSlots,
                            donorIdentity.programIndex,
                            donorIdentity.programGeneration
                        );
                    if (distinctProgram) {
                        uint pairKey = cellPairKey(divisionParent, donorIndex);
                        uint fingerprint = cellPairFingerprint(
                            cellIdentities, divisionParent, donorIndex
                        );
                        uint junctionIndex = findCellJunction(
                            cellJunctions, pairKey, fingerprint
                        );
                        if (junctionIndex < cellJunctionCapacity) {
                            uint lastSeen = atomic_load_explicit(
                                &cellJunctions[junctionIndex].lastSeenStep,
                                memory_order_relaxed
                            );
                            bool recentJunction = uniforms.step >= lastSeen &&
                                uniforms.step - lastSeen <= 2u;
                            CellState donor = cells[donorIndex];
                            AgentState primaryProgram = agentWithCellProgram(
                                agent, parentIdentity.programIndex, heritablePrograms
                            );
                            AgentState donorProgram = agentWithCellProgram(
                                agent, donorIdentity.programIndex, heritablePrograms
                            );
                            float compatibility = recognitionCompatibility(
                                primaryProgram, donorProgram
                            );
                            float programDifference = saturate(
                                length(primaryProgram.geneA - donorProgram.geneA) * 0.22 +
                                length(primaryProgram.geneB - donorProgram.geneB) * 0.18 +
                                length(primaryProgram.geneC - donorProgram.geneC) * 0.18
                            );
                            float donorCompetence = smoothstep(
                                0.10, 0.28, donor.physiology.x
                            ) * smoothstep(0.28, 0.72, donor.physiology.w) *
                                (1.0 - smoothstep(0.48, 0.78, donor.signals.z));
                            float junctionMaturity = smoothstep(
                                2.0, 34.0, cellJunctions[junctionIndex].age
                            ) * saturate(cellJunctions[junctionIndex].strength);
                            float bilateralInvestment = min(
                                primaryProgram.social.w, donorProgram.social.w
                            );
                            float differenceGate = smoothstep(
                                0.015, 0.16, programDifference
                            );
                            bool recombinationEligible = recentJunction &&
                                compatibility > 0.35 &&
                                donorCompetence > 0.08 &&
                                junctionMaturity > 0.001 &&
                                bilateralInvestment > 0.20 &&
                                programDifference > 0.04;
                            float combinedSuitability = compatibility * donorCompetence *
                                junctionMaturity * bilateralInvestment * differenceGate;
                            // Five independent gates produce a product-space value.
                            // Its geometric mean restores a normalized suitability
                            // score before the separate stochastic reproduction step.
                            float score = recombinationEligible
                                ? pow(max(combinedSuitability, 0.000000000001), 0.20)
                                : 0.0;
                            if (score > recombinationScore ||
                                (score > 0.0 && score == recombinationScore &&
                                    donorIndex < recombinationDonor)) {
                                recombinationScore = score;
                                recombinationDonor = donorIndex;
                            }
                        }
                    }
                }
                donorIndex = followingDonor;
            }
            if (recombinationDonor < maxCellCount) {
                atomic_fetch_add_explicit(
                    &identityCounters[13], 1u, memory_order_relaxed
                );
                atomic_fetch_max_explicit(
                    &identityCounters[15],
                    uint(clamp(recombinationScore * 1000000.0, 0.0, 1000000.0)),
                    memory_order_relaxed
                );
            }
            DevelopmentalGenome inheritedDevelopment =
                developmentalGenomes[parentIdentity.programIndex];
            float phaseAngle = parent.dynamics.z * 2.0 * M_PI_F;
            float2 phaseAxis = float2(cos(phaseAngle), sin(phaseAngle));
            float2 polarityAxis = length(parent.development.xy) > 0.0001
                ? normalize(parent.development.xy) : phaseAxis;
            float2 boundaryAxis = length(parent.tissueGeometry.xy) > 0.0001
                ? normalize(parent.tissueGeometry.xy) : polarityAxis;
            float2 axis = normalize(
                polarityAxis * (0.52 + parent.regulation.x * 0.36) +
                phaseAxis * (0.18 + parent.regulation.z * 0.24) +
                boundaryAxis * (0.10 + parent.tissueGeometry.z * 0.22) +
                float2(parent.signals.x - parent.signals.y, parent.mechanics.y - 0.5) * 0.12
            );
            CellState child = parent;
            // Cytokinesis starts with overlapping daughter membranes. The next
            // contact pass can create a physical junction. Placing the centers
            // beyond their post-division membrane supports would immediately
            // produce two independently handled components instead of tissue growth.
            parent.position -= axis * 0.072;
            child.position += axis * 0.072;
            parent.velocity -= axis * 0.00035;
            child.velocity += axis * 0.00035;
            parent.physiology.x *= 0.50;
            child.physiology.x = parent.physiology.x;
            parent.physiology.y *= 0.50;
            child.physiology.y = parent.physiology.y;
            parent.physiology.z = 0.0;
            child.physiology.z = 0.0;
            float partitionAmplitude = clamp(
                0.006 + abs(parent.signals.x - parent.signals.y) * 0.085 +
                    parent.regulation.z * 0.055 + parent.mechanics.y * 0.035 +
                    abs(inheritedDevelopment.morphogenTransport.x -
                        inheritedDevelopment.morphogenTransport.y) * 0.025 +
                    abs(inheritedDevelopment.morphogenTransport.z -
                        inheritedDevelopment.morphogenTransport.w) * 0.020,
                0.006, 0.18
            );
            float2 morphogenPartition = float2(
                conservativeDivisionDelta(
                    parent.signals.x,
                    signedRandom(divisionSeed + 11u) * partitionAmplitude * 0.34
                ),
                conservativeDivisionDelta(
                    parent.signals.y,
                    signedRandom(divisionSeed + 13u) * partitionAmplitude * 0.34
                )
            );
            parent.signals.xy -= morphogenPartition;
            child.signals.xy += morphogenPartition;
            float fateMemoryDelta = conservativeDivisionDelta(
                parent.development.z,
                signedRandom(divisionSeed + 17u) * partitionAmplitude * 0.34
            );
            parent.development.z -= fateMemoryDelta;
            child.development.z += fateMemoryDelta;
            float polarityRotation = signedRandom(divisionSeed + 2u) *
                (0.010 + partitionAmplitude * 0.20);
            float rotationCosine = cos(polarityRotation);
            float rotationSine = sin(polarityRotation);
            float2 inheritedPolarity = polarityAxis;
            parent.development.xy = normalize(float2(
                inheritedPolarity.x * rotationCosine + inheritedPolarity.y * rotationSine,
                -inheritedPolarity.x * rotationSine + inheritedPolarity.y * rotationCosine
            ));
            child.development.xy = normalize(float2(
                inheritedPolarity.x * rotationCosine - inheritedPolarity.y * rotationSine,
                inheritedPolarity.x * rotationSine + inheritedPolarity.y * rotationCosine
            ));
            parent.development.w = 0.0;
            child.development.w = 0.0;
            child.interaction = float4(0.0);
            child.dynamics.z = fract(
                parent.dynamics.z + signedRandom(divisionSeed + 3u) * 0.040 + 1.0
            );
            child.dynamics.w = clamp(
                parent.dynamics.w * (1.0 + signedRandom(divisionSeed + 4u) * 0.045),
                0.0012, 0.0075
            );
            parent.mechanics = float4(0.0, parent.mechanics.yz, parent.mechanics.w);
            child.mechanics = parent.mechanics;
            parent.energetics = float4(0.0);
            child.energetics = float4(0.0);
            child.resonance.xy *= float2(0.72, -0.48);
            child.resonance.z *= 0.72;
            parent.resonance.xy *= float2(0.72, 0.48);
            parent.resonance.z *= 0.72;
            float2 signalingPartition = float2(
                conservativeDivisionDelta(
                    parent.signaling.x,
                    signedRandom(divisionSeed + 19u) * partitionAmplitude * 0.08
                ),
                conservativeDivisionDelta(
                    parent.signaling.y,
                    signedRandom(divisionSeed + 23u) * partitionAmplitude * 0.08
                )
            );
            parent.signaling.xy -= signalingPartition;
            child.signaling.xy += signalingPartition;
            parent.signalCausality = float4(0.0);
            child.signalCausality = float4(0.0);
            child.tissueForce = float4(0.0);
            child.tissueGeometry = float4(axis, 1.0, 0.0);

            uint parentStateBase = divisionParent * regulatoryNodeCapacity;
            uint childStateBase = divisionTarget * regulatoryNodeCapacity;
            for (uint node = 0u; node < regulatoryNodeCapacity; ++node) {
                float state = regulatoryStates[parentStateBase + node];
                float stateDelta = conservativeDivisionDelta(
                    state,
                    signedRandom(divisionSeed + 101u + node) *
                        partitionAmplitude * 0.12
                );
                regulatoryStates[parentStateBase + node] = state - stateDelta;
                regulatoryStates[childStateBase + node] = state + stateDelta;
            }
            uint parentMembraneBase = divisionParent * membraneVertexCount;
            uint childMembraneBase = divisionTarget * membraneVertexCount;
            for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
                MembraneVertex membrane = membraneVertices[parentMembraneBase + vertexIndex];
                membrane.position *= 0.70710678;
                membrane.velocity *= 0.25;
                membrane.mechanics.x *= 0.70710678;
                membraneVertices[parentMembraneBase + vertexIndex] = membrane;
                MembraneVertex daughterMembrane = membrane;
                daughterMembrane.velocity *= -1.0;
                daughterMembrane.mechanics.zw = float2(0.0);
                membraneVertices[childMembraneBase + vertexIndex] = daughterMembrane;
            }
            parent.membrane.xy *= float2(0.50, 0.70710678);
            child.membrane = parent.membrane;
            cells[divisionParent] = parent;
            cells[divisionTarget] = child;
            CellIdentity childIdentity;
            childIdentity.owner = owner;
            childIdentity.programIndex = parentIdentity.programIndex;
            childIdentity.persistentID = atomic_fetch_add_explicit(
                &identityCounters[3], 1u, memory_order_relaxed
            );
            childIdentity.componentRoot = parentIdentity.componentRoot;
            childIdentity.programGeneration = parentIdentity.programGeneration;
            childIdentity.identityPadding0 = 0u;
            childIdentity.identityPadding1 = 0u;
            childIdentity.identityPadding2 = 0u;
            AgentState inheritedAgent = agentWithCellProgram(
                agent, parentIdentity.programIndex, heritablePrograms
            );
            AgentState childProgramAgent = inheritedAgent;
            float repairFidelity = saturate(
                parent.regulation.w * 0.55 + parent.physiology.x * 0.30 +
                parent.physiology.w * 0.15
            );
            float replicationDamage = saturate(
                parent.signals.z * 0.58 + (1.0 - parent.physiology.w) * 0.42
            );
            float replicationError = clamp(
                (0.020 + inheritedAgent.geneB.y * 0.62 + replicationDamage * 0.040) *
                    mix(1.0, 0.42, repairFidelity) * max(uniforms.mutationScale, 0.25),
                0.020, 0.10
            );
            bool programMutated = false;
            bool programCrossbred = false;
            uint donorPersistentID = 0xffffffffu;
            if (recombinationDonor < maxCellCount &&
                random01(divisionSeed + 1741u) <
                    clamp(recombinationScore * 0.28, 0.0, 0.22)) {
                atomic_fetch_add_explicit(
                    &identityCounters[14], 1u, memory_order_relaxed
                );
                CellIdentity donorIdentity = cellIdentities[recombinationDonor];
                uint daughterProgramGeneration = 0u;
                uint daughterProgram = claimHeritableProgram(
                    programSlots, identityCounters, divisionSeed ^ 0x72b4a91du,
                    daughterProgramGeneration
                );
                if (daughterProgram < maxHeritableProgramCount) {
                    childProgramAgent = recombineCellPrograms(
                        developmentalGenomes, regulatoryNodes, regulatoryEdges,
                        resonanceGenomes, heritablePrograms, programSlots,
                        agent, parentIdentity.programIndex, donorIdentity.programIndex,
                        daughterProgram, daughterProgramGeneration,
                        childIdentity.persistentID, divisionSeed ^ 0x3f6a2c87u
                    );
                    childIdentity.programIndex = daughterProgram;
                    childIdentity.programGeneration = daughterProgramGeneration;
                    donorPersistentID = donorIdentity.persistentID;
                    programCrossbred = true;
                }
            }
            bool mutationDue = !programCrossbred && accrueProgramMutationHazard(
                programSlots, parentIdentity.programIndex,
                parentIdentity.programGeneration, replicationError
            );
            if (mutationDue) {
                uint daughterProgramGeneration = 0u;
                uint daughterProgram = claimHeritableProgram(
                    programSlots, identityCounters, divisionSeed ^ 0x4b1d5a77u,
                    daughterProgramGeneration
                );
                if (daughterProgram < maxHeritableProgramCount) {
                    uint replicationGeneration =
                        heritablePrograms[parentIdentity.programIndex].generation + 1u;
                    float evolvedStructuralRate = clamp(
                        0.08 + inheritedDevelopment.mutation.w * 0.78,
                        0.08, 0.22
                    );
                    bool structuralMutation = random01(divisionSeed + 1789u) <
                        evolvedStructuralRate;
                    childProgramAgent = mutateCellProgram(
                        developmentalGenomes, regulatoryNodes, regulatoryEdges,
                        resonanceGenomes, heritablePrograms, programSlots, identityCounters,
                        agent, parentIdentity.programIndex, daughterProgram,
                        daughterProgramGeneration, childIdentity.persistentID,
                        replicationGeneration, divisionSeed ^ 0x8da6b343u,
                        uniforms.mutationScale, structuralMutation
                    );
                    childIdentity.programIndex = daughterProgram;
                    childIdentity.programGeneration = daughterProgramGeneration;
                    programMutated = true;
                }
            }
            if (!retainHeritableProgram(
                programSlots, childIdentity.programIndex, childIdentity.programGeneration
            )) {
                if (childIdentity.programIndex != parentIdentity.programIndex) {
                    abandonHeritableProgram(
                        programSlots, identityCounters, childIdentity.programIndex
                    );
                }
                atomic_store_explicit(
                    &cellOccupancy[divisionTarget], 0u, memory_order_relaxed
                );
                return;
            }
            cellIdentities[divisionTarget] = childIdentity;
            cellParentIDs[divisionTarget] = parentIdentity.persistentID;
            programInteractions[divisionTarget] = float4(0.0, 0.0, -1.0, 0.0);
            uint cytokineticPairKey = cellPairKey(divisionParent, divisionTarget);
            uint cytokineticFingerprint = cellPairFingerprint(
                cellIdentities, divisionParent, divisionTarget
            );
            float daughterAdhesion = min(parent.phenotype.x, child.phenotype.x);
            float daughterRepair = min(parent.regulation.w, child.regulation.w);
            float daughterIntegrity = min(parent.physiology.w, child.physiology.w);
            float cytokineticTension = max(parent.membrane.w, child.membrane.w);
            float tensionGate = 1.0 / (1.0 + max(cytokineticTension, 0.0) * 6.0);
            float midbodyStrength = clamp(
                (0.32 + daughterAdhesion * 0.28 + daughterRepair * 0.20 +
                    daughterIntegrity * 0.20) * tensionGate,
                0.28, 0.94
            );
            uint midbodyJunction = findOrCreateCellJunction(
                cellJunctions, cytokineticPairKey, cytokineticFingerprint,
                uniforms.step, length(child.position - parent.position), midbodyStrength
            );
            if (midbodyJunction < cellJunctionCapacity) {
                float4 midbodyInheritedMaterial = sqrt(max(
                    developmentalGenomes[parentIdentity.programIndex].junctionMaterial *
                        developmentalGenomes[childIdentity.programIndex].junctionMaterial,
                    float4(0.0001)
                ));
                float midbodyRestDistance = length(child.position - parent.position);
                cellJunctions[midbodyJunction].flags = 3u;
                cellJunctions[midbodyJunction].age = mix(
                    5.0, 14.0, daughterRepair * daughterIntegrity
                );
                cellJunctions[midbodyJunction].material = clamp(float4(
                    midbodyStrength * midbodyInheritedMaterial.x,
                    midbodyInheritedMaterial.z,
                    midbodyInheritedMaterial.w * daughterIntegrity,
                    midbodyInheritedMaterial.y * (0.45 + daughterRepair * 0.55)
                ), float4(0.02), float4(1.80));
                cellJunctions[midbodyJunction].remodeling = float4(
                    midbodyRestDistance, 0.0,
                    daughterRepair * daughterIntegrity, 1.0
                );
            }
            uint ownerHead = atomic_load_explicit(
                &ownerCellHeads[owner], memory_order_relaxed
            );
            if (ownerHead == emptySpatialHashEntry || divisionTarget < ownerHead) {
                ownerCellNext[divisionTarget] = ownerHead;
                atomic_store_explicit(
                    &ownerCellHeads[owner], divisionTarget, memory_order_relaxed
                );
            } else {
                uint previous = ownerHead;
                uint following = ownerCellNext[previous];
                while (following != emptySpatialHashEntry && following < divisionTarget) {
                    previous = following;
                    following = ownerCellNext[following];
                }
                ownerCellNext[divisionTarget] = following;
                ownerCellNext[previous] = divisionTarget;
            }
            agent.biomass = min(agent.biomass + 0.0008, 1.0);
            if (agent.generation > 0u) {
                // A separated fragment becomes a regenerative descendant only
                // after its own cells restart and complete the division cycle.
                agent.componentFlags |= componentRegeneratedFlag;
            }
            agents[owner] = agent;
            atomic_store_explicit(&contactWorkState[2], 1u, memory_order_relaxed);
            HeritableProgram childProgram = heritablePrograms[childIdentity.programIndex];
            DevelopmentalGenome childDevelopment =
                developmentalGenomes[childIdentity.programIndex];
            ResonanceGenome childResonance = resonanceGenomes[childIdentity.programIndex];
            recordCellLineageEvent(
                lineageEvents, identityCounters, 5u, childIdentity,
                parentIdentity.persistentID, child, childProgram,
                childDevelopment, childResonance, 0.0, uniforms.step
            );
            if (programMutated) {
                recordCellLineageEvent(
                    lineageEvents, identityCounters, 4u, childIdentity,
                    parentIdentity.persistentID, child, childProgram,
                    childDevelopment, childResonance,
                    childProgramAgent.lastMutationDistance, uniforms.step
                );
            }
            if (programCrossbred) {
                recordCellLineageEvent(
                    lineageEvents, identityCounters, 6u, childIdentity,
                    donorPersistentID, child, childProgram,
                    childDevelopment, childResonance,
                    childProgramAgent.lastMutationDistance, uniforms.step
                );
            }
        }
        }
        index = nextIndex;
    }

    float activeCount = 0.0;
    float atpTotal = 0.0;
    float biomassTotal = 0.0;
    float cycleTotal = 0.0;
    float integrityTotal = 0.0;
    float stressTotal = 0.0;
    float dividingCount = 0.0;
    float voltageTotal = 0.0;
    float frequencyTotal = 0.0;
    float2 phaseTotal = float2(0.0);
    float strainTotal = 0.0;
    float contractilityTotal = 0.0;
    float waveSpeedTotal = 0.0;
    float4 energeticsTotal = float4(0.0);
    float4 regulationTotal = float4(0.0);
    float4 regulationBTotal = float4(0.0);
    float4 causalityTotal = float4(0.0);
    float resonanceDisplacementTotal = 0.0;
    float resonanceAmplitudeTotal = 0.0;
    float membraneAreaTotal = 0.0;
    float membranePerimeterTotal = 0.0;
    float membraneShapeTotal = 0.0;
    float junctionForceTotal = 0.0;
    float4 signalingTotal = float4(0.0);
    float4 signalCausalityTotal = float4(0.0);
    float4 environmentTotal = float4(0.0);
    float4 developmentTotal = float4(0.0);
    float2 developmentalPolarityTotal = float2(0.0);
    float morphogenDifferentiationTotal = 0.0;
    float morphogenSynthesisTotal = 0.0;
    float morphogenTransportWorkTotal = 0.0;
    float2 cellCentroid = float2(0.0);
    float2 boundaryCentroidTotal = float2(0.0);
    float boundaryLength = 0.0;
    float2 netForce = float2(0.0);
    float meanForceMagnitude = 0.0;
    float contactLoad = 0.0;
    float trophicGain = 0.0;
    float trophicLoss = 0.0;
    float maximumDetachment = 0.0;
    float nonDominantProgramCount = 0.0;
    float4 programEcologyTotal = float4(0.0);
    float recognitionSampleCount = 0.0;
    uint programFingerprint = 0u;
    uint maximumProgramReplicationGeneration = 0u;
    index = atomic_load_explicit(&ownerCellHeads[owner], memory_order_relaxed);
    while (index != emptySpatialHashEntry) {
        uint nextIndex = ownerCellNext[index];
        if (atomic_load_explicit(&cellOccupancy[index], memory_order_relaxed) == 0u ||
            cellIdentities[index].owner != owner) {
            index = nextIndex;
            continue;
        }
        CellState cell = cells[index];
        activeCount += 1.0;
        uint cellProgramIndex = cellIdentities[index].programIndex;
        nonDominantProgramCount += cellProgramIndex != agent.dominantProgramIndex ? 1.0 : 0.0;
        if (cellProgramIndex < maxHeritableProgramCount) {
            programFingerprint |= 1u << (hash32(cellProgramIndex) & 31u);
            maximumProgramReplicationGeneration = max(
                maximumProgramReplicationGeneration,
                heritablePrograms[cellProgramIndex].generation
            );
        }
        float4 programInteraction = programInteractions[index];
        programEcologyTotal.x += abs(programInteraction.x);
        programEcologyTotal.y += programInteraction.y;
        programEcologyTotal.w += programInteraction.w;
        if (programInteraction.z >= 0.0) {
            programEcologyTotal.z += programInteraction.z;
            recognitionSampleCount += 1.0;
        }
        atpTotal += cell.physiology.x;
        biomassTotal += cell.physiology.y;
        cycleTotal += cell.physiology.z;
        integrityTotal += cell.physiology.w;
        stressTotal += cell.signals.z;
        dividingCount += cell.physiology.z >= 0.78 ? 1.0 : 0.0;
        voltageTotal += cell.dynamics.x;
        frequencyTotal += cell.dynamics.w;
        float phaseAngle = cell.dynamics.z * 2.0 * M_PI_F;
        phaseTotal += float2(cos(phaseAngle), sin(phaseAngle));
        strainTotal += cell.mechanics.y;
        contractilityTotal += cell.mechanics.x;
        waveSpeedTotal += cell.mechanics.z;
        energeticsTotal += cell.energetics;
        regulationTotal += cell.regulation;
        regulationBTotal += cell.regulationB;
        resonanceDisplacementTotal += cell.resonance.x;
        resonanceAmplitudeTotal += cell.resonance.z;
        membraneAreaTotal += cell.membrane.x;
        membranePerimeterTotal += cell.membrane.y;
        membraneShapeTotal += cell.membrane.z;
        junctionForceTotal += cell.membrane.w;
        signalingTotal += cell.signaling;
        signalCausalityTotal += cell.signalCausality;
        environmentTotal += cell.environment;
        developmentTotal += float4(
            cell.signals.xy, cell.development.z, cell.development.w
        );
        developmentalPolarityTotal += length(cell.development.xy) > 0.0001
            ? normalize(cell.development.xy) : float2(0.0);
        morphogenDifferentiationTotal += abs(cell.signals.x - cell.signals.y);
        uint developmentalProgramIndex = cellIdentities[index].programIndex;
        if (developmentalProgramIndex < maxHeritableProgramCount) {
            DevelopmentalGenome cellDevelopment =
                developmentalGenomes[developmentalProgramIndex];
            float activatorAutocatalysis = cell.signals.x * cell.signals.x /
                max(0.08 + cell.signals.x * cell.signals.x, 0.0001);
            float inhibitorSuppression = 1.0 / (
                1.0 + cell.signals.y * cellDevelopment.morphogenTransport.y * 1.4
            );
            morphogenSynthesisTotal +=
                cellDevelopment.morphogenKinetics.x *
                    mix(0.34, 1.20, cell.regulationB.y) *
                    mix(0.42, 1.0, activatorAutocatalysis) *
                    inhibitorSuppression * 0.00155 +
                cellDevelopment.morphogenKinetics.y *
                    mix(1.05, 0.46, cell.regulationB.y) *
                    (0.48 + cell.signals.x *
                        cellDevelopment.morphogenTransport.x * 0.52) * 0.00145;
        }
        morphogenTransportWorkTotal += cell.development.w * 0.006;
        netForce += cell.tissueForce.xy;
        meanForceMagnitude += length(cell.tissueForce.xy);
        contactLoad += cell.tissueForce.z;
        trophicGain += max(cell.tissueForce.w, 0.0);
        trophicLoss += max(-cell.tissueForce.w, 0.0);
        maximumDetachment = max(maximumDetachment, cell.tissueGeometry.w);
        float energySupport = cellularEnergySupport(cell.physiology.x, cell.energetics);
        float unconstrainedCycleDrive = cellCycleDrive(
            cell.physiology.x, cell.physiology.y, cell.energetics,
            cell.regulation.x, cell.signals.z, cell.tissueGeometry.z
        );
        float cycleDecay = cellCycleQuiescenceDecay(
            energySupport, cell.interaction.z, cell.signals.z
        );
        float contactEffect = -(unconstrainedCycleDrive * cell.interaction.z + cycleDecay);
        float repairEffect = cell.regulation.w * cell.physiology.x * 0.00022;
        causalityTotal += float4(
            cell.interaction.w, unconstrainedCycleDrive, contactEffect, repairEffect
        );
        cellCentroid += cell.position;
        uint membraneBase = index * membraneVertexCount;
        for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
            uint nextVertex = (vertexIndex + 1u) % membraneVertexCount;
            float2 a = cell.position + membraneVertices[membraneBase + vertexIndex].position;
            float2 b = cell.position + membraneVertices[membraneBase + nextVertex].position;
            float2 midpoint = (a + b) * 0.5;
            if (membraneVertices[membraneBase + vertexIndex].mechanics.w < 0.0) { continue; }
            float edgeLength = length(b - a);
            boundaryLength += edgeLength;
            boundaryCentroidTotal += midpoint * edgeLength;
        }
        index = nextIndex;
    }

    float inverseCount = 1.0 / max(activeCount, 1.0);
    cellCentroid *= inverseCount;
    float2 boundaryCentroid = boundaryLength > 0.0001
        ? boundaryCentroidTotal / boundaryLength : cellCentroid;
    float covarianceXX = 0.0;
    float covarianceXY = 0.0;
    float covarianceYY = 0.0;
    float boundaryWeight = 0.0;
    index = atomic_load_explicit(&ownerCellHeads[owner], memory_order_relaxed);
    while (index != emptySpatialHashEntry) {
        uint nextIndex = ownerCellNext[index];
        if (atomic_load_explicit(&cellOccupancy[index], memory_order_relaxed) == 0u ||
            cellIdentities[index].owner != owner) {
            index = nextIndex;
            continue;
        }
        CellState cell = cells[index];
        uint membraneBase = index * membraneVertexCount;
        for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
            uint nextVertex = (vertexIndex + 1u) % membraneVertexCount;
            float2 a = cell.position + membraneVertices[membraneBase + vertexIndex].position;
            float2 b = cell.position + membraneVertices[membraneBase + nextVertex].position;
            if (membraneVertices[membraneBase + vertexIndex].mechanics.w < 0.0) { continue; }
            float edgeLength = length(b - a);
            float2 offsetA = a - boundaryCentroid;
            float2 offsetB = b - boundaryCentroid;
            covarianceXX += edgeLength * (
                offsetA.x * offsetA.x + offsetA.x * offsetB.x + offsetB.x * offsetB.x
            ) / 3.0;
            covarianceXY += edgeLength * (
                2.0 * offsetA.x * offsetA.y + offsetA.x * offsetB.y +
                offsetB.x * offsetA.y + 2.0 * offsetB.x * offsetB.y
            ) / 6.0;
            covarianceYY += edgeLength * (
                offsetA.y * offsetA.y + offsetA.y * offsetB.y + offsetB.y * offsetB.y
            ) / 3.0;
            boundaryWeight += edgeLength;
        }
        index = nextIndex;
    }
    float inverseBoundaryWeight = 1.0 / max(boundaryWeight, 0.0001);
    covarianceXX *= inverseBoundaryWeight;
    covarianceXY *= inverseBoundaryWeight;
    covarianceYY *= inverseBoundaryWeight;
    float covarianceTrace = covarianceXX + covarianceYY;
    float covarianceDiscriminant = sqrt(max(
        (covarianceXX - covarianceYY) * (covarianceXX - covarianceYY) +
            4.0 * covarianceXY * covarianceXY,
        0.0
    ));
    float majorEigenvalue = max((covarianceTrace + covarianceDiscriminant) * 0.5, 0.000001);
    float minorEigenvalue = max((covarianceTrace - covarianceDiscriminant) * 0.5, 0.000001);
    float2 principalAxis = abs(covarianceXY) > 0.000001
        ? normalize(float2(covarianceXY, majorEigenvalue - covarianceXX))
        : (covarianceXX >= covarianceYY ? float2(1.0, 0.0) : float2(0.0, 1.0));
    float2 secondaryAxis = float2(-principalAxis.y, principalAxis.x);
    float positiveMajorExtent = 0.0;
    float negativeMajorExtent = 0.0;
    float positiveMinorExtent = 0.0;
    float negativeMinorExtent = 0.0;
    index = atomic_load_explicit(&ownerCellHeads[owner], memory_order_relaxed);
    while (index != emptySpatialHashEntry) {
        uint nextIndex = ownerCellNext[index];
        if (atomic_load_explicit(&cellOccupancy[index], memory_order_relaxed) == 0u ||
            cellIdentities[index].owner != owner) {
            index = nextIndex;
            continue;
        }
        CellState cell = cells[index];
        uint membraneBase = index * membraneVertexCount;
        for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
            uint nextVertex = (vertexIndex + 1u) % membraneVertexCount;
            float2 a = cell.position + membraneVertices[membraneBase + vertexIndex].position;
            float2 b = cell.position + membraneVertices[membraneBase + nextVertex].position;
            if (membraneVertices[membraneBase + vertexIndex].mechanics.w < 0.0) { continue; }
            float2 offsetA = a - boundaryCentroid;
            float2 offsetB = b - boundaryCentroid;
            float2 majorProjection = float2(
                dot(offsetA, principalAxis), dot(offsetB, principalAxis)
            );
            float2 minorProjection = float2(
                dot(offsetA, secondaryAxis), dot(offsetB, secondaryAxis)
            );
            positiveMajorExtent = max(
                positiveMajorExtent, max(majorProjection.x, majorProjection.y)
            );
            negativeMajorExtent = max(
                negativeMajorExtent, max(-majorProjection.x, -majorProjection.y)
            );
            positiveMinorExtent = max(
                positiveMinorExtent, max(minorProjection.x, minorProjection.y)
            );
            negativeMinorExtent = max(
                negativeMinorExtent, max(-minorProjection.x, -minorProjection.y)
            );
        }
        index = nextIndex;
    }
    float majorExtent = max(
        positiveMajorExtent + negativeMajorExtent, sqrt(majorEigenvalue) * 2.0
    );
    float minorExtent = max(
        positiveMinorExtent + negativeMinorExtent, sqrt(minorEigenvalue) * 2.0
    );
    float2 geometryPolarity = principalAxis *
        ((positiveMajorExtent - negativeMajorExtent) / max(majorExtent, 0.0001)) +
        secondaryAxis *
        ((positiveMinorExtent - negativeMinorExtent) / max(minorExtent, 0.0001));
    float elongation = saturate(
        (majorExtent - minorExtent) / max(majorExtent + minorExtent, 0.0001)
    );
    float squaredRadius = 0.0;
    float tissueTorque = 0.0;
    index = atomic_load_explicit(&ownerCellHeads[owner], memory_order_relaxed);
    while (index != emptySpatialHashEntry) {
        uint nextIndex = ownerCellNext[index];
        if (atomic_load_explicit(&cellOccupancy[index], memory_order_relaxed) != 0u &&
            cellIdentities[index].owner == owner) {
            CellState cell = cells[index];
            float2 offset = cell.position - cellCentroid;
            squaredRadius += dot(offset, offset);
            tissueTorque += offset.x * cell.tissueForce.y - offset.y * cell.tissueForce.x;
            cell.position = offset;
            cells[index] = cell;
        }
        index = nextIndex;
    }

    CellAggregate aggregate;
    aggregate.physiology = float4(
        activeCount, atpTotal * inverseCount,
        integrityTotal * inverseCount, stressTotal * inverseCount
    );
    aggregate.morphology = float4(
        biomassTotal * inverseCount, cycleTotal * inverseCount,
        sqrt(squaredRadius * inverseCount), dividingCount * inverseCount
    );
    float phaseCoherence = saturate(length(phaseTotal) * inverseCount);
    float meanPhase = phaseCoherence > 0.0001
        ? fract(atan2(phaseTotal.y, phaseTotal.x) / (2.0 * M_PI_F) + 1.0) : 0.0;
    aggregate.dynamics = float4(
        voltageTotal * inverseCount, phaseCoherence,
        frequencyTotal * inverseCount, meanPhase
    );
    aggregate.mechanics = float4(
        strainTotal * inverseCount, contractilityTotal * inverseCount,
        waveSpeedTotal * inverseCount,
        (energeticsTotal.x - energeticsTotal.y - energeticsTotal.z - energeticsTotal.w) *
            inverseCount
    );
    aggregate.energetics = energeticsTotal;
    aggregate.regulation = regulationTotal * inverseCount;
    aggregate.regulationB = regulationBTotal * inverseCount;
    aggregate.causality = causalityTotal * inverseCount;
    aggregate.resonance = float4(
        resonanceDisplacementTotal * inverseCount,
        resonanceAmplitudeTotal * inverseCount,
        frequencyTotal * inverseCount,
        agent.dominantProgramIndex < maxHeritableProgramCount
            ? resonanceGenomes[agent.dominantProgramIndex].mechanics.y : 0.0
    );
    aggregate.shape = float4(
        membraneAreaTotal * inverseCount, membranePerimeterTotal * inverseCount,
        membraneShapeTotal * inverseCount, junctionForceTotal * inverseCount
    );
    aggregate.signaling = signalingTotal * inverseCount;
    aggregate.signalCausality = signalCausalityTotal * inverseCount;
    aggregate.geometryAxes = float4(principalAxis, majorExtent, minorExtent);
    aggregate.geometryBoundary = float4(
        length(geometryPolarity) > 0.0001 ? normalize(geometryPolarity) : principalAxis,
        elongation, boundaryLength
    );
    aggregate.tissueMotion = float4(
        netForce, tissueTorque, meanForceMagnitude * inverseCount
    );
    aggregate.trophic = float4(
        contactLoad, trophicGain, trophicLoss, maximumDetachment
    );
    float nonDominantFraction = nonDominantProgramCount * inverseCount;
    aggregate.inheritance = float4(
        1.0 - nonDominantFraction,
        nonDominantFraction,
        float(popcount(programFingerprint)),
        float(agent.dominantProgramIndex)
    );
    aggregate.programEcology = float4(
        programEcologyTotal.x * inverseCount,
        programEcologyTotal.y * inverseCount,
        recognitionSampleCount > 0.0
            ? programEcologyTotal.z / recognitionSampleCount : -1.0,
        programEcologyTotal.w * inverseCount
    );
    aggregate.environment = environmentTotal * inverseCount;
    aggregate.development = developmentTotal * inverseCount;
    aggregate.developmentCausality = float4(
        morphogenDifferentiationTotal * inverseCount,
        saturate(length(developmentalPolarityTotal) * inverseCount),
        morphogenSynthesisTotal * inverseCount,
        morphogenTransportWorkTotal * inverseCount
    );
    aggregates[owner] = aggregate;
    agent.programReplicationGeneration = maximumProgramReplicationGeneration;
    agents[owner] = agent;
}


kernel void resetActiveComponentDispatch(
    device atomic_uint* activeComponentCount [[buffer(0)]],
    device uint* dispatchArguments [[buffer(1)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid != 0u) { return; }
    atomic_store_explicit(activeComponentCount, 0u, memory_order_relaxed);
    dispatchArguments[0] = 0u;
    dispatchArguments[1] = 1u;
    dispatchArguments[2] = 1u;
}

kernel void compactActiveComponents(
    device const atomic_uint* occupancy [[buffer(0)]],
    device uint* activeComponents [[buffer(1)]],
    device atomic_uint* activeComponentCount [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= maxAgentCount ||
        atomic_load_explicit(&occupancy[gid], memory_order_relaxed) != 1u) { return; }
    uint compactIndex = atomic_fetch_add_explicit(
        activeComponentCount, 1u, memory_order_relaxed
    );
    activeComponents[compactIndex] = gid;
}

kernel void prepareActiveComponentDispatch(
    device const atomic_uint* activeComponentCount [[buffer(0)]],
    device uint* dispatchArguments [[buffer(1)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid != 0u) { return; }
    uint count = atomic_load_explicit(activeComponentCount, memory_order_relaxed);
    dispatchArguments[0] = (count + 63u) / 64u;
    dispatchArguments[1] = 1u;
    dispatchArguments[2] = 1u;
}

kernel void compactActiveCellsOrdered(
    device const atomic_uint* cellOccupancy [[buffer(0)]],
    device uint* activeCellIndices [[buffer(1)]],
    device atomic_uint* activeCellCount [[buffer(2)]],
    device uint* dispatchArguments [[buffer(3)]],
    uint threadIndex [[thread_index_in_threadgroup]],
    uint threadCount [[threads_per_threadgroup]]
) {
    threadgroup uint localCounts[256];
    threadgroup uint localOffsets[256];
    uint chunkSize = (maxCellCount + threadCount - 1u) / threadCount;
    uint start = min(threadIndex * chunkSize, maxCellCount);
    uint end = min(start + chunkSize, maxCellCount);
    uint localCount = 0u;
    for (uint cellIndex = start; cellIndex < end; ++cellIndex) {
        if (atomic_load_explicit(&cellOccupancy[cellIndex], memory_order_relaxed) != 0u) {
            localCount += 1u;
        }
    }
    localCounts[threadIndex] = localCount;
    threadgroup_barrier(mem_flags::mem_threadgroup);

    if (threadIndex == 0u) {
        uint prefix = 0u;
        for (uint index = 0u; index < threadCount; ++index) {
            localOffsets[index] = prefix;
            prefix += localCounts[index];
        }
        atomic_store_explicit(activeCellCount, prefix, memory_order_relaxed);
        dispatchArguments[0] = (prefix + 63u) / 64u;
        dispatchArguments[1] = 1u;
        dispatchArguments[2] = 1u;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    uint output = localOffsets[threadIndex];
    for (uint cellIndex = start; cellIndex < end; ++cellIndex) {
        if (atomic_load_explicit(&cellOccupancy[cellIndex], memory_order_relaxed) != 0u) {
            activeCellIndices[output++] = cellIndex;
        }
    }
}

kernel void expandAgents(
    device AgentState* agents [[buffer(0)]],
    device atomic_uint* occupancy [[buffer(1)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= maxAgentCount || atomic_load_explicit(&occupancy[gid], memory_order_relaxed) == 0u) { return; }
    AgentState agent = agents[gid];
    agent.position = 0.25 + agent.position * 0.5;
    agent.velocity *= 0.5;
    agents[gid] = agent;
}

kernel void resetRenderDrawArguments(
    device atomic_uint* cellDrawArguments [[buffer(0)]],
    device atomic_uint* meshDispatchArguments [[buffer(1)]],
    device atomic_uint* junctionDrawArguments [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid != 0u) { return; }
    for (uint index = 0u; index < 4u; ++index) {
        atomic_store_explicit(&cellDrawArguments[index], 0u, memory_order_relaxed);
        atomic_store_explicit(&junctionDrawArguments[index], 0u, memory_order_relaxed);
    }
    for (uint index = 0u; index < 3u; ++index) {
        atomic_store_explicit(&meshDispatchArguments[index], 0u, memory_order_relaxed);
    }
}

kernel void compactVisibleCells(
    device const atomic_uint* agentOccupancy [[buffer(0)]],
    device const atomic_uint* cellOccupancy [[buffer(1)]],
    device uint* visibleCellIndices [[buffer(2)]],
    device atomic_uint* drawArguments [[buffer(3)]],
    constant SimulationUniforms& uniforms [[buffer(4)]],
    device const CellIdentity* cellIdentities [[buffer(5)]],
    device const AgentState* agents [[buffer(6)]],
    device const CellState* cells [[buffer(7)]],
    device atomic_uint* meshDispatchArguments [[buffer(8)]],
    device const atomic_uint* activeCellCount [[buffer(29)]],
    device const uint* activeCellIndices [[buffer(30)]],
    uint compactIndex [[thread_position_in_grid]]
) {
    if (compactIndex >= atomic_load_explicit(activeCellCount, memory_order_relaxed)) { return; }
    uint gid = activeCellIndices[compactIndex];
    if (gid >= maxCellCount ||
        atomic_load_explicit(&cellOccupancy[gid], memory_order_relaxed) == 0u) { return; }
    uint owner = cellIdentities[gid].owner;
    if (owner >= maxAgentCount ||
        atomic_load_explicit(&agentOccupancy[owner], memory_order_relaxed) == 0u) { return; }
    float observationZoom = uniforms.cameraZoom / max(uniforms.worldScale, 1.0);
    if (observationZoom <= 0.35 || observationZoom >= 180.0) { return; }
    if (uniforms.trackedAgentID != 0xffffffffu &&
        uniforms.trackedAgentID != owner && observationZoom >= 34.0) { return; }

    float2 center = cellWorldPosition(agents[owner], cells[gid].position, uniforms);
    float safeAspect = max(uniforms.viewportAspect, 0.001);
    float2 viewScale = safeAspect >= 1.0
        ? float2(1.0, 1.0 / safeAspect) : float2(safeAspect, 1.0);
    float2 screenUV = 0.5 + (center - uniforms.cameraCenter) *
        max(uniforms.cameraZoom, 0.000000001) / viewScale;
    float2 screenRadius = float2(0.30 * cellWorldScale(uniforms) * uniforms.cameraZoom) /
        viewScale;
    float2 margin = screenRadius + float2(0.004);
    if (any(screenUV < -margin) || any(screenUV > 1.0 + margin)) { return; }

    uint target = atomic_fetch_add_explicit(&drawArguments[1], 1u, memory_order_relaxed);
    atomic_fetch_add_explicit(&meshDispatchArguments[0], 1u, memory_order_relaxed);
    if (target < maxCellCount) {
        visibleCellIndices[target] = gid;
    }
}

kernel void compactVisibleJunctions(
    device const CellJunctionState* junctionStates [[buffer(0)]],
    device const atomic_uint* cellOccupancy [[buffer(1)]],
    device const CellIdentity* cellIdentities [[buffer(2)]],
    device const AgentState* agents [[buffer(3)]],
    device const atomic_uint* agentOccupancy [[buffer(4)]],
    device const CellState* cells [[buffer(5)]],
    constant SimulationUniforms& uniforms [[buffer(6)]],
    device uint* visibleJunctionIndices [[buffer(7)]],
    device atomic_uint* drawArguments [[buffer(8)]],
    uint junctionIndex [[thread_position_in_grid]]
) {
    if (junctionIndex >= cellJunctionCapacity) { return; }
    uint pairKey = atomic_load_explicit(
        &junctionStates[junctionIndex].pairKey, memory_order_relaxed
    );
    if (pairKey == emptySpatialHashEntry || pairKey == 0u) { return; }
    uint packedPair = pairKey - 1u;
    uint cellA = packedPair / maxCellCount;
    uint cellB = packedPair % maxCellCount;
    if (cellA >= maxCellCount || cellB >= maxCellCount || cellA >= cellB ||
        atomic_load_explicit(&cellOccupancy[cellA], memory_order_relaxed) == 0u ||
        atomic_load_explicit(&cellOccupancy[cellB], memory_order_relaxed) == 0u) { return; }
    uint owner = cellIdentities[cellA].owner;
    if (owner >= maxAgentCount || cellIdentities[cellB].owner != owner ||
        atomic_load_explicit(&agentOccupancy[owner], memory_order_relaxed) == 0u) { return; }
    uint lastSeen = atomic_load_explicit(
        &junctionStates[junctionIndex].lastSeenStep, memory_order_relaxed
    );
    if (uniforms.step < lastSeen || uniforms.step - lastSeen > 180u ||
        junctionStates[junctionIndex].persistentFingerprint !=
            cellPairFingerprint(cellIdentities, cellA, cellB) ||
        !isfinite(junctionStates[junctionIndex].load) ||
        !all(isfinite(junctionStates[junctionIndex].material)) ||
        !all(isfinite(junctionStates[junctionIndex].remodeling))) { return; }

    float observationZoom = uniforms.cameraZoom / max(uniforms.worldScale, 1.0);
    if (observationZoom <= 1.25 || observationZoom >= 180.0 ||
        (uniforms.trackedAgentID != 0xffffffffu &&
            uniforms.trackedAgentID != owner && observationZoom >= 34.0)) { return; }
    float2 centerA = cellWorldPosition(agents[owner], cells[cellA].position, uniforms);
    float2 centerB = cellWorldPosition(agents[owner], cells[cellB].position, uniforms);
    if (!all(isfinite(centerA)) || !all(isfinite(centerB))) { return; }
    float safeAspect = max(uniforms.viewportAspect, 0.001);
    float2 viewScale = safeAspect >= 1.0
        ? float2(1.0, 1.0 / safeAspect) : float2(safeAspect, 1.0);
    float2 screenA = 0.5 + (centerA - uniforms.cameraCenter) *
        max(uniforms.cameraZoom, 0.000000001) / viewScale;
    float2 screenB = 0.5 + (centerB - uniforms.cameraCenter) *
        max(uniforms.cameraZoom, 0.000000001) / viewScale;
    float2 lower = min(screenA, screenB);
    float2 upper = max(screenA, screenB);
    if (any(upper < float2(-0.025)) || any(lower > float2(1.025))) { return; }

    uint target = atomic_fetch_add_explicit(&drawArguments[1], 1u, memory_order_relaxed);
    if (target < cellJunctionCapacity) {
        visibleJunctionIndices[target] = junctionIndex;
    }
}

kernel void finalizeRenderDrawArguments(
    device atomic_uint* cellDrawArguments [[buffer(0)]],
    device atomic_uint* meshDispatchArguments [[buffer(1)]],
    device atomic_uint* junctionDrawArguments [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid != 0u) { return; }
    uint cellCount = min(
        atomic_load_explicit(&cellDrawArguments[1], memory_order_relaxed),
        maxCellCount
    );
    uint meshCount = min(
        atomic_load_explicit(&meshDispatchArguments[0], memory_order_relaxed),
        maxCellCount
    );
    uint junctionCount = min(
        atomic_load_explicit(&junctionDrawArguments[1], memory_order_relaxed),
        cellJunctionCapacity
    );
    atomic_store_explicit(
        &cellDrawArguments[0], membraneRenderSegmentCount * 3u, memory_order_relaxed
    );
    atomic_store_explicit(&cellDrawArguments[1], cellCount, memory_order_relaxed);
    atomic_store_explicit(&cellDrawArguments[2], 0u, memory_order_relaxed);
    atomic_store_explicit(&cellDrawArguments[3], 0u, memory_order_relaxed);
    atomic_store_explicit(&meshDispatchArguments[0], meshCount, memory_order_relaxed);
    atomic_store_explicit(&meshDispatchArguments[1], 1u, memory_order_relaxed);
    atomic_store_explicit(&meshDispatchArguments[2], 1u, memory_order_relaxed);
    atomic_store_explicit(&junctionDrawArguments[0], 6u, memory_order_relaxed);
    atomic_store_explicit(&junctionDrawArguments[1], junctionCount, memory_order_relaxed);
    atomic_store_explicit(&junctionDrawArguments[2], 0u, memory_order_relaxed);
    atomic_store_explicit(&junctionDrawArguments[3], 0u, memory_order_relaxed);
}

struct RasterData {
    float4 position [[position]];
    float2 uv;
};

vertex RasterData fullscreenVertex(uint vertexID [[vertex_id]]) {
    const float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    const float2 coordinates[3] = { float2(0.0, 1.0), float2(2.0, 1.0), float2(0.0, -1.0) };
    RasterData output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.uv = coordinates[vertexID];
    return output;
}

inline float3 hsvToRGB(float3 hsv) {
    float3 p = abs(fract(hsv.xxx + float3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
    return hsv.z * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), hsv.y);
}

inline float visualNoise(float2 position) {
    float2 base = floor(position);
    float2 fraction = fract(position);
    fraction = fraction * fraction * (3.0 - 2.0 * fraction);
    uint2 p = uint2(base);
    float a = random01(p.x * 1597334677u ^ p.y * 3812015801u);
    float b = random01((p.x + 1u) * 1597334677u ^ p.y * 3812015801u);
    float c = random01(p.x * 1597334677u ^ (p.y + 1u) * 3812015801u);
    float d = random01((p.x + 1u) * 1597334677u ^ (p.y + 1u) * 3812015801u);
    return mix(mix(a, b, fraction.x), mix(c, d, fraction.x), fraction.y);
}

inline float complexCurrent(float2 amplitude, float2 neighbor) {
    return amplitude.x * neighbor.y - amplitude.y * neighbor.x;
}

inline float spinorPhase(float4 spinor) {
    float2 amplitude = spinor.xy + spinor.zw;
    return fract(atan2(amplitude.y, amplitude.x) / (2.0 * M_PI_F) + 1.0);
}

inline float wrappedPhaseDelta(float from, float to) {
    return fract(to - from + 0.5) - 0.5;
}

inline float3 quantumPhaseColor(float phase) {
    float3 cycle = 0.5 + 0.5 * cos(2.0 * M_PI_F * (phase + float3(0.00, 0.67, 0.33)));
    return mix(float3(0.05, 0.13, 0.24), pow(cycle, float3(0.72)), 0.88);
}

kernel void bloomPrefilter(
    texture2d<half, access::sample> source [[texture(0)]],
    texture2d<half, access::write> destination [[texture(1)]],
    constant PostProcessUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destination.get_width() || gid.y >= destination.get_height()) { return; }
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = (float2(gid) + 0.5) / float2(destination.get_width(), destination.get_height());
    float2 sourceTexel = 1.0 / max(uniforms.sourceSize, float2(1.0));
    float2 outer = sourceTexel * 6.0;
    float2 inner = sourceTexel * 3.0;
    float3 center = float3(source.sample(linearSampler, uv).rgb);
    float3 axial =
        float3(source.sample(linearSampler, uv + float2( outer.x, 0.0)).rgb) +
        float3(source.sample(linearSampler, uv + float2(-outer.x, 0.0)).rgb) +
        float3(source.sample(linearSampler, uv + float2(0.0,  outer.y)).rgb) +
        float3(source.sample(linearSampler, uv + float2(0.0, -outer.y)).rgb);
    float3 outerCorners =
        float3(source.sample(linearSampler, uv + float2( outer.x,  outer.y)).rgb) +
        float3(source.sample(linearSampler, uv + float2(-outer.x,  outer.y)).rgb) +
        float3(source.sample(linearSampler, uv + float2( outer.x, -outer.y)).rgb) +
        float3(source.sample(linearSampler, uv + float2(-outer.x, -outer.y)).rgb);
    float3 innerCorners =
        float3(source.sample(linearSampler, uv + float2( inner.x,  inner.y)).rgb) +
        float3(source.sample(linearSampler, uv + float2(-inner.x,  inner.y)).rgb) +
        float3(source.sample(linearSampler, uv + float2( inner.x, -inner.y)).rgb) +
        float3(source.sample(linearSampler, uv + float2(-inner.x, -inner.y)).rgb);
    float3 color = center * 0.125 + axial * 0.0625 +
        outerCorners * 0.03125 + innerCorners * 0.125;
    color = all(isfinite(color)) ? clamp(color, 0.0, 16.0) : float3(0.0);

    const float threshold = 0.92;
    const float knee = 0.38;
    float brightness = max(max(color.r, color.g), color.b);
    float soft = clamp(brightness - threshold + knee, 0.0, 2.0 * knee);
    soft = soft * soft / (4.0 * knee + 0.0001);
    float contribution = max(brightness - threshold, soft) / max(brightness, 0.0001);
    destination.write(half4(half3(color * contribution), half(1.0)), gid);
}

inline float3 mapToDisplay(
    float3 linearScene,
    float3 linearBloom,
    constant PostProcessUniforms& uniforms,
    uint2 pixel
) {
    if (!all(isfinite(linearScene))) { linearScene = float3(0.0); }
    if (!all(isfinite(linearBloom))) { linearBloom = float3(0.0); }
    linearScene = clamp(linearScene, 0.0, 16.0);
    linearBloom = clamp(linearBloom, 0.0, 16.0);
    float3 hdr = linearScene * uniforms.exposure + linearBloom * uniforms.bloomIntensity;

    float peak = max(max(hdr.r, hdr.g), hdr.b);
    float peakScale = (1.0 - exp(-peak)) / max(peak, 0.0001);
    float3 mapped = hdr * peakScale;
    float luminance = dot(mapped, float3(0.2126, 0.7152, 0.0722));
    float saturation = uniforms.observationZoom >= 420.0 ? 1.02 :
        (uniforms.observationZoom >= 160.0 ? 1.18 :
            (uniforms.observationZoom >= 64.0 ? 1.15 : 1.08));
    mapped = mix(float3(luminance), mapped, saturation);

    float dither = random01(pixel.x * 1597334677u ^ pixel.y * 3812015801u ^
        uniforms.frameIndex * 2246822519u) - 0.5;
    return saturate(mapped + dither / 1023.0);
}

inline float4 finiteHDRColor(float3 color, float gain) {
    color *= gain;
    if (!all(isfinite(color))) {
        return float4(0.0015, 0.003, 0.006, 1.0);
    }
    return float4(clamp(color, 0.0, 16.0), 1.0);
}

fragment float4 compositeFragment(
    RasterData input [[stage_in]],
    texture2d<half, access::sample> scene [[texture(0)]],
    texture2d<half, access::sample> bloom [[texture(1)]],
    constant PostProcessUniforms& uniforms [[buffer(0)]]
) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float3 linearScene = float3(scene.sample(linearSampler, input.uv).rgb);
    float3 linearBloom = uniforms.bloomIntensity > 0.001
        ? float3(bloom.sample(linearSampler, input.uv).rgb)
        : float3(0.0);
    return float4(mapToDisplay(
        linearScene, linearBloom, uniforms, uint2(input.position.xy)
    ), 1.0);
}

inline float segmentDistance(float2 point, float2 start, float2 end) {
    float2 segment = end - start;
    float position = saturate(dot(point - start, segment) / max(dot(segment, segment), 0.000001));
    return length(point - (start + segment * position));
}

inline float taperedSegmentMask(
    float2 point,
    float2 start,
    float2 end,
    float startWidth,
    float endWidth,
    float antialiasWidth
) {
    float2 segment = end - start;
    float position = saturate(dot(point - start, segment) / max(dot(segment, segment), 0.000001));
    float distance = length(point - (start + segment * position));
    float width = mix(startWidth, endWidth, position);
    return 1.0 - smoothstep(width - antialiasWidth, width + antialiasWidth, distance);
}

inline float3 spinorCellVisualization(float2 uv, float4 wave, float currentStrength) {
    float2 quantumCell = fract(uv * float(quantumGridSize));
    bool positiveComponent = quantumCell.x < 0.5;
    float2 componentPosition = positiveComponent
        ? float2(quantumCell.x * 2.0 - 0.5, quantumCell.y * 2.0 - 1.0)
        : float2((quantumCell.x - 0.5) * 2.0 - 0.5, quantumCell.y * 2.0 - 1.0);
    float2 positiveAmplitude = wave.xy;
    float2 negativeAmplitude = wave.zw;
    float probabilityA = dot(positiveAmplitude, positiveAmplitude);
    float probabilityB = dot(negativeAmplitude, negativeAmplitude);
    float totalProbability = probabilityA + probabilityB;
    float componentProbability = positiveComponent ? probabilityA : probabilityB;
    float scaledProbability = componentProbability * 900000.0;
    float componentDensity = scaledProbability / (1.0 + scaledProbability);
    float2 componentAmplitude = positiveComponent ? positiveAmplitude : negativeAmplitude;
    float inverseComponentMagnitude = rsqrt(max(componentProbability, 0.0000000001));
    float2 phasor = componentAmplitude * inverseComponentMagnitude;
    float componentCosine = phasor.x;
    float componentSine = phasor.y;
    float crossMagnitude = sqrt(max(probabilityA * probabilityB, 0.0));
    float balance = 2.0 * crossMagnitude / max(totalProbability, 0.0000000001);
    float phaseAlignment = saturate(0.5 + 0.5 * dot(positiveAmplitude, negativeAmplitude) /
        max(crossMagnitude, 0.0000000001));
    float localCoherence = balance * phaseAlignment;

    float3 componentBase = positiveComponent ? float3(0.02, 0.82, 1.0) : float3(1.0, 0.25, 0.035);
    float3 phaseCycle = 0.5 + 0.5 * float3(
        componentCosine,
        -0.481754 * componentCosine + 0.876307 * componentSine,
        -0.481754 * componentCosine - 0.876307 * componentSine
    );
    float3 phaseColor = mix(float3(0.05, 0.13, 0.24),
        mix(phaseCycle, sqrt(max(phaseCycle, 0.0)), 0.56), 0.88);
    float3 componentColor = mix(componentBase, phaseColor, 0.44);
    float radius = length(componentPosition);
    float antialiasWidth = max(fwidth(radius) * 1.25, 0.0015);
    float componentMask = 1.0 - smoothstep(0.46 - antialiasWidth, 0.46 + antialiasWidth, radius);
    float componentEdge = 1.0 - smoothstep(antialiasWidth * 0.8, antialiasWidth * 2.6,
        abs(radius - 0.46));

    float phasorDistance = abs(componentPosition.x * phasor.y - componentPosition.y * phasor.x);
    float forwardProjection = dot(componentPosition, phasor);
    float phasorLine = (1.0 - smoothstep(0.008, 0.008 + antialiasWidth * 2.2, phasorDistance)) *
        smoothstep(-0.03, 0.03, forwardProjection) *
        (1.0 - smoothstep(0.31, 0.36, forwardProjection));
    float2 arrowTip = phasor * 0.34;
    float2 arrowNormal = float2(-phasor.y, phasor.x);
    float arrowHead = max(
        taperedSegmentMask(componentPosition, arrowTip, arrowTip - phasor * 0.085 + arrowNormal * 0.060,
            0.014, 0.004, antialiasWidth),
        taperedSegmentMask(componentPosition, arrowTip, arrowTip - phasor * 0.085 - arrowNormal * 0.060,
            0.014, 0.004, antialiasWidth)
    );

    float probabilityRadius = 0.10 + componentDensity * 0.24;
    float probabilityRing = 1.0 - smoothstep(antialiasWidth * 1.2, antialiasWidth * 3.2,
        abs(radius - probabilityRadius));
    float latticeDistance = min(min(quantumCell.x, 1.0 - quantumCell.x),
        min(quantumCell.y, 1.0 - quantumCell.y));
    float latticeAA = max(fwidth(latticeDistance) * 1.5, 0.001);
    float latticeEdge = 1.0 - smoothstep(latticeAA, latticeAA * 3.0, latticeDistance);
    float componentDivider = 1.0 - smoothstep(latticeAA, latticeAA * 2.8, abs(quantumCell.x - 0.5));
    float coherenceBridge = (1.0 - smoothstep(0.010, 0.010 + latticeAA * 3.0,
        abs(quantumCell.y - 0.5))) *
        smoothstep(0.19, 0.27, quantumCell.x) *
        (1.0 - smoothstep(0.73, 0.81, quantumCell.x));

    float radialShading = 0.38 + 0.62 * sqrt(saturate(1.0 - radius * radius / 0.22));
    float3 color = float3(0.0015, 0.003, 0.009);
    color += componentColor * componentMask * componentDensity * radialShading;
    color += componentBase * componentEdge * (0.38 + componentDensity * 0.42);
    color += componentColor * probabilityRing * componentMask * 0.72;
    color += float3(0.94, 0.985, 1.0) * max(phasorLine, arrowHead) * componentMask *
        (0.54 + componentDensity * 0.72);
    color += mix(float3(0.12, 0.52, 0.96), float3(0.96, 0.28, 0.48), phaseAlignment) *
        coherenceBridge * localCoherence * (0.42 + currentStrength * 0.46);
    color += float3(0.08, 0.18, 0.27) * latticeEdge * 0.72;
    color += float3(0.18, 0.38, 0.50) * componentDivider * 0.44;
    return color;
}

inline float3 molecularReactionVisualization(
    float2 uv,
    float4 localState,
    float4 localEcology,
    float4 localGeology,
    float4 geneA,
    float4 geneC,
    float quantumOrder,
    float chemicalAffinity,
    float catalystProduction,
    float energyProduction,
    float membraneAssembly,
    float mineralization,
    float phase,
    float2 reactionDirection,
    float fieldGridSize,
    uint step,
    uint displayMode
) {
    const float3 resourceAColor = float3(0.015, 0.56, 1.0);
    const float3 resourceBColor = float3(0.48, 0.12, 1.0);
    const float3 catalystColor = float3(0.02, 0.92, 0.74);
    const float3 energyColor = float3(1.0, 0.68, 0.025);
    const float3 membraneColor = float3(0.03, 1.0, 0.58);
    const float3 detritusColor = float3(1.0, 0.30, 0.025);
    const float3 toxinColor = float3(1.0, 0.025, 0.01);

    float resourceA = saturate(localState.x);
    float resourceB = saturate(localEcology.x);
    float storedEnergy = saturate(localState.z * 14.0);
    float membrane = saturate(localState.w * 22.0);
    float detritus = saturate(localEcology.y);
    float toxin = saturate(localEcology.z * 1.2);
    float catalyst = saturate(localEcology.w * 10.0);
    // Concentrations span orders of magnitude. Square-root encoding changes only
    // marker occupancy; field hue and all flux calculations retain linear values.
    float resourceAAbundance = saturate(sqrt(resourceA) * 1.85);
    float resourceBAbundance = saturate(sqrt(resourceB) * 1.85);
    float catalystAbundance = saturate(sqrt(catalyst) * 1.55);
    float energyAbundance = saturate(sqrt(storedEnergy) * 1.60);
    float membraneAbundance = saturate(sqrt(membrane) * 1.65);
    float detritusAbundance = saturate(sqrt(detritus) * 1.35);
    float toxinAbundance = saturate(sqrt(toxin) * 1.20);
    float reactionPotential = saturate(
        resourceA * 0.26 + resourceB * 0.26 + catalyst * 0.22 +
        storedEnergy * 0.16 + membrane * 0.10
    );
    float2 fieldCoordinate = uv * fieldGridSize;
    float fieldContour = 1.0 - smoothstep(0.026, 0.105,
        abs(fract(reactionPotential * 13.0 +
            visualNoise(fieldCoordinate * 0.31) * 0.18) - 0.5));
    float catalystHotspot = catalyst * chemicalAffinity *
        (0.42 + quantumOrder * 0.58);
    float energyHotspot = storedEnergy *
        (0.32 + saturate(energyProduction * 280.0) * 0.68);

    float substrateTotal = saturate((resourceA + resourceB) * 3.4);
    float substrateBalance = resourceB / max(resourceA + resourceB, 0.00001);
    float3 substrateHue = mix(resourceAColor, resourceBColor,
        smoothstep(0.12, 0.88, substrateBalance));
    float barrier = smoothstep(0.48, 0.84, localGeology.w);
    float3 color = float3(0.0012, 0.0028, 0.0070);
    color += substrateHue * substrateTotal * (0.038 + fieldContour * 0.030);
    color += catalystColor * catalystHotspot * fieldContour * 0.10;
    color += energyColor * energyHotspot * fieldContour * 0.085;
    color += membraneColor * membrane * fieldContour * 0.095;
    color += detritusColor * detritus * (1.0 - fieldContour) * 0.055;
    color = mix(color, toxinColor * (0.08 + color), toxin * 0.22);

    float2 glyphCoordinate = uv * fieldGridSize * 6.0;
    int2 glyphCell = int2(floor(glyphCoordinate));
    uint glyphSeed = hash32(
        uint(glyphCell.x) * 1597334677u ^
        uint(glyphCell.y) * 3812015801u
    );
    float2 jitter = float2(
        random01(glyphSeed + 1u), random01(glyphSeed + 2u)
    ) - 0.5;
    float2 glyphPosition = fract(glyphCoordinate) - 0.5 - jitter * 0.34;
    float glyphAngle = 2.0 * M_PI_F * random01(glyphSeed + 3u) + phase * 0.72;
    float2 glyphAxis = float2(cos(glyphAngle), sin(glyphAngle));
    float2 glyphNormal = float2(-glyphAxis.y, glyphAxis.x);
    float selector = random01(glyphSeed + 4u);
    float aa = max(fwidth(length(glyphPosition)) * 1.35, 0.003);
    float glyph = 0.0;
    float abundance = 0.0;
    float3 glyphColor = float3(0.0);
    if (selector < 0.20) {
        float2 offset = glyphAxis * 0.064;
        glyph = max(
            1.0 - smoothstep(0.052, 0.052 + aa * 2.0, length(glyphPosition - offset)),
            1.0 - smoothstep(0.052, 0.052 + aa * 2.0, length(glyphPosition + offset))
        );
        glyph = max(glyph, 1.0 - smoothstep(
            0.012, 0.012 + aa * 2.0,
            segmentDistance(glyphPosition, -offset, offset)
        ));
        abundance = resourceAAbundance;
        glyphColor = resourceAColor;
    } else if (selector < 0.39) {
        float2 a = glyphAxis * 0.070;
        float2 b = -glyphAxis * 0.045 + glyphNormal * 0.064;
        float2 c = -glyphAxis * 0.045 - glyphNormal * 0.064;
        glyph = max(
            1.0 - smoothstep(0.045, 0.045 + aa * 2.0, length(glyphPosition - a)),
            max(
                1.0 - smoothstep(0.045, 0.045 + aa * 2.0, length(glyphPosition - b)),
                1.0 - smoothstep(0.045, 0.045 + aa * 2.0, length(glyphPosition - c))
            )
        );
        glyph = max(glyph, 1.0 - smoothstep(
            0.010, 0.010 + aa * 2.0,
            min(segmentDistance(glyphPosition, a, b), segmentDistance(glyphPosition, a, c))
        ));
        abundance = resourceBAbundance;
        glyphColor = resourceBColor;
    } else if (selector < 0.55) {
        float radius = length(glyphPosition);
        glyph = 1.0 - smoothstep(aa, aa * 3.0, abs(radius - 0.095));
        glyph = max(glyph,
            1.0 - smoothstep(0.026, 0.026 + aa * 2.0, radius));
        abundance = catalystAbundance;
        glyphColor = catalystColor;
    } else if (selector < 0.70) {
        float diamond = abs(glyphPosition.x) + abs(glyphPosition.y);
        glyph = 1.0 - smoothstep(0.070, 0.070 + aa * 2.4, diamond);
        float pulse = 0.65 + 0.35 * sin(
            float(step) * 0.090 + random01(glyphSeed + 5u) * 2.0 * M_PI_F
        );
        abundance = energyAbundance * pulse;
        glyphColor = energyColor;
    } else if (selector < 0.84) {
        float along = dot(glyphPosition, glyphAxis);
        float across = abs(dot(glyphPosition, glyphNormal) -
            sin(along * 35.0 + phase * 2.0 * M_PI_F) * 0.020);
        glyph = (1.0 - smoothstep(0.012, 0.012 + aa * 2.0, across)) *
            (1.0 - smoothstep(0.09, 0.13, abs(along)));
        abundance = membraneAbundance;
        glyphColor = membraneColor;
    } else if (selector < 0.94) {
        float shardA = 1.0 - smoothstep(0.012, 0.012 + aa * 2.0,
            segmentDistance(glyphPosition, -glyphAxis * 0.10, glyphNormal * 0.07));
        float shardB = 1.0 - smoothstep(0.012, 0.012 + aa * 2.0,
            segmentDistance(glyphPosition, glyphAxis * 0.09, -glyphNormal * 0.06));
        glyph = max(shardA, shardB);
        abundance = detritusAbundance;
        glyphColor = detritusColor;
    } else {
        float crossA = 1.0 - smoothstep(0.013, 0.013 + aa * 2.0,
            segmentDistance(glyphPosition, -glyphAxis * 0.10, glyphAxis * 0.10));
        float crossB = 1.0 - smoothstep(0.013, 0.013 + aa * 2.0,
            segmentDistance(glyphPosition, -glyphNormal * 0.10, glyphNormal * 0.10));
        glyph = max(crossA, crossB);
        abundance = toxinAbundance;
        glyphColor = toxinColor;
    }
    float glyphThreshold = random01(glyphSeed + 6u) * 0.58;
    float glyphVisibility = smoothstep(glyphThreshold,
        min(glyphThreshold + 0.14, 1.0), abundance);
    color += glyphColor * glyph * glyphVisibility * (0.82 + abundance * 0.96);

    float2 safeReactionDirection = length(reactionDirection) > 0.0001
        ? normalize(reactionDirection)
        : float2(cos(phase * 2.0 * M_PI_F), sin(phase * 2.0 * M_PI_F));
    float2 reactionNormal = float2(-safeReactionDirection.y, safeReactionDirection.x);
    float streamline = 1.0 - smoothstep(0.018, 0.060,
        abs(fract(dot(fieldCoordinate, reactionNormal) * 0.32) - 0.5));
    float movingPulse = 1.0 - smoothstep(0.018, 0.075,
        abs(fract(dot(fieldCoordinate, safeReactionDirection) * 0.13 -
            float(step) * 0.010) - 0.5));
    float recyclePulse = 1.0 - smoothstep(0.018, 0.070,
        abs(fract(dot(fieldCoordinate, safeReactionDirection) * 0.11 +
            float(step) * 0.007 + 0.37) - 0.5));
    float reactionTrace = streamline * movingPulse;
    float recycleTrace = streamline * recyclePulse;
    // Logarithmic radiometry keeps source terms visible across several decades
    // while preserving zero and monotonic ordering.
    float catalystFlux = saturate(log2(1.0 + catalystProduction * 1.0e6) * 0.18);
    float energyFlux = saturate(log2(1.0 + energyProduction * 4.0e6) * 0.18);
    float assemblyFlux = saturate(log2(1.0 + membraneAssembly * 1.0e6) * 0.18);
    float recycleFlux = saturate(log2(1.0 + mineralization * 8.0e6) * 0.18);
    float reactionRing = 1.0 - smoothstep(0.010, 0.030,
        abs(length(glyphPosition) - 0.155));
    color += mix(catalystColor, energyColor, energyFlux) * reactionTrace *
        max(catalystFlux, energyFlux) * 0.96;
    color += membraneColor * reactionTrace * assemblyFlux * 0.88;
    color += detritusColor * recycleTrace * recycleFlux * 0.56;
    color += mix(catalystColor, energyColor, energyFlux) * reactionRing *
        glyphVisibility * max(catalystFlux, energyFlux) * 0.42;
    color *= 1.0 - toxin * (0.12 + streamline * 0.25);

    if (displayMode == 1u) {
        float substrateRadiance = saturate(sqrt(resourceA + resourceB) * 0.68);
        color = float3(0.0015, 0.0035, 0.0080);
        color += substrateHue * substrateRadiance * (0.12 + fieldContour * 0.075);
        color += energyColor * energyHotspot * (0.34 + movingPulse * 0.26);
        color += catalystColor * catalystHotspot * fieldContour * 0.18;
        color += detritusColor * detritus * (0.08 + recycleTrace * 0.18);
        color += glyphColor * glyph * glyphVisibility * (0.72 + abundance * 0.76);
        color += mix(catalystColor, energyColor, energyFlux) * reactionTrace *
            max(catalystFlux, energyFlux) * 0.68;
        color += membraneColor * reactionTrace * assemblyFlux * 0.72;
        color += detritusColor * recycleTrace * recycleFlux * 0.44;
    } else if (displayMode == 2u) {
        color = float3(0.002, 0.005, 0.010);
        color += float3(1.0, 0.12, 0.035) * saturate(geneA.x) * 0.34;
        color += float3(0.04, 0.94, 0.58) * saturate(geneA.y) * 0.31;
        color += float3(0.08, 0.42, 1.0) * saturate(geneA.z) * 0.28;
        color += float3(0.94, 0.46, 0.04) * saturate(geneC.w) * 0.34;
        color *= 0.72 + fieldContour * 0.44;
    } else if (displayMode == 3u) {
        color = float3(0.002, 0.004, 0.009) +
            resourceAColor * resourceA * 0.42 +
            resourceBColor * resourceB * 0.38 +
            detritusColor * detritus * 0.30 +
            toxinColor * toxin * 0.38;
    } else if (displayMode == 4u) {
        color = float3(0.002, 0.005, 0.010) +
            catalystColor * catalystHotspot * 0.52 +
            energyColor * energyHotspot * 0.44 +
            membraneColor * membrane * (0.28 + fieldContour * 0.34);
    } else if (displayMode == 5u) {
        color = float3(0.0015, 0.003, 0.007);
        color += float3(0.02, 0.84, 1.0) * quantumOrder * chemicalAffinity * 0.24;
        color += catalystColor * catalystFlux * (0.20 + reactionTrace * 0.94);
        color += energyColor * energyFlux * (0.18 + reactionTrace * 0.86);
        color += membraneColor * assemblyFlux * reactionTrace * 0.92;
        color += detritusColor * recycleFlux * recycleTrace * 0.66;
        color += toxinColor * toxin * 0.18;
    }
    return max(color * (1.0 - barrier * 0.82), 0.0);
}

struct JunctionRasterData {
    float4 position [[position]];
    float2 ribbonCoordinate;
    float4 mechanics;
    float4 transport;
    float4 lineageA;
    float4 lineageB;
    float visibility;
};

vertex JunctionRasterData junctionVertex(
    device const AgentState* agents [[buffer(0)]],
    device const atomic_uint* agentOccupancy [[buffer(1)]],
    device const CellState* cells [[buffer(2)]],
    device const atomic_uint* cellOccupancy [[buffer(3)]],
    device const MembraneVertex* membraneVertices [[buffer(4)]],
    constant SimulationUniforms& uniforms [[buffer(5)]],
    device const uint* visibleJunctionIndices [[buffer(6)]],
    device const CellIdentity* cellIdentities [[buffer(7)]],
    device const HeritableProgram* heritablePrograms [[buffer(8)]],
    device const float4* programInteractions [[buffer(9)]],
    device const ProgramSlotState* programSlots [[buffer(10)]],
    device const CellJunctionState* junctionStates [[buffer(11)]],
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]]
) {
    JunctionRasterData output = {};
    output.position = float4(3.0, 3.0, 0.0, 1.0);
    if (instanceID >= cellJunctionCapacity || vertexID >= 6u) { return output; }
    uint junctionIndex = visibleJunctionIndices[instanceID];
    if (junctionIndex >= cellJunctionCapacity) { return output; }
    uint pairKey = atomic_load_explicit(
        &junctionStates[junctionIndex].pairKey, memory_order_relaxed
    );
    if (pairKey == emptySpatialHashEntry || pairKey == 0u) { return output; }
    uint packedPair = pairKey - 1u;
    uint cellA = packedPair / maxCellCount;
    uint cellB = packedPair % maxCellCount;
    if (cellA >= maxCellCount || cellB >= maxCellCount || cellA >= cellB ||
        atomic_load_explicit(&cellOccupancy[cellA], memory_order_relaxed) == 0u ||
        atomic_load_explicit(&cellOccupancy[cellB], memory_order_relaxed) == 0u) { return output; }
    CellIdentity identityA = cellIdentities[cellA];
    CellIdentity identityB = cellIdentities[cellB];
    uint owner = identityA.owner;
    if (owner >= maxAgentCount || identityB.owner != owner ||
        atomic_load_explicit(&agentOccupancy[owner], memory_order_relaxed) == 0u) { return output; }

    AgentState agent = agents[owner];
    CellState stateA = cells[cellA];
    CellState stateB = cells[cellB];
    float2 centerA = cellWorldPosition(agent, stateA.position, uniforms);
    float2 centerB = cellWorldPosition(agent, stateB.position, uniforms);
    float2 centerDelta = centerB - centerA;
    if (!all(isfinite(centerA)) || !all(isfinite(centerB)) ||
        length(centerDelta) < 0.0000001) { return output; }
    float2 directionAB = normalize(centerDelta);
    MembraneSupportSample supportA = membraneSupportSample(
        membraneVertices, cellA, rotateWorldToTissue(directionAB, agent)
    );
    MembraneSupportSample supportB = membraneSupportSample(
        membraneVertices, cellB, rotateWorldToTissue(-directionAB, agent)
    );
    bool finiteSupport = all(isfinite(supportA.point)) && all(isfinite(supportB.point)) &&
        isfinite(supportA.integrity) && isfinite(supportB.integrity) &&
        length(supportA.point) >= 0.025 && length(supportB.point) >= 0.025 &&
        length(supportA.point) <= 0.30 && length(supportB.point) <= 0.30;
    if (!finiteSupport) { return output; }
    float worldUnit = cellWorldScale(uniforms);
    float2 membraneA = centerA + rotateTissueToWorld(supportA.point, agent) * worldUnit;
    float2 membraneB = centerB + rotateTissueToWorld(supportB.point, agent) * worldUnit;
    // The path enters each cytoplasm before crossing the measured support arcs so
    // directional transport remains legible while the junction stays physically anchored.
    float2 pathA = mix(centerA, membraneA, 0.72);
    float2 pathB = mix(centerB, membraneB, 0.72);
    float safeAspect = max(uniforms.viewportAspect, 0.001);
    float2 viewScale = safeAspect >= 1.0
        ? float2(1.0, 1.0 / safeAspect) : float2(safeAspect, 1.0);
    float2 screenA = 0.5 + (pathA - uniforms.cameraCenter) *
        max(uniforms.cameraZoom, 0.000000001) / viewScale;
    float2 screenB = 0.5 + (pathB - uniforms.cameraCenter) *
        max(uniforms.cameraZoom, 0.000000001) / viewScale;
    float2 clipA = float2(screenA.x * 2.0 - 1.0, 1.0 - screenA.y * 2.0);
    float2 clipB = float2(screenB.x * 2.0 - 1.0, 1.0 - screenB.y * 2.0);
    float2 clipDelta = clipB - clipA;
    if (!all(isfinite(clipA)) || !all(isfinite(clipB)) ||
        !all(isfinite(clipDelta)) || length(clipDelta) < 0.00001 ||
        any(abs(clipA) > float2(2.5)) || any(abs(clipB) > float2(2.5))) {
        return output;
    }

    const float2 quad[6] = {
        float2(0.0, -1.0), float2(1.0, -1.0), float2(0.0, 1.0),
        float2(0.0, 1.0), float2(1.0, -1.0), float2(1.0, 1.0)
    };
    float2 coordinate = quad[vertexID % 6u];
    float load = saturate(junctionStates[junctionIndex].load / 0.0028);
    float strain = clamp(junctionStates[junctionIndex].remodeling.y * 18.0, -1.0, 1.0);
    float strength = saturate(junctionStates[junctionIndex].strength);
    float corticalTension = saturate(junctionStates[junctionIndex].material.w);
    float thickness = clamp(
        worldUnit * uniforms.cameraZoom * (0.010 + load * 0.012 + corticalTension * 0.004),
        0.0018, 0.012
    );
    float2 normal = normalize(float2(-clipDelta.y, clipDelta.x));
    float2 clipPosition = mix(clipA, clipB, coordinate.x) +
        normal * coordinate.y * thickness;
    output.position = float4(clipPosition, 0.0, 1.0);
    output.ribbonCoordinate = coordinate;
    output.mechanics = float4(load, strain, strength, corticalTension);

    float4 interactionA = programInteractions[cellA];
    float4 interactionB = programInteractions[cellB];
    float signedATPTransport = clamp(
        0.5 * (interactionB.x - interactionA.x) * 5000.0, -1.0, 1.0
    );
    float conductance = saturate(
        strength * junctionStates[junctionIndex].material.z *
        min(stateA.physiology.w, stateB.physiology.w)
    );
    float signalAvailability = max(stateA.signaling.w, stateB.signaling.w);
    float signedCalciumTransport = clamp(
        (stateA.signaling.x - stateB.signaling.x) * conductance *
            signalAvailability * 2.4,
        -1.0, 1.0
    );
    float signedERKTransport = clamp(
        (stateA.signaling.y - stateB.signaling.y) * conductance *
            signalAvailability * 2.8,
        -1.0, 1.0
    );
    bool mixedPrograms = identityA.programIndex != identityB.programIndex ||
        identityA.programGeneration != identityB.programGeneration;
    output.transport = float4(
        signedATPTransport, signedCalciumTransport, signedERKTransport,
        mixedPrograms ? 1.0 : 0.0
    );

    float hueA = fract(float(hash32(identityA.persistentID)) / 4294967296.0);
    float hueB = fract(float(hash32(identityB.persistentID)) / 4294967296.0);
    if (programSlotMatches(programSlots, identityA.programIndex, identityA.programGeneration)) {
        hueA = fract(heritablePrograms[identityA.programIndex].geneB.w);
    }
    if (programSlotMatches(programSlots, identityB.programIndex, identityB.programGeneration)) {
        hueB = fract(heritablePrograms[identityB.programIndex].geneB.w);
    }
    output.lineageA = float4(hsvToRGB(float3(hueA, 0.82, 0.92)), 1.0);
    output.lineageB = float4(hsvToRGB(float3(hueB, 0.82, 0.92)), 1.0);
    float observationZoom = uniforms.cameraZoom / max(uniforms.worldScale, 1.0);
    output.visibility = smoothstep(2.0, 8.0, observationZoom) *
        (1.0 - smoothstep(112.0, 180.0, observationZoom));
    return output;
}

fragment float4 junctionFragment(
    JunctionRasterData input [[stage_in]],
    constant SimulationUniforms& uniforms [[buffer(0)]]
) {
    float along = saturate(input.ribbonCoordinate.x);
    float side = abs(input.ribbonCoordinate.y);
    float edgeAA = max(fwidth(side) * 1.2, 0.018);
    float ribbon = 1.0 - smoothstep(0.90, 0.90 + edgeAA, side);
    if (ribbon <= 0.001 || input.visibility <= 0.001) { discard_fragment(); }

    float load = saturate(input.mechanics.x);
    float signedStrain = clamp(input.mechanics.y, -1.0, 1.0);
    float strength = saturate(input.mechanics.z);
    float corticalTension = saturate(input.mechanics.w);
    float3 compressionColor = float3(0.04, 0.62, 1.0);
    float3 tensionColor = float3(1.0, 0.24, 0.025);
    float3 mechanicalColor = mix(
        compressionColor, tensionColor, saturate(signedStrain * 0.5 + 0.5)
    );
    float centerRail = 1.0 - smoothstep(0.18, 0.52, side);
    float3 color = mechanicalColor * ribbon * centerRail *
        (0.10 + load * 0.62 + corticalTension * 0.12);

    float time = float(uniforms.step);
    float atpFlux = input.transport.x;
    float atpDirection = atpFlux >= 0.0 ? 1.0 : -1.0;
    float atpCoordinate = atpDirection > 0.0 ? along : 1.0 - along;
    float atpPacket = 1.0 - smoothstep(0.045, 0.15,
        abs(fract(atpCoordinate * 3.0 - time * 0.025) - 0.5));
    float atpLane = 1.0 - smoothstep(0.12, 0.38, abs(side - 0.12));
    color += float3(1.0, 0.72, 0.025) * atpPacket * atpLane *
        saturate(abs(atpFlux)) * 1.42;

    float calciumFlux = input.transport.y;
    float calciumCoordinate = calciumFlux >= 0.0 ? along : 1.0 - along;
    float calciumWave = 1.0 - smoothstep(0.035, 0.13,
        abs(fract(calciumCoordinate * 2.0 - time * 0.017 + 0.18) - 0.5));
    float calciumLane = 1.0 - smoothstep(0.10, 0.30, abs(side - 0.46));
    color += float3(0.02, 0.88, 1.0) * calciumWave * calciumLane *
        saturate(abs(calciumFlux)) * 1.26;

    float erkFlux = input.transport.z;
    float erkCoordinate = erkFlux >= 0.0 ? along : 1.0 - along;
    float erkWave = 1.0 - smoothstep(0.040, 0.14,
        abs(fract(erkCoordinate * 2.0 - time * 0.013 + 0.61) - 0.5));
    float erkLane = 1.0 - smoothstep(0.10, 0.30, abs(side - 0.70));
    color += float3(0.98, 0.07, 0.62) * erkWave * erkLane *
        saturate(abs(erkFlux)) * 1.18;

    float mixedPrograms = saturate(input.transport.w);
    float lineageRail = smoothstep(0.62, 0.80, side) *
        (1.0 - smoothstep(0.88, 1.0, side));
    float3 lineageColor = mix(input.lineageA.rgb, input.lineageB.rgb, along);
    float lineagePacket = 0.72 + 0.28 * sin(
        along * 14.0 - time * 0.018 + signedStrain * 2.0
    );
    color += lineageColor * lineageRail * mixedPrograms * lineagePacket * 0.92;
    float mixingInterface = (1.0 - smoothstep(0.015, 0.070, abs(along - 0.5))) *
        mixedPrograms * (1.0 - smoothstep(0.0, 0.48, side));
    color += float3(0.94, 0.98, 1.0) * mixingInterface * 0.70;

    float activity = max(
        load, max(abs(atpFlux), max(abs(calciumFlux), abs(erkFlux)))
    );
    float alpha = ribbon * input.visibility * saturate(
        0.16 + strength * 0.18 + load * 0.28 + activity * 0.34 + mixedPrograms * 0.18
    );
    color *= input.visibility;
    if (!all(isfinite(color)) || !isfinite(alpha)) { discard_fragment(); }
    return float4(clamp(color, 0.0, 16.0), saturate(alpha));
}

struct CellRasterData {
    float4 position [[position]];
    float2 local;
    float4 physiology;
    float4 phenotype;
    float4 signals;
    float4 interaction;
    float4 dynamics;
    float4 mechanics;
    float4 energetics;
    float4 regulation;
    float4 regulationB;
    float4 resonance;
    float4 signaling;
    float4 signalCausality;
    float4 tissueGeometry;
    float4 tissueForce;
    float4 environment;
    float4 development;
    float4 programEcology;
    float4 construction;
    float lineageHue;
    float closureSignal;
    float visibility;
    float tracked;
    float radialCoordinate;
    float edgeExposure;
    float4 localMembrane;
};

inline float2 smoothMembranePosition(
    device const MembraneVertex* membraneVertices,
    uint cellIndex,
    uint renderSample
) {
    uint wrappedSample = renderSample % membraneRenderSegmentCount;
    uint vertexIndex = wrappedSample / membraneRenderSubdivision;
    uint subdivisionIndex = wrappedSample % membraneRenderSubdivision;
    uint previous = (vertexIndex + membraneVertexCount - 1u) % membraneVertexCount;
    uint next = (vertexIndex + 1u) % membraneVertexCount;
    uint base = cellIndex * membraneVertexCount;
    float2 previousPosition = membraneVertices[base + previous].position;
    float2 currentPosition = membraneVertices[base + vertexIndex].position;
    float2 nextPosition = membraneVertices[base + next].position;
    float2 curveStart = (previousPosition + currentPosition) * 0.5;
    float2 curveEnd = (currentPosition + nextPosition) * 0.5;
    float t = float(subdivisionIndex) / float(membraneRenderSubdivision);
    float oneMinusT = 1.0 - t;
    return curveStart * (oneMinusT * oneMinusT) +
        currentPosition * (2.0 * oneMinusT * t) + curveEnd * (t * t);
}

inline CellRasterData makeCellRasterData(
    device const AgentState* agents,
    device const uint* agentOccupancy,
    device const CellState* cells,
    device const uint* cellOccupancy,
    device const MembraneVertex* membraneVertices,
    constant SimulationUniforms& uniforms,
    device const uint* visibleCellIndices,
    device const CellIdentity* cellIdentities,
    device const HeritableProgram* heritablePrograms,
    device const float4* programInteractions,
    device const ProgramSlotState* programSlots,
    uint vertexID,
    uint instanceID
) {
    CellRasterData output = {};
    output.position = float4(3.0, 3.0, 0.0, 1.0);
    if (instanceID >= maxCellCount || vertexID >= membraneRenderSegmentCount * 3u) {
        return output;
    }
    uint cellIndex = visibleCellIndices[instanceID];
    if (cellIndex >= maxCellCount) { return output; }
    uint owner = cellIdentities[cellIndex].owner;
    if (owner >= maxAgentCount) { return output; }
    AgentState agent = agents[owner];
    CellState cell = cells[cellIndex];
    float observationZoom = uniforms.cameraZoom / max(uniforms.worldScale, 1.0);
    float scaleVisibility = smoothstep(0.35, 1.10, observationZoom) *
        (1.0 - smoothstep(112.0, 180.0, observationZoom));
    float trackingVisibility = uniforms.trackedAgentID == 0xffffffffu ||
        uniforms.trackedAgentID == owner ? 1.0 : 1.0 - smoothstep(16.0, 34.0, observationZoom);
    float visibility = scaleVisibility * trackingVisibility;

    float2 heading = tissueHeading(agent);
    float2 lateral = float2(-heading.y, heading.x);
    float worldUnit = cellWorldScale(uniforms);
    float2 cellCenter = cellWorldPosition(agent, cell.position, uniforms);
    uint triangle = vertexID / 3u;
    uint triangleVertex = vertexID % 3u;
    float2 membraneStart = smoothMembranePosition(membraneVertices, cellIndex, triangle);
    float2 membraneEnd = smoothMembranePosition(membraneVertices, cellIndex, triangle + 1u);
    uint membraneSample = triangleVertex == 2u ? triangle + 1u : triangle;
    float2 membranePosition = triangleVertex == 0u
        ? float2(0.0)
        : (triangleVertex == 1u ? membraneStart : membraneEnd);
    float startRadius = length(membraneStart);
    float endRadius = length(membraneEnd);
    float membraneEdgeLength = length(membraneEnd - membraneStart);
    float signedTriangleArea = membraneStart.x * membraneEnd.y -
        membraneStart.y * membraneEnd.x;
    bool finiteGeometry = all(isfinite(cellCenter)) &&
        all(isfinite(membraneStart)) && all(isfinite(membraneEnd)) &&
        all(cellCenter >= float2(-0.05)) && all(cellCenter <= float2(1.05)) &&
        startRadius >= 0.025 && endRadius >= 0.025 &&
        startRadius <= 0.30 && endRadius <= 0.30 &&
        membraneEdgeLength <= 0.08 && signedTriangleArea > 0.0000001;
    float2 worldPosition = cellCenter +
        heading * membranePosition.x * worldUnit +
        lateral * membranePosition.y * worldUnit;
    float safeAspect = max(uniforms.viewportAspect, 0.001);
    float2 viewScale = safeAspect >= 1.0 ? float2(1.0, 1.0 / safeAspect) : float2(safeAspect, 1.0);
    float2 screenUV = 0.5 + (worldPosition - uniforms.cameraCenter) *
        max(uniforms.cameraZoom, 0.000000001) / viewScale;
    finiteGeometry = finiteGeometry && all(isfinite(heading)) &&
        all(isfinite(worldPosition)) && all(isfinite(screenUV)) &&
        all(abs(screenUV - 0.5) <= float2(1.0));
    bool occupied = agentOccupancy[owner] != 0u && cellOccupancy[cellIndex] != 0u &&
        finiteGeometry && visibility > 0.001;

    output.position = occupied
        ? float4(screenUV.x * 2.0 - 1.0, 1.0 - screenUV.y * 2.0, 0.0, 1.0)
        : float4(3.0, 3.0, 0.0, 1.0);
    float membraneArea = isfinite(cell.membrane.x) ? max(cell.membrane.x, 0.010) : 0.010;
    float nominalRadius = clamp(sqrt(membraneArea / M_PI_F), 0.085, 0.18);
    output.local = membranePosition / nominalRadius;
    output.physiology = cell.physiology;
    output.phenotype = cell.phenotype;
    output.signals = cell.signals;
    output.interaction = cell.interaction;
    output.dynamics = cell.dynamics;
    output.mechanics = cell.mechanics;
    output.energetics = cell.energetics;
    output.regulation = cell.regulation;
    output.regulationB = cell.regulationB;
    output.resonance = cell.resonance;
    output.signaling = cell.signaling;
    output.signalCausality = cell.signalCausality;
    output.tissueGeometry = cell.tissueGeometry;
    output.tissueForce = cell.tissueForce;
    output.environment = cell.environment;
    output.development = cell.development;
    output.programEcology = programInteractions[cellIndex];
    uint programIndex = cellIdentities[cellIndex].programIndex;
    AgentState cellProgram = agentWithCellProgram(
        agent, programIndex, heritablePrograms
    );
    float constructionExposure = saturate(cell.tissueGeometry.z) *
        saturate(cell.physiology.x);
    output.construction = constructionExposure * float4(
        cell.regulationB.y * cell.regulationB.w *
            saturate((cellProgram.geneC.w - 0.025) * 2.2),
        cell.regulation.y * cell.regulation.w * cellProgram.geneA.w,
        cell.regulationB.x * cell.regulationB.y *
            (0.35 + saturate(cell.resonance.z * 5.0) * 0.65),
        cell.regulationB.w * cell.signaling.y
    );
    output.lineageHue = programSlotMatches(
        programSlots, programIndex, cellIdentities[cellIndex].programGeneration
    ) &&
        programIndex != agent.dominantProgramIndex
        ? heritablePrograms[programIndex].geneB.w : agent.geneB.w;
    float boundaryMaintenance = saturate(
        cell.physiology.x * cell.physiology.w * cell.regulation.w *
        (0.35 + saturate(cell.tissueGeometry.z) * 0.65)
    );
    float mechanochemicalLoop = pow(max(
        cell.signalCausality.x * cell.signalCausality.y *
        cell.signalCausality.z * length(cell.tissueForce.xy), 0.0
    ), 0.25);
    output.closureSignal = saturate(sqrt(
        boundaryMaintenance * saturate(mechanochemicalLoop * 160.0)
    ));
    output.visibility = visibility;
    output.tracked = uniforms.trackedAgentID == owner ? 1.0 : 0.0;
    output.radialCoordinate = triangleVertex == 0u ? 0.0 : 1.0;
    uint physicalEdge = (membraneSample / membraneRenderSubdivision) % membraneVertexCount;
    // Exposure is encoded by the sign so the stored strain magnitude remains available.
    float edgeExposure = membraneVertices[
        cellIndex * membraneVertexCount + physicalEdge
    ].mechanics.w > 0.0 ? 1.0 : 0.0;
    output.edgeExposure = triangleVertex == 0u
        ? saturate(cell.tissueGeometry.z)
        : edgeExposure;
    MembraneVertex localVertex = membraneVertices[
        cellIndex * membraneVertexCount + physicalEdge
    ];
    float localIntegrity = triangleVertex == 0u
        ? saturate(cell.physiology.w) : saturate(localVertex.mechanics.y);
    float localPressure = triangleVertex == 0u
        ? saturate(cell.tissueForce.z * 900.0)
        : saturate(localVertex.mechanics.z * 120.0);
    float localStrain = triangleVertex == 0u
        ? saturate(cell.mechanics.y)
        : saturate(abs(localVertex.mechanics.w) * 18.0);
    float paidRepair = saturate(
        cell.regulation.w * cell.physiology.x *
        (0.45 + saturate(cell.energetics.y * 2400.0) * 0.55)
    );
    output.localMembrane = float4(
        localIntegrity, localPressure, localStrain, paidRepair
    );
    return output;
}

vertex CellRasterData cellVertex(
    device const AgentState* agents [[buffer(0)]],
    device const uint* agentOccupancy [[buffer(1)]],
    device const CellState* cells [[buffer(2)]],
    device const uint* cellOccupancy [[buffer(3)]],
    device const MembraneVertex* membraneVertices [[buffer(4)]],
    constant SimulationUniforms& uniforms [[buffer(5)]],
    device const uint* visibleCellIndices [[buffer(6)]],
    device const CellIdentity* cellIdentities [[buffer(7)]],
    device const HeritableProgram* heritablePrograms [[buffer(8)]],
    device const float4* programInteractions [[buffer(9)]],
    device const ProgramSlotState* programSlots [[buffer(10)]],
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]]
) {
    return makeCellRasterData(
        agents, agentOccupancy, cells, cellOccupancy, membraneVertices, uniforms,
        visibleCellIndices, cellIdentities, heritablePrograms, programInteractions,
        programSlots, vertexID, instanceID
    );
}

using CellContourMesh = metal::mesh<
    CellRasterData, void, membraneRenderSegmentCount + 1u,
    membraneRenderSegmentCount, metal::topology::triangle
>;

[[mesh, max_total_threads_per_threadgroup(64)]]
void cellContourMesh(
    CellContourMesh output,
    device const AgentState* agents [[buffer(0)]],
    device const uint* agentOccupancy [[buffer(1)]],
    device const CellState* cells [[buffer(2)]],
    device const uint* cellOccupancy [[buffer(3)]],
    device const MembraneVertex* membraneVertices [[buffer(4)]],
    constant SimulationUniforms& uniforms [[buffer(5)]],
    device const uint* visibleCellIndices [[buffer(6)]],
    device const CellIdentity* cellIdentities [[buffer(7)]],
    device const HeritableProgram* heritablePrograms [[buffer(8)]],
    device const float4* programInteractions [[buffer(9)]],
    device const ProgramSlotState* programSlots [[buffer(10)]],
    uint lane [[thread_index_in_threadgroup]],
    uint meshIndex [[threadgroup_position_in_grid]]
) {
    float observationZoom = uniforms.cameraZoom / max(uniforms.worldScale, 1.0);
    uint segmentCount = observationZoom >= 6.0
        ? membraneRenderSegmentCount : membraneRenderSegmentCount / 2u;
    if (lane <= segmentCount) {
        uint sample = lane == 0u ? 0u :
            (lane - 1u) * (membraneRenderSegmentCount / segmentCount);
        uint syntheticVertex = lane == 0u ? 0u :
            (sample == 0u ? 1u : (sample - 1u) * 3u + 2u);
        output.set_vertex(lane, makeCellRasterData(
            agents, agentOccupancy, cells, cellOccupancy, membraneVertices, uniforms,
            visibleCellIndices, cellIdentities, heritablePrograms, programInteractions,
            programSlots, syntheticVertex, meshIndex
        ));
    }
    if (lane < segmentCount) {
        output.set_index(lane * 3u, 0u);
        output.set_index(lane * 3u + 1u, lane + 1u);
        output.set_index(lane * 3u + 2u, lane + 1u == segmentCount
            ? 1u : lane + 2u);
    }
    if (lane == 0u) {
        output.set_primitive_count(segmentCount);
    }
}

fragment float4 cellFragment(
    CellRasterData input [[stage_in]],
    constant SimulationUniforms& uniforms [[buffer(0)]]
) {
    float2 p = input.local;
    float angle = atan2(p.y, p.x);
    float oscillatorAngle = input.dynamics.z * 2.0 * M_PI_F;
    float2 polarityVector = input.development.xy;
    float2 morphologyAxis = length(polarityVector) > 0.001
        ? normalize(polarityVector)
        : float2(cos(oscillatorAngle), sin(oscillatorAngle));
    float2 morphologyNormal = float2(-morphologyAxis.y, morphologyAxis.x);
    float radius = input.radialCoordinate;
    float aa = max(fwidth(radius) * 1.15, 0.004);
    float body = 1.0 - smoothstep(1.0 - aa * 1.8, 1.0, radius);
    if (body <= 0.001) { discard_fragment(); }

    float integrity = saturate(input.localMembrane.x);
    float localPressure = saturate(input.localMembrane.y);
    float localStrain = saturate(input.localMembrane.z);
    float paidRepair = saturate(input.localMembrane.w);
    float membraneThickness = clamp(
        0.10 + integrity * 0.10 + paidRepair * 0.035 - localStrain * 0.025,
        0.065, 0.22
    );
    float membrane = body * smoothstep(1.0 - membraneThickness, 0.985, radius);
    float cytoplasm = body * (1.0 - smoothstep(0.62, 0.94, radius));
    float nucleusRadius = 0.20 + input.signals.x * 0.08;
    float2 nucleusPosition = morphologyAxis * (input.development.z - 0.5) * 0.18;
    float nucleus = (1.0 - smoothstep(nucleusRadius, nucleusRadius + aa * 2.0,
        length(p - nucleusPosition))) * body;
    float exposure = saturate(input.edgeExposure);
    float2 boundaryNormal = length(input.tissueGeometry.xy) > 0.0001
        ? normalize(input.tissueGeometry.xy) : morphologyAxis;
    float2 surfaceDirection = length(p) > 0.001 ? normalize(p) : boundaryNormal;
    float exposedArc = membrane * exposure;
    float localFailure = saturate((1.0 - integrity) * 1.35 + localStrain * 0.28);
    float membraneContinuity = 1.0 - localFailure * exposure *
        smoothstep(0.82, 1.0, radius) * 0.82;
    membrane *= membraneContinuity;
    exposedArc *= membraneContinuity;
    float woundArc = membrane * smoothstep(0.08, 0.78, localFailure);
    float repairDemand = saturate((1.0 - integrity) * 1.5 + localStrain * 0.30);
    float repairFront = membrane * paidRepair * repairDemand *
        (1.0 - smoothstep(0.88, 1.0, localFailure) * 0.46);
    float repairBoundary = body * paidRepair * repairDemand *
        (1.0 - smoothstep(0.018, 0.070,
            abs(radius - (1.0 - membraneThickness * 0.72))));
    float pressureFront = membrane * localPressure;
    float leakage = exposedArc * localFailure *
        (0.55 + 0.45 * sin(angle * 17.0 + input.dynamics.z * 9.0));
    float autonomySignal = saturate(input.closureSignal);
    float autonomyPulse = 0.88 + 0.12 * sin(
        input.dynamics.z * 2.0 * M_PI_F + angle * 3.0
    );
    float contactDamage = saturate(input.tissueForce.z * 1800.0);
    float trophicGain = saturate(max(input.tissueForce.w, 0.0) * 1800.0);
    float trophicLoss = saturate(max(-input.tissueForce.w, 0.0) * 1800.0);
    float tractionMagnitude = saturate(length(input.tissueForce.xy) * 11000.0);
    float barrierCompression = saturate(input.environment.y);
    float frequencyMatch = saturate(input.environment.w);
    float environmentalFrequencyCoordinate = saturate(
        (input.environment.z - 0.0010) / 0.0074
    );
    float3 environmentalFrequencyColor = hsvToRGB(float3(
        mix(0.56, 0.92, environmentalFrequencyCoordinate), 0.86, 0.90
    ));
    float frequencyBand = (0.5 + 0.5 * sin(
        angle * 5.0 - float(uniforms.step) * input.environment.z * 2.0 * M_PI_F
    )) * membrane;
    float programExchange = saturate(abs(input.programEcology.x) * 5000.0);
    float programRejection = saturate(input.programEcology.y);
    float programContact = saturate(programExchange + programRejection);
    float positiveProgramContribution = saturate(max(input.programEcology.w, 0.0) * 5000.0);
    float negativeProgramContribution = saturate(max(-input.programEcology.w, 0.0) * 5000.0);
    float2 tractionDirection = length(input.tissueForce.xy) > 0.000001
        ? normalize(input.tissueForce.xy) : boundaryNormal;
    float tractionTrack = (1.0 - smoothstep(0.020, 0.065, segmentDistance(
        p, tractionDirection * 0.08, tractionDirection * 0.82
    ))) * cytoplasm * tractionMagnitude;
    float coarseObservationZoom = uniforms.cameraZoom / max(uniforms.worldScale, 1.0);
    if (coarseObservationZoom < 18.0) {
        float morphologyMembrane = body * smoothstep(
            0.84 - integrity * 0.045, 0.985, radius
        );
        float morphologyCytoplasm = body * (1.0 - smoothstep(0.82, 0.97, radius));
        float morphologyExposedArc = morphologyMembrane * exposure;
        float coarseATP = saturate(input.physiology.x);
        float coarseCalcium = saturate(input.signaling.x);
        float coarseERK = saturate(input.signaling.y);
        float coarseVoltage = saturate(input.dynamics.x * 0.30 + 0.5);
        float organismDetail = smoothstep(3.0, 14.0, coarseObservationZoom);
        float radialDepth = sqrt(saturate(1.0 - radius * radius));
        float3 coarseLineage = hsvToRGB(float3(input.lineageHue, 0.82, 0.70));
        float roleTotal = max(
            input.phenotype.x + input.phenotype.y + input.phenotype.z + input.phenotype.w,
            0.001
        );
        float3 roleColor = (
            float3(0.02, 0.92, 0.66) * input.phenotype.x +
            float3(0.98, 0.18, 0.08) * input.phenotype.y +
            float3(0.08, 0.50, 1.0) * input.phenotype.z +
            float3(0.98, 0.12, 0.68) * input.phenotype.w
        ) / roleTotal;
        float3 coarseVoltageColor = mix(
            float3(0.02, 0.34, 1.0), float3(1.0, 0.08, 0.02), coarseVoltage
        );
        float3 tissueColor = mix(coarseLineage, roleColor, 0.44 + organismDetail * 0.20);
        float coarseContactStrength = length(input.interaction.xy) > 0.001
            ? saturate(input.interaction.z) : 0.0;
        float2 coarseContactDirection = length(input.interaction.xy) > 0.001
            ? normalize(input.interaction.xy) : morphologyAxis;
        float coarseJunction = (1.0 - smoothstep(0.024, 0.074, segmentDistance(
            p, coarseContactDirection * 0.66, coarseContactDirection * 1.04
        ))) * coarseContactStrength * body;
        float junctionNode = (1.0 - smoothstep(0.055, 0.125,
            length(p - coarseContactDirection * 0.78))) * coarseContactStrength * body;
        float energyCore = (1.0 - smoothstep(0.08, 0.42, radius)) *
            morphologyCytoplasm * coarseATP;
        float outerMembrane = morphologyExposedArc;
        float internalMembrane = morphologyMembrane * (1.0 - exposure);
        float nucleusRing = (1.0 - smoothstep(aa * 1.1, aa * 3.0,
            abs(length(p - nucleusPosition) - nucleusRadius * 1.18))) *
            morphologyCytoplasm;
        float coarseOrganelleNoise = visualNoise(
            p * (11.0 + input.phenotype.z * 5.0) +
            float2(input.lineageHue * 19.0, input.phenotype.w * 13.0)
        );
        float coarseOrganelles = smoothstep(0.75, 0.90, coarseOrganelleNoise) *
            morphologyCytoplasm * (1.0 - nucleus) * organismDetail;
        float coarseFiber = (1.0 - smoothstep(0.030, 0.095,
            abs(sin(dot(p, morphologyNormal) * (12.0 + input.phenotype.y * 8.0) +
                angle * 0.72)))) * morphologyCytoplasm * organismDetail;
        float3 coarseColor = float3(0.006, 0.012, 0.018) * body;
        coarseColor += tissueColor * morphologyCytoplasm *
            (0.30 + coarseATP * 0.18 + radialDepth * (0.18 + organismDetail * 0.12));
        coarseColor += float3(1.0, 0.66, 0.05) * energyCore *
            (0.05 + organismDetail * 0.10);
        coarseColor += mix(float3(0.02, 0.16, 0.24), coarseVoltageColor, 0.28) *
            morphologyMembrane * (0.055 + integrity * 0.075);
        coarseColor += float3(0.018, 0.075, 0.095) * internalMembrane *
            (0.48 + coarseContactStrength * 0.52);
        coarseColor += float3(0.04, 0.92, 0.74) * internalMembrane *
            coarseContactStrength * (0.16 + organismDetail * 0.28);
        coarseColor += mix(roleColor, float3(0.94, 0.99, 1.0),
            0.28 + autonomySignal * 0.22) * outerMembrane *
            (0.44 + autonomySignal * 0.34);
        coarseColor += mix(float3(0.98, 0.12, 0.66), coarseLineage, 0.28) * nucleus *
            (0.24 + organismDetail * 0.62);
        coarseColor += mix(float3(0.06, 0.78, 1.0), float3(1.0, 0.18, 0.64),
            coarseERK) * nucleusRing * (0.16 + organismDetail * 0.28);
        coarseColor += float3(0.04, 0.96, 0.76) * coarseJunction *
            (0.56 + organismDetail * 0.82);
        coarseColor += float3(0.86, 1.0, 0.94) * junctionNode *
            (0.24 + organismDetail * 0.46);
        coarseColor += mix(float3(0.04, 0.68, 1.0), float3(1.0, 0.64, 0.05),
            coarseATP) * coarseOrganelles * 0.36;
        coarseColor += float3(0.12, 0.82, 0.72) * coarseFiber *
            (0.045 + saturate(input.mechanics.x) * 0.095);
        coarseColor += float3(0.02, 0.88, 1.0) * coarseCalcium * morphologyMembrane *
            (0.22 + organismDetail * 0.42);
        coarseColor += float3(0.98, 0.08, 0.66) * coarseERK * nucleus *
            (0.26 + organismDetail * 0.54);
        coarseColor += float3(0.02, 1.0, 0.58) * tractionTrack *
            (0.42 + organismDetail * 0.52);
        coarseColor += float3(0.08, 1.0, 0.62) * repairFront *
            (0.42 + organismDetail * 0.52);
        coarseColor += float3(0.04, 0.58, 1.0) * repairBoundary *
            (0.46 + organismDetail * 0.48);
        coarseColor += float3(1.0, 0.055, 0.018) * woundArc *
            (0.42 + organismDetail * 0.58);
        coarseColor += float3(1.0, 0.30, 0.015) * pressureFront *
            (0.38 + organismDetail * 0.32);
        coarseColor += float3(1.0, 0.065, 0.018) * leakage *
            (0.72 + organismDetail * 0.42);
        coarseColor += float3(1.0, 0.08, 0.015) * morphologyExposedArc * contactDamage * 1.16;
        coarseColor += float3(1.0, 0.045, 0.01) * morphologyExposedArc * input.construction.x * 0.94;
        coarseColor += float3(0.08, 0.92, 0.62) * morphologyExposedArc * input.construction.y * 0.72;
        coarseColor += float3(0.04, 0.78, 1.0) * morphologyExposedArc * input.construction.z * 0.88;
        coarseColor += float3(0.12, 1.0, 0.42) * morphologyExposedArc * input.construction.w * 0.74;
        coarseColor += mix(
            float3(0.08, 0.96, 0.70), float3(0.96, 0.99, 1.0), autonomySignal
        ) * morphologyExposedArc * autonomySignal * autonomyPulse *
            (0.46 + organismDetail * 0.34);
        coarseColor += environmentalFrequencyColor * frequencyBand *
            (0.18 + frequencyMatch * 0.56);
        coarseColor += float3(1.0, 0.28, 0.02) * morphologyMembrane *
            barrierCompression * 0.82;
        coarseColor += float3(1.0, 0.76, 0.02) * morphologyCytoplasm * trophicGain * 0.82;
        coarseColor += float3(0.02, 0.96, 0.82) * morphologyMembrane *
            programExchange * 0.82;
        coarseColor += float3(1.0, 0.04, 0.12) * morphologyMembrane *
            programRejection * 0.94;
        if (uniforms.displayMode == 4) {
            float morphogenA = saturate(input.signals.x);
            float morphogenB = saturate(input.signals.y);
            float3 morphogenColor = (
                float3(0.00, 0.92, 1.0) * morphogenA +
                float3(1.0, 0.06, 0.58) * morphogenB
            ) / max(morphogenA + morphogenB, 0.001);
            coarseColor = morphogenColor * morphologyCytoplasm *
                (0.32 + abs(morphogenA - morphogenB) * 0.68);
            coarseColor += mix(
                float3(1.0, 0.70, 0.02), float3(0.08, 1.0, 0.56),
                saturate(input.development.z)
            ) * nucleus * 0.96;
            coarseColor += float3(0.90, 0.98, 1.0) * morphologyMembrane *
                saturate(input.development.w * 28.0) * 0.82;
        } else if (uniforms.displayMode == 5) {
            float mechanicsCalcium = saturate(input.signalCausality.x * 48.0);
            float calciumERK = saturate(input.signalCausality.y * 56.0);
            float erkTraction = saturate(input.signalCausality.z * 12000.0);
            coarseColor = float3(0.008, 0.014, 0.022) * body;
            coarseColor += float3(0.02, 0.88, 1.0) * mechanicsCalcium *
                morphologyMembrane * 1.24;
            coarseColor += float3(0.98, 0.08, 0.66) * calciumERK * nucleus * 1.36;
            coarseColor += float3(0.08, 1.0, 0.56) * erkTraction *
                morphologyCytoplasm * 0.82;
        }
        float coarseAlpha = body * input.visibility *
            mix(0.76, 0.96, organismDetail) * (1.0 - saturate(input.signals.w) * 0.35);
        coarseColor *= input.visibility;
        if (!all(isfinite(coarseColor)) || !isfinite(coarseAlpha)) {
            discard_fragment();
        }
        return float4(clamp(coarseColor, 0.0, 16.0), saturate(coarseAlpha));
    }
    float mitochondriaPattern = visualNoise(p * (13.0 + input.phenotype.z * 7.0) +
        float2(input.lineageHue * 17.0, input.phenotype.w * 11.0));
    float mitochondria = smoothstep(0.73, 0.92, mitochondriaPattern) * cytoplasm *
        (1.0 - nucleus);
    float cycle = saturate(input.physiology.z);
    float divisionAngle = input.dynamics.z * 2.0 * M_PI_F +
        (input.regulation.z - input.regulation.y) * 1.4;
    float2 divisionAxis = float2(cos(divisionAngle), sin(divisionAngle));
    float cleavage = (1.0 - smoothstep(0.025, 0.075, abs(dot(p, divisionAxis)))) *
        body * smoothstep(0.76, 1.0, cycle);
    float proliferativeEnvelope = (1.0 - smoothstep(0.018, 0.050,
        abs(length(p - nucleusPosition) - nucleusRadius * 1.24))) *
        cytoplasm * input.regulation.x;
    float actomyosinFiber = (1.0 - smoothstep(0.025, 0.085,
        abs(sin(dot(p, morphologyNormal) * (18.0 + input.phenotype.y * 12.0) +
            angle * 1.7)))) * cytoplasm * input.regulation.z;

    float contactStrength = length(input.interaction.xy) > 0.001 ? input.interaction.z : 0.0;
    float2 contactDirection = length(input.interaction.xy) > 0.001
        ? normalize(input.interaction.xy)
        : float2(1.0, 0.0);
    float junction = 1.0 - smoothstep(0.018, 0.055, segmentDistance(
        p, contactDirection * 0.58, contactDirection * 1.04
    ));
    junction *= body * contactStrength;

    float3 lineage = hsvToRGB(float3(input.lineageHue, 0.78, 0.62));
    float3 phenotypeColor = input.phenotype.z * float3(0.02, 0.64, 0.96) +
        input.phenotype.w * float3(0.98, 0.54, 0.035) +
        input.phenotype.y * float3(0.76, 0.08, 0.82);
    phenotypeColor /= max(input.phenotype.z + input.phenotype.w + input.phenotype.y, 0.001);
    float atp = saturate(input.physiology.x);
    float stress = saturate(input.signals.z);
    float apoptosis = saturate(input.signals.w);
    float voltagePolarity = saturate(input.dynamics.x * 0.30 + 0.5);
    float3 voltageColor = mix(float3(0.02, 0.34, 1.0), float3(1.0, 0.08, 0.02), voltagePolarity);
    float3 phaseColor = hsvToRGB(float3(fract(input.dynamics.z + 0.52), 0.82, 0.84));
    float frequencyCoordinate = saturate((input.dynamics.w - 0.0008) / 0.0082);
    float3 resonanceColor = hsvToRGB(float3(
        mix(0.56, 0.02, frequencyCoordinate), 0.88, 0.82
    ));
    float calciumSignal = saturate(input.signaling.x);
    float erkSignal = saturate(input.signaling.y);
    float signalRefractory = saturate(input.signaling.z);
    float neighborSignal = saturate(input.signaling.w);
    float mechanicsCalciumCause = saturate(input.signalCausality.x * 48.0);
    float calciumERKCause = saturate(input.signalCausality.y * 56.0);
    float erkTractionCause = saturate(input.signalCausality.z * 12000.0);
    float signalingCost = saturate(input.signalCausality.w * 18000.0);
    float morphogenA = saturate(input.signals.x);
    float morphogenB = saturate(input.signals.y);
    float fateMemory = saturate(input.development.z);
    float junctionMorphogenTransport = saturate(input.development.w * 28.0);
    float developmentalAxisTrack = (1.0 - smoothstep(0.018, 0.060, segmentDistance(
        p, -morphologyAxis * 0.68, morphologyAxis * 0.68
    ))) * cytoplasm;
    float3 color = mix(lineage, phenotypeColor, 0.42) * cytoplasm * (0.22 + atp * 0.46);
    float centralProgram = saturate(input.signals.x - input.signals.y + 0.5);
    float3 differentiatedLineage = mix(lineage,
        mix(float3(0.04, 0.56, 0.92), float3(0.92, 0.38, 0.04), 1.0 - centralProgram), 0.34);
    color = mix(color, differentiatedLineage * cytoplasm * (0.24 + atp * 0.34), 0.42);
    color = mix(color, phaseColor * cytoplasm * (0.30 + atp * 0.30), 0.24);
    color += resonanceColor * membrane * saturate(input.resonance.z * 18.0) * 0.72;
    color += environmentalFrequencyColor * frequencyBand *
        (0.12 + frequencyMatch * 0.64);
    float3 membraneColor = mix(differentiatedLineage, voltageColor, 0.58);
    color += membraneColor * membrane * (0.30 + integrity * 0.34);
    color += float3(1.0, 0.58, 0.025) * mitochondria * atp * 0.62;
    color += mix(float3(0.86, 0.06, 0.68), lineage, 0.34) * nucleus * 0.72;
    color += float3(0.96, 0.90, 0.58) * cleavage * cycle * 0.56;
    color += float3(1.0, 0.76, 0.04) * proliferativeEnvelope * (0.32 + cycle * 0.54);
    color += float3(1.0, 0.16, 0.42) * actomyosinFiber * input.mechanics.x * 0.34;
    color += mix(float3(0.08, 0.90, 1.0), float3(0.18, 1.0, 0.56), input.phenotype.x) *
        junction * 0.54;
    color += float3(0.02, 0.96, 0.82) * junction * programExchange * 1.16;
    color += float3(1.0, 0.04, 0.12) * membrane * programRejection *
        (0.48 + programContact * 0.52);
    float mechanosensoryPositive = saturate(max(input.interaction.w, 0.0) * 3200.0);
    float mechanosensoryNegative = saturate(max(-input.interaction.w, 0.0) * 3200.0);
    float membranePolarity = smoothstep(0.52, 0.94, abs(dot(surfaceDirection, morphologyAxis))) * membrane;
    color += float3(0.02, 0.88, 1.0) * membranePolarity * mechanosensoryPositive * 0.82;
    color += float3(0.34, 0.18, 1.0) * membranePolarity * mechanosensoryNegative * 0.72;
    color = mix(color, float3(0.94, 0.055, 0.018) * body, stress * 0.34);
    color *= 1.0 - apoptosis * (0.46 + 0.28 * mitochondriaPattern);
    color += float3(0.76, 0.12, 1.0) * apoptosis * membrane * 0.66;
    color += float3(0.10, 0.92, 1.0) * input.tracked * membrane * 0.24;
    color += float3(0.08, 1.0, 0.62) * repairFront * 0.92;
    color += float3(0.04, 0.58, 1.0) * repairBoundary * 0.86;
    color += float3(1.0, 0.055, 0.018) * woundArc * 0.72;
    color += float3(1.0, 0.30, 0.015) * pressureFront * 0.76;
    color += float3(1.0, 0.065, 0.018) * leakage * 1.18;
    color += float3(0.02, 1.0, 0.58) * tractionTrack * 0.82;
    color += float3(0.02, 0.94, 0.78) * exposedArc * (0.12 + exposure * 0.22);
    color += float3(1.0, 0.26, 0.015) * membrane * barrierCompression *
        (0.42 + input.mechanics.y * 0.48);
    color += float3(1.0, 0.045, 0.01) * exposedArc * input.construction.x * 0.90;
    color += float3(0.08, 0.92, 0.62) * exposedArc * input.construction.y * 0.72;
    color += float3(0.04, 0.78, 1.0) * exposedArc * input.construction.z * 0.86;
    color += float3(0.12, 1.0, 0.42) * exposedArc * input.construction.w * 0.70;
    color += float3(1.0, 0.055, 0.012) * exposedArc * contactDamage * (0.72 + trophicLoss);
    color += float3(1.0, 0.74, 0.02) * cytoplasm * trophicGain * 0.76;
    float contractionRing = (1.0 - smoothstep(0.020, 0.060,
        abs(radius - (0.50 + input.mechanics.x * 0.17)))) * cytoplasm;
    color += phaseColor * contractionRing * input.mechanics.x * (0.26 + input.mechanics.w * 0.40);
    float strainAxis = 1.0 - smoothstep(0.020, 0.070,
        abs(dot(p, float2(cos(oscillatorAngle), sin(oscillatorAngle)))));
    color += float3(0.04, 0.88, 1.0) * strainAxis * cytoplasm * input.mechanics.y * 0.72;
    float netPower = input.energetics.x - input.energetics.y - input.energetics.z - input.energetics.w;
    color += mix(float3(0.82, 0.06, 0.03), float3(1.0, 0.72, 0.02), step(0.0, netPower)) *
        mitochondria * saturate(abs(netPower) * 5200.0) * 0.48;
    color += float3(1.0, 0.80, 0.05) * mitochondria * positiveProgramContribution * 0.54;
    color += float3(0.24, 0.14, 1.0) * mitochondria * negativeProgramContribution * 0.52;
    float repairPatch = smoothstep(0.62, 0.86,
        visualNoise(p * 19.0 + float2(input.lineageHue * 23.0, input.dynamics.z * 17.0))) *
        membrane * input.regulation.w * (1.0 - integrity);
    color += float3(0.12, 0.48, 1.0) * repairPatch * 1.15;
    float calciumFrontPhase = fract(
        input.dynamics.z + neighborSignal * 0.18 + signalRefractory * 0.12
    );
    float calciumFrontRadius = 0.18 + calciumFrontPhase * 0.62;
    float calciumFront = (1.0 - smoothstep(0.022, 0.070,
        abs(length(p - nucleusPosition) - calciumFrontRadius))) * cytoplasm;
    float erkDomain = smoothstep(0.08, 0.44, erkSignal) *
        (1.0 - smoothstep(nucleusRadius * 0.88, nucleusRadius * 1.82,
            length(p - nucleusPosition))) * body;
    float junctionTransmission = junction * neighborSignal;
    float tractionPath = (1.0 - smoothstep(0.020, 0.068,
        abs(dot(p, morphologyNormal)))) * cytoplasm * erkTractionCause;
    color += float3(0.02, 0.88, 1.0) * calciumFront * calciumSignal * 0.92;
    color += float3(0.98, 0.08, 0.66) * erkDomain * 0.68;
    color += float3(0.18, 0.98, 0.62) * junctionTransmission *
        (0.30 + calciumSignal * 0.54);
    color += float3(0.08, 1.0, 0.56) * tractionPath * 0.62;

    const float2 regulatoryPositions[4] = {
        float2(-0.13, 0.11), float2(0.13, 0.11),
        float2(-0.13, -0.11), float2(0.13, -0.11)
    };
    const float3 regulatoryColors[4] = {
        float3(1.0, 0.80, 0.04), float3(0.04, 0.94, 0.64),
        float3(1.0, 0.10, 0.42), float3(0.12, 0.48, 1.0)
    };
    float3 regulatoryEmission = float3(0.0);
    for (uint node = 0u; node < 4u; ++node) {
        float nodeMask = 1.0 - smoothstep(
            0.022 + input.regulation[node] * 0.018,
            0.035 + input.regulation[node] * 0.018,
            length(p - nucleusPosition - regulatoryPositions[node])
        );
        regulatoryEmission += regulatoryColors[node] * nodeMask * input.regulation[node];
    }
    color += regulatoryEmission * nucleus * 1.25;
    if (uniforms.displayMode == 4) {
        float3 morphogenColor = (
            float3(0.00, 0.92, 1.0) * morphogenA +
            float3(1.0, 0.06, 0.58) * morphogenB
        ) / max(morphogenA + morphogenB, 0.001);
        float3 fateColor = mix(
            float3(1.0, 0.70, 0.02), float3(0.08, 1.0, 0.56), fateMemory
        );
        float differentiation = saturate(abs(morphogenA - morphogenB) * 1.8);
        color = float3(0.006, 0.012, 0.020) * body +
            morphogenColor * cytoplasm * (0.34 + differentiation * 0.66) +
            fateColor * nucleus * (0.56 + abs(fateMemory - 0.5) * 0.82) +
            float3(0.90, 0.98, 1.0) * developmentalAxisTrack *
                (0.20 + differentiation * 0.68) +
            mix(float3(0.08, 0.48, 1.0), float3(0.14, 1.0, 0.70),
                junctionMorphogenTransport) * membrane *
                (0.22 + junctionMorphogenTransport * 0.86) +
            regulatoryEmission * nucleus * 0.82;
    } else if (uniforms.displayMode == 5) {
        float energySupport = cellularEnergySupport(atp, input.energetics);
        float unconstrainedCycleDrive = cellCycleDrive(
            atp, input.physiology.y, input.energetics, input.regulation.x,
            stress, input.tissueGeometry.z
        );
        float cycleDecay = cellCycleQuiescenceDecay(
            energySupport, input.interaction.z, stress
        );
        float contactEffect = saturate((input.interaction.z * unconstrainedCycleDrive +
            cycleDecay) * 3000.0);
        float repairEffect = saturate(input.regulation.w * atp * 0.00022 * 10000.0);
        float proliferativeEffect = saturate(unconstrainedCycleDrive * 2400.0);
        float3 mechanosensoryColor = float3(0.02, 0.88, 1.0) * mechanosensoryPositive +
            float3(0.34, 0.18, 1.0) * mechanosensoryNegative;
        float mechanosensoryPath = (1.0 - smoothstep(0.024, 0.080,
            abs(dot(p, morphologyNormal)))) * cytoplasm;
        color = float3(0.012, 0.020, 0.030) * body +
            float3(0.028, 0.055, 0.075) * cytoplasm * (0.35 + atp * 0.42);
        color += mechanosensoryColor * membranePolarity * 1.70;
        color += mechanosensoryColor * mechanosensoryPath * 0.34;
        color += float3(1.0, 0.76, 0.04) * proliferativeEnvelope *
            proliferativeEffect * 2.05;
        color += float3(1.0, 0.60, 0.02) * nucleus * proliferativeEffect * 0.42;
        color += float3(0.02, 0.94, 0.62) * junction * contactEffect * 2.20;
        color += float3(0.12, 0.48, 1.0) * membrane * repairEffect * (0.62 + repairPatch * 1.3);
        color += float3(0.02, 0.88, 1.0) * calciumFront * mechanicsCalciumCause * 2.10;
        color += float3(0.98, 0.08, 0.66) * erkDomain * calciumERKCause * 1.90;
        color += float3(0.08, 1.0, 0.56) * tractionPath * 1.80;
        color += float3(1.0, 0.42, 0.02) * mitochondria * signalingCost * 1.35;
        color += float3(0.18, 0.98, 0.62) * junctionTransmission * 0.72;
        color += float3(0.02, 0.96, 0.82) * junction * programExchange * 1.65;
        color += float3(1.0, 0.04, 0.12) * membrane * programRejection * 1.55;
        color += float3(0.92, 0.97, 1.0) * nucleus * 0.20;
    }

    float observationZoom = uniforms.cameraZoom / max(uniforms.worldScale, 1.0);
    float cellDetail = smoothstep(14.0, 30.0, observationZoom);
    color = mix(lineage * body * (0.32 + atp * 0.44), color, cellDetail);
    color += mix(
        float3(0.06, 0.88, 0.62), float3(0.92, 0.98, 1.0), autonomySignal
    ) * exposedArc * autonomySignal * autonomyPulse * mix(0.28, 0.48, cellDetail);
    float alpha = body * input.visibility * mix(0.62, 0.94, cellDetail) * (1.0 - apoptosis * 0.35);
    color *= input.visibility;
    if (!all(isfinite(color)) || !isfinite(alpha)) { discard_fragment(); }
    return float4(clamp(color, 0.0, 16.0), saturate(alpha));
}

template <ushort renderScaleIndex>
float4 quantumSurfaceForScale(
    RasterData input,
    texture2d<float, access::sample> quantum,
    texture2d_array<float, access::sample> state,
    texture2d_array<float, access::sample> ecology,
    texture2d_array<float, access::sample> environment,
    texture2d_array<float, access::sample> mechanicalField,
    texture2d_array<float, access::sample> genomeA,
    texture2d_array<float, access::sample> genomeC,
    constant SimulationUniforms& uniforms
) {
    constexpr sampler quantumSampler(coord::normalized, address::repeat, filter::linear);
    constexpr sampler quantumCellSampler(coord::normalized, address::repeat, filter::nearest);
    constexpr sampler fieldSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float safeAspect = max(uniforms.viewportAspect, 0.001);
    float2 viewScale = safeAspect >= 1.0 ? float2(1.0, 1.0 / safeAspect) : float2(safeAspect, 1.0);
    float2 rawUV = uniforms.cameraCenter + (input.uv - 0.5) * viewScale /
        max(uniforms.cameraZoom, 0.000000001);
    float2 uv = clamp(rawUV, 0.0, 1.0);
    float observationZoom = uniforms.cameraZoom / max(uniforms.worldScale, 1.0);

    float2 quantumTexel = 1.0 / float(quantumGridSize);
    bool resolvesLatticeCells = renderScaleIndex == 5u;
    float4 wave = resolvesLatticeCells
        ? quantum.sample(quantumCellSampler, uv)
        : quantum.sample(quantumSampler, uv);
    float4 waveRight = resolvesLatticeCells
        ? quantum.sample(quantumCellSampler, uv + float2(quantumTexel.x, 0.0))
        : quantum.sample(quantumSampler, uv + float2(quantumTexel.x, 0.0));
    float4 waveUp = resolvesLatticeCells
        ? quantum.sample(quantumCellSampler, uv + float2(0.0, quantumTexel.y))
        : quantum.sample(quantumSampler, uv + float2(0.0, quantumTexel.y));
    float probabilityA = dot(wave.xy, wave.xy);
    float probabilityB = dot(wave.zw, wave.zw);
    float probability = probabilityA + probabilityB;
    float componentCoherence = abs(dot(wave.xy, wave.zw)) /
        max(sqrt(probabilityA * probabilityB), 0.0000000001);
    float2 current = float2(
        complexCurrent(wave.xy, waveRight.xy) + complexCurrent(wave.zw, waveRight.zw),
        complexCurrent(wave.xy, waveUp.xy) + complexCurrent(wave.zw, waveUp.zw)
    );
    float currentMagnitude = length(current);
    float currentStrength = saturate(currentMagnitude * 950000.0);
    float latticeReveal = renderScaleIndex == 5u
        ? smoothstep(420.0, 900.0, observationZoom) : 0.0;
    if (latticeReveal >= 0.999) {
        float3 spinorTile = spinorCellVisualization(uv, wave, currentStrength);
        return finiteHDRColor(spinorTile, 1.16);
    }

    float density = 1.0 - exp(-probability * 285000.0);
    float quantumOrder = density * (0.24 + 0.76 * saturate(componentCoherence));
    float4 waveDiagonal = quantum.sample(quantumSampler, uv + quantumTexel);
    float2 combinedAmplitude = wave.xy + wave.zw;
    float phase = fract(atan2(combinedAmplitude.y, combinedAmplitude.x) / (2.0 * M_PI_F) + 1.0);
    float phaseRight = spinorPhase(waveRight);
    float phaseUp = spinorPhase(waveUp);
    float phaseDiagonal = spinorPhase(waveDiagonal);
    float phaseWinding = abs(
        wrappedPhaseDelta(phase, phaseRight) +
        wrappedPhaseDelta(phaseRight, phaseDiagonal) +
        wrappedPhaseDelta(phaseDiagonal, phaseUp) +
        wrappedPhaseDelta(phaseUp, phase)
    );
    float polarization = (probabilityA - probabilityB) / max(probability, 0.0000000001);
    float2 currentDirection = current / max(currentMagnitude, 0.0000000001);
    float phaseContour = 0.62 + 0.38 * cos(phase * 28.0 * M_PI_F);
    float flowCoordinate = fract(dot(uv * float(quantumGridSize), currentDirection) * 0.22 -
        float(uniforms.step) * 0.012);
    float currentPulse = 1.0 - smoothstep(0.035, 0.13, abs(flowCoordinate - 0.5));
    float3 spinColor = mix(
        float3(1.0, 0.22, 0.025),
        float3(0.02, 0.82, 1.0),
        polarization * 0.5 + 0.5
    );
    float3 waveColor = mix(quantumPhaseColor(phase), spinColor, 0.38) *
        density * (0.54 + phaseContour * 0.46);
    waveColor += float3(0.82, 0.97, 1.0) * currentPulse * currentStrength * density * 0.68;
    float node = 1.0 - smoothstep(0.018, 0.15, density);
    waveColor *= 1.0 - node * 0.84;
    float logDensity = log2(1.0 + probability * 1200000.0);
    float densityIsoline = 1.0 - smoothstep(0.025, 0.095,
        abs(fract(logDensity * 2.4) - 0.5));
    float vortexCore = smoothstep(0.55, 0.92, phaseWinding) *
        (1.0 - smoothstep(0.025, 0.28, density));
    waveColor += float3(0.38, 0.92, 1.0) * densityIsoline * density * 0.065;
    waveColor += float3(0.72, 0.88, 1.0) * vortexCore * 1.42;
    // The continuous wave view is radiometric, not a filled contour map. Keep
    // low-amplitude regions dark so probability, current, and phase remain separable.
    waveColor *= mix(0.15, 0.45, smoothstep(320.0, 420.0, observationZoom));

    // Wave and spinor views do not pay for molecular-field sampling or glyph synthesis.
    if (renderScaleIndex >= 4u) {
        float3 spinorTile = spinorCellVisualization(uv, wave, currentStrength);
        float3 quantumOnlyColor = mix(waveColor, spinorTile, latticeReveal);
        if (observationZoom < 512.0) {
            float4 feedbackState = state.sample(fieldSampler, uv, 0);
            float4 feedbackEcology = ecology.sample(fieldSampler, uv, 0);
            float4 feedbackGenome = genomeA.sample(fieldSampler, uv, 0);
            float matterPotential = 0.012 * (
                feedbackState.x + feedbackEcology.x * 0.8 + feedbackState.y * 2.2 +
                feedbackState.w * 3.0 + feedbackEcology.z * 1.4
            );
            float potentialRadiance = saturate(matterPotential * 46.0);
            float potentialContour = 1.0 - smoothstep(0.035, 0.11,
                abs(fract(matterPotential * 420.0) - 0.5));
            float coinAngle = 0.18 + 0.16 * saturate(feedbackState.w * 4.0) +
                0.06 * saturate(feedbackGenome.y);
            float coinPerturbation = saturate((coinAngle - 0.18) / 0.22);
            float coinContour = 1.0 - smoothstep(0.035, 0.12,
                abs(fract(coinAngle * 23.0) - 0.5));
            float feedbackWindow = smoothstep(176.0, 210.0, observationZoom) *
                (1.0 - smoothstep(420.0, 512.0, observationZoom));
            float3 feedbackColor = mix(
                float3(0.08, 1.0, 0.62), float3(1.0, 0.42, 0.025), coinPerturbation
            );
            quantumOnlyColor *= 1.0 - potentialRadiance * feedbackWindow * 0.12;
            quantumOnlyColor += feedbackColor * potentialContour * potentialRadiance *
                feedbackWindow * 0.42;
            quantumOnlyColor += float3(1.0, 0.42, 0.025) * coinContour *
                coinPerturbation * feedbackWindow * density * 0.24;
        }
        return finiteHDRColor(quantumOnlyColor, 1.16);
    }

    float4 localState = state.sample(fieldSampler, uv, 0);
    float4 localEcology = ecology.sample(fieldSampler, uv, 0);
    float4 localGeology = environment.sample(fieldSampler, uv, 0);
    float4 localMechanical = mechanicalField.sample(fieldSampler, uv, 0);
    float4 localGeneA = genomeA.sample(fieldSampler, uv, 0);
    float4 localGeneC = genomeC.sample(fieldSampler, uv, 0);
    float2 reactionTexel = 1.0 / float2(uniforms.width, uniforms.height);
    float4 stateRight = state.sample(fieldSampler, uv + float2(reactionTexel.x, 0.0), 0);
    float4 stateUp = state.sample(fieldSampler, uv + float2(0.0, reactionTexel.y), 0);
    float4 ecologyRight = ecology.sample(fieldSampler, uv + float2(reactionTexel.x, 0.0), 0);
    float4 ecologyUp = ecology.sample(fieldSampler, uv + float2(0.0, reactionTexel.y), 0);
    float2 reactionGradient = float2(
        (stateRight.x - localState.x) + (ecologyRight.x - localEcology.x),
        (stateUp.x - localState.x) + (ecologyUp.x - localEcology.x)
    );
    float obstacle = smoothstep(0.48, 0.84, localGeology.w);
    float permeability = 1.0 - obstacle * 0.88;
    float chemicalAffinity = sqrt(saturate(localState.x) * saturate(localEcology.x)) *
        permeability * (1.0 - saturate(localEcology.z));
    float mechanicalActivity = saturate(
        length(localMechanical.xy) * 18.0 + length(localMechanical.zw) * 75.0
    );
    float catalystProduction = uniforms.dt * chemicalAffinity *
        (quantumOrder * 0.0090 + mechanicalActivity * 0.00032);
    float energyProduction = uniforms.dt * max(localEcology.w, 0.0) * permeability *
        (quantumOrder * (0.015 + 0.035 * saturate(localState.x + localEcology.x)) +
            mechanicalActivity * 0.00018);
    float prebioticOrder = smoothstep(0.018, 0.065, max(localEcology.w, 0.0)) *
        smoothstep(0.002, 0.015, max(localState.z, 0.0)) * quantumOrder;
    float membraneAssembly = max(
        uniforms.dt * 0.22 * (prebioticOrder * 0.035 - max(localState.w, 0.0)),
        0.0
    );
    float mineralization = min(
        max(localEcology.y, 0.0),
        uniforms.dt * max(localEcology.y, 0.0) *
            (0.00035 + max(localEcology.w, 0.0) * 0.0032) *
            permeability * (1.0 - saturate(localEcology.z) * 0.72)
    );
    float2 molecularDirection = reactionGradient + currentDirection *
        (0.0002 + currentStrength * 0.0012);
    float3 molecularColor = molecularReactionVisualization(
        uv,
        localState,
        localEcology,
        localGeology,
        localGeneA,
        localGeneC,
        quantumOrder,
        chemicalAffinity,
        catalystProduction,
        energyProduction,
        membraneAssembly,
        mineralization,
        phase,
        molecularDirection,
        float(uniforms.width),
        uniforms.step,
        uniforms.displayMode
    );
    float waveReveal = smoothstep(136.0, 176.0, observationZoom);
    float3 color = mix(molecularColor, waveColor, waveReveal);

    float3 spinorTile = spinorCellVisualization(uv, wave, currentStrength);
    color = mix(color, spinorTile, latticeReveal);

    return finiteHDRColor(color, 1.16);
}

#define NUMI_QUANTUM_SURFACE(NAME, SCALE) \
fragment float4 NAME( \
    RasterData input [[stage_in]], \
    texture2d<float, access::sample> quantum [[texture(0)]], \
    texture2d_array<float, access::sample> state [[texture(1)]], \
    texture2d_array<float, access::sample> ecology [[texture(2)]], \
    texture2d_array<float, access::sample> environment [[texture(3)]], \
    texture2d_array<float, access::sample> mechanicalField [[texture(4)]], \
    texture2d_array<float, access::sample> genomeA [[texture(5)]], \
    texture2d_array<float, access::sample> genomeC [[texture(6)]], \
    constant SimulationUniforms& uniforms [[buffer(0)]] \
) { \
    return quantumSurfaceForScale<SCALE>( \
        input, quantum, state, ecology, environment, mechanicalField, \
        genomeA, genomeC, uniforms \
    ); \
}

NUMI_QUANTUM_SURFACE(molecularSurfaceFragment, 3u)
NUMI_QUANTUM_SURFACE(waveSurfaceFragment, 4u)
NUMI_QUANTUM_SURFACE(spinorSurfaceFragment, 5u)
#undef NUMI_QUANTUM_SURFACE

fragment float4 spinorDisplayFragment(
    RasterData input [[stage_in]],
    texture2d<float, access::sample> quantum [[texture(0)]],
    texture2d_array<float, access::sample> state [[texture(1)]],
    texture2d_array<float, access::sample> ecology [[texture(2)]],
    texture2d_array<float, access::sample> environment [[texture(3)]],
    texture2d_array<float, access::sample> mechanicalField [[texture(4)]],
    texture2d_array<float, access::sample> genomeA [[texture(5)]],
    texture2d_array<float, access::sample> genomeC [[texture(6)]],
    constant SimulationUniforms& uniforms [[buffer(0)]],
    constant PostProcessUniforms& postUniforms [[buffer(1)]]
) {
    float3 linearScene = quantumSurfaceForScale<5u>(
        input, quantum, state, ecology, environment, mechanicalField,
        genomeA, genomeC, uniforms
    ).rgb;
    return float4(mapToDisplay(
        linearScene, float3(0.0), postUniforms, uint2(input.position.xy)
    ), 1.0);
}

fragment float4 worldSurfaceFragment(
    RasterData input [[stage_in]],
    texture2d_array<float, access::sample> state [[texture(0)]],
    texture2d_array<float, access::sample> ecology [[texture(1)]],
    texture2d_array<float, access::sample> environment [[texture(2)]],
    texture2d_array<float, access::sample> events [[texture(3)]],
    texture2d_array<float, access::sample> mechanicalField [[texture(4)]],
    constant SimulationUniforms& uniforms [[buffer(0)]]
) {
    constexpr sampler fieldSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float safeAspect = max(uniforms.viewportAspect, 0.001);
    float2 viewScale = safeAspect >= 1.0 ? float2(1.0, 1.0 / safeAspect) : float2(safeAspect, 1.0);
    float2 rawUV = uniforms.cameraCenter + (input.uv - 0.5) * viewScale /
        max(uniforms.cameraZoom, 0.000000001);
    float2 uv = clamp(rawUV, 0.0, 1.0);
    float2 texel = 1.0 / float2(uniforms.width, uniforms.height);

    float4 cell = state.sample(fieldSampler, uv, 0);
    float4 chemistry = ecology.sample(fieldSampler, uv, 0);
    float4 geology = environment.sample(fieldSampler, uv, 0);
    float4 localMechanical = mechanicalField.sample(fieldSampler, uv, 0);
    float terrain = visualNoise(uv * 43.0);
    float fineTerrain = visualNoise(uv * 97.0 + float2(17.0, 31.0));

    float4 geologyRight = environment.sample(fieldSampler, uv + float2(texel.x, 0.0), 0);
    float4 geologyUp = environment.sample(fieldSampler, uv + float2(0.0, texel.y), 0);
    float2 rockSlope = float2(geologyRight.w - geology.w, geologyUp.w - geology.w);
    float rockGradient = length(rockSlope);
    float rock = smoothstep(0.30, 0.68, geology.w + (terrain - 0.5) * 0.52);
    float rockRim = smoothstep(0.018, 0.12, rockGradient) * (1.0 - rock * 0.35);

    float resourceA = saturate(cell.x * 0.82);
    float resourceB = saturate(chemistry.x * 0.86);
    float detritus = saturate(chemistry.y * 1.18);
    float toxin = saturate(max(chemistry.z, geology.z) * 1.28);
    float4 stateRight = state.sample(fieldSampler, uv + float2(texel.x, 0.0), 0);
    float4 stateUp = state.sample(fieldSampler, uv + float2(0.0, texel.y), 0);
    float4 ecologyRight = ecology.sample(fieldSampler, uv + float2(texel.x, 0.0), 0);
    float4 ecologyUp = ecology.sample(fieldSampler, uv + float2(0.0, texel.y), 0);
    float2 resourceGradientA = float2(stateRight.x - cell.x, stateUp.x - cell.x);
    float2 resourceGradientB = float2(ecologyRight.x - chemistry.x, ecologyUp.x - chemistry.x);
    float resourceFlux = saturate((length(resourceGradientA) + length(resourceGradientB)) * 5.5);
    float2 totalResourceGradient = resourceGradientA + resourceGradientB;
    float2 resourceDirection = length(totalResourceGradient) > 0.000001
        ? -normalize(totalResourceGradient) : float2(1.0, 0.0);
    float resourceTransportCoordinate = fract(
        dot(uv * float2(uniforms.width, uniforms.height), resourceDirection) * 0.095 -
            float(uniforms.step) * 0.007
    );
    float resourceTransportPulse = 1.0 - smoothstep(0.025, 0.090,
        abs(resourceTransportCoordinate - 0.5));
    float resourcePotential = cell.x * 0.62 + chemistry.x * 0.52 + chemistry.y * 0.22;
    float resourceIsoline = 1.0 - smoothstep(0.025, 0.095,
        abs(fract(resourcePotential * 13.0 + terrain * 0.12) - 0.5));
    float ecotone = smoothstep(0.025, 0.22, abs(resourceA - resourceB)) *
        smoothstep(0.02, 0.24, min(resourceA, resourceB));
    float nutrientBed = smoothstep(0.16, 0.66, geology.x + (terrain - 0.5) * 0.30);
    float mineralBed = smoothstep(0.16, 0.66, geology.y + (fineTerrain - 0.5) * 0.34);
    float2 substrateDrive = substrateForcing(uv, geology, uniforms.step);
    float localEnvironmentalFrequency = environmentalFrequency(uv, geology);
    float geologicalMechanicalDrive = environmentalMechanicalAmplitude(geology);
    float grain = visualNoise(uv * float2(uniforms.width, uniforms.height) * 0.84 + float2(11.0, 3.0));
    float nutrient = nutrientBed * mix(0.12, 1.0, smoothstep(0.58, 0.88, grain)) *
        mix(0.32, 1.0, substrateDrive.x) * smoothstep(0.004, 0.18, resourceA);
    float mineral = mineralBed * mix(0.10, 1.0, smoothstep(0.64, 0.91, 1.0 - grain)) *
        mix(0.32, 1.0, substrateDrive.y) * smoothstep(0.004, 0.18, resourceB);
    float hazardPulse = 0.68 + 0.32 * sin(float(uniforms.step) * 0.016 +
        (uv.x * 13.0 - uv.y * 9.0) * M_PI_F);
    float fissure = 1.0 - smoothstep(0.025, 0.12,
        abs(sin((uv.x * 17.0 + uv.y * 23.0 + terrain * 0.8) * M_PI_F)));
    float hazardPresence = smoothstep(0.10, 0.58, toxin);
    float hazard = hazardPresence * (0.08 + fissure * 0.52) * hazardPulse;
    float obstacle = smoothstep(0.48, 0.84, geology.w);
    float permeability = 1.0 - obstacle * 0.88;
    float mineralization = min(
        max(chemistry.y, 0.0),
        uniforms.dt * max(chemistry.y, 0.0) *
            (0.00035 + max(chemistry.w, 0.0) * 0.0032) * permeability *
            (1.0 - saturate(chemistry.z) * 0.72)
    );
    float recycleRadiance = saturate(log2(1.0 + mineralization * 8.0e6) * 0.18);
    float recycleCoordinate = fract(
        uv.x * 17.0 - uv.y * 11.0 + terrain * 0.38 + float(uniforms.step) * 0.006
    );
    float recyclePulse = 1.0 - smoothstep(0.022, 0.082,
        abs(recycleCoordinate - 0.5));
    float vibration = saturate(length(localMechanical.xy) * 16.0 + length(localMechanical.zw) * 72.0);
    float frequencyCoordinate = saturate((localEnvironmentalFrequency - 0.0010) / 0.0074);
    float3 frequencyColor = hsvToRGB(float3(mix(0.56, 0.94, frequencyCoordinate), 0.82, 0.84));
    float frequencyCarrier = 0.5 + 0.5 * sin(
        (uv.x * 19.0 + uv.y * 13.0 + environmentalPhase(uv, geology)) * 2.0 * M_PI_F -
            float(uniforms.step) * localEnvironmentalFrequency * 2.0 * M_PI_F
    );
    float frequencyBand = smoothstep(0.76, 0.98, frequencyCarrier) *
        saturate(geologicalMechanicalDrive * 9.0 + vibration * 0.34);

    float3 color;
    if (uniforms.displayMode == 1) {
        color = float3(0.002, 0.006, 0.012);
        color += float3(0.00, 0.42, 0.90) * resourceA;
        color += float3(0.66, 0.04, 0.78) * resourceB;
        color += float3(1.00, 0.45, 0.015) * detritus;
        color += float3(1.00, 0.04, 0.015) * toxin * 0.72;
        color += frequencyColor * frequencyBand * 0.34;
    } else if (uniforms.displayMode == 2) {
        float fieldEdge = smoothstep(0.015, 0.16, abs(resourceA - resourceB));
        float substrateTotal = saturate(sqrt(resourceA + resourceB) * 0.72);
        float substrateBalance = resourceB / max(resourceA + resourceB, 0.0001);
        float3 substrateColor = mix(
            float3(0.02, 0.48, 0.76), float3(0.42, 0.08, 0.58),
            substrateBalance
        );
        color = float3(0.0025, 0.005, 0.011) * (0.84 + terrain * 0.28);
        color += substrateColor * substrateTotal * 0.028;
        color += float3(0.04, 0.13, 0.17) * fieldEdge * 0.42;
        color += frequencyColor * frequencyBand * 0.026;
        color += mix(float3(0.02, 0.44, 0.92), float3(0.06, 0.92, 0.54),
            saturate(resourceA / max(resourceA + resourceB, 0.001))) *
            resourceIsoline * resourceFlux * 0.045;
        color += mix(float3(0.02, 0.50, 1.0), float3(0.94, 0.48, 0.06),
            frequencyCoordinate) * vibration * 0.055;
    } else if (uniforms.displayMode == 3) {
        color = float3(0.002, 0.006, 0.010);
        color += float3(0.00, 0.76, 0.42) * resourceA * 0.46;
        color += float3(1.00, 0.50, 0.02) * resourceB * 0.48;
        color += float3(0.78, 0.08, 0.95) * detritus * 0.42;
        color += float3(1.00, 0.025, 0.012) * hazard * 0.72;
        color += frequencyColor * frequencyBand * 0.30;
    } else {
        color = float3(0.0025, 0.006, 0.012) * (0.72 + terrain * 0.40);
        color += float3(0.00, 0.045, 0.055) * resourceA;
        color += float3(0.045, 0.007, 0.064) * resourceB;
        color *= 1.0 - rock * 0.84;
        float3 rockNormal = normalize(float3(-rockSlope * 15.0, 0.42));
        float rockLight = 0.32 + 0.68 * saturate(dot(rockNormal, normalize(float3(-0.44, 0.56, 0.70))));
        float rockStrata = 0.72 + 0.28 * sin((geology.w * 11.0 + fineTerrain * 2.0) * M_PI_F);
        color += float3(0.014, 0.019, 0.023) * rock * rockLight * rockStrata;
        color += float3(0.10, 0.14, 0.15) * rockRim * (0.08 + rockLight * 0.12);
        color += float3(0.02, 0.82, 0.48) * nutrient * (1.0 - rock) * 0.12;
        color += float3(0.96, 0.52, 0.025) * mineral * (1.0 - rock) * 0.11;
        color += mix(float3(0.02, 0.42, 0.92), float3(0.86, 0.06, 0.66),
            saturate(0.5 + atan2(localMechanical.w, localMechanical.z) / (2.0 * M_PI_F))) *
            vibration * (1.0 - rock) * 0.050;
        color += float3(1.0, 0.035, 0.012) * hazard * 0.18;
        color += mix(float3(0.02, 0.44, 0.78), float3(0.06, 0.92, 0.54),
            saturate(resourceA / max(resourceA + resourceB, 0.001))) *
            resourceIsoline * resourceFlux * (1.0 - rock) * 0.085;
        color += float3(0.72, 0.12, 0.94) * ecotone * (1.0 - rock) * 0.10;
        color += frequencyColor * frequencyBand * (1.0 - rock * 0.72) * 0.045;
    }

    if (uniforms.displayMode != 2) {
        float3 transportColor = mix(
            float3(0.02, 0.52, 1.0), float3(0.04, 0.98, 0.56),
            saturate(resourceA / max(resourceA + resourceB, 0.001))
        );
        color += transportColor * resourceTransportPulse * resourceFlux *
            (1.0 - rock) * 0.080;
        color += float3(1.0, 0.30, 0.025) * recyclePulse * recycleRadiance *
            (1.0 - rock) * 0.14;
    }

    return finiteHDRColor(color, 1.08);
}

fragment float4 cellularSurfaceFragment(
    RasterData input [[stage_in]],
    texture2d_array<float, access::sample> state [[texture(0)]],
    texture2d_array<float, access::sample> ecology [[texture(1)]],
    texture2d_array<float, access::sample> environment [[texture(2)]],
    texture2d_array<float, access::sample> events [[texture(3)]],
    texture2d_array<float, access::sample> mechanicalField [[texture(4)]],
    constant SimulationUniforms& uniforms [[buffer(0)]]
) {
    constexpr sampler fieldSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float safeAspect = max(uniforms.viewportAspect, 0.001);
    float2 viewScale = safeAspect >= 1.0 ? float2(1.0, 1.0 / safeAspect) : float2(safeAspect, 1.0);
    float2 uv = clamp(
        uniforms.cameraCenter + (input.uv - 0.5) * viewScale /
            max(uniforms.cameraZoom, 0.000000001),
        0.0, 1.0
    );
    float2 texel = 1.0 / float2(uniforms.width, uniforms.height);
    float4 localState = state.sample(fieldSampler, uv, 0);
    float4 localEcology = ecology.sample(fieldSampler, uv, 0);
    float4 localEnvironment = environment.sample(fieldSampler, uv, 0);
    float4 localMechanical = mechanicalField.sample(fieldSampler, uv, 0);
    float4 mechanicalRight = mechanicalField.sample(fieldSampler, uv + float2(texel.x, 0.0), 0);
    float4 mechanicalUp = mechanicalField.sample(fieldSampler, uv + float2(0.0, texel.y), 0);
    float2 displacementGradient = float2(
        length(mechanicalRight.xy - localMechanical.xy),
        length(mechanicalUp.xy - localMechanical.xy)
    );
    float mechanicalStrain = saturate(length(displacementGradient) * 28.0);
    float waveSpeed = saturate(length(localMechanical.zw) * 92.0);
    float waveAngle = atan2(localMechanical.w, localMechanical.z);
    float2 waveDirection = float2(cos(waveAngle), sin(waveAngle));
    float waveCoordinate = dot(uv * float2(uniforms.width, uniforms.height), waveDirection) * 0.18 -
        float(uniforms.step) * 0.020;
    float waveFront = 1.0 - smoothstep(0.035, 0.14, abs(fract(waveCoordinate) - 0.5));
    float biomassRight = state.sample(fieldSampler, uv + float2(texel.x, 0.0), 0).y;
    float biomassUp = state.sample(fieldSampler, uv + float2(0.0, texel.y), 0).y;
    float2 biomassGradient = float2(biomassRight - localState.y, biomassUp - localState.y);
    float matrixStrain = saturate(length(biomassGradient) * 9.0);
    float potential = saturate((localState.x + localEcology.x * 0.8 + localState.y * 2.2 +
        localState.w * 3.0 + localEcology.z * 1.4) * 0.42);
    float potentialContour = 1.0 - smoothstep(0.035, 0.12,
        abs(fract(potential * 17.0) - 0.5));

    float3 color = float3(0.003, 0.008, 0.013);
    color += float3(0.012, 0.11, 0.16) * saturate(localState.x * 0.72);
    color += float3(0.15, 0.055, 0.015) * saturate(localEcology.x * 0.66);
    color += float3(0.018, 0.14, 0.10) * saturate(localState.w * 1.8);
    color += float3(0.12, 0.18, 0.20) * matrixStrain * 0.18;
    color += mix(float3(0.025, 0.46, 1.0), float3(1.0, 0.46, 0.06),
        saturate(waveAngle / (2.0 * M_PI_F) + 0.5)) * waveFront * waveSpeed * 0.52;
    color += float3(0.06, 0.88, 0.76) * mechanicalStrain * (0.18 + waveFront * 0.34);
    color += mix(float3(0.01, 0.28, 0.48), float3(0.02, 0.58, 0.32), potential) *
        potentialContour * 0.050;
    color += float3(0.84, 0.11, 0.025) * saturate(localEcology.z + localEnvironment.z) * 0.22;
    if (uniforms.displayMode == 5) {
        float mechanicsGain = saturate(uniforms.intervention.x);
        float storedEnergy = saturate(localState.z * 12.0);
        float contactSubstrate = saturate(localState.y * 2.6) * matrixStrain;
        color = float3(0.002, 0.006, 0.011);
        color += float3(0.01, 0.24, 0.34) * mechanicalStrain *
            (0.24 + waveFront * 0.32) * mechanicsGain;
        color += float3(0.11, 0.08, 0.30) * waveFront * waveSpeed * 0.18 * mechanicsGain;
        color += float3(0.34, 0.24, 0.015) * potentialContour * storedEnergy * 0.065;
        color += float3(0.01, 0.24, 0.15) * contactSubstrate * 0.10;
    }
    float contextExposure = uniforms.displayMode == 5 ? 0.82 : 0.64;
    return finiteHDRColor(color, contextExposure);
}

fragment float4 worldFragment(
    RasterData input [[stage_in]],
    texture2d_array<float, access::sample> state [[texture(0)]],
    texture2d_array<float, access::sample> genomeA [[texture(1)]],
    texture2d_array<float, access::sample> genomeB [[texture(2)]],
    texture2d_array<float, access::sample> ecology [[texture(3)]],
    texture2d_array<float, access::sample> genomeC [[texture(4)]],
    texture2d<float, access::sample> quantum [[texture(5)]],
    texture2d_array<float, access::sample> events [[texture(6)]],
    texture2d_array<float, access::sample> environment [[texture(7)]],
    constant SimulationUniforms& uniforms [[buffer(0)]]
) {
    constexpr sampler cellSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
    constexpr sampler fieldSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    constexpr sampler quantumSampler(coord::normalized, address::repeat, filter::linear);
    float safeAspect = max(uniforms.viewportAspect, 0.001);
    float2 viewScale = safeAspect >= 1.0 ? float2(1.0, 1.0 / safeAspect) : float2(safeAspect, 1.0);
    float2 rawUV = uniforms.cameraCenter + (input.uv - 0.5) * viewScale / max(uniforms.cameraZoom, 0.000000001);
    float2 uv = clamp(rawUV, 0.0, 1.0);

    float2 biologicalSize = float2(uniforms.width, uniforms.height);
    float2 texel = 1.0 / biologicalSize;
    float4 fieldCell = state.sample(cellSampler, uv, 0);
    float4 fieldChemistry = ecology.sample(cellSampler, uv, 0);
    float4 localEnvironment = environment.sample(fieldSampler, uv, 0);

    const float territoryStride = 6.0;
    float2 territoryIndex = floor((uv * biologicalSize + territoryStride * 0.5) / territoryStride);
    float2 territoryOrigin = territoryIndex * territoryStride - territoryStride * 0.5;
    float2 candidateOffsets[5] = {
        float2(3.0, 3.0), float2(1.0, 3.0), float2(5.0, 3.0),
        float2(3.0, 1.0), float2(3.0, 5.0)
    };
    float2 agentSourceUV = (territoryOrigin + candidateOffsets[0]) / biologicalSize;
    float bestAgentScore = -1.0;
    for (uint candidateIndex = 0; candidateIndex < 5; ++candidateIndex) {
        float2 candidateUV = clamp(
            (territoryOrigin + candidateOffsets[candidateIndex]) / biologicalSize,
            texel * 0.5,
            1.0 - texel * 0.5
        );
        float4 candidateState = state.sample(cellSampler, candidateUV, 0);
        uint2 candidateCell = uint2(candidateUV * biologicalSize);
        float tieBreak = random01(candidateCell.x * 2246822519u ^ candidateCell.y * 3266489917u) * 0.0001;
        float score = candidateState.y + tieBreak;
        if (score > bestAgentScore) {
            bestAgentScore = score;
            agentSourceUV = candidateUV;
        }
    }

    float4 cell = state.sample(cellSampler, agentSourceUV, 0);
    float4 geneA = genomeA.sample(cellSampler, agentSourceUV, 0);
    float4 geneB = genomeB.sample(cellSampler, agentSourceUV, 0);
    float4 niche = genomeC.sample(cellSampler, agentSourceUV, 0);
    float4 visibleEvents = float4(0.0);
    float biomass = saturate(cell.y * 1.25);
    float membrane = saturate(cell.w * 2.6);

    uint2 agentID = uint2(territoryIndex);
    uint individualSeed = hash32(agentID.x * 1597334677u ^ agentID.y * 3812015801u);
    float individualPhase = random01(individualSeed);
    float leftResource = state.sample(cellSampler, agentSourceUV - float2(texel.x, 0.0), 0).x;
    float rightResource = state.sample(cellSampler, agentSourceUV + float2(texel.x, 0.0), 0).x;
    float downResource = ecology.sample(cellSampler, agentSourceUV - float2(0.0, texel.y), 0).x;
    float upResource = ecology.sample(cellSampler, agentSourceUV + float2(0.0, texel.y), 0).x;
    float2 resourceGradient = float2(rightResource - leftResource, upResource - downResource);
    float inheritedAngle = geneB.w * 2.0 * M_PI_F + signedRandom(individualSeed + 7u) * 0.88;
    float2 inheritedHeading = float2(cos(inheritedAngle), sin(inheritedAngle));
    float2 steering = inheritedHeading + resourceGradient * (1.6 + niche.x * 2.4);
    steering /= max(length(steering), 0.0001);
    float movementTime = float(uniforms.step) * (0.0045 + 0.0040 * geneB.z) + individualPhase * 19.0;
    float2 lateral = float2(-steering.y, steering.x);
    float conflictLunge = pow(saturate(visibleEvents.z), 2.2) * niche.w;
    float2 homeOffset = float2(signedRandom(individualSeed + 31u), signedRandom(individualSeed + 47u)) * 0.045;
    float2 movementOffset = homeOffset + steering * sin(movementTime) * 0.052 +
        lateral * cos(movementTime * 0.73) * 0.032 + steering * conflictLunge * 0.040;
    float observationZoom = uniforms.cameraZoom / max(uniforms.worldScale, 1.0);
    movementOffset *= 1.0 - smoothstep(18.0, 72.0, observationZoom);
    float2 territorySpan = territoryStride / biologicalSize;
    float2 agentCenter = (territoryOrigin + territoryStride * 0.5) / biologicalSize + movementOffset * territorySpan;
    float2 cellPosition = (uv - agentCenter) / territorySpan;
    float locomotion = sin(movementTime * 3.1);
    float orientation = atan2(steering.y, steering.x) + locomotion * 0.12;
    float2 forward = float2(cos(orientation), sin(orientation));
    float2 bodyPosition = float2(dot(cellPosition, forward), dot(cellPosition, float2(-forward.y, forward.x)));
    float bodyLength = 0.27 + 0.10 * geneB.z;
    float bodyWidth = 0.15 + 0.085 * geneA.y;
    float bodyDistance = length(float2(bodyPosition.x / bodyLength, bodyPosition.y / bodyWidth));
    float abdomenMask = 1.0 - smoothstep(0.82, 1.04, bodyDistance);
    float2 headCenter = float2(bodyLength * 0.72, 0.0);
    float headRadius = 0.095 + 0.055 * niche.w + 0.025 * geneA.z;
    float headDistance = length(bodyPosition - headCenter) / headRadius;
    float headMask = 1.0 - smoothstep(0.78, 1.06, headDistance);
    float tailStart = -bodyLength * 0.64;
    float tailEnd = -0.39;
    float tailRange = smoothstep(tailEnd - 0.02, tailEnd + 0.055, bodyPosition.x) *
        (1.0 - smoothstep(tailStart - 0.04, tailStart + 0.035, bodyPosition.x));
    float tailWave = sin((bodyPosition.x - tailEnd) * (19.0 + geneB.z * 11.0) +
        float(uniforms.step) * (0.024 + geneA.x * 0.018) + individualPhase * 8.0) *
        (0.025 + 0.035 * geneB.z);
    float tailMask = (1.0 - smoothstep(0.018, 0.052, abs(bodyPosition.y - tailWave))) * tailRange;
    float limbReach = 0.20 + 0.08 * geneA.z;
    float limbWidth = 0.015 + 0.018 * geneA.y;
    float limbs = 0.0;
    limbs = max(limbs, 1.0 - smoothstep(limbWidth, limbWidth + 0.025,
        segmentDistance(bodyPosition, float2(-0.05, bodyWidth * 0.62), float2(-0.12, limbReach))));
    limbs = max(limbs, 1.0 - smoothstep(limbWidth, limbWidth + 0.025,
        segmentDistance(bodyPosition, float2(-0.05, -bodyWidth * 0.62), float2(-0.12, -limbReach))));
    limbs *= 0.28 + 0.72 * geneA.z;
    float bodyMask = max(max(abdomenMask, headMask), max(tailMask, limbs));
    // Mobile organisms are rendered from persistent agent state, never synthesized per field tile.
    float occupied = 0.0;
    float organism = bodyMask * occupied;
    float bodyEdge = max(
        abdomenMask * smoothstep(0.62, 0.94, bodyDistance),
        headMask * smoothstep(0.52, 0.90, headDistance)
    ) * occupied;
    float bodyInterior = (1.0 - smoothstep(0.34, 0.84, bodyDistance)) * occupied;
    float head = headMask * occupied;
    float sensor = (1.0 - smoothstep(0.018, 0.040,
        length(bodyPosition - headCenter - float2(headRadius * 0.28, headRadius * 0.18)))) * occupied;
    float jawUpper = 1.0 - smoothstep(0.014, 0.040, segmentDistance(
        bodyPosition, headCenter + float2(headRadius * 0.35, 0.02), float2(0.49, 0.10)
    ));
    float jawLower = 1.0 - smoothstep(0.014, 0.040, segmentDistance(
        bodyPosition, headCenter + float2(headRadius * 0.35, -0.02), float2(0.49, -0.10)
    ));
    float jaws = max(jawUpper, jawLower) * occupied * smoothstep(0.08, 0.42, niche.w);

    float leftBio = state.sample(cellSampler, agentSourceUV - float2(texel.x, 0.0), 0).y;
    float rightBio = state.sample(cellSampler, agentSourceUV + float2(texel.x, 0.0), 0).y;
    float downBio = state.sample(cellSampler, agentSourceUV - float2(0.0, texel.y), 0).y;
    float upBio = state.sample(cellSampler, agentSourceUV + float2(0.0, texel.y), 0).y;
    float2 gradient = float2(rightBio - leftBio, upBio - downBio);
    float rightLineage = genomeB.sample(cellSampler, agentSourceUV + float2(texel.x, 0.0), 0).w;
    float lineageDelta = abs(fract(geneB.w - rightLineage + 0.5) - 0.5);
    float lineageBoundary = smoothstep(0.018, 0.11, lineageDelta) *
        smoothstep(0.03, 0.18, min(cell.y, rightBio));

    float closeDetail = smoothstep(2.0, 16.0, observationZoom);
    float organismReveal = smoothstep(4.0, 18.0, observationZoom);
    float potentialReveal = smoothstep(18.0, 58.0, observationZoom);
    float quantumReveal = smoothstep(52.0, 160.0, observationZoom);
    float latticeReveal = smoothstep(420.0, 980.0, observationZoom);
    float2 detailPosition = uv * float(uniforms.width) * 3.4;
    float microA = visualNoise(detailPosition + geneA.xy * 19.0);
    float microB = visualNoise(detailPosition * 2.1 + geneA.zw * 31.0);
    float micro = mix(microA, microB, 0.42 + geneB.z * 0.24);
    float filament = 1.0 - smoothstep(0.035, 0.13, abs(microA - microB));
    float terrainA = visualNoise(uv * 43.0);
    float terrainB = visualNoise(uv * 91.0 + float2(17.0, 31.0));
    float terrain = mix(terrainA, terrainB, 0.34);
    float environmentRight = environment.sample(fieldSampler, uv + float2(texel.x, 0.0), 0).w;
    float environmentUp = environment.sample(fieldSampler, uv + float2(0.0, texel.y), 0).w;
    float rockGradient = length(float2(environmentRight - localEnvironment.w, environmentUp - localEnvironment.w));
    float rockMask = smoothstep(0.30, 0.68, localEnvironment.w + (terrain - 0.5) * 0.52);
    float rockRim = smoothstep(0.018, 0.12, rockGradient) * (1.0 - rockMask * 0.35);
    float nutrientBed = smoothstep(0.16, 0.66, localEnvironment.x + (terrain - 0.5) * 0.30);
    float mineralBed = smoothstep(0.16, 0.66, localEnvironment.y + (terrainB - 0.5) * 0.34);
    float nutrientGrain = smoothstep(0.60, 0.86, visualNoise(uv * biologicalSize * 0.72 + float2(11.0, 3.0)));
    float mineralGrain = smoothstep(0.66, 0.90, visualNoise(uv * biologicalSize * 0.94 + float2(5.0, 19.0)));
    float visibleResourceA = saturate(fieldCell.x * 0.82);
    float visibleResourceB = saturate(fieldChemistry.x * 0.86);
    float nutrientObject = nutrientBed * (0.10 + nutrientGrain * 0.90) *
        smoothstep(0.004, 0.18, visibleResourceA);
    float mineralObject = mineralBed * (0.08 + mineralGrain * 0.92) *
        smoothstep(0.004, 0.18, visibleResourceB);
    float hazardPulse = 0.62 + 0.38 * sin(float(uniforms.step) * 0.016 +
        (uv.x * 13.0 - uv.y * 9.0) * M_PI_F);
    float fissure = 1.0 - smoothstep(0.025, 0.12,
        abs(sin((uv.x * 17.0 + uv.y * 23.0 + terrain * 0.8) * M_PI_F)));
    float hazardObject = smoothstep(0.18, 0.68, localEnvironment.z + (terrain - 0.5) * 0.22) *
        (0.18 + fissure * 0.82) * hazardPulse;
    float energyCore = saturate(cell.z / max(cell.y * 0.18, 0.001));
    float3 lineage = hsvToRGB(float3(geneB.w, 0.88, 0.50 + 0.28 * geneA.w));
    float3 predatorColor = float3(1.00, 0.055, 0.025);
    float3 defenseColor = float3(0.03, 0.94, 0.66);
    float3 rim = mix(defenseColor, predatorColor, niche.w);

    float genomeRadius = 0.055 + 0.025 * geneB.x;
    float2 genomeCenter = float2(-bodyLength * 0.12, (geneA.z - 0.5) * bodyWidth * 0.28);
    float genomeKnot = (1.0 - smoothstep(genomeRadius, genomeRadius * 1.75, length(bodyPosition - genomeCenter))) * organism;
    float metabolicChannels = filament * bodyInterior * organismReveal;
    float vesicles = smoothstep(0.79, 0.94, visualNoise(bodyPosition * 24.0 + geneB.xy * 13.0)) * organism;

    float3 color;

    if (uniforms.displayMode == 1) {
        color = float3(0.004, 0.009, 0.018) * (0.75 + terrain * 0.32);
        color += float3(0.00, 0.23, 0.46) * saturate(fieldCell.x * 0.82);
        color += float3(0.46, 0.07, 0.57) * saturate(fieldChemistry.x * 0.86);
        color += float3(0.92, 0.20, 0.015) * saturate(fieldChemistry.y * 1.25);
        color += float3(1.0, 0.72, 0.10) * energyCore * biomass * 0.18;
    } else if (uniforms.displayMode == 2) {
        color = float3(0.004, 0.008, 0.015) +
            pow(geneA.xyz, float3(0.75)) * biomass * 0.16;
    } else if (uniforms.displayMode == 3) {
        float enzymeTotal = max(niche.x + niche.y + niche.z, 0.001);
        color = float3(0.004, 0.008, 0.015) +
            (niche.xyz / enzymeTotal) * biomass * 0.18;
        color += predatorColor * niche.w * biomass * 0.12;
    } else {
        float3 normal = normalize(float3(-gradient * 4.0, 0.32));
        float light = 0.46 + 0.42 * max(dot(normal, normalize(float3(-0.36, 0.52, 0.78))), 0.0);
        float bodyBulge = sqrt(saturate(1.0 - bodyDistance * bodyDistance));
        color = float3(0.0025, 0.006, 0.012) * (0.72 + terrain * 0.40);
        color += float3(0.00, 0.035, 0.042) * saturate(fieldCell.x * 0.72);
        color += float3(0.035, 0.006, 0.055) * saturate(fieldChemistry.x * 0.72);
        color += lineage * biomass * organism * (0.38 + bodyBulge * 0.44) * light;
        color += float3(1.0, 0.69, 0.055) * bodyInterior * energyCore * energyCore * (0.18 + 0.36 * organismReveal);
        color += rim * membrane * bodyEdge * (0.72 + 0.70 * organismReveal);
        color += predatorColor * head * niche.w * niche.w * (0.56 + 0.52 * organismReveal);
        color += float3(0.82, 0.98, 1.0) * sensor * organismReveal * 0.92;
        color += predatorColor * jaws * (0.20 + pow(saturate(visibleEvents.z), 2.2) * 1.35);
        color += float3(0.98, 0.12, 0.74) * genomeKnot * organismReveal * 0.74;
        color += mix(float3(0.03, 0.58, 0.96), float3(0.98, 0.64, 0.06), geneA.x) * metabolicChannels * 0.18;
        color += float3(0.90, 0.92, 1.0) * vesicles * organismReveal * 0.12;
        color *= 1.0 - lineageBoundary * organism * 0.22;
        color += hsvToRGB(float3(fract(geneB.w + 0.5), 0.92, 0.72)) * lineageBoundary * organism * 0.10;
    }

    float rimStrength = uniforms.displayMode == 0 ? 0.10 + 0.30 * closeDetail : 0.20 + 0.48 * closeDetail;
    if (uniforms.displayMode == 0) {
        color *= 1.0 - rockMask * 0.76;
        color += float3(0.055, 0.070, 0.078) * rockMask * (0.58 + terrain * 0.34);
        color += float3(0.30, 0.38, 0.40) * rockRim * 0.24;
        color += float3(0.02, 0.82, 0.48) * nutrientObject * (1.0 - rockMask) * 0.25;
        color += float3(0.96, 0.52, 0.025) * mineralObject * (1.0 - rockMask) * 0.27;
        color += float3(1.0, 0.025, 0.012) * hazardObject * (0.24 + localEnvironment.z * 0.42);
    }
    color += rim * bodyEdge * rimStrength;
    color *= mix(1.0, 0.82 + micro * 0.34, closeDetail * organism);
    if (uniforms.displayMode == 0) {
        float birthFlash = pow(saturate(visibleEvents.x), 4.0);
        float mutationFlash = pow(saturate(visibleEvents.y), 2.4);
        float conflictFlash = pow(saturate(visibleEvents.z), 2.8);
        float deathFlash = pow(saturate(visibleEvents.w), 2.6);
        float eventBody = bodyMask * max(occupied, max(max(birthFlash, mutationFlash), max(conflictFlash, deathFlash)));
        float eventVisibility = 1.0 - smoothstep(30.0, 86.0, observationZoom);
        color += float3(0.00, 0.98, 0.88) * birthFlash * eventBody * eventVisibility * 0.88;
        color += float3(0.96, 0.03, 0.92) * mutationFlash * eventBody * eventVisibility * 1.04;
        color += predatorColor * conflictFlash * eventBody * eventVisibility * 1.42;
        color += float3(1.00, 0.27, 0.01) * deathFlash * eventBody * eventVisibility * 1.16;
    }

    float ecologicalPotential = 0.012 * (
        fieldCell.x + fieldChemistry.x * 0.8 + fieldCell.y * 2.2 +
        fieldCell.w * 3.0 + fieldChemistry.z * 1.4
    );
    float potentialField = saturate(ecologicalPotential * 46.0);
    float potentialBands = 1.0 - smoothstep(0.06, 0.19, abs(fract(ecologicalPotential * 420.0) - 0.5));
    float3 potentialColor = mix(float3(0.02, 0.34, 0.62), float3(0.08, 0.96, 0.58), potentialField);
    potentialColor = mix(potentialColor, float3(1.0, 0.16, 0.04), saturate(fieldChemistry.z * 1.4));
    float chemistryWindow = potentialReveal * organism;
    float3 chemistryInterior = color * 0.56 + potentialColor * (0.22 + 0.48 * potentialBands);
    chemistryInterior += float3(1.0, 0.68, 0.06) * metabolicChannels * energyCore * 0.30;
    color = mix(color, chemistryInterior, chemistryWindow);
    color += float3(0.64, 1.0, 0.88) * bodyEdge * potentialReveal * membrane * 0.46;

    float4 wave = quantum.sample(quantumSampler, uv);
    float2 quantumTexel = 1.0 / float(quantumGridSize);
    float4 waveRight = quantum.sample(quantumSampler, uv + float2(quantumTexel.x, 0.0));
    float4 waveUp = quantum.sample(quantumSampler, uv + float2(0.0, quantumTexel.y));
    float probabilityA = dot(wave.xy, wave.xy);
    float probabilityB = dot(wave.zw, wave.zw);
    float probability = probabilityA + probabilityB;
    float2 combinedAmplitude = wave.xy + wave.zw;
    float phase = fract(atan2(combinedAmplitude.y, combinedAmplitude.x) / (2.0 * M_PI_F) + 1.0);
    float probabilityDensity = 1.0 - exp(-probability * 285000.0);
    float spinPolarization = (probabilityA - probabilityB) / max(probability, 0.0000000001);
    float2 probabilityCurrent = float2(
        complexCurrent(wave.xy, waveRight.xy) + complexCurrent(wave.zw, waveRight.zw),
        complexCurrent(wave.xy, waveUp.xy) + complexCurrent(wave.zw, waveUp.zw)
    );
    float currentStrength = saturate(length(probabilityCurrent) * 950000.0);
    float2 currentDirection = probabilityCurrent / max(length(probabilityCurrent), 0.0000000001);
    float3 phaseColor = quantumPhaseColor(phase);
    float3 spinColor = mix(float3(1.0, 0.24, 0.035), float3(0.02, 0.78, 1.0), spinPolarization * 0.5 + 0.5);
    float phaseContour = 0.66 + 0.34 * cos(phase * 28.0 * M_PI_F);
    float flowCoordinate = fract(dot(uv * float(quantumGridSize), currentDirection) * 0.22 - float(uniforms.step) * 0.012);
    float currentPulse = 1.0 - smoothstep(0.035, 0.13, abs(flowCoordinate - 0.5));
    float node = 1.0 - smoothstep(0.018, 0.15, probabilityDensity);
    float3 quantumColor = mix(phaseColor, spinColor, 0.36) * probabilityDensity * (0.56 + 0.44 * phaseContour);
    quantumColor += float3(0.78, 0.96, 1.0) * currentPulse * currentStrength * probabilityDensity * 0.72;
    quantumColor *= 1.0 - node * 0.86;

    float2 quantumCell = fract(uv * float(quantumGridSize));
    bool positiveComponent = quantumCell.x < 0.5;
    float2 componentPosition = positiveComponent
        ? float2(quantumCell.x * 2.0, quantumCell.y) - 0.5
        : float2((quantumCell.x - 0.5) * 2.0, quantumCell.y) - 0.5;
    float componentMask = 1.0 - smoothstep(0.37, 0.48, length(componentPosition));
    float2 componentAmplitude = positiveComponent ? wave.xy : wave.zw;
    float componentProbability = positiveComponent ? probabilityA : probabilityB;
    float componentDensity = 1.0 - exp(-componentProbability * 520000.0);
    float componentPhase = fract(atan2(componentAmplitude.y, componentAmplitude.x) / (2.0 * M_PI_F) + 1.0);
    float3 componentBase = positiveComponent ? float3(0.02, 0.82, 1.0) : float3(1.0, 0.25, 0.035);
    float3 componentColor = mix(componentBase, quantumPhaseColor(componentPhase), 0.46);
    float2 phasorDirection = float2(cos(componentPhase * 2.0 * M_PI_F), sin(componentPhase * 2.0 * M_PI_F));
    float phasorLine = 1.0 - smoothstep(0.018, 0.055, abs(componentPosition.x * phasorDirection.y - componentPosition.y * phasorDirection.x));
    phasorLine *= smoothstep(0.38, 0.12, length(componentPosition));
    float latticeEdge = 1.0 - smoothstep(0.015, 0.065, min(min(quantumCell.x, 1.0 - quantumCell.x), min(quantumCell.y, 1.0 - quantumCell.y)));
    float3 spinorTile = float3(0.002, 0.004, 0.010) + componentColor * componentMask * componentDensity;
    spinorTile += float3(0.92, 0.98, 1.0) * phasorLine * componentMask * componentDensity * 0.86;
    spinorTile += float3(0.08, 0.18, 0.26) * latticeEdge * 0.52;
    quantumColor = mix(quantumColor, spinorTile, latticeReveal);

    float quantumWindow = quantumReveal * organism;
    color = mix(color, quantumColor, quantumWindow);
    color += potentialColor * potentialBands * chemistryWindow * (1.0 - quantumReveal) * 0.12;
    color += float3(0.66, 1.0, 0.90) * bodyEdge * quantumReveal *
        (0.22 + currentStrength * 0.52);
    color = 1.0 - exp(-max(color, 0.0) * 1.46);
    return finiteHDRColor(color, 1.0);
}
