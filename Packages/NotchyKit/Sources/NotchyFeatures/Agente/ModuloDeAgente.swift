import AppKit
import Foundation
import NotchyCore
import NotchyDesign
import Observation
import SwiftUI

/// Modelo observable del minichatbot agéntico impulsado por OpenCode (`opencode run`).
@MainActor
@Observable
public final class ModeloDeAgente {
    public private(set) var mensajes: [MensajeDeAgente] = []
    public var entrada = ""
    public private(set) var respondiendo = false
    public private(set) var modelosDisponibles: [String] = ProveedoresDelAgente.modelosDeRespaldo
    public var modeloSeleccionado: String {
        didSet { defaults.set(modeloSeleccionado, forKey: Self.claveModelo) }
    }
    public private(set) var sesionID: String?

    @ObservationIgnored private let puerto: any PuertoAgenteOpenCode
    @ObservationIgnored private let ajustes: Ajustes?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var tareaActual: Task<Void, Never>?
    @ObservationIgnored private static let claveModelo = "notchy.agente.modelo"

    public init(
        puerto: any PuertoAgenteOpenCode,
        ajustes: Ajustes? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.puerto = puerto
        self.ajustes = ajustes
        self.defaults = defaults
        self.modeloSeleccionado = ProveedoresDelAgente.resolver(
            elegido: defaults.string(forKey: Self.claveModelo),
            disponibles: ProveedoresDelAgente.modelosDeRespaldo
        )
        self.mensajes = [
            MensajeDeAgente(
                rol: .asistente,
                texto: "Hola Darian. Estoy conectado a OpenCode y a tu vault. ¿En qué te ayudo?"
            )
        ]
    }

    public var salud: SaludDeModulo {
        puerto.estaDisponible() ? .listo : .error("Falta instalar OpenCode en /opt/homebrew/bin/opencode")
    }

    public func cargarModelos() async {
        let lista = ProveedoresDelAgente.filtrar(await puerto.modelosDisponibles())
        if !lista.isEmpty {
            modelosDisponibles = lista
        }
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
        mensajes.append(MensajeDeAgente(rol: .usuario, texto: texto))
        let idRespuesta = UUID().uuidString
        mensajes.append(MensajeDeAgente(id: idRespuesta, rol: .asistente, texto: "Pensando con OpenCode…"))
        respondiendo = true

        let modelo = modeloSeleccionado
        let sesion = sesionID
        let dir = ajustes?.rutaVaultObsidian

        tareaActual = Task { [weak self] in
            guard let self else { return }
            do {
                let resultado = try await self.puerto.enviarMensaje(
                    prompt: texto,
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
            } catch {
                self.actualizarMensaje(
                    id: idRespuesta,
                    texto: "No se pudo ejecutar OpenCode: \(error.localizedDescription)"
                )
            }
            self.respondiendo = false
        }
    }

    public func cancelar() {
        tareaActual?.cancel()
        tareaActual = nil
        respondiendo = false
    }

    public func nuevaConversacion() {
        cancelar()
        sesionID = nil
        mensajes = [
            MensajeDeAgente(
                rol: .asistente,
                texto: "Sesión nueva lista en OpenCode. ¿Qué hacemos?"
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
        Task { await modelo.cargarModelos() }
    }

    public func detener() {
        modelo.cancelar()
    }
}

struct VistaDeAgente: View {
    @Bindable var modelo: ModeloDeAgente
    @FocusState private var campoEnfocado: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            barraSuperior
            areaMensajes
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
                            Text(m)
                            if m == modelo.modeloSeleccionado {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(nombreCortoModelo(modelo.modeloSeleccionado))
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
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
        }
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
                    withAnimation(.easeOut(duration: 0.18)) {
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
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                esUsuario ? Paleta.agente.opacity(0.28) : Paleta.superficie,
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
        completo.components(separatedBy: "/").last ?? completo
    }
}
