import AppKit
import Foundation
import NotchyCore
import OSLog
import Observation

/// Modelo observable del módulo Ahora suena: controla la reproducción, extrae el color de la carátula y obtiene la letra sincronizada (MUS-1).
@MainActor
@Observable
public final class ModeloDeAhoraSuena {
    public private(set) var estadoActual: EstadoDeAhoraSuena?
    public private(set) var salud: SaludDeModulo = .listo
    public private(set) var letraActual: LetraDeCancion?
    public private(set) var cargandoLetra = false
    public var mostrarLetra = true
    public private(set) var nivelesEspectro: [Double] = Array(repeating: 0.25, count: 12)
    /// Color dominante de la carátula, para teñir el espectro de las orejas.
    public private(set) var hexDeCaratula: UInt32?

    @ObservationIgnored private let puerto: any PuertoDeAhoraSuena
    @ObservationIgnored private let bus: BusDeEventos?
    @ObservationIgnored private var pidioCompacto = false
    @ObservationIgnored private var claveUltimaLetra: String?
    @ObservationIgnored private var tareaLetra: Task<Void, Never>?
    @ObservationIgnored private var tareaEspectro: Task<Void, Never>?
    @ObservationIgnored private let log = Registro.de(.musica)

    public init(
        puerto: any PuertoDeAhoraSuena,
        bus: BusDeEventos? = nil
    ) {
        self.puerto = puerto
        self.bus = bus
    }

    public func iniciar() {
        puerto.iniciar { [weak self] nuevo in
            self?.aplicar(nuevo)
        }
        Task { [weak self] in
            guard let self else { return }
            let ok = await self.puerto.probarAdaptador()
            if !ok {
                self.log.notice("mediaremote-adapter test devolvió fallo; usando respaldo AppleScript si hace falta")
            }
        }
    }

    public func detener() {
        puerto.detener()
        tareaLetra?.cancel()
        tareaLetra = nil
        tareaEspectro?.cancel()
        tareaEspectro = nil
        if pidioCompacto, let bus {
            pidioCompacto = false
            Task {
                await bus.publicar(PeticionDeEstadoCompacto(modulo: "musica", prioridad: nil))
            }
        }
    }

    public func alternarReproduccion() {
        puerto.enviar(.alternar)
    }

    public func siguiente() {
        puerto.enviar(.siguiente)
    }

    public func anterior() {
        puerto.enviar(.anterior)
    }

    public func saltarA(segundos: Double) {
        guard let actual = estadoActual else { return }
        let duracion = actual.duracionSegundos ?? max(segundos, 0)
        let destino = min(max(0, segundos), max(duracion, 0))
        estadoActual = EstadoDeAhoraSuena(
            titulo: actual.titulo,
            artista: actual.artista,
            album: actual.album,
            appOrigen: actual.appOrigen,
            bundleIdentifier: actual.bundleIdentifier,
            reproduciendo: actual.reproduciendo,
            duracionSegundos: actual.duracionSegundos,
            transcurridoSegundos: destino,
            fechaDeMuestra: .now,
            caratulaPNG: actual.caratulaPNG,
            usandoRespaldoAppleScript: actual.usandoRespaldoAppleScript
        )
        puerto.saltarA(segundos: destino)
    }

    public func saltarAFraccion(_ fraccion: Double) {
        guard let duracion = estadoActual?.duracionSegundos, duracion > 0 else { return }
        let acotada = min(max(fraccion, 0), 1)
        saltarA(segundos: duracion * acotada)
    }

    private func aplicar(_ nuevo: EstadoDeAhoraSuena?) {
        let anterior = estadoActual
        estadoActual = nuevo
        // El color solo se recalcula cuando cambia la carátula, no en cada actualización.
        let caratulaCambio = nuevo?.caratulaPNG != anterior?.caratulaPNG
        if caratulaCambio {
            hexDeCaratula = Self.colorDominante(de: nuevo?.caratulaPNG)
        }
        if let bus {
            Task { await bus.publicar(CambioDeAhoraSuena(estado: nuevo)) }
            if caratulaCambio {
                let hex = hexDeCaratula
                Task { await bus.publicar(ColorDeCaratulaActualizado(hex: hex)) }
            }
        }
        let debeMostrarCompacto = (nuevo?.reproduciendo == true)
        if debeMostrarCompacto != pidioCompacto {
            pidioCompacto = debeMostrarCompacto
            if let bus {
                let prioridad: PrioridadCompacta? = debeMostrarCompacto ? .musica : nil
                Task {
                    await bus.publicar(
                        PeticionDeEstadoCompacto(modulo: "musica", prioridad: prioridad))
                }
            }
        }

        if let nuevo {
            let clave = "\(nuevo.titulo.lowercased())|\((nuevo.artista ?? "").lowercased())"
            if clave != claveUltimaLetra {
                claveUltimaLetra = clave
                buscarLetra(titulo: nuevo.titulo, artista: nuevo.artista ?? "", duracion: nuevo.duracionSegundos)
            }
        } else {
            claveUltimaLetra = nil
            letraActual = nil
        }

        if anterior?.reproduciendo != nuevo?.reproduciendo {
            actualizarEspectro()
            // El espectro solo se anima mientras suena: en pausa no hay nada que despertar.
            if nuevo?.reproduciendo == true {
                iniciarMedidorDeEspectro()
            } else {
                tareaEspectro?.cancel()
                tareaEspectro = nil
            }
        }
    }

    private func iniciarMedidorDeEspectro() {
        tareaEspectro?.cancel()
        tareaEspectro = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(130))
                guard let self, !Task.isCancelled else { break }
                self.actualizarEspectro()
            }
        }
    }

    private func actualizarEspectro() {
        guard let estado = estadoActual, estado.reproduciendo else {
            let reposo = Array(repeating: 0.22, count: 12)
            if nivelesEspectro != reposo { nivelesEspectro = reposo }
            return
        }
        let ahora = Date.now
        let t = estado.transcurridoActual(en: ahora) ?? ahora.timeIntervalSinceReferenceDate
        let semillaCancion = abs(estado.titulo.hashValue % 97)
        let envolvente = 0.55 + 0.45 * abs(sin(t * 2.4 + Double(semillaCancion) * 0.1))
        var nuevos: [Double] = []
        nuevos.reserveCapacity(12)
        for i in 0..<12 {
            let freq1 = sin(t * (3.2 + Double(i) * 0.43) + Double(i) * 0.9)
            let freq2 = cos(t * (5.1 - Double(i % 5) * 0.6) + Double(semillaCancion))
            let crudo = (abs(freq1) * 0.65 + abs(freq2) * 0.35) * envolvente
            let acotado = min(max(0.18 + crudo * 0.82, 0.18), 1.0)
            nuevos.append(acotado)
        }
        nivelesEspectro = nuevos
    }

    private func buscarLetra(titulo: String, artista: String, duracion: Double?) {
        tareaLetra?.cancel()
        cargandoLetra = true
        tareaLetra = Task { [weak self] in
            let descargada = await Self.descargarLetraLRCLib(titulo: titulo, artista: artista, duracion: duracion)
            guard let self, !Task.isCancelled else { return }
            self.cargandoLetra = false
            if let descargada, !descargada.lineas.isEmpty {
                self.letraActual = descargada
            } else {
                self.letraActual = LetraDeCancion(
                    titulo: titulo,
                    artista: artista,
                    lineas: [
                        LineaDeLetra(id: 0, tiempoSegundos: 0, texto: "♪ \(titulo)"),
                        LineaDeLetra(
                            id: 1,
                            tiempoSegundos: 4,
                            texto: artista.isEmpty ? "Reproduciendo en tu Mac" : artista
                        ),
                        LineaDeLetra(id: 2, tiempoSegundos: 10, texto: "Sin letra sincronizada para esta pista"),
                    ]
                )
            }
        }
    }

    static func descargarLetraLRCLib(titulo: String, artista: String, duracion: Double?) async -> LetraDeCancion? {
        var componentes = URLComponents(string: "https://lrclib.net/api/get")
        var items = [
            URLQueryItem(name: "track_name", value: titulo),
            URLQueryItem(name: "artist_name", value: artista),
        ]
        if let duracion, duracion > 1 {
            items.append(URLQueryItem(name: "duration", value: String(Int(duracion.rounded()))))
        }
        componentes?.queryItems = items
        guard let url = componentes?.url else { return nil }

        var solicitud = URLRequest(url: url)
        solicitud.timeoutInterval = 4
        solicitud.setValue("Notchy/1.0 (macOS)", forHTTPHeaderField: "User-Agent")

        guard let (datos, respuesta) = try? await URLSession.shared.data(for: solicitud),
            let http = respuesta as? HTTPURLResponse,
            http.statusCode == 200,
            let json = try? JSONSerialization.jsonObject(with: datos) as? [String: Any]
        else {
            return nil
        }

        if let sincronizada = json["syncedLyrics"] as? String, !sincronizada.isEmpty {
            let lineas = parsearLRC(sincronizada)
            if !lineas.isEmpty {
                return LetraDeCancion(titulo: titulo, artista: artista, lineas: lineas)
            }
        }
        if let plana = json["plainLyrics"] as? String, !plana.isEmpty {
            let partes = plana.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let lineas = partes.enumerated().map { idx, texto in
                LineaDeLetra(id: idx, tiempoSegundos: Double(idx) * 4.0, texto: texto)
            }
            return LetraDeCancion(titulo: titulo, artista: artista, lineas: lineas)
        }
        return nil
    }

    public static func parsearLRC(_ lrc: String) -> [LineaDeLetra] {
        var resultado: [LineaDeLetra] = []
        let filas = lrc.components(separatedBy: .newlines)
        for fila in filas {
            guard fila.hasPrefix("["), let cierre = fila.firstIndex(of: "]") else { continue }
            let marca = String(fila[fila.index(after: fila.startIndex)..<cierre])
            let texto = String(fila[fila.index(after: cierre)...]).trimmingCharacters(in: .whitespaces)
            guard !texto.isEmpty else { continue }
            let partes = marca.split(separator: ":")
            guard partes.count == 2,
                let min = Double(partes[0]),
                let seg = Double(partes[1])
            else { continue }
            resultado.append(
                LineaDeLetra(id: resultado.count, tiempoSegundos: min * 60.0 + seg, texto: texto))
        }
        return resultado
    }

    static func colorDominante(de datos: Data?) -> UInt32? {
        guard let datos,
            let imagen = NSImage(data: datos),
            let cgImage = imagen.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return nil
        }
        let ancho = 1
        let alto = 1
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard
            let contexto = CGContext(
                data: &pixel,
                width: ancho,
                height: alto,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }
        contexto.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let r = UInt32(max(pixel[0], 60))
        let g = UInt32(max(pixel[1], 60))
        let b = UInt32(max(pixel[2], 60))
        return (r << 16) | (g << 8) | b
    }
}
