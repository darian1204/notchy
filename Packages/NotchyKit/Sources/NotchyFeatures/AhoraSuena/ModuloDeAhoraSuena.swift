import AppKit
import NotchyCore
import NotchyDesign
import SwiftUI

/// Módulo Ahora suena: estado multimedia, carátula, barra de progreso, controles y orejas compactas (MUS-1).
@MainActor
public final class ModuloDeAhoraSuena: ModuloDeIsla {
    public let identidad = IdentidadDeModulo(
        id: "musica",
        nombre: "Ahora suena",
        icono: "play.fill",
        color: Paleta.hexMusica,
        lado: .izquierda
    )
    public let tamanoExpandido = Medidas.ahoraSuena
    public let modelo: ModeloDeAhoraSuena

    public init(modelo: ModeloDeAhoraSuena) {
        self.modelo = modelo
    }

    public var salud: SaludDeModulo {
        modelo.salud
    }

    public var vistaExpandida: AnyView {
        AnyView(VistaDeAhoraSuena(modelo: modelo))
    }

    public var orejaIzquierdaCompacta: AnyView? {
        AnyView(
            CaratulaDeCancion(
                datos: modelo.estadoActual?.caratulaPNG,
                tamano: 22,
                radio: 5
            ))
    }

    public var orejaDerechaCompacta: AnyView? {
        AnyView(
            EspectroDeAudio(
                barras: 4,
                alto: 14,
                reproduciendo: modelo.estadoActual?.reproduciendo == true
            )
            .frame(width: 18, height: 14))
    }

    public func arrancar() {
        modelo.iniciar()
    }

    public func detener() {
        modelo.detener()
    }
}

struct VistaDeAhoraSuena: View {
    let modelo: ModeloDeAhoraSuena

    var body: some View {
        if let estado = modelo.estadoActual {
            HStack(spacing: 14) {
                CaratulaDeCancion(datos: estado.caratulaPNG, tamano: 96, radio: 12)

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(estado.titulo)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Paleta.texto)
                            .lineLimit(1)
                        Text(subtitulo(de: estado))
                            .textoDeApoyo()
                            .lineLimit(1)
                    }

                    BarraDeProgresoMusical(estado: estado)

                    HStack(spacing: 18) {
                        Button {
                            modelo.anterior()
                        } label: {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Paleta.texto)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Canción anterior")

                        Button {
                            modelo.alternarReproduccion()
                        } label: {
                            Image(systemName: estado.reproduciendo ? "pause.fill" : "play.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Paleta.fondo)
                                .frame(width: 34, height: 34)
                                .background(Paleta.texto, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(estado.reproduciendo ? "Pausar" : "Reproducir")

                        Button {
                            modelo.siguiente()
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Paleta.texto)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Siguiente canción")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity)

                EspectroDeAudio(
                    barras: 12,
                    alto: 56,
                    reproduciendo: estado.reproduciendo
                )
                .frame(width: 92, height: 56)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Tarjeta {
                HStack(spacing: 12) {
                    CaratulaDeCancion(datos: nil, tamano: 52, radio: 10)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nada sonando")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Paleta.texto)
                        Text("Reproduce música en Música, Spotify o el navegador para controlarla desde aquí.")
                            .textoDeApoyo()
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    private func subtitulo(de estado: EstadoDeAhoraSuena) -> String {
        let partes = [estado.artista, estado.appOrigen].compactMap { $0 }.filter { !$0.isEmpty }
        return partes.isEmpty ? "Reproductor del sistema" : partes.joined(separator: " · ")
    }
}

/// Barra de progreso que estima el avance segundo a segundo mientras suena sin sondear al sistema.
struct BarraDeProgresoMusical: View {
    let estado: EstadoDeAhoraSuena

    var body: some View {
        TimelineView(.periodic(from: .now, by: estado.reproduciendo ? 1.0 : 60.0)) { contexto in
            let ahora = contexto.date
            let transcurrido = estado.transcurridoActual(en: ahora) ?? 0
            let duracion = estado.duracionSegundos ?? 0
            let fraccion = estado.fraccionDeProgreso(en: ahora)
            HStack(spacing: 8) {
                Text(formatearSegundos(transcurrido))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Paleta.textoDeApoyo)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Paleta.superficieAlta)
                            .frame(height: 4)
                        Capsule()
                            .fill(Paleta.texto)
                            .frame(width: max(0, geo.size.width * fraccion), height: 4)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 12)
                Text(formatearSegundos(duracion))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Paleta.textoDeApoyo)
            }
        }
    }

    private func formatearSegundos(_ segundos: Double) -> String {
        guard segundos.isFinite, segundos > 0 else { return "0:00" }
        let total = Int(segundos.rounded(.down))
        let minutos = total / 60
        let resto = total % 60
        return String(format: "%d:%02d", minutos, resto)
    }
}

/// Carátula del álbum o degradado de respaldo del mockup.
struct CaratulaDeCancion: View {
    let datos: Data?
    let tamano: CGFloat
    let radio: CGFloat

    var body: some View {
        Group {
            if let datos, let imagen = NSImage(data: datos) {
                Image(nsImage: imagen)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [
                        Color(hex: 0xFF9A5A),
                        Color(hex: 0xA03DFF),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: max(10, tamano * 0.36), weight: .semibold))
                        .foregroundStyle(Paleta.texto.opacity(0.85))
                }
            }
        }
        .frame(width: tamano, height: tamano)
        .clipShape(RoundedRectangle(cornerRadius: radio))
    }
}

/// Barras de espectro en color verde música (`Paleta.musica`), respetando reducir movimiento.
struct EspectroDeAudio: View {
    let barras: Int
    let alto: CGFloat
    let reproduciendo: Bool
    @Environment(\.accessibilityReduceMotion) private var reducirMovimiento

    var body: some View {
        TimelineView(.periodic(from: .now, by: (reproduciendo && !reducirMovimiento) ? 0.35 : 60.0)) { contexto in
            let fase = Int(contexto.date.timeIntervalSinceReferenceDate / 0.35)
            HStack(alignment: .bottom, spacing: barras > 6 ? 3 : 2) {
                ForEach(0..<barras, id: \.self) { indice in
                    let factor = alturaRelativa(indice: indice, fase: fase)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Paleta.musica.opacity(reproduciendo ? 1.0 : 0.4))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(3, alto * factor))
                }
            }
            .animation(
                reducirMovimiento ? nil : .easeInOut(duration: 0.3),
                value: fase
            )
        }
    }

    private func alturaRelativa(indice: Int, fase: Int) -> CGFloat {
        guard reproduciendo else {
            return 0.25
        }
        if reducirMovimiento {
            let base = 25 + ((indice * 41) % 70)
            return CGFloat(base) / 100.0
        }
        let semilla = (indice * 37 + fase * 29) % 70
        return CGFloat(25 + semilla) / 100.0
    }
}
