import Foundation
import Testing

@testable import NotchyCore

@Suite struct RutasDeDatosTests {
    @Test func laDepuracionNoTocaLosDatosReales() throws {
        let depuracion = try RutasDeDatos.porDefecto(.depuracion)
        let real = try RutasDeDatos.porDefecto(.publicacion)
        #expect(depuracion.raiz.lastPathComponent == "Notchy-Dev")
        #expect(real.raiz.lastPathComponent == "Notchy")
        #expect(depuracion.baseDeDatos.lastPathComponent == "notchy.sqlite")
    }

    @Test func creaSuCarpeta() throws {
        let raiz = FileManager.default.temporaryDirectory.appending(path: "notchy-pruebas-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: raiz) }
        try RutasDeDatos(raiz: raiz).crearCarpetas()
        #expect(FileManager.default.fileExists(atPath: raiz.path))
    }
}
