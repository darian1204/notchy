import AppKit
import NotchyCore
import NotchyDesign
import SwiftUI

/// Módulo Ahora suena (`620 × 224 pt`): carátula, controles, letra sincronizada (LYRICS) y espectro dinámico (MUS-1, MUS-2).
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
                niveles: Array(modelo.nivelesEspectro.prefix(4)),
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
    @Bindable var modelo: ModeloDeAhoraSuena

    var body: some View {
        if let estado = modelo.estadoActual {
            HStack(spacing: 16) {
                // Izquierda: carátula + título + barra + controles
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        CaratulaDeCancion(datos: estado.caratulaPNG, tamano: 76, radio: 14)

                        VStack(alignment: .leading, spacing: 3) {
                            if let origen = estado.appOrigen {
                                Text(origen.uppercased())
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Paleta.musica)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Paleta.superficieAlta, in: Capsule())
                            }
                            Text(estado.titulo)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Paleta.texto)
                                .lineLimit(1)
                            Text(subtitulo(de: estado))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Paleta.textoDeApoyo)
                                .lineLimit(1)
                        }
                    }

                    BarraDeProgresoMusical(estado: estado)

                    HStack(spacing: 16) {
                        Button {
                            modelo.anterior()
                        } label: {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Paleta.texto)
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Canción anterior")

                        Button {
                            modelo.alternarReproduccion()
                        } label: {
                            Image(systemName: estado.reproduciendo ? "pause.fill" : "play.fill")
                                .font(.system(size: 13, weight: .bold))
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
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Paleta.texto)
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Siguiente canción")

                        Spacer(minLength: 0)

                        EspectroDeAudio(
                            niveles: Array(modelo.nivelesEspectro.prefix(8)),
                            alto: 22,
                            reproduciendo: estado.reproduciendo
                        )
                        .frame(width: 48, height: 22)
                    }
                }
                .frame(width: 265)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)
                    .padding(.vertical, 6)

                // Derecha: panel de LYRICS sincronizado en tiempo real
                PanelDeLetraMusical(estado: estado, letra: modelo.letraActual, cargando: modelo.cargandoLetra)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        Text("Reproduce música en Música, Spotify o el navegador para ver controles y letra.")
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
        let partes = [estado.artista, estado.album].compactMap { $0 }.filter { !$0.isEmpty }
        return partes.isEmpty ? (estado.appOrigen ?? "Reproductor del sistema") : partes.joined(separator: " · ")
    }
}

/// Panel de letra sincronizada inspirado en el diseño de referencia (línea anterior tenue, actual resaltada, siguientes debajo).
struct PanelDeLetraMusical: View {
    let estado: EstadoDeAhoraSuena
    let letra: LetraDeCancion?
    let cargando: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: estado.reproduciendo ? 0.4 : 60.0)) { contexto in
            let seg = estado.transcurridoActual(en: contexto.date) ?? 0
            VStack(alignment: .leading, spacing: 6) {
                Text("LYRICS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Paleta.textoDeApoyo)
                    .tracking(0.8)

                if cargando {
                    Spacer(minLength: 0)
                    Text("Buscando letra sincronizada…")
                        .textoDeApoyo()
                    Spacer(minLength: 0)
                } else if let letra, !letra.lineas.isEmpty {
                    let idx = letra.indiceActivo(en: seg)
                    let anterior = idx > 0 ? letra.lineas[idx - 1].texto : " "
                    let actual = letra.lineas[idx].texto
                    let siguiente = (idx + 1 < letra.lineas.count) ? letra.lineas[idx + 1].texto : " "
                    let siguiente2 = (idx + 2 < letra.lineas.count) ? letra.lineas[idx + 2].texto : ""

                    VStack(alignment: .leading, spacing: 5) {
                        Text(anterior)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.32))
                            .lineLimit(1)

                        Text(actual)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Paleta.texto)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(siguiente)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.45))
                            .lineLimit(1)

                        if !siguiente2.isEmpty {
                            Text(siguiente2)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.28))
                                .lineLimit(1)
                        }
                    }
                    .animation(.easeOut(duration: 0.22), value: idx)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    Text("Sin letra disponible")
                        .textoDeApoyo()
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
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
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
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
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
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

/// Barras de espectro dinámicas impulsadas por `nivelesEspectro` del modelo.
struct EspectroDeAudio: View {
    let niveles: [Double]
    let alto: CGFloat
    let reproduciendo: Bool
    var color: Color = Paleta.musica
    @Environment(\.accessibilityReduceMotion) private var reducirMovimiento

    var body: some View {
        HStack(alignment: .bottom, spacing: niveles.count > 5 ? 2.5 : 2) {
            ForEach(Array(niveles.enumerated()), id: \.offset) { _, nivel in
                let factor = reproduciendo ? CGFloat(min(max(nivel, 0.16), 1.0)) : 0.22
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color.opacity(reproduciendo ? 1.0 : 0.4))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(3, alto * factor))
            }
        }
        .animation(
            reducirMovimiento ? nil : .spring(response: 0.16, dampingFraction: 0.72),
            value: niveles
        )
    }
}
