import Foundation
import NotchyCore
import NotchyDesign
import Observation
import SwiftUI

/// Modelo observable del módulo de Clima (Open-Meteo en vivo, sin API key).
@MainActor
@Observable
public final class ModeloDeClima {
    public private(set) var estado: EstadoDelClima
    public var usarFahrenheit: Bool {
        didSet { defaults.set(usarFahrenheit, forKey: Self.claveFahrenheit) }
    }
    public private(set) var cargando = false
    public var editandoCiudad = false
    public var consultaCiudad = ""

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var tareaRefresco: Task<Void, Never>?
    @ObservationIgnored private static let claveCache = "notchy.clima.cache"
    @ObservationIgnored private static let claveFahrenheit = "notchy.clima.fahrenheit"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.usarFahrenheit = defaults.bool(forKey: Self.claveFahrenheit)
        if let datos = defaults.data(forKey: Self.claveCache),
            let guardado = try? JSONDecoder().decode(EstadoDelClima.self, from: datos)
        {
            self.estado = guardado
        } else {
            self.estado = Self.estadoInicialPorDefecto()
        }
    }

    public func iniciar() {
        detener()
        tareaRefresco = Task { [weak self] in
            await self?.actualizarClima()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(900))
                guard !Task.isCancelled else { break }
                await self?.actualizarClima()
            }
        }
    }

    public func detener() {
        tareaRefresco?.cancel()
        tareaRefresco = nil
    }

    public func formatearTemp(_ celsius: Double) -> String {
        let valor = usarFahrenheit ? (celsius * 9.0 / 5.0 + 32.0) : celsius
        let unidad = usarFahrenheit ? "°F" : "°C"
        return "\(Int(valor.rounded()))\(unidad)"
    }

    public func buscarYCambiarCiudad() async {
        let nombre = consultaCiudad.trimmingCharacters(in: .whitespacesAndNewlines)
        editandoCiudad = false
        guard !nombre.isEmpty else { return }
        guard let codificado = nombre.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(
                string:
                    "https://geocoding-api.open-meteo.com/v1/search?name=\(codificado)&count=1&language=es&format=json"
            )
        else { return }
        cargando = true
        defer { cargando = false }
        do {
            let (datos, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: datos) as? [String: Any],
                let resultados = json["results"] as? [[String: Any]],
                let primero = resultados.first,
                let lat = primero["latitude"] as? Double,
                let lon = primero["longitude"] as? Double
            {
                let ciudad = (primero["name"] as? String) ?? nombre
                await descargarOpenMeteo(ciudad: ciudad, latitud: lat, longitud: lon)
            }
        } catch {
            // Conserva el último pronóstico válido
        }
    }

    public func actualizarClima() async {
        await descargarOpenMeteo(
            ciudad: estado.ciudad,
            latitud: estado.latitud,
            longitud: estado.longitud
        )
    }

    private func descargarOpenMeteo(ciudad: String, latitud: Double, longitud: Double) async {
        let urlString =
            "https://api.open-meteo.com/v1/forecast?latitude=\(latitud)&longitude=\(longitud)"
            + "&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,surface_pressure,wind_speed_10m"
            + "&hourly=temperature_2m,weather_code,is_day,precipitation_probability"
            + "&daily=temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max"
            + "&timezone=auto&forecast_days=2"
        guard let url = URL(string: urlString) else { return }
        cargando = true
        defer { cargando = false }
        do {
            let (datos, respuesta) = try await URLSession.shared.data(from: url)
            guard let http = respuesta as? HTTPURLResponse, http.statusCode == 200,
                let raiz = try JSONSerialization.jsonObject(with: datos) as? [String: Any],
                let actual = raiz["current"] as? [String: Any]
            else { return }

            let tempC = actual["temperature_2m"] as? Double ?? estado.temperaturaC
            let sensacionC = actual["apparent_temperature"] as? Double ?? tempC
            let humedad = actual["relative_humidity_2m"] as? Int ?? 48
            let viento = actual["wind_speed_10m"] as? Double ?? 8.0
            let presion = Int((actual["surface_pressure"] as? Double ?? 1013.0).rounded())
            let wmo = actual["weather_code"] as? Int ?? 0
            let esDeDia = (actual["is_day"] as? Int ?? 1) == 1

            let diario = raiz["daily"] as? [String: Any]
            let maxC = (diario?["temperature_2m_max"] as? [Double])?.first ?? (tempC + 5)
            let minC = (diario?["temperature_2m_min"] as? [Double])?.first ?? (tempC - 5)
            let uvMax = (diario?["uv_index_max"] as? [Double])?.first ?? 4.0
            let amanecerCrudo = (diario?["sunrise"] as? [String])?.first ?? "T06:18"
            let atardecerCrudo = (diario?["sunset"] as? [String])?.first ?? "T19:42"
            let amanecer = Self.extraerHoraHHMM(amanecerCrudo)
            let atardecer = Self.extraerHoraHHMM(atardecerCrudo)

            let horario = raiz["hourly"] as? [String: Any]
            let tiemposHora = horario?["time"] as? [String] ?? []
            let tempsHora = horario?["temperature_2m"] as? [Double] ?? []
            let codigosHora = horario?["weather_code"] as? [Int] ?? []
            let diasHora = horario?["is_day"] as? [Int] ?? []
            let lluviaHora = horario?["precipitation_probability"] as? [Int] ?? []

            let horaActualISO = (actual["time"] as? String) ?? ""
            let prefijoHoraActual = String(horaActualISO.prefix(13))
            let indiceInicio = tiemposHora.firstIndex(where: { $0.hasPrefix(prefijoHoraActual) }) ?? 0
            let probLluvia = indiceInicio < lluviaHora.count ? lluviaHora[indiceInicio] : 0

            var tiraHoraria: [PronosticoPorHora] = []
            let limite = min(tiemposHora.count, indiceInicio + 13)
            for idx in indiceInicio..<limite {
                let etiqueta = Self.extraerHoraCorta(tiemposHora[idx])
                let t = idx < tempsHora.count ? tempsHora[idx] : tempC
                let c = idx < codigosHora.count ? codigosHora[idx] : wmo
                let d = idx < diasHora.count ? (diasHora[idx] == 1) : esDeDia
                tiraHoraria.append(
                    PronosticoPorHora(
                        id: "\(idx)-\(etiqueta)",
                        etiquetaHora: etiqueta,
                        codigoWMO: c,
                        esDeDia: d,
                        temperaturaC: t
                    )
                )
            }

            let nuevo = EstadoDelClima(
                ciudad: ciudad,
                latitud: latitud,
                longitud: longitud,
                temperaturaC: tempC,
                sensacionC: sensacionC,
                maximaC: maxC,
                minimaC: minC,
                humedadPorcentaje: humedad,
                vientoKmH: viento,
                indiceUV: uvMax,
                probabilidadLluvia: probLluvia,
                presionHPa: presion,
                amanecer: amanecer,
                atardecer: atardecer,
                codigoWMO: wmo,
                esDeDia: esDeDia,
                porHora: tiraHoraria.isEmpty ? estado.porHora : tiraHoraria,
                fechaActualizacion: .now
            )
            estado = nuevo
            if let guardado = try? JSONEncoder().encode(nuevo) {
                defaults.set(guardado, forKey: Self.claveCache)
            }
        } catch {
            // Mantener estado en caché si no hay red
        }
    }

    private static func extraerHoraHHMM(_ iso: String) -> String {
        if let tIndex = iso.firstIndex(of: "T") {
            let resto = iso[iso.index(after: tIndex)...]
            return String(resto.prefix(5))
        }
        return String(iso.suffix(5))
    }

    private static func extraerHoraCorta(_ iso: String) -> String {
        let hhmm = extraerHoraHHMM(iso)
        return String(hhmm.prefix(2))
    }

    public static func estadoInicialPorDefecto() -> EstadoDelClima {
        var horas: [PronosticoPorHora] = []
        for h in 1...13 {
            let deDia = (h >= 7 && h <= 19)
            let wmo = deDia ? 0 : 1
            let temp = Double(15 + (h % 9))
            horas.append(
                PronosticoPorHora(
                    id: "h-\(h)",
                    etiquetaHora: String(format: "%02d", h),
                    codigoWMO: wmo,
                    esDeDia: deDia,
                    temperaturaC: temp
                )
            )
        }
        return EstadoDelClima(
            ciudad: "Chihuahua",
            latitud: 28.6353,
            longitud: -106.0889,
            temperaturaC: 22,
            sensacionC: 21,
            maximaC: 28,
            minimaC: 14,
            humedadPorcentaje: 38,
            vientoKmH: 11,
            indiceUV: 5,
            probabilidadLluvia: 0,
            presionHPa: 1014,
            amanecer: "06:18",
            atardecer: "19:46",
            codigoWMO: 0,
            esDeDia: true,
            porHora: horas
        )
    }
}

/// Módulo de Clima en el notch con pronóstico en vivo de Open-Meteo.
@MainActor
public final class ModuloDeClima: ModuloDeIsla {
    public let identidad = IdentidadDeModulo(
        id: "clima",
        nombre: "Clima",
        icono: "cloud.sun.fill",
        color: Paleta.hexClima,
        lado: .izquierda
    )
    public let tamanoExpandido = Medidas.clima
    public let modelo: ModeloDeClima

    public init(modelo: ModeloDeClima) {
        self.modelo = modelo
    }

    public var salud: SaludDeModulo { .listo }

    public var vistaExpandida: AnyView {
        AnyView(VistaDeClima(modelo: modelo))
    }

    public func arrancar() {
        modelo.iniciar()
    }

    public func detener() {
        modelo.detener()
    }
}

struct VistaDeClima: View {
    @Bindable var modelo: ModeloDeClima

    var body: some View {
        let clima = modelo.estado
        ZStack {
            fondoAtmosferico(esDeDia: clima.esDeDia)

            VStack(alignment: .leading, spacing: 7) {
                barraSuperior(clima)
                filaPrincipal(clima)
                filaMetricas(clima)
                tiraPorHora(clima)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: Medidas.radioDeTarjeta, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Medidas.radioDeTarjeta, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func fondoAtmosferico(esDeDia: Bool) -> some View {
        LinearGradient(
            colors: esDeDia
                ? [Color(hex: 0x0A1526), Color(hex: 0x080C14)]
                : [Color(hex: 0x05070D), Color(hex: 0x0B0F1C)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func barraSuperior(_ clima: EstadoDelClima) -> some View {
        HStack(spacing: 8) {
            Image(systemName: EstadoDelClima.iconoWMO(codigo: clima.codigoWMO, esDeDia: clima.esDeDia))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(clima.esDeDia ? Color(hex: 0xFFD60A) : Paleta.clima)

            if modelo.editandoCiudad {
                TextField("Ciudad…", text: $modelo.consultaCiudad)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Paleta.texto)
                    .frame(width: 130)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Paleta.superficieAlta, in: RoundedRectangle(cornerRadius: 5))
                    .onSubmit {
                        Task { await modelo.buscarYCambiarCiudad() }
                    }
            } else {
                Button {
                    modelo.consultaCiudad = clima.ciudad
                    modelo.editandoCiudad = true
                } label: {
                    HStack(spacing: 4) {
                        Text("Weather")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Paleta.texto)
                        Text("· \(clima.ciudad)")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Paleta.textoDeApoyo)
                    }
                }
                .buttonStyle(.plain)
                .help("Clic para cambiar de ciudad")
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Label(clima.amanecer, systemImage: "sunrise.fill")
                    .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Paleta.textoDeApoyo)
                Label(clima.atardecer, systemImage: "sunset.fill")
                    .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Paleta.textoDeApoyo)

                Button {
                    modelo.usarFahrenheit.toggle()
                } label: {
                    Text(modelo.usarFahrenheit ? "°F" : "°C")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Paleta.texto)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Paleta.superficieAlta, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Alternar °C / °F")

                Button {
                    Task { await modelo.actualizarClima() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Paleta.textoDeApoyo)
                        .rotationEffect(.degrees(modelo.cargando ? 360 : 0))
                }
                .buttonStyle(.plain)
                .help("Actualizar pronóstico")
            }
        }
    }

    private func filaPrincipal(_ clima: EstadoDelClima) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: EstadoDelClima.iconoWMO(codigo: clima.codigoWMO, esDeDia: clima.esDeDia))
                .font(.system(size: 28, weight: .medium))
                .symbolRenderingMode(.multicolor)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(modelo.formatearTemp(clima.temperaturaC))
                    .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Paleta.texto)
                HStack(spacing: 6) {
                    Text(EstadoDelClima.descripcionWMO(codigo: clima.codigoWMO))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Paleta.texto.opacity(0.9))
                    Text("H: \(modelo.formatearTemp(clima.maximaC))  L: \(modelo.formatearTemp(clima.minimaC))")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(Paleta.textoDeApoyo)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text("Feels like")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Paleta.textoDeApoyo)
                Text(modelo.formatearTemp(clima.sensacionC))
                    .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Paleta.texto)
            }
        }
    }

    private func filaMetricas(_ clima: EstadoDelClima) -> some View {
        HStack(spacing: 6) {
            chipMetrica(icono: "humidity.fill", titulo: "Humidity", valor: "\(clima.humedadPorcentaje)%")
            chipMetrica(icono: "wind", titulo: "Wind", valor: "\(Int(clima.vientoKmH.rounded())) km/h")
            chipMetrica(icono: "sun.max.fill", titulo: "UV", valor: "\(Int(clima.indiceUV.rounded()))")
            chipMetrica(icono: "cloud.rain.fill", titulo: "Rain chance", valor: "\(clima.probabilidadLluvia)%")
            chipMetrica(icono: "gauge.with.needle", titulo: "Pressure", valor: "\(clima.presionHPa) hPa")
        }
    }

    private func chipMetrica(icono: String, titulo: String, valor: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icono)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Paleta.textoDeApoyo)
            VStack(alignment: .leading, spacing: 0.5) {
                Text(titulo)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Paleta.textoDeApoyo)
                    .lineLimit(1)
                Text(valor)
                    .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(Paleta.texto)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func tiraPorHora(_ clima: EstadoDelClima) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Hourly")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(Paleta.textoDeApoyo)

            HStack(spacing: 0) {
                ForEach(clima.porHora.prefix(12)) { item in
                    VStack(spacing: 3) {
                        Text(item.etiquetaHora)
                            .font(.system(size: 8.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(Paleta.textoDeApoyo)
                        Image(systemName: EstadoDelClima.iconoWMO(codigo: item.codigoWMO, esDeDia: item.esDeDia))
                            .font(.system(size: 10, weight: .medium))
                            .symbolRenderingMode(.multicolor)
                            .frame(height: 12)
                        Text(modelo.formatearTemp(item.temperaturaC))
                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                            .foregroundStyle(Paleta.texto)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
