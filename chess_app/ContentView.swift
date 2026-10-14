//
//  ContentView.swift
//  chess_app
//
//  Created by Ashley Harris on 14/10/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var game = ChessGame()
    @State private var setup = GameSetup()
    @State private var engine = StockfishEngine()
    @State private var showingNewGame = false
    @State private var engineError: String?

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Text(statusText)
                        .font(.title2.bold())
                    if isComputerTurn {
                        ProgressView()
                    }
                }
                Text(setup.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ChessBoardView(game: game, flipped: setup.computerColor == .white)
                // A new game gets a fresh board view, clearing any selected square.
                .id(ObjectIdentifier(game))
                .allowsHitTesting(!isComputerTurn)

            if game.pendingPromotion != nil {
                promotionPicker
            }

            HStack(spacing: 16) {
                Button("Undo", action: undo)
                    .disabled(!canUndo)

                Button("New Game") {
                    showingNewGame = true
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .task(id: ComputerTurnKey(game: ObjectIdentifier(game), fen: game.fen, setup: setup)) {
            await playComputerMoveIfNeeded()
        }
        .sheet(isPresented: $showingNewGame) {
            NewGameView(setup: setup) { newSetup in
                setup = newSetup
                game = ChessGame()
            }
        }
        .alert("Stockfish couldn't move", isPresented: Binding(
            get: { engineError != nil },
            set: { if !$0 { engineError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(engineError ?? "")
        }
    }

    /// The computer's turn restarts whenever the game, position or setup changes.
    private struct ComputerTurnKey: Hashable {
        let game: ObjectIdentifier
        let fen: String
        let setup: GameSetup
    }

    private var isComputerTurn: Bool {
        game.turn == setup.computerColor && !game.isGameOver && game.pendingPromotion == nil
    }

    private func playComputerMoveIfNeeded() async {
        guard isComputerTurn else { return }
        let currentGame = game
        let fen = game.fen

        do {
            let move = try await engine.bestMove(fen: fen, difficulty: setup.difficulty)
            // Ignore the answer if the player undid or started a new game while Stockfish was thinking.
            guard !Task.isCancelled, currentGame === game, game.fen == fen, let move else { return }
            game.make(uciMove: move)
        } catch {
            engineError = error.localizedDescription
        }
    }

    private var canUndo: Bool {
        guard let computerColor = setup.computerColor else { return game.canUndo }
        // Only allow undo once the player has made a move of their own.
        let playerMoves = computerColor == .black ? (game.plyCount + 1) / 2 : game.plyCount / 2
        return playerMoves > 0
    }

    private func undo() {
        game.undo()
        // Against the computer, take back its reply too so that it's the player's turn again.
        if game.turn == setup.computerColor && game.canUndo {
            game.undo()
        }
    }

    private var statusText: String {
        switch game.status {
        case .inProgress where isComputerTurn:
            "Stockfish is thinking…"
        case .inProgress:
            "\(game.turn.name) to move"
        case .check:
            "\(game.turn.name) is in check"
        case .checkmate(let winner):
            "Checkmate — \(winner.name) wins"
        case .stalemate:
            "Stalemate — it's a draw"
        case .draw(.fiftyMoveRule):
            "Draw — 50 moves without a capture or pawn move"
        case .draw(.threefoldRepetition):
            "Draw — the same position occurred three times"
        case .draw(.insufficientMaterial):
            "Draw — not enough pieces left to checkmate"
        }
    }

    private var promotionPicker: some View {
        VStack(spacing: 8) {
            Text("Promote pawn to:")
                .font(.headline)
            HStack(spacing: 12) {
                ForEach([PieceKind.queen, .rook, .bishop, .knight], id: \.self) { kind in
                    Button {
                        game.promote(to: kind)
                    } label: {
                        PieceGlyph(piece: ChessPiece(kind: kind, color: game.turn), size: 40)
                            .frame(width: 56, height: 56)
                            .background(Color.darkSquare, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
