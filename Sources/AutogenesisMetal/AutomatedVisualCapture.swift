import Foundation
import Metal
import MetalKit

struct AutomatedVisualCaptureConfiguration: Sendable {
    let outputURL: URL
    let width: Int
    let height: Int
    let steps: UInt64
    let seed: UInt32
    let magnification: Float
    let introducesFounder: Bool

    static func parse(_ arguments: ArraySlice<String>) throws -> Self {
        var outputPath: String?
        var width = 1_240
        var height = 820
        var steps: UInt64 = 720
        var seed: UInt32 = 1
        var magnification: Float = 96
        var introducesFounder = false
        var index = arguments.startIndex

        func value(after option: String) throws -> String {
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else {
                throw AutomatedVisualCaptureError.missingValue(option)
            }
            index = valueIndex
            return arguments[valueIndex]
        }

        while index < arguments.endIndex {
            let argument = arguments[index]
            switch argument {
            case "--output":
                outputPath = try value(after: argument)
            case "--width":
                let raw = try value(after: argument)
                guard let parsed = Int(raw), (320...7_680).contains(parsed) else {
                    throw AutomatedVisualCaptureError.invalidValue(argument, raw)
                }
                width = parsed
            case "--height":
                let raw = try value(after: argument)
                guard let parsed = Int(raw), (240...4_320).contains(parsed) else {
                    throw AutomatedVisualCaptureError.invalidValue(argument, raw)
                }
                height = parsed
            case "--steps":
                let raw = try value(after: argument)
                guard let parsed = UInt64(raw), parsed > 0 else {
                    throw AutomatedVisualCaptureError.invalidValue(argument, raw)
                }
                steps = parsed
            case "--seed":
                let raw = try value(after: argument)
                guard let parsed = UInt32(raw) else {
                    throw AutomatedVisualCaptureError.invalidValue(argument, raw)
                }
                seed = parsed
            case "--magnification":
                let raw = try value(after: argument)
                guard let parsed = Float(raw), parsed.isFinite, parsed > 0 else {
                    throw AutomatedVisualCaptureError.invalidValue(argument, raw)
                }
                magnification = parsed
            case "--add-life":
                introducesFounder = true
            case "-h", "--help":
                print("""
                Usage: NumiAutomata capture --output PATH [options]
                  --width N             Render width (default: 1240)
                  --height N            Render height (default: 820)
                  --steps N             Biological steps before capture (default: 720)
                  --seed N              Deterministic world seed (default: 1)
                  --magnification VALUE Observation magnification (default: 96)
                  --add-life            Introduce one audited founder before simulation
                """)
                exit(EXIT_SUCCESS)
            default:
                throw AutomatedVisualCaptureError.unknownOption(argument)
            }
            index = arguments.index(after: index)
        }

        guard let outputPath else { throw AutomatedVisualCaptureError.missingOutput }
        return Self(
            outputURL: URL(fileURLWithPath: outputPath).standardizedFileURL,
            width: width,
            height: height,
            steps: steps,
            seed: seed,
            magnification: magnification,
            introducesFounder: introducesFounder
        )
    }
}

enum AutomatedVisualCaptureError: LocalizedError {
    case missingOutput
    case missingValue(String)
    case invalidValue(String, String)
    case unknownOption(String)

    var errorDescription: String? {
        switch self {
        case .missingOutput:
            "capture requires --output PATH"
        case let .missingValue(option):
            "capture option \(option) requires a value"
        case let .invalidValue(option, value):
            "capture option \(option) has invalid value \(value)"
        case let .unknownOption(option):
            "unknown capture option \(option)"
        }
    }
}

enum AutomatedVisualCaptureCLI {
    @MainActor
    static func run(arguments: ArraySlice<String>) throws {
        let configuration = try AutomatedVisualCaptureConfiguration.parse(arguments)
        try FileManager.default.createDirectory(
            at: configuration.outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw EvolutionRendererError.noMetalDevice
        }
        let view = MTKView(frame: .zero, device: device)
        view.isPaused = true
        let renderer = try EvolutionRenderer(view: view)
        try renderer.runHeadlessVisualCapture(configuration: configuration)
        print(
            "numi_capture=\(configuration.outputURL.path) " +
                "steps=\(configuration.steps) magnification=\(configuration.magnification) " +
                "add_life=\(configuration.introducesFounder ? 1 : 0) " +
                "size=\(configuration.width)x\(configuration.height)"
        )
    }
}
