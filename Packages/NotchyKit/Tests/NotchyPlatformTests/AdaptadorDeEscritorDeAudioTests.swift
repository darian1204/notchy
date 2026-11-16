import Foundation
import NotchyCore
import Testing

@testable import NotchyPlatform

@Suite("Adaptador de escritor de audio por trozos (M4)")
@MainActor
struct AdaptadorDeEscritorDeAudioTests {
    @Test
    func escribeYRotaTrozosM4A() throws {
        let carpeta = FileManager.default.temporaryDirectory.appending(
            path: "notchy-audio-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: carpeta) }

        let escritor = AdaptadorDeEscritorDeAudio()
        try escritor.iniciarSesion(
            carpetaBase: carpeta,
            prefijo: "prueba",
            incluirSistema: true,
            duracionTrozoSegundos: 5
        )

        // Si se rota o finaliza sin haber escrito nada del sistema, no debe quedar archivo vacío del sistema.
        let onda = (0..<4_800).map { i in Float(sin(Double(i) * 0.05) * 0.25) }
        try escritor.escribir(
            BloqueDeAudioPCM(
                fuente: .microfono,
                muestras: onda,
                frecuencia: 48_000,
                canales: 1
            )
        )
        try escritor.rotarTrozo()
        try escritor.escribir(
            BloqueDeAudioPCM(
                fuente: .microfono,
                muestras: onda,
                frecuencia: 48_000,
                canales: 1
            )
        )

        let rutas = escritor.finalizarSesion()
        #expect(rutas.rutasMicrofono.count == 2)
        #expect(rutas.rutasSistema.isEmpty)
        for ruta in rutas.rutasMicrofono {
            let atributos = try FileManager.default.attributesOfItem(atPath: ruta)
            let bytes = (atributos[.size] as? NSNumber)?.intValue ?? 0
            #expect(bytes > 0)
        }
    }
}
