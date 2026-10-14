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

enum DrawReason: Equatable {
    case fiftyMoveRule
    case threefoldRepetition
    case insufficientMaterial
}

enum GameStatus: Equatable {
    case inProgress
    case check
    case checkmate(winner: PieceColor)
    case stalemate
    case draw(DrawReason)
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
    /// Half-moves (one player's turn each) since the last pawn move or capture.
    private(set) var halfmoveClock = 0
    /// Starts at 1 and goes up after each black move, as in FEN.
    private(set) var fullmoveNumber = 1
    /// How many times each position has occurred, for threefold repetition.
    private var positionCounts: [PositionKey: Int] = [:]
    private var history: [Snapshot] = []

    /// Everything a move can change, so that it can be undone.
    private struct Snapshot {
        let board: ChessBoard
        let turn: PieceColor
        let status: GameStatus
        let enPassantTarget: Position?
        let pendingPromotion: Position?
        let touchedSquares: Set<Position>
        let halfmoveClock: Int
        let fullmoveNumber: Int
        let positionCounts: [PositionKey: Int]
    }

    /// Two positions are the same for repetition if the pieces, the side to move,
    /// the castling rights and the en passant possibilities all match.
    private struct PositionKey: Hashable {
        let board: ChessBoard
        let turn: PieceColor
        let castlingRights: [Bool]
        let enPassantTarget: Position?
    }

    init() {
        positionCounts[positionKey()] = 1
    }

    /// Starts from a custom position (used for tests and puzzles). Castling is allowed
    /// wherever the king and rook are on their home squares.
    init(board: ChessBoard, turn: PieceColor = .white) {
        self.board = board
        self.turn = turn
        positionCounts[positionKey()] = 1
        evaluateStatus()
    }

    var isGameOver: Bool {
        switch status {
        case .checkmate, .stalemate, .draw: true
        case .inProgress, .check: false
        }
    }

    var canUndo: Bool {
        !history.isEmpty
    }

    /// The number of half-moves played so far (that can be undone).
    var plyCount: Int {
        history.count
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

        history.append(Snapshot(
            board: board, turn: turn, status: status, enPassantTarget: enPassantTarget,
            pendingPromotion: pendingPromotion, touchedSquares: touchedSquares,
            halfmoveClock: halfmoveClock, fullmoveNumber: fullmoveNumber, positionCounts: positionCounts
        ))

        let isCapture = board[move.to] != nil || move.isEnPassant
        halfmoveClock = (piece.kind == .pawn || isCapture) ? 0 : halfmoveClock + 1

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

    /// Takes back the last move, including a promotion that is still waiting to be chosen.
    func undo() {
        guard let snapshot = history.popLast() else { return }
        board = snapshot.board
        turn = snapshot.turn
        status = snapshot.status
        enPassantTarget = snapshot.enPassantTarget
        pendingPromotion = snapshot.pendingPromotion
        touchedSquares = snapshot.touchedSquares
        halfmoveClock = snapshot.halfmoveClock
        fullmoveNumber = snapshot.fullmoveNumber
        positionCounts = snapshot.positionCounts
    }

    // MARK: - UCI (for talking to chess engines)

    /// The current position in Forsyth–Edwards Notation.
    var fen: String {
        let placement = (0..<8).map { row in
            var rank = ""
            var emptyCount = 0
            for column in 0..<8 {
                if let piece = board[Position(row: row, column: column)] {
                    if emptyCount > 0 { rank += String(emptyCount) }
                    emptyCount = 0
                    rank += piece.fenLetter
                } else {
                    emptyCount += 1
                }
            }
            if emptyCount > 0 { rank += String(emptyCount) }
            return rank
        }.joined(separator: "/")

        let castling = [
            canCastle(.white, rookColumn: 7) ? "K" : "",
            canCastle(.white, rookColumn: 0) ? "Q" : "",
            canCastle(.black, rookColumn: 7) ? "k" : "",
            canCastle(.black, rookColumn: 0) ? "q" : "",
        ].joined()

        return [
            placement,
            turn == .white ? "w" : "b",
            castling.isEmpty ? "-" : castling,
            enPassantTarget?.algebraic ?? "-",
            String(halfmoveClock),
            String(fullmoveNumber),
        ].joined(separator: " ")
    }

    /// Plays a move in UCI long algebraic notation, such as "e2e4" or "e7e8q".
    /// Returns false (and changes nothing) if the move isn't legal.
    @discardableResult
    func make(uciMove: String) -> Bool {
        let characters = Array(uciMove)
        guard characters.count == 4 || characters.count == 5,
              let from = Position(algebraic: String(characters[0...1])),
              let to = Position(algebraic: String(characters[2...3])),
              let move = legalMoves(from: from).first(where: { $0.to == to }) else { return false }

        let promotion = characters.count == 5 ? PieceKind(fenLetter: characters[4]) : nil
        make(move)
        if pendingPromotion != nil {
            promote(to: promotion ?? .queen)
        }
        return true
    }

    // MARK: - Turn handling

    private func endTurn() {
        if turn == .black {
            fullmoveNumber += 1
        }
        turn = turn.opposite
        positionCounts[positionKey(), default: 0] += 1
        evaluateStatus()
    }

    private func evaluateStatus() {
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

        // Checkmate and stalemate take priority over the automatic draws.
        if status == .inProgress || status == .check, let reason = drawReason() {
            status = .draw(reason)
        }
    }

    private func drawReason() -> DrawReason? {
        if hasInsufficientMaterial() { return .insufficientMaterial }
        if positionCounts[positionKey(), default: 0] >= 3 { return .threefoldRepetition }
        if halfmoveClock >= 100 { return .fiftyMoveRule }
        return nil
    }

    /// True when neither side could ever deliver checkmate: bare kings, a lone knight or bishop,
    /// or only bishops that all stand on the same colour of square.
    private func hasInsufficientMaterial() -> Bool {
        let others = ChessBoard.allPositions.compactMap { position in
            board[position].flatMap { $0.kind == .king ? nil : (position, $0.kind) }
        }
        if others.isEmpty { return true }
        if others.count == 1 { return others[0].1 == .bishop || others[0].1 == .knight }

        guard others.allSatisfy({ $0.1 == .bishop }) else { return false }
        return Set(others.map { ($0.0.row + $0.0.column) % 2 }).count == 1
    }

    /// Whether `color` still has the right to castle with the rook in `rookColumn`
    /// (ignoring whether castling is possible right now).
    private func canCastle(_ color: PieceColor, rookColumn: Int) -> Bool {
        let row = color == .white ? 7 : 0
        let king = Position(row: row, column: 4)
        let rook = Position(row: row, column: rookColumn)
        return board[king] == ChessPiece(kind: .king, color: color)
            && board[rook] == ChessPiece(kind: .rook, color: color)
            && !touchedSquares.contains(king) && !touchedSquares.contains(rook)
    }

    private func positionKey() -> PositionKey {
        // An en passant square only matters if a capture onto it is actually possible.
        let enPassantPossible = enPassantTarget != nil && ChessBoard.allPositions.contains { position in
            guard let piece = board[position], piece.color == turn, piece.kind == .pawn else { return false }
            return generateLegalMoves(from: position, piece: piece).contains { $0.isEnPassant }
        }

        return PositionKey(
            board: board,
            turn: turn,
            castlingRights: [
                canCastle(.white, rookColumn: 7), canCastle(.white, rookColumn: 0),
                canCastle(.black, rookColumn: 7), canCastle(.black, rookColumn: 0),
            ],
            enPassantTarget: enPassantPossible ? enPassantTarget : nil
        )
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
