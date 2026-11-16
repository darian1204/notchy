import Foundation
import NotchyCore
import Testing

@testable import NotchyStorage

@Suite struct GrabadoraYReunionesStorageTests {
    @Test func guardaYBuscaSegmentosDeReunionSinAcentos() throws {
        let repo = RepositorioDeGrabadoraYReuniones(try BaseDeDatos.enMemoria())
        let reunion = ReunionGrabada(
            id: "r1",
            titulo: "Planeación semanal",
            inicio: Date(timeIntervalSince1970: 1_700_000_000),
            estado: .enCurso,
            idioma: .espanolMexico,
            rutasAudioMicrofono: ["/tmp/r1-mic-001.m4a"],
            rutasAudioSistema: ["/tmp/r1-sis-001.m4a"]
        )
        try repo.guardarReunion(reunion)

        let seg1 = SegmentoDeTranscripcion(
            id: "s1",
            reunionID: "r1",
            fuente: .sistema,
            inicioSegundos: 2,
            finSegundos: 6,
            texto: "La migración técnica queda para el miércoles."
        )
        let seg2 = SegmentoDeTranscripcion(
            id: "s2",
            reunionID: "r1",
            fuente: .microfono,
            inicioSegundos: 7,
            finSegundos: 11,
            texto: "Yo reviso la configuración en Supabase."
        )
        try repo.guardarSegmento(seg1)
        try repo.guardarSegmento(seg2)

        let todos = try repo.listarSegmentos(reunionID: "r1")
        #expect(todos.map(\.id) == ["s1", "s2"])

        let hallados = try repo.buscarSegmentos(consulta: "migracion miercoles")
        #expect(hallados.map(\.id) == ["s1"])
    }

    @Test func recuperaReunionesAbiertasTrasCaidaYConservaSegmentos() throws {
        let repo = RepositorioDeGrabadoraYReuniones(try BaseDeDatos.enMemoria())
        let inicio = Date(timeIntervalSince1970: 1_700_000_000)
        try repo.guardarReunion(
            ReunionGrabada(
                id: "caida",
                titulo: "Llamada cortada",
                inicio: inicio,
                estado: .enCurso
            )
        )
        try repo.guardarSegmento(
            SegmentoDeTranscripcion(
                id: "seg-ultimo",
                reunionID: "caida",
                fuente: .microfono,
                inicioSegundos: 120,
                finSegundos: 185,
                texto: "Seguimos viendo el punto tres."
            )
        )

        let recuperadas = try repo.recuperarReunionesIncompletas(
            en: inicio.addingTimeInterval(500)
        )
        #expect(recuperadas.count == 1)
        #expect(recuperadas.first?.estado == .recuperada)
        #expect(recuperadas.first?.fin == inicio.addingTimeInterval(185))
        #expect(try repo.listarSegmentos(reunionID: "caida").count == 1)
    }

    @Test func aplicaRetencionDeAudioDe30DiasSinBorrarLaTranscripcion() throws {
        let repo = RepositorioDeGrabadoraYReuniones(try BaseDeDatos.enMemoria())
        let ahora = Date(timeIntervalSince1970: 1_800_000_000)
        let hace35Dias = ahora.addingTimeInterval(-35 * 86_400)
        let hace5Dias = ahora.addingTimeInterval(-5 * 86_400)

        try repo.guardarReunion(
            ReunionGrabada(
                id: "vieja",
                titulo: "Reunión vieja",
                inicio: hace35Dias,
                fin: hace35Dias.addingTimeInterval(600),
                estado: .finalizada,
                rutasAudioMicrofono: ["/tmp/vieja-mic.m4a"],
                rutasAudioSistema: ["/tmp/vieja-sis.m4a"]
            )
        )
        try repo.guardarSegmento(
            SegmentoDeTranscripcion(
                id: "seg-vieja",
                reunionID: "vieja",
                fuente: .microfono,
                inicioSegundos: 1,
                finSegundos: 4,
                texto: "Texto que se conserva siempre"
            )
        )
        try repo.guardarReunion(
            ReunionGrabada(
                id: "reciente",
                titulo: "Reunión reciente",
                inicio: hace5Dias,
                fin: hace5Dias.addingTimeInterval(600),
                estado: .finalizada,
                rutasAudioMicrofono: ["/tmp/reciente-mic.m4a"]
            )
        )

        let rutasBorradas = try repo.aplicarRetencionDeAudio(dias: 30, ahora: ahora)
        #expect(Set(rutasBorradas) == Set(["/tmp/vieja-mic.m4a", "/tmp/vieja-sis.m4a"]))

        let viejaActualizada = try #require(try repo.obtenerReunion(id: "vieja"))
        #expect(viejaActualizada.rutasAudioMicrofono.isEmpty)
        #expect(viejaActualizada.rutasAudioSistema.isEmpty)
        #expect(try repo.listarSegmentos(reunionID: "vieja").count == 1)

        let recienteActualizada = try #require(try repo.obtenerReunion(id: "reciente"))
        #expect(recienteActualizada.rutasAudioMicrofono == ["/tmp/reciente-mic.m4a"])
    }

    @Test func guardaYBorraNotasDeVozYReemplazaSegmentosAlRetranscribir() throws {
        let repo = RepositorioDeGrabadoraYReuniones(try BaseDeDatos.enMemoria())
        let nota = NotaDeVoz(
            id: "n1",
            creado: Date(timeIntervalSince1970: 1_700_000_100),
            titulo: "Idea rápida",
            duracionSegundos: 14,
            rutaArchivo: "/tmp/nota1.m4a",
            transcripcion: "Probar el glosario de Supabase"
        )
        try repo.guardarNotaDeVoz(nota)
        #expect(try repo.listarNotasDeVoz().count == 1)
        let borrada = try repo.borrarNotaDeVoz(id: "n1")
        #expect(borrada?.rutaArchivo == "/tmp/nota1.m4a")
        #expect(try repo.listarNotasDeVoz().isEmpty)
    }
}
