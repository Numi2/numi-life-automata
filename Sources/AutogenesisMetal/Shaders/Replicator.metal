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

constant uint metricCount = 32;
constant float metricScale = 4096.0;
constant uint quantumGridSize = 1024u;
constant uint maxAgentCount = 384u;
constant uint cellsPerAgent = 24u;
constant uint maxCellCount = maxAgentCount * cellsPerAgent;
constant uint regulatoryNodeCapacity = 16u;
constant uint regulatoryEdgeCapacity = 48u;
constant uint membraneVertexCount = 12u;
constant uint lineageEventCapacity = 4096u;
constant int mechanicalForceScale = 1048576;

struct AgentState {
    float2 position;
    float2 velocity;
    float4 behavior;
    float4 geneA;
    float4 geneB;
    float4 geneC;
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
    uint reserved;
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
};

struct CellAggregate {
    // Active cell count, mean ATP, mean membrane integrity, mean stress.
    float4 physiology;
    // Centroid, root-mean-square radius, dividing-cell fraction.
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
};

struct DevelopmentalGenome {
    // Active nodes, active edges, topology hash, and cumulative structural mutations.
    uint4 topology;
    // Cumulative distance, last mutation distance, node rate, and edge rate.
    float4 mutation;
    // Basal drive for the eight stable actuator channels.
    float4 actuatorBiasA;
    float4 actuatorBiasB;
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

struct MembraneVertex {
    float2 position;
    float2 velocity;
    // Rest edge length, local integrity, contact pressure, and local strain.
    float4 mechanics;
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

inline float4 randomSigned4(uint seed) {
    return float4(
        signedRandom(seed), signedRandom(seed + 1u),
        signedRandom(seed + 2u), signedRandom(seed + 3u)
    );
}

inline DevelopmentalGenome emptyDevelopmentalGenome() {
    DevelopmentalGenome genome;
    genome.topology = uint4(0u);
    genome.mutation = float4(0.0, 0.0, 0.018, 0.032);
    genome.actuatorBiasA = float4(-0.20, -0.08, -0.16, -0.05);
    genome.actuatorBiasB = float4(-0.22, -0.28, -0.30, -0.18);
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

inline uint agentGenomeHash(AgentState agent, uint regulatoryHash, ResonanceGenome resonance) {
    uint value = regulatoryHash;
    value = hash32(value ^ as_type<uint>(agent.geneA.x) ^ as_type<uint>(agent.geneA.y));
    value = hash32(value ^ as_type<uint>(agent.geneB.z) ^ as_type<uint>(agent.geneC.w));
    value = hash32(value ^ as_type<uint>(resonance.mechanics.x) ^ as_type<uint>(resonance.mechanics.y));
    return value;
}

inline void initializeFounderRegulatoryGenome(
    device DevelopmentalGenome* genomes,
    device RegulatoryNode* nodes,
    device RegulatoryEdge* edges,
    device atomic_uint* identityCounters,
    uint owner,
    AgentState agent,
    uint seed
) {
    uint nodeBase = owner * regulatoryNodeCapacity;
    uint edgeBase = owner * regulatoryEdgeCapacity;
    for (uint index = 0u; index < regulatoryNodeCapacity; ++index) {
        nodes[nodeBase + index] = emptyRegulatoryNode();
    }
    for (uint index = 0u; index < regulatoryEdgeCapacity; ++index) {
        edges[edgeBase + index] = emptyRegulatoryEdge();
    }

    for (uint index = 0u; index < 8u; ++index) {
        RegulatoryNode node = emptyRegulatoryNode();
        node.bias = -0.42 + random01(seed + index * 17u) * 0.54;
        node.responseRate = clamp(0.012 + random01(seed + index * 19u + 1u) * 0.050, 0.004, 0.095);
        node.sensorWeight = 0.52 + random01(seed + index * 23u + 2u) * 0.92;
        if (index == 2u || index == 3u) { node.sensorWeight *= -0.72; }
        node.outputWeight = 0.72 + random01(seed + index * 29u + 3u) * 0.52;
        node.sensorIndex = index;
        node.actuatorMask = 1u << index;
        if (index == 0u) { node.actuatorMask |= 1u << 4u; }
        if (index == 2u) { node.actuatorMask |= 1u << 7u; }
        node.innovationID = atomic_fetch_add_explicit(&identityCounters[1], 1u, memory_order_relaxed);
        node.flags = 1u;
        nodes[nodeBase + index] = node;
    }

    for (uint index = 0u; index < 14u; ++index) {
        RegulatoryEdge edge = emptyRegulatoryEdge();
        edge.source = index % 8u;
        edge.target = (index * 3u + 1u) % 8u;
        edge.weight = signedRandom(seed + 101u + index * 7u) * 1.18;
        if (index < 4u) { edge.weight = 0.42 + random01(seed + 201u + index) * 0.72; }
        edge.plasticity = signedRandom(seed + 301u + index) * 0.025;
        edge.innovationID = atomic_fetch_add_explicit(&identityCounters[1], 1u, memory_order_relaxed);
        edge.flags = 1u;
        edges[edgeBase + index] = edge;
    }

    DevelopmentalGenome genome = emptyDevelopmentalGenome();
    genome.topology = uint4(8u, 14u, 0u, 0u);
    genome.mutation.z = 0.010 + agent.geneB.y * 0.26;
    genome.mutation.w = 0.016 + agent.geneB.y * 0.38;
    genome.actuatorBiasA += randomSigned4(seed + 401u) * 0.08;
    genome.actuatorBiasB += randomSigned4(seed + 405u) * 0.08;
    genomes[owner] = genome;
    genome.topology.z = topologyHash(nodes, edges, owner);
    genomes[owner] = genome;
}

inline float mutateScalar(float value, uint seed, float amount, float lower, float upper) {
    return clamp(value + signedRandom(seed) * amount, lower, upper);
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
    uint structuralChanges = 0u;
    bool structuralMutation = branchMutation || random01(seed + 719u) < child.mutation.w;
    if (structuralMutation) {
        uint operation = hash32(seed + 727u) % 5u;
        if (operation == 0u) {
            uint sourceSlot = hash32(seed + 733u) % regulatoryNodeCapacity;
            uint targetSlot = regulatoryNodeCapacity;
            for (uint index = 0u; index < regulatoryNodeCapacity; ++index) {
                if ((mutableNodes[childNodeBase + index].flags & 1u) == 0u) { targetSlot = index; break; }
            }
            if (targetSlot < regulatoryNodeCapacity &&
                (mutableNodes[childNodeBase + sourceSlot].flags & 1u) != 0u) {
                RegulatoryNode duplicate = mutableNodes[childNodeBase + sourceSlot];
                duplicate.bias = mutateScalar(duplicate.bias, seed + 739u, 0.22, -3.0, 3.0);
                duplicate.sensorIndex = random01(seed + 743u) < 0.54 ? duplicate.sensorIndex : 8u;
                duplicate.actuatorMask = random01(seed + 747u) < 0.60
                    ? duplicate.actuatorMask : (1u << (hash32(seed + 751u) & 7u));
                duplicate.innovationID = atomic_fetch_add_explicit(
                    &identityCounters[1], 1u, memory_order_relaxed
                );
                mutableNodes[childNodeBase + targetSlot] = duplicate;
                structuralChanges += 1u;
            }
        } else if (operation == 1u && child.topology.x > 4u) {
            uint slot = hash32(seed + 757u) % regulatoryNodeCapacity;
            if ((mutableNodes[childNodeBase + slot].flags & 1u) != 0u) {
                mutableNodes[childNodeBase + slot].flags = 0u;
                structuralChanges += 1u;
            }
        } else {
            uint slot = hash32(seed + 761u) % regulatoryEdgeCapacity;
            RegulatoryEdge edge = mutableEdges[childEdgeBase + slot];
            if (operation == 2u || (edge.flags & 1u) == 0u) {
                edge.source = hash32(seed + 769u) % regulatoryNodeCapacity;
                edge.target = hash32(seed + 773u) % regulatoryNodeCapacity;
                if ((mutableNodes[childNodeBase + edge.source].flags & 1u) != 0u &&
                    (mutableNodes[childNodeBase + edge.target].flags & 1u) != 0u) {
                    edge.weight = signedRandom(seed + 779u) * 1.4;
                    edge.plasticity = signedRandom(seed + 787u) * 0.04;
                    edge.innovationID = atomic_fetch_add_explicit(
                        &identityCounters[1], 1u, memory_order_relaxed
                    );
                    edge.flags = 1u;
                    structuralChanges += 1u;
                }
            } else if (operation == 3u) {
                edge.flags = 0u;
                structuralChanges += 1u;
            } else if (operation == 4u) {
                edge.source = hash32(seed + 797u) % regulatoryNodeCapacity;
                edge.target = hash32(seed + 809u) % regulatoryNodeCapacity;
                edge.innovationID = atomic_fetch_add_explicit(
                    &identityCounters[1], 1u, memory_order_relaxed
                );
                edge.flags = ((mutableNodes[childNodeBase + edge.source].flags & 1u) != 0u &&
                    (mutableNodes[childNodeBase + edge.target].flags & 1u) != 0u) ? 1u : 0u;
                structuralChanges += edge.flags & 1u;
            }
            mutableEdges[childEdgeBase + slot] = edge;
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
        drive[index] = node.bias;
        if ((node.flags & 1u) != 0u && node.sensorIndex < 8u) {
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
        aggregate.physiology.x / float(cellsPerAgent),
        aggregate.morphology.z,
        aggregate.shape.z,
        aggregate.dynamics.y
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
    float carrier = (uv.x * 31.0 + uv.y * 17.0) * M_PI_F;
    float relativePhase = (uv.y - 0.5) * 22.0 * M_PI_F;
    float2 leftAmplitude = leftPacket * float2(cos(carrier), sin(carrier));
    float2 rightAmplitude = rightPacket * float2(
        cos(carrier + relativePhase),
        sin(carrier + relativePhase)
    );
    float2 superposition = (leftAmplitude + rightAmplitude) * normalization;
    quantumOut.write(float4(superposition * 0.9238795, superposition * 0.3826834), gid);
}

kernel void evolveQuantumField(
    texture2d<float, access::read> quantumIn [[texture(0)]],
    texture2d_array<float, access::read> state [[texture(1)]],
    texture2d_array<float, access::read> genomeA [[texture(2)]],
    texture2d_array<float, access::read> ecology [[texture(3)]],
    texture2d<float, access::write> quantumOut [[texture(4)]],
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
    float4 stateA = state.read(bioA, 0);
    float4 stateB = state.read(bioB, 0);
    float4 geneAValue = genomeA.read(bioA, 0);
    float4 geneBValue = genomeA.read(bioB, 0);
    float thetaA = 0.18 + 0.16 * saturate(stateA.w * 4.0) + 0.06 * geneAValue.y;
    float thetaB = 0.18 + 0.16 * saturate(stateB.w * 4.0) + 0.06 * geneBValue.y;
    float4 coinA = quantumCoin(quantumIn.read(sourceA), thetaA);
    float4 coinB = quantumCoin(quantumIn.read(sourceB), thetaB);
    float4 shifted = float4(coinA.xy, coinB.zw);

    uint2 bio = min(
        gid * biologicalSize / quantumGridSize,
        biologicalMax
    );
    float4 localState = state.read(bio, 0);
    float4 localEcology = ecology.read(bio, 0);
    float potential = 0.012 * (
        localState.x + localEcology.x * 0.8 + localState.y * 2.2 +
        localState.w * 3.0 + localEcology.z * 1.4
    );
    float phaseCosine = cos(potential);
    float phaseSine = sin(potential);
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

    float centralDeposit = exp(-dot(uv - 0.5, uv - 0.5) / 0.0018);
    nutrientDeposit = max(nutrientDeposit, centralDeposit * 0.88);
    mineralDeposit = max(mineralDeposit, centralDeposit * 0.62);
    toxicVent *= 1.0 - centralDeposit;
    rock *= (1.0 - centralDeposit) * (1.0 - saturate(max(nutrientDeposit, mineralDeposit) * 0.82));
    return saturate(float4(nutrientDeposit, mineralDeposit, toxicVent, rock));
}

kernel void initializeWorld(
    texture2d_array<float, access::write> stateOut [[texture(0)]],
    texture2d_array<float, access::write> genomeAOut [[texture(1)]],
    texture2d_array<float, access::write> genomeBOut [[texture(2)]],
    texture2d_array<float, access::write> ecologyOut [[texture(3)]],
    texture2d_array<float, access::write> genomeCOut [[texture(4)]],
    texture2d_array<float, access::write> eventOut [[texture(5)]],
    texture2d_array<float, access::write> environmentOut [[texture(6)]],
    constant SimulationUniforms& uniforms [[buffer(0)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height || gid.z >= uniforms.worldCount) { return; }

    float2 uv = (float2(gid.xy) + 0.5) / float2(uniforms.width, uniforms.height);
    float4 geneA = float4(0.50);
    float4 geneB = float4(0.50, 0.012, 0.50, 0.50);
    float4 geneC = float4(0.40, 0.40, 0.20, 0.02);
    float4 geology = geologyAt(uv, gid.z * 13u);
    float resourceA = 0.006 + geology.x * 0.94;
    float resourceB = 0.004 + geology.y * 0.82;

    stateOut.write(float4(resourceA, 0.0, 0.0, 0.0), gid.xy, gid.z);
    genomeAOut.write(geneA, gid.xy, gid.z);
    genomeBOut.write(geneB, gid.xy, gid.z);
    ecologyOut.write(float4(resourceB, 0.008, geology.z * 0.10, 0.0), gid.xy, gid.z);
    genomeCOut.write(geneC, gid.xy, gid.z);
    eventOut.write(float4(0.0), gid.xy, gid.z);
    environmentOut.write(geology, gid.xy, gid.z);
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
        return;
    }

    uint seed = hash32(
        gid.x * 73856093u ^ gid.y * 19349663u ^
        expansionLevel * 83492791u ^ gid.z * 2654435761u
    );
    float4 geology = geologyAt(uv, expansionLevel * 17u + gid.z * 13u);
    float resourceA = 0.006 + geology.x * 0.94;
    float resourceB = 0.004 + geology.y * 0.82;
    stateOut.write(float4(resourceA, 0.0, 0.0, 0.0), gid.xy, gid.z);
    genomeAOut.write(float4(0.5), gid.xy, gid.z);
    genomeBOut.write(float4(0.5, 0.02, 0.5, random01(seed + 3u)), gid.xy, gid.z);
    ecologyOut.write(float4(resourceB, 0.008, geology.z * 0.10, 0.0), gid.xy, gid.z);
    genomeCOut.write(float4(0.5, 0.5, 0.5, 0.0), gid.xy, gid.z);
    eventOut.write(float4(0.0), gid.xy, gid.z);
    environmentOut.write(geology, gid.xy, gid.z);
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
    float obstacle = smoothstep(0.45, 0.88, environment.read(gid.xy, gid.z).w);
    float stiffness = mix(0.105, 0.030, obstacle);
    float damping = mix(0.965, 0.78, obstacle);
    float2 velocity = (center.zw + displacementLaplacian * stiffness + activeForce * 0.24) * damping;
    float2 uv = (float2(gid.xy) + 0.5) / float2(uniforms.width, uniforms.height);
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
    constant SimulationUniforms& uniforms [[buffer(0)]],
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
    uint2 cardinalCoordinates[4] = {
        uint2(left, gid.y), uint2(right, gid.y), uint2(gid.x, down), uint2(gid.x, up)
    };

    float resourceLaplacian = 0.0;
    float4 chemistryLaplacian = float4(0.0);
    float4 eventLaplacian = float4(0.0);
    for (uint index = 0; index < 4; ++index) {
        uint2 coordinate = cardinalCoordinates[index];
        resourceLaplacian += stateIn.read(coordinate, layer).x - center.x;
        chemistryLaplacian += ecologyIn.read(coordinate, layer) - chemistry;
        eventLaplacian += eventIn.read(coordinate, layer) - priorEvents;
    }

    float obstacle = smoothstep(0.48, 0.84, geology.w);
    float permeability = 1.0 - obstacle * 0.88;
    float resourceA = max(0.0, center.x + uniforms.dt * 0.18 * permeability * resourceLaplacian);
    float resourceB = max(0.0, chemistry.x + uniforms.dt * 0.15 * permeability * chemistryLaplacian.x);
    float detritus = max(0.0, chemistry.y + uniforms.dt * 0.10 * chemistryLaplacian.y);
    float toxin = max(0.0, chemistry.z + uniforms.dt * 0.16 * chemistryLaplacian.z);
    float catalyst = max(0.0, chemistry.w + uniforms.dt * 0.08 * chemistryLaplacian.w);
    resourceA += uniforms.dt * uniforms.resourceFlux * (0.00008 + geology.x * 0.030) * permeability * max(0.0, 1.1 - resourceA);
    resourceB += uniforms.dt * uniforms.resourceFlux * (0.00006 + geology.y * 0.028) * permeability * max(0.0, 1.1 - resourceB);
    toxin += uniforms.dt * geology.z * 0.0045;
    toxin *= 1.0 - uniforms.dt * (0.052 + (1.0 - geology.z) * 0.040);
    catalyst *= 1.0 - uniforms.dt * 0.032;

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
        preyOpportunity += neighborState.y * difference * 0.125;
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
        float uptakeRate = (0.018 + 0.075 * geneA.x) * interference * (1.0 + catalyst * 0.14);
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
            0.0030 * neighborOccupancy
        );
        energy = max(energy - maintenance, 0.0);
        float reserve = biomass * (0.025 + 0.10 * geneB.x);
        float habitatCapacity = 1.20 * permeability;
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
}

inline float2 damageCenter(uint world, uint generation) {
    uint seed = hash32(world * 0x9e3779b9u + generation * 0x85ebca6bu + 71u);
    return float2(0.2 + 0.6 * random01(seed + 1u), 0.2 + 0.6 * random01(seed + 2u));
}

kernel void damageWorld(
    texture2d_array<float, access::read_write> state [[texture(0)]],
    texture2d_array<float, access::read_write> ecology [[texture(1)]],
    texture2d_array<float, access::read_write> events [[texture(2)]],
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
    float trophicActivity = active * saturate(niche.w * 0.7 + niche.z * localChemistry.y * 0.8 + localChemistry.z * 0.2);
    uint lineageBin = min(uint(fract(genomeB.read(gid.xy, layer).w) * 16.0), 15u);

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
    addBinnedMetric(groupMetrics, 16 + lineageBin, active);

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
    return cell;
}

inline void seedOrganismCells(
    device CellState* cells,
    device atomic_uint* cellOccupancy,
    device CellAggregate* aggregates,
    device float* regulatoryStates,
    uint owner,
    AgentState agent,
    uint seed,
    ResonanceGenome resonanceGenome
) {
    uint base = owner * cellsPerAgent;
    for (uint localIndex = 0u; localIndex < cellsPerAgent; ++localIndex) {
        uint index = base + localIndex;
        if (localIndex == 0u) {
            cells[index] = founderCell(agent, resonanceGenome, seed);
            atomic_store_explicit(&cellOccupancy[index], 1u, memory_order_relaxed);
        } else {
            cells[index] = emptyCell();
            atomic_store_explicit(&cellOccupancy[index], 0u, memory_order_relaxed);
        }
        uint stateBase = index * regulatoryNodeCapacity;
        for (uint node = 0u; node < regulatoryNodeCapacity; ++node) {
            regulatoryStates[stateBase + node] = 0.0;
        }
    }
    CellState founder = cells[base];
    CellAggregate aggregate;
    aggregate.physiology = float4(1.0, founder.physiology.x, founder.physiology.w, founder.signals.z);
    aggregate.morphology = float4(0.0, 0.0, 0.0, 0.0);
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
    aggregates[owner] = aggregate;
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
    agent.reserved = 0u;
    agents[gid] = agent;
    atomic_store_explicit(&occupancy[gid], 0u, memory_order_relaxed);
    uint base = gid * cellsPerAgent;
    for (uint localIndex = 0u; localIndex < cellsPerAgent; ++localIndex) {
        uint cellIndex = base + localIndex;
        cells[cellIndex] = emptyCell();
        atomic_store_explicit(&cellOccupancy[cellIndex], 0u, memory_order_relaxed);
        uint stateBase = cellIndex * regulatoryNodeCapacity;
        for (uint node = 0u; node < regulatoryNodeCapacity; ++node) {
            regulatoryStates[stateBase + node] = 0.0;
        }
        uint membraneBase = cellIndex * membraneVertexCount;
        for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
            membraneVertices[membraneBase + vertexIndex] = emptyMembraneVertex();
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
    cellAggregates[gid] = aggregate;
    developmentalGenomes[gid] = emptyDevelopmentalGenome();
    resonanceGenomes[gid] = emptyResonanceGenome();
    uint nodeBase = gid * regulatoryNodeCapacity;
    for (uint node = 0u; node < regulatoryNodeCapacity; ++node) {
        regulatoryNodes[nodeBase + node] = emptyRegulatoryNode();
    }
    uint edgeBase = gid * regulatoryEdgeCapacity;
    for (uint edge = 0u; edge < regulatoryEdgeCapacity; ++edge) {
        regulatoryEdges[edgeBase + edge] = emptyRegulatoryEdge();
    }
    for (uint event = gid; event < lineageEventCapacity; event += maxAgentCount) {
        LineageEventRecord record;
        record.sequence = 0u;
        lineageEvents[event] = record;
    }
    if (gid == 0u) {
        atomic_store_explicit(&identityCounters[0], 1u, memory_order_relaxed);
        atomic_store_explicit(&identityCounters[1], 1u, memory_order_relaxed);
        atomic_store_explicit(&identityCounters[2], 0u, memory_order_relaxed);
        atomic_store_explicit(&identityCounters[3], 0u, memory_order_relaxed);
    }
}

kernel void collectAgentObservations(
    device const AgentState* agents [[buffer(0)]],
    device const atomic_uint* occupancy [[buffer(1)]],
    device AgentObservationRecord* observations [[buffer(2)]],
    device const CellAggregate* cellAggregates [[buffer(3)]],
    device const DevelopmentalGenome* developmentalGenomes [[buffer(4)]],
    device const ResonanceGenome* resonanceGenomes [[buffer(5)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= maxAgentCount) { return; }
    uint occupied = atomic_load_explicit(&occupancy[gid], memory_order_relaxed);
    AgentState agent = agents[gid];
    AgentObservationRecord observation;
    observation.position = agent.position;
    observation.generation = agent.generation;
    observation.flags = occupied != 0u ? (1u | (agent.geneC.w >= 0.08 ? 2u : 0u)) : 0u;
    observation.birthID = agent.birthID;
    observation.parentBirthID = agent.parentBirthID;
    observation.genomeHash = agent.genomeHash;
    observation.topologyHash = developmentalGenomes[gid].topology.z;
    CellAggregate aggregate = cellAggregates[gid];
    observation.morphology = float4(
        aggregate.physiology.x / float(cellsPerAgent),
        aggregate.morphology.z,
        aggregate.shape.z,
        aggregate.morphology.w
    );
    observation.dynamics = float4(
        resonanceGenomes[gid].mechanics.x,
        aggregate.resonance.y,
        aggregate.dynamics.y,
        aggregate.mechanics.y
    );
    observation.mutationDistance = agent.mutationDistance;
    observation.padding = float3(0.0);
    observations[gid] = observation;
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
    founder.birthID = atomic_fetch_add_explicit(&identityCounters[0], 1u, memory_order_relaxed);
    founder.parentBirthID = 0xffffffffu;
    founder.birthStep = uniforms.step;
    founder.mutationDistance = 0.0;
    founder.lastMutationDistance = 0.0;
    founder.lineageFlags = 1u;
    founder.reserved = 0u;
    initializeFounderRegulatoryGenome(
        developmentalGenomes, regulatoryNodes, regulatoryEdges, identityCounters,
        0u, founder, founderSeed
    );
    ResonanceGenome resonance = founderResonanceGenome(founder, founderSeed ^ 0x92d68ca2u);
    resonanceGenomes[0] = resonance;
    founder.genomeHash = agentGenomeHash(founder, developmentalGenomes[0].topology.z, resonance);
    agents[0] = founder;
    seedOrganismCells(
        cells, cellOccupancy, cellAggregates, regulatoryStates,
        0u, founder, founderSeed, resonance
    );
    recordLineageEvent(
        lineageEvents, identityCounters, 1u, founder, developmentalGenomes[0],
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
    texture2d_array<float, access::read> state [[texture(0)]],
    texture2d_array<float, access::read> ecology [[texture(1)]],
    texture2d_array<float, access::read> environment [[texture(2)]],
    texture2d_array<float, access::read> mechanicalField [[texture(3)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= maxAgentCount) { return; }
    AgentState agent = agentsIn[gid];
    if (atomic_load_explicit(&occupancy[gid], memory_order_relaxed) == 0u) {
        agentsOut[gid] = agent;
        return;
    }

    uint2 coordinate = min(
        uint2(fract(agent.position) * float2(uniforms.width, uniforms.height)),
        uint2(uniforms.width - 1u, uniforms.height - 1u)
    );
    int2 p = int2(coordinate);
    uint2 left = uint2(wrapped(p + int2(-2, 0), uniforms.width, uniforms.height));
    uint2 right = uint2(wrapped(p + int2(2, 0), uniforms.width, uniforms.height));
    uint2 down = uint2(wrapped(p + int2(0, -2), uniforms.width, uniforms.height));
    uint2 up = uint2(wrapped(p + int2(0, 2), uniforms.width, uniforms.height));
    float4 localState = state.read(coordinate, 0);
    float4 localEcology = ecology.read(coordinate, 0);
    float4 localEnvironment = environment.read(coordinate, 0);
    CellAggregate cellAggregate = cellAggregates[gid];
    float2 nutrientGradient = float2(
        state.read(right, 0).x - state.read(left, 0).x,
        state.read(up, 0).x - state.read(down, 0).x
    );
    float2 mineralGradient = float2(
        ecology.read(right, 0).x - ecology.read(left, 0).x,
        ecology.read(up, 0).x - ecology.read(down, 0).x
    );
    float2 dangerGradient = float2(
        environment.read(right, 0).z + environment.read(right, 0).w -
            environment.read(left, 0).z - environment.read(left, 0).w,
        environment.read(up, 0).z + environment.read(up, 0).w -
            environment.read(down, 0).z - environment.read(down, 0).w
    );
    float mechanicalLeft = length(mechanicalField.read(left, 0).xy) +
        length(mechanicalField.read(left, 0).zw) * 2.0;
    float mechanicalRight = length(mechanicalField.read(right, 0).xy) +
        length(mechanicalField.read(right, 0).zw) * 2.0;
    float mechanicalDown = length(mechanicalField.read(down, 0).xy) +
        length(mechanicalField.read(down, 0).zw) * 2.0;
    float mechanicalUp = length(mechanicalField.read(up, 0).xy) +
        length(mechanicalField.read(up, 0).zw) * 2.0;
    float2 vibrationGradient = float2(
        mechanicalRight - mechanicalLeft,
        mechanicalUp - mechanicalDown
    );

    float spatialScale = 1.0 / max(uniforms.worldScale, 1.0);
    float separationRadius = 0.030 * spatialScale;
    float preySenseRadius = 0.16 * spatialScale;
    float threatSenseRadius = 0.13 * spatialScale;
    float contactRadius = 0.022 * spatialScale;
    float2 separation = float2(0.0);
    float2 preyVector = float2(0.0);
    float2 threatVector = float2(0.0);
    float nearestPrey = 10.0;
    float nearestThreat = 10.0;
    float preyOpportunity = 0.0;
    float incomingAttack = 0.0;
    float crowding = 0.0;
    for (uint otherIndex = 0u; otherIndex < maxAgentCount; ++otherIndex) {
        if (otherIndex == gid || atomic_load_explicit(&occupancy[otherIndex], memory_order_relaxed) == 0u) { continue; }
        AgentState other = agentsIn[otherIndex];
        float2 delta = other.position - agent.position;
        float distance = max(length(delta), 0.0001);
        float difference = saturate(length(agent.geneC - other.geneC) * 0.72 +
            length(agent.geneA - other.geneA) * 0.20);
        if (distance < separationRadius) {
            float proximity = 1.0 - distance / separationRadius;
            separation -= delta / distance * proximity;
            crowding += proximity;
        }
        bool canHunt = agent.geneC.w > 0.08 && difference > 0.035 && other.biomass <= agent.biomass * 1.24;
        if (canHunt && distance < nearestPrey && distance < preySenseRadius) {
            nearestPrey = distance;
            preyVector = delta / distance;
        }
        if (canHunt && distance < contactRadius) {
            preyOpportunity += difference * other.biomass * (1.0 - distance / contactRadius);
        }
        bool isThreat = other.geneC.w > agent.geneC.w + 0.035 && difference > 0.035 &&
            other.biomass > agent.biomass * 0.84;
        if (isThreat && distance < nearestThreat && distance < threatSenseRadius) {
            nearestThreat = distance;
            threatVector = -delta / distance;
        }
        if (isThreat && distance < contactRadius) {
            incomingAttack += other.geneC.w * difference * (1.0 - distance / contactRadius);
        }
    }

    float preySignal = nearestPrey < preySenseRadius
        ? saturate(1.0 - nearestPrey / preySenseRadius)
        : 0.0;
    float threatSignal = nearestThreat < threatSenseRadius
        ? saturate(1.0 - nearestThreat / threatSenseRadius)
        : 0.0;
    agent.behavior = float4(
        preyVector * preySignal,
        saturate(preyOpportunity * 8.0),
        saturate(incomingAttack * 8.0 + threatSignal * 0.35)
    );

    float2 inheritedHeading = normalize(float2(
        cos(agent.geneB.w * 2.0 * M_PI_F), sin(agent.geneB.w * 2.0 * M_PI_F)
    ));
    float2 resourceSteering = nutrientGradient * agent.geneC.x + mineralGradient * agent.geneC.y;
    float2 desiredHeading = inheritedHeading * 0.10 + resourceSteering * 3.1 -
        dangerGradient * (1.2 + agent.geneA.w * 1.6);
    float vibrationPreference = (agent.geneB.x - 0.46) *
        (0.45 + cellAggregate.dynamics.y * 0.55);
    desiredHeading += vibrationGradient * vibrationPreference * 5.4;
    desiredHeading += separation * (0.48 + agent.geneA.z * 0.58);
    desiredHeading += preyVector * agent.geneC.w * 2.1;
    desiredHeading += threatVector * (0.78 + (1.0 - agent.geneA.w) * 1.18);
    float2 edgeAvoidance = float2(
        1.0 - smoothstep(0.015, 0.08, agent.position.x) - smoothstep(0.92, 0.985, agent.position.x),
        1.0 - smoothstep(0.015, 0.08, agent.position.y) - smoothstep(0.92, 0.985, agent.position.y)
    );
    desiredHeading += edgeAvoidance * 2.4;
    if (length(desiredHeading) > 0.0001) { desiredHeading = normalize(desiredHeading); }
    float previousSpeed = length(agent.velocity);
    float2 previousHeading = previousSpeed > 0.000001 ? agent.velocity / previousSpeed : inheritedHeading;
    float turnRate = 0.004 + 0.005 * agent.geneA.z;
    float2 smoothHeading = normalize(mix(previousHeading, desiredHeading, turnRate));
    float cruiseSpeed = (0.000020 + 0.000050 * agent.geneB.z) * spatialScale;
    float urgency = saturate(preyOpportunity * 1.8 + incomingAttack * 2.5);
    float coordinatedContraction = saturate(cellAggregate.mechanics.y * cellAggregate.dynamics.y * 2.8);
    float targetSpeed = cruiseSpeed * (0.66 + urgency * 0.55 + coordinatedContraction * 0.22);
    float smoothSpeed = mix(previousSpeed, targetSpeed, 0.008 + agent.geneA.x * 0.004);
    agent.velocity = smoothHeading * smoothSpeed;
    float speed = length(agent.velocity);
    agent.position = clamp(
        agent.position + agent.velocity * uniforms.transportScale,
        float2(0.002),
        float2(0.998)
    );

    float resourceGain = 0.00055 * (
        localState.x * agent.geneC.x + localEcology.x * agent.geneC.y + localEcology.y * agent.geneC.z
    ) / (1.0 + crowding * 0.72);
    float predationGain = 0.00042 * agent.geneC.w * preyOpportunity;
    float cellularViability = cellAggregate.physiology.x > 0.5
        ? saturate(cellAggregate.physiology.y * cellAggregate.physiology.z)
        : 0.0;
    float cellularPower = cellAggregate.mechanics.w * cellAggregate.physiology.x;
    float maintenance = 0.000050 *
        (0.72 + agent.biomass * 0.65 + speed / max(cruiseSpeed, 0.000001) * 0.42) +
        crowding * 0.000014;
    maintenance *= mix(1.08, 0.92, cellularViability * cellAggregate.dynamics.y);
    float environmentalDamage = 0.00034 * localEnvironment.z * (1.0 - agent.geneA.w) +
        0.00046 * localEnvironment.w + 0.00030 * incomingAttack +
        cellAggregate.physiology.w * 0.000025 + cellAggregate.mechanics.x * 0.000018;
    float cellularSurplus = max(cellularPower, 0.0) * 0.11;
    agent.energy = clamp(
        agent.energy + resourceGain + predationGain + cellularSurplus - maintenance - environmentalDamage,
        0.0, 1.45
    );
    agent.biomass = clamp(agent.biomass + (agent.energy - 0.55) * 0.00008 - environmentalDamage * 0.18, 0.12, 1.0);
    agent.age += 1.0;
    bool cellularFailure = agent.age > 240.0 && cellAggregate.physiology.x < 0.5;
    if (agent.energy <= 0.0001 || agent.biomass <= 0.121 ||
        agent.age > 180000.0 || cellularFailure) {
        recordLineageEvent(
            lineageEvents, identityCounters, 2u, agent, developmentalGenomes[gid],
            resonanceGenomes[gid], cellAggregate, uniforms.step
        );
        agent.energy = 0.0;
        agent.biomass = 0.0;
        agent.behavior = float4(0.0);
        atomic_store_explicit(&occupancy[gid], 0u, memory_order_relaxed);
    }
    agentsOut[gid] = agent;
}

kernel void spawnAgents(
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
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= maxAgentCount || atomic_load_explicit(&occupancy[gid], memory_order_relaxed) == 0u) { return; }
    AgentState parent = agents[gid];
    CellAggregate parentCells = cellAggregates[gid];
    bool tissueStable = parentCells.physiology.x >= 5.0 &&
        parentCells.physiology.y >= 0.34 && parentCells.physiology.z >= 0.58 &&
        parentCells.dynamics.y >= 0.18 && parentCells.mechanics.w > -0.00042;
    if (parent.energy < 1.06 || parent.age < 720.0 || !tissueStable) { return; }
    uint birthSeed = hash32(gid * 2246822519u ^ uniforms.step * 3266489917u ^ parent.generation * 668265263u);
    float birthChance = 0.00100 + parent.geneA.z * 0.00080 + parent.geneB.y * 0.0020;
    if (random01(birthSeed) >= birthChance) { return; }
    uint target = hash32(birthSeed + 17u) % maxAgentCount;
    if (target == gid) { target = (target + 1u) % maxAgentCount; }
    uint expected = 0u;
    if (!atomic_compare_exchange_weak_explicit(
        &occupancy[target], &expected, 1u, memory_order_relaxed, memory_order_relaxed
    )) { return; }

    float mutation = uniforms.mutationScale * (0.006 + parent.geneB.y * 0.18);
    bool branchMutation = random01(birthSeed + 31u) < 0.032;
    if (branchMutation) {
        mutation += uniforms.mutationScale * (0.035 + 0.055 * random01(birthSeed + 32u));
    }
    AgentState child = parent;
    child.geneA = clamp(parent.geneA + float4(
        signedRandom(birthSeed + 1u), signedRandom(birthSeed + 2u),
        signedRandom(birthSeed + 3u), signedRandom(birthSeed + 4u)
    ) * mutation, 0.0, 1.0);
    child.geneB.xyz = clamp(parent.geneB.xyz + float3(
        signedRandom(birthSeed + 5u), signedRandom(birthSeed + 6u), signedRandom(birthSeed + 7u)
    ) * mutation, 0.0, 1.0);
    child.geneB.y = clamp(child.geneB.y, 0.001, 0.12);
    child.geneB.w = fract(parent.geneB.w + signedRandom(birthSeed + 8u) * mutation * 2.8);
    child.geneC = clamp(parent.geneC + float4(
        signedRandom(birthSeed + 9u), signedRandom(birthSeed + 10u),
        signedRandom(birthSeed + 11u), signedRandom(birthSeed + 12u)
    ) * mutation, 0.0, 1.0);
    float spatialScale = 1.0 / max(uniforms.worldScale, 1.0);
    float angle = random01(birthSeed + 13u) * 2.0 * M_PI_F;
    float2 offset = float2(cos(angle), sin(angle)) *
        (0.010 + 0.006 * parent.geneB.z) * spatialScale;
    child.position = fract(parent.position + offset + 1.0);
    child.velocity = normalize(offset) *
        (0.000020 + 0.000050 * child.geneB.z) * spatialScale;
    child.behavior = float4(0.0);
    child.energy = 0.48;
    child.biomass = 0.38;
    child.age = 0.0;
    child.generation = parent.generation + 1u;
    child.birthID = atomic_fetch_add_explicit(&identityCounters[0], 1u, memory_order_relaxed);
    child.parentBirthID = parent.birthID;
    child.birthStep = uniforms.step;
    child.lineageFlags = branchMutation ? 2u : 0u;
    child.reserved = 0u;
    parent.energy -= 0.35;
    parent.age = 0.0;
    agents[gid] = parent;
    ResonanceGenome childResonance = resonanceGenomes[gid];
    float resonanceMutation = 0.012 + mutation * (branchMutation ? 1.8 : 0.65);
    childResonance.mechanics.x = mutateScalar(
        childResonance.mechanics.x, birthSeed + 901u, resonanceMutation * 0.020, 0.0008, 0.0090
    );
    childResonance.mechanics.y = mutateScalar(
        childResonance.mechanics.y, birthSeed + 907u, resonanceMutation * 0.32, 0.04, 0.72
    );
    childResonance.mechanics.z = mutateScalar(
        childResonance.mechanics.z, birthSeed + 911u, resonanceMutation * 0.62, 0.08, 1.60
    );
    childResonance.mechanics.w = mutateScalar(
        childResonance.mechanics.w, birthSeed + 919u, resonanceMutation * 0.08, 0.0, 0.12
    );
    childResonance.tuning = clamp(
        childResonance.tuning + randomSigned4(birthSeed + 929u) * resonanceMutation *
            float4(0.024, 0.020, 0.80, 1.20),
        float4(0.0003, 0.00005, -0.48, -1.0),
        float4(0.0080, 0.0060, 0.48, 1.0)
    );
    resonanceGenomes[target] = childResonance;
    mutateDevelopmentalGenome(
        developmentalGenomes, developmentalGenomes,
        regulatoryNodes, regulatoryNodes, regulatoryEdges, regulatoryEdges,
        identityCounters, gid, target, birthSeed ^ 0x5e2d58d1u, mutation, branchMutation
    );
    child.lastMutationDistance = developmentalGenomes[target].mutation.y + resonanceMutation * 0.12;
    child.mutationDistance = parent.mutationDistance + child.lastMutationDistance;
    child.genomeHash = agentGenomeHash(
        child, developmentalGenomes[target].topology.z, childResonance
    );
    agents[target] = child;
    seedOrganismCells(
        cells, cellOccupancy, cellAggregates, regulatoryStates,
        target, child, birthSeed ^ 0xa511e9b3u, childResonance
    );
    recordLineageEvent(
        lineageEvents, identityCounters, 1u, child, developmentalGenomes[target],
        childResonance, cellAggregates[target], uniforms.step
    );
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
    float spatialScale = 1.0 / max(uniforms.worldScale, 1.0);
    founder.velocity = float2(cos(heading), sin(heading)) *
        (0.000020 + 0.000050 * founder.geneB.z) * spatialScale;
    founder.behavior = float4(0.0);
    founder.energy = 1.02;
    founder.biomass = 0.66;
    founder.age = 0.0;
    founder.generation = 0u;
    founder.birthID = atomic_fetch_add_explicit(&identityCounters[0], 1u, memory_order_relaxed);
    founder.parentBirthID = 0xffffffffu;
    founder.birthStep = uniforms.step;
    founder.mutationDistance = 0.0;
    founder.lastMutationDistance = 0.0;
    founder.lineageFlags = 1u;
    founder.reserved = 0u;
    initializeFounderRegulatoryGenome(
        developmentalGenomes, regulatoryNodes, regulatoryEdges, identityCounters,
        claimed, founder, seed
    );
    ResonanceGenome resonance = founderResonanceGenome(founder, seed ^ 0xe6f13a8bu);
    resonanceGenomes[claimed] = resonance;
    founder.genomeHash = agentGenomeHash(founder, developmentalGenomes[claimed].topology.z, resonance);
    agents[claimed] = founder;
    seedOrganismCells(
        cells, cellOccupancy, cellAggregates, regulatoryStates,
        claimed, founder, seed ^ 0x63d83595u, resonance
    );
    recordLineageEvent(
        lineageEvents, identityCounters, 1u, founder, developmentalGenomes[claimed],
        resonance, cellAggregates[claimed], uniforms.step
    );
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
    texture2d_array<float, access::read> state [[texture(0)]],
    texture2d_array<float, access::read> ecology [[texture(1)]],
    texture2d_array<float, access::read> environment [[texture(2)]],
    texture2d_array<float, access::read> events [[texture(3)]],
    texture2d_array<float, access::read> mechanicalField [[texture(4)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= maxCellCount) { return; }
    uint owner = gid / cellsPerAgent;
    if (atomic_load_explicit(&agentOccupancy[owner], memory_order_relaxed) == 0u) {
        if (atomic_load_explicit(&cellOccupancy[gid], memory_order_relaxed) != 0u) {
            atomic_store_explicit(&cellOccupancy[gid], 0u, memory_order_relaxed);
        }
        return;
    }
    if (atomic_load_explicit(&cellOccupancy[gid], memory_order_relaxed) == 0u) {
        return;
    }

    AgentState agent = agents[owner];
    CellState cell = cellsIn[gid];
    ResonanceGenome resonanceGenome = resonanceGenomes[owner];
    uint ownerBase = owner * cellsPerAgent;
    float2 mechanicalForce = -cell.position * (0.00045 + cell.phenotype.y * 0.00045);
    float2 contactSignal = float2(0.0);
    float2 nearestContact = float2(0.0);
    float nearestDistance = 10.0;
    float contactCount = 0.0;
    float neighborVoltage = 0.0;
    float phaseCoupling = 0.0;
    float2 phaseVector = float2(0.0);
    float neighborCalcium = 0.0;
    float neighborERK = 0.0;
    float2 erkGradient = float2(0.0);
    for (uint localIndex = 0u; localIndex < cellsPerAgent; ++localIndex) {
        uint otherIndex = ownerBase + localIndex;
        if (otherIndex == gid ||
            atomic_load_explicit(&cellOccupancy[otherIndex], memory_order_relaxed) == 0u) { continue; }
        CellState other = cellsIn[otherIndex];
        float2 delta = other.position - cell.position;
        float distance = max(length(delta), 0.0001);
        float2 direction = delta / distance;
        float cellRadius = clamp(sqrt(max(cell.membrane.x, 0.010) / M_PI_F), 0.085, 0.18);
        float otherRadius = clamp(sqrt(max(other.membrane.x, 0.010) / M_PI_F), 0.085, 0.18);
        float contactDistance = cellRadius + otherRadius;
        if (distance < contactDistance) {
            mechanicalForce -= direction * (contactDistance - distance) * 0.024;
        } else if (distance < contactDistance + 0.30) {
            float pairAdhesion = min(cell.phenotype.x, other.phenotype.x);
            mechanicalForce += direction * (distance - contactDistance) * pairAdhesion * 0.0042;
        }
        if (distance < 0.58) {
            float weight = 1.0 - distance / 0.58;
            contactSignal += other.signals.xy * weight;
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
            contactCount += weight;
            if (distance < nearestDistance) {
                nearestDistance = distance;
                nearestContact = direction;
            }
        }
    }

    float inheritedAngle = agent.geneB.w * 2.0 * M_PI_F;
    float agentSpeed = length(agent.velocity);
    float2 heading = agentSpeed > 0.000001
        ? agent.velocity / agentSpeed
        : float2(cos(inheritedAngle), sin(inheritedAngle));
    float2 lateral = float2(-heading.y, heading.x);
    float spatialScale = 1.0 / max(uniforms.worldScale, 1.0);
    float bodyWorldRadius = (0.012 + 0.0045 * agent.geneB.z + 0.0025 * agent.biomass) * spatialScale;
    float2 worldPosition = clamp(
        agent.position + heading * cell.position.x * bodyWorldRadius +
            lateral * cell.position.y * bodyWorldRadius * 0.72,
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
    uint2 coordinateLeft = uint2(max(int(coordinate.x) - 1, 0), coordinate.y);
    uint2 coordinateRight = uint2(min(coordinate.x + 1u, uniforms.width - 1u), coordinate.y);
    uint2 coordinateDown = uint2(coordinate.x, max(int(coordinate.y) - 1, 0));
    uint2 coordinateUp = uint2(coordinate.x, min(coordinate.y + 1u, uniforms.height - 1u));
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
    float junctionSignalGain = 0.30 + cell.phenotype.x * 0.54;
    float neighborCalciumDrive = max(meanNeighborCalcium - previousCalcium, 0.0) *
        junctionSignalGain * (1.0 - previousRefractory);
    float extrusionCalciumDrive = cell.signals.w * (0.10 + cell.physiology.w * 0.16);
    float calciumLoss = previousCalcium * (0.0090 + previousRefractory * 0.0140);
    float calciumWithoutMechanical = clamp(
        previousCalcium + neighborCalciumDrive * 0.018 + extrusionCalciumDrive * 0.012 - calciumLoss,
        0.0, 1.0
    );
    float mechanicalCalciumGate = saturate(
        abs(resonantResponse) * 0.72 + fieldStrain * 0.30 +
        saturate(cell.membrane.w * 8.0) * 0.18
    ) * signalingAvailability * saturate(uniforms.intervention.x);
    float calcium = clamp(
        calciumWithoutMechanical + mechanicalCalciumGate * (1.0 - previousCalcium) * 0.026,
        0.0, 1.0
    );
    float mechanicsToCalciumEffect = max(calcium - calciumWithoutMechanical, 0.0);

    float neighborERKDrive = max(meanNeighborERK - previousERK, 0.0) *
        (0.22 + cell.phenotype.x * 0.42);
    float erkLoss = previousERK * (0.0042 + previousRefractory * 0.010);
    float erkWithoutCalcium = clamp(
        previousERK + neighborERKDrive * 0.016 - erkLoss,
        0.0, 1.0
    );
    float calciumERKDrive = smoothstep(0.08, 0.46, calcium) * (1.0 - previousRefractory);
    float erk = clamp(
        erkWithoutCalcium + calciumERKDrive * (1.0 - previousERK) * 0.020,
        0.0, 1.0
    );
    float calciumToERKEffect = max(erk - erkWithoutCalcium, 0.0);
    float refractory = clamp(
        previousRefractory + erk * 0.0075 - previousRefractory * 0.0038,
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
        (0.72 + max(voltage, 0.0) * 0.20), 0.11);

    float uptake = 0.00022 + 0.00072 * (
        localState.x * cell.phenotype.z + localEcology.x * cell.phenotype.w +
        localEcology.y * agent.geneC.z * 0.34
    );
    uptake *= 0.62 + agent.energy * 0.38;
    float maintenance = 0.00046 * (
        0.62 + cell.physiology.y * 0.48 + cell.phenotype.y * 0.28
    );
    float externalStress = saturate(
        localEnvironment.z * 0.72 + localEnvironment.w * 0.36 + localEcology.z * 0.58 +
        localEvents.z * 0.24 + max(contactCount - 4.5, 0.0) * 0.08
    );
    float regulatorySensors[8] = {
        clamp(cell.physiology.x * 2.0 - 1.0, -1.0, 1.0),
        clamp(voltage / 1.8, -1.0, 1.0),
        fieldStrain,
        saturate(contactCount / 4.2),
        clamp(cell.signals.x - cell.signals.y, -1.0, 1.0),
        clamp(uptake * 1350.0 - externalStress - cell.signals.z * 0.35, -1.0, 1.0),
        clamp(resonantResponse, -1.0, 1.0),
        saturate(cell.membrane.w * 8.0 + abs(cell.membrane.z - 1.0))
    };
    RegulatoryOutputs regulatoryOutput = evolveDevelopmentalProgram(
        developmentalGenomes, regulatoryNodes, regulatoryEdges, regulatoryStates,
        owner, gid, regulatorySensors
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
    uptake *= mix(0.66, 1.42, permeabilityProgram);
    contractility *= mix(0.52, 1.58, contractileProgram) * (1.0 + calcium * 0.18);
    maintenance *= 0.94 + repairProgram * 0.16 + proliferationProgram * 0.10;
    float signalingCost = calcium * 0.000020 + erk * 0.000024 +
        (mechanicsToCalciumEffect + calciumToERKEffect) * 0.000080;
    float activeWork = contractility * (0.000055 + fieldStrain * 0.000070) +
        abs(voltageDerivative) * 0.000070 + signalingCost;
    float dissipation = externalStress * 0.00032 + fieldWaveSpeed * 0.000035 +
        dot(cell.velocity, cell.velocity) * 2.8;
    float atp = clamp(
        cell.physiology.x + uptake - maintenance - activeWork - dissipation,
        0.0, 1.2
    );
    float stress = mix(cell.signals.z, externalStress + (atp < 0.18 ? 0.36 : 0.0), 0.018);
    float apoptosis = clamp(
        cell.signals.w + max(stress - 0.72, 0.0) * 0.0024 - 0.00022 -
            repairProgram * 0.00030 - apoptosisSuppression * 0.00034,
        0.0, 1.0
    );
    float membraneIntegrity = clamp(
        cell.physiology.w + (atp - 0.38) * 0.00020 + repairProgram * atp * 0.00022 -
            stress * 0.00030 - apoptosis * 0.00045 - permeabilityProgram * 0.000035,
        0.0, 1.0
    );
    float biomass = clamp(
        cell.physiology.y + (atp - 0.48) * 0.00018 * mix(0.42, 1.38, proliferationProgram),
        0.42, 1.08
    );
    float contactInhibition = saturate(contactCount / (3.6 + cell.phenotype.x * 1.8));
    float unconstrainedCycleDrive = 0.00145 * smoothstep(0.40, 0.72, atp) *
        mix(0.12, 1.62, proliferationProgram) * (1.0 - saturate(stress));
    float contactBrake = contactInhibition * (0.62 + adhesiveProgram * 0.30);
    float cycleRate = unconstrainedCycleDrive * (1.0 - contactBrake);
    float cycle = clamp(
        cell.physiology.z + cycleRate - contactInhibition * 0.00022,
        0.0, 1.2
    );

    float2 localMorphogens = contactCount > 0.001 ? contactSignal / contactCount : cell.signals.xy;
    float radialPosition = saturate(length(cell.position) / 0.82);
    float2 targetMorphogens = float2(
        (1.0 - radialPosition) * mix(0.72, 1.16, adhesiveProgram),
        radialPosition * mix(0.72, 1.18, contractileProgram)
    );
    cell.signals.xy = mix(
        cell.signals.xy,
        mix(targetMorphogens, localMorphogens, 0.58) +
            float2(secretionProgram, 1.0 - secretionProgram) * 0.018,
        0.014
    );
    cell.signals.zw = float2(stress, apoptosis);
    float centralProgram = saturate(cell.signals.x - cell.signals.y + 0.5);
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

    float2 polarity = float2(cell.signals.x - cell.signals.y, signedRandom(gid * 31u + uniforms.step / 16u));
    mechanicalForce += polarity * cell.phenotype.y *
        (0.00008 + contractileProgram * 0.00010 + motilityProgram * 0.00010);
    float2 antiWaveDirection = length(erkGradient) > 0.0001
        ? -normalize(erkGradient)
        : (length(polarity) > 0.0001 ? normalize(polarity) : float2(1.0, 0.0));
    float2 erkTraction = antiWaveDirection * erk * motilityProgram *
        (0.000035 + cell.phenotype.y * 0.000085);
    mechanicalForce += erkTraction;
    float radialLength = length(cell.position);
    if (radialLength > 0.0001) {
        mechanicalForce -= cell.position / radialLength * contractility * 0.00072;
    }
    mechanicalForce += float2(
        dot(localMechanical.xy, heading),
        dot(localMechanical.xy, lateral)
    ) * (0.0008 + agent.geneA.z * 0.0014);
    cell.velocity = cell.velocity * 0.90 + mechanicalForce;
    float cellSpeed = length(cell.velocity);
    if (cellSpeed > 0.0024) { cell.velocity *= 0.0024 / cellSpeed; }
    cell.position += cell.velocity * uniforms.transportScale;
    float radialDistance = length(cell.position);
    if (radialDistance > 0.86) {
        float2 normal = cell.position / radialDistance;
        cell.position = normal * 0.86;
        cell.velocity -= normal * max(dot(cell.velocity, normal), 0.0) * 1.6;
    }

    cell.interaction = float4(
        nearestContact,
        contactBrake,
        mechanosensoryDrive * 0.020
    );
    cell.signaling = float4(calcium, erk, refractory, neighborSignalInput);
    cell.signalCausality = float4(
        mechanicsToCalciumEffect,
        calciumToERKEffect,
        length(erkTraction),
        signalingCost
    );

    float2 localContractionDirection = radialLength > 0.0001
        ? -cell.position / radialLength
        : float2(cos(oscillatorPhase * 2.0 * M_PI_F), sin(oscillatorPhase * 2.0 * M_PI_F));
    float2 worldContraction = (heading * localContractionDirection.x + lateral * localContractionDirection.y) *
        contractility * membraneIntegrity * 0.0065;
    uint forcingIndex = (coordinate.y * uniforms.width + coordinate.x) * 2u;
    int forceX = int(clamp(worldContraction.x * float(mechanicalForceScale), -8192.0, 8192.0));
    int forceY = int(clamp(worldContraction.y * float(mechanicalForceScale), -8192.0, 8192.0));
    atomic_fetch_add_explicit(&mechanicalForcing[forcingIndex], forceX, memory_order_relaxed);
    atomic_fetch_add_explicit(&mechanicalForcing[forcingIndex + 1u], forceY, memory_order_relaxed);

    if (membraneIntegrity < 0.055 || apoptosis > 0.985 ||
        (atp < 0.008 && stress > 0.82)) {
        atomic_store_explicit(&cellOccupancy[gid], 0u, memory_order_relaxed);
    }
    cellsOut[gid] = cell;
}

kernel void evolveCellMembranes(
    device const CellState* cellsIn [[buffer(0)]],
    device CellState* cellsOut [[buffer(1)]],
    device const atomic_uint* cellOccupancy [[buffer(2)]],
    device MembraneVertex* membraneVertices [[buffer(3)]],
    constant SimulationUniforms& uniforms [[buffer(4)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= maxCellCount ||
        atomic_load_explicit(&cellOccupancy[gid], memory_order_relaxed) == 0u) { return; }

    CellState cell = cellsIn[gid];
    uint owner = gid / cellsPerAgent;
    uint ownerBase = owner * cellsPerAgent;
    uint membraneBase = gid * membraneVertexCount;
    float2 positions[membraneVertexCount];
    float2 velocities[membraneVertexCount];
    float localIntegrity[membraneVertexCount];
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
    }

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
        float stiffness = mix(0.006, 0.026, saturate(cell.physiology.w * localIntegrity[vertexIndex]));
        float2 edgeForce = toPrevious / previousLength * (previousLength - restEdge) * stiffness +
            toNext / nextLength * (nextLength - restEdge) * stiffness;
        float2 bendingForce = (positions[previous] + positions[next] - current * 2.0) *
            (0.012 + cell.regulation.y * 0.018) * localIntegrity[vertexIndex];
        float radialLength = max(length(current), 0.0001);
        float2 radialNormal = current / radialLength;
        float2 pressureForce = radialNormal * areaError *
            (0.0018 + cell.physiology.x * 0.0028);
        float2 contractileForce = -radialNormal * cell.mechanics.x *
            (0.00028 + cell.regulation.z * 0.00062);
        float2 contactForce = float2(0.0);
        float contactPressure = 0.0;
        float2 tissueVertex = cell.position + current;
        for (uint localIndex = 0u; localIndex < cellsPerAgent; ++localIndex) {
            uint otherIndex = ownerBase + localIndex;
            if (otherIndex == gid ||
                atomic_load_explicit(&cellOccupancy[otherIndex], memory_order_relaxed) == 0u) { continue; }
            CellState other = cellsIn[otherIndex];
            float otherRadius = clamp(sqrt(max(other.membrane.x, 0.010) / M_PI_F), 0.085, 0.18);
            float2 delta = tissueVertex - other.position;
            float distance = max(length(delta), 0.0001);
            float overlap = otherRadius - distance;
            if (overlap > 0.0) {
                float magnitude = overlap * (0.010 + min(cell.phenotype.x, other.phenotype.x) * 0.012);
                contactForce += delta / distance * magnitude;
                contactPressure += magnitude;
            } else if (distance < otherRadius + 0.055) {
                float adhesion = min(cell.phenotype.x, other.phenotype.x) *
                    (1.0 - (distance - otherRadius) / 0.055);
                contactForce -= delta / distance * adhesion * 0.00024;
            }
        }
        float integrityTarget = clamp(
            cell.physiology.w - contactPressure * 8.0 - cell.signals.z * 0.08,
            0.04, 1.0
        );
        float integrity = mix(
            localIntegrity[vertexIndex], integrityTarget, 0.012 + cell.regulation.w * 0.014
        );
        float2 force = edgeForce + bendingForce + pressureForce + contractileForce + contactForce;
        float2 velocity = velocities[vertexIndex] * (0.78 + integrity * 0.12) + force;
        float speed = length(velocity);
        if (speed > 0.006) { velocity *= 0.006 / speed; }
        float2 position = current + velocity * uniforms.transportScale;
        float radius = length(position);
        if (radius > 0.21) { position *= 0.21 / radius; velocity *= 0.4; }
        MembraneVertex output;
        output.position = position;
        output.velocity = velocity;
        output.mechanics = float4(
            restEdge, integrity, contactPressure,
            abs(previousLength - restEdge) + abs(nextLength - restEdge)
        );
        membraneVertices[membraneBase + vertexIndex] = output;
        transmittedForce += length(contactForce);
    }

    float updatedDoubleArea = 0.0;
    float updatedPerimeter = 0.0;
    for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
        uint next = (vertexIndex + 1u) % membraneVertexCount;
        float2 a = membraneVertices[membraneBase + vertexIndex].position;
        float2 b = membraneVertices[membraneBase + next].position;
        updatedDoubleArea += a.x * b.y - b.x * a.y;
        updatedPerimeter += length(b - a);
    }
    float updatedArea = max(abs(updatedDoubleArea) * 0.5, 0.0001);
    float shapeIndex = updatedPerimeter * updatedPerimeter /
        max(4.0 * M_PI_F * updatedArea, 0.0001);
    cell.membrane = float4(
        updatedArea, updatedPerimeter, clamp(shapeIndex, 1.0, 3.5), transmittedForce
    );
    cellsOut[gid] = cell;
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
    device const ResonanceGenome* resonanceGenomes [[buffer(8)]],
    uint owner [[thread_position_in_grid]]
) {
    if (owner >= maxAgentCount) { return; }
    uint base = owner * cellsPerAgent;
    if (atomic_load_explicit(&agentOccupancy[owner], memory_order_relaxed) == 0u) {
        return;
    }

    uint divisionParent = maxCellCount;
    uint divisionTarget = maxCellCount;
    float mostAdvancedCycle = 1.0;
    for (uint localIndex = 0u; localIndex < cellsPerAgent; ++localIndex) {
        uint index = base + localIndex;
        if (atomic_load_explicit(&cellOccupancy[index], memory_order_relaxed) == 0u) {
            if (divisionTarget == maxCellCount) { divisionTarget = index; }
            continue;
        }
        float cycle = cells[index].physiology.z;
        if (cycle >= mostAdvancedCycle) {
            mostAdvancedCycle = cycle;
            divisionParent = index;
        }
    }

    AgentState agent = agents[owner];
    if (divisionParent != maxCellCount && divisionTarget != maxCellCount && agent.energy > 0.42) {
        uint expected = 0u;
        if (atomic_compare_exchange_weak_explicit(
            &cellOccupancy[divisionTarget], &expected, 1u,
            memory_order_relaxed, memory_order_relaxed
        )) {
            CellState parent = cells[divisionParent];
            uint divisionSeed = hash32(owner * 2246822519u ^ divisionParent * 3266489917u ^ uniforms.step);
            float phaseAngle = parent.dynamics.z * 2.0 * M_PI_F;
            float2 phaseAxis = float2(cos(phaseAngle), sin(phaseAngle));
            float radialLength = length(parent.position);
            float2 radialAxis = radialLength > 0.0001 ? parent.position / radialLength : phaseAxis;
            float2 axis = normalize(
                phaseAxis * (0.38 + parent.regulation.x * 0.42) +
                radialAxis * (0.26 + parent.regulation.z * 0.58) +
                float2(parent.signals.x - parent.signals.y, parent.mechanics.y - 0.5) * 0.24
            );
            CellState child = parent;
            parent.position -= axis * 0.095;
            child.position += axis * 0.095;
            parent.velocity -= axis * 0.00035;
            child.velocity += axis * 0.00035;
            parent.physiology.x *= 0.56;
            child.physiology.x = parent.physiology.x;
            parent.physiology.y *= 0.62;
            child.physiology.y = parent.physiology.y;
            parent.physiology.z = 0.0;
            child.physiology.z = 0.0;
            float fateAsymmetry = clamp(
                0.035 + abs(parent.signals.x - parent.signals.y) * 0.085 +
                    parent.regulation.z * 0.055 + parent.mechanics.y * 0.035,
                0.03, 0.18
            );
            float4 fateDelta = float4(
                fateAsymmetry, -fateAsymmetry * 0.74,
                fateAsymmetry * 0.58, -fateAsymmetry * 0.30
            );
            parent.regulation = saturate(parent.regulation - fateDelta);
            child.regulation = saturate(child.regulation + fateDelta);
            parent.signals.xy = saturate(
                parent.signals.xy + float2(fateAsymmetry * 0.34, -fateAsymmetry * 0.34)
            );
            child.signals.xy = saturate(
                child.signals.xy + float2(-fateAsymmetry * 0.34, fateAsymmetry * 0.34)
            );
            child.interaction = float4(0.0);
            child.dynamics.z = fract(parent.dynamics.z + signedRandom(divisionSeed + 3u) * 0.040 + 1.0);
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
            child.signaling.xy = saturate(
                parent.signaling.xy + float2(-fateAsymmetry, fateAsymmetry) * 0.08
            );
            parent.signaling.xy = saturate(
                parent.signaling.xy + float2(fateAsymmetry, -fateAsymmetry) * 0.08
            );
            parent.signalCausality = float4(0.0);
            child.signalCausality = float4(0.0);
            uint parentStateBase = divisionParent * regulatoryNodeCapacity;
            uint childStateBase = divisionTarget * regulatoryNodeCapacity;
            for (uint node = 0u; node < regulatoryNodeCapacity; ++node) {
                float state = regulatoryStates[parentStateBase + node];
                regulatoryStates[parentStateBase + node] = saturate(
                    state - signedRandom(divisionSeed + 101u + node) * fateAsymmetry * 0.12
                );
                regulatoryStates[childStateBase + node] = saturate(
                    state + signedRandom(divisionSeed + 101u + node) * fateAsymmetry * 0.12
                );
            }
            uint parentMembraneBase = divisionParent * membraneVertexCount;
            uint childMembraneBase = divisionTarget * membraneVertexCount;
            for (uint vertexIndex = 0u; vertexIndex < membraneVertexCount; ++vertexIndex) {
                MembraneVertex membrane = membraneVertices[parentMembraneBase + vertexIndex];
                membrane.position *= 0.78;
                membrane.velocity *= 0.25;
                membrane.mechanics.x *= 0.78;
                membraneVertices[parentMembraneBase + vertexIndex] = membrane;
                MembraneVertex daughterMembrane = membrane;
                daughterMembrane.velocity *= -1.0;
                daughterMembrane.mechanics.zw = float2(0.0);
                membraneVertices[childMembraneBase + vertexIndex] = daughterMembrane;
            }
            parent.membrane.xy *= float2(0.61, 0.78);
            child.membrane = parent.membrane;
            cells[divisionParent] = parent;
            cells[divisionTarget] = child;
            agent.energy = max(agent.energy - 0.0045, 0.0);
            agent.biomass = min(agent.biomass + 0.0008, 1.0);
            agents[owner] = agent;
        }
    } else if (divisionTarget == maxCellCount) {
        for (uint localIndex = 0u; localIndex < cellsPerAgent; ++localIndex) {
            uint index = base + localIndex;
            if (atomic_load_explicit(&cellOccupancy[index], memory_order_relaxed) == 0u) { continue; }
            CellState cell = cells[index];
            if (cell.physiology.z > 0.74) {
                cell.physiology.z = max(0.70, cell.physiology.z - 0.0032);
                cells[index] = cell;
            }
        }
    }

    float activeCount = 0.0;
    float atpTotal = 0.0;
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
    float2 centroid = float2(0.0);
    for (uint localIndex = 0u; localIndex < cellsPerAgent; ++localIndex) {
        uint index = base + localIndex;
        if (atomic_load_explicit(&cellOccupancy[index], memory_order_relaxed) == 0u) { continue; }
        CellState cell = cells[index];
        activeCount += 1.0;
        atpTotal += cell.physiology.x;
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
        float unconstrainedCycleDrive = 0.00145 * smoothstep(0.40, 0.72, cell.physiology.x) *
            mix(0.12, 1.62, cell.regulation.x) * (1.0 - saturate(cell.signals.z));
        float contactInhibition = cell.interaction.z /
            max(0.62 + cell.regulation.y * 0.30, 0.001);
        float contactEffect = -(unconstrainedCycleDrive * cell.interaction.z +
            contactInhibition * 0.00022);
        float repairEffect = cell.regulation.w * cell.physiology.x * 0.00022;
        causalityTotal += float4(
            cell.interaction.w,
            unconstrainedCycleDrive,
            contactEffect,
            repairEffect
        );
        centroid += cell.position;
    }
    centroid /= max(activeCount, 1.0);
    float squaredRadius = 0.0;
    for (uint localIndex = 0u; localIndex < cellsPerAgent; ++localIndex) {
        uint index = base + localIndex;
        if (atomic_load_explicit(&cellOccupancy[index], memory_order_relaxed) == 0u) { continue; }
        float2 offset = cells[index].position - centroid;
        squaredRadius += dot(offset, offset);
    }
    CellAggregate aggregate;
    float inverseCount = 1.0 / max(activeCount, 1.0);
    aggregate.physiology = float4(
        activeCount,
        atpTotal * inverseCount,
        integrityTotal * inverseCount,
        stressTotal * inverseCount
    );
    aggregate.morphology = float4(
        centroid,
        sqrt(squaredRadius * inverseCount),
        dividingCount * inverseCount
    );
    float phaseCoherence = saturate(length(phaseTotal) * inverseCount);
    float meanPhase = phaseCoherence > 0.0001
        ? fract(atan2(phaseTotal.y, phaseTotal.x) / (2.0 * M_PI_F) + 1.0)
        : 0.0;
    aggregate.dynamics = float4(
        voltageTotal * inverseCount,
        phaseCoherence,
        frequencyTotal * inverseCount,
        meanPhase
    );
    aggregate.mechanics = float4(
        strainTotal * inverseCount,
        contractilityTotal * inverseCount,
        waveSpeedTotal * inverseCount,
        (energeticsTotal.x - energeticsTotal.y - energeticsTotal.z - energeticsTotal.w) * inverseCount
    );
    aggregate.energetics = energeticsTotal;
    aggregate.regulation = regulationTotal * inverseCount;
    aggregate.regulationB = regulationBTotal * inverseCount;
    aggregate.causality = causalityTotal * inverseCount;
    aggregate.resonance = float4(
        resonanceDisplacementTotal * inverseCount,
        resonanceAmplitudeTotal * inverseCount,
        frequencyTotal * inverseCount,
        resonanceGenomes[owner].mechanics.y
    );
    aggregate.shape = float4(
        membraneAreaTotal * inverseCount,
        membranePerimeterTotal * inverseCount,
        membraneShapeTotal * inverseCount,
        junctionForceTotal * inverseCount
    );
    aggregate.signaling = signalingTotal * inverseCount;
    aggregate.signalCausality = signalCausalityTotal * inverseCount;
    aggregates[owner] = aggregate;
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

kernel void compactVisibleCells(
    device const atomic_uint* agentOccupancy [[buffer(0)]],
    device const atomic_uint* cellOccupancy [[buffer(1)]],
    device uint* visibleCellIndices [[buffer(2)]],
    device atomic_uint* drawArguments [[buffer(3)]],
    constant SimulationUniforms& uniforms [[buffer(4)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= maxCellCount ||
        atomic_load_explicit(&cellOccupancy[gid], memory_order_relaxed) == 0u) { return; }
    uint owner = gid / cellsPerAgent;
    if (atomic_load_explicit(&agentOccupancy[owner], memory_order_relaxed) == 0u) { return; }
    float observationZoom = uniforms.cameraZoom / max(uniforms.worldScale, 1.0);
    if (observationZoom <= 5.0 || observationZoom >= 180.0) { return; }
    if (uniforms.trackedAgentID != 0xffffffffu &&
        uniforms.trackedAgentID != owner && observationZoom >= 34.0) { return; }
    uint target = atomic_fetch_add_explicit(&drawArguments[1], 1u, memory_order_relaxed);
    if (target < maxCellCount) {
        visibleCellIndices[target] = gid;
    }
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
    float3 color = float3(source.sample(linearSampler, uv).rgb) * 0.50;
    color += float3(source.sample(linearSampler, uv + sourceTexel * float2(-1.25, -1.25)).rgb) * 0.125;
    color += float3(source.sample(linearSampler, uv + sourceTexel * float2( 1.25, -1.25)).rgb) * 0.125;
    color += float3(source.sample(linearSampler, uv + sourceTexel * float2(-1.25,  1.25)).rgb) * 0.125;
    color += float3(source.sample(linearSampler, uv + sourceTexel * float2( 1.25,  1.25)).rgb) * 0.125;

    const float threshold = 0.92;
    const float knee = 0.38;
    float brightness = max(max(color.r, color.g), color.b);
    float soft = clamp(brightness - threshold + knee, 0.0, 2.0 * knee);
    soft = soft * soft / (4.0 * knee + 0.0001);
    float contribution = max(brightness - threshold, soft) / max(brightness, 0.0001);
    destination.write(half4(half3(color * contribution), half(1.0)), gid);
}

kernel void blurBloom(
    texture2d<half, access::sample> source [[texture(0)]],
    texture2d<half, access::write> destination [[texture(1)]],
    constant float2& direction [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destination.get_width() || gid.y >= destination.get_height()) { return; }
    constexpr sampler linearSampler(coord::pixel, address::clamp_to_edge, filter::linear);
    float2 position = float2(gid) + 0.5;
    half3 color = source.sample(linearSampler, position).rgb * half(0.227027);
    color += source.sample(linearSampler, position + direction * 1.384615).rgb * half(0.316216);
    color += source.sample(linearSampler, position - direction * 1.384615).rgb * half(0.316216);
    color += source.sample(linearSampler, position + direction * 3.230769).rgb * half(0.070270);
    color += source.sample(linearSampler, position - direction * 3.230769).rgb * half(0.070270);
    destination.write(half4(color, half(1.0)), gid);
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
    float3 hdr = linearScene * uniforms.exposure + linearBloom * uniforms.bloomIntensity;

    float peak = max(max(hdr.r, hdr.g), hdr.b);
    float peakScale = (1.0 - exp(-peak)) / max(peak, 0.0001);
    float3 mapped = hdr * peakScale;
    float luminance = dot(mapped, float3(0.2126, 0.7152, 0.0722));
    float saturation = uniforms.observationZoom >= 420.0 ? 1.02 : 1.08;
    mapped = mix(float3(luminance), mapped, saturation);

    uint2 pixel = uint2(input.position.xy);
    float dither = random01(pixel.x * 1597334677u ^ pixel.y * 3812015801u ^
        uniforms.frameIndex * 2246822519u) - 0.5;
    mapped = saturate(mapped + dither / 1023.0);
    return float4(mapped, 1.0);
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

struct AgentRasterData {
    float4 position [[position]];
    float2 local;
    float2 worldUV;
    float4 geneA;
    float4 geneB;
    float4 geneC;
    float energy;
    float biomass;
    float age;
    float speed;
    float4 behavior;
    float4 cellularPhysiology;
    float4 tissueMorphology;
    float4 tissueDynamics;
    float4 tissueMechanics;
    float4 tissueRegulation;
    float4 tissueCausality;
    float4 tissueSignaling;
    float4 tissueSignalCausality;
    float focus;
    float tracked;
    float trackingActive;
};

vertex AgentRasterData agentVertex(
    device const AgentState* agents [[buffer(0)]],
    device const uint* occupancy [[buffer(1)]],
    constant SimulationUniforms& uniforms [[buffer(2)]],
    device const CellAggregate* cellAggregates [[buffer(3)]],
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]]
) {
    const float2 corners[6] = {
        float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0),
        float2(-1.0, 1.0), float2(1.0, -1.0), float2(1.0, 1.0)
    };
    AgentState agent = agents[instanceID];
    CellAggregate cellularAggregate = cellAggregates[instanceID];
    float2 corner = corners[vertexID];
    float speed = length(agent.velocity);
    float inheritedAngle = agent.geneB.w * 2.0 * M_PI_F;
    float2 heading = speed > 0.000001
        ? agent.velocity / speed
        : float2(cos(inheritedAngle), sin(inheritedAngle));
    float2 lateral = float2(-heading.y, heading.x);
    float tissueOccupancy = saturate(cellularAggregate.physiology.x / float(cellsPerAgent));
    float ontogeneticScale = mix(0.34, 1.0, smoothstep(0.04, 0.46, tissueOccupancy));
    float worldRadius = (0.012 + 0.0045 * agent.geneB.z + 0.0025 * agent.biomass) *
        ontogeneticScale / max(uniforms.worldScale, 1.0);
    float2 worldPosition = agent.position +
        heading * corner.x * worldRadius + lateral * corner.y * worldRadius * 0.72;
    float safeAspect = max(uniforms.viewportAspect, 0.001);
    float2 viewScale = safeAspect >= 1.0 ? float2(1.0, 1.0 / safeAspect) : float2(safeAspect, 1.0);
    float2 screenUV = 0.5 + (worldPosition - uniforms.cameraCenter) *
        max(uniforms.cameraZoom, 0.000000001) / viewScale;

    AgentRasterData output;
    output.position = occupancy[instanceID] == 0u
        ? float4(3.0, 3.0, 0.0, 1.0)
        : float4(screenUV.x * 2.0 - 1.0, 1.0 - screenUV.y * 2.0, 0.0, 1.0);
    output.local = corner;
    output.worldUV = fract(worldPosition + 1.0);
    output.geneA = agent.geneA;
    output.geneB = agent.geneB;
    output.geneC = agent.geneC;
    output.energy = agent.energy;
    output.biomass = agent.biomass;
    output.age = agent.age;
    output.speed = speed;
    output.behavior = float4(
        dot(agent.behavior.xy, heading),
        dot(agent.behavior.xy, lateral),
        agent.behavior.zw
    );
    output.cellularPhysiology = cellularAggregate.physiology;
    output.tissueMorphology = cellularAggregate.morphology;
    output.tissueDynamics = cellularAggregate.dynamics;
    output.tissueMechanics = cellularAggregate.mechanics;
    output.tissueRegulation = cellularAggregate.regulation;
    output.tissueCausality = cellularAggregate.causality;
    output.tissueSignaling = cellularAggregate.signaling;
    output.tissueSignalCausality = cellularAggregate.signalCausality;
    output.focus = uniforms.trackedAgentID == instanceID ? 1.0 : 0.0;
    output.tracked = uniforms.trackedAgentID == instanceID ? 1.0 : 0.0;
    output.trackingActive = uniforms.trackedAgentID == 0xffffffffu ? 0.0 : 1.0;
    return output;
}

fragment float4 agentFragment(
    AgentRasterData input [[stage_in]],
    texture2d_array<float, access::sample> state [[texture(0)]],
    texture2d_array<float, access::sample> ecology [[texture(1)]],
    texture2d<float, access::sample> quantum [[texture(2)]],
    constant SimulationUniforms& uniforms [[buffer(0)]]
) {
    constexpr sampler fieldSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    constexpr sampler quantumSampler(coord::normalized, address::repeat, filter::linear);
    float2 p = input.local;
    float observationZoom = uniforms.cameraZoom / max(uniforms.worldScale, 1.0);
    float organismEnvelope = 1.0 - smoothstep(14.0, 24.0, observationZoom);
    if (organismEnvelope <= 0.001) { discard_fragment(); }
    float scaleVisibility = 1.0 - smoothstep(18.0, 48.0, observationZoom);
    float focusVisibility = input.trackingActive > 0.5 && input.focus > 0.5
        ? max(scaleVisibility, 1.0 - smoothstep(64.0, 128.0, observationZoom))
        : scaleVisibility;
    if (focusVisibility <= 0.001) { discard_fragment(); }
    float oscillatorCoherence = saturate(input.tissueDynamics.y);
    float pulsePhase = mix(
        float(uniforms.step) * (0.032 + input.geneA.x * 0.018) + input.geneB.w * 11.0,
        input.tissueDynamics.w * 2.0 * M_PI_F,
        oscillatorCoherence
    );
    float pulse = sin(pulsePhase);
    float locomotorSpeed = saturate(input.speed * max(uniforms.worldScale, 1.0) * 16000.0);

    float tissueOccupancy = saturate(input.cellularPhysiology.x / float(cellsPerAgent));
    float tissueRadius = saturate(input.tissueMorphology.z / 0.86);
    float tissueATP = saturate(input.cellularPhysiology.y);
    float tissueIntegrity = saturate(input.cellularPhysiology.z);
    float tissueStress = saturate(input.cellularPhysiology.w);
    float proliferationProgram = saturate(input.tissueRegulation.x);
    float adhesiveProgram = saturate(input.tissueRegulation.y);
    float contractileProgram = saturate(input.tissueRegulation.z);
    float repairProgram = saturate(input.tissueRegulation.w);
    float mechanosensoryPositive = saturate(max(input.tissueCausality.x, 0.0) * 3200.0);
    float mechanosensoryNegative = saturate(max(-input.tissueCausality.x, 0.0) * 3200.0);
    float proliferativeDrive = saturate(input.tissueCausality.y * 900.0);
    float contactSuppression = saturate(-input.tissueCausality.z * 900.0);
    float repairEffect = saturate(input.tissueCausality.w * 5200.0);
    float calciumSignal = saturate(input.tissueSignaling.x);
    float erkSignal = saturate(input.tissueSignaling.y);
    float signalRefractory = saturate(input.tissueSignaling.z);
    float mechanicsCalciumCause = saturate(input.tissueSignalCausality.x * 48.0);
    float calciumERKCause = saturate(input.tissueSignalCausality.y * 56.0);
    float erkTractionCause = saturate(input.tissueSignalCausality.z * 12000.0);
    float signalingCost = saturate(input.tissueSignalCausality.w * 18000.0);
    float synchronizedContraction = input.tissueMechanics.y * oscillatorCoherence;
    float abdomenLength = (0.66 + input.geneB.z * 0.15) * mix(0.82, 1.10, tissueRadius) *
        mix(0.90, 1.12, contractileProgram);
    float abdomenWidth = (0.36 + input.geneA.y * 0.16) * mix(0.72, 1.14, sqrt(tissueOccupancy)) *
        mix(0.86, 1.12, adhesiveProgram);
    abdomenLength *= 1.0 - synchronizedContraction * 0.030;
    abdomenWidth *= 1.0 + synchronizedContraction * 0.045;
    float2 abdomenP = float2((p.x + 0.08) / abdomenLength, p.y / abdomenWidth);
    float abdomenDistance = length(abdomenP);
    float abdomenAA = max(fwidth(abdomenDistance) * 1.15, 0.0025);
    float abdomen = 1.0 - smoothstep(1.0 - abdomenAA, 1.0 + abdomenAA, abdomenDistance);

    float2 headCenter = float2(0.56 + input.geneB.z * 0.04, 0.0);
    float headRadius = (0.19 + input.geneC.w * 0.13 + input.geneA.z * 0.045) *
        mix(0.84, 1.06, tissueIntegrity) * mix(0.91, 1.08, repairProgram);
    float headDistance = length(p - headCenter) / headRadius;
    float headAA = max(fwidth(headDistance) * 1.15, 0.003);
    float head = 1.0 - smoothstep(1.0 - headAA, 1.0 + headAA, headDistance);

    float tailWave = sin((p.x + 0.78) * (10.0 + input.geneB.z * 7.0) + pulsePhase * 1.35) *
        (0.045 + input.geneB.z * 0.055) * (0.55 + locomotorSpeed * 0.45);
    float tailRange = smoothstep(-1.02, -0.80, p.x) * (1.0 - smoothstep(-0.56, -0.45, p.x));
    float tailDistance = abs(p.y - tailWave);
    float tailWidth = 0.036 + input.geneB.z * 0.022;
    float tailAA = max(fwidth(tailDistance) * 1.2, 0.0025);
    float tail = (1.0 - smoothstep(tailWidth - tailAA, tailWidth + tailAA, tailDistance)) * tailRange;

    float gait = pulse * (0.06 + locomotorSpeed * 0.12);
    float appendageWidth = 0.018 + input.geneA.y * 0.024;
    float appendageAA = max(fwidth(p.y) * 1.4, 0.003);
    float appendageReach = (0.48 + input.geneA.z * 0.22) * mix(0.76, 1.06, tissueATP) *
        mix(0.56, 1.18, contractileProgram);
    const float appendageAnchors[3] = { -0.34, -0.07, 0.20 };
    float limbs = 0.0;
    float limbJoints = 0.0;
    for (uint limbIndex = 0; limbIndex < 3; ++limbIndex) {
        float anchorX = appendageAnchors[limbIndex];
        float gaitSign = limbIndex == 1u ? -1.0 : 1.0;
        float tipX = anchorX - 0.14 + gait * gaitSign;
        float rootY = abdomenWidth * (0.70 - float(limbIndex) * 0.035);
        float tipY = appendageReach * (0.82 + float(limbIndex) * 0.08);
        float2 upperRoot = float2(anchorX, rootY);
        float2 upperKnee = float2(anchorX - 0.08 + gait * 0.45, mix(rootY, tipY, 0.48));
        float2 upperTip = float2(tipX, tipY);
        float2 lowerRoot = float2(anchorX, -rootY);
        float2 lowerKnee = float2(anchorX - 0.08 - gait * 0.55, -mix(rootY, tipY, 0.48));
        float2 lowerTip = float2(tipX - gait * 1.4, -tipY);
        float upperLimb = max(
            taperedSegmentMask(p, upperRoot, upperKnee, appendageWidth, appendageWidth * 0.74, appendageAA),
            taperedSegmentMask(p, upperKnee, upperTip, appendageWidth * 0.74, appendageWidth * 0.30, appendageAA)
        );
        float lowerLimb = max(
            taperedSegmentMask(p, lowerRoot, lowerKnee, appendageWidth, appendageWidth * 0.74, appendageAA),
            taperedSegmentMask(p, lowerKnee, lowerTip, appendageWidth * 0.74, appendageWidth * 0.30, appendageAA)
        );
        limbs = max(limbs, max(upperLimb, lowerLimb));
        float jointRadius = appendageWidth * 1.18;
        limbJoints = max(limbJoints, 1.0 - smoothstep(jointRadius - appendageAA,
            jointRadius + appendageAA, min(length(p - upperKnee), length(p - lowerKnee))));
    }
    limbs *= 0.24 + input.geneA.z * 0.76;

    float defenseInvestment = smoothstep(0.48, 0.90, input.geneA.w);
    float spines = 0.0;
    const float spineAnchors[3] = { -0.38, -0.12, 0.15 };
    for (uint spineIndex = 0; spineIndex < 3; ++spineIndex) {
        float spineX = spineAnchors[spineIndex];
        float spineLength = 0.10 + input.geneA.w * 0.14;
        float upperSpine = segmentDistance(p, float2(spineX, abdomenWidth * 0.80),
            float2(spineX - 0.035, abdomenWidth + spineLength));
        float lowerSpine = segmentDistance(p, float2(spineX, -abdomenWidth * 0.80),
            float2(spineX - 0.035, -abdomenWidth - spineLength));
        spines = max(spines, 1.0 - smoothstep(0.012, 0.012 + appendageAA,
            min(upperSpine, lowerSpine)));
    }
    spines *= defenseInvestment;

    float predatoryInvestment = smoothstep(0.08, 0.38, input.geneC.w);
    float jawAperture = 0.10 + predatoryInvestment *
        (0.08 + 0.035 * (0.5 + 0.5 * pulse) + input.behavior.z * 0.075);
    float jawTop = 1.0 - smoothstep(0.020, 0.020 + appendageAA, segmentDistance(
        p, headCenter + float2(headRadius * 0.48, 0.025), float2(0.98, jawAperture)
    ));
    float jawBottom = 1.0 - smoothstep(0.020, 0.020 + appendageAA, segmentDistance(
        p, headCenter + float2(headRadius * 0.48, -0.025), float2(0.98, -jawAperture)
    ));
    float jaws = max(jawTop, jawBottom) * predatoryInvestment;

    float body = max(max(abdomen, head), max(max(tail, limbs), max(spines, jaws)));
    float trackedRing = input.tracked *
        (1.0 - smoothstep(0.010, 0.026, abs(length(p) - 0.91))) *
        smoothstep(0.34, 0.48, 0.5 + 0.5 * sin(atan2(p.y, p.x) * 12.0 - pulsePhase));
    if (max(body, trackedRing) <= 0.001) { discard_fragment(); }

    float abdomenEdge = abdomen * smoothstep(0.72, 0.97, abdomenDistance);
    float headEdge = head * smoothstep(0.64, 0.95, headDistance);
    float edge = max(max(abdomenEdge, headEdge), max(spines, jaws));
    float interior = abdomen * (1.0 - smoothstep(0.38, 0.82, abdomenDistance));
    float sensorA = 1.0 - smoothstep(0.022, 0.022 + appendageAA,
        length(p - headCenter - float2(headRadius * 0.24, headRadius * 0.34)));
    float sensorB = 1.0 - smoothstep(0.022, 0.022 + appendageAA,
        length(p - headCenter - float2(headRadius * 0.24, -headRadius * 0.34)));
    float sensor = max(sensorA, sensorB) * head;

    float3 lineage = hsvToRGB(float3(input.geneB.w, 0.82, 0.62 + input.geneA.w * 0.24));
    float3 defenseColor = float3(0.02, 0.95, 0.64);
    float3 predatorColor = float3(1.0, 0.045, 0.012);
    float3 rim = mix(defenseColor, predatorColor, saturate(input.geneC.w * 1.35));
    float energy = saturate(input.energy / 1.25);
    float bodyBulge = sqrt(saturate(1.0 - abdomenDistance * abdomenDistance));
    float3 surfaceNormal = normalize(float3(abdomenP.x * 0.42, abdomenP.y * 0.62,
        max(bodyBulge, 0.08)));
    float3 lightDirection = normalize(float3(-0.42, 0.58, 0.74));
    float diffuse = 0.34 + 0.66 * saturate(dot(surfaceNormal, lightDirection));
    float specular = pow(saturate(dot(surfaceNormal, normalize(lightDirection + float3(0.0, 0.0, 1.0)))),
        28.0 + input.geneA.y * 52.0) * abdomen;
    float nicheTotal = max(input.geneC.x + input.geneC.y + input.geneC.z, 0.001);
    float3 nicheColor = (input.geneC.x * float3(0.02, 0.78, 0.94) +
        input.geneC.y * float3(1.0, 0.52, 0.025) +
        input.geneC.z * float3(0.86, 0.08, 0.78)) / nicheTotal;
    float3 bodyColor = mix(lineage, nicheColor, 0.16 + input.geneB.x * 0.20);
    bodyColor = mix(bodyColor, float3(0.72, 0.055, 0.025), tissueStress * 0.42);
    float voltagePolarity = saturate(input.tissueDynamics.x * 0.30 + 0.5);
    float3 voltageColor = mix(float3(0.03, 0.42, 1.0), float3(1.0, 0.10, 0.025), voltagePolarity);
    bodyColor = mix(bodyColor, voltageColor, oscillatorCoherence * 0.16);
    float3 color = bodyColor * body * diffuse * (0.60 + input.biomass * 0.40);
    color += rim * edge * (0.42 + input.geneA.w * 0.72) * (0.34 + tissueIntegrity * 0.66);
    color += float3(1.0, 0.69, 0.045) * interior * energy * energy * 0.40;
    color += float3(0.84, 0.98, 1.0) * sensor * 1.34;
    color += predatorColor * jaws * (0.72 + input.geneC.w * 1.18);
    color += float3(0.84, 0.96, 1.0) * specular * (0.14 + input.geneA.y * 0.24);
    color += rim * limbJoints * (0.24 + input.geneA.z * 0.34);
    color += float3(0.12, 0.92, 1.0) * trackedRing * 1.8;
    float pursuitStrength = length(input.behavior.xy);
    float2 pursuitDirection = pursuitStrength > 0.0001
        ? input.behavior.xy / pursuitStrength
        : float2(1.0, 0.0);
    float pursuitPath = 1.0 - smoothstep(0.012, 0.035, segmentDistance(
        p, headCenter + pursuitDirection * headRadius * 0.42,
        headCenter + pursuitDirection * (0.34 + pursuitStrength * 0.34)
    ));
    pursuitPath *= pursuitStrength * (1.0 - head) * predatoryInvestment;
    color += mix(float3(1.0, 0.42, 0.02), predatorColor, input.behavior.z) * pursuitPath * 0.92;
    color += float3(1.0, 0.08, 0.18) * edge * input.behavior.w *
        (0.32 + 0.24 * sin(pulsePhase * 2.3));
    float resonanceBand = (1.0 - smoothstep(0.025, 0.075,
        abs(fract(abdomenDistance * 3.4 - input.tissueDynamics.w) - 0.5))) * abdomen;
    color += voltageColor * resonanceBand * oscillatorCoherence *
        (0.10 + synchronizedContraction * 0.34);

    float organismReveal = smoothstep(4.0, 18.0, observationZoom);
    float chemistryReveal = smoothstep(18.0, 58.0, observationZoom);
    float quantumReveal = smoothstep(52.0, 160.0, observationZoom);
    float latticeReveal = smoothstep(420.0, 980.0, observationZoom);
    float tissueNoiseA = visualNoise(p * (16.0 + input.geneB.x * 9.0) + input.geneA.xy * 17.0);
    float tissueNoiseB = visualNoise(p * 31.0 + input.geneA.zw * 29.0);
    float channels = (1.0 - smoothstep(0.035, 0.14, abs(tissueNoiseA - tissueNoiseB))) * abdomen;
    float segmentCount = 3.0 + floor(input.geneB.x * 5.0);
    float segmentCoordinate = saturate((p.x + abdomenLength * 0.92) / (abdomenLength * 1.72));
    float segmentPhase = fract(segmentCoordinate * segmentCount);
    float segmentRidge = (1.0 - smoothstep(0.035, 0.12, min(segmentPhase, 1.0 - segmentPhase))) *
        abdomen * smoothstep(0.42, 0.92, abdomenDistance);
    float pigmentation = smoothstep(0.58 + input.geneA.x * 0.16, 0.94, tissueNoiseA * 0.62 + tissueNoiseB * 0.38) *
        abdomen * (1.0 - abdomenEdge);
    float nucleusRadius = 0.095 + input.geneB.x * 0.045;
    float nucleus = (1.0 - smoothstep(nucleusRadius, nucleusRadius * 1.55,
        length(p - float2(-0.12, (input.geneA.z - 0.5) * 0.12)))) * abdomen;
    float reproductionReadiness = smoothstep(0.88, 1.06, input.energy) * smoothstep(560.0, 720.0, input.age);
    float broodPulse = reproductionReadiness * (0.72 + 0.28 * sin(pulsePhase * 1.7)) * nucleus;
    color += mix(float3(0.03, 0.58, 0.98), float3(0.98, 0.59, 0.04), input.geneA.x) *
        channels * organismReveal * 0.22;
    color += nicheColor * pigmentation * organismReveal * 0.34;
    color += rim * segmentRidge * organismReveal * (0.18 + input.geneA.w * 0.28);
    color += float3(0.98, 0.08, 0.74) * nucleus * organismReveal * 0.74;
    color += float3(0.98, 0.92, 0.30) * broodPulse * organismReveal * 1.10;
    float signalFront = (1.0 - smoothstep(0.030, 0.105,
        abs(abdomenDistance - (0.24 + signalRefractory * 0.62)))) * abdomen;
    float signalConduit = channels * (0.38 + 0.62 * calciumSignal);
    color += float3(0.02, 0.88, 1.0) * signalFront * calciumSignal * organismReveal * 0.78;
    color += float3(0.98, 0.08, 0.66) * signalConduit * erkSignal * organismReveal * 0.54;
    color += float3(0.08, 1.0, 0.56) * max(limbs, tail) * erkTractionCause *
        organismReveal * 0.44;

    float4 localState = state.sample(fieldSampler, input.worldUV, 0);
    float4 localEcology = ecology.sample(fieldSampler, input.worldUV, 0);
    float potential = saturate((localState.x + localEcology.x * 0.8 + localState.y * 2.2 +
        localState.w * 3.0 + localEcology.z * 1.4) * 0.55);
    float bands = 1.0 - smoothstep(0.07, 0.19, abs(fract(potential * 31.0 + tissueNoiseA * 0.25) - 0.5));
    float3 chemistryColor = mix(float3(0.02, 0.30, 0.82), float3(0.04, 1.0, 0.52), potential);
    chemistryColor = mix(chemistryColor, float3(1.0, 0.12, 0.025), saturate(localEcology.z * 1.4));
    chemistryColor *= 0.48 + bands * 0.52;
    color = mix(color, chemistryColor, chemistryReveal * abdomen);
    color += float3(0.68, 1.0, 0.88) * edge * chemistryReveal * 0.48;

    if (quantumReveal > 0.001) {
        float4 wave = quantum.sample(quantumSampler, input.worldUV);
        float2 quantumTexel = 1.0 / float(quantumGridSize);
        float4 waveRight = quantum.sample(quantumSampler, input.worldUV + float2(quantumTexel.x, 0.0));
        float4 waveUp = quantum.sample(quantumSampler, input.worldUV + float2(0.0, quantumTexel.y));
        float4 waveDiagonal = quantum.sample(quantumSampler, input.worldUV + quantumTexel);
        float probabilityA = dot(wave.xy, wave.xy);
        float probabilityB = dot(wave.zw, wave.zw);
        float probability = probabilityA + probabilityB;
        float phase = spinorPhase(wave);
        float phaseRight = spinorPhase(waveRight);
        float phaseUp = spinorPhase(waveUp);
        float phaseDiagonal = spinorPhase(waveDiagonal);
        float phaseWinding = abs(
            wrappedPhaseDelta(phase, phaseRight) +
            wrappedPhaseDelta(phaseRight, phaseDiagonal) +
            wrappedPhaseDelta(phaseDiagonal, phaseUp) +
            wrappedPhaseDelta(phaseUp, phase)
        );
        float density = 1.0 - exp(-probability * 285000.0);
        float polarization = (probabilityA - probabilityB) / max(probability, 0.0000000001);
        float2 current = float2(
            complexCurrent(wave.xy, waveRight.xy) + complexCurrent(wave.zw, waveRight.zw),
            complexCurrent(wave.xy, waveUp.xy) + complexCurrent(wave.zw, waveUp.zw)
        );
        float currentMagnitude = length(current);
        float currentStrength = saturate(currentMagnitude * 950000.0);
        float2 currentDirection = current / max(currentMagnitude, 0.0000000001);
        float phaseContour = 0.60 + 0.40 * cos(phase * 28.0 * M_PI_F);
        float flowCoordinate = fract(dot(input.worldUV * float(quantumGridSize), currentDirection) * 0.22 -
            float(uniforms.step) * 0.012);
        float currentPulse = 1.0 - smoothstep(0.035, 0.13, abs(flowCoordinate - 0.5));
        float3 spinColor = mix(float3(1.0, 0.22, 0.025), float3(0.02, 0.82, 1.0),
            polarization * 0.5 + 0.5);
        float3 quantumColor = mix(quantumPhaseColor(phase), spinColor, 0.38) *
            density * (0.52 + phaseContour * 0.48);
        quantumColor += float3(0.82, 0.97, 1.0) * currentPulse * currentStrength * density * 0.68;
        float logDensity = log2(1.0 + probability * 1200000.0);
        float densityIsoline = 1.0 - smoothstep(0.025, 0.095,
            abs(fract(logDensity * 2.4) - 0.5));
        float vortexCore = smoothstep(0.55, 0.92, phaseWinding) *
            (1.0 - smoothstep(0.025, 0.28, density));
        quantumColor += float3(0.38, 0.92, 1.0) * densityIsoline * density * 0.18;
        quantumColor += float3(1.0, 0.08, 0.72) * vortexCore * 1.65;

        float3 spinorTile = spinorCellVisualization(input.worldUV, wave, currentStrength);
        quantumColor = mix(quantumColor, spinorTile, latticeReveal);
        color = mix(color, quantumColor, quantumReveal * abdomen);
        color += rim * edge * quantumReveal * (0.18 + currentStrength * 0.52);
    }

    if (uniforms.displayMode == 1) {
        color = mix(color, float3(localState.x, localEcology.x, localEcology.y) * body * 1.3, 0.72);
    } else if (uniforms.displayMode == 2) {
        color = input.geneA.xyz * body * 0.82 + lineage * edge;
    } else if (uniforms.displayMode == 3) {
        float enzymes = max(input.geneC.x + input.geneC.y + input.geneC.z, 0.001);
        color = input.geneC.xyz / enzymes * body * 1.2 + predatorColor * input.geneC.w * head;
    } else if (uniforms.displayMode == 4) {
        float3 regulatoryColor = proliferationProgram * float3(0.98, 0.82, 0.08) +
            adhesiveProgram * float3(0.08, 0.90, 0.66) +
            contractileProgram * float3(0.96, 0.16, 0.46) +
            repairProgram * float3(0.18, 0.50, 1.0);
        regulatoryColor /= max(
            proliferationProgram + adhesiveProgram + contractileProgram + repairProgram, 0.001
        );
        color = regulatoryColor * body * (0.48 + tissueATP * 0.48) +
            float3(0.94, 0.98, 1.0) * edge * tissueIntegrity * 0.34;
    } else if (uniforms.displayMode == 5) {
        float causalBand = (1.0 - smoothstep(0.035, 0.11,
            abs(fract((p.x + 1.1) * 3.2 - pulsePhase * 0.045) - 0.5))) * abdomen;
        float3 mechanosensoryColor = float3(0.02, 0.86, 1.0) * mechanosensoryPositive +
            float3(0.30, 0.20, 1.0) * mechanosensoryNegative;
        color = float3(0.008, 0.012, 0.018) * body;
        color += mechanosensoryColor * edge * (0.42 + causalBand * 0.70);
        color += float3(1.0, 0.76, 0.04) * proliferativeDrive * nucleus * 1.25;
        color += float3(0.02, 0.94, 0.62) * contactSuppression * segmentRidge * 1.10;
        color += float3(0.12, 0.46, 1.0) * repairEffect * edge * 1.20;
        color += float3(0.02, 0.88, 1.0) * mechanicsCalciumCause * signalFront * 1.55;
        color += float3(0.98, 0.08, 0.66) * calciumERKCause * signalConduit * 1.40;
        color += float3(0.08, 1.0, 0.56) * erkTractionCause * max(limbs, tail) * 1.55;
        color += float3(1.0, 0.42, 0.02) * signalingCost *
            (0.35 + tissueNoiseA * 0.65) * interior * 0.32;
    }
    color += float3(0.12, 0.92, 1.0) * trackedRing * 1.8;
    float alpha = saturate(max(body, trackedRing)) * focusVisibility * organismEnvelope;
    return float4(max(color, 0.0) * focusVisibility * 0.84, alpha);
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
    float lineageHue;
    float ownerEnergy;
    float visibility;
    float tracked;
    float radialCoordinate;
};

vertex CellRasterData cellVertex(
    device const AgentState* agents [[buffer(0)]],
    device const uint* agentOccupancy [[buffer(1)]],
    device const CellState* cells [[buffer(2)]],
    device const uint* cellOccupancy [[buffer(3)]],
    device const MembraneVertex* membraneVertices [[buffer(4)]],
    constant SimulationUniforms& uniforms [[buffer(5)]],
    device const uint* visibleCellIndices [[buffer(6)]],
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]]
) {
    uint cellIndex = visibleCellIndices[instanceID];
    uint owner = cellIndex / cellsPerAgent;
    AgentState agent = agents[owner];
    CellState cell = cells[cellIndex];
    float observationZoom = uniforms.cameraZoom / max(uniforms.worldScale, 1.0);
    float scaleVisibility = smoothstep(5.0, 11.0, observationZoom) *
        (1.0 - smoothstep(112.0, 180.0, observationZoom));
    float trackingVisibility = uniforms.trackedAgentID == 0xffffffffu ||
        uniforms.trackedAgentID == owner ? 1.0 : 1.0 - smoothstep(16.0, 34.0, observationZoom);
    float visibility = scaleVisibility * trackingVisibility;

    float speed = length(agent.velocity);
    float inheritedAngle = agent.geneB.w * 2.0 * M_PI_F;
    float2 heading = speed > 0.000001
        ? agent.velocity / speed
        : float2(cos(inheritedAngle), sin(inheritedAngle));
    float2 lateral = float2(-heading.y, heading.x);
    float bodyWorldRadius = (0.012 + 0.0045 * agent.geneB.z + 0.0025 * agent.biomass) /
        max(uniforms.worldScale, 1.0);
    float2 cellCenter = agent.position + heading * cell.position.x * bodyWorldRadius +
        lateral * cell.position.y * bodyWorldRadius * 0.72;
    uint triangle = vertexID / 3u;
    uint triangleVertex = vertexID % 3u;
    uint membraneIndex = triangleVertex == 1u
        ? triangle
        : (triangleVertex == 2u ? (triangle + 1u) % membraneVertexCount : 0u);
    float2 membranePosition = triangleVertex == 0u
        ? float2(0.0)
        : membraneVertices[cellIndex * membraneVertexCount + membraneIndex].position;
    float2 worldPosition = cellCenter +
        heading * membranePosition.x * bodyWorldRadius +
        lateral * membranePosition.y * bodyWorldRadius * 0.72;
    float safeAspect = max(uniforms.viewportAspect, 0.001);
    float2 viewScale = safeAspect >= 1.0 ? float2(1.0, 1.0 / safeAspect) : float2(safeAspect, 1.0);
    float2 screenUV = 0.5 + (worldPosition - uniforms.cameraCenter) *
        max(uniforms.cameraZoom, 0.000000001) / viewScale;
    bool occupied = owner < maxAgentCount && cellIndex < maxCellCount &&
        agentOccupancy[owner] != 0u && cellOccupancy[cellIndex] != 0u && visibility > 0.001;

    CellRasterData output;
    output.position = occupied
        ? float4(screenUV.x * 2.0 - 1.0, 1.0 - screenUV.y * 2.0, 0.0, 1.0)
        : float4(3.0, 3.0, 0.0, 1.0);
    float nominalRadius = clamp(sqrt(max(cell.membrane.x, 0.010) / M_PI_F), 0.085, 0.18);
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
    output.lineageHue = agent.geneB.w;
    output.ownerEnergy = agent.energy;
    output.visibility = visibility;
    output.tracked = uniforms.trackedAgentID == owner ? 1.0 : 0.0;
    output.radialCoordinate = triangleVertex == 0u ? 0.0 : 1.0;
    return output;
}

fragment float4 cellFragment(
    CellRasterData input [[stage_in]],
    constant SimulationUniforms& uniforms [[buffer(0)]]
) {
    float2 p = input.local;
    float angle = atan2(p.y, p.x);
    float oscillatorAngle = input.dynamics.z * 2.0 * M_PI_F;
    float2 polarityVector = float2(
        input.signals.x - input.signals.y,
        input.dynamics.x * 0.22 + sin(oscillatorAngle) * 0.10
    );
    float2 morphologyAxis = length(polarityVector) > 0.001
        ? normalize(polarityVector)
        : float2(cos(oscillatorAngle), sin(oscillatorAngle));
    float2 morphologyNormal = float2(-morphologyAxis.y, morphologyAxis.x);
    float radius = input.radialCoordinate;
    float aa = max(fwidth(radius) * 1.15, 0.004);
    float body = 1.0;
    if (body <= 0.001) { discard_fragment(); }

    float integrity = saturate(input.physiology.w);
    float membrane = body * smoothstep(0.72 - integrity * 0.10, 0.98, radius);
    float cytoplasm = body * (1.0 - smoothstep(0.62, 0.94, radius));
    float nucleusRadius = 0.20 + input.signals.x * 0.08;
    float2 nucleusPosition = float2((input.signals.x - input.signals.y) * 0.12, 0.0);
    float nucleus = (1.0 - smoothstep(nucleusRadius, nucleusRadius + aa * 2.0,
        length(p - nucleusPosition))) * body;
    float coarseObservationZoom = uniforms.cameraZoom / max(uniforms.worldScale, 1.0);
    if (coarseObservationZoom < 14.0) {
        float coarseATP = saturate(input.physiology.x);
        float coarseCalcium = saturate(input.signaling.x);
        float coarseERK = saturate(input.signaling.y);
        float coarseVoltage = saturate(input.dynamics.x * 0.30 + 0.5);
        float3 coarseLineage = hsvToRGB(float3(input.lineageHue, 0.78, 0.62));
        float3 coarseVoltageColor = mix(
            float3(0.02, 0.34, 1.0), float3(1.0, 0.08, 0.02), coarseVoltage
        );
        float3 coarseColor = coarseLineage * cytoplasm * (0.28 + coarseATP * 0.46);
        coarseColor += coarseVoltageColor * membrane * (0.30 + integrity * 0.34);
        coarseColor += float3(0.02, 0.88, 1.0) * coarseCalcium * membrane * 0.52;
        coarseColor += float3(0.98, 0.08, 0.66) * coarseERK * nucleus * 0.74;
        if (uniforms.displayMode == 5) {
            float mechanicsCalcium = saturate(input.signalCausality.x * 48.0);
            float calciumERK = saturate(input.signalCausality.y * 56.0);
            float erkTraction = saturate(input.signalCausality.z * 12000.0);
            coarseColor = float3(0.008, 0.014, 0.022) * body;
            coarseColor += float3(0.02, 0.88, 1.0) * mechanicsCalcium * membrane * 1.24;
            coarseColor += float3(0.98, 0.08, 0.66) * calciumERK * nucleus * 1.36;
            coarseColor += float3(0.08, 1.0, 0.56) * erkTraction * cytoplasm * 0.82;
        }
        float coarseAlpha = body * input.visibility * (1.0 - saturate(input.signals.w) * 0.35);
        return float4(max(coarseColor, 0.0) * input.visibility, coarseAlpha);
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
    float3 color = mix(lineage, phenotypeColor, 0.42) * cytoplasm * (0.22 + atp * 0.46);
    float centralProgram = saturate(input.signals.x - input.signals.y + 0.5);
    float3 differentiatedLineage = mix(lineage,
        mix(float3(0.04, 0.56, 0.92), float3(0.92, 0.38, 0.04), 1.0 - centralProgram), 0.34);
    color = mix(color, differentiatedLineage * cytoplasm * (0.24 + atp * 0.34), 0.42);
    color = mix(color, phaseColor * cytoplasm * (0.30 + atp * 0.30), 0.24);
    color += resonanceColor * membrane * saturate(input.resonance.z * 18.0) * 0.72;
    float3 membraneColor = mix(differentiatedLineage, voltageColor, 0.58);
    color += membraneColor * membrane * (0.30 + integrity * 0.34);
    color += float3(1.0, 0.58, 0.025) * mitochondria * atp * 0.62;
    color += mix(float3(0.86, 0.06, 0.68), lineage, 0.34) * nucleus * 0.72;
    color += float3(0.96, 0.90, 0.58) * cleavage * cycle * 0.56;
    color += float3(1.0, 0.76, 0.04) * proliferativeEnvelope * (0.32 + cycle * 0.54);
    color += float3(1.0, 0.16, 0.42) * actomyosinFiber * input.mechanics.x * 0.34;
    color += mix(float3(0.08, 0.90, 1.0), float3(0.18, 1.0, 0.56), input.phenotype.x) *
        junction * 0.54;
    float mechanosensoryPositive = saturate(max(input.interaction.w, 0.0) * 3200.0);
    float mechanosensoryNegative = saturate(max(-input.interaction.w, 0.0) * 3200.0);
    float2 membraneDirection = length(p) > 0.001 ? normalize(p) : morphologyAxis;
    float membranePolarity = smoothstep(0.52, 0.94, abs(dot(membraneDirection, morphologyAxis))) * membrane;
    color += float3(0.02, 0.88, 1.0) * membranePolarity * mechanosensoryPositive * 0.82;
    color += float3(0.34, 0.18, 1.0) * membranePolarity * mechanosensoryNegative * 0.72;
    color = mix(color, float3(0.94, 0.055, 0.018) * body, stress * 0.34);
    color *= 1.0 - apoptosis * (0.46 + 0.28 * mitochondriaPattern);
    color += float3(0.76, 0.12, 1.0) * apoptosis * membrane * 0.66;
    color += float3(0.10, 0.92, 1.0) * input.tracked * membrane * 0.24;
    float contractionRing = (1.0 - smoothstep(0.020, 0.060,
        abs(radius - (0.50 + input.mechanics.x * 0.17)))) * cytoplasm;
    color += phaseColor * contractionRing * input.mechanics.x * (0.26 + input.mechanics.w * 0.40);
    float strainAxis = 1.0 - smoothstep(0.020, 0.070,
        abs(dot(p, float2(cos(oscillatorAngle), sin(oscillatorAngle)))));
    color += float3(0.04, 0.88, 1.0) * strainAxis * cytoplasm * input.mechanics.y * 0.72;
    float netPower = input.energetics.x - input.energetics.y - input.energetics.z - input.energetics.w;
    color += mix(float3(0.82, 0.06, 0.03), float3(1.0, 0.72, 0.02), step(0.0, netPower)) *
        mitochondria * saturate(abs(netPower) * 5200.0) * 0.48;
    float repairPatch = smoothstep(0.62, 0.86,
        visualNoise(p * 19.0 + float2(input.lineageHue * 23.0, input.dynamics.z * 17.0))) *
        membrane * input.regulation.w * (1.0 - integrity);
    color += float3(0.12, 0.48, 1.0) * repairPatch * 1.15;
    float calciumFrontRadius = 0.20 + signalRefractory * 0.58;
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
        float3 regulatoryColor = input.regulation.x * regulatoryColors[0] +
            input.regulation.y * regulatoryColors[1] +
            input.regulation.z * regulatoryColors[2] +
            input.regulation.w * regulatoryColors[3];
        regulatoryColor /= max(input.regulation.x + input.regulation.y +
            input.regulation.z + input.regulation.w, 0.001);
        color = regulatoryColor * cytoplasm * (0.40 + atp * 0.52) +
            regulatoryEmission * nucleus * 1.8 + voltageColor * membrane * 0.36;
    } else if (uniforms.displayMode == 5) {
        float unconstrainedCycleDrive = 0.00145 * smoothstep(0.40, 0.72, atp) *
            mix(0.12, 1.62, input.regulation.x) * (1.0 - stress);
        float contactInhibition = input.interaction.z /
            max(0.62 + input.regulation.y * 0.30, 0.001);
        float contactEffect = saturate((input.interaction.z * unconstrainedCycleDrive +
            contactInhibition * 0.00022) * 3000.0);
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
        color += float3(0.92, 0.97, 1.0) * nucleus * 0.20;
    }

    float observationZoom = uniforms.cameraZoom / max(uniforms.worldScale, 1.0);
    float cellDetail = smoothstep(14.0, 30.0, observationZoom);
    color = mix(lineage * body * (0.32 + atp * 0.44), color, cellDetail);
    float alpha = body * input.visibility * mix(0.62, 0.94, cellDetail) * (1.0 - apoptosis * 0.35);
    return float4(max(color, 0.0) * input.visibility, alpha);
}

fragment float4 quantumSurfaceFragment(
    RasterData input [[stage_in]],
    texture2d<float, access::sample> quantum [[texture(0)]],
    texture2d_array<float, access::sample> state [[texture(1)]],
    texture2d_array<float, access::sample> ecology [[texture(2)]],
    constant SimulationUniforms& uniforms [[buffer(0)]]
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
    bool resolvesLatticeCells = observationZoom >= 420.0;
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
    float2 current = float2(
        complexCurrent(wave.xy, waveRight.xy) + complexCurrent(wave.zw, waveRight.zw),
        complexCurrent(wave.xy, waveUp.xy) + complexCurrent(wave.zw, waveUp.zw)
    );
    float currentMagnitude = length(current);
    float currentStrength = saturate(currentMagnitude * 950000.0);
    float latticeReveal = smoothstep(420.0, 900.0, observationZoom);
    if (latticeReveal >= 0.999) {
        float3 spinorTile = spinorCellVisualization(uv, wave, currentStrength);
        return float4(max(spinorTile, 0.0) * 1.16, 1.0);
    }

    float density = 1.0 - exp(-probability * 285000.0);
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
    waveColor += float3(0.38, 0.92, 1.0) * densityIsoline * density * 0.18;
    waveColor += float3(1.0, 0.08, 0.72) * vortexCore * 1.65;

    float4 localState = state.sample(fieldSampler, uv, 0);
    float4 localEcology = ecology.sample(fieldSampler, uv, 0);
    float resourcePotential = saturate(localState.x * 0.54 + localEcology.x * 0.46);
    float storedEnergy = saturate(localState.z * 12.0);
    float membrane = saturate(localState.w * 18.0);
    float catalyst = saturate(localEcology.w * 8.0);
    float toxin = saturate(localEcology.z * 1.35);
    float potential = saturate(
        localState.x + localEcology.x * 0.8 + localState.y * 2.2 +
        localState.w * 3.0 + localEcology.z * 1.4
    );
    float potentialBands = 1.0 - smoothstep(0.055, 0.18, abs(fract(potential * 37.0) - 0.5));
    float3 chemistryColor = float3(0.003, 0.007, 0.014);
    chemistryColor += mix(float3(0.01, 0.22, 0.62), float3(0.02, 0.92, 0.48), resourcePotential) *
        resourcePotential * 0.62;
    chemistryColor += float3(1.0, 0.66, 0.035) * storedEnergy * 0.82;
    chemistryColor += float3(0.20, 1.0, 0.74) * membrane * (0.48 + potentialBands * 0.52);
    chemistryColor += float3(0.96, 0.09, 0.76) * catalyst * density * 0.68;
    chemistryColor += float3(1.0, 0.025, 0.012) * toxin * 0.42;

    float waveReveal = smoothstep(36.0, 110.0, observationZoom);
    float3 color = mix(chemistryColor, waveColor, waveReveal);
    color += mix(float3(0.03, 0.34, 0.84), float3(0.05, 0.96, 0.55), potential) *
        potentialBands * (1.0 - waveReveal) * density * 0.26;

    float3 spinorTile = spinorCellVisualization(uv, wave, currentStrength);
    color = mix(color, spinorTile, latticeReveal);

    return float4(max(color, 0.0) * 1.16, 1.0);
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
    float4 biologicalEvents = events.sample(fieldSampler, uv, 0);
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
    float resourcePotential = cell.x * 0.62 + chemistry.x * 0.52 + chemistry.y * 0.22;
    float resourceIsoline = 1.0 - smoothstep(0.025, 0.095,
        abs(fract(resourcePotential * 13.0 + terrain * 0.12) - 0.5));
    float ecotone = smoothstep(0.025, 0.22, abs(resourceA - resourceB)) *
        smoothstep(0.02, 0.24, min(resourceA, resourceB));
    float nutrientBed = smoothstep(0.16, 0.66, geology.x + (terrain - 0.5) * 0.30);
    float mineralBed = smoothstep(0.16, 0.66, geology.y + (fineTerrain - 0.5) * 0.34);
    float grain = visualNoise(uv * float2(uniforms.width, uniforms.height) * 0.84 + float2(11.0, 3.0));
    float nutrient = nutrientBed * mix(0.12, 1.0, smoothstep(0.58, 0.88, grain));
    float mineral = mineralBed * mix(0.10, 1.0, smoothstep(0.64, 0.91, 1.0 - grain));
    float hazardPulse = 0.68 + 0.32 * sin(float(uniforms.step) * 0.016 +
        (uv.x * 13.0 - uv.y * 9.0) * M_PI_F);
    float fissure = 1.0 - smoothstep(0.025, 0.12,
        abs(sin((uv.x * 17.0 + uv.y * 23.0 + terrain * 0.8) * M_PI_F)));
    float hazard = toxin * (0.18 + fissure * 0.82) * hazardPulse;
    float vibration = saturate(length(localMechanical.xy) * 16.0 + length(localMechanical.zw) * 72.0);

    float3 color;
    if (uniforms.displayMode == 1) {
        color = float3(0.002, 0.006, 0.012);
        color += float3(0.00, 0.42, 0.90) * resourceA;
        color += float3(0.66, 0.04, 0.78) * resourceB;
        color += float3(1.00, 0.45, 0.015) * detritus;
        color += float3(1.00, 0.04, 0.015) * toxin * 0.72;
    } else if (uniforms.displayMode == 2) {
        float fieldEdge = smoothstep(0.015, 0.16, abs(resourceA - resourceB));
        color = float3(0.0025, 0.005, 0.011) * (0.84 + terrain * 0.28);
        color += float3(0.04, 0.10, 0.14) * fieldEdge * 0.42;
    } else if (uniforms.displayMode == 3) {
        color = float3(0.002, 0.006, 0.010);
        color += float3(0.00, 0.76, 0.42) * resourceA * 0.46;
        color += float3(1.00, 0.50, 0.02) * resourceB * 0.48;
        color += float3(0.78, 0.08, 0.95) * detritus * 0.42;
        color += float3(1.00, 0.025, 0.012) * hazard * 0.72;
    } else {
        color = float3(0.0025, 0.006, 0.012) * (0.72 + terrain * 0.40);
        color += float3(0.00, 0.045, 0.055) * resourceA;
        color += float3(0.045, 0.007, 0.064) * resourceB;
        color *= 1.0 - rock * 0.76;
        float3 rockNormal = normalize(float3(-rockSlope * 15.0, 0.42));
        float rockLight = 0.32 + 0.68 * saturate(dot(rockNormal, normalize(float3(-0.44, 0.56, 0.70))));
        float rockStrata = 0.72 + 0.28 * sin((geology.w * 11.0 + fineTerrain * 2.0) * M_PI_F);
        color += float3(0.065, 0.082, 0.090) * rock * rockLight * rockStrata;
        color += float3(0.42, 0.50, 0.50) * rockRim * (0.18 + rockLight * 0.32);
        color += float3(0.02, 0.82, 0.48) * nutrient * (1.0 - rock) * 0.40;
        color += float3(1.0, 0.56, 0.025) * mineral * (1.0 - rock) * 0.48;
        color += mix(float3(0.02, 0.42, 0.92), float3(0.86, 0.06, 0.66),
            saturate(0.5 + atan2(localMechanical.w, localMechanical.z) / (2.0 * M_PI_F))) *
            vibration * (1.0 - rock) * 0.16;
        color += float3(1.0, 0.025, 0.012) * hazard * 0.66;
        color += mix(float3(0.02, 0.44, 0.78), float3(0.06, 0.92, 0.54),
            saturate(resourceA / max(resourceA + resourceB, 0.001))) *
            resourceIsoline * resourceFlux * (1.0 - rock) * 0.18;
        color += float3(0.72, 0.12, 0.94) * ecotone * (1.0 - rock) * 0.10;
    }

    if (uniforms.displayMode == 0) {
        float birth = pow(saturate(biologicalEvents.x), 2.2);
        float mutation = pow(saturate(biologicalEvents.y), 2.0);
        float conflict = pow(saturate(biologicalEvents.z), 2.1);
        float death = pow(saturate(biologicalEvents.w), 2.0);
        color += float3(0.00, 0.96, 0.80) * birth * 0.48;
        color += float3(0.96, 0.08, 0.72) * mutation * 0.42;
        color += float3(1.00, 0.08, 0.018) * conflict * 0.58;
        color += float3(0.42, 0.14, 0.96) * death * 0.46;
    }

    return float4(max(color, 0.0) * 1.08, 1.0);
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
    float4 localEvents = events.sample(fieldSampler, uv, 0);
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
    color += float3(0.12, 0.18, 0.20) * matrixStrain * 0.32;
    color += mix(float3(0.025, 0.46, 1.0), float3(1.0, 0.08, 0.64),
        saturate(waveAngle / (2.0 * M_PI_F) + 0.5)) * waveFront * waveSpeed * 0.52;
    color += float3(0.06, 0.88, 0.76) * mechanicalStrain * (0.18 + waveFront * 0.34);
    color += mix(float3(0.01, 0.28, 0.48), float3(0.02, 0.58, 0.32), potential) *
        potentialContour * 0.11;
    color += float3(0.84, 0.11, 0.025) * saturate(localEcology.z + localEnvironment.z) * 0.22;
    color += float3(0.00, 0.76, 0.64) * pow(saturate(localEvents.x), 2.2) * 0.24;
    color += float3(0.92, 0.06, 0.66) * pow(saturate(localEvents.y), 2.0) * 0.22;
    color += float3(0.96, 0.06, 0.018) * pow(saturate(localEvents.z), 2.0) * 0.30;
    color += float3(0.38, 0.10, 0.88) * pow(saturate(localEvents.w), 2.0) * 0.24;
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
    return float4(max(color, 0.0), 1.0);
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
    float nutrientObject = nutrientBed * (0.10 + nutrientGrain * 0.90);
    float mineralObject = mineralBed * (0.08 + mineralGrain * 0.92);
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
        color += float3(1.0, 0.72, 0.10) * energyCore * biomass * bodyMask * 0.82;
    } else if (uniforms.displayMode == 2) {
        color = float3(0.004, 0.008, 0.015) + pow(geneA.xyz, float3(0.75)) * biomass * bodyMask * 0.92;
        color += lineage * membrane * bodyEdge * 0.88;
    } else if (uniforms.displayMode == 3) {
        float enzymeTotal = max(niche.x + niche.y + niche.z, 0.001);
        color = float3(0.004, 0.008, 0.015) + (niche.xyz / enzymeTotal) * biomass * bodyMask * 1.26;
        color += predatorColor * niche.w * biomass * bodyMask * 0.92;
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
        color += float3(0.02, 0.82, 0.48) * nutrientObject * (1.0 - rockMask) * 0.40;
        color += float3(1.0, 0.56, 0.025) * mineralObject * (1.0 - rockMask) * 0.48;
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
    return float4(color, 1.0);
}
