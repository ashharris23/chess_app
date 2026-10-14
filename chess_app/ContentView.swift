//
//  ContentView.swift
//  chess_app
//
//  Created by Ashley Harris on 14/10/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var game = ChessGame()

    var body: some View {
        VStack(spacing: 20) {
            Text(statusText)
                .font(.title2.bold())

            ChessBoardView(game: game)
                // A new game gets a fresh board view, clearing any selected square.
                .id(ObjectIdentifier(game))

            if game.pendingPromotion != nil {
                promotionPicker
            }

            Button("New Game") {
                game = ChessGame()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var statusText: String {
        switch game.status {
        case .inProgress:
            "\(game.turn.name) to move"
        case .check:
            "\(game.turn.name) is in check"
        case .checkmate(let winner):
            "Checkmate — \(winner.name) wins"
        case .stalemate:
            "Stalemate — it's a draw"
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
