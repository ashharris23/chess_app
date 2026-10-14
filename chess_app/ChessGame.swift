//
//  ChessGame.swift
//  chess_app
//

import Observation

struct Move: Equatable {
    let from: Position
    let to: Position
    var isEnPassant = false
    var isCastling = false
}

enum GameStatus: Equatable {
    case inProgress
    case check
    case checkmate(winner: PieceColor)
    case stalemate
}

/// A local two-player game: holds the position and enforces the rules of chess.
@Observable
final class ChessGame {
    private(set) var board = ChessBoard.startingPosition
    private(set) var turn: PieceColor = .white
    private(set) var status: GameStatus = .inProgress
    /// The square a pawn can capture onto en passant. Only set straight after a two-square pawn advance.
    private(set) var enPassantTarget: Position?
    /// A pawn that has reached the last rank and is waiting for the player to pick its promotion.
    private(set) var pendingPromotion: Position?
    /// Every square a move has started from or landed on. A king or rook whose starting
    /// square is in here has moved (or been captured), so it can no longer castle.
    private var touchedSquares: Set<Position> = []

    var isGameOver: Bool {
        switch status {
        case .checkmate, .stalemate: true
        case .inProgress, .check: false
        }
    }

    /// The king of the side to move, if it is in check.
    var checkedKingPosition: Position? {
        Self.isKingInCheck(turn, on: board) ? board.kingPosition(of: turn) : nil
    }

    /// The legal moves for the piece on `position`. Empty unless it is that piece's turn.
    func legalMoves(from position: Position) -> [Move] {
        guard !isGameOver, pendingPromotion == nil,
              let piece = board[position], piece.color == turn else { return [] }
        return generateLegalMoves(from: position, piece: piece)
    }

    func make(_ move: Move) {
        guard legalMoves(from: move.from).contains(move), let piece = board[move.from] else { return }

        board = Self.applying(move, to: board)
        touchedSquares.insert(move.from)
        touchedSquares.insert(move.to)

        if piece.kind == .pawn && abs(move.to.row - move.from.row) == 2 {
            enPassantTarget = Position(row: (move.from.row + move.to.row) / 2, column: move.from.column)
        } else {
            enPassantTarget = nil
        }

        if piece.kind == .pawn && (move.to.row == 0 || move.to.row == 7) {
            pendingPromotion = move.to
        } else {
            endTurn()
        }
    }

    func promote(to kind: PieceKind) {
        guard let position = pendingPromotion, kind != .king, kind != .pawn else { return }
        board[position] = ChessPiece(kind: kind, color: turn)
        pendingPromotion = nil
        endTurn()
    }

    // MARK: - Turn handling

    private func endTurn() {
        turn = turn.opposite

        let inCheck = Self.isKingInCheck(turn, on: board)
        let canMove = ChessBoard.allPositions.contains { position in
            guard let piece = board[position], piece.color == turn else { return false }
            return !generateLegalMoves(from: position, piece: piece).isEmpty
        }

        switch (inCheck, canMove) {
        case (true, false): status = .checkmate(winner: turn.opposite)
        case (false, false): status = .stalemate
        case (true, true): status = .check
        case (false, true): status = .inProgress
        }
    }

    // MARK: - Move generation

    private func generateLegalMoves(from position: Position, piece: ChessPiece) -> [Move] {
        var moves = pseudoLegalMoves(from: position, piece: piece)
        if piece.kind == .king {
            moves += castlingMoves(from: position, color: piece.color)
        }
        // A move is only legal if it doesn't leave the mover's own king in check.
        return moves.filter { !Self.isKingInCheck(piece.color, on: Self.applying($0, to: board)) }
    }

    /// Moves that follow how the piece moves, without checking whether they expose the king.
    private func pseudoLegalMoves(from position: Position, piece: ChessPiece) -> [Move] {
        guard piece.kind == .pawn else {
            return Self.attackedSquares(from: position, piece: piece, on: board)
                .filter { board[$0]?.color != piece.color }
                .map { Move(from: position, to: $0) }
        }

        var moves: [Move] = []
        let oneStep = position.offset(piece.color.forward, 0)
        if oneStep.isOnBoard && board[oneStep] == nil {
            moves.append(Move(from: position, to: oneStep))

            let startingRow = piece.color == .white ? 6 : 1
            let twoSteps = oneStep.offset(piece.color.forward, 0)
            if position.row == startingRow && board[twoSteps] == nil {
                moves.append(Move(from: position, to: twoSteps))
            }
        }

        for target in Self.attackedSquares(from: position, piece: piece, on: board) {
            if let captured = board[target], captured.color != piece.color {
                moves.append(Move(from: position, to: target))
            } else if target == enPassantTarget {
                moves.append(Move(from: position, to: target, isEnPassant: true))
            }
        }
        return moves
    }

    private func castlingMoves(from kingPosition: Position, color: PieceColor) -> [Move] {
        let row = color == .white ? 7 : 0
        guard kingPosition == Position(row: row, column: 4),
              !touchedSquares.contains(kingPosition),
              !Self.isKingInCheck(color, on: board) else { return [] }

        // (rook's column, squares that must be empty, squares the king passes over or lands on)
        let sides = [
            (rookColumn: 7, emptyColumns: [5, 6], kingPath: [5, 6]),
            (rookColumn: 0, emptyColumns: [1, 2, 3], kingPath: [3, 2]),
        ]

        return sides.compactMap { side in
            let rookPosition = Position(row: row, column: side.rookColumn)
            guard !touchedSquares.contains(rookPosition),
                  board[rookPosition] == ChessPiece(kind: .rook, color: color),
                  side.emptyColumns.allSatisfy({ board[Position(row: row, column: $0)] == nil }),
                  !side.kingPath.contains(where: {
                      Self.isSquareAttacked(Position(row: row, column: $0), by: color.opposite, on: board)
                  })
            else { return nil }
            return Move(from: kingPosition, to: Position(row: row, column: side.kingPath[1]), isCastling: true)
        }
    }

    // MARK: - Board analysis

    /// The squares a piece attacks. For pawns that's only the diagonal captures.
    private static func attackedSquares(from position: Position, piece: ChessPiece, on board: ChessBoard) -> [Position] {
        let orthogonal = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        let diagonal = [(1, 1), (1, -1), (-1, 1), (-1, -1)]

        func steps(_ offsets: [(Int, Int)]) -> [Position] {
            offsets.map { position.offset($0.0, $0.1) }.filter(\.isOnBoard)
        }

        func slides(_ directions: [(Int, Int)]) -> [Position] {
            directions.flatMap { direction in
                var squares: [Position] = []
                var current = position.offset(direction.0, direction.1)
                while current.isOnBoard {
                    squares.append(current)
                    if board[current] != nil { break }
                    current = current.offset(direction.0, direction.1)
                }
                return squares
            }
        }

        switch piece.kind {
        case .pawn:
            return steps([(piece.color.forward, -1), (piece.color.forward, 1)])
        case .knight:
            return steps([(1, 2), (2, 1), (-1, 2), (-2, 1), (1, -2), (2, -1), (-1, -2), (-2, -1)])
        case .king:
            return steps(orthogonal + diagonal)
        case .rook:
            return slides(orthogonal)
        case .bishop:
            return slides(diagonal)
        case .queen:
            return slides(orthogonal + diagonal)
        }
    }

    private static func isSquareAttacked(_ square: Position, by color: PieceColor, on board: ChessBoard) -> Bool {
        ChessBoard.allPositions.contains { position in
            guard let piece = board[position], piece.color == color else { return false }
            return attackedSquares(from: position, piece: piece, on: board).contains(square)
        }
    }

    private static func isKingInCheck(_ color: PieceColor, on board: ChessBoard) -> Bool {
        guard let king = board.kingPosition(of: color) else { return false }
        return isSquareAttacked(king, by: color.opposite, on: board)
    }

    /// The board after `move`, including the side effects of en passant and castling.
    private static func applying(_ move: Move, to board: ChessBoard) -> ChessBoard {
        var board = board
        board[move.to] = board[move.from]
        board[move.from] = nil

        if move.isEnPassant {
            board[Position(row: move.from.row, column: move.to.column)] = nil
        }
        if move.isCastling {
            let rookFrom = Position(row: move.from.row, column: move.to.column > move.from.column ? 7 : 0)
            let rookTo = Position(row: move.from.row, column: (move.from.column + move.to.column) / 2)
            board[rookTo] = board[rookFrom]
            board[rookFrom] = nil
        }
        return board
    }
}
