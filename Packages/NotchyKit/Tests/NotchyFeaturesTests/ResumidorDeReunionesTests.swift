import Foundation
import NotchyCore
import NotchyStorage
import Testing

@testable import NotchyFeatures

private struct ModeloFalso: PuertoDeResumenDeTexto {
    var listo = true
    func disponible() async -> Bool { listo }
    func resumir(_ texto: String, instrucciones: String) async throws -> String {
        """
        ## Resumen
        - resumen de \(texto.count) caracteres

        ## Decisiones
        - Usar SQLite local

        ## Tareas
        - [ ] Revisar apuntes — Darian
        """
    }
}

private final class AlmacenFalso: AlmacenDeAjustes, @unchecked Sendable {
    var datos: [String: Data] = [:]
    func leer(_ clave: String) -> Data? { datos[clave] }
    func guardar(_ dato: Data?, en clave: String) { datos[clave] = dato }
}

@Suite("Resumen de reuniones en base e inbox (M5)")
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
            id: "r",
            titulo: "Lenguajes y autómatas",
            inicio: inicio,
            fin: inicio.addingTimeInterval(45 * 60),
            estado: .finalizada,
            idioma: .espanolMexico
        )
    }

    @Test
    func guardaSiempreEnLaBaseYMandaAlInboxSoloSiEstaActivo() async throws {
        let repo = RepositorioDeGrabadoraYReuniones(try BaseDeDatos.enMemoria())
        let reu = reunion()
        try repo.guardarReunion(reu)

        var escritoEnInbox: String?
        let ajustesActivos = Ajustes(almacen: AlmacenFalso())
        ajustesActivos.resumirReunionesEnInbox = true

        let resumidorActivo = ResumidorDeReuniones(
            bus: BusDeEventos(),
            modelo: ModeloFalso(),
            ajustes: ajustesActivos,
            repositorio: repo,
            segmentosDe: { _ in segmentos(10) },
            escribirEnInbox: { nota in
                escritoEnInbox = nota
                return true
            }
        )
        let nota = await resumidorActivo.procesar(reu)
        #expect(nota != nil)
        #expect(escritoEnInbox?.hasPrefix("Resumen de reunión: Lenguajes y autómatas (") == true)
        #expect(escritoEnInbox?.contains("45 min)") == true)
        #expect(escritoEnInbox?.contains("## Resumen") == true)
        #expect(escritoEnInbox?.contains("## Decisiones") == true)
        #expect(escritoEnInbox?.contains("## Tareas") == true)

        let guardadaEnBase = try #require(try repo.obtenerNotaDeReunion(reunionID: reu.id))
        #expect(guardadaEnBase.markdown.contains("## Tareas\n- [ ] Revisar apuntes — Darian"))

        // Con el ajuste de inbox apagado, igual guarda en la base pero no escribe al inbox
        try repo.borrarNotaDeReunion(reunionID: reu.id)
        escritoEnInbox = nil
        let ajustesApagados = Ajustes(almacen: AlmacenFalso())
        ajustesApagados.resumirReunionesEnInbox = false

        let resumidorSinInbox = ResumidorDeReuniones(
            bus: BusDeEventos(),
            modelo: ModeloFalso(),
            ajustes: ajustesApagados,
            repositorio: repo,
            segmentosDe: { _ in segmentos(10) },
            escribirEnInbox: { nota in
                escritoEnInbox = nota
                return true
            }
        )
        let soloResumen = await resumidorSinInbox.procesar(reu)
        #expect(soloResumen != nil)
        #expect(escritoEnInbox == nil)
        #expect(try repo.obtenerNotaDeReunion(reunionID: reu.id) != nil)
    }

    @Test
    func noResumeSiEsMuyCortoOSinModelo() async {
        var escrituras = 0
        let escribir: @MainActor (String) -> Bool = { _ in
            escrituras += 1
            return true
        }

        let corto = ResumidorDeReuniones(
            bus: BusDeEventos(), modelo: ModeloFalso(), ajustes: Ajustes(almacen: AlmacenFalso()),
            segmentosDe: { _ in segmentos(1) }, escribirEnInbox: escribir)
        let sinModelo = ResumidorDeReuniones(
            bus: BusDeEventos(), modelo: ModeloFalso(listo: false), ajustes: Ajustes(almacen: AlmacenFalso()),
            segmentosDe: { _ in segmentos(10) }, escribirEnInbox: escribir)

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
    func uneResumenesLargosEnRondasYNormalizaSecciones() async throws {
        let texto = (0..<400).map { "segmento \($0) de una clase larga" }.joined(separator: "\n")
        let resumen = try await RedaccionDeResumen.resumirPorPartes(texto, con: ModeloFalso(), maximo: 500)
        #expect(!resumen.isEmpty)
        #expect(resumen.contains("## Resumen"))
        #expect(resumen.contains("## Decisiones"))
        #expect(resumen.contains("## Tareas"))
    }
}
