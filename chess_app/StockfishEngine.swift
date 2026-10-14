//
//  StockfishEngine.swift
//  chess_app
//

import ChessKitEngine
import Foundation

/// Runs Stockfish on the device (via the ChessKitEngine package) and asks it for moves.
///
/// - Important: ChessKitEngine talks to Stockfish by redirecting the app's standard output,
///   so anything written with `print()` goes into the engine's pipe. That can corrupt one of
///   Stockfish's replies and leave the computer thinking forever. Use `Logger` (os.log) instead.
final class StockfishEngine {
    enum Difficulty: Int, CaseIterable, Identifiable {
        case easy, medium, hard, maximum

        var id: Self { self }

        var name: String {
            switch self {
            case .easy: "Easy"
            case .medium: "Medium"
            case .hard: "Hard"
            case .maximum: "Maximum"
            }
        }

        /// Stockfish's "Skill Level" option, from 0 (weakest) to 20 (full strength).
        var skillLevel: Int {
            switch self {
            case .easy: 1
            case .medium: 6
            case .hard: 12
            case .maximum: 20
            }
        }

        /// How long Stockfish thinks per move, in milliseconds.
        var moveTime: Int {
            switch self {
            case .easy: 200
            case .medium: 400
            case .hard: 800
            case .maximum: 1500
            }
        }
    }

    enum EngineError: LocalizedError {
        case missingNetworkFiles
        case failedToStart

        var errorDescription: String? {
            switch self {
            case .missingNetworkFiles:
                "Stockfish's network files (nn-1111cefa1111.nnue and nn-37f18f62d772.nnue) are missing from the app."
            case .failedToStart:
                "Stockfish didn't start."
            }
        }
    }

    /// The NNUE evaluation networks Stockfish 17 needs, by UCI option name, found in the app bundle.
    ///
    /// ChessKitEngine also sets these, but it percent-encodes the paths, so any path containing a
    /// space (such as Xcode Previews' "Simulator Devices" folder) points at a file that doesn't exist,
    /// and Stockfish then quits the whole app when asked to search. We send the plain paths before
    /// every search instead; Stockfish skips reloading a network it already has loaded.
    private static let networkPaths: [String: String]? = {
        let files = ["EvalFile": "nn-1111cefa1111", "EvalFileSmall": "nn-37f18f62d772"]
        let paths = files.compactMapValues {
            Bundle.main.url(forResource: $0, withExtension: "nnue")?.path(percentEncoded: false)
        }
        return paths.count == files.count ? paths : nil
    }()

    private let engine = Engine(type: .stockfish)
    private var startup: Task<Bool, Never>?
    private var responseListener: Task<Void, Never>?
    /// The search currently running (or queued). Searches run one at a time so that each
    /// `bestmove` Stockfish sends back belongs to the request waiting for it.
    private var currentSearch: Task<String?, Never>?
    private var waitingForBestMove: CheckedContinuation<String?, Never>?

    deinit {
        responseListener?.cancel()
    }

    /// Asks Stockfish for its move in the position `fen`, as a UCI move such as "e2e4" or "e7e8q".
    /// Cancelling the calling task stops the search early.
    func bestMove(fen: String, difficulty: Difficulty) async throws -> String? {
        // Stockfish quits the whole process if its networks are missing, so check first.
        guard let networkPaths = Self.networkPaths else {
            throw EngineError.missingNetworkFiles
        }
        guard await start() else {
            throw EngineError.failedToStart
        }

        let previousSearch = currentSearch
        let search = Task { () -> String? in
            if let previousSearch {
                await engine.send(command: .stop)
                _ = await previousSearch.value
            }
            for (option, path) in networkPaths.sorted(by: { $0.key < $1.key }) {
                await engine.send(command: .setoption(id: option, value: path))
            }
            await engine.send(command: .setoption(id: "Skill Level", value: String(difficulty.skillLevel)))
            await engine.send(command: .position(.fen(fen)))
            return await withCheckedContinuation { continuation in
                waitingForBestMove = continuation
                Task { await engine.send(command: .go(movetime: difficulty.moveTime)) }
            }
        }
        currentSearch = search

        let stockfish = engine
        return await withTaskCancellationHandler {
            await search.value
        } onCancel: {
            // Makes Stockfish answer straight away, which finishes the search.
            Task { await stockfish.send(command: .stop) }
        }
    }

    /// Starts the engine the first time it's needed. Returns whether it's running.
    private func start() async -> Bool {
        if let startup {
            return await startup.value
        }

        let startup = Task { () -> Bool in
            await engine.start(coreCount: ProcessInfo.processInfo.activeProcessorCount)

            // `isRunning` turns true once the engine has finished its UCI handshake.
            for _ in 0..<200 where !(await engine.isRunning) {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard await engine.isRunning, let responses = await engine.responseStream else { return false }

            responseListener = Task { [weak self] in
                for await response in responses {
                    if case let .bestmove(move, _) = response {
                        self?.receivedBestMove(move)
                    }
                }
            }
            return true
        }
        self.startup = startup
        return await startup.value
    }

    private func receivedBestMove(_ move: String) {
        // Stockfish answers "(none)" when the side to move has no legal moves.
        waitingForBestMove?.resume(returning: move == "(none)" ? nil : move)
        waitingForBestMove = nil
    }
}
