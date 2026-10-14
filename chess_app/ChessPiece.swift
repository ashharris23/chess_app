//
//  ChessPiece.swift
//  chess_app
//

enum PieceColor {
    case white
    case black

    var opposite: PieceColor {
        self == .white ? .black : .white
    }

    var name: String {
        self == .white ? "White" : "Black"
    }

    /// The row direction this colour's pawns advance in (white starts at the bottom).
    var forward: Int {
        self == .white ? -1 : 1
    }
}

enum PieceKind {
    case king, queen, rook, bishop, knight, pawn
}

struct ChessPiece: Equatable {
    let kind: PieceKind
    let color: PieceColor

    /// Unicode chess glyph. The solid (black) glyphs are used for both colours
    /// so that they can be tinted; white pieces are drawn in white.
    var symbol: String {
        switch kind {
        case .king: "♚"
        case .queen: "♛"
        case .rook: "♜"
        case .bishop: "♝"
        case .knight: "♞"
        case .pawn: "♟\u{FE0E}"
        }
    }
}

struct Position: Hashable {
    let row: Int
    let column: Int

    var isOnBoard: Bool {
        (0..<8).contains(row) && (0..<8).contains(column)
    }

    func offset(_ rowDelta: Int, _ columnDelta: Int) -> Position {
        Position(row: row + rowDelta, column: column + columnDelta)
    }
}

/// An 8x8 board. Row 0 is rank 8 (top), column 0 is file a, so white starts at the bottom.
struct ChessBoard {
    var squares: [[ChessPiece?]]

    static let allPositions: [Position] = (0..<8).flatMap { row in
        (0..<8).map { column in Position(row: row, column: column) }
    }

    subscript(position: Position) -> ChessPiece? {
        get { squares[position.row][position.column] }
        set { squares[position.row][position.column] = newValue }
    }

    func kingPosition(of color: PieceColor) -> Position? {
        Self.allPositions.first { self[$0] == ChessPiece(kind: .king, color: color) }
    }

    static var startingPosition: ChessBoard {
        let backRank: [PieceKind] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]

        var squares = Array(repeating: Array<ChessPiece?>(repeating: nil, count: 8), count: 8)
        for column in 0..<8 {
            squares[0][column] = ChessPiece(kind: backRank[column], color: .black)
            squares[1][column] = ChessPiece(kind: .pawn, color: .black)
            squares[6][column] = ChessPiece(kind: .pawn, color: .white)
            squares[7][column] = ChessPiece(kind: backRank[column], color: .white)
        }
        return ChessBoard(squares: squares)
    }
}
