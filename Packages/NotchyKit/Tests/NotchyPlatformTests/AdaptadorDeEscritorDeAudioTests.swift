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

        let urls = rutas.rutasMicrofono.map { URL(fileURLWithPath: $0) }
        let muestras16k = try AdaptadorDeDiarizacion.concatenarYConvertirA16kMono(archivos: urls)
        #expect(muestras16k.count >= 2_500)
    }

    @Test(
        .enabled(if: ProcessInfo.processInfo.environment["NOTCHY_TEST_DIARIZACION_REAL"] == "1")
    )
    func diarizaReunionRealDeNotchyDev() async throws {
        let soporte = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let carpetaAudio = soporte.appending(path: "Notchy-Dev/audio", directoryHint: .isDirectory)
        let carpetaModelos = soporte.appending(path: "Notchy-Dev/models", directoryHint: .isDirectory)
        let idReunion = "D5081E46-BA82-4A57-A3B1-DAA2C4749411"
        let urls = (1...9)
            .map { indice in
                carpetaAudio.appending(
                    path: String(format: "reunion-%@-mic-%03d.m4a", idReunion, indice)
                )
            }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        #expect(!urls.isEmpty)

        let adaptador = AdaptadorDeDiarizacion(carpetaModelos: carpetaModelos)
        let tramos = try await adaptador.diarizar(archivos: urls)
        let hablantesUnicos = Set(tramos.map(\.hablanteID))
        print(
            "DIARIZACION_REAL: archivos=\(urls.count) hablantes=\(hablantesUnicos.count) (\(hablantesUnicos.sorted().joined(separator: ", "))) tramos=\(tramos.count)"
        )
        #expect(!tramos.isEmpty)
    }
}
