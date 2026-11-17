import Foundation
import NotchyCore
import Testing

@testable import NotchyFeatures

private struct ModeloFalso: PuertoDeResumenDeTexto {
    var listo = true
    func disponible() async -> Bool { listo }
    func resumir(_ texto: String, instrucciones: String) async throws -> String {
        "- resumen de \(texto.count) caracteres"
    }
}

private final class AlmacenFalso: AlmacenDeAjustes, @unchecked Sendable {
    var datos: [String: Data] = [:]
    func leer(_ clave: String) -> Data? { datos[clave] }
    func guardar(_ dato: Data?, en clave: String) { datos[clave] = dato }
}

@Suite("Resumen de reuniones al inbox")
@MainActor
struct ResumidorDeReunionesTests {
    private func segmentos(_ n: Int) -> [SegmentoDeTranscripcion] {
        (0..<n).map { i in
            SegmentoDeTranscripcion(
                reunionID: "r",
                fuente: i.isMultiple(of: 2) ? .microfono : .sistema,
                inicioSegundos: Double(i * 10),
                finSegundos: Double(i * 10 + 5),
                texto: "Hoy vimos el tema número \(i) de autómatas de pila y su relación con gramáticas."
            )
        }
    }

    private func reunion() -> ReunionGrabada {
        let inicio = Date(timeIntervalSince1970: 1_800_000_000)
        return ReunionGrabada(
            titulo: "Lenguajes y autómatas",
            inicio: inicio,
            fin: inicio.addingTimeInterval(45 * 60),
            idioma: .espanolMexico
        )
    }

    @Test
    func escribeElResumenEnElInbox() async {
        var escrito: String?
        let resumidor = ResumidorDeReuniones(
            bus: BusDeEventos(),
            modelo: ModeloFalso(),
            ajustes: Ajustes(almacen: AlmacenFalso()),
            segmentosDe: { _ in segmentos(10) },
            escribirEnInbox: { nota in
                escrito = nota
                return true
            }
        )
        let nota = await resumidor.procesar(reunion())
        #expect(nota != nil)
        #expect(escrito?.hasPrefix("Resumen de reunión: Lenguajes y autómatas (") == true)
        #expect(escrito?.contains("45 min)") == true)
        #expect(escrito?.contains("- resumen de") == true)
    }

    @Test
    func noResumeSiEstaApagadoOEsMuyCortoOSinModelo() async {
        let ajustesApagados = Ajustes(almacen: AlmacenFalso())
        ajustesApagados.resumirReunionesEnInbox = false
        var escrituras = 0
        let escribir: @MainActor (String) -> Bool = { _ in
            escrituras += 1
            return true
        }

        let apagado = ResumidorDeReuniones(
            bus: BusDeEventos(), modelo: ModeloFalso(), ajustes: ajustesApagados,
            segmentosDe: { _ in segmentos(10) }, escribirEnInbox: escribir)
        let corto = ResumidorDeReuniones(
            bus: BusDeEventos(), modelo: ModeloFalso(), ajustes: Ajustes(almacen: AlmacenFalso()),
            segmentosDe: { _ in segmentos(1) }, escribirEnInbox: escribir)
        let sinModelo = ResumidorDeReuniones(
            bus: BusDeEventos(), modelo: ModeloFalso(listo: false), ajustes: Ajustes(almacen: AlmacenFalso()),
            segmentosDe: { _ in segmentos(10) }, escribirEnInbox: escribir)

        #expect(await apagado.procesar(reunion()) == nil)
        #expect(await corto.procesar(reunion()) == nil)
        #expect(await sinModelo.procesar(reunion()) == nil)
        #expect(escrituras == 0)
    }

    @Test
    func partePorLineasSinPasarseDelMaximo() {
        let texto = (0..<50).map { "línea \($0) con algo de texto" }.joined(separator: "\n")
        let partes = RedaccionDeResumen.trozos(de: texto, maximo: 100)
        #expect(partes.count > 1)
        #expect(partes.allSatisfy { $0.count <= 100 })
        #expect(partes.joined(separator: "\n") == texto)
    }

    @Test
    func cortaUnaLineaMasLargaQueElMaximo() {
        let partes = RedaccionDeResumen.trozos(de: String(repeating: "a", count: 250), maximo: 100)
        #expect(partes.map(\.count) == [100, 100, 50])
    }

    @Test
    func uneResumenesLargosEnRondas() async throws {
        let texto = (0..<400).map { "segmento \($0) de una clase larga" }.joined(separator: "\n")
        let resumen = try await RedaccionDeResumen.resumirPorPartes(texto, con: ModeloFalso(), maximo: 500)
        #expect(!resumen.isEmpty)
        #expect(resumen.count <= 500)
    }
}
