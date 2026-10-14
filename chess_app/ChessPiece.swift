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

    /// Reads a FEN/UCI piece letter, in either case.
    init?(fenLetter: Character) {
        switch fenLetter.lowercased() {
        case "k": self = .king
        case "q": self = .queen
        case "r": self = .rook
        case "b": self = .bishop
        case "n": self = .knight
        case "p": self = .pawn
        default: return nil
        }
    }
}

struct ChessPiece: Hashable {
    let kind: PieceKind
    let color: PieceColor

    /// Unicode chess glyph. The solid (black) glyphs are used for both colours
    /// so that they can be tinted; white pieces are drawn in white.
    /// The FEN letter: uppercase for white, lowercase for black.
    var fenLetter: String {
        let letter = switch kind {
        case .king: "k"
        case .queen: "q"
        case .rook: "r"
        case .bishop: "b"
        case .knight: "n"
        case .pawn: "p"
        }
        return color == .white ? letter.uppercased() : letter
    }

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

    /// The square name, such as "e4".
    var algebraic: String {
        let file = Character(UnicodeScalar(UInt8(97 + column)))
        return "\(file)\(8 - row)"
    }

    func offset(_ rowDelta: Int, _ columnDelta: Int) -> Position {
        Position(row: row + rowDelta, column: column + columnDelta)
    }
}

// In an extension so that Position keeps its memberwise initializer.
extension Position {
    /// Reads a square name such as "e4".
    init?(algebraic: String) {
        let characters = Array(algebraic)
        guard characters.count == 2,
              let file = characters[0].asciiValue, (97...104).contains(file),
              let rank = characters[1].wholeNumberValue, (1...8).contains(rank) else { return nil }
        self.init(row: 8 - rank, column: Int(file) - 97)
    }
}

/// An 8x8 board. Row 0 is rank 8 (top), column 0 is file a, so white starts at the bottom.
struct ChessBoard: Hashable {
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
