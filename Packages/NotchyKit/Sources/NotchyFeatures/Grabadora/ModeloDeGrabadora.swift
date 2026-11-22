import AppKit
import Foundation
import NotchyCore
import NotchyStorage
import OSLog
import Observation

/// Modos de grabación activa dentro del módulo Grabadora.
public enum ModoDeGrabacionActiva: String, Sendable, Equatable {
    case ninguno
    case reunion
    case notaDeVoz
}

/// Pestañas visibles en la vista expandida de Grabadora.
public enum PestanaDeGrabadora: String, CaseIterable, Sendable, Equatable {
    case reunion = "Reunión"
    case notasDeVoz = "Notas de voz"
    case historial = "Historial"
    case glosario = "Glosario"
}

/// Secciones del detalle de una reunión en la pestaña Historial (GRB-4, NOT-1, NOT-2).
public enum SeccionDetalleDeReunion: String, CaseIterable, Sendable, Equatable {
    case transcripcion = "Transcripción"
    case notas = "Notas"
}

/// Modelo observable de Grabadora y Reuniones con transcripción en vivo, guardado incremental por trozos,
/// recuperación tras caída, glosario y retención de audio de 30 días (GRB-1 a GRB-8, D-25, RNF-4).
@MainActor
@Observable
public final class ModeloDeGrabadora {
    public var pestanaSeleccionada: PestanaDeGrabadora = .reunion
    public var tituloReunion = ""
    public var idiomaSeleccionado: IdiomaDeTranscripcion
    public private(set) var permisoMicrofono: EstadoDePermiso = .sinPedir
    public private(set) var modoActivo: ModoDeGrabacionActiva = .ninguno
    public private(set) var pausada = false
    public private(set) var segundosTranscurridos = 0
    public private(set) var nivelMicrofono: Double = 0
    public private(set) var nivelSistema: Double = 0
    public private(set) var nivelesOnda: [Double] = [0.18, 0.25, 0.2, 0.3]
    public private(set) var estadisticasCaptura = EstadisticasDeCapturaDeAudio()
    public private(set) var avisoDeFuente: String?
    public private(set) var mensajeDeError: String?
    /// `true` unos segundos después de copiar una transcripción, para confirmar en el botón.
    public private(set) var transcripcionCopiada = false
    private var tareaAvisoCopiado: Task<Void, Never>?

    public private(set) var reunionActual: ReunionGrabada?
    public private(set) var ensamblador: EnsambladorDeSegmentos?
    public private(set) var textoNotaEnVivo = ""

    public private(set) var notasDeVoz: [NotaDeVoz] = []
    public private(set) var reunionesGuardadas: [ReunionGrabada] = []
    public private(set) var idsDeReunionesConNota: Set<String> = []
    public private(set) var segmentosDeReunionSeleccionada: [SegmentoDeTranscripcion] = []
    public private(set) var nombresHablantesDeReunionSeleccionada: [String: String] = [:]
    public private(set) var notaDeReunionSeleccionada: NotaDeReunion?
    public var seccionDetalleHistorial: SeccionDetalleDeReunion = .transcripcion
    public private(set) var resumiendo = false
    public private(set) var diarizando = false
    public private(set) var estadoDiarizacion: String?
    public private(set) var errorDeResumen: String?
    public private(set) var notaCopiada = false
    private var tareaAvisoNotaCopiada: Task<Void, Never>?
    public var reunionSeleccionadaID: String? {
        didSet {
            errorDeResumen = nil
            cargarSegmentosDeSeleccionada()
        }
    }
    public var consultaBusqueda = "" {
        didSet { actualizarBusqueda() }
    }
    public private(set) var resultadosBusqueda: [SegmentoDeTranscripcion] = []
    public private(set) var glosario: [EntradaDeGlosario] = EntradaDeGlosario.porDefecto
    public private(set) var retranscribiendo = false

    @ObservationIgnored private let captura: any PuertoDeCapturaDeAudio
    @ObservationIgnored private let escritor: any PuertoDeEscritorDeAudio
    @ObservationIgnored private let transcripcion: any PuertoDeTranscripcion
    @ObservationIgnored private let diarizacion: (any PuertoDeDiarizacion)?
    @ObservationIgnored private let resumenDeTexto: (any PuertoDeResumenDeTexto)?
    @ObservationIgnored private let escribirEnInbox: (@MainActor (String) -> Bool)?
    @ObservationIgnored private let repositorio: RepositorioDeGrabadoraYReuniones?
    @ObservationIgnored private let carpetaAudio: URL
    @ObservationIgnored private let ajustes: Ajustes
    @ObservationIgnored private let bus: BusDeEventos?
    @ObservationIgnored private let alAbrirURL: (@MainActor (URL) -> Void)?
    @ObservationIgnored private let duracionTrozoSegundos: Double
    @ObservationIgnored private let log = Registro.de(.grabadora)

    @ObservationIgnored private var tareaReloj: Task<Void, Never>?
    @ObservationIgnored private var tareaAvisoAgenda: Task<Void, Never>?
    @ObservationIgnored private var inicioTramoActual: Date?
    @ObservationIgnored private var acumuladoAntesDePausa: Double = 0

    public init(
        captura: any PuertoDeCapturaDeAudio,
        escritor: any PuertoDeEscritorDeAudio,
        transcripcion: any PuertoDeTranscripcion,
        diarizacion: (any PuertoDeDiarizacion)? = nil,
        resumenDeTexto: (any PuertoDeResumenDeTexto)? = nil,
        escribirEnInbox: (@MainActor (String) -> Bool)? = nil,
        repositorio: RepositorioDeGrabadoraYReuniones? = nil,
        carpetaAudio: URL? = nil,
        ajustes: Ajustes? = nil,
        bus: BusDeEventos? = nil,
        duracionTrozoSegundos: Double = 60,
        alAbrirURL: (@MainActor (URL) -> Void)? = nil
    ) {
        self.captura = captura
        self.escritor = escritor
        self.transcripcion = transcripcion
        self.diarizacion = diarizacion
        self.resumenDeTexto = resumenDeTexto
        self.escribirEnInbox = escribirEnInbox
        self.repositorio = repositorio
        self.carpetaAudio =
            carpetaAudio
            ?? FileManager.default.temporaryDirectory.appending(path: "notchy-audio", directoryHint: .isDirectory)
        let ajustesResueltos = ajustes ?? Ajustes(almacen: AlmacenEnMemoriaGrabadora())
        self.ajustes = ajustesResueltos
        self.bus = bus
        self.duracionTrozoSegundos = duracionTrozoSegundos
        self.alAbrirURL = alAbrirURL
        self.idiomaSeleccionado = ajustesResueltos.idiomaTranscripcionPorDefecto
        self.permisoMicrofono = captura.estadoDePermisoMicrofono()
    }

    public var grabando: Bool {
        modoActivo != .ninguno
    }

    public var cronometroFormateado: String {
        String(format: "%02d:%02d", segundosTranscurridos / 60, segundosTranscurridos % 60)
    }

    public var segmentosEnVivo: [SegmentoDeTranscripcion] {
        ensamblador?.segmentosEnVivo ?? []
    }

    public var salud: SaludDeModulo {
        if permisoMicrofono == .denegado || permisoMicrofono == .restringido {
            return .faltaPermiso(PermisoDelSistema.microfono.nombre)
        }
        if let mensajeDeError {
            return .error(mensajeDeError)
        }
        return .listo
    }

    // MARK: - Ciclo de vida

    public func iniciar() {
        permisoMicrofono = captura.estadoDePermisoMicrofono()
        try? FileManager.default.createDirectory(at: carpetaAudio, withIntermediateDirectories: true)
        recuperarYLimpiarAlArrancar()
        recargarDatos()
        suscribirAvisosDeAgenda()
    }

    public func detener() {
        tareaAvisoAgenda?.cancel()
        tareaAvisoAgenda = nil
        if grabando {
            Task { await detenerGrabacion() }
        }
    }

    public func recargarDatos() {
        guard let repositorio else { return }
        do {
            notasDeVoz = try repositorio.listarNotasDeVoz()
            reunionesGuardadas = try repositorio.listarReuniones()
            idsDeReunionesConNota = (try? repositorio.idsDeReunionesConNota()) ?? []
            let entradas = try repositorio.listarGlosario()
            if !entradas.isEmpty {
                glosario = entradas
            }
            if reunionSeleccionadaID == nil {
                reunionSeleccionadaID = reunionesGuardadas.first?.id
            } else {
                cargarSegmentosDeSeleccionada()
            }
        } catch {
            log.error("No se pudieron cargar las grabaciones: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func tieneNotaGuardada(_ reunionID: String) -> Bool {
        idsDeReunionesConNota.contains(reunionID)
    }

    public func nombreVisibleDeHablante(para segmento: SegmentoDeTranscripcion) -> String {
        segmento.etiquetaDeHablante(nombres: nombresHablantesDeReunionSeleccionada)
    }

    // MARK: - Reuniones con transcripción en vivo (GRB-2 a GRB-8)

    public func iniciarReunion(
        tituloPersonalizado: String? = nil,
        eventoCalendarioID: String? = nil,
        ahora: Date = .now
    ) async {
        guard await asegurarPermisoMicrofono() else { return }
        if grabando {
            await detenerGrabacion(ahora: ahora)
        }

        let id = UUID().uuidString
        let tituloFinal = resolverTituloReunion(tituloPersonalizado, fecha: ahora)
        let guardarAudio = ajustes.guardarAudioReuniones
        let prefijo = "reunion-\(id)"

        do {
            if guardarAudio {
                try escritor.iniciarSesion(
                    carpetaBase: carpetaAudio,
                    prefijo: prefijo,
                    incluirSistema: true,
                    duracionTrozoSegundos: duracionTrozoSegundos
                )
            }

            let nuevaReunion = ReunionGrabada(
                id: id,
                titulo: tituloFinal,
                inicio: ahora,
                estado: .enCurso,
                idioma: idiomaSeleccionado,
                eventoCalendarioID: eventoCalendarioID
            )
            reunionActual = nuevaReunion
            ensamblador = EnsambladorDeSegmentos(
                reunionID: id,
                corrector: CorrectorDeGlosario(entradas: glosario)
            )
            try repositorio?.guardarReunion(nuevaReunion)

            try await transcripcion.iniciar(
                idioma: idiomaSeleccionado,
                incluirSistema: true
            ) { [weak self] resultado in
                Task { @MainActor [weak self] in
                    self?.procesarResultadoDeTranscripcion(resultado)
                }
            }

            try await captura.iniciarCaptura(
                incluirSistema: true,
                preferirMicrofonoInterno: ajustes.preferirMicrofonoInternoConBluetooth,
                alRecibirBloque: { [weak self] bloque in
                    Task { @MainActor [weak self] in
                        self?.procesarBloqueDeAudio(bloque)
                    }
                },
                alCambiarEntorno: { [weak self] evento in
                    Task { @MainActor [weak self] in
                        await self?.manejarEventoDeEntorno(evento)
                    }
                }
            )

            modoActivo = .reunion
            pausada = false
            segundosTranscurridos = 0
            acumuladoAntesDePausa = 0
            inicioTramoActual = ahora
            avisoDeFuente = nil
            mensajeDeError = nil
            estadisticasCaptura = captura.estadisticas
            arrancarReloj()
            await publicarEstadoDeGrabacion()
        } catch {
            _ = escritor.finalizarSesion()
            await transcripcion.detener()
            await captura.detenerCaptura()
            reunionActual = nil
            ensamblador = nil
            modoActivo = .ninguno
            mensajeDeError = error.localizedDescription
            log.error("No se pudo iniciar la reunión: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Notas de voz (GRB-1)

    public func iniciarNotaDeVoz(ahora: Date = .now) async {
        guard await asegurarPermisoMicrofono() else { return }
        if grabando {
            await detenerGrabacion(ahora: ahora)
        }

        let id = UUID().uuidString
        let prefijo = "nota-\(id)"
        textoNotaEnVivo = ""

        do {
            try escritor.iniciarSesion(
                carpetaBase: carpetaAudio,
                prefijo: prefijo,
                incluirSistema: false,
                duracionTrozoSegundos: max(300, duracionTrozoSegundos)
            )

            try? await transcripcion.iniciar(
                idioma: idiomaSeleccionado,
                incluirSistema: false
            ) { [weak self] resultado in
                Task { @MainActor [weak self] in
                    guard let self, self.modoActivo == .notaDeVoz else { return }
                    let corregido = CorrectorDeGlosario(entradas: self.glosario).corregir(resultado.texto)
                    if !corregido.isEmpty {
                        self.textoNotaEnVivo = corregido
                    }
                }
            }

            try await captura.iniciarCaptura(
                incluirSistema: false,
                preferirMicrofonoInterno: ajustes.preferirMicrofonoInternoConBluetooth,
                alRecibirBloque: { [weak self] bloque in
                    Task { @MainActor [weak self] in
                        self?.procesarBloqueDeAudio(bloque)
                    }
                },
                alCambiarEntorno: { [weak self] evento in
                    Task { @MainActor [weak self] in
                        await self?.manejarEventoDeEntorno(evento)
                    }
                }
            )

            modoActivo = .notaDeVoz
            pausada = false
            segundosTranscurridos = 0
            acumuladoAntesDePausa = 0
            inicioTramoActual = ahora
            avisoDeFuente = nil
            mensajeDeError = nil
            estadisticasCaptura = captura.estadisticas
            arrancarReloj()
            await publicarEstadoDeGrabacion()
        } catch {
            _ = escritor.finalizarSesion()
            await transcripcion.detener()
            await captura.detenerCaptura()
            modoActivo = .ninguno
            mensajeDeError = error.localizedDescription
            log.error("No se pudo iniciar la nota de voz: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func alternarPausa(ahora: Date = .now) {
        guard grabando else { return }
        if pausada {
            pausada = false
            inicioTramoActual = ahora
            if var reunion = reunionActual {
                reunion.estado = .enCurso
                reunionActual = reunion
                try? repositorio?.guardarReunion(reunion)
            }
        } else {
            actualizarSegundos(ahora: ahora)
            acumuladoAntesDePausa = Double(segundosTranscurridos)
            inicioTramoActual = nil
            pausada = true
            nivelMicrofono = 0
            nivelSistema = 0
            if var reunion = reunionActual {
                reunion.estado = .pausada
                reunionActual = reunion
                try? repositorio?.guardarReunion(reunion)
            }
        }
        Task { await publicarEstadoDeGrabacion() }
    }

    /// Texto plano de una transcripción: `[mm:ss] Tú: …` (o el nombre del hablante), una línea por segmento, con título opcional.
    public nonisolated static func textoDeTranscripcion(
        _ segmentos: [SegmentoDeTranscripcion],
        titulo: String? = nil,
        nombresHablantes: [String: String] = [:]
    ) -> String {
        var lineas: [String] = []
        if let titulo = titulo?.trimmingCharacters(in: .whitespacesAndNewlines), !titulo.isEmpty {
            lineas.append(titulo)
            lineas.append("")
        }
        for seg in segmentos {
            let texto = seg.texto.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !texto.isEmpty else { continue }
            let etiqueta = seg.etiquetaDeHablante(nombres: nombresHablantes)
            lineas.append("[\(seg.marcaDeTiempoFormateada)] \(etiqueta): \(texto)")
        }
        return lineas.joined(separator: "\n")
    }

    /// Copia la transcripción al portapapeles del sistema y marca `transcripcionCopiada` por 1.5 s.
    public func copiarTranscripcion(_ segmentos: [SegmentoDeTranscripcion], titulo: String? = nil) {
        let texto = Self.textoDeTranscripcion(
            segmentos,
            titulo: titulo,
            nombresHablantes: nombresHablantesDeReunionSeleccionada
        )
        guard !texto.isEmpty else { return }
        let pasta = NSPasteboard.general
        pasta.clearContents()
        pasta.setString(texto, forType: .string)
        transcripcionCopiada = true
        tareaAvisoCopiado?.cancel()
        tareaAvisoCopiado = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            self?.transcripcionCopiada = false
        }
    }

    /// Inserta una marca de tiempo en la transcripción de la reunión activa (GRB-8).
    @discardableResult
    public func agregarMarcaEnReunion(etiqueta: String = "Marca importante") -> SegmentoDeTranscripcion? {
        guard modoActivo == .reunion, var ens = ensamblador else { return nil }
        let marca = ens.agregarMarca(etiqueta: etiqueta, enSegundos: Double(segundosTranscurridos))
        ensamblador = ens
        try? repositorio?.guardarSegmento(marca)
        if let bus {
            Task { await bus.publicar(SegmentoDeTranscripcionRecibido(segmento: marca)) }
        }
        return marca
    }

    /// Cambia el idioma de transcripción en vivo entre `es-MX` y `en-US` (GRB-3, S4).
    public func cambiarIdioma(_ nuevo: IdiomaDeTranscripcion) async {
        guard nuevo != idiomaSeleccionado else { return }
        idiomaSeleccionado = nuevo
        ajustes.idiomaTranscripcionPorDefecto = nuevo
        guard grabando else { return }
        if var ens = ensamblador {
            for seg in ens.consolidarProvisionales(enSegundos: Double(segundosTranscurridos)) {
                try? repositorio?.guardarSegmento(seg)
            }
            ensamblador = ens
        }
        if var reunion = reunionActual {
            reunion.idioma = nuevo
            reunionActual = reunion
            try? repositorio?.guardarReunion(reunion)
        }
        do {
            try await transcripcion.cambiarIdioma(nuevo)
        } catch {
            avisoDeFuente = "No se pudo cambiar el idioma: \(error.localizedDescription)"
        }
    }

    public func detenerGrabacion(ahora: Date = .now) async {
        guard grabando else { return }
        actualizarSegundos(ahora: ahora)
        let modo = modoActivo
        let duracion = max(1, Double(segundosTranscurridos))

        tareaReloj?.cancel()
        tareaReloj = nil
        inicioTramoActual = nil
        acumuladoAntesDePausa = 0

        await captura.detenerCaptura()
        await transcripcion.detener()
        let rutas = escritor.finalizarSesion()

        switch modo {
        case .reunion:
            if var ens = ensamblador {
                for pendiente in ens.consolidarProvisionales(enSegundos: duracion) {
                    try? repositorio?.guardarSegmento(pendiente)
                }
                ensamblador = ens
            }
            if var reunion = reunionActual {
                reunion.fin = ahora
                reunion.estado = .finalizada
                reunion.rutasAudioMicrofono = rutas.rutasMicrofono
                reunion.rutasAudioSistema = rutas.rutasSistema
                reunion.desfaseInicialMs = estadisticasCaptura.desfaseInicialMs
                reunionActual = nil
                try? repositorio?.guardarReunion(reunion)
                if ajustes.separarVocesEnReuniones {
                    await ejecutarDiarizacionAutomatica(para: reunion)
                }
                reunionSeleccionadaID = reunion.id
                if let bus {
                    await bus.publicar(ReunionTerminada(reunion: reunion))
                }
            }
            ensamblador = nil

        case .notaDeVoz:
            if let primeraRuta = rutas.rutasMicrofono.first {
                let formateador = DateFormatter()
                formateador.locale = Locale(identifier: "es_MX")
                formateador.dateFormat = "d MMM, HH:mm"
                let nota = NotaDeVoz(
                    creado: ahora.addingTimeInterval(-duracion),
                    titulo: "Nota \(formateador.string(from: ahora))",
                    duracionSegundos: duracion,
                    rutaArchivo: primeraRuta,
                    transcripcion: textoNotaEnVivo.isEmpty ? nil : textoNotaEnVivo,
                    idioma: idiomaSeleccionado
                )
                try? repositorio?.guardarNotaDeVoz(nota)
            } else {
                mensajeDeError = "No se recibieron muestras del micrófono; no se guardó archivo vacío."
            }
            textoNotaEnVivo = ""

        case .ninguno:
            break
        }

        modoActivo = .ninguno
        pausada = false
        segundosTranscurridos = 0
        nivelMicrofono = 0
        nivelSistema = 0
        recargarDatos()
        await publicarEstadoDeGrabacion()
    }

    // MARK: - Retranscripción, Glosario y Acciones (GRB-4, GRB-5)

    public func retranscribirReunion(_ reunion: ReunionGrabada, idioma: IdiomaDeTranscripcion? = nil) async {
        let idiomaUsado = idioma ?? reunion.idioma
        var archivos: [(fuente: FuenteDeAudio, url: URL)] = []
        for ruta in reunion.rutasAudioMicrofono {
            archivos.append((.microfono, URL(fileURLWithPath: ruta)))
        }
        for ruta in reunion.rutasAudioSistema {
            archivos.append((.sistema, URL(fileURLWithPath: ruta)))
        }
        guard !archivos.isEmpty else {
            mensajeDeError = "Esta reunión ya no tiene archivos de audio guardados."
            return
        }
        retranscribiendo = true
        defer { retranscribiendo = false }
        do {
            let resultados = try await transcripcion.retranscribir(archivos: archivos, idioma: idiomaUsado)
            let corrector = CorrectorDeGlosario(entradas: glosario)
            var nuevos: [SegmentoDeTranscripcion] = []
            for (indice, r) in resultados.enumerated() {
                let texto = corrector.corregir(r.texto.trimmingCharacters(in: .whitespacesAndNewlines))
                guard !texto.isEmpty else { continue }
                let seg = SegmentoDeTranscripcion(
                    reunionID: reunion.id,
                    fuente: r.fuente,
                    inicioSegundos: Double(indice * 3),
                    finSegundos: Double(indice * 3 + 2),
                    texto: texto,
                    confianza: r.confianza,
                    esFinal: true
                )
                nuevos.append(seg)
            }
            try repositorio?.reemplazarSegmentos(reunionID: reunion.id, nuevos: nuevos)
            cargarSegmentosDeSeleccionada()
            mensajeDeError = nil
        } catch {
            mensajeDeError = "No se pudo retranscribir: \(error.localizedDescription)"
        }
    }

    public func agregarEntradaGlosario(malReconocido: String, correcto: String) {
        let mal = malReconocido.trimmingCharacters(in: .whitespacesAndNewlines)
        let bien = correcto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mal.isEmpty, !bien.isEmpty else { return }
        let entrada = EntradaDeGlosario(malReconocido: mal, correcto: bien, activo: true)
        try? repositorio?.guardarEntradaGlosario(entrada)
        if let repositorio, let lista = try? repositorio.listarGlosario() {
            glosario = lista
        } else {
            glosario.append(entrada)
        }
        ensamblador?.corrector = CorrectorDeGlosario(entradas: glosario)
    }

    public func borrarEntradaGlosario(_ id: String) {
        try? repositorio?.borrarEntradaGlosario(id: id)
        glosario.removeAll { $0.id == id }
        ensamblador?.corrector = CorrectorDeGlosario(entradas: glosario)
    }

    public func borrarNotaDeVoz(_ nota: NotaDeVoz) {
        if let borrada = try? repositorio?.borrarNotaDeVoz(id: nota.id) {
            try? FileManager.default.removeItem(atPath: borrada.rutaArchivo)
        } else {
            try? FileManager.default.removeItem(atPath: nota.rutaArchivo)
        }
        notasDeVoz.removeAll { $0.id == nota.id }
    }

    public func borrarReunion(_ reunion: ReunionGrabada) {
        let eliminada = (try? repositorio?.borrarReunion(id: reunion.id)) ?? reunion
        for ruta in eliminada.rutasAudioMicrofono + eliminada.rutasAudioSistema {
            try? FileManager.default.removeItem(atPath: ruta)
        }
        reunionesGuardadas.removeAll { $0.id == reunion.id }
        idsDeReunionesConNota.remove(reunion.id)
        if reunionSeleccionadaID == reunion.id {
            reunionSeleccionadaID = reunionesGuardadas.first?.id
        }
    }

    /// Borra todas las reuniones, transcripciones y notas de voz de la base y limpia los archivos de audio en disco.
    public func borrarTodo() {
        let rutas = (try? repositorio?.borrarTodo()) ?? []
        for ruta in rutas {
            try? FileManager.default.removeItem(atPath: ruta)
        }
        if let archivos = try? FileManager.default.contentsOfDirectory(
            at: carpetaAudio,
            includingPropertiesForKeys: nil
        ) {
            for url in archivos {
                try? FileManager.default.removeItem(at: url)
            }
        }
        notasDeVoz.removeAll()
        reunionesGuardadas.removeAll()
        idsDeReunionesConNota.removeAll()
        segmentosDeReunionSeleccionada.removeAll()
        nombresHablantesDeReunionSeleccionada.removeAll()
        notaDeReunionSeleccionada = nil
        errorDeResumen = nil
        resultadosBusqueda.removeAll()
        reunionSeleccionadaID = nil
        consultaBusqueda = ""
    }

    // MARK: - Separación de voces (diarización en el micrófono)

    /// Separa las voces del micrófono de una reunión grabada usando el puerto de diarización y actualiza los segmentos.
    @discardableResult
    public func separarVocesDeReunion(_ reunion: ReunionGrabada) async -> Bool {
        guard let diarizacion else {
            mensajeDeError = "La separación de voces no está disponible en este Mac."
            return false
        }
        let urls =
            reunion.rutasAudioMicrofono
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else {
            mensajeDeError = "Esta reunión no tiene archivos de audio del micrófono guardados."
            return false
        }
        guard await diarizacion.disponible() else {
            mensajeDeError = "La separación de voces no está disponible."
            return false
        }
        diarizando = true
        estadoDiarizacion = "Separando voces (la primera vez descarga los modelos)…"
        defer {
            diarizando = false
            estadoDiarizacion = nil
        }
        do {
            let tramos = try await diarizacion.diarizar(archivos: urls)
            let existentes: [SegmentoDeTranscripcion]
            if let repositorio, let guardados = try? repositorio.listarSegmentos(reunionID: reunion.id) {
                existentes = guardados
            } else if reunionSeleccionadaID == reunion.id {
                existentes = segmentosDeReunionSeleccionada
            } else {
                existentes = []
            }
            let asignacion = AsignadorDeHablantes.asignar(segmentos: existentes, tramos: tramos)
            try repositorio?.guardarAsignacionDeHablantes(
                reunionID: reunion.id,
                segmentos: asignacion.segmentos,
                hablantes: asignacion.hablantes
            )
            if reunionSeleccionadaID == reunion.id {
                segmentosDeReunionSeleccionada = asignacion.segmentos
                if let repositorio, let nombres = try? repositorio.listarNombresDeHablantes(reunionID: reunion.id) {
                    nombresHablantesDeReunionSeleccionada = nombres
                } else {
                    var mapa: [String: String] = [:]
                    for h in asignacion.hablantes { mapa[h] = h }
                    nombresHablantesDeReunionSeleccionada = mapa
                }
            }
            mensajeDeError = nil
            return true
        } catch {
            log.error("Fallo al separar voces de la reunión: \(error.localizedDescription, privacy: .public)")
            mensajeDeError = "No se pudieron separar las voces: \(error.localizedDescription)"
            return false
        }
    }

    /// Renombra un hablante de la reunión seleccionada y persiste el cambio para todos sus segmentos.
    public func renombrarHablante(reunionID: String, hablanteID: String, nuevoNombre: String) {
        let idLimpio = hablanteID.trimmingCharacters(in: .whitespacesAndNewlines)
        let nombreLimpio = nuevoNombre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idLimpio.isEmpty, !nombreLimpio.isEmpty else { return }
        try? repositorio?.renombrarHablante(
            reunionID: reunionID,
            hablanteID: idLimpio,
            nombre: nombreLimpio
        )
        if reunionSeleccionadaID == reunionID {
            if let repositorio, let nombres = try? repositorio.listarNombresDeHablantes(reunionID: reunionID) {
                nombresHablantesDeReunionSeleccionada = nombres
            } else {
                nombresHablantesDeReunionSeleccionada[idLimpio] = nombreLimpio
            }
        }
    }

    private func ejecutarDiarizacionAutomatica(para reunion: ReunionGrabada) async {
        guard let diarizacion else { return }
        let urls =
            reunion.rutasAudioMicrofono
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        guard await diarizacion.disponible() else { return }
        diarizando = true
        estadoDiarizacion = "Separando voces…"
        defer {
            diarizando = false
            estadoDiarizacion = nil
        }
        do {
            let tramos = try await diarizacion.diarizar(archivos: urls)
            guard let repositorio else { return }
            let existentes = try repositorio.listarSegmentos(reunionID: reunion.id)
            let asignacion = AsignadorDeHablantes.asignar(segmentos: existentes, tramos: tramos)
            try repositorio.guardarAsignacionDeHablantes(
                reunionID: reunion.id,
                segmentos: asignacion.segmentos,
                hablantes: asignacion.hablantes
            )
        } catch {
            log.error(
                "No se pudo separar las voces al terminar la reunión: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Notas de reunión: resumen a pedido, edición, copia y exportación (NOT-1, NOT-2)

    /// Resume una reunión del historial a pedido, guarda la nota en la base y (si el ajuste está activo) la envía al inbox.
    @discardableResult
    public func resumirReunion(_ reunion: ReunionGrabada) async -> NotaDeReunion? {
        errorDeResumen = nil
        guard let resumenDeTexto else {
            errorDeResumen = "Apple Intelligence no está disponible en este Mac."
            return nil
        }
        let segmentos: [SegmentoDeTranscripcion]
        if let repositorio, let guardados = try? repositorio.listarSegmentos(reunionID: reunion.id) {
            segmentos = guardados
        } else if reunionSeleccionadaID == reunion.id {
            segmentos = segmentosDeReunionSeleccionada
        } else {
            segmentos = []
        }
        let nombres =
            (try? repositorio?.listarNombresDeHablantes(reunionID: reunion.id))
            ?? (reunionSeleccionadaID == reunion.id ? nombresHablantesDeReunionSeleccionada : [:])
        let texto = Self.textoDeTranscripcion(segmentos, nombresHablantes: nombres)
        guard !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorDeResumen = "Esta reunión no tiene transcripción para resumir."
            return nil
        }
        resumiendo = true
        defer { resumiendo = false }
        guard await resumenDeTexto.disponible() else {
            errorDeResumen = "Apple Intelligence no está disponible o sigue descargándose."
            return nil
        }
        do {
            let markdown = try await RedaccionDeResumen.resumirPorPartes(texto, con: resumenDeTexto)
            guard !markdown.isEmpty else {
                errorDeResumen = "No se pudo generar el resumen de la reunión."
                return nil
            }
            let nota = NotaDeReunion(
                reunionID: reunion.id,
                markdown: markdown,
                generadaEn: .now,
                editadaEn: nil
            )
            try repositorio?.guardarNotaDeReunion(nota)
            idsDeReunionesConNota.insert(reunion.id)
            if reunionSeleccionadaID == reunion.id {
                notaDeReunionSeleccionada = nota
                seccionDetalleHistorial = .notas
            }
            if ajustes.resumirReunionesEnInbox {
                let fin = reunion.fin ?? .now
                let minutos = Int((fin.timeIntervalSince(reunion.inicio) / 60).rounded())
                let bloqueInbox = RedaccionDeResumen.notaDeInbox(
                    titulo: reunion.titulo,
                    inicio: reunion.inicio,
                    duracionMinutos: minutos,
                    resumen: markdown
                )
                _ = escribirEnInbox?(bloqueInbox)
            }
            return nota
        } catch {
            errorDeResumen = "No se pudo resumir la reunión: \(error.localizedDescription)"
            return nil
        }
    }

    /// Guarda los cambios manuales en la nota de una reunión y actualiza `editada_en` (NOT-2).
    @discardableResult
    public func guardarEdicionNota(reunionID: String, markdown: String, ahora: Date = .now) -> NotaDeReunion? {
        let limpio = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { return nil }
        let existente = (try? repositorio?.obtenerNotaDeReunion(reunionID: reunionID)) ?? notaDeReunionSeleccionada
        let generada = existente?.generadaEn ?? ahora
        let actualizada = NotaDeReunion(
            reunionID: reunionID,
            markdown: limpio,
            generadaEn: generada,
            editadaEn: ahora
        )
        try? repositorio?.guardarNotaDeReunion(actualizada)
        idsDeReunionesConNota.insert(reunionID)
        if reunionSeleccionadaID == reunionID {
            notaDeReunionSeleccionada = actualizada
        }
        return actualizada
    }

    /// Refresca la nota de la reunión seleccionada si el resumidor en segundo plano acaba de guardarla.
    public func recargarNotaDeReunionSeleccionada() {
        guard let repositorio else { return }
        idsDeReunionesConNota = (try? repositorio.idsDeReunionesConNota()) ?? idsDeReunionesConNota
        guard let id = reunionSeleccionadaID else { return }
        notaDeReunionSeleccionada = try? repositorio.obtenerNotaDeReunion(reunionID: id)
        if notaDeReunionSeleccionada != nil {
            seccionDetalleHistorial = .notas
        }
    }

    /// Copia el Markdown de la nota al portapapeles del sistema y marca `notaCopiada` por 1.5 s.
    public func copiarNota(_ markdown: String) {
        let texto = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty else { return }
        let pasta = NSPasteboard.general
        pasta.clearContents()
        pasta.setString(texto, forType: .string)
        notaCopiada = true
        tareaAvisoNotaCopiada?.cancel()
        tareaAvisoNotaCopiada = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            self?.notaCopiada = false
        }
    }

    /// Construye el documento Markdown completo y su nombre de archivo sugerido para exportar (NOT-2).
    public func construirExportacionMarkdown(para reunion: ReunionGrabada) -> (nombreArchivo: String, contenido: String)
    {
        let nota: NotaDeReunion?
        if reunionSeleccionadaID == reunion.id, let actual = notaDeReunionSeleccionada {
            nota = actual
        } else {
            nota = try? repositorio?.obtenerNotaDeReunion(reunionID: reunion.id)
        }
        let segmentos: [SegmentoDeTranscripcion]
        if let repositorio, let guardados = try? repositorio.listarSegmentos(reunionID: reunion.id) {
            segmentos = guardados
        } else if reunionSeleccionadaID == reunion.id {
            segmentos = segmentosDeReunionSeleccionada
        } else {
            segmentos = []
        }
        let nombres =
            (try? repositorio?.listarNombresDeHablantes(reunionID: reunion.id))
            ?? (reunionSeleccionadaID == reunion.id ? nombresHablantesDeReunionSeleccionada : [:])
        let nombre = RedaccionDeResumen.nombreArchivoMarkdown(titulo: reunion.titulo, fecha: reunion.inicio)
        let contenido = RedaccionDeResumen.markdownExportable(
            reunion: reunion,
            notaMarkdown: nota?.markdown,
            segmentos: segmentos,
            nombresHablantes: nombres
        )
        return (nombre, contenido)
    }

    public func abrirArchivo(_ ruta: String) {
        alAbrirURL?(URL(fileURLWithPath: ruta))
    }

    public func abrirAjustesPermisoMicrofono() {
        if let url = PermisoDelSistema.microfono.enlaceDeAjustesDelSistema {
            alAbrirURL?(url)
        }
    }

    // MARK: - Procesamiento interno de bloques, transcripción y entorno

    private func procesarBloqueDeAudio(_ bloque: BloqueDeAudioPCM) {
        guard grabando, !pausada else { return }
        switch bloque.fuente {
        case .microfono:
            nivelMicrofono = bloque.nivelRMS
        case .sistema:
            nivelSistema = bloque.nivelRMS
        case .marca:
            break
        }
        let pico = max(nivelMicrofono, nivelSistema)
        nivelesOnda = [
            max(0.16, min(1.0, nivelMicrofono * 0.9 + 0.16)),
            max(0.16, min(1.0, pico)),
            max(0.16, min(1.0, nivelSistema * 0.9 + 0.18)),
            max(0.16, min(1.0, (nivelMicrofono + nivelSistema) * 0.55 + 0.16)),
        ]
        estadisticasCaptura = captura.estadisticas

        if modoActivo == .notaDeVoz || ajustes.guardarAudioReuniones {
            do {
                try escritor.escribir(bloque)
                sincronizarRutasEnReunionActiva()
            } catch {
                log.error("Error al escribir trozo de audio: \(error.localizedDescription, privacy: .public)")
            }
        }
        transcripcion.alimentar(bloque)
    }

    private func procesarResultadoDeTranscripcion(_ resultado: ResultadoDeTranscripcion) {
        guard modoActivo == .reunion, !pausada, var ens = ensamblador else { return }
        let seg = ens.recibir(
            fuente: resultado.fuente,
            texto: resultado.texto,
            esFinal: resultado.esFinal,
            enSegundos: Double(segundosTranscurridos),
            confianza: resultado.confianza
        )
        ensamblador = ens
        guard let seg else { return }
        if seg.esFinal {
            try? repositorio?.guardarSegmento(seg)
            sincronizarRutasEnReunionActiva()
        }
        if let bus {
            Task { await bus.publicar(SegmentoDeTranscripcionRecibido(segmento: seg)) }
        }
    }

    /// Maneja el reposo del Mac, el cambio de dispositivo de audio o la pérdida de una fuente (GRB-7).
    public func manejarEventoDeEntorno(_ evento: EventoDeEntornoDeAudio) async {
        guard grabando else { return }
        switch evento {
        case .reposoDelMacIniciado:
            avisoDeFuente = "Mac en reposo: trozo guardado para continuar al despertar."
            if var ens = ensamblador {
                for seg in ens.consolidarProvisionales(enSegundos: Double(segundosTranscurridos)) {
                    try? repositorio?.guardarSegmento(seg)
                }
                ensamblador = ens
            }
            try? escritor.rotarTrozo()
            sincronizarRutasEnReunionActiva()

        case .despertarDelMac:
            avisoDeFuente = "Grabación reanudada tras el reposo."
            sincronizarRutasEnReunionActiva()

        case .cambioDeDispositivo(let nombre):
            avisoDeFuente = "Dispositivo cambiado a \(nombre); grabación continua en nuevo trozo."
            try? escritor.rotarTrozo()
            sincronizarRutasEnReunionActiva()
            estadisticasCaptura = captura.estadisticas

        case .falloDeFuente(let fuente, let detalle):
            avisoDeFuente = "Aviso en \(fuente.etiqueta): \(detalle)"
        }
    }

    private func sincronizarRutasEnReunionActiva() {
        guard var reunion = reunionActual else { return }
        let mic = escritor.rutasMicrofono
        let sis = escritor.rutasSistema
        let desfase = estadisticasCaptura.desfaseInicialMs
        if reunion.rutasAudioMicrofono != mic
            || reunion.rutasAudioSistema != sis
            || reunion.desfaseInicialMs != desfase
        {
            reunion.rutasAudioMicrofono = mic
            reunion.rutasAudioSistema = sis
            reunion.desfaseInicialMs = desfase
            reunionActual = reunion
            try? repositorio?.guardarReunion(reunion)
        }
    }

    private func recuperarYLimpiarAlArrancar() {
        guard let repositorio else { return }
        if let recuperadas = try? repositorio.recuperarReunionesIncompletas(), !recuperadas.isEmpty {
            avisoDeFuente = "Se recuperó \(recuperadas.count) reunión cerrada inesperadamente."
        }
        if let rutasViejas = try? repositorio.aplicarRetencionDeAudio(
            dias: ajustes.diasRetencionAudioReuniones
        ) {
            for ruta in rutasViejas {
                try? FileManager.default.removeItem(atPath: ruta)
            }
        }
    }

    private func cargarSegmentosDeSeleccionada() {
        guard let id = reunionSeleccionadaID, let repositorio else {
            segmentosDeReunionSeleccionada = []
            nombresHablantesDeReunionSeleccionada = [:]
            notaDeReunionSeleccionada = nil
            seccionDetalleHistorial = .transcripcion
            return
        }
        segmentosDeReunionSeleccionada = (try? repositorio.listarSegmentos(reunionID: id)) ?? []
        nombresHablantesDeReunionSeleccionada = (try? repositorio.listarNombresDeHablantes(reunionID: id)) ?? [:]
        notaDeReunionSeleccionada = try? repositorio.obtenerNotaDeReunion(reunionID: id)
        if notaDeReunionSeleccionada != nil {
            idsDeReunionesConNota.insert(id)
            seccionDetalleHistorial = .notas
        } else {
            idsDeReunionesConNota.remove(id)
            seccionDetalleHistorial = .transcripcion
        }
    }

    private func actualizarBusqueda() {
        guard let repositorio else {
            resultadosBusqueda = []
            return
        }
        let limpia = consultaBusqueda.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpia.isEmpty else {
            resultadosBusqueda = []
            return
        }
        resultadosBusqueda = (try? repositorio.buscarSegmentos(consulta: limpia)) ?? []
    }

    private func asegurarPermisoMicrofono() async -> Bool {
        permisoMicrofono = captura.estadoDePermisoMicrofono()
        if permisoMicrofono == .sinPedir {
            permisoMicrofono = await captura.pedirPermisoMicrofono()
            if let bus {
                await bus.publicar(CambioDePermiso(permiso: .microfono, estado: permisoMicrofono))
            }
        }
        guard permisoMicrofono == .concedido else {
            mensajeDeError = "Activa el permiso de Micrófono para grabar."
            return false
        }
        return true
    }

    private func resolverTituloReunion(_ personalizado: String?, fecha: Date) -> String {
        let base = (personalizado ?? tituloReunion).trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.isEmpty { return base }
        let formateador = DateFormatter()
        formateador.locale = Locale(identifier: "es_MX")
        formateador.dateFormat = "d MMM, HH:mm"
        return "Reunión \(formateador.string(from: fecha))"
    }

    private func arrancarReloj() {
        tareaReloj?.cancel()
        tareaReloj = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, self.grabando else { break }
                if !self.pausada {
                    self.actualizarSegundos(ahora: .now)
                }
                await self.publicarEstadoDeGrabacion()
            }
        }
    }

    private func actualizarSegundos(ahora: Date) {
        guard let inicio = inicioTramoActual else { return }
        let total = acumuladoAntesDePausa + max(0, ahora.timeIntervalSince(inicio))
        segundosTranscurridos = Int(total.rounded(.down))
    }

    private func publicarEstadoDeGrabacion() async {
        guard let bus else { return }
        await bus.publicar(
            PeticionDeEstadoCompacto(
                modulo: "grabadora",
                prioridad: grabando ? .grabando : nil
            )
        )
        await bus.publicar(
            GrabacionCambiada(
                activa: grabando,
                esReunion: modoActivo == .reunion,
                pausada: pausada,
                segundos: segundosTranscurridos,
                nivelMicrofono: nivelMicrofono,
                nivelSistema: nivelSistema
            )
        )
    }

    private func suscribirAvisosDeAgenda() {
        tareaAvisoAgenda?.cancel()
        guard let bus else { return }
        tareaAvisoAgenda = Task { [weak self] in
            let flujo = await bus.suscribir(a: IniciarReunionDesdeAviso.self)
            for await pedido in flujo {
                guard let self else { break }
                self.pestanaSeleccionada = .reunion
                self.tituloReunion = pedido.titulo
                await self.iniciarReunion(
                    tituloPersonalizado: pedido.titulo,
                    eventoCalendarioID: pedido.eventoCalendarioID
                )
            }
        }
    }
}

private final class AlmacenEnMemoriaGrabadora: AlmacenDeAjustes, @unchecked Sendable {
    private var datos: [String: Data] = [:]
    func leer(_ clave: String) -> Data? { datos[clave] }
    func guardar(_ dato: Data?, en clave: String) { datos[clave] = dato }
}
