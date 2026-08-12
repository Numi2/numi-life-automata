#include <metal_stdlib>
using namespace metal;
#include "OpenEndedEcologyABI.metalh"

struct SimulationUniforms {
    uint width;
    uint height;
    uint worldCount;
    uint step;
    float dt;
    float externalEnergyFlux;
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
constant uint ecologyGridSize = 193u;
constant uint ecologyWorldCount = 1u;
constant uint ecologyTileCapacity =
    ecologyGridSize * ecologyGridSize * ecologyWorldCount;
constant uint maxCellCount = 9216u;
constant uint maxAgentCount = maxCellCount;
constant uint maxGenomeHeaderCount = 4096u;
constant uint maxProgramsPerPropagule = 16u;
constant uint mixedComponentOwner = maxAgentCount + 1u;
constant float referenceTissueCellCount = 24.0;
constant uint regulatoryStateChannelCount = 12u;
constant uint membraneVertexCount = 12u;
constant uint membraneRenderSubdivision = 3u;
constant uint membraneRenderSegmentCount = membraneVertexCount * membraneRenderSubdivision;
// A division can publish a birth, mutation, and recombination record, while a
// topology pass can publish one component record per cell.  Keeping four slots
// per physical cell prevents two live GPU writers in one dispatch interval from
// aliasing the same ring entry before the observer can consume it.
constant uint lineageEventCapacity = maxCellCount * 4u;
constant uint cellSpatialHashBucketCount = 16384u;
constant uint cellSpatialHashAxisResolution = 128u;
// A twelve-vertex membrane has at most one unoccluded nearest contact per
// support sector. The queue therefore has a physical, population-wide bound.
constant uint membraneContactPairCapacity = maxCellCount * membraneVertexCount;
constant uint componentTopologyReconciliationStride = 256u;
constant uint cellJunctionCapacity = 32768u;
constant uint cellJunctionMask = cellJunctionCapacity - 1u;
constant uint registeredJunctionCountIndex = 4u;
constant uint registeredJunctionFlag = 0x80000000u;
constant uint cellContactEffectChannelCount = 14u;
constant uint trophicSourceBudgetChannel = 10u;
constant uint trophicReceiverBudgetChannel = 11u;
constant uint reproductiveSourceBudgetChannel = 12u;
constant uint reproductiveReceiverBudgetChannel = 13u;
constant uint cellOccupancyFree = 0u;
constant uint cellOccupancyAlive = 1u;
constant uint cellOccupancyCorpse = 2u;
constant uint embodiedMemoryCount = 4u;
constant uint corpseStructureScale = 1048576u;
constant uint corpseMaximumPersistenceSteps = 720u;
constant uint sexualPartnerIndexBits = 14u;
constant uint sexualPartnerIndexMask = (1u << sexualPartnerIndexBits) - 1u;
// Channels 0...1 return reduced matter and heat. Channels 2...7 carry
// cell-produced developmental outputs into the next extracellular-field step:
// ligand A, ligand B, matrix deposition, wound/remodeling cue, catalytic
// molecule secretion, and reactive-molecule neutralization.
constant uint worldExchangeChannelCount = 8u;
constant uint componentMulticellularFlag = 1u << 0u;
constant uint componentRegeneratedFlag = 1u << 1u;
constant uint componentHomeostaticFlag = 1u << 2u;
constant uint componentChallengedFlag = 1u << 3u;
constant uint componentQualificationTargetFlag = 1u << 4u;
constant uint componentSexualOffspringFlag = 1u << 5u;
constant uint reservedCellJunctionEntry = 0u;
constant uint emptySpatialHashEntry = 0xffffffffu;
constant int mechanicalForceScale = 1048576;
constant int cellContactForceScale = 268435456;
constant int cellContactScalarScale = 1048576;
// Exchange channels are accumulated per world tile.  The previous Q28 format
// wrapped at only 16 units, so a dense local death/recycling event could turn a
// positive export into a tiny value. Q22 covers 1,024 units while still resolving
// the smallest developmental secretion channels.
constant uint substrateFixedScale = 4194304u;
// Energy audits reduce over all 9,216 cells.  Q16 covers the full-population
// storage bound without signed 32-bit wrap and retains 15-micro-unit precision.
constant int energyAuditScale = 65536;
constant uint energyAuditResidualTolerance = 16u;
constant uint energySharingResidualTolerance = 64u;
constant float interactionAuditScale = 1048576.0;
constant float chemistryAuditScale = 1048576.0;
constant uint invariantStateCount = 20u;
constant uint invariantScratchHeaderCount = 16u;
constant uint invariantOwnerRootOffset = invariantScratchHeaderCount + maxGenomeHeaderCount;
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
    float4 metabolicExpression;
    float4 dynamicExpression;
    float4 transportExpression;
    // Page-decoded ligand composition followed by receptor-binding expression.
    float4 receptorChemistry;
    // Page-decoded junction adhesion, permeability, rejection chemistry, and transfer.
    float4 junctionChemistry;
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
    // Adhesion, contractility, feedstock-A uptake, feedstock-B uptake.
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
    // External energy forcing, barrier load, environmental frequency, and frequency match.
    float4 environment;
    // Persistent tissue polarity, fate memory, and junction morphogen transport.
    float4 development;
    // Emergent boundary coverage, transmitted tension, protrusion growth, and oscillation phase.
    float4 boundaryDynamics;
    // Evolvable membrane thickness, stiffness, toughness, and adhesion.
    float4 membraneProperties;
    // Evolvable permeability, conductivity, receptor density, and catalytic coating.
    float4 membraneChemistry;
    // Chronological age, replication burden, proteostasis burden, and injury reopening.
    float4 lifeHistory;
    // Measured replication, maintenance, signaling, and material-synthesis activity.
    float4 functionalActivity;
    // Cue prediction, prediction error, habituation, and acquired sensorimotor bias.
    float4 learning;
    // Paid stiffness, storage, catalysis, and reactive-binding material deposition.
    float4 constructionFlux;
    // Proton gradient, ion gradient, redox potential, and requested expression work.
    float4 molecularEnergy;
    // Folded catalytic, transport, regulatory, and structural protein activity.
    float4 molecularExpression;
    // Folded fraction, damaged fraction, chaperone activity, and proteolytic recycling.
    float4 proteostasis;
    // Localization diversity, membrane-bound fraction, inherited foreign fraction,
    // and persistence of internally segregated chemistry.
    float4 compartments;
    // Genome-derived molecule routes used by the deterministic chemistry settlement.
    uint4 molecularUptakeSpecies;
    uint4 molecularOutputSpecies;
};

// Four packed half4 episodes. Each episode is
// (cue projection, action projection, physical consequence, retained strength).
struct CellMemoryState {
    uint2 episodes[embodiedMemoryCount];
};

// Structure is physical/informational mass, not a second energy store. Terminal
// energy still enters the existing recycledMatter/heat ledger exactly once.
struct CellCorpseState {
    atomic_uint structure;
    uint deathStep;
    float2 worldPosition;
    uint donorGenomeHash;
    uint reserved;
    uint2 episodes[embodiedMemoryCount];
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

struct ProgramLineageRecord {
    float4 metabolicExpression;
    float4 dynamicExpression;
    float4 transportExpression;
    float4 receptorChemistry;
    float4 junctionChemistry;
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
    // Mean absolute ATP exchange, rejection load, receptorChemistry compatibility, and net contribution.
    float4 programEcology;
    // Mean substrate forcing, barrier load, environmental frequency, and frequency match.
    float4 environment;
    // Mean morphogen A, morphogen B, fate memory, and junction transport.
    float4 development;
    // Morphogen differentiation, polarity coherence, synthesis, and transport work.
    float4 developmentCausality;
    // Component-level cue, action, consequence, and retained evidence.
    float4 embodiedMemory;
    // Mean membrane thickness, stiffness, toughness, and adhesion.
    float4 membraneProperties;
    // Mean permeability, conductivity, receptor density, and catalytic coating.
    float4 membraneChemistry;
    // Mean chronological age, replication burden, proteostasis burden, and injury reopening.
    float4 lifeHistory;
    // Mean replication, maintenance, signaling, and material-synthesis activity.
    float4 functionalActivity;
    // Mean cue prediction, prediction error, habituation, and acquired behavior.
    float4 learning;
    // Mean stiffness, storage, catalysis, and reactive-binding deposition.
    float4 constructionFlux;
    // Mean membrane gradients/redox/work and folded molecular capabilities.
    float4 molecularEnergy;
    float4 molecularExpression;
    // Mean folding quality, damage/turnover machinery, and compartmentalization.
    float4 proteostasis;
    float4 compartments;
};

struct QualificationTargetMeasurement {
    // Owner slot, permanent birth ID, current cell count, and component flags.
    uint4 identity;
    // Extracellular ligand A/B, matrix density, and wound cue at the target centroid.
    float4 developmental;
};

struct ProgramExpressionCache {
    // Nonauthoritative hot cache decoded from immutable genome pages.
    // Expressed regulation pages, linked pages, program hash, and structural mutations.
    uint4 pageSummary;
    // Cumulative distance, last mutation distance, page-change rate, and link-change rate.
    float4 mutation;
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
    // Reactive-molecule tolerance, molecular scavenging, shear anchoring, starvation quiescence.
    float4 chemicalResponse;
    // Organizer persistence, segment frequency, bilateral coupling, outgrowth gain.
    float4 morphogenesisA;
    // Plasticity gain, canalization rate, material retention, injury reopening.
    float4 morphogenesisB;
    // Damage production, turnover sensitivity, replication cost, and repair kinetics.
    float4 turnoverControl;
    // Reopening gain, replication allocation, maintenance allocation, and plasticity.
    float4 allocationControl;
    // Stiffness, storage, catalytic, and reactive-binding material synthesis.
    float4 materialSynthesis;
    // Signal plasticity, learning rate, habituation, and contact-memory transfer.
    float4 plasticityControl;
};

struct ResonanceExpressionCache {
    // Natural frequency, damping ratio, sensor gain, and response threshold.
    float4 mechanics;
    // Bandwidth, adaptation rate, phase delay, and directional preference.
    float4 tuning;
};

struct ProgramMetricRecord {
    ProgramExpressionCache developmental;
    ResonanceExpressionCache resonance;
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
    float4 junctionChemistry;
    // External energy forcing, barrier load, environmental frequency, and frequency match.
    float4 environment;
    float4 lifeHistory;
    float4 functionalActivity;
    float4 learning;
    float4 constructionFlux;
    float4 molecularEnergy;
    float4 molecularExpression;
    float4 proteostasis;
    float4 compartments;
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
    float4 junctionChemistry;
    float4 environment;
    float4 lifeHistory;
    float4 functionalActivity;
    float4 learning;
    float4 constructionFlux;
    float4 molecularEnergy;
    float4 molecularExpression;
    float4 proteostasis;
    float4 compartments;
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

inline float2 normalizedOr(float2 value, float2 fallback) {
    float magnitudeSquared = dot(value, value);
    return magnitudeSquared > 0.000000000001 && all(isfinite(value))
        ? value * rsqrt(magnitudeSquared)
        : fallback;
}

inline uint moleculeIndex(uint tileIndex, uint slot) {
    // Species-major storage lets adjacent Apple GPU SIMD lanes read the same
    // sparse slot from adjacent world tiles in one contiguous transaction.
    // Tile-major storage imposed a 128-byte stride per lane in the dominant
    // diffusion kernel and discarded most fetched cache-line data.
    return slot * ecologyTileCapacity + tileIndex;
}

/// Map a destination texel in the central half of an expanded world to the
/// lower-left texel of its exact 2 x 2 source block. Deriving this from texel
/// centres shifts every block by one source texel, drops the old zero edge,
/// and duplicates the far edge.
inline uint2 expandedWorldSourceBase(uint2 destination, uint2 dimensions) {
    uint2 centralOrigin = dimensions / 4u;
    return min(
        (destination - centralOrigin) * 2u,
        dimensions - uint2(2u)
    );
}

inline void atomicAddSaturatingUInt(
    device atomic_uint* destination,
    uint increment
) {
    if (increment == 0u) { return; }
    uint observed = atomic_load_explicit(destination, memory_order_relaxed);
    while (observed != 0xffffffffu) {
        uint desired = observed > 0xffffffffu - increment
            ? 0xffffffffu : observed + increment;
        uint expected = observed;
        if (atomic_compare_exchange_weak_explicit(
            destination, &expected, desired,
            memory_order_relaxed, memory_order_relaxed
        )) { return; }
        observed = expected;
    }
}

/// Consume a value after its producing pass has completed. Metal command order
/// makes these consumers exclusive, so a load and conditional clear preserve
/// the producer/consumer contract without an unnecessary read-modify-write on
/// every empty world tile.
inline uint consumePublishedUInt(device atomic_uint* source) {
    uint value = atomic_load_explicit(source, memory_order_relaxed);
    if (value != 0u) {
        atomic_store_explicit(source, 0u, memory_order_relaxed);
    }
    return value;
}

inline int consumePublishedInt(device atomic_int* source) {
    int value = atomic_load_explicit(source, memory_order_relaxed);
    if (value != 0) {
        atomic_store_explicit(source, 0, memory_order_relaxed);
    }
    return value;
}

inline bool atomicAddSaturatingInt(
    device atomic_int* destination,
    int increment
) {
    if (increment == 0) { return false; }
    constexpr int upperLimit = 2147483647;
    constexpr int lowerLimit = -2147483647;
    int observed = atomic_load_explicit(destination, memory_order_relaxed);
    while (true) {
        int desired;
        if (increment > 0 && observed > upperLimit - increment) {
            desired = upperLimit;
        } else if (increment < 0 && observed < lowerLimit - increment) {
            desired = lowerLimit;
        } else {
            desired = observed + increment;
        }
        bool saturated = desired == upperLimit || desired == lowerLimit;
        if (desired == observed) { return saturated; }
        int expected = observed;
        if (atomic_compare_exchange_weak_explicit(
            destination, &expected, desired,
            memory_order_relaxed, memory_order_relaxed
        )) { return saturated; }
        observed = expected;
    }
}

inline void auditChemistry(
    device ChemistryAuditState* audit,
    device atomic_int* destination,
    float value
) {
    if (!isfinite(value)) {
        atomicAddSaturatingUInt(&audit->auditSaturationCount, 1u);
        return;
    }
    float scaled = value * chemistryAuditScale;
    bool inputClamped = scaled < -2147480000.0 || scaled > 2147480000.0;
    int fixed = int(clamp(
        scaled, -2147480000.0, 2147480000.0
    ));
    if (inputClamped || atomicAddSaturatingInt(destination, fixed)) {
        atomicAddSaturatingUInt(&audit->auditSaturationCount, 1u);
    }
}

inline void auditChemistryFixed(
    device ChemistryAuditState* audit,
    device atomic_int* destination,
    int fixed
) {
    if (atomicAddSaturatingInt(destination, fixed)) {
        atomicAddSaturatingUInt(&audit->auditSaturationCount, 1u);
    }
}

inline float4 unpackEmbodiedMemory(uint2 packed) {
    half2 lower = as_type<half2>(packed.x);
    half2 upper = as_type<half2>(packed.y);
    return float4(float2(lower), float2(upper));
}

inline uint2 packEmbodiedMemory(float4 episode) {
    float4 bounded = clamp(
        episode,
        float4(-1.0, -1.0, -1.0, 0.0),
        float4(1.0)
    );
    return uint2(
        as_type<uint>(half2(bounded.xy)),
        as_type<uint>(half2(bounded.zw))
    );
}

inline CellMemoryState emptyCellMemory() {
    CellMemoryState memory;
    for (uint index = 0u; index < embodiedMemoryCount; ++index) {
        memory.episodes[index] = uint2(0u);
    }
    return memory;
}

inline float strongestEmbodiedMemory(
    CellMemoryState memory,
    thread float4& episode
) {
    float strongest = 0.0;
    episode = float4(0.0);
    for (uint index = 0u; index < embodiedMemoryCount; ++index) {
        float4 candidate = unpackEmbodiedMemory(memory.episodes[index]);
        if (candidate.w > strongest) {
            strongest = candidate.w;
            episode = candidate;
        }
    }
    return strongest;
}

inline float recallEmbodiedAction(CellMemoryState memory, float cue) {
    float replay = 0.0;
    float evidence = 0.0;
    for (uint index = 0u; index < embodiedMemoryCount; ++index) {
        float4 episode = unpackEmbodiedMemory(memory.episodes[index]);
        float similarity = saturate(1.0 - abs(cue - episode.x) * 1.75);
        float weight = similarity * episode.w;
        replay += episode.y * episode.z * weight;
        evidence += weight;
    }
    return evidence > 0.0001 ? clamp(replay / evidence, -1.0, 1.0) : 0.0;
}

inline void learnEmbodiedEpisode(
    thread CellMemoryState& memory,
    float cue,
    float action,
    float consequence
) {
    uint bestIndex = 0u;
    uint weakestIndex = 0u;
    float bestMatch = -1.0;
    float weakestStrength = 2.0;
    float4 episodes[embodiedMemoryCount];
    for (uint index = 0u; index < embodiedMemoryCount; ++index) {
        float4 episode = unpackEmbodiedMemory(memory.episodes[index]);
        episode.w *= 0.99915;
        episode.z *= 0.99965;
        episodes[index] = episode;
        float match = 1.0 - saturate(
            abs(cue - episode.x) * 1.30 + abs(action - episode.y) * 0.70
        );
        if (match > bestMatch) {
            bestMatch = match;
            bestIndex = index;
        }
        if (episode.w < weakestStrength) {
            weakestStrength = episode.w;
            weakestIndex = index;
        }
    }

    float consequenceMagnitude = abs(consequence);
    if (bestMatch > 0.62 && episodes[bestIndex].w > 0.015) {
        float adaptation = 0.018 + consequenceMagnitude * 0.055;
        episodes[bestIndex].x = mix(episodes[bestIndex].x, cue, adaptation);
        episodes[bestIndex].y = mix(episodes[bestIndex].y, action, adaptation);
        episodes[bestIndex].z = mix(
            episodes[bestIndex].z, consequence, 0.025 + consequenceMagnitude * 0.090
        );
        episodes[bestIndex].w = saturate(
            episodes[bestIndex].w + consequenceMagnitude * 0.0105
        );
    } else if (consequenceMagnitude > 0.045) {
        episodes[weakestIndex] = float4(
            cue, action, consequence,
            clamp(0.025 + consequenceMagnitude * 0.14, 0.025, 0.22)
        );
    }
    for (uint index = 0u; index < embodiedMemoryCount; ++index) {
        memory.episodes[index] = packEmbodiedMemory(episodes[index]);
    }
}

inline void receiveEmbodiedEpisode(
    thread CellMemoryState& memory,
    float4 received
) {
    if (received.w <= 0.0001) { return; }
    uint weakestIndex = 0u;
    float weakestStrength = 2.0;
    for (uint index = 0u; index < embodiedMemoryCount; ++index) {
        float4 episode = unpackEmbodiedMemory(memory.episodes[index]);
        float similarity = 1.0 - saturate(
            abs(received.x - episode.x) * 1.25 +
            abs(received.y - episode.y) * 0.75
        );
        if (similarity > 0.72 && episode.w > 0.01) {
            float transmission = min(received.w, 0.12);
            episode.xyz = mix(episode.xyz, received.xyz, transmission);
            episode.w = saturate(episode.w + transmission * 0.10);
            memory.episodes[index] = packEmbodiedMemory(episode);
            return;
        }
        if (episode.w < weakestStrength) {
            weakestStrength = episode.w;
            weakestIndex = index;
        }
    }
    received.w = min(received.w * 0.34, 0.09);
    memory.episodes[weakestIndex] = packEmbodiedMemory(received);
}

inline uint claimCorpseStructure(device atomic_uint* structure, uint requested) {
    uint available = atomic_load_explicit(structure, memory_order_relaxed);
    while (available > 0u) {
        uint claimed = min(available, requested);
        uint remaining = available - claimed;
        if (atomic_compare_exchange_weak_explicit(
            structure, &available, remaining,
            memory_order_relaxed, memory_order_relaxed
        )) {
            return claimed;
        }
    }
    return 0u;
}

inline void publishCellCorpse(
    device CellCorpseState* corpses,
    uint cellIndex,
    CellMemoryState memory,
    float2 worldPosition,
    uint donorGenomeHash,
    float biomass,
    float integrity,
    uint step
) {
    corpses[cellIndex].deathStep = step;
    corpses[cellIndex].worldPosition = clamp(
        worldPosition, float2(0.0), float2(1.0)
    );
    corpses[cellIndex].donorGenomeHash = donorGenomeHash;
    corpses[cellIndex].reserved = 0u;
    for (uint index = 0u; index < embodiedMemoryCount; ++index) {
        corpses[cellIndex].episodes[index] = memory.episodes[index];
    }
    uint structure = uint(clamp(
        biomass * mix(0.38, 1.0, saturate(integrity)) * float(corpseStructureScale),
        1.0, float(corpseStructureScale)
    ));
    atomic_store_explicit(
        &corpses[cellIndex].structure, structure, memory_order_relaxed
    );
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

inline uint packedSexualPartner(uint partnerIndex, float score) {
    if (partnerIndex >= maxCellCount || score <= 0.0) { return 0u; }
    uint scoreQ18 = max(
        uint(clamp(score * 262143.0, 1.0, 262143.0)), 1u
    );
    // Higher suitability wins; equal suitability deterministically selects the
    // lower persistent cell slot without another allocation or arbitration pass.
    return (scoreQ18 << sexualPartnerIndexBits) |
        (sexualPartnerIndexMask - partnerIndex);
}

inline uint sexualPartnerIndex(uint packedPartner) {
    if (packedPartner == 0u) { return maxCellCount; }
    return sexualPartnerIndexMask - (packedPartner & sexualPartnerIndexMask);
}

inline float sexualPartnerScore(uint packedPartner) {
    return float(packedPartner >> sexualPartnerIndexBits) / 262143.0;
}

inline void nominateSexualPartner(
    device CellIdentity* identities,
    uint gestatingCell,
    uint donorCell,
    float score
) {
    uint packedPartner = packedSexualPartner(donorCell, score);
    if (packedPartner == 0u) { return; }
    device atomic_uint* nomination = reinterpret_cast<device atomic_uint*>(
        &identities[gestatingCell].identityPadding0
    );
    atomic_fetch_max_explicit(nomination, packedPartner, memory_order_relaxed);
}

inline uint sexualBudAge(CellIdentity identity, uint step) {
    if (identity.identityPadding2 == 0u) { return 0u; }
    uint conceptionStep = identity.identityPadding2 - 1u;
    return step >= conceptionStep ? step - conceptionStep : 0u;
}

inline float sexualBudNurture(
    CellIdentity identity,
    uint step,
    float propaguleInvestment
) {
    if (identity.identityPadding2 == 0u) { return 0.0; }
    float investment = saturate(propaguleInvestment / 1.80);
    float releaseStart = mix(112.0, 48.0, investment);
    return 1.0 - smoothstep(releaseStart * 0.45, releaseStart + 28.0,
        float(sexualBudAge(identity, step)));
}

inline float sexualBudRelease(
    CellIdentity identity,
    uint step,
    float propaguleInvestment,
    float atp,
    float integrity
) {
    if (identity.identityPadding2 == 0u) { return 0.0; }
    float investment = saturate(propaguleInvestment / 1.80);
    float releaseStart = mix(112.0, 48.0, investment);
    float developmentalTime = smoothstep(
        releaseStart, releaseStart + mix(112.0, 56.0, investment),
        float(sexualBudAge(identity, step))
    );
    float physiologicalReadiness = smoothstep(0.18, 0.34, atp) *
        smoothstep(0.50, 0.82, integrity);
    return saturate(developmentalTime * physiologicalReadiness);
}

inline float reproductiveEndocrineDrive(
    CellState cell,
    ProgramExpressionCache development,
    AgentState program
) {
    float energeticSurplus = smoothstep(0.16, 0.48, cell.physiology.x) *
        smoothstep(0.40, 0.82, cell.physiology.y);
    float membraneReadiness = smoothstep(0.34, 0.78, cell.physiology.w) *
        (1.0 - smoothstep(0.42, 0.74, cell.signals.z));
    float receptorBalance =
        cell.signals.x * development.morphogenTransport.x -
        cell.signals.y * development.morphogenTransport.y +
        (cell.development.z - 0.5) * 0.34;
    float endocrinePermission = mix(
        0.48, 1.0, smoothstep(-0.28, 0.46, receptorBalance)
    );
    float refractoryAvailability = mix(
        0.30, 1.0, 1.0 - smoothstep(0.20, 0.72, cell.signaling.z)
    );
    // The program parameter is retained for ABI stability, but reproductive
    // permission is produced by folded regulatory/structural molecules rather
    // than a directly readable inherited coefficient.
    (void)program;
    float inheritedInvestment = sqrt(max(
        cell.molecularExpression.z * cell.molecularExpression.w *
            saturate(development.mechanochemistryB.w / 1.80),
        0.0
    ));
    float readinessProduct = max(
        energeticSurplus * membraneReadiness * endocrinePermission *
            refractoryAvailability,
        0.0000001
    );
    return saturate(sqrt(sqrt(readinessProduct)) * inheritedInvestment);
}

inline void applyLocalReproductiveClimax(
    thread CellState& cell,
    float intensity
) {
    float peak = saturate(intensity);
    cell.signals.z = saturate(cell.signals.z - peak * 0.060);
    cell.signaling.x = saturate(cell.signaling.x + peak * 0.30);
    cell.signaling.y = saturate(cell.signaling.y + peak * 0.34);
    cell.signaling.z = saturate(cell.signaling.z + peak * 0.16);
    cell.dynamics.x = clamp(cell.dynamics.x + peak * 0.20, -1.8, 1.8);
    cell.mechanics.x = clamp(cell.mechanics.x + peak * 0.42, 0.0, 1.8);
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

inline ProgramExpressionCache emptyProgramExpressionCache() {
    ProgramExpressionCache genome;
    genome.pageSummary = uint4(0u);
    genome.mutation = float4(0.0, 0.0, 0.018, 0.032);
    genome.mechanochemistryA = float4(1.0, 1.0, 1.0, 1.0);
    genome.mechanochemistryB = float4(1.0, 1.0, 0.42, 1.0);
    genome.morphogenKinetics = float4(0.34, 0.30, 0.22, 0.20);
    genome.morphogenTransport = float4(1.0, 1.0, 0.42, 0.34);
    genome.junctionMaterial = float4(0.72, 0.42, 0.46, 0.52);
    genome.chemicalResponse = float4(0.28, 0.24, 0.30, 0.36);
    genome.morphogenesisA = float4(0.68, 2.40, 0.72, 0.70);
    genome.morphogenesisB = float4(0.72, 0.42, 0.78, 0.66);
    genome.turnoverControl = float4(1.0, 0.46, 1.05, 0.34);
    genome.allocationControl = float4(0.76, 0.48, 0.66, 0.72);
    genome.materialSynthesis = float4(0.42, 0.38, 0.46, 0.40);
    genome.plasticityControl = float4(0.48, 0.36, 0.42, 0.28);
    return genome;
}

inline ResonanceExpressionCache emptyResonanceExpressionCache() {
    ResonanceExpressionCache genome;
    genome.mechanics = float4(0.0032, 0.24, 0.68, 0.004);
    genome.tuning = float4(0.0018, 0.0012, 0.0, 0.0);
    return genome;
}

inline ProgramLineageRecord emptyProgramLineageRecord() {
    ProgramLineageRecord program;
    program.metabolicExpression = float4(0.0);
    program.dynamicExpression = float4(0.0);
    program.transportExpression = float4(0.0);
    program.receptorChemistry = float4(0.0);
    program.junctionChemistry = float4(0.0);
    program.genomeHash = 0u;
    program.parentGenomeHash = 0u;
    program.originBirthID = 0u;
    program.generation = 0u;
    program.parentProgramIndex = maxGenomeHeaderCount;
    program.parentProgramGeneration = 0u;
    program.secondParentGenomeHash = 0u;
    program.secondParentProgramIndex = maxGenomeHeaderCount;
    program.secondParentProgramGeneration = 0u;
    program.ancestryFlags = 0u;
    return program;
}

inline AgentState agentWithProgramExpression(
    AgentState agent,
    ProgramLineageRecord program
) {
    agent.metabolicExpression = program.metabolicExpression;
    agent.dynamicExpression = program.dynamicExpression;
    agent.transportExpression = program.transportExpression;
    agent.receptorChemistry = program.receptorChemistry;
    agent.junctionChemistry = program.junctionChemistry;
    agent.genomeHash = program.genomeHash;
    return agent;
}

inline AgentState agentWithCellProgram(
    AgentState agent,
    uint programIndex,
    device const ProgramLineageRecord* programs
) {
    if (programIndex < maxGenomeHeaderCount &&
        programIndex != agent.dominantProgramIndex) {
        return agentWithProgramExpression(agent, programs[programIndex]);
    }
    return agent;
}

inline ProgramLineageRecord programLineageRecordFromAgent(
    AgentState agent,
    uint parentGenomeHash,
    uint parentProgramIndex,
    uint parentProgramGeneration
) {
    ProgramLineageRecord program;
    program.metabolicExpression = agent.metabolicExpression;
    program.dynamicExpression = agent.dynamicExpression;
    program.transportExpression = agent.transportExpression;
    program.receptorChemistry = agent.receptorChemistry;
    program.junctionChemistry = agent.junctionChemistry;
    program.genomeHash = agent.genomeHash;
    program.parentGenomeHash = parentGenomeHash;
    program.originBirthID = agent.birthID;
    program.generation = agent.programReplicationGeneration;
    program.parentProgramIndex = parentProgramIndex;
    program.parentProgramGeneration = parentProgramGeneration;
    program.secondParentGenomeHash = 0u;
    program.secondParentProgramIndex = maxGenomeHeaderCount;
    program.secondParentProgramGeneration = 0u;
    program.ancestryFlags = 0u;
    return program;
}

inline float4 founderReceptorChemistry(AgentState agent, uint seed) {
    float2 ligand = fract(float2(
        agent.metabolicExpression.x * 0.61 + agent.dynamicExpression.w * 0.39 + random01(seed + 31u) * 0.16,
        agent.metabolicExpression.y * 0.47 + agent.transportExpression.y * 0.53 + random01(seed + 37u) * 0.16
    ));
    float2 receptor = clamp(
        ligand + float2(signedRandom(seed + 41u), signedRandom(seed + 43u)) * 0.055,
        0.0, 1.0
    );
    return float4(ligand, receptor);
}

inline float4 founderJunctionChemistry(AgentState agent, uint seed) {
    return clamp(float4(
        0.24 + agent.metabolicExpression.y * 0.58 + signedRandom(seed + 47u) * 0.08,
        0.18 + agent.dynamicExpression.x * 0.54 + signedRandom(seed + 53u) * 0.08,
        0.12 + agent.metabolicExpression.w * 0.62 + signedRandom(seed + 59u) * 0.08,
        0.24 + agent.dynamicExpression.z * 0.58 + signedRandom(seed + 61u) * 0.08
    ), 0.0, 1.0);
}

inline float receptorChemistryCompatibility(AgentState a, AgentState b) {
    float reciprocalMismatch = 0.5 * (
        length(a.receptorChemistry.xy - b.receptorChemistry.zw) +
        length(b.receptorChemistry.xy - a.receptorChemistry.zw)
    );
    return saturate(1.0 - reciprocalMismatch * 0.92);
}

#include "GenomePages.metalh"

inline ResonanceExpressionCache founderResonanceExpression(AgentState agent, uint seed) {
    ResonanceExpressionCache genome;
    float frequency = 0.0014 + agent.dynamicExpression.z * 0.0042 +
        random01(seed + 3u) * 0.0010;
    genome.mechanics = float4(
        clamp(frequency, 0.0008, 0.0090),
        clamp(0.12 + (1.0 - agent.metabolicExpression.z) * 0.30 +
            signedRandom(seed + 5u) * 0.04, 0.06, 0.62),
        clamp(0.42 + agent.metabolicExpression.z * 0.72 +
            signedRandom(seed + 7u) * 0.10, 0.12, 1.40),
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

inline uint agentGenomeHash(
    AgentState agent,
    uint pageHash,
    ResonanceExpressionCache resonance,
    ProgramExpressionCache development
) {
    uint value = pageHash;
    value = hash32(value ^ as_type<uint>(agent.metabolicExpression.x) ^
        as_type<uint>(agent.metabolicExpression.y));
    value = hash32(value ^ as_type<uint>(agent.dynamicExpression.z) ^
        as_type<uint>(agent.transportExpression.w));
    value = hash32(value ^ as_type<uint>(agent.receptorChemistry.x) ^
        as_type<uint>(agent.receptorChemistry.y));
    value = hash32(value ^ as_type<uint>(agent.junctionChemistry.x) ^
        as_type<uint>(agent.junctionChemistry.y));
    value = hash32(value ^ as_type<uint>(resonance.mechanics.x) ^
        as_type<uint>(resonance.mechanics.y));
    value = hash32(value ^ as_type<uint>(development.mechanochemistryA.x) ^
        as_type<uint>(development.mechanochemistryB.y));
    value = hash32(value ^ as_type<uint>(development.morphogenKinetics.x) ^
        as_type<uint>(development.morphogenTransport.z));
    value = hash32(value ^ as_type<uint>(development.junctionMaterial.x) ^
        as_type<uint>(development.chemicalResponse.y));
    value = hash32(value ^ as_type<uint>(development.morphogenesisA.z) ^
        as_type<uint>(development.morphogenesisB.w));
    value = hash32(value ^ as_type<uint>(development.turnoverControl.x) ^
        as_type<uint>(development.allocationControl.z));
    value = hash32(value ^ as_type<uint>(development.materialSynthesis.y) ^
        as_type<uint>(development.plasticityControl.w));
    return value;
}

inline void initializeFounderRegulatoryGenome(
    device ProgramExpressionCache* genomes,
    uint programIndex,
    AgentState agent,
    uint seed
) {
    ProgramExpressionCache genome = emptyProgramExpressionCache();
    genome.pageSummary = uint4(8u, 7u, hash32(seed ^ 0x811c9dc5u), 0u);
    genome.mutation.z = 0.010 + agent.dynamicExpression.y * 0.26;
    genome.mutation.w = 0.016 + agent.dynamicExpression.y * 0.38;
    genome.mechanochemistryA = clamp(float4(
        0.74 + agent.metabolicExpression.z * 0.58,
        0.68 + agent.metabolicExpression.y * 0.64,
        0.72 + agent.metabolicExpression.x * 0.56,
        0.68 + agent.metabolicExpression.w * 0.66
    ) + randomSigned4(seed + 409u) * 0.10, float4(0.25), float4(2.25));
    genome.mechanochemistryB = clamp(float4(
        0.72 + agent.dynamicExpression.x * 0.54,
        0.64 + agent.metabolicExpression.z * 0.82,
        0.24 + agent.metabolicExpression.y * 0.26,
        0.66 + agent.dynamicExpression.z * 0.62
    ) + randomSigned4(seed + 413u) * 0.10, float4(0.10), float4(2.50));
    genome.morphogenKinetics = clamp(float4(
        0.22 + agent.metabolicExpression.y * 0.30,
        0.20 + agent.metabolicExpression.z * 0.30,
        0.12 + agent.dynamicExpression.x * 0.24,
        0.11 + agent.dynamicExpression.z * 0.24
    ) + randomSigned4(seed + 429u) * 0.045, float4(0.035), float4(0.85));
    genome.morphogenTransport = clamp(float4(
        0.60 + agent.transportExpression.x * 0.75,
        0.60 + agent.transportExpression.y * 0.75,
        0.20 + agent.metabolicExpression.y * 0.55,
        0.16 + agent.metabolicExpression.z * 0.55
    ) + randomSigned4(seed + 433u) * 0.075, float4(0.05), float4(1.80));
    genome.junctionMaterial = clamp(float4(
        0.38 + agent.metabolicExpression.y * 0.62,
        0.22 + agent.metabolicExpression.z * 0.56,
        0.20 + agent.dynamicExpression.x * 0.58,
        0.24 + agent.junctionChemistry.y * 0.62
    ) + randomSigned4(seed + 437u) * 0.08, float4(0.05), float4(1.40));
    genome.chemicalResponse = clamp(float4(
        0.12 + agent.metabolicExpression.w * 0.58,
        0.10 + agent.transportExpression.z * 0.64,
        0.10 + agent.metabolicExpression.z * 0.60,
        0.14 + agent.dynamicExpression.x * 0.58
    ) + randomSigned4(seed + 441u) * 0.08, float4(0.0), float4(1.0));
    genome.morphogenesisA = clamp(float4(
        0.52 + agent.dynamicExpression.z * 0.46,
        1.25 + agent.transportExpression.w * 3.60,
        0.40 + agent.junctionChemistry.y * 0.52,
        0.38 + agent.metabolicExpression.z * 0.74
    ) + randomSigned4(seed + 445u) * float4(0.10, 0.52, 0.12, 0.14),
        float4(0.05, 0.50, 0.0, 0.10), float4(1.50, 8.00, 1.0, 2.00));
    genome.morphogenesisB = clamp(float4(
        0.44 + agent.dynamicExpression.x * 0.70,
        0.24 + agent.metabolicExpression.y * 0.54,
        0.54 + agent.metabolicExpression.w * 0.38,
        0.42 + agent.dynamicExpression.z * 0.66
    ) + randomSigned4(seed + 449u) * 0.10,
        float4(0.10, 0.05, 0.0, 0.0), float4(2.00, 1.50, 1.0, 2.00));
    genome.turnoverControl = clamp(float4(
        0.62 + agent.dynamicExpression.x * 0.92,
        0.28 + agent.metabolicExpression.y * 0.34,
        0.82 + agent.metabolicExpression.w * 0.74,
        0.18 + agent.dynamicExpression.y * 4.8
    ) + randomSigned4(seed + 453u) * float4(0.12, 0.055, 0.12, 0.10),
        float4(0.25, 0.20, 0.58, 0.05), float4(2.20, 0.82, 1.90, 1.80));
    genome.allocationControl = clamp(float4(
        0.42 + agent.metabolicExpression.w * 0.92,
        0.24 + agent.dynamicExpression.z * 0.66,
        0.34 + agent.metabolicExpression.y * 0.78,
        0.38 + agent.dynamicExpression.x * 0.82
    ) + randomSigned4(seed + 457u) * 0.10, float4(0.0), float4(2.0));
    genome.materialSynthesis = clamp(float4(
        0.18 + agent.metabolicExpression.y * 0.74,
        0.16 + agent.transportExpression.x * 0.42 + agent.transportExpression.y * 0.32,
        0.14 + agent.transportExpression.z * 0.82,
        0.16 + agent.metabolicExpression.w * 0.72
    ) + randomSigned4(seed + 461u) * 0.09, float4(0.0), float4(1.60));
    genome.plasticityControl = clamp(float4(
        0.20 + agent.metabolicExpression.z * 0.74,
        0.16 + agent.dynamicExpression.x * 0.68,
        0.18 + agent.metabolicExpression.w * 0.58,
        0.10 + agent.junctionChemistry.y * 0.62
    ) + randomSigned4(seed + 465u) * 0.08, float4(0.0), float4(1.60));
    genomes[programIndex] = genome;
}

inline float mutateScalar(
    float value, uint seed, float amount, float lower, float upper
) {
    return clamp(value + signedRandom(seed) * amount, lower, upper);
}

inline float mutateProgramExpressionCache(
    device ProgramExpressionCache* genomes,
    uint parentProgram,
    uint childProgram,
    uint seed,
    float mutation,
    bool branchMutation
) {
    ProgramExpressionCache parent = genomes[parentProgram];
    ProgramExpressionCache child = parent;
    float amplitude = clamp(
        mutation * (branchMutation ? 1.35 : 0.55), 0.001, 0.20
    );
    child.mechanochemistryA = clamp(
        child.mechanochemistryA + randomSigned4(seed + 5u) * amplitude,
        float4(0.05), float4(3.0)
    );
    child.mechanochemistryB = clamp(
        child.mechanochemistryB + randomSigned4(seed + 7u) * amplitude,
        float4(0.05), float4(3.0)
    );
    child.morphogenKinetics = clamp(
        child.morphogenKinetics + randomSigned4(seed + 11u) * amplitude,
        float4(0.005), float4(2.0)
    );
    child.morphogenTransport = clamp(
        child.morphogenTransport + randomSigned4(seed + 13u) * amplitude,
        float4(0.005), float4(2.5)
    );
    child.junctionMaterial = clamp(
        child.junctionMaterial + randomSigned4(seed + 17u) * amplitude,
        float4(0.01), float4(2.0)
    );
    child.chemicalResponse = clamp(
        child.chemicalResponse + randomSigned4(seed + 19u) * amplitude,
        float4(0.0), float4(2.0)
    );
    child.morphogenesisA = clamp(
        child.morphogenesisA + randomSigned4(seed + 23u) * amplitude,
        float4(0.01), float4(8.0)
    );
    child.morphogenesisB = clamp(
        child.morphogenesisB + randomSigned4(seed + 29u) * amplitude,
        float4(0.0), float4(3.0)
    );
    child.turnoverControl = clamp(
        child.turnoverControl + randomSigned4(seed + 31u) * amplitude,
        float4(0.0), float4(3.0)
    );
    child.allocationControl = clamp(
        child.allocationControl + randomSigned4(seed + 37u) * amplitude,
        float4(0.0), float4(3.0)
    );
    child.materialSynthesis = clamp(
        child.materialSynthesis + randomSigned4(seed + 41u) * amplitude,
        float4(0.0), float4(2.0)
    );
    child.plasticityControl = clamp(
        child.plasticityControl + randomSigned4(seed + 43u) * amplitude,
        float4(0.0), float4(2.0)
    );
    float distance = length(child.mechanochemistryA - parent.mechanochemistryA) +
        length(child.morphogenesisA - parent.morphogenesisA);
    child.mutation.x = parent.mutation.x + distance;
    child.mutation.y = distance;
    child.pageSummary = uint4(
        parent.pageSummary.x + 1u,
        parent.pageSummary.y + (branchMutation ? 2u : 1u),
        hash32(parent.pageSummary.z ^ seed),
        parent.pageSummary.w + 1u
    );
    genomes[childProgram] = child;
    return distance;
}

struct RegulatoryOutputs {
    float4 a;
    float4 b;
    float4 c;
};

inline RegulatoryOutputs evolveDevelopmentalProgram(
    device const GenomeHeader* headers,
    device const GenomePage* pages,
    device float* regulatoryStates,
    uint programIndex,
    uint cellIndex,
    thread const float* sensors,
    uint relaxationSpan
) {
    float actuators[regulatoryStateChannelCount];
    float weights[regulatoryStateChannelCount];
    uint stateBase = cellIndex * regulatoryStateChannelCount;
    for (uint actuator = 0u; actuator < regulatoryStateChannelCount; ++actuator) {
        actuators[actuator] = regulatoryStates[stateBase + actuator] * 2.0 - 1.0;
        weights[actuator] = 1.0;
    }
    if (programIndex < maxGenomeHeaderCount) {
        uint page = headers[programIndex].firstPage;
        uint traversed = 0u;
        while (page < genomePageCapacity && traversed < 512u) {
            GenomePage candidate = pages[page];
            if (candidate.header.x == genomePageRegulation) {
                for (uint module = 0u; module < 15u; ++module) {
                    float4 rule = candidate.payload[module];
                    uint sensorIndex = min(
                        uint(fract(abs(rule.x)) * 24.0), 23u
                    );
                    uint actuator = min(
                        uint(fract(abs(rule.w)) *
                            float(regulatoryStateChannelCount)),
                        regulatoryStateChannelCount - 1u
                    );
                    float drive = sensors[sensorIndex] * clamp(rule.y, -3.0, 3.0) +
                        clamp(rule.z, -2.0, 2.0);
                    actuators[actuator] += drive;
                    weights[actuator] += abs(rule.y) + 0.25;
                }
            }
            page = candidate.header.y;
            ++traversed;
        }
    }
    float retained = pow(0.94, float(max(relaxationSpan, 1u)));
    for (uint actuator = 0u; actuator < regulatoryStateChannelCount; ++actuator) {
        float target = saturate(
            0.5 + 0.5 * tanh(actuators[actuator] / weights[actuator])
        );
        float updated = mix(target, regulatoryStates[stateBase + actuator], retained);
        regulatoryStates[stateBase + actuator] = updated;
        actuators[actuator] = updated;
    }
    RegulatoryOutputs output;
    output.a = float4(actuators[0], actuators[1], actuators[2], actuators[3]);
    output.b = float4(actuators[4], actuators[5], actuators[6], actuators[7]);
    output.c = float4(actuators[8], actuators[9], actuators[10], actuators[11]);
    return output;
}

inline void recordLineageEvent(
    device LineageEventRecord* events,
    device atomic_uint* identityCounters,
    uint kind,
    AgentState agent,
    ProgramExpressionCache genome,
    ResonanceExpressionCache resonance,
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
    event.topologyHash = genome.pageSummary.z;
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
        maxGenomeHeaderCount, 0u
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
    ProgramLineageRecord program,
    ProgramExpressionCache genome,
    ResonanceExpressionCache resonance,
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
    event.topologyHash = genome.pageSummary.z;
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
        program.secondParentProgramIndex < maxGenomeHeaderCount;
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

#include "QuantumChemistry.metalh"
#include "GenomeCells.metalh"
#include "GenomeObservation.metalh"
#include "BodyComponents.metalh"
#include "MolecularExpression.metalh"
#include "CellPhysiology.metalh"
#include "ContactTopology.metalh"
#include "SimulationAudits.metalh"
#include "ObserverCompaction.metalh"
#include "WorldRendering.metalh"
#include "CellRendering.metalh"
#include "UnifiedEcology.metalh"
