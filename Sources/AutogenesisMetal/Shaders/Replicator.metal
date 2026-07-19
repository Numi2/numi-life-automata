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
    // Nearest-contact direction, metabolite exchange, contact conflict.
    float4 interaction;
};

struct CellAggregate {
    // Active cell count, mean ATP, mean membrane integrity, mean stress.
    float4 physiology;
    // Centroid, root-mean-square radius, dividing-cell fraction.
    float4 morphology;
};

struct AgentObservationRecord {
    float2 position;
    uint generation;
    uint flags;
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
    constant SimulationUniforms& uniforms [[buffer(0)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height || gid.z >= uniforms.worldCount) { return; }

    int2 p = int2(gid.xy);
    uint layer = gid.z;
    float4 center = stateIn.read(gid.xy, layer);
    float4 chemistry = ecologyIn.read(gid.xy, layer);
    float4 geneA = genomeAIn.read(gid.xy, layer);
    float4 geneB = genomeBIn.read(gid.xy, layer);
    float4 geneC = genomeCIn.read(gid.xy, layer);
    float4 priorEvents = eventIn.read(gid.xy, layer);
    float4 geology = environmentIn.read(gid.xy, layer);
    int2 cardinal[4] = { int2(-1, 0), int2(1, 0), int2(0, -1), int2(0, 1) };

    float resourceLaplacian = 0.0;
    float4 chemistryLaplacian = float4(0.0);
    float4 eventLaplacian = float4(0.0);
    for (uint index = 0; index < 4; ++index) {
        uint2 coordinate = uint2(wrapped(p + cardinal[index], uniforms.width, uniforms.height));
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
    catalyst += uniforms.dt * quantumOrder * chemicalAffinity * 0.0090;
    float prebioticCapacity = 0.012 + catalyst * 0.20;
    energy += uniforms.dt * quantumOrder * catalyst *
        (0.015 + 0.035 * saturate(resourceA + resourceB)) * permeability;
    energy = min(energy, prebioticCapacity);
    float prebioticOrder = smoothstep(0.018, 0.065, catalyst) *
        smoothstep(0.002, 0.015, energy) * quantumOrder;
    float prebioticMembraneTarget = prebioticOrder * 0.035;
    membrane += uniforms.dt * 0.22 * (prebioticMembraneTarget - membrane);
    bool wasAlive = biomass > 0.018;
    bool born = false;
    bool replaced = false;
    float mutationPulse = 0.0;
    int2 offsets[8] = {
        int2(-1, 0), int2(1, 0), int2(0, -1), int2(0, 1),
        int2(-1, -1), int2(1, -1), int2(-1, 1), int2(1, 1)
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
        uint2 coordinate = uint2(wrapped(p + offsets[index], uniforms.width, uniforms.height));
        float4 neighborState = stateIn.read(coordinate, layer);
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
        float membraneTarget = biomass * geneA.y * boundaryExposure * 0.72;
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
    return cell;
}

inline CellState founderCell(AgentState agent, uint localIndex, uint seed) {
    CellState cell;
    float angle = localIndex == 0u ? 0.0 :
        (float(localIndex - 1u) / 6.0) * 2.0 * M_PI_F + signedRandom(seed + 11u) * 0.08;
    float radius = localIndex == 0u ? 0.0 : 0.31 + signedRandom(seed + localIndex * 17u) * 0.018;
    cell.position = float2(cos(angle), sin(angle)) * radius;
    cell.velocity = float2(0.0);
    cell.physiology = float4(
        clamp(0.58 + agent.energy * 0.20 + signedRandom(seed + localIndex * 23u) * 0.025, 0.42, 0.92),
        clamp(0.70 + agent.biomass * 0.18, 0.68, 0.90),
        random01(seed + localIndex * 29u) * 0.18,
        clamp(0.76 + agent.geneA.w * 0.20, 0.70, 0.98)
    );
    float centrality = 1.0 - saturate(radius / 0.62);
    cell.phenotype = float4(
        clamp(0.30 + agent.geneA.y * 0.58, 0.0, 1.0),
        clamp(0.18 + agent.geneA.z * 0.64, 0.0, 1.0),
        clamp(0.18 + agent.geneC.x * 0.74, 0.0, 1.0),
        clamp(0.18 + agent.geneC.y * 0.74, 0.0, 1.0)
    );
    cell.signals = float4(
        centrality,
        1.0 - centrality,
        0.02 + random01(seed + localIndex * 31u) * 0.025,
        0.0
    );
    cell.interaction = float4(0.0);
    return cell;
}

inline void seedOrganismCells(
    device CellState* cells,
    device atomic_uint* cellOccupancy,
    device CellAggregate* aggregates,
    uint owner,
    AgentState agent,
    uint seed
) {
    uint base = owner * cellsPerAgent;
    const uint founderCellCount = 7u;
    for (uint localIndex = 0u; localIndex < cellsPerAgent; ++localIndex) {
        uint index = base + localIndex;
        if (localIndex < founderCellCount) {
            cells[index] = founderCell(agent, localIndex, seed);
            atomic_store_explicit(&cellOccupancy[index], 1u, memory_order_relaxed);
        } else {
            cells[index] = emptyCell();
            atomic_store_explicit(&cellOccupancy[index], 0u, memory_order_relaxed);
        }
    }
    CellAggregate aggregate;
    aggregate.physiology = float4(float(founderCellCount), 0.68, 0.88, 0.03);
    aggregate.morphology = float4(0.0, 0.0, 0.29, 0.0);
    aggregates[owner] = aggregate;
}

kernel void initializeAgents(
    device AgentState* agents [[buffer(0)]],
    device atomic_uint* occupancy [[buffer(1)]],
    constant SimulationUniforms& uniforms [[buffer(2)]],
    device CellState* cells [[buffer(3)]],
    device atomic_uint* cellOccupancy [[buffer(4)]],
    device CellAggregate* cellAggregates [[buffer(5)]],
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
    agents[gid] = agent;
    atomic_store_explicit(&occupancy[gid], 0u, memory_order_relaxed);
    uint base = gid * cellsPerAgent;
    for (uint localIndex = 0u; localIndex < cellsPerAgent; ++localIndex) {
        cells[base + localIndex] = emptyCell();
        atomic_store_explicit(&cellOccupancy[base + localIndex], 0u, memory_order_relaxed);
    }
    CellAggregate aggregate;
    aggregate.physiology = float4(0.0);
    aggregate.morphology = float4(0.0);
    cellAggregates[gid] = aggregate;
}

kernel void collectAgentObservations(
    device const AgentState* agents [[buffer(0)]],
    device const atomic_uint* occupancy [[buffer(1)]],
    device AgentObservationRecord* observations [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= maxAgentCount) { return; }
    uint occupied = atomic_load_explicit(&occupancy[gid], memory_order_relaxed);
    AgentState agent = agents[gid];
    AgentObservationRecord observation;
    observation.position = agent.position;
    observation.generation = agent.generation;
    observation.flags = occupied != 0u ? (1u | (agent.geneC.w >= 0.08 ? 2u : 0u)) : 0u;
    observations[gid] = observation;
}

kernel void nucleateAutogenicFounder(
    device AgentState* agents [[buffer(0)]],
    device atomic_uint* occupancy [[buffer(1)]],
    constant SimulationUniforms& uniforms [[buffer(2)]],
    device CellState* cells [[buffer(3)]],
    device atomic_uint* cellOccupancy [[buffer(4)]],
    device CellAggregate* cellAggregates [[buffer(5)]],
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
    agents[0] = founder;
    seedOrganismCells(cells, cellOccupancy, cellAggregates, 0u, founder,
        hash32(gid.x * 2246822519u ^ gid.y * 3266489917u ^ uniforms.step));
}

kernel void evolveAgents(
    device const AgentState* agentsIn [[buffer(0)]],
    device AgentState* agentsOut [[buffer(1)]],
    device atomic_uint* occupancy [[buffer(2)]],
    constant SimulationUniforms& uniforms [[buffer(3)]],
    device const CellAggregate* cellAggregates [[buffer(4)]],
    texture2d_array<float, access::read> state [[texture(0)]],
    texture2d_array<float, access::read> ecology [[texture(1)]],
    texture2d_array<float, access::read> environment [[texture(2)]],
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
    float targetSpeed = cruiseSpeed * (0.72 + urgency * 0.55);
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
    CellAggregate cellAggregate = cellAggregates[gid];
    float cellularViability = cellAggregate.physiology.x > 0.5
        ? saturate(cellAggregate.physiology.y * cellAggregate.physiology.z)
        : 0.0;
    float maintenance = 0.000050 *
        (0.72 + agent.biomass * 0.65 + speed / max(cruiseSpeed, 0.000001) * 0.42) +
        crowding * 0.000014;
    maintenance *= mix(1.04, 0.96, cellularViability);
    float environmentalDamage = 0.00034 * localEnvironment.z * (1.0 - agent.geneA.w) +
        0.00046 * localEnvironment.w + 0.00030 * incomingAttack +
        cellAggregate.physiology.w * 0.000025;
    agent.energy = clamp(agent.energy + resourceGain + predationGain - maintenance - environmentalDamage, 0.0, 1.45);
    agent.biomass = clamp(agent.biomass + (agent.energy - 0.55) * 0.00008 - environmentalDamage * 0.18, 0.12, 1.0);
    agent.age += 1.0;
    bool cellularFailure = agent.age > 240.0 && cellAggregate.physiology.x < 0.5;
    if (agent.energy <= 0.0001 || agent.biomass <= 0.121 ||
        agent.age > 180000.0 || cellularFailure) {
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
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= maxAgentCount || atomic_load_explicit(&occupancy[gid], memory_order_relaxed) == 0u) { return; }
    AgentState parent = agents[gid];
    if (parent.energy < 1.06 || parent.age < 720.0) { return; }
    uint birthSeed = hash32(gid * 2246822519u ^ uniforms.step * 3266489917u ^ parent.generation * 668265263u);
    float birthChance = 0.00042 + parent.geneA.z * 0.00062 + parent.geneB.y * 0.0015;
    if (random01(birthSeed) >= birthChance) { return; }
    uint target = hash32(birthSeed + 17u) % maxAgentCount;
    if (target == gid) { target = (target + 1u) % maxAgentCount; }
    uint expected = 0u;
    if (!atomic_compare_exchange_weak_explicit(
        &occupancy[target], &expected, 1u, memory_order_relaxed, memory_order_relaxed
    )) { return; }

    float mutation = uniforms.mutationScale * (0.006 + parent.geneB.y * 0.18);
    if (random01(birthSeed + 31u) < 0.032) {
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
    child.energy = 0.34;
    child.biomass = 0.38;
    child.age = 0.0;
    child.generation = parent.generation + 1u;
    parent.energy -= 0.31;
    parent.age = 0.0;
    agents[gid] = parent;
    agents[target] = child;
    seedOrganismCells(cells, cellOccupancy, cellAggregates, target, child, birthSeed ^ 0xa511e9b3u);
}

kernel void injectFounder(
    device AgentState* agents [[buffer(0)]],
    device atomic_uint* occupancy [[buffer(1)]],
    constant SimulationUniforms& uniforms [[buffer(2)]],
    device CellState* cells [[buffer(3)]],
    device atomic_uint* cellOccupancy [[buffer(4)]],
    device CellAggregate* cellAggregates [[buffer(5)]],
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
    agents[claimed] = founder;
    seedOrganismCells(cells, cellOccupancy, cellAggregates, claimed, founder, seed ^ 0x63d83595u);
}

kernel void evolveOrganismCells(
    device const AgentState* agents [[buffer(0)]],
    device const atomic_uint* agentOccupancy [[buffer(1)]],
    device const CellState* cellsIn [[buffer(2)]],
    device CellState* cellsOut [[buffer(3)]],
    device atomic_uint* cellOccupancy [[buffer(4)]],
    constant SimulationUniforms& uniforms [[buffer(5)]],
    texture2d_array<float, access::read> state [[texture(0)]],
    texture2d_array<float, access::read> ecology [[texture(1)]],
    texture2d_array<float, access::read> environment [[texture(2)]],
    texture2d_array<float, access::read> events [[texture(3)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= maxCellCount) { return; }
    uint owner = gid / cellsPerAgent;
    if (atomic_load_explicit(&agentOccupancy[owner], memory_order_relaxed) == 0u) {
        cellsOut[gid] = emptyCell();
        atomic_store_explicit(&cellOccupancy[gid], 0u, memory_order_relaxed);
        return;
    }
    if (atomic_load_explicit(&cellOccupancy[gid], memory_order_relaxed) == 0u) {
        cellsOut[gid] = cellsIn[gid];
        return;
    }

    AgentState agent = agents[owner];
    CellState cell = cellsIn[gid];
    uint ownerBase = owner * cellsPerAgent;
    float2 mechanicalForce = -cell.position * (0.00045 + cell.phenotype.y * 0.00045);
    float2 contactSignal = float2(0.0);
    float2 nearestContact = float2(0.0);
    float nearestDistance = 10.0;
    float neighborATP = 0.0;
    float contactCount = 0.0;
    float contactConflict = 0.0;
    float adhesion = 0.0;
    for (uint localIndex = 0u; localIndex < cellsPerAgent; ++localIndex) {
        uint otherIndex = ownerBase + localIndex;
        if (otherIndex == gid ||
            atomic_load_explicit(&cellOccupancy[otherIndex], memory_order_relaxed) == 0u) { continue; }
        CellState other = cellsIn[otherIndex];
        float2 delta = other.position - cell.position;
        float distance = max(length(delta), 0.0001);
        float2 direction = delta / distance;
        if (distance < 0.31) {
            mechanicalForce -= direction * (0.31 - distance) * 0.018;
        } else if (distance < 0.62) {
            float pairAdhesion = min(cell.phenotype.x, other.phenotype.x);
            mechanicalForce += direction * (distance - 0.31) * pairAdhesion * 0.0038;
        }
        if (distance < 0.58) {
            float weight = 1.0 - distance / 0.58;
            contactSignal += other.signals.xy * weight;
            neighborATP += other.physiology.x * weight;
            adhesion += min(cell.phenotype.x, other.phenotype.x) * weight;
            contactConflict += abs(cell.phenotype.y - other.phenotype.y) * weight;
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
    float atp = clamp(cell.physiology.x + uptake - maintenance - externalStress * 0.00042, 0.0, 1.2);
    float stress = mix(cell.signals.z, externalStress + (atp < 0.18 ? 0.36 : 0.0), 0.018);
    float apoptosis = clamp(cell.signals.w + max(stress - 0.72, 0.0) * 0.0024 - 0.00035, 0.0, 1.0);
    float membraneIntegrity = clamp(
        cell.physiology.w + (atp - 0.38) * 0.00020 - stress * 0.00030 - apoptosis * 0.00045,
        0.0, 1.0
    );
    float biomass = clamp(cell.physiology.y + (atp - 0.48) * 0.00018, 0.42, 1.08);
    float contactInhibition = saturate(contactCount / (3.6 + cell.phenotype.x * 1.8));
    float cycleRate = 0.00054 * smoothstep(0.44, 0.76, atp) *
        (1.0 - contactInhibition * (0.72 + cell.phenotype.x * 0.20)) *
        (1.0 - stress);
    float cycle = clamp(
        cell.physiology.z + cycleRate - contactInhibition * 0.00022,
        0.0, 1.2
    );

    float2 localMorphogens = contactCount > 0.001 ? contactSignal / contactCount : cell.signals.xy;
    float radialPosition = saturate(length(cell.position) / 0.82);
    float2 targetMorphogens = float2(1.0 - radialPosition, radialPosition);
    cell.signals.xy = mix(cell.signals.xy, mix(targetMorphogens, localMorphogens, 0.58), 0.014);
    cell.signals.zw = float2(stress, apoptosis);
    float centralProgram = saturate(cell.signals.x - cell.signals.y + 0.5);
    cell.phenotype.x = mix(cell.phenotype.x,
        clamp(0.24 + agent.geneA.y * 0.46 + centralProgram * 0.24, 0.0, 1.0), 0.0016);
    cell.phenotype.y = mix(cell.phenotype.y,
        clamp(0.16 + agent.geneA.z * 0.42 + (1.0 - centralProgram) * 0.32, 0.0, 1.0), 0.0016);
    cell.phenotype.z = mix(cell.phenotype.z,
        clamp(0.14 + agent.geneC.x * 0.62 + centralProgram * 0.16, 0.0, 1.0), 0.0012);
    cell.phenotype.w = mix(cell.phenotype.w,
        clamp(0.14 + agent.geneC.y * 0.62 + (1.0 - centralProgram) * 0.16, 0.0, 1.0), 0.0012);
    cell.physiology = float4(atp, biomass, cycle, membraneIntegrity);

    float2 polarity = float2(cell.signals.x - cell.signals.y, signedRandom(gid * 31u + uniforms.step / 16u));
    mechanicalForce += polarity * cell.phenotype.y * 0.00016;
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

    float exchange = contactCount > 0.001 ? abs(atp - neighborATP / contactCount) : 0.0;
    cell.interaction = float4(
        nearestContact,
        saturate(exchange * 2.4 + adhesion * 0.08),
        saturate(contactConflict * 0.18 + localEvents.z * 0.72 + stress * 0.22)
    );

    if (membraneIntegrity < 0.055 || apoptosis > 0.985 ||
        (atp < 0.008 && stress > 0.82)) {
        atomic_store_explicit(&cellOccupancy[gid], 0u, memory_order_relaxed);
    }
    cellsOut[gid] = cell;
}

kernel void divideAndReduceOrganismCells(
    device AgentState* agents [[buffer(0)]],
    device const atomic_uint* agentOccupancy [[buffer(1)]],
    device CellState* cells [[buffer(2)]],
    device atomic_uint* cellOccupancy [[buffer(3)]],
    device CellAggregate* aggregates [[buffer(4)]],
    constant SimulationUniforms& uniforms [[buffer(5)]],
    uint owner [[thread_position_in_grid]]
) {
    if (owner >= maxAgentCount) { return; }
    uint base = owner * cellsPerAgent;
    if (atomic_load_explicit(&agentOccupancy[owner], memory_order_relaxed) == 0u) {
        for (uint localIndex = 0u; localIndex < cellsPerAgent; ++localIndex) {
            atomic_store_explicit(&cellOccupancy[base + localIndex], 0u, memory_order_relaxed);
        }
        CellAggregate emptyAggregate;
        emptyAggregate.physiology = float4(0.0);
        emptyAggregate.morphology = float4(0.0);
        aggregates[owner] = emptyAggregate;
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
            float angle = random01(divisionSeed) * 2.0 * M_PI_F;
            float2 axis = float2(cos(angle), sin(angle));
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
            child.signals.xy += float2(signedRandom(divisionSeed + 1u), signedRandom(divisionSeed + 2u)) * 0.018;
            child.interaction = float4(0.0);
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
    float2 corner = corners[vertexID];
    float speed = length(agent.velocity);
    float inheritedAngle = agent.geneB.w * 2.0 * M_PI_F;
    float2 heading = speed > 0.000001
        ? agent.velocity / speed
        : float2(cos(inheritedAngle), sin(inheritedAngle));
    float2 lateral = float2(-heading.y, heading.x);
    float worldRadius = (0.012 + 0.0045 * agent.geneB.z + 0.0025 * agent.biomass) /
        max(uniforms.worldScale, 1.0);
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
    output.cellularPhysiology = cellAggregates[instanceID].physiology;
    output.tissueMorphology = cellAggregates[instanceID].morphology;
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
    float scaleVisibility = 1.0 - smoothstep(18.0, 48.0, observationZoom);
    float focusVisibility = input.trackingActive > 0.5 && input.focus > 0.5
        ? max(scaleVisibility, 1.0 - smoothstep(64.0, 128.0, observationZoom))
        : scaleVisibility;
    if (focusVisibility <= 0.001) { discard_fragment(); }
    float pulsePhase = float(uniforms.step) * (0.032 + input.geneA.x * 0.018) + input.geneB.w * 11.0;
    float pulse = sin(pulsePhase);
    float locomotorSpeed = saturate(input.speed * max(uniforms.worldScale, 1.0) * 16000.0);

    float tissueOccupancy = saturate(input.cellularPhysiology.x / float(cellsPerAgent));
    float tissueRadius = saturate(input.tissueMorphology.z / 0.86);
    float tissueATP = saturate(input.cellularPhysiology.y);
    float tissueIntegrity = saturate(input.cellularPhysiology.z);
    float tissueStress = saturate(input.cellularPhysiology.w);
    float abdomenLength = (0.66 + input.geneB.z * 0.15) * mix(0.88, 1.08, tissueRadius);
    float abdomenWidth = (0.36 + input.geneA.y * 0.16) * mix(0.84, 1.12, sqrt(tissueOccupancy));
    float2 abdomenP = float2((p.x + 0.08) / abdomenLength, p.y / abdomenWidth);
    float abdomenDistance = length(abdomenP);
    float abdomenAA = max(fwidth(abdomenDistance) * 1.15, 0.0025);
    float abdomen = 1.0 - smoothstep(1.0 - abdomenAA, 1.0 + abdomenAA, abdomenDistance);

    float2 headCenter = float2(0.56 + input.geneB.z * 0.04, 0.0);
    float headRadius = (0.19 + input.geneC.w * 0.13 + input.geneA.z * 0.045) *
        mix(0.90, 1.06, tissueIntegrity);
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
    float appendageReach = (0.48 + input.geneA.z * 0.22) * mix(0.86, 1.04, tissueATP);
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
    }
    color += float3(0.12, 0.92, 1.0) * trackedRing * 1.8;
    float organismEnvelope = 1.0 - smoothstep(14.0, 24.0, observationZoom);
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
    float lineageHue;
    float ownerEnergy;
    float visibility;
    float tracked;
};

vertex CellRasterData cellVertex(
    device const AgentState* agents [[buffer(0)]],
    device const uint* agentOccupancy [[buffer(1)]],
    device const CellState* cells [[buffer(2)]],
    device const uint* cellOccupancy [[buffer(3)]],
    constant SimulationUniforms& uniforms [[buffer(4)]],
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]]
) {
    const float2 corners[6] = {
        float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0),
        float2(-1.0, 1.0), float2(1.0, -1.0), float2(1.0, 1.0)
    };
    uint owner = instanceID / cellsPerAgent;
    AgentState agent = agents[owner];
    CellState cell = cells[instanceID];
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
    float cellRadius = bodyWorldRadius * (0.105 + cell.physiology.y * 0.020);
    float2 cellCenter = agent.position + heading * cell.position.x * bodyWorldRadius +
        lateral * cell.position.y * bodyWorldRadius * 0.72;
    float2 corner = corners[vertexID];
    float2 worldPosition = cellCenter + heading * corner.x * cellRadius + lateral * corner.y * cellRadius;
    float safeAspect = max(uniforms.viewportAspect, 0.001);
    float2 viewScale = safeAspect >= 1.0 ? float2(1.0, 1.0 / safeAspect) : float2(safeAspect, 1.0);
    float2 screenUV = 0.5 + (worldPosition - uniforms.cameraCenter) *
        max(uniforms.cameraZoom, 0.000000001) / viewScale;
    bool occupied = owner < maxAgentCount && instanceID < maxCellCount &&
        agentOccupancy[owner] != 0u && cellOccupancy[instanceID] != 0u && visibility > 0.001;

    CellRasterData output;
    output.position = occupied
        ? float4(screenUV.x * 2.0 - 1.0, 1.0 - screenUV.y * 2.0, 0.0, 1.0)
        : float4(3.0, 3.0, 0.0, 1.0);
    output.local = corner;
    output.physiology = cell.physiology;
    output.phenotype = cell.phenotype;
    output.signals = cell.signals;
    output.interaction = cell.interaction;
    output.lineageHue = agent.geneB.w;
    output.ownerEnergy = agent.energy;
    output.visibility = visibility;
    output.tracked = uniforms.trackedAgentID == owner ? 1.0 : 0.0;
    return output;
}

fragment float4 cellFragment(
    CellRasterData input [[stage_in]],
    constant SimulationUniforms& uniforms [[buffer(0)]]
) {
    float2 p = input.local;
    float angle = atan2(p.y, p.x);
    float irregularRadius = 0.91 + 0.035 * sin(angle * (5.0 + floor(input.phenotype.x * 3.0)) +
        input.lineageHue * 13.0);
    float radius = length(p) / irregularRadius;
    float aa = max(fwidth(radius) * 1.15, 0.004);
    float body = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, radius);
    if (body <= 0.001) { discard_fragment(); }

    float integrity = saturate(input.physiology.w);
    float membrane = body * smoothstep(0.72 - integrity * 0.10, 0.98, radius);
    float cytoplasm = body * (1.0 - smoothstep(0.62, 0.94, radius));
    float nucleusRadius = 0.20 + input.signals.x * 0.08;
    float2 nucleusPosition = float2((input.signals.x - input.signals.y) * 0.12, 0.0);
    float nucleus = (1.0 - smoothstep(nucleusRadius, nucleusRadius + aa * 2.0,
        length(p - nucleusPosition))) * body;
    float mitochondriaPattern = visualNoise(p * (13.0 + input.phenotype.z * 7.0) +
        float2(input.lineageHue * 17.0, input.phenotype.w * 11.0));
    float mitochondria = smoothstep(0.73, 0.92, mitochondriaPattern) * cytoplasm *
        (1.0 - nucleus);
    float cycle = saturate(input.physiology.z);
    float2 divisionAxis = normalize(float2(cos(input.lineageHue * 19.0), sin(input.lineageHue * 19.0)));
    float cleavage = (1.0 - smoothstep(0.025, 0.075, abs(dot(p, divisionAxis)))) *
        body * smoothstep(0.76, 1.0, cycle);

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
    float3 color = mix(lineage, phenotypeColor, 0.42) * cytoplasm * (0.22 + atp * 0.46);
    float centralProgram = saturate(input.signals.x - input.signals.y + 0.5);
    float3 differentiatedLineage = mix(lineage,
        mix(float3(0.04, 0.56, 0.92), float3(0.92, 0.38, 0.04), 1.0 - centralProgram), 0.34);
    color = mix(color, differentiatedLineage * cytoplasm * (0.24 + atp * 0.34), 0.42);
    float3 membraneColor = mix(differentiatedLineage, float3(0.02, 0.76, 0.58), 0.28);
    color += membraneColor * membrane * (0.30 + integrity * 0.34);
    color += float3(1.0, 0.58, 0.025) * mitochondria * atp * 0.62;
    color += mix(float3(0.86, 0.06, 0.68), lineage, 0.34) * nucleus * 0.72;
    color += float3(0.96, 0.90, 0.58) * cleavage * cycle * 0.56;
    color += mix(float3(0.08, 0.90, 1.0), float3(0.18, 1.0, 0.56), input.phenotype.x) *
        junction * 0.54;
    color += float3(1.0, 0.055, 0.025) * input.interaction.w * membrane * 0.72;
    color = mix(color, float3(0.94, 0.055, 0.018) * body, stress * 0.34);
    color *= 1.0 - apoptosis * (0.46 + 0.28 * mitochondriaPattern);
    color += float3(0.76, 0.12, 1.0) * apoptosis * membrane * 0.66;
    color += float3(0.10, 0.92, 1.0) * input.tracked * membrane * 0.24;

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
    constexpr sampler fieldSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float safeAspect = max(uniforms.viewportAspect, 0.001);
    float2 viewScale = safeAspect >= 1.0 ? float2(1.0, 1.0 / safeAspect) : float2(safeAspect, 1.0);
    float2 rawUV = uniforms.cameraCenter + (input.uv - 0.5) * viewScale /
        max(uniforms.cameraZoom, 0.000000001);
    float2 uv = clamp(rawUV, 0.0, 1.0);
    float observationZoom = uniforms.cameraZoom / max(uniforms.worldScale, 1.0);

    float4 wave = quantum.sample(quantumSampler, uv);
    float2 quantumTexel = 1.0 / float(quantumGridSize);
    float4 waveRight = quantum.sample(quantumSampler, uv + float2(quantumTexel.x, 0.0));
    float4 waveUp = quantum.sample(quantumSampler, uv + float2(0.0, quantumTexel.y));
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
    color += mix(float3(0.01, 0.28, 0.48), float3(0.02, 0.58, 0.32), potential) *
        potentialContour * 0.11;
    color += float3(0.84, 0.11, 0.025) * saturate(localEcology.z + localEnvironment.z) * 0.22;
    color += float3(0.00, 0.76, 0.64) * pow(saturate(localEvents.x), 2.2) * 0.24;
    color += float3(0.92, 0.06, 0.66) * pow(saturate(localEvents.y), 2.0) * 0.22;
    color += float3(0.96, 0.06, 0.018) * pow(saturate(localEvents.z), 2.0) * 0.30;
    color += float3(0.38, 0.10, 0.88) * pow(saturate(localEvents.w), 2.0) * 0.24;
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
