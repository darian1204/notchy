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
    @ObservationIgnored private let ahora: @MainActor () -> Date
    @ObservationIgnored private let segundosSinUsar: @MainActor () -> TimeInterval
    @ObservationIgnored private let hayVideo: @MainActor () -> Bool
    /// Día al que pertenecen `usosPorApp`. Al cambiar de día se empieza de cero.
    @ObservationIgnored private var diaCargado = ""
    @ObservationIgnored private var ultimoTic: Date?
    /// Hay cambios sin escribir en disco. Se guardan una vez por minuto, no en cada tic.
    @ObservationIgnored private var cambiosSinGuardar = false
    @ObservationIgnored private var ultimoGuardado: Date = .distantPast
    static let intervaloDeGuardado: TimeInterval = 60

    /// Cada cuánto se suma tiempo a la app del frente.
    static let intervaloDeTic: TimeInterval = 10
    /// Sin teclado ni ratón por más de esto, no se cuenta (te fuiste), salvo que haya un video
    /// reproduciéndose.
    static let limiteDeInactividad: TimeInterval = 5 * 60
    /// Apps que no son uso real: la pantalla de bloqueo y el protector de pantalla.
    static let appsQueNoCuentan: Set<String> = ["com.apple.loginwindow", "com.apple.ScreenSaver.Engine"]

    public init(
        defaults: UserDefaults = .standard,
        ahora: @escaping @MainActor () -> Date = { .now },
        segundosSinUsar: @escaping @MainActor () -> TimeInterval = {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        },
        hayVideo: @escaping @MainActor () -> Bool = { false }
    ) {
        self.defaults = defaults
        self.ahora = ahora
        self.segundosSinUsar = segundosSinUsar
        self.hayVideo = hayVideo
        cargarDatosDeHoy()
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
                try? await Task.sleep(for: .seconds(Self.intervaloDeTic))
                guard !Task.isCancelled, let self else { break }
                self.tic()
            }
        }
    }

    public func detener() {
        guardarSiHayCambios(forzar: true)
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

    /// Suma tiempo a mano y lo guarda al momento.
    public func registrarTiempoManual(
        bundleID: String,
        nombre: String,
        segundos: TimeInterval,
        cambios: Int = 1
    ) {
        sumar(bundleID: bundleID, nombre: nombre, segundos: segundos, cambios: cambios)
        guardarSiHayCambios(forzar: true)
    }

    private func sumar(bundleID: String, nombre: String, segundos: TimeInterval, cambios: Int) {
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
        cambiosSinGuardar = true
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
            // La sesión más larga se mide con el tiempo contado, no con el reloj: así no entra el
            // rato con la Mac bloqueada o dormida.
            if segundosSesionActual > sesionMasLargaSegundos {
                sesionMasLargaSegundos = segundosSesionActual
            }
            appActualNombre = nombre
            appActualBundleID = bundleID
            inicioSesionActual = ahora()
            segundosSesionActual = 0
        }
        // Un cambio de app no es tiempo de uso: antes sumaba 5 s por cambio.
        if contarCambio, !Self.appsQueNoCuentan.contains(bundleID) {
            asegurarDiaActual()
            sumar(bundleID: bundleID, nombre: nombre, segundos: 0, cambios: 1)
            guardarSiHayCambios()
        }
    }

    /// Suma el tiempo real desde el último tic, solo si la Mac está en uso.
    public func tic() {
        let momento = ahora()
        defer { ultimoTic = momento }
        asegurarDiaActual()
        guard let ultimoTic else { return }
        let transcurrido = momento.timeIntervalSince(ultimoTic)
        // Un hueco largo es que la Mac durmió: ese tiempo no se usó.
        guard transcurrido > 0, transcurrido <= Self.intervaloDeTic * 3 else { return }
        guard segundosSinUsar() < Self.limiteDeInactividad || hayVideo() else { return }
        guard !Self.appsQueNoCuentan.contains(appActualBundleID) else { return }
        acumularTiempo(segundos: min(transcurrido, Self.intervaloDeTic))
    }

    private func acumularTiempo(segundos: TimeInterval) {
        segundosSesionActual += segundos
        if segundosSesionActual > sesionMasLargaSegundos {
            sesionMasLargaSegundos = segundosSesionActual
        }
        sumar(bundleID: appActualBundleID, nombre: appActualNombre, segundos: segundos, cambios: 0)
        guardarSiHayCambios()
    }

    private var claveDeHoy: String { "notchy.screentime." + Self.dia(de: ahora()) }

    static func dia(de fecha: Date) -> String {
        let partes = Calendar.current.dateComponents([.year, .month, .day], from: fecha)
        return String(format: "%04d-%02d-%02d", partes.year ?? 0, partes.month ?? 0, partes.day ?? 0)
    }

    /// Si ya es otro día, cierra el anterior en su propia fecha y empieza de cero.
    private func asegurarDiaActual() {
        guard Self.dia(de: ahora()) != diaCargado else { return }
        guardarSiHayCambios(forzar: true)
        cargarDatosDeHoy()
    }

    /// Lee lo guardado de hoy. Descarta registros imposibles (más tiempo que el que lleva el día), que
    /// dejó la versión que arrastraba los totales de un día a otro. No inventa datos.
    private func cargarDatosDeHoy() {
        diaCargado = Self.dia(de: ahora())
        cambiosSinGuardar = false
        segundosSesionActual = 0
        sesionMasLargaSegundos = 0
        usosPorApp = []
        if let frontal = NSWorkspace.shared.frontmostApplication {
            appActualNombre = frontal.localizedName ?? "App"
            appActualBundleID = frontal.bundleIdentifier ?? "app.desconocida"
        }
        guard let datos = defaults.data(forKey: claveDeHoy),
            let guardados = try? JSONDecoder().decode([UsoDeAppScreenTime].self, from: datos)
        else { return }
        let reales = guardados.filter { !Self.appsQueNoCuentan.contains($0.bundleId) }
        let total = reales.reduce(0) { $0 + $1.segundos }
        let llevaElDia = ahora().timeIntervalSince(Calendar.current.startOfDay(for: ahora()))
        guard total <= llevaElDia + 60 else {
            defaults.removeObject(forKey: claveDeHoy)
            return
        }
        usosPorApp = reales.sorted { $0.segundos > $1.segundos }
    }

    /// Escribe en disco como mucho una vez por minuto; `forzar` escribe ya (al cerrar o cambiar de día).
    /// Siempre en la fecha de los datos cargados, no en la de ahora.
    private func guardarSiHayCambios(forzar: Bool = false) {
        guard cambiosSinGuardar, !diaCargado.isEmpty else { return }
        let momento = ahora()
        guard forzar || momento.timeIntervalSince(ultimoGuardado) >= Self.intervaloDeGuardado else { return }
        if let datos = try? JSONEncoder().encode(usosPorApp) {
            defaults.set(datos, forKey: "notchy.screentime." + diaCargado)
        }
        cambiosSinGuardar = false
        ultimoGuardado = momento
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
