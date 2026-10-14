//
//  NewGameView.swift
//  chess_app
//

import SwiftUI

struct GameSetup: Hashable {
    enum Opponent: Hashable {
        case human
        case computer
    }

    var opponent: Opponent = .human
    /// Which side the player takes when playing the computer.
    var playerColor: PieceColor = .white
    var difficulty: StockfishEngine.Difficulty = .medium

    /// The side Stockfish plays, or nil in a two-player game.
    var computerColor: PieceColor? {
        opponent == .computer ? playerColor.opposite : nil
    }

    var description: String {
        switch opponent {
        case .human: "Two players"
        case .computer: "You play \(playerColor.name) vs Stockfish (\(difficulty.name))"
        }
    }
}

struct NewGameView: View {
    @State var setup: GameSetup
    let onStart: (GameSetup) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("Opponent", selection: $setup.opponent) {
                    Text("Two Players").tag(GameSetup.Opponent.human)
                    Text("Computer").tag(GameSetup.Opponent.computer)
                }
                .pickerStyle(.segmented)

                if setup.opponent == .computer {
                    Picker("You play", selection: $setup.playerColor) {
                        Text("White").tag(PieceColor.white)
                        Text("Black").tag(PieceColor.black)
                    }

                    Picker("Difficulty", selection: $setup.difficulty) {
                        ForEach(StockfishEngine.Difficulty.allCases) { difficulty in
                            Text(difficulty.name).tag(difficulty)
                        }
                    }
                }
            }
            .navigationTitle("New Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        onStart(setup)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    NewGameView(setup: GameSetup()) { _ in }
}
