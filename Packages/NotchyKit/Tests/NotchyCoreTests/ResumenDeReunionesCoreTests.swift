import Foundation
import Testing

@testable import NotchyCore

@Suite("Notas de reunión y exportación Markdown (M5: NOT-1, NOT-2)")
struct ResumenDeReunionesCoreTests {
    @Test
    func normalizaSalidaEstructuradaCompletaDelModelo() {
        let entrada = """
            ## Resumen
            - Se revisó el esquema de la base de datos.
            - Acordamos usar migraciones incrementales.

            ## Decisiones
            - Mantener retención de audio de 30 días.

            ## Tareas
            - [ ] Preparar pruebas de almacenamiento — Darian
            - Documentar exportación a Obsidian
            """
        let normalizada = RedaccionDeResumen.normalizarNotaEstructurada(entrada)
        let esperado = """
            ## Resumen
            - Se revisó el esquema de la base de datos.
            - Acordamos usar migraciones incrementales.

            ## Decisiones
            - Mantener retención de audio de 30 días.

            ## Tareas
            - [ ] Preparar pruebas de almacenamiento — Darian
            - [ ] Documentar exportación a Obsidian
            """
        #expect(normalizada == esperado)
    }

    @Test
    func siElModeloNoRespetaLasSeccionesPoneTodoBajoResumen() {
        let entradaSinEncabezados = """
            - Hablamos de lenguajes regulares y autómatas.
            - El examen parcial es el viernes.
            """
        let normalizada = RedaccionDeResumen.normalizarNotaEstructurada(entradaSinEncabezados)
        let esperado = """
            ## Resumen
            - Hablamos de lenguajes regulares y autómatas.
            - El examen parcial es el viernes.

            ## Decisiones
            - Ninguna

            ## Tareas
            - Ninguna
            """
        #expect(normalizada == esperado)
    }

    @Test
    func seccionesSinDecisionesOTareasDicenNinguna() {
        let entrada = """
            ## Resumen
            - Solo fue una sesión informativa.
            ## Decisiones
            ## Tareas
            - Ninguna
            """
        let normalizada = RedaccionDeResumen.normalizarNotaEstructurada(entrada)
        #expect(normalizada.contains("## Decisiones\n- Ninguna"))
        #expect(normalizada.contains("## Tareas\n- Ninguna"))
    }

    @Test
    func generaSlugSinAcentosNiEnesEnMinusculasConGuiones() {
        let slug = RedaccionDeResumen.slugParaArchivo("Planeación de Otoño: Diseño & Ñandú #5!")
        #expect(slug == "planeacion-de-otono-diseno-nandu-5")
        #expect(RedaccionDeResumen.slugParaArchivo("   ??? ") == "reunion")

        let fecha = Date(timeIntervalSince1970: 1_763_683_200)  // 2025-11-21 00:00:00 UTC
        let nombre = RedaccionDeResumen.nombreArchivoMarkdown(
            titulo: "Revisión de Notchy & Diseño",
            fecha: fecha,
            zonaHoraria: TimeZone(secondsFromGMT: 0)!
        )
        #expect(nombre == "2025-11-21-revision-de-notchy-diseno.md")
    }

    @Test
    func armaMarkdownExportableConFrontmatterValidoYCaracteresEspecialesEscapados() {
        let inicio = Date(timeIntervalSince1970: 1_763_683_200)  // 2025-11-21 00:00:00 UTC
        let reunion = ReunionGrabada(
            id: "reu-export",
            titulo: "Sync: Arquitectura \"v2\" & #Notchy",
            inicio: inicio,
            fin: inicio.addingTimeInterval(35 * 60),
            estado: .finalizada
        )
        let nota = """
            ## Resumen
            - Revisamos el módulo de notas.

            ## Decisiones
            - Exportar compatible con Obsidian.

            ## Tareas
            - [ ] Correr scripts/check — Darian
            """
        let segmentos = [
            SegmentoDeTranscripcion(
                reunionID: "reu-export",
                fuente: .microfono,
                inicioSegundos: 5,
                finSegundos: 9,
                texto: "Empezamos con la revisión."
            ),
            SegmentoDeTranscripcion(
                reunionID: "reu-export",
                fuente: .sistema,
                inicioSegundos: 125,
                finSegundos: 130,
                texto: "De acuerdo con el formato YAML."
            ),
        ]

        let md = RedaccionDeResumen.markdownExportable(
            reunion: reunion,
            notaMarkdown: nota,
            segmentos: segmentos,
            zonaHoraria: TimeZone(secondsFromGMT: 0)!
        )

        #expect(md.hasPrefix("---\n"))
        #expect(md.contains("tipo: reunion\n"))
        #expect(md.contains("titulo: \"Sync: Arquitectura \\\"v2\\\" & #Notchy\"\n"))
        #expect(md.contains("fecha: 2025-11-21\n"))
        #expect(md.contains("duracion_min: 35\n"))
        #expect(md.contains("tags: [reunion]\n---\n"))
        #expect(md.contains("# Sync: Arquitectura \"v2\" & #Notchy\n"))
        #expect(md.contains("## Resumen\n- Revisamos el módulo de notas."))
        #expect(md.contains("## Decisiones\n- Exportar compatible con Obsidian."))
        #expect(md.contains("## Tareas\n- [ ] Correr scripts/check — Darian"))
        #expect(
            md.contains(
                "## Transcripción\n**[00:05]** Empezamos con la revisión.\n**[02:05]** De acuerdo con el formato YAML.")
        )
    }
}
