import Foundation

/// Un tema de color del panel o de la barra. Los originales salen de `TemaDePanel` y `TemaDeBarra`;
/// el usuario puede editarlos, borrarlos y agregar los suyos.
public struct TemaDeColor: Codable, Sendable, Equatable, Identifiable {
    /// De dónde sale el color al pintar.
    public enum Fuente: String, Codable, Sendable {
        /// El color `hex`, tal cual.
        case fijo
        /// El color de la carátula que suena; `hex` queda de respaldo si no hay carátula.
        case caratula
        /// Solo barra: cada módulo con su propio color (el tema Clásico).
        case porModulo
    }

    public var id: String
    public var nombre: String
    public var hex: UInt32
    public var fuente: Fuente

    public init(id: String, nombre: String, hex: UInt32, fuente: Fuente = .fijo) {
        self.id = id
        self.nombre = nombre
        self.hex = hex & 0xFFFFFF
        self.fuente = fuente
    }

    /// Solo los temas de color fijo dejan elegir el color.
    public var colorEditable: Bool { fuente == .fijo }

    /// `#RRGGBB`.
    public var textoHex: String { Self.texto(de: hex) }

    public static func texto(de hex: UInt32) -> String {
        String(format: "#%06X", hex & 0xFFFFFF)
    }

    /// Lee `#RRGGBB`, `RRGGBB` o `#RGB`. Devuelve `nil` si no es un color.
    public static func hex(desde texto: String) -> UInt32? {
        var limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if limpio.hasPrefix("#") { limpio.removeFirst() }
        if limpio.count == 3 { limpio = limpio.map { "\($0)\($0)" }.joined() }
        guard limpio.count == 6, limpio.allSatisfy(\.isHexDigit) else { return nil }
        return UInt32(limpio, radix: 16)
    }
}

/// Las dos listas de temas, que se manejan por separado.
public enum ListaDeTemas: Sendable, CaseIterable {
    case panel, barra

    public var originales: [TemaDeColor] {
        switch self {
        case .panel:
            TemaDePanel.allCases.map { tema in
                TemaDeColor(
                    id: tema.rawValue,
                    nombre: tema.nombre,
                    hex: tema.hexBase,
                    fuente: tema == .caratula ? .caratula : .fijo
                )
            }
        case .barra:
            TemaDeBarra.allCases.map { tema in
                let fuente: TemaDeColor.Fuente =
                    switch tema {
                    case .clasico: .porModulo
                    case .caratula: .caratula
                    default: .fijo
                    }
                return TemaDeColor(
                    id: tema.rawValue, nombre: tema.nombre, hex: tema.hexAcento ?? 0x5AA9FF, fuente: fuente)
            }
        }
    }

    /// El tema elegido al empezar o al restablecer.
    public var porDefecto: String {
        switch self {
        case .panel: TemaDePanel.obsidiana.rawValue
        case .barra: TemaDeBarra.clasico.rawValue
        }
    }
}
