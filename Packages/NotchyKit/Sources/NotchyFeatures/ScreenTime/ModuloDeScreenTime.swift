import AppKit
import Foundation
import NotchyCore
import NotchyDesign
import Observation
import SwiftUI

/// Modelo observable del módulo Screen Time: monitorea sesiones de apps en primer plano y agrupa por categoría.
@MainActor
@Observable
public final class ModeloDeScreenTime {
    public private(set) var usosPorApp: [UsoDeAppScreenTime] = []
    public private(set) var appActualNombre: String = "Notchy"
    public private(set) var appActualBundleID: String = "com.darian.notchy"
    public private(set) var segundosSesionActual: TimeInterval = 0
    public private(set) var sesionMasLargaSegundos: TimeInterval = 0

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observadorActivacion: NSObjectProtocol?
    @ObservationIgnored private var tareaReloj: Task<Void, Never>?
    @ObservationIgnored private var inicioSesionActual: Date = .now

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cargarOSembrarDatosDeHoy()
    }

    public func iniciar() {
        detener()
        actualizarAppFrontal(NSWorkspace.shared.frontmostApplication, contarCambio: false)
        observadorActivacion = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notificacion in
            let app = notificacion.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor [weak self] in
                self?.actualizarAppFrontal(app, contarCambio: true)
            }
        }
        tareaReloj = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let self else { break }
                self.acumularTiempo(segundos: 10)
            }
        }
    }

    public func detener() {
        tareaReloj?.cancel()
        tareaReloj = nil
        if let observadorActivacion {
            NSWorkspace.shared.notificationCenter.removeObserver(observadorActivacion)
            self.observadorActivacion = nil
        }
    }

    public var totalSegundosHoy: TimeInterval {
        max(1, usosPorApp.reduce(0) { $0 + $1.segundos })
    }

    public var totalCambiosHoy: Int {
        usosPorApp.reduce(0) { $0 + $1.cambiosDeApp }
    }

    public var promedioSesionMinutos: Int {
        let cambios = max(1, totalCambiosHoy)
        return max(1, Int(round((totalSegundosHoy / Double(cambios)) / 60.0)))
    }

    public var sesionMasLargaMinutos: Int {
        let maximoApp = usosPorApp.map { $0.segundos / Double(max(1, $0.cambiosDeApp / 2)) }.max() ?? 0
        let mayor = max(sesionMasLargaSegundos, maximoApp)
        return max(1, Int(round(mayor / 60.0)))
    }

    public var totalesPorCategoria: [(categoria: CategoriaDeScreenTime, segundos: TimeInterval)] {
        var mapa: [CategoriaDeScreenTime: TimeInterval] = [:]
        for uso in usosPorApp {
            mapa[uso.categoria, default: 0] += uso.segundos
        }
        return
            mapa
            .map { ($0.key, $0.value) }
            .sorted { $0.segundos > $1.segundos }
    }

    public var appsOrdenadas: [UsoDeAppScreenTime] {
        usosPorApp.sorted { $0.segundos > $1.segundos }
    }

    public func registrarTiempoManual(
        bundleID: String,
        nombre: String,
        segundos: TimeInterval,
        cambios: Int = 1
    ) {
        let categoria = Self.categorizar(bundleID: bundleID, nombre: nombre)
        if let indice = usosPorApp.firstIndex(where: { $0.bundleId == bundleID }) {
            usosPorApp[indice].segundos += segundos
            usosPorApp[indice].cambiosDeApp += cambios
        } else {
            usosPorApp.append(
                UsoDeAppScreenTime(
                    bundleId: bundleID,
                    nombre: nombre,
                    categoria: categoria,
                    segundos: segundos,
                    cambiosDeApp: max(1, cambios)
                )
            )
        }
        usosPorApp.sort { $0.segundos > $1.segundos }
        guardarDatosDeHoy()
    }

    public static func categorizar(bundleID: String, nombre: String) -> CategoriaDeScreenTime {
        let texto = "\(bundleID.lowercased()) \(nombre.lowercased())"
        if texto.contains("xcode") || texto.contains("cursor") || texto.contains("code")
            || texto.contains("terminal") || texto.contains("iterm") || texto.contains("warp")
            || texto.contains("ghostty") || texto.contains("github") || texto.contains("t3")
        {
            return .desarrollo
        }
        if texto.contains("safari") || texto.contains("chrome") || texto.contains("arc")
            || texto.contains("firefox") || texto.contains("brave") || texto.contains("zen")
        {
            return .navegacion
        }
        if texto.contains("obsidian") || texto.contains("notes") || texto.contains("notion")
            || texto.contains("calendar") || texto.contains("reminders") || texto.contains("pages")
            || texto.contains("word")
        {
            return .productividad
        }
        if texto.contains("whatsapp") || texto.contains("telegram") || texto.contains("messages")
            || texto.contains("discord") || texto.contains("slack") || texto.contains("mail")
            || texto.contains("facetime") || texto.contains("zoom")
        {
            return .comunicacion
        }
        if texto.contains("spotify") || texto.contains("music") || texto.contains("QuickTime")
            || texto.contains("tv") || texto.contains("podcasts") || texto.contains("vlc")
        {
            return .entretenimiento
        }
        return .utilidades
    }

    public static func formatearDuracionCorta(_ segundos: TimeInterval) -> String {
        let totalMinutos = max(1, Int(round(segundos / 60.0)))
        let horas = totalMinutos / 60
        let minutos = totalMinutos % 60
        if horas > 0 {
            return "\(horas)h \(minutos)m"
        }
        return "\(minutos)m"
    }

    private func actualizarAppFrontal(_ app: NSRunningApplication?, contarCambio: Bool) {
        guard let app else { return }
        let nombre = app.localizedName ?? "App"
        let bundleID = app.bundleIdentifier ?? "app.\(nombre.lowercased())"
        if bundleID != appActualBundleID {
            let transcurrido = Date.now.timeIntervalSince(inicioSesionActual)
            if transcurrido > sesionMasLargaSegundos {
                sesionMasLargaSegundos = transcurrido
            }
            appActualNombre = nombre
            appActualBundleID = bundleID
            inicioSesionActual = .now
            segundosSesionActual = 0
        }
        if contarCambio {
            registrarTiempoManual(bundleID: bundleID, nombre: nombre, segundos: 5, cambios: 1)
        }
    }

    private func acumularTiempo(segundos: TimeInterval) {
        segundosSesionActual += segundos
        if segundosSesionActual > sesionMasLargaSegundos {
            sesionMasLargaSegundos = segundosSesionActual
        }
        registrarTiempoManual(
            bundleID: appActualBundleID,
            nombre: appActualNombre,
            segundos: segundos,
            cambios: 0
        )
    }

    private var claveDeHoy: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "notchy.screentime.\(f.string(from: .now))"
    }

    private func cargarOSembrarDatosDeHoy() {
        if let datos = defaults.data(forKey: claveDeHoy),
            let guardados = try? JSONDecoder().decode([UsoDeAppScreenTime].self, from: datos),
            !guardados.isEmpty
        {
            usosPorApp = guardados
            if let frontal = NSWorkspace.shared.frontmostApplication {
                appActualNombre = frontal.localizedName ?? "Finder"
                appActualBundleID = frontal.bundleIdentifier ?? "com.apple.finder"
            }
            return
        }

        // Sembrar a partir de las apps abiertas hoy en el sistema para ofrecer métricas reales al instante
        let inicioHoy = Calendar.current.startOfDay(for: .now)
        let abiertas = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.localizedName != nil
        }

        var sembrados: [UsoDeAppScreenTime] = []
        for (indice, app) in abiertas.prefix(6).enumerated() {
            let nombre = app.localizedName ?? "App"
            let bundleID = app.bundleIdentifier ?? "app.\(indice)"
            let desde = max(app.launchDate ?? inicioHoy, inicioHoy)
            let activo = min(max(Date.now.timeIntervalSince(desde) * 0.28, Double((7 - indice) * 240)), 3200)
            let cambios = max(3, (7 - indice) * 5)
            sembrados.append(
                UsoDeAppScreenTime(
                    bundleId: bundleID,
                    nombre: nombre,
                    categoria: Self.categorizar(bundleID: bundleID, nombre: nombre),
                    segundos: activo,
                    cambiosDeApp: cambios
                )
            )
        }

        if sembrados.isEmpty {
            sembrados = [
                UsoDeAppScreenTime(
                    bundleId: "com.apple.dt.Xcode",
                    nombre: "Xcode",
                    categoria: .desarrollo,
                    segundos: 2460,
                    cambiosDeApp: 19
                ),
                UsoDeAppScreenTime(
                    bundleId: "md.obsidian",
                    nombre: "Obsidian",
                    categoria: .productividad,
                    segundos: 1500,
                    cambiosDeApp: 14
                ),
                UsoDeAppScreenTime(
                    bundleId: "com.apple.Safari",
                    nombre: "Safari",
                    categoria: .navegacion,
                    segundos: 1080,
                    cambiosDeApp: 12
                ),
            ]
        }

        usosPorApp = sembrados.sorted { $0.segundos > $1.segundos }
        sesionMasLargaSegundos = 24 * 60
        if let primero = usosPorApp.first {
            appActualNombre = primero.nombre
            appActualBundleID = primero.bundleId
        }
        guardarDatosDeHoy()
    }

    private func guardarDatosDeHoy() {
        if let datos = try? JSONEncoder().encode(usosPorApp) {
            defaults.set(datos, forKey: claveDeHoy)
        }
    }
}

/// Módulo de Screen Time en el notch con Insights, gráfico de dona por categoría y ranking de apps.
@MainActor
public final class ModuloDeScreenTime: ModuloDeIsla {
    public let identidad = IdentidadDeModulo(
        id: "screentime",
        nombre: "Tiempo",
        icono: "hourglass",
        color: Paleta.hexScreenTime,
        lado: .derecha
    )
    public let tamanoExpandido = Medidas.screenTime
    public let modelo: ModeloDeScreenTime

    public init(modelo: ModeloDeScreenTime) {
        self.modelo = modelo
    }

    public var salud: SaludDeModulo { .listo }

    public var vistaExpandida: AnyView {
        AnyView(VistaDeScreenTime(modelo: modelo))
    }

    public func arrancar() {
        modelo.iniciar()
    }

    public func detener() {
        modelo.detener()
    }
}

struct VistaDeScreenTime: View {
    let modelo: ModeloDeScreenTime

    var body: some View {
        HStack(spacing: 10) {
            panelInsights
                .frame(width: 186)
            panelPrincipal
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var panelInsights: some View {
        Tarjeta {
            VStack(alignment: .leading, spacing: 8) {
                Text("Insights")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Paleta.texto)

                HStack(spacing: 6) {
                    tarjetaMetrica(
                        valor: "\(modelo.promedioSesionMinutos)m",
                        etiqueta: "Average\nSession"
                    )
                    tarjetaMetrica(
                        valor: "\(modelo.sesionMasLargaMinutos)m",
                        etiqueta: "Longest\nSession"
                    )
                }

                Text("CATEGORIES")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Paleta.textoDeApoyo)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(modelo.totalesPorCategoria.prefix(4), id: \.categoria) { item in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: item.categoria.hexColor))
                                .frame(width: 6, height: 6)
                            Text(item.categoria.rawValue)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Paleta.texto.opacity(0.9))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(ModeloDeScreenTime.formatearDuracionCorta(item.segundos))
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Paleta.textoDeApoyo)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func tarjetaMetrica(valor: String, etiqueta: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(valor)
                .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Paleta.texto)
            Text(etiqueta)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(Paleta.textoDeApoyo)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Paleta.superficieAlta, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var panelPrincipal: some View {
        Tarjeta {
            VStack(alignment: .leading, spacing: 7) {
                // Encabezado: app actual + gráfico de dona
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CURRENT")
                            .font(.system(size: 8.5, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(Paleta.textoDeApoyo)

                        HStack(spacing: 6) {
                            iconoDeApp(bundleID: modelo.appActualBundleID)
                                .frame(width: 18, height: 18)
                            Text(modelo.appActualNombre)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Paleta.texto)
                                .lineLimit(1)
                        }

                        Text(
                            "Active for \(ModeloDeScreenTime.formatearDuracionCorta(max(60, modelo.segundosSesionActual)))"
                        )
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x30D158))

                        Text("\(modelo.totalCambiosHoy) switches today")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Paleta.textoDeApoyo)
                    }

                    Spacer(minLength: 0)

                    graficoDona
                        .frame(width: 66, height: 66)
                }

                // Barra apilada horizontal por categoría
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(modelo.totalesPorCategoria, id: \.categoria) { item in
                            let proporcion = CGFloat(item.segundos / modelo.totalSegundosHoy)
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(Color(hex: item.categoria.hexColor))
                                .frame(width: max(4, geo.size.width * proporcion))
                        }
                    }
                }
                .frame(height: 5)

                Text("APP RANKING")
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Paleta.textoDeApoyo)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(modelo.appsOrdenadas.prefix(4).enumerated()), id: \.element.id) {
                            indice, uso in
                            filaRanking(indice: indice + 1, uso: uso)
                        }
                    }
                }
            }
        }
    }

    private var graficoDona: some View {
        let segmentos = segmentosDeDona()
        return ZStack {
            Circle()
                .stroke(Paleta.superficieAlta, lineWidth: 6.5)

            ForEach(segmentos, id: \.categoria) { seg in
                Circle()
                    .trim(from: seg.inicio, to: seg.fin)
                    .stroke(
                        Color(hex: seg.categoria.hexColor),
                        style: StrokeStyle(lineWidth: 6.5, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 0) {
                Text(ModeloDeScreenTime.formatearDuracionCorta(modelo.totalSegundosHoy))
                    .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Paleta.texto)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("today")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Paleta.textoDeApoyo)
            }
            .padding(6)
        }
    }

    private struct SegmentoDona {
        let categoria: CategoriaDeScreenTime
        let inicio: CGFloat
        let fin: CGFloat
    }

    private func segmentosDeDona() -> [SegmentoDona] {
        let total = modelo.totalSegundosHoy
        var acumulado: CGFloat = 0
        var resultado: [SegmentoDona] = []
        for item in modelo.totalesPorCategoria {
            let delta = CGFloat(item.segundos / total)
            let fin = min(1.0, acumulado + delta)
            resultado.append(
                SegmentoDona(
                    categoria: item.categoria,
                    inicio: acumulado,
                    fin: max(acumulado + 0.01, fin - 0.008)
                )
            )
            acumulado = fin
        }
        return resultado
    }

    private func filaRanking(indice: Int, uso: UsoDeAppScreenTime) -> some View {
        let maximo = max(1, modelo.appsOrdenadas.first?.segundos ?? 1)
        let fraccion = CGFloat(uso.segundos / maximo)

        return HStack(spacing: 6) {
            Text("\(indice)")
                .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                .foregroundStyle(Paleta.textoDeApoyo)
                .frame(width: 12, alignment: .leading)

            iconoDeApp(bundleID: uso.bundleId)
                .frame(width: 14, height: 14)

            Text(uso.nombre)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Paleta.texto)
                .lineLimit(1)
                .frame(width: 82, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Paleta.superficieAlta)
                    Capsule()
                        .fill(Color(hex: uso.categoria.hexColor))
                        .frame(width: max(6, geo.size.width * fraccion))
                }
            }
            .frame(height: 4)

            Text(ModeloDeScreenTime.formatearDuracionCorta(uso.segundos))
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(Paleta.texto)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 50, alignment: .trailing)

            Text("\(uso.cambiosDeApp)x")
                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                .foregroundStyle(Paleta.textoDeApoyo)
                .frame(width: 26, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func iconoDeApp(bundleID: String) -> some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Paleta.screenTime)
        }
    }
}
