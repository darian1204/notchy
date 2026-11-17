import AppKit
import Foundation
import NotchyCore
import NotchyDesign
import Observation
import SwiftUI

/// Modelo observable del módulo de Notificaciones Recientes en el notch.
@MainActor
@Observable
public final class ModeloDeNotificaciones {
    public private(set) var notificaciones: [NotificacionReciente] = []
    public var appFiltro: String?

    /// `false` cuando falta Acceso total al disco para leer las notificaciones de macOS.
    public private(set) var accesoAlSistema: Bool = true

    @ObservationIgnored private let bus: BusDeEventos?
    @ObservationIgnored private let sistema: (any PuertoDeNotificacionesDelSistema)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var tareaEventos: Task<Void, Never>?
    @ObservationIgnored private var tareaSistema: Task<Void, Never>?
    @ObservationIgnored private var descartadas: Set<String>
    @ObservationIgnored private var limpiadoHasta: Date
    @ObservationIgnored private static let claveGuardadas = "notchy.notificaciones.recientes"
    @ObservationIgnored private static let claveDescartadas = "notchy.notificaciones.descartadas"
    @ObservationIgnored private static let claveLimpiadoHasta = "notchy.notificaciones.limpiadoHasta"
    @ObservationIgnored private static let limite = 50

    public init(
        bus: BusDeEventos? = nil,
        sistema: (any PuertoDeNotificacionesDelSistema)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.bus = bus
        self.sistema = sistema
        self.defaults = defaults
        self.descartadas = Set(defaults.stringArray(forKey: Self.claveDescartadas) ?? [])
        self.limpiadoHasta = defaults.object(forKey: Self.claveLimpiadoHasta) as? Date ?? .distantPast
        if let datos = defaults.data(forKey: Self.claveGuardadas),
            let guardadas = try? JSONDecoder().decode([NotificacionReciente].self, from: datos)
        {
            // Quita los ejemplos de demostración que guardaban versiones anteriores.
            let ejemplos = Set(Self.notificacionesIniciales().map(\.titulo))
            self.notificaciones = guardadas.filter { !ejemplos.contains($0.titulo) }
        } else {
            self.notificaciones = []
        }
    }

    public var noLeidas: Int {
        notificaciones.filter { !$0.leida }.count
    }

    public var appsDisponibles: [String] {
        Array(Set(notificaciones.map(\.nombreApp))).sorted()
    }

    public var notificacionesFiltradas: [NotificacionReciente] {
        guard let appFiltro else { return notificaciones }
        return notificaciones.filter { $0.nombreApp == appFiltro }
    }

    public func iniciar() {
        detener()
        iniciarLecturaDelSistema()
        guard let bus else { return }
        tareaEventos = Task { [weak self] in
            await withTaskGroup(of: Void.self) { grupo in
                grupo.addTask {
                    let flujo = await bus.suscribir(a: ReunionProximaDetectada.self)
                    for await aviso in flujo {
                        guard !Task.isCancelled else { break }
                        await MainActor.run {
                            self?.registrar(
                                NotificacionReciente(
                                    bundleId: "com.apple.iCal",
                                    nombreApp: "Calendar",
                                    titulo: aviso.evento.titulo,
                                    cuerpo:
                                        "Comienza en \(aviso.minutosRestantes) min · Reunión programada en tu calendario."
                                )
                            )
                        }
                    }
                }
                grupo.addTask {
                    let flujo = await bus.suscribir(a: ArchivoAirDropDetectado.self)
                    for await recibido in flujo {
                        guard !Task.isCancelled else { break }
                        await MainActor.run {
                            self?.registrar(
                                NotificacionReciente(
                                    bundleId: "com.apple.finder",
                                    nombreApp: "AirDrop",
                                    titulo: recibido.archivo.nombre,
                                    cuerpo:
                                        "Archivo recibido en Descargas (\(ByteCountFormatter.string(fromByteCount: recibido.archivo.bytes, countStyle: .file)))."
                                )
                            )
                        }
                    }
                }
            }
        }
    }

    public func detener() {
        tareaEventos?.cancel()
        tareaEventos = nil
        tareaSistema?.cancel()
        tareaSistema = nil
    }

    // MARK: Notificaciones de macOS

    private func iniciarLecturaDelSistema() {
        guard sistema != nil else { return }
        tareaSistema = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sincronizarConElSistema()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    /// Mezcla lo que entregó macOS con lo propio de Notchy, conservando leídas y descartadas.
    public func sincronizarConElSistema() async {
        guard let sistema else { return }
        guard sistema.tieneAcceso() else {
            accesoAlSistema = false
            return
        }
        do {
            let delSistema = try await sistema.recientes(limite: Self.limite)
            accesoAlSistema = true
            let leidas = Set(notificaciones.filter(\.leida).map(\.id))
            let nuevas =
                delSistema
                .filter { !descartadas.contains($0.id) && $0.fecha > limpiadoHasta }
                .map { item -> NotificacionReciente in
                    var copia = item
                    copia.leida = leidas.contains(item.id)
                    return copia
                }
            let propias = notificaciones.filter { !$0.id.hasPrefix("nc-") }
            let mezcla = Array((nuevas + propias).sorted { $0.fecha > $1.fecha }.prefix(Self.limite))
            if mezcla != notificaciones {
                notificaciones = mezcla
                guardar()
            }
        } catch {
            accesoAlSistema = false
        }
    }

    public func abrirAjustesDeAccesoAlDisco() {
        let appInstalada = URL(fileURLWithPath: "/Applications/Notchy.app")
        let rutaApp =
            FileManager.default.fileExists(atPath: appInstalada.path)
            ? appInstalada
            : Bundle.main.bundleURL
        if rutaApp.pathExtension == "app" {
            NSWorkspace.shared.activateFileViewerSelecting([rutaApp])
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    public func registrar(_ nueva: NotificacionReciente) {
        notificaciones.removeAll { $0.titulo == nueva.titulo && $0.nombreApp == nueva.nombreApp }
        notificaciones.insert(nueva, at: 0)
        if notificaciones.count > 30 {
            notificaciones = Array(notificaciones.prefix(30))
        }
        guardar()
    }

    public func descartar(_ id: String) {
        notificaciones.removeAll { $0.id == id }
        if id.hasPrefix("nc-") {
            descartadas.insert(id)
            defaults.set(Array(descartadas.suffix(500)), forKey: Self.claveDescartadas)
        }
        guardar()
    }

    public func marcarLeida(_ id: String) {
        if let idx = notificaciones.firstIndex(where: { $0.id == id }) {
            notificaciones[idx].leida = true
            guardar()
        }
    }

    public func limpiarTodas() {
        notificaciones.removeAll()
        limpiadoHasta = .now
        defaults.set(limpiadoHasta, forKey: Self.claveLimpiadoHasta)
        descartadas.removeAll()
        defaults.removeObject(forKey: Self.claveDescartadas)
        guardar()
    }

    public func abrirApp(de item: NotificacionReciente) {
        marcarLeida(item.id)
        if let urlApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.bundleId) {
            NSWorkspace.shared.openApplication(
                at: urlApp,
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
    }

    public func copiarTexto(de item: NotificacionReciente) {
        marcarLeida(item.id)
        let pasta = NSPasteboard.general
        pasta.clearContents()
        pasta.setString("\(item.titulo)\n\(item.cuerpo)", forType: .string)
    }

    private func guardar() {
        if let datos = try? JSONEncoder().encode(notificaciones) {
            defaults.set(datos, forKey: Self.claveGuardadas)
        }
    }

    public static func notificacionesIniciales() -> [NotificacionReciente] {
        let ahora = Date.now
        return [
            NotificacionReciente(
                bundleId: "md.obsidian",
                nombreApp: "Obsidian",
                titulo: "Vault sincronizado · 00_Inbox/Notchy Inbox.md",
                cuerpo: "Notas rápidas conectadas con Notchy listas para editar desde el Home.",
                fecha: ahora.addingTimeInterval(-14 * 60),
                leida: false
            ),
            NotificacionReciente(
                bundleId: "com.apple.iCal",
                nombreApp: "Calendar",
                titulo: "Revisión de proyecto · Diseño y Arquitectura",
                cuerpo: "Agenda del día sincronizada con EventKit y avisos Dynamic Island 5 min antes.",
                fecha: ahora.addingTimeInterval(-51 * 60),
                leida: false
            ),
            NotificacionReciente(
                bundleId: "com.apple.mail",
                nombreApp: "Mail",
                titulo: "Resumen semanal de actividad",
                cuerpo: "Tus suscripciones e hilos recientes de esta semana están al día.",
                fecha: ahora.addingTimeInterval(-75 * 60),
                leida: false
            ),
        ]
    }
}

/// Módulo de Notificaciones Recientes en el notch (`bell.fill`).
@MainActor
public final class ModuloDeNotificaciones: ModuloDeIsla {
    public let identidad = IdentidadDeModulo(
        id: "notificaciones",
        nombre: "Alertas",
        icono: "bell.fill",
        color: Paleta.hexNotificaciones,
        lado: .izquierda
    )
    public let tamanoExpandido = Medidas.notificaciones
    public let modelo: ModeloDeNotificaciones

    public init(modelo: ModeloDeNotificaciones) {
        self.modelo = modelo
    }

    public var salud: SaludDeModulo {
        modelo.accesoAlSistema ? .listo : .faltaPermiso("Acceso total al disco")
    }

    public var vistaExpandida: AnyView {
        AnyView(VistaDeNotificaciones(modelo: modelo))
    }

    public func arrancar() {
        modelo.iniciar()
    }

    public func detener() {
        modelo.detener()
    }
}

struct VistaDeNotificaciones: View {
    @Bindable var modelo: ModeloDeNotificaciones

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            encabezado
            if !modelo.accesoAlSistema {
                avisoDeAccesoAlDisco
            }
            if modelo.notificacionesFiltradas.isEmpty {
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Paleta.textoDeApoyo)
                        Text("Sin notificaciones pendientes")
                            .textoDeApoyo()
                    }
                    Spacer()
                }
                Spacer(minLength: 0)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(modelo.notificacionesFiltradas) { item in
                            filaNotificacion(item)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var avisoDeAccesoAlDisco: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Paleta.notificaciones)
            Text("Para ver todas las notificaciones de la Mac, da Acceso total al disco a Notchy.")
                .font(.system(size: 10.5))
                .foregroundStyle(Paleta.textoDeApoyo)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button("Abrir Ajustes") { modelo.abrirAjustesDeAccesoAlDisco() }
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Paleta.notificaciones, in: Capsule())
                .buttonStyle(.plain)
        }
        .padding(8)
        .background(Paleta.superficie, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var encabezado: some View {
        HStack(spacing: 8) {
            Text("Notifications")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Paleta.texto)

            if modelo.noLeidas > 0 {
                Text("\(modelo.noLeidas)")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(Paleta.texto)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Paleta.superficieAlta, in: Capsule())
            }

            Spacer(minLength: 0)

            Menu {
                Button("All Apps") {
                    modelo.appFiltro = nil
                }
                Divider()
                ForEach(modelo.appsDisponibles, id: \.self) { app in
                    Button(app) {
                        modelo.appFiltro = app
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text(modelo.appFiltro ?? "Apps")
                        .font(.system(size: 10.5, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .bold))
                }
                .foregroundStyle(Paleta.texto)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Paleta.superficie, in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                modelo.limpiarTodas()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Paleta.textoDeApoyo)
            }
            .buttonStyle(.plain)
            .help("Limpiar todas las notificaciones")
        }
    }

    private func filaNotificacion(_ item: NotificacionReciente) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                iconoApp(bundleId: item.bundleId)
                    .frame(width: 26, height: 26)
                if !item.leida {
                    Circle()
                        .fill(Paleta.notificaciones)
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.nombreApp)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Paleta.textoDeApoyo)
                    Spacer(minLength: 0)
                    Text(tiempoRelativo(desde: item.fecha))
                        .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(Paleta.textoDeApoyo.opacity(0.75))
                }

                Text(item.titulo)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Paleta.texto)
                    .lineLimit(1)

                Text(item.cuerpo)
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(Paleta.textoDeApoyo)
                    .lineLimit(2)
            }

            HStack(spacing: 5) {
                botonAccion(icono: "arrow.turn.up.left", ayuda: "Abrir \(item.nombreApp)") {
                    modelo.abrirApp(de: item)
                }
                botonAccion(icono: "doc.on.doc", ayuda: "Copiar texto") {
                    modelo.copiarTexto(de: item)
                }
                botonAccion(icono: "xmark", ayuda: "Descartar") {
                    modelo.descartar(item.id)
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Paleta.superficie, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Paleta.borde.opacity(0.6), lineWidth: 1)
        )
    }

    private func botonAccion(
        icono: String,
        ayuda: String,
        accion: @escaping () -> Void
    ) -> some View {
        Button(action: accion) {
            Image(systemName: icono)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Paleta.textoDeApoyo)
                .frame(width: 22, height: 22)
                .background(Paleta.superficieAlta, in: Circle())
        }
        .buttonStyle(.plain)
        .help(ayuda)
    }

    @ViewBuilder
    private func iconoApp(bundleId: String) -> some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
        } else {
            Image(systemName: "app.badge.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Paleta.notificaciones)
        }
    }

    private func tiempoRelativo(desde fecha: Date) -> String {
        let seg = max(1, Int(Date.now.timeIntervalSince(fecha)))
        if seg < 60 { return "now" }
        let min = seg / 60
        if min < 60 { return "\(min)m ago" }
        let h = min / 60
        if h < 24 { return "\(h)h ago" }
        return "\(h / 24)d ago"
    }
}
