import Darwin
import Dispatch
import Foundation

private struct Options {
    let terminalKitPath: String
    let autoStatePath: String
    let logPath: String
    let recoverySeconds: Double

    static func parse(_ arguments: [String]) throws -> Options {
        var terminalKitPath: String?
        var autoStatePath: String?
        var logPath: String?
        var recoverySeconds: Double = 300

        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            guard index + 1 < arguments.count else {
                throw NSError(
                    domain: "terminal-kit-memoryd",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "missing value for \(argument)"]
                )
            }

            let value = arguments[index + 1]
            switch argument {
            case "--terminal-kit":
                terminalKitPath = value
            case "--auto-state":
                autoStatePath = value
            case "--log":
                logPath = value
            case "--recovery-seconds":
                guard let parsed = Double(value), parsed >= 30 else {
                    throw NSError(
                        domain: "terminal-kit-memoryd",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "recovery seconds must be at least 30"]
                    )
                }
                recoverySeconds = parsed
            default:
                throw NSError(
                    domain: "terminal-kit-memoryd",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "unknown argument: \(argument)"]
                )
            }
            index += 2
        }

        guard let terminalKitPath, let autoStatePath, let logPath else {
            throw NSError(
                domain: "terminal-kit-memoryd",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "--terminal-kit, --auto-state, and --log are required"]
            )
        }

        return Options(
            terminalKitPath: terminalKitPath,
            autoStatePath: autoStatePath,
            logPath: logPath,
            recoverySeconds: recoverySeconds
        )
    }
}

// All mutable state is isolated to `queue`. The unchecked conformance is needed
// because Dispatch event handlers are @Sendable in current Swift toolchains.
private final class MemoryController: @unchecked Sendable {
    private let options: Options
    private let queue = DispatchQueue(label: "com.terminal-kit.memoryd")
    private var recoveryWorkItem: DispatchWorkItem?
    private var pressureSource: (any DispatchSourceMemoryPressure)?
    private var terminationSource: (any DispatchSourceSignal)?
    private var interruptSource: (any DispatchSourceSignal)?

    init(options: Options) {
        self.options = options
    }

    func run() {
        log("started; recovery delay \(Int(options.recoverySeconds))s")

        let pressure = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: queue
        )
        pressureSource = pressure
        pressure.setEventHandler { [weak self] in
            guard let self, let source = self.pressureSource else { return }
            self.handle(source.data)
        }
        pressure.setCancelHandler { [weak self] in
            self?.log("stopped")
        }
        pressure.activate()

        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)

        let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)
        terminationSource = termination
        termination.setEventHandler { [weak self] in
            self?.shutdown()
        }
        termination.activate()

        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: queue)
        interruptSource = interrupt
        interrupt.setEventHandler { [weak self] in
            self?.shutdown()
        }
        interrupt.activate()

        dispatchMain()
    }

    private func handle(_ event: DispatchSource.MemoryPressureEvent) {
        guard autoEnabled() else {
            log("automatic mode is off; ignoring pressure event")
            return
        }

        if event.contains(.critical) {
            recoveryWorkItem?.cancel()
            recoveryWorkItem = nil
            apply(mode: "ultra", pressure: "critical")
            return
        }

        if event.contains(.warning) {
            recoveryWorkItem?.cancel()
            recoveryWorkItem = nil
            apply(mode: "lean", pressure: "warning")
            return
        }

        if event.contains(.normal) {
            recoveryWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.autoEnabled() else { return }
                self.apply(mode: "balanced", pressure: "normal")
            }
            recoveryWorkItem = workItem
            queue.asyncAfter(deadline: .now() + options.recoverySeconds, execute: workItem)
            log("pressure normal; recovery scheduled")
        }
    }

    private func apply(mode: String, pressure: String) {
        guard autoEnabled() else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: options.terminalKitPath)
        process.arguments = ["memory", "_auto-apply", mode, pressure]

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                log("pressure \(pressure); applied \(mode)")
            } else {
                log("pressure \(pressure); terminal-kit exited \(process.terminationStatus)")
            }
        } catch {
            log("could not apply \(mode): \(error.localizedDescription)")
        }
    }

    private func autoEnabled() -> Bool {
        guard let data = FileManager.default.contents(atPath: options.autoStatePath),
              let value = String(data: data, encoding: .utf8) else {
            return false
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines) == "on"
    }

    private func log(_ message: String) {
        let url = URL(fileURLWithPath: options.logPath)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if !FileManager.default.fileExists(atPath: url.path) {
            _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Logging must never destabilize the controller.
        }
    }

    private func shutdown() {
        recoveryWorkItem?.cancel()
        pressureSource?.cancel()
        terminationSource?.cancel()
        interruptSource?.cancel()
        exit(0)
    }
}

@main
private enum TerminalKitMemoryDaemon {
    static func main() {
        do {
            let options = try Options.parse(CommandLine.arguments)
            MemoryController(options: options).run()
        } catch {
            FileHandle.standardError.write(
                Data("terminal-kit-memoryd: \(error.localizedDescription)\n".utf8)
            )
            exit(2)
        }
    }
}
