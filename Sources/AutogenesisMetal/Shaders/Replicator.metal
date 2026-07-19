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

constant uint metricCount = 32;
constant float metricScale = 4096.0;
constant uint quantumGridSize = 1024u;
constant uint maxAgentCount = 384u;

struct AgentState {
    float2 position;
    float2 velocity;
    float4 geneA;
    float4 geneB;
    float4 geneC;
    float energy;
    float biomass;
    float age;
    uint generation;
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

inline void addMetric(device atomic_uint* metrics, uint world, uint metric, float value) {
    uint fixedValue = uint(clamp(value, 0.0, 1.0) * metricScale);
    atomic_fetch_add_explicit(&metrics[world * metricCount + metric], fixedValue, memory_order_relaxed);
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
    uint3 gid [[thread_position_in_grid]]
) {
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

    addMetric(metrics, layer, 0, min(current.y, 1.0));
    addMetric(metrics, layer, 1, min(current.x * 0.5, 1.0));
    addMetric(metrics, layer, 2, min(current.z, 1.0));
    addMetric(metrics, layer, 3, active);
    addMetric(metrics, layer, 4, activity);
    addMetric(metrics, layer, 5, coherence);
    addMetric(metrics, layer, 6, multiscale * active);
    addMetric(metrics, layer, 7, recovered);
    addMetric(metrics, layer, 8, recoveryTarget);
    addMetric(metrics, layer, 9, geneDifference);
    addMetric(metrics, layer, 10, uv.x * min(current.y, 1.0));
    addMetric(metrics, layer, 11, uv.y * min(current.y, 1.0));
    addMetric(metrics, layer, 12, nicheDifference);
    addMetric(metrics, layer, 13, specialization);
    addMetric(metrics, layer, 14, trophicActivity);
    addMetric(metrics, layer, 15, active * saturate(current.x));
    addMetric(metrics, layer, 16 + lineageBin, active);
}

kernel void initializeAgents(
    device AgentState* agents [[buffer(0)]],
    device atomic_uint* occupancy [[buffer(1)]],
    constant SimulationUniforms& uniforms [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= maxAgentCount) { return; }
    AgentState agent;
    agent.position = float2(0.5);
    agent.velocity = float2(0.0);
    agent.geneA = float4(0.76, 0.66, 0.48, 0.72);
    agent.geneB = float4(0.58, 0.032, 0.72, 0.42);
    agent.geneC = float4(0.72, 0.68, 0.34, 0.06);
    agent.energy = 0.0;
    agent.biomass = 0.0;
    agent.age = 0.0;
    agent.generation = 0u;
    agents[gid] = agent;
    atomic_store_explicit(&occupancy[gid], 0u, memory_order_relaxed);
}

kernel void nucleateAutogenicFounder(
    device AgentState* agents [[buffer(0)]],
    device atomic_uint* occupancy [[buffer(1)]],
    constant SimulationUniforms& uniforms [[buffer(2)]],
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
    founder.energy = clamp(0.62 + localState.z * 8.0, 0.62, 1.02);
    founder.biomass = clamp(0.42 + localState.y * 1.8, 0.42, 0.70);
    founder.age = 0.0;
    founder.generation = 0u;
    agents[0] = founder;
}

kernel void evolveAgents(
    device const AgentState* agentsIn [[buffer(0)]],
    device AgentState* agentsOut [[buffer(1)]],
    device atomic_uint* occupancy [[buffer(2)]],
    constant SimulationUniforms& uniforms [[buffer(3)]],
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
    float maintenance = 0.000050 *
        (0.72 + agent.biomass * 0.65 + speed / max(cruiseSpeed, 0.000001) * 0.42) +
        crowding * 0.000014;
    float environmentalDamage = 0.00034 * localEnvironment.z * (1.0 - agent.geneA.w) +
        0.00046 * localEnvironment.w + 0.00030 * incomingAttack;
    agent.energy = clamp(agent.energy + resourceGain + predationGain - maintenance - environmentalDamage, 0.0, 1.45);
    agent.biomass = clamp(agent.biomass + (agent.energy - 0.55) * 0.00008 - environmentalDamage * 0.18, 0.12, 1.0);
    agent.age += 1.0;
    if (agent.energy <= 0.0001 || agent.biomass <= 0.121 || agent.age > 180000.0) {
        agent.energy = 0.0;
        agent.biomass = 0.0;
        atomic_store_explicit(&occupancy[gid], 0u, memory_order_relaxed);
    }
    agentsOut[gid] = agent;
}

kernel void spawnAgents(
    device AgentState* agents [[buffer(0)]],
    device atomic_uint* occupancy [[buffer(1)]],
    constant SimulationUniforms& uniforms [[buffer(2)]],
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
    child.energy = 0.34;
    child.biomass = 0.38;
    child.age = 0.0;
    child.generation = parent.generation + 1u;
    parent.energy -= 0.31;
    parent.age = 0.0;
    agents[gid] = parent;
    agents[target] = child;
}

kernel void injectFounder(
    device AgentState* agents [[buffer(0)]],
    device atomic_uint* occupancy [[buffer(1)]],
    constant SimulationUniforms& uniforms [[buffer(2)]],
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
    founder.energy = 1.02;
    founder.biomass = 0.66;
    founder.age = 0.0;
    founder.generation = 0u;
    agents[claimed] = founder;
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

inline float3 quantumPhaseColor(float phase) {
    float3 cycle = 0.5 + 0.5 * cos(2.0 * M_PI_F * (phase + float3(0.00, 0.67, 0.33)));
    return mix(float3(0.05, 0.13, 0.24), pow(cycle, float3(0.72)), 0.88);
}

inline float segmentDistance(float2 point, float2 start, float2 end) {
    float2 segment = end - start;
    float position = saturate(dot(point - start, segment) / max(dot(segment, segment), 0.000001));
    return length(point - (start + segment * position));
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
    float focus;
};

vertex AgentRasterData agentVertex(
    device const AgentState* agents [[buffer(0)]],
    device const uint* occupancy [[buffer(1)]],
    constant SimulationUniforms& uniforms [[buffer(2)]],
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
    output.focus = uniforms.trackedAgentID == 0xffffffffu || uniforms.trackedAgentID == instanceID
        ? 1.0
        : 0.0;
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
    float focusVisibility = input.focus > 0.5
        ? 1.0
        : 1.0 - smoothstep(5.0, 7.0, observationZoom);
    if (focusVisibility <= 0.001) { discard_fragment(); }
    float pulse = sin(float(uniforms.step) * (0.032 + input.geneA.x * 0.018) + input.geneB.w * 11.0);

    float2 abdomenP = float2((p.x + 0.08) / (0.70 + input.geneB.z * 0.08),
        p.y / (0.42 + input.geneA.y * 0.12));
    float abdomenDistance = length(abdomenP);
    float abdomen = 1.0 - smoothstep(0.88, 1.02, abdomenDistance);
    float2 headCenter = float2(0.58, 0.0);
    float headRadius = 0.22 + input.geneC.w * 0.08 + input.geneA.z * 0.035;
    float headDistance = length(p - headCenter) / headRadius;
    float head = 1.0 - smoothstep(0.84, 1.06, headDistance);
    float tailWave = sin((p.x + 0.76) * (11.0 + input.geneB.z * 5.0) + pulse * 1.4) *
        (0.07 + input.geneB.z * 0.035);
    float tailRange = smoothstep(-1.03, -0.77, p.x) * (1.0 - smoothstep(-0.56, -0.43, p.x));
    float tail = (1.0 - smoothstep(0.035, 0.085, abs(p.y - tailWave))) * tailRange;
    float limbWidth = 0.030 + input.geneA.y * 0.022;
    float stride = pulse * (0.08 + input.speed * 180.0);
    float limbs = 1.0 - smoothstep(limbWidth, limbWidth + 0.035, segmentDistance(
        p, float2(-0.17, 0.29), float2(-0.33 + stride, 0.64)
    ));
    limbs = max(limbs, 1.0 - smoothstep(limbWidth, limbWidth + 0.035, segmentDistance(
        p, float2(-0.17, -0.29), float2(-0.33 - stride, -0.64)
    )));
    limbs *= 0.34 + input.geneA.z * 0.66;
    float body = max(max(abdomen, head), max(tail, limbs));
    if (body <= 0.001) { discard_fragment(); }

    float abdomenEdge = abdomen * smoothstep(0.70, 0.96, abdomenDistance);
    float headEdge = head * smoothstep(0.63, 0.94, headDistance);
    float edge = max(abdomenEdge, headEdge);
    float interior = abdomen * (1.0 - smoothstep(0.34, 0.79, abdomenDistance));
    float sensor = 1.0 - smoothstep(0.035, 0.075,
        length(p - headCenter - float2(headRadius * 0.25, headRadius * 0.36)));
    sensor *= head;
    float jawTop = 1.0 - smoothstep(0.025, 0.060, segmentDistance(
        p, headCenter + float2(headRadius * 0.48, 0.03), float2(0.98, 0.16)
    ));
    float jawBottom = 1.0 - smoothstep(0.025, 0.060, segmentDistance(
        p, headCenter + float2(headRadius * 0.48, -0.03), float2(0.98, -0.16)
    ));
    float jaws = max(jawTop, jawBottom) * smoothstep(0.08, 0.38, input.geneC.w);
    body = max(body, jaws);

    float3 lineage = hsvToRGB(float3(input.geneB.w, 0.84, 0.64 + input.geneA.w * 0.22));
    float3 defenseColor = float3(0.02, 0.95, 0.64);
    float3 predatorColor = float3(1.0, 0.045, 0.012);
    float3 rim = mix(defenseColor, predatorColor, input.geneC.w);
    float energy = saturate(input.energy / 1.25);
    float bodyBulge = sqrt(saturate(1.0 - abdomenDistance * abdomenDistance));
    float light = 0.48 + bodyBulge * 0.44;
    float3 color = lineage * body * light * (0.62 + input.biomass * 0.38);
    color += rim * edge * (0.52 + input.geneA.w * 0.58);
    color += float3(1.0, 0.69, 0.045) * interior * energy * energy * 0.54;
    color += float3(0.84, 0.98, 1.0) * sensor * 0.96;
    color += predatorColor * jaws * (0.56 + input.geneC.w * 0.92);

    float organismReveal = smoothstep(4.0, 18.0, observationZoom);
    float chemistryReveal = smoothstep(18.0, 58.0, observationZoom);
    float quantumReveal = smoothstep(52.0, 160.0, observationZoom);
    float latticeReveal = smoothstep(420.0, 980.0, observationZoom);
    float tissueNoiseA = visualNoise(p * (16.0 + input.geneB.x * 9.0) + input.geneA.xy * 17.0);
    float tissueNoiseB = visualNoise(p * 31.0 + input.geneA.zw * 29.0);
    float channels = (1.0 - smoothstep(0.035, 0.14, abs(tissueNoiseA - tissueNoiseB))) * abdomen;
    float nucleusRadius = 0.095 + input.geneB.x * 0.045;
    float nucleus = (1.0 - smoothstep(nucleusRadius, nucleusRadius * 1.55,
        length(p - float2(-0.12, (input.geneA.z - 0.5) * 0.12)))) * abdomen;
    color += mix(float3(0.03, 0.58, 0.98), float3(0.98, 0.59, 0.04), input.geneA.x) *
        channels * organismReveal * 0.34;
    color += float3(0.98, 0.08, 0.74) * nucleus * organismReveal * 0.82;

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

    float4 wave = quantum.sample(quantumSampler, input.worldUV);
    float2 quantumTexel = 1.0 / float(quantumGridSize);
    float4 waveRight = quantum.sample(quantumSampler, input.worldUV + float2(quantumTexel.x, 0.0));
    float4 waveUp = quantum.sample(quantumSampler, input.worldUV + float2(0.0, quantumTexel.y));
    float probabilityA = dot(wave.xy, wave.xy);
    float probabilityB = dot(wave.zw, wave.zw);
    float probability = probabilityA + probabilityB;
    float2 amplitude = wave.xy + wave.zw;
    float phase = fract(atan2(amplitude.y, amplitude.x) / (2.0 * M_PI_F) + 1.0);
    float density = 1.0 - exp(-probability * 285000.0);
    float polarization = (probabilityA - probabilityB) / max(probability, 0.0000000001);
    float2 current = float2(
        complexCurrent(wave.xy, waveRight.xy) + complexCurrent(wave.zw, waveRight.zw),
        complexCurrent(wave.xy, waveUp.xy) + complexCurrent(wave.zw, waveUp.zw)
    );
    float currentStrength = saturate(length(current) * 950000.0);
    float3 spinColor = mix(float3(1.0, 0.22, 0.025), float3(0.02, 0.82, 1.0), polarization * 0.5 + 0.5);
    float3 quantumColor = mix(quantumPhaseColor(phase), spinColor, 0.38) * density;
    quantumColor += float3(0.82, 0.97, 1.0) * currentStrength * density * 0.56;

    float2 quantumCell = fract(input.worldUV * float(quantumGridSize));
    bool positiveComponent = quantumCell.x < 0.5;
    float2 componentPosition = positiveComponent
        ? float2(quantumCell.x * 2.0, quantumCell.y) - 0.5
        : float2((quantumCell.x - 0.5) * 2.0, quantumCell.y) - 0.5;
    float2 componentAmplitude = positiveComponent ? wave.xy : wave.zw;
    float componentProbability = positiveComponent ? probabilityA : probabilityB;
    float componentDensity = 1.0 - exp(-componentProbability * 520000.0);
    float componentPhase = fract(atan2(componentAmplitude.y, componentAmplitude.x) / (2.0 * M_PI_F) + 1.0);
    float3 componentBase = positiveComponent ? float3(0.02, 0.82, 1.0) : float3(1.0, 0.25, 0.035);
    float3 componentColor = mix(componentBase, quantumPhaseColor(componentPhase), 0.46);
    float componentMask = 1.0 - smoothstep(0.37, 0.48, length(componentPosition));
    float2 phasor = float2(cos(componentPhase * 2.0 * M_PI_F), sin(componentPhase * 2.0 * M_PI_F));
    float phasorLine = 1.0 - smoothstep(0.018, 0.055,
        abs(componentPosition.x * phasor.y - componentPosition.y * phasor.x));
    phasorLine *= smoothstep(0.38, 0.12, length(componentPosition));
    float latticeEdge = 1.0 - smoothstep(0.015, 0.065,
        min(min(quantumCell.x, 1.0 - quantumCell.x), min(quantumCell.y, 1.0 - quantumCell.y)));
    float3 spinorTile = float3(0.002, 0.004, 0.010) +
        componentColor * componentMask * componentDensity;
    spinorTile += float3(0.92, 0.98, 1.0) * phasorLine * componentMask * componentDensity * 0.86;
    spinorTile += float3(0.08, 0.18, 0.26) * latticeEdge * 0.52;
    quantumColor = mix(quantumColor, spinorTile, latticeReveal);
    color = mix(color, quantumColor, quantumReveal * abdomen);
    color += rim * edge * quantumReveal * (0.18 + currentStrength * 0.52);

    if (uniforms.displayMode == 1) {
        color = mix(color, float3(localState.x, localEcology.x, localEcology.y) * body * 1.3, 0.72);
    } else if (uniforms.displayMode == 2) {
        color = input.geneA.xyz * body * 0.82 + lineage * edge;
    } else if (uniforms.displayMode == 3) {
        float enzymes = max(input.geneC.x + input.geneC.y + input.geneC.z, 0.001);
        color = input.geneC.xyz / enzymes * body * 1.2 + predatorColor * input.geneC.w * head;
    }
    color = 1.0 - exp(-max(color, 0.0) * 1.42);
    return float4(color, saturate(body) * focusVisibility);
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
    float density = 1.0 - exp(-probability * 285000.0);
    float2 combinedAmplitude = wave.xy + wave.zw;
    float phase = fract(atan2(combinedAmplitude.y, combinedAmplitude.x) / (2.0 * M_PI_F) + 1.0);
    float polarization = (probabilityA - probabilityB) / max(probability, 0.0000000001);
    float2 current = float2(
        complexCurrent(wave.xy, waveRight.xy) + complexCurrent(wave.zw, waveRight.zw),
        complexCurrent(wave.xy, waveUp.xy) + complexCurrent(wave.zw, waveUp.zw)
    );
    float currentMagnitude = length(current);
    float currentStrength = saturate(currentMagnitude * 950000.0);
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

    float2 quantumCell = fract(uv * float(quantumGridSize));
    bool positiveComponent = quantumCell.x < 0.5;
    float2 componentPosition = positiveComponent
        ? float2(quantumCell.x * 2.0, quantumCell.y) - 0.5
        : float2((quantumCell.x - 0.5) * 2.0, quantumCell.y) - 0.5;
    float2 componentAmplitude = positiveComponent ? wave.xy : wave.zw;
    float componentProbability = positiveComponent ? probabilityA : probabilityB;
    float componentDensity = 1.0 - exp(-componentProbability * 520000.0);
    float componentPhase = fract(
        atan2(componentAmplitude.y, componentAmplitude.x) / (2.0 * M_PI_F) + 1.0
    );
    float3 componentBase = positiveComponent ? float3(0.02, 0.82, 1.0) : float3(1.0, 0.25, 0.035);
    float3 componentColor = mix(componentBase, quantumPhaseColor(componentPhase), 0.46);
    float componentMask = 1.0 - smoothstep(0.37, 0.48, length(componentPosition));
    float2 phasor = float2(cos(componentPhase * 2.0 * M_PI_F), sin(componentPhase * 2.0 * M_PI_F));
    float phasorLine = 1.0 - smoothstep(0.018, 0.055,
        abs(componentPosition.x * phasor.y - componentPosition.y * phasor.x));
    phasorLine *= smoothstep(0.38, 0.12, length(componentPosition));
    float latticeEdge = 1.0 - smoothstep(0.015, 0.065,
        min(min(quantumCell.x, 1.0 - quantumCell.x), min(quantumCell.y, 1.0 - quantumCell.y)));
    float3 spinorTile = float3(0.002, 0.004, 0.010) +
        componentColor * componentMask * componentDensity;
    spinorTile += float3(0.92, 0.98, 1.0) * phasorLine * componentMask * componentDensity * 0.86;
    spinorTile += float3(0.08, 0.18, 0.26) * latticeEdge * 0.52;
    float latticeReveal = smoothstep(420.0, 900.0, observationZoom);
    color = mix(color, spinorTile, latticeReveal);

    color = 1.0 - exp(-max(color, 0.0) * 1.52);
    return float4(color, 1.0);
}

fragment float4 worldSurfaceFragment(
    RasterData input [[stage_in]],
    texture2d_array<float, access::sample> state [[texture(0)]],
    texture2d_array<float, access::sample> ecology [[texture(1)]],
    texture2d_array<float, access::sample> environment [[texture(2)]],
    constant SimulationUniforms& uniforms [[buffer(0)]]
) {
    constexpr sampler cellSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
    constexpr sampler fieldSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float safeAspect = max(uniforms.viewportAspect, 0.001);
    float2 viewScale = safeAspect >= 1.0 ? float2(1.0, 1.0 / safeAspect) : float2(safeAspect, 1.0);
    float2 rawUV = uniforms.cameraCenter + (input.uv - 0.5) * viewScale /
        max(uniforms.cameraZoom, 0.000000001);
    float2 uv = clamp(rawUV, 0.0, 1.0);
    float2 texel = 1.0 / float2(uniforms.width, uniforms.height);

    float4 cell = state.sample(cellSampler, uv, 0);
    float4 chemistry = ecology.sample(cellSampler, uv, 0);
    float4 geology = environment.sample(fieldSampler, uv, 0);
    float terrain = visualNoise(uv * 43.0);
    float fineTerrain = visualNoise(uv * 97.0 + float2(17.0, 31.0));

    float rockRight = environment.sample(fieldSampler, uv + float2(texel.x, 0.0), 0).w;
    float rockUp = environment.sample(fieldSampler, uv + float2(0.0, texel.y), 0).w;
    float rockGradient = length(float2(rockRight - geology.w, rockUp - geology.w));
    float rock = smoothstep(0.30, 0.68, geology.w + (terrain - 0.5) * 0.52);
    float rockRim = smoothstep(0.018, 0.12, rockGradient) * (1.0 - rock * 0.35);

    float resourceA = saturate(cell.x * 0.82);
    float resourceB = saturate(chemistry.x * 0.86);
    float detritus = saturate(chemistry.y * 1.18);
    float toxin = saturate(max(chemistry.z, geology.z) * 1.28);
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
        color += float3(0.055, 0.070, 0.078) * rock * (0.58 + terrain * 0.34);
        color += float3(0.30, 0.38, 0.40) * rockRim * 0.24;
        color += float3(0.02, 0.82, 0.48) * nutrient * (1.0 - rock) * 0.40;
        color += float3(1.0, 0.56, 0.025) * mineral * (1.0 - rock) * 0.48;
        color += float3(1.0, 0.025, 0.012) * hazard * 0.66;
    }

    color = 1.0 - exp(-max(color, 0.0) * 1.46);
    return float4(color, 1.0);
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
