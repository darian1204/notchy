import Foundation
import NotchyCore
import NotchyPlatform
import Testing

@MainActor
struct AdaptadorDeAirDropTests {
    @Test func distingueArchivosRecibidosPorSharingd() throws {
        let temporal = FileManager.default.temporaryDirectory
            .appending(path: "notchy-airdrop-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporal, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporal) }

        let archivoAirDrop = temporal.appending(path: "IMG_2041.heic")
        let archivoNavegador = temporal.appending(path: "apuntes.pdf")
        try Data("foto".utf8).write(to: archivoAirDrop)
        try Data("pdf".utf8).write(to: archivoNavegador)

        #expect(
            AdaptadorDeAirDrop.escribirAtributoExtend(
                ruta: archivoAirDrop.path,
                nombre: "com.apple.quarantine",
                valor: "0081;6912a100;sharingd;"
            )
        )
        #expect(
            AdaptadorDeAirDrop.escribirAtributoExtend(
                ruta: archivoNavegador.path,
                nombre: "com.apple.quarantine",
                valor: "0083;6912a100;Safari;"
            )
        )

        let adaptador = AdaptadorDeAirDrop(carpetaDescargas: temporal)
        let recibidos = try adaptador.listarRecibidos()
        #expect(recibidos.map(\.nombre) == ["IMG_2041.heic"])
    }
}
