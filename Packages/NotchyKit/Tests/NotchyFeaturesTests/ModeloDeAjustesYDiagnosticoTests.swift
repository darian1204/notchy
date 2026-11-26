import Foundation
import NotchyCore
import NotchyStorage
import NotchyTestSupport
import Testing

@testable import NotchyFeatures

@MainActor
@Suite struct ModeloDeAjustesYDiagnosticoTests {
    private let modulos = [
        IdentidadDeModulo(id: "inicio", nombre: "Inicio", icono: "house.fill", color: 0xFFFFFF, lado: .izquierda),
        IdentidadDeModulo(id: "agenda", nombre: "Agenda", icono: "calendar", color: 0x5AA9FF, lado: .izquierda),
        IdentidadDeModulo(id: "musica", nombre: "Música", icono: "music.note", color: 0x3DDC97, lado: .izquierda),
    ]

    @Test func reordenaYActivaModulosEnAjustes() throws {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        let permisos = ProveedorDePermisosFalso()
        let base = try BaseDeDatos.enMemoria()
        let modelo = ModeloDeAjustesYDiagnostico(
            ajustes: ajustes,
            modulosDisponibles: modulos,
            proveedorDePermisos: permisos,
            consultarBase: { ModeloDeAjustesYDiagnostico.diagnosticarBase(base) },
            consultarOpenCode: { .instalado(ruta: "/opt/homebrew/bin/opencode") }
        )

        #expect(modelo.modulosOrdenados.map(\.id) == ["inicio", "agenda", "musica"])
        modelo.moverModuloAbajo("inicio")
        #expect(modelo.modulosOrdenados.map(\.id) == ["agenda", "inicio", "musica"])
        #expect(ajustes.ordenDeModulos == ["agenda", "inicio", "musica"])

        modelo.moverModuloArriba("musica")
        #expect(modelo.modulosOrdenados.map(\.id) == ["agenda", "musica", "inicio"])

        modelo.cambiarModuloActivo("agenda", false)
        #expect(!modelo.estaModuloActivo("agenda"))
        #expect(!ajustes.estaActivo("agenda"))
    }

    @Test func pidePermisosYPublicaEvento() async throws {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        let permisos = ProveedorDePermisosFalso(
            iniciales: [.microfono: .sinPedir, .camara: .denegado],
            alPedir: [.microfono: .concedido]
        )
        let bus = BusDeEventos()
        let flujo = await bus.suscribir(a: CambioDePermiso.self)
        let base = try BaseDeDatos.enMemoria()

        let modelo = ModeloDeAjustesYDiagnostico(
            ajustes: ajustes,
            modulosDisponibles: modulos,
            proveedorDePermisos: permisos,
            consultarBase: { ModeloDeAjustesYDiagnostico.diagnosticarBase(base) },
            consultarOpenCode: { .noEncontrado },
            bus: bus
        )

        #expect(modelo.estado(de: .microfono) == .sinPedir)
        #expect(modelo.estado(de: .camara) == .denegado)
        #expect(modelo.diagnosticoDeBase.estaBien)
        #expect(!modelo.estadoDeOpenCode.estaListo)

        await modelo.pedirPermiso(.microfono)
        #expect(modelo.estado(de: .microfono) == .concedido)
        #expect(permisos.permisosPedidos == [.microfono])

        var iterador = flujo.makeAsyncIterator()
        let evento = await iterador.next()
        #expect(evento == CambioDePermiso(permiso: .microfono, estado: .concedido))
    }

    @Test func diagnosticaBaseAusente() {
        let diagnostico = ModeloDeAjustesYDiagnostico.diagnosticarBase(nil)
        #expect(!diagnostico.estaBien)
        #expect(diagnostico.comoArreglarlo != nil)
    }

    @Test func registraInicioAlAbrirSesionAlArrancarYAlCambiarToggle() throws {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        let servicio = ServicioDeInicioAlAbrirSesionFalso(inicial: .inactivo, alActivar: .requiereAprobacion)
        let base = try BaseDeDatos.enMemoria()

        let modelo = ModeloDeAjustesYDiagnostico(
            ajustes: ajustes,
            modulosDisponibles: modulos,
            proveedorDePermisos: ProveedorDePermisosFalso(),
            servicioDeInicio: servicio,
            consultarBase: { ModeloDeAjustesYDiagnostico.diagnosticarBase(base) },
            consultarOpenCode: { .noEncontrado }
        )

        #expect(servicio.historialAplicado == [true])
        #expect(modelo.estadoDeInicioAlAbrirSesion == .requiereAprobacion)
        #expect(modelo.estadoDeInicioAlAbrirSesion.requiereAprobacionEnSistema)

        modelo.abrirAjustesDeItemsDeInicio()
        #expect(servicio.vecesAbrioAjustes == 1)

        ajustes.iniciarAlAbrirSesion = false
        #expect(servicio.historialAplicado == [true, false])
        #expect(modelo.estadoDeInicioAlAbrirSesion == .inactivo)
    }

    @Test func exportarDiagnosticoIncluyeMetadatosYExcluyeTextoCopiadoYTituloDeReunion() throws {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        ajustes.rutaVaultObsidian = "/Users/darian/Documents/SecretVaultPersonal"
        ajustes.carpetaFotosEspejo = "/Users/darian/Pictures/FotosPrivadas"
        ajustes.temaPanel = "medianoche"

        let base = try BaseDeDatos.enMemoria()
        let repoPortapapeles = RepositorioDePortapapeles(base)
        let repoGrabadora = RepositorioDeGrabadoraYReuniones(base)

        let textoCopiadoSecreto = "CLAVE_SECRETA_PORTAPAPELES_987654"
        let tituloReunionSecreto = "Reunión confidencial con comité directivo"
        let transcripcionSecreta = "Transcripción privada que nunca debe exportarse"

        _ = try repoPortapapeles.registrar(
            ElementoDePortapapeles(
                id: "clip-1",
                tipo: .texto,
                texto: textoCopiadoSecreto,
                rutaArchivo: "/Users/darian/Desktop/documento-privado.pdf",
                huella: "huella-1",
                appOrigen: "Notas",
                bytes: 34
            )
        )
        try repoGrabadora.guardarReunion(
            ReunionGrabada(
                id: "reu-1",
                titulo: tituloReunionSecreto,
                inicio: .now,
                estado: .finalizada,
                rutasAudioMicrofono: ["/Users/darian/Audio/reu-1.m4a"]
            )
        )
        try repoGrabadora.guardarSegmento(
            SegmentoDeTranscripcion(
                id: "seg-1",
                reunionID: "reu-1",
                fuente: .microfono,
                inicioSegundos: 0,
                finSegundos: 5,
                texto: transcripcionSecreta
            )
        )

        let permisos = ProveedorDePermisosFalso(iniciales: [.microfono: .concedido, .camara: .denegado])
        let modelo = ModeloDeAjustesYDiagnostico(
            ajustes: ajustes,
            modulosDisponibles: modulos,
            proveedorDePermisos: permisos,
            consultarBase: { ModeloDeAjustesYDiagnostico.diagnosticarBase(base) },
            consultarOpenCode: { .instalado(ruta: "/Users/darian/.local/bin/opencode") },
            consultarModulos: {
                [
                    DiagnosticoDeModulo(
                        id: "grabadora",
                        nombre: "Grabadora",
                        activo: true,
                        salud: .error("Fallo en /Users/darian/Audio/secreto.m4a")
                    )
                ]
            },
            consultarConteos: {
                ConteosDeDiagnostico(
                    portapapeles: (try? repoPortapapeles.total()) ?? 0,
                    bandeja: 2,
                    reuniones: (try? repoGrabadora.listarReuniones().count) ?? 0,
                    notasDeVoz: 0
                )
            }
        )

        let entorno = EntornoDeDiagnostico(
            versionApp: "0.1.0",
            buildApp: "1",
            versionMacOS: "27.0.0",
            modeloMac: "Mac16,1",
            arquitectura: "arm64"
        )
        let reporte = modelo.construirReporteDeDiagnostico(entorno: entorno)

        #expect(reporte.contains("\"versionApp\" : \"0.1.0\""))
        #expect(reporte.contains("\"versionMacOS\" : \"27.0.0\""))
        #expect(reporte.contains("\"arquitectura\" : \"arm64\""))
        #expect(reporte.contains("\"temaPanel\" : \"medianoche\""))
        #expect(reporte.contains("\"portapapeles\" : 1"))
        #expect(reporte.contains("\"reuniones\" : 1"))

        #expect(!reporte.contains(textoCopiadoSecreto))
        #expect(!reporte.contains(tituloReunionSecreto))
        #expect(!reporte.contains(transcripcionSecreta))
        #expect(!reporte.contains("SecretVaultPersonal"))
        #expect(!reporte.contains("FotosPrivadas"))
        #expect(!reporte.contains("documento-privado.pdf"))
        #expect(!reporte.contains("/Users/darian"))
    }
}
