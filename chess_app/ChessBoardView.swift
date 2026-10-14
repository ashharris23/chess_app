//
//  ChessBoardView.swift
//  chess_app
//

import SwiftUI

extension Color {
    static let lightSquare = Color(red: 0.93, green: 0.85, blue: 0.71)
    static let darkSquare = Color(red: 0.71, green: 0.53, blue: 0.39)
}

struct ChessBoardView: View {
    let game: ChessGame
    /// Shows the board from black's side, with black's pieces at the bottom.
    var flipped = false
    @State private var selected: Position?

    var body: some View {
        let moves = selected.map { game.legalMoves(from: $0) } ?? []

        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let squareSize = side / 8

            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { column in
                            let position = flipped
                                ? Position(row: 7 - row, column: 7 - column)
                                : Position(row: row, column: column)
                            square(at: position, size: squareSize, moves: moves)
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        // Undo changes the board without a tap, so drop any stale selection.
        .onChange(of: game.board) {
            selected = nil
        }
    }

    private func square(at position: Position, size: CGFloat, moves: [Move]) -> some View {
        let move = moves.first { $0.to == position }
        let piece = game.board[position]

        return ZStack {
            Rectangle()
                .fill((position.row + position.column).isMultiple(of: 2) ? Color.lightSquare : Color.darkSquare)

            if position == selected {
                Rectangle().fill(Color.yellow.opacity(0.45))
            } else if position == game.checkedKingPosition {
                Rectangle().fill(Color.red.opacity(0.55))
            }

            if let piece {
                PieceGlyph(piece: piece, size: size * 0.8)
            }

            if let move {
                if piece != nil || move.isEnPassant {
                    Circle()
                        .strokeBorder(Color.black.opacity(0.3), lineWidth: size * 0.08)
                } else {
                    Circle()
                        .fill(Color.black.opacity(0.25))
                        .frame(width: size * 0.3, height: size * 0.3)
                }
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onTapGesture {
            if let move {
                game.make(move)
                selected = nil
            } else if position != selected, piece?.color == game.turn {
                selected = position
            } else {
                selected = nil
            }
        }
    }
}

struct PieceGlyph: View {
    let piece: ChessPiece
    let size: CGFloat

    var body: some View {
        let isWhite = piece.color == .white
        Text(piece.symbol)
            .font(.system(size: size))
            .foregroundStyle(isWhite ? Color.white : Color.black)
            .shadow(color: isWhite ? .black : .clear, radius: 1)
    }
}

#Preview {
    ChessBoardView(game: ChessGame())
        .padding()
}
