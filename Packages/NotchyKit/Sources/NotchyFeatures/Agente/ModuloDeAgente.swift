import AppKit
import Foundation
import NotchyCore
import NotchyDesign
import NotchyStorage
import Observation
import SwiftUI

/// Modelo observable del minichatbot agéntico impulsado por OpenCode (`opencode run`) y Apple Intelligence local.
@MainActor
@Observable
public final class ModeloDeAgente {
    public private(set) var mensajes: [MensajeDeAgente] = []
    public var entrada = ""
    public private(set) var respondiendo = false
    public private(set) var modelosDisponibles: [String] = ProveedoresDelAgente.modelosDeRespaldo
    public var modeloSeleccionado: String {
        didSet {
            defaults.set(modeloSeleccionado, forKey: Self.claveModelo)
            corredorDePermisos.estadoDelAgente.actualizarModelo(modeloSeleccionado)
        }
    }
    public private(set) var sesionID: String?
    public private(set) var conversacionActualID: String?
    public private(set) var conversacionesGuardadas: [ConversacionDeAgente] = []
    public var mostrandoHistorial = false
    public private(set) var avisoDeRespaldoLocal: String?
    public let corredorDePermisos: CorredorDePermisos

    @ObservationIgnored private let puerto: any PuertoAgenteOpenCode
    @ObservationIgnored private let chatLocal: (any PuertoDeChatLocal)?
    @ObservationIgnored private let repositorio: RepositorioDeAgente?
    @ObservationIgnored private let contextoLocal: (@MainActor () async -> String)?
    @ObservationIgnored private let servidorMCP: (any PuertoServidorMCPAgente)?
    @ObservationIgnored private let ajustes: Ajustes?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var tareaActual: Task<Void, Never>?
    @ObservationIgnored private var ultimoModeloUsadoEnEnvio: String?
    @ObservationIgnored private static let claveModelo = "notchy.agente.modelo"

    public init(
        puerto: any PuertoAgenteOpenCode,
        chatLocal: (any PuertoDeChatLocal)? = nil,
        repositorio: RepositorioDeAgente? = nil,
        contextoLocal: (@MainActor () async -> String)? = nil,
        ajustes: Ajustes? = nil,
        corredorDePermisos: CorredorDePermisos? = nil,
        servidorMCP: (any PuertoServidorMCPAgente)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.puerto = puerto
        self.chatLocal = chatLocal
        self.repositorio = repositorio
        self.contextoLocal = contextoLocal
        self.ajustes = ajustes
        let corredor = corredorDePermisos ?? CorredorDePermisos(ajustes: ajustes)
        self.corredorDePermisos = corredor
        self.servidorMCP = servidorMCP
        self.defaults = defaults
        let modeloInicial = ProveedoresDelAgente.resolver(
            elegido: defaults.string(forKey: Self.claveModelo),
            disponibles: ProveedoresDelAgente.modelosDeRespaldo + [ProveedoresDelAgente.modeloAppleLocal]
        )
        self.modeloSeleccionado = modeloInicial
        corredor.estadoDelAgente.actualizarModelo(modeloInicial)
        self.mensajes = [
            MensajeDeAgente(
                rol: .asistente,
                texto: "Hola. Estoy conectado a OpenCode y a tu vault. ¿En qué te ayudo?"
            )
        ]
        self.conversacionesGuardadas = (try? repositorio?.listarConversaciones()) ?? []
        corredor.alDenegar = { [weak self] _ in
            self?.mensajes.append(MensajeDeAgente(rol: .herramienta, texto: "Negado"))
        }
    }

    public func arrancar() async {
        try? await servidorMCP?.arrancar()
        recargarConversaciones()
        await cargarModelos()
    }

    public func detener() async {
        cancelar()
        await servidorMCP?.detener()
    }

    public var salud: SaludDeModulo {
        if ProveedoresDelAgente.esModeloDeApple(modeloSeleccionado) {
            return .listo
        }
        return puerto.estaDisponible() ? .listo : .error("Falta instalar OpenCode en /opt/homebrew/bin/opencode")
    }

    public func cargarModelos() async {
        var lista = ProveedoresDelAgente.filtrar(await puerto.modelosDisponibles())
        if lista.isEmpty {
            lista = ProveedoresDelAgente.modelosDeRespaldo
        }
        let appleDisponible = await chatLocal?.disponible() ?? false
        if appleDisponible, !lista.contains(ProveedoresDelAgente.modeloAppleLocal) {
            lista.append(ProveedoresDelAgente.modeloAppleLocal)
        }
        modelosDisponibles = lista
        let resuelto = ProveedoresDelAgente.resolver(elegido: modeloSeleccionado, disponibles: modelosDisponibles)
        if resuelto != modeloSeleccionado {
            modeloSeleccionado = resuelto
        }
    }

    public func enviar() {
        let texto = entrada.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty, !respondiendo else { return }
        entrada = ""
        enviarPrompt(texto)
    }

    public func enviarPrompt(_ texto: String) {
        guard !respondiendo else { return }
        mostrandoHistorial = false
        let msgUsuario = MensajeDeAgente(rol: .usuario, texto: texto)
        mensajes.append(msgUsuario)

        let modelo = modeloSeleccionado
        let esAppleElegido = ProveedoresDelAgente.esModeloDeApple(modelo)
        let idRespuesta = UUID().uuidString
        let textoPensando = esAppleElegido ? "Pensando en la Mac…" : "Pensando con OpenCode…"
        mensajes.append(MensajeDeAgente(id: idRespuesta, rol: .asistente, texto: textoPensando))
        respondiendo = true

        let sesion = sesionID
        let dir = ajustes?.rutaVaultObsidian
        let veniaDeApple = ultimoModeloUsadoEnEnvio.map(ProveedoresDelAgente.esModeloDeApple) ?? false

        tareaActual = Task { [weak self] in
            guard let self else { return }
            let sinOpenCode = !self.puerto.estaDisponible()
            let sinRed = !self.puerto.hayRedDisponible()

            if esAppleElegido || sinOpenCode || sinRed {
                let esRespaldo = !esAppleElegido && (sinOpenCode || sinRed)
                await self.responderConModeloLocal(
                    idRespuesta: idRespuesta,
                    mostrarAvisoSinRed: esRespaldo
                )
                self.ultimoModeloUsadoEnEnvio = ProveedoresDelAgente.modeloAppleLocal
                self.persistirConversacionActual()
                self.respondiendo = false
                return
            }

            self.avisoDeRespaldoLocal = nil
            let promptEfectivo =
                veniaDeApple
                ? Self.construirPromptConHistorialReciente(mensajes: self.mensajes, nuevoTexto: texto)
                : texto

            do {
                let resultado = try await self.puerto.enviarMensaje(
                    prompt: promptEfectivo,
                    modelo: modelo,
                    sesionID: sesion,
                    directorio: dir
                ) { parcial, nuevaSesion in
                    self.actualizarMensaje(id: idRespuesta, texto: parcial)
                    if let nuevaSesion {
                        self.sesionID = nuevaSesion
                    }
                }
                self.actualizarMensaje(id: idRespuesta, texto: resultado.textoFinal)
                if let sid = resultado.sesionID {
                    self.sesionID = sid
                }
                self.ultimoModeloUsadoEnEnvio = modelo
                self.persistirConversacionActual()
            } catch {
                if self.chatLocal != nil && (!self.puerto.hayRedDisponible() || Self.esErrorDeRed(error)) {
                    await self.responderConModeloLocal(
                        idRespuesta: idRespuesta,
                        mostrarAvisoSinRed: true
                    )
                    self.ultimoModeloUsadoEnEnvio = ProveedoresDelAgente.modeloAppleLocal
                    self.persistirConversacionActual()
                } else {
                    self.actualizarMensaje(
                        id: idRespuesta,
                        texto: "No se pudo ejecutar OpenCode: \(error.localizedDescription)"
                    )
                    self.persistirConversacionActual()
                }
            }
            self.respondiendo = false
        }
    }

    private func responderConModeloLocal(
        idRespuesta: String,
        mostrarAvisoSinRed: Bool
    ) async {
        if mostrarAvisoSinRed {
            let textoAviso = "Sin red: respondo con el modelo de Apple"
            avisoDeRespaldoLocal = textoAviso
            if let idx = mensajes.firstIndex(where: { $0.id == idRespuesta }) {
                mensajes.insert(MensajeDeAgente(rol: .herramienta, texto: textoAviso), at: idx)
            }
        } else {
            avisoDeRespaldoLocal = nil
        }

        guard let chatLocal else {
            actualizarMensaje(
                id: idRespuesta,
                texto: "El modelo local de Apple no está disponible en esta Mac."
            )
            return
        }

        let resumenAgenda = (await contextoLocal?())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var instrucciones =
            "Eres Notchy, el asistente del notch del usuario en macOS. Responde en español, de forma directa y breve (una o dos frases). No inventes datos."
        if !resumenAgenda.isEmpty {
            instrucciones += "\n\nContexto actual de agenda_hoy:\n\(resumenAgenda)"
        }

        let historialSinPlaceholder = mensajes.filter {
            $0.id != idRespuesta && ($0.rol == .usuario || $0.rol == .asistente)
        }
        do {
            let respuesta = try await chatLocal.responder(
                mensajes: historialSinPlaceholder,
                instrucciones: instrucciones
            )
            actualizarMensaje(id: idRespuesta, texto: respuesta.isEmpty ? "Listo." : respuesta)
        } catch {
            actualizarMensaje(
                id: idRespuesta,
                texto: "No se pudo responder con el modelo de Apple: \(error.localizedDescription)"
            )
        }
    }

    public static func construirPromptConHistorialReciente(
        mensajes: [MensajeDeAgente],
        nuevoTexto: String
    ) -> String {
        let previos =
            mensajes
            .filter { $0.rol == .usuario || $0.rol == .asistente }
            .dropLast(2)
            .suffix(6)
        guard !previos.isEmpty else { return nuevoTexto }
        let lineas =
            previos
            .map { msg in
                let rol = msg.rol == .usuario ? "Usuario" : "Asistente"
                return "\(rol): \(msg.texto)"
            }
            .joined(separator: "\n")
        return """
            Contexto reciente de la conversación:
            \(lineas)

            Mensaje actual del usuario:
            \(nuevoTexto)
            """
    }

    private static func esErrorDeRed(_ error: any Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain || nsError.code == -1009 {
            return true
        }
        let texto = error.localizedDescription.lowercased()
        let pistas = [
            "network", "offline", "sin red", "connection", "connect",
            "timed out", "timeout", "enotfound", "econnrefused",
            "econnreset", "ehostunreach", "enetunreach", "fetch failed",
            "dns", "socket", "unreachable", "404",
        ]
        return pistas.contains { texto.contains($0) }
    }

    public func cancelar() {
        tareaActual?.cancel()
        tareaActual = nil
        respondiendo = false
    }

    public func nuevaConversacion() {
        cancelar()
        sesionID = nil
        conversacionActualID = nil
        ultimoModeloUsadoEnEnvio = nil
        avisoDeRespaldoLocal = nil
        mostrandoHistorial = false
        mensajes = [
            MensajeDeAgente(
                rol: .asistente,
                texto: "Sesión nueva lista en OpenCode. ¿Qué hacemos?"
            )
        ]
    }

    // MARK: - Historial de conversaciones (AGT-8)

    public func recargarConversaciones() {
        conversacionesGuardadas = (try? repositorio?.listarConversaciones()) ?? []
    }

    private func persistirConversacionActual() {
        guard let repositorio else { return }
        guard let primerUsuario = mensajes.first(where: { $0.rol == .usuario }) else { return }
        let ahora = Date.now
        let idConv = conversacionActualID ?? UUID().uuidString
        conversacionActualID = idConv
        let existente = try? repositorio.obtenerConversacion(id: idConv)
        let conversacion = ConversacionDeAgente(
            id: idConv,
            sesionOpenCodeID: sesionID ?? existente?.sesionOpenCodeID,
            titulo: existente?.titulo ?? ConversacionDeAgente.recortarTitulo(primerUsuario.texto),
            modelo: modeloSeleccionado,
            creado: existente?.creado ?? primerUsuario.fecha,
            actualizado: ahora
        )
        try? repositorio.guardarConversacionYMensajes(conversacion, mensajes: mensajes)
        recargarConversaciones()
    }

    public func abrirConversacion(_ id: String) {
        guard let repositorio,
            let conversacion = try? repositorio.obtenerConversacion(id: id)
        else { return }
        cancelar()
        conversacionActualID = conversacion.id
        sesionID = conversacion.sesionOpenCodeID
        if ProveedoresDelAgente.estaPermitido(conversacion.modelo) {
            modeloSeleccionado = conversacion.modelo
        }
        let guardados = (try? repositorio.listarMensajes(conversacionID: id)) ?? []
        if !guardados.isEmpty {
            mensajes = guardados
        }
        ultimoModeloUsadoEnEnvio = conversacion.modelo
        mostrandoHistorial = false
    }

    public func borrarConversacion(_ id: String) async {
        let sesionABorrar = try? repositorio?.borrarConversacion(id: id)
        if let sid = sesionABorrar ?? nil, !sid.isEmpty {
            _ = await puerto.eliminarSesion(id: sid)
        }
        if conversacionActualID == id {
            nuevaConversacion()
        }
        recargarConversaciones()
    }

    /// Borra el historial de conversación del agente y restablece el modelo seleccionado.
    public func borrarHistorial() {
        cancelar()
        let sesionActiva = sesionID
        let sesionesGuardadas = (try? repositorio?.borrarTodo()) ?? []
        var todasLasSesiones = Set(sesionesGuardadas)
        if let sesionActiva, !sesionActiva.isEmpty {
            todasLasSesiones.insert(sesionActiva)
        }
        let puertoCapturado = puerto
        if !todasLasSesiones.isEmpty {
            Task { @MainActor in
                for sid in todasLasSesiones {
                    _ = await puertoCapturado.eliminarSesion(id: sid)
                }
            }
        }
        sesionID = nil
        conversacionActualID = nil
        conversacionesGuardadas = []
        ultimoModeloUsadoEnEnvio = nil
        avisoDeRespaldoLocal = nil
        mostrandoHistorial = false
        entrada = ""
        defaults.removeObject(forKey: Self.claveModelo)
        modeloSeleccionado = ProveedoresDelAgente.resolver(
            elegido: nil,
            disponibles: modelosDisponibles
        )
        mensajes = [
            MensajeDeAgente(
                rol: .asistente,
                texto: "Hola. Estoy conectado a OpenCode y a tu vault. ¿En qué te ayudo?"
            )
        ]
    }

    public func copiar(_ texto: String) {
        let pasta = NSPasteboard.general
        pasta.clearContents()
        pasta.setString(texto, forType: .string)
    }

    private func actualizarMensaje(id: String, texto: String) {
        guard let idx = mensajes.firstIndex(where: { $0.id == id }) else { return }
        mensajes[idx].texto = texto
    }
}

/// Módulo del Minichatbot Agéntico con proveedor OpenCode (`sparkles`).
@MainActor
public final class ModuloDeAgente: ModuloDeIsla {
    public let identidad = IdentidadDeModulo(
        id: "agente",
        nombre: "OpenCode",
        icono: "sparkles",
        color: Paleta.hexAgente,
        lado: .izquierda
    )
    public let tamanoExpandido = Medidas.agente
    public let modelo: ModeloDeAgente

    public init(modelo: ModeloDeAgente) {
        self.modelo = modelo
    }

    public var salud: SaludDeModulo {
        modelo.salud
    }

    public var vistaExpandida: AnyView {
        AnyView(VistaDeAgente(modelo: modelo))
    }

    public func arrancar() {
        Task { await modelo.arrancar() }
    }

    public func detener() {
        modelo.cancelar()
        Task { await modelo.detener() }
    }
}

struct VistaDeAgente: View {
    @Bindable var modelo: ModeloDeAgente
    @FocusState private var campoEnfocado: Bool
    @Environment(\.accessibilityReduceMotion) private var reducirMovimiento
    @Environment(\.accessibilityReduceTransparency) private var reducirTransparencia

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            barraSuperior
            if modelo.mostrandoHistorial {
                listaHistorialConversaciones
            } else {
                areaMensajes
            }
            if let solicitud = modelo.corredorDePermisos.solicitudActual {
                tarjetaDePermiso(solicitud)
            }
            barraEntrada
        }
        .padding(.horizontal, 4)
        .onAppear {
            campoEnfocado = true
        }
    }

    private var barraSuperior: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Paleta.agente)
                Text("OpenCode Agent")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Paleta.texto)
            }

            Menu {
                ForEach(modelo.modelosDisponibles.prefix(18), id: \.self) { m in
                    Button {
                        modelo.modeloSeleccionado = m
                    } label: {
                        HStack {
                            Text(
                                "\(ProveedoresDelAgente.nombreParaMostrar(m)) · \(ProveedoresDelAgente.clasificar(m).rawValue)"
                            )
                            if m == modelo.modeloSeleccionado {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                let ubicacion = ProveedoresDelAgente.clasificar(modelo.modeloSeleccionado)
                HStack(spacing: 4) {
                    Text(nombreCortoModelo(modelo.modeloSeleccionado))
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    chipUbicacionModelo(ubicacion)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(Paleta.textoDeApoyo)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Paleta.superficie, in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                chipSugerencia("Resumen Inbox") {
                    modelo.enviarPrompt("Resume brevemente qué hay en mi archivo 00-inbox/inbox.md o 00_Inbox.")
                }
                chipSugerencia("Explicar rápido") {
                    campoEnfocado = true
                }
            }

            Button {
                modelo.recargarConversaciones()
                modelo.mostrandoHistorial.toggle()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(modelo.mostrandoHistorial ? Paleta.agente : Paleta.textoDeApoyo)
                    .frame(width: 22, height: 22)
                    .background(Paleta.superficie, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Historial de conversaciones")
            .accessibilityLabel("Historial de conversaciones")

            Button {
                modelo.nuevaConversacion()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Paleta.textoDeApoyo)
                    .frame(width: 22, height: 22)
                    .background(Paleta.superficie, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Nueva sesión de OpenCode")
            .accessibilityLabel("Nueva sesión de OpenCode")
        }
    }

    private func chipUbicacionModelo(_ ubicacion: UbicacionDeModeloAgente) -> some View {
        let esLocal = ubicacion == .local
        return Text(ubicacion.rawValue)
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(esLocal ? Color(hex: 0x30D158) : Paleta.agente)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                (esLocal ? Color(hex: 0x30D158) : Paleta.agente).opacity(0.18),
                in: Capsule()
            )
    }

    private var listaHistorialConversaciones: some View {
        VStack(alignment: .leading, spacing: 6) {
            if modelo.conversacionesGuardadas.isEmpty {
                VStack(spacing: 4) {
                    Text("Sin conversaciones previas")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Paleta.textoDeApoyo)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(modelo.conversacionesGuardadas) { conv in
                            HStack(spacing: 8) {
                                Button {
                                    modelo.abrirConversacion(conv.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(conv.titulo)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(Paleta.texto)
                                            .lineLimit(1)
                                        Text(formatearFechaConversacion(conv.actualizado))
                                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                                            .foregroundStyle(Paleta.textoDeApoyo)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    Task { await modelo.borrarConversacion(conv.id) }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Color(hex: 0xFF453A))
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.plain)
                                .help("Borrar conversación")
                                .accessibilityLabel("Borrar conversación")
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Paleta.superficie, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formatearFechaConversacion(_ fecha: Date) -> String {
        let formateador = DateFormatter()
        formateador.locale = Locale(identifier: "es_MX")
        formateador.dateFormat = "d MMM, HH:mm"
        return formateador.string(from: fecha)
    }

    private func chipSugerencia(_ titulo: String, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Text(titulo)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Paleta.agente)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Paleta.agente.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var areaMensajes: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(modelo.mensajes) { msg in
                        burbuja(msg)
                            .id(msg.id)
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: modelo.mensajes.count) { _, _ in
                if let ultimo = modelo.mensajes.last?.id {
                    withAnimation(Movimiento.cambioDeEstado(reducir: reducirMovimiento)) {
                        proxy.scrollTo(ultimo, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func burbuja(_ msg: MensajeDeAgente) -> some View {
        let esUsuario = msg.rol == .usuario
        return HStack(alignment: .top, spacing: 6) {
            if esUsuario { Spacer(minLength: 36) }

            HStack(alignment: .top, spacing: 6) {
                Text(msg.texto)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Paleta.texto)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if !esUsuario {
                    Button {
                        modelo.copiar(msg.texto)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Paleta.textoDeApoyo)
                    }
                    .buttonStyle(.plain)
                    .help("Copiar respuesta")
                    .accessibilityLabel("Copiar respuesta")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                esUsuario
                    ? Paleta.agente.opacity(0.28)
                    : (reducirTransparencia ? Paleta.superficieSolida : Paleta.superficie),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        esUsuario ? Paleta.agente.opacity(0.45) : Paleta.borde.opacity(0.6),
                        lineWidth: 1
                    )
            )

            if !esUsuario { Spacer(minLength: 24) }
        }
    }

    private func tarjetaDePermiso(_ solicitud: SolicitudDePermisoAgente) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Paleta.agente)
                Text("Permiso requerido: \(solicitud.herramienta)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Paleta.texto)
                Spacer(minLength: 0)
            }

            Text(solicitud.resumenArgumentos)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(Paleta.textoDeApoyo)
                .lineLimit(2)

            HStack(spacing: 6) {
                Button("Negar") {
                    modelo.corredorDePermisos.responder(.negar)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color(hex: 0xFF453A).opacity(0.85), in: Capsule())

                Button("Permitir") {
                    modelo.corredorDePermisos.responder(.permitirUnaVez)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Paleta.texto)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Paleta.superficieSolida, in: Capsule())

                Button("Siempre") {
                    modelo.corredorDePermisos.responder(.siempre)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Paleta.agente, in: Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Paleta.superficie, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Paleta.agente.opacity(0.6), lineWidth: 1)
        )
    }

    private var barraEntrada: some View {
        HStack(spacing: 8) {
            TextField("Pregúntale a OpenCode o pídele una tarea…", text: $modelo.entrada)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Paleta.texto)
                .focused($campoEnfocado)
                .onSubmit {
                    modelo.enviar()
                }

            if modelo.respondiendo {
                Button {
                    modelo.cancelar()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Color(hex: 0xFF453A), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Detener ejecución")
                .accessibilityLabel("Detener ejecución")
            } else {
                Button {
                    modelo.enviar()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Paleta.agente, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(modelo.entrada.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Enviar a OpenCode")
                .accessibilityLabel("Enviar a OpenCode")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Paleta.superficie, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(campoEnfocado ? Paleta.agente.opacity(0.6) : Paleta.borde, lineWidth: 1)
        )
    }

    private func nombreCortoModelo(_ completo: String) -> String {
        ProveedoresDelAgente.nombreCortoParaMostrar(completo)
    }
}
