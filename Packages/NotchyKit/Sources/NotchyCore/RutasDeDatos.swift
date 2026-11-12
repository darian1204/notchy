import Foundation

/// Dónde guarda Notchy sus archivos. Todo cuelga de una sola carpeta para poder borrarlo todo.
public struct RutasDeDatos: Sendable, Equatable {
    public let raiz: URL

    public init(raiz: URL) {
        self.raiz = raiz
    }

    /// `~/Library/Application Support/Notchy`, o `Notchy-Dev` en depuración.
    public static func porDefecto(_ compilacion: NotchyInfo.Compilacion = NotchyInfo.compilacionActual) throws
        -> RutasDeDatos
    {
        let soporte = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return RutasDeDatos(
            raiz: soporte.appending(path: NotchyInfo.carpetaDeDatos(compilacion), directoryHint: .isDirectory))
    }

    public var baseDeDatos: URL { raiz.appending(path: "notchy.sqlite") }

    public func crearCarpetas() throws {
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
    }
}
