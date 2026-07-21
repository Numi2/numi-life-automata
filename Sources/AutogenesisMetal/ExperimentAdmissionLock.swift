import Darwin
import Foundation

enum ExperimentAdmissionError: LocalizedError {
    case unavailable(owner: String)
    case system(String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(owner):
            "Another Numi Automata GPU experiment holds the admission lock\(owner.isEmpty ? "." : " (\(owner)).") Use --allow-concurrent only when separate GPU load is intentional."
        case let .system(message): message
        }
    }
}

/// A kernel-released advisory lock. A crash cannot leave it permanently held.
final class ExperimentAdmissionLock {
    private static let path = "/tmp/com.numi.automata.gpu-experiment.lock"
    private let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    static func acquire(unless allowConcurrent: Bool) throws -> ExperimentAdmissionLock? {
        guard !allowConcurrent else { return nil }
        let descriptor = open(path, O_RDWR | O_CREAT | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw ExperimentAdmissionError.system(
                "Could not open the GPU experiment admission lock: \(String(cString: strerror(errno)))."
            )
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let owner = readOwner(from: descriptor)
            close(descriptor)
            throw ExperimentAdmissionError.unavailable(owner: owner)
        }
        let identity = "pid=\(getpid()) started=\(ISO8601DateFormatter().string(from: Date()))"
        ftruncate(descriptor, 0)
        identity.withCString { pointer in
            _ = Darwin.write(descriptor, pointer, strlen(pointer))
        }
        return ExperimentAdmissionLock(descriptor: descriptor)
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }

    private static func readOwner(from descriptor: Int32) -> String {
        guard lseek(descriptor, 0, SEEK_SET) >= 0 else { return "" }
        var bytes = [UInt8](repeating: 0, count: 256)
        let count = Darwin.read(descriptor, &bytes, bytes.count)
        guard count > 0 else { return "" }
        return String(decoding: bytes.prefix(count), as: UTF8.self)
    }
}
