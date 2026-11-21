import AppKit
import NotchyCore
import NotchyDesign
import SwiftUI

/// Módulo Ahora suena (`620 × 224 pt`): carátula, controles con scrubbing, letra sincronizada animada (LYRICS) y espectro dinámico (MUS-1, MUS-2).
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
                // Izquierda: carátula + título + barra interactiva + controles
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

                    BarraDeProgresoMusical(
                        estado: estado,
                        alSaltarAFraccion: { fraccion in
                            modelo.saltarAFraccion(fraccion)
                        }
                    )

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

                // Derecha: panel de LYRICS sincronizado y animado en tiempo real
                PanelDeLetraMusical(
                    estado: estado,
                    letra: modelo.letraActual,
                    cargando: modelo.cargandoLetra,
                    alSaltarASegundo: { seg in
                        modelo.saltarA(segundos: seg)
                    }
                )
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

/// Panel de letra en vivo con animaciones de resorte, brillo karaoke y salto al hacer clic en cualquier verso.
struct PanelDeLetraMusical: View {
    let estado: EstadoDeAhoraSuena
    let letra: LetraDeCancion?
    let cargando: Bool
    var alSaltarASegundo: ((Double) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reducirMovimiento
    @Environment(\.accessibilityReduceTransparency) private var reducirTransparencia

    var body: some View {
        TimelineView(.periodic(from: .now, by: estado.reproduciendo ? 0.25 : 60.0)) { contexto in
            let seg = estado.transcurridoActual(en: contexto.date) ?? 0
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Paleta.musica)
                    Text("LYRICS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Paleta.textoDeApoyo)
                        .tracking(0.8)
                    Spacer(minLength: 0)
                }

                if cargando {
                    Spacer(minLength: 0)
                    Text("Buscando letra sincronizada…")
                        .textoDeApoyo()
                    Spacer(minLength: 0)
                } else if let letra, !letra.lineas.isEmpty {
                    let idx = letra.indiceActivo(en: seg)
                    let ventana = indicesVisibles(actual: idx, total: letra.lineas.count)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(ventana, id: \.self) { i in
                            let linea = letra.lineas[i]
                            let distancia = i - idx
                            let esActiva = distancia == 0
                            let progresoVerso = progresoDeLinea(
                                indice: i,
                                lineas: letra.lineas,
                                segundoActual: seg
                            )

                            Button {
                                if let t = linea.tiempoSegundos {
                                    alSaltarASegundo?(t)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(linea.texto)
                                        .font(
                                            .system(
                                                size: esActiva ? 14 : (abs(distancia) == 1 ? 11.5 : 10.5),
                                                weight: esActiva ? .bold : .semibold
                                            )
                                        )
                                        .foregroundStyle(colorParaDistancia(distancia))
                                        .shadow(
                                            color: esActiva ? Paleta.musica.opacity(0.45) : .clear,
                                            radius: esActiva ? 6 : 0
                                        )
                                        .lineLimit(esActiva ? 2 : 1)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .scaleEffect(esActiva ? 1.02 : 0.96, anchor: .leading)
                                        .blur(
                                            radius: (esActiva || reducirTransparencia)
                                                ? 0 : (abs(distancia) >= 2 ? 0.6 : 0.2)
                                        )

                                    if esActiva, linea.tiempoSegundos != nil {
                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                Capsule()
                                                    .fill(Color.white.opacity(0.14))
                                                Capsule()
                                                    .fill(
                                                        LinearGradient(
                                                            colors: [Paleta.musica, Color.white],
                                                            startPoint: .leading,
                                                            endPoint: .trailing
                                                        )
                                                    )
                                                    .frame(width: max(6, geo.size.width * progresoVerso))
                                            }
                                        }
                                        .frame(height: 2.5)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(linea.id)
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                )
                            )
                        }
                    }
                    .animation(Movimiento.cambioDeEstado(reducir: reducirMovimiento), value: idx)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    Text("Sin letra disponible")
                        .textoDeApoyo()
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
        }
    }

    private func indicesVisibles(actual: Int, total: Int) -> [Int] {
        guard total > 0 else { return [] }
        let inicio = max(0, actual - 1)
        let fin = min(total - 1, inicio + 3)
        return Array(inicio...fin)
    }

    private func colorParaDistancia(_ distancia: Int) -> Color {
        switch distancia {
        case 0:
            return Paleta.texto
        case -1:
            return Color.white.opacity(0.32)
        case 1:
            return Color.white.opacity(0.54)
        default:
            return Color.white.opacity(0.28)
        }
    }

    private func progresoDeLinea(
        indice: Int,
        lineas: [LineaDeLetra],
        segundoActual: Double
    ) -> CGFloat {
        guard let inicio = lineas[indice].tiempoSegundos else { return 0 }
        let fin: Double
        if indice + 1 < lineas.count, let siguiente = lineas[indice + 1].tiempoSegundos, siguiente > inicio {
            fin = siguiente
        } else {
            fin = inicio + 4.0
        }
        let fraccion = (segundoActual - inicio) / max(0.2, fin - inicio)
        return CGFloat(min(max(fraccion, 0), 1))
    }
}

/// Barra de progreso interactiva: permite hacer clic o arrastrar para cambiar el minuto/segundo de la canción.
struct BarraDeProgresoMusical: View {
    let estado: EstadoDeAhoraSuena
    var alSaltarAFraccion: ((Double) -> Void)?

    @State private var fraccionArrastre: Double?
    @State private var cursorEncima = false
    @Environment(\.accessibilityReduceMotion) private var reducirMovimiento

    var body: some View {
        TimelineView(.periodic(from: .now, by: estado.reproduciendo ? 0.5 : 60.0)) { contexto in
            let ahora = contexto.date
            let duracion = estado.duracionSegundos ?? 0
            let fraccionReal = estado.fraccionDeProgreso(en: ahora)
            let fraccionMostrada = fraccionArrastre ?? fraccionReal
            let transcurridoMostrado =
                fraccionArrastre != nil
                ? duracion * (fraccionArrastre ?? 0) : (estado.transcurridoActual(en: ahora) ?? 0)

            HStack(spacing: 8) {
                Text(formatearSegundos(transcurridoMostrado))
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(fraccionArrastre != nil ? Paleta.musica : Paleta.textoDeApoyo)
                    .frame(width: 32, alignment: .leading)

                GeometryReader { geo in
                    let ancho = max(1, geo.size.width)
                    let xThumb = max(0, min(ancho, ancho * fraccionMostrada))
                    let altoBarra: CGFloat = (cursorEncima || fraccionArrastre != nil) ? 6 : 4

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Paleta.superficieAlta)
                            .frame(height: altoBarra)

                        Capsule()
                            .fill(fraccionArrastre != nil ? Paleta.musica : Paleta.texto)
                            .frame(width: xThumb, height: altoBarra)

                        if cursorEncima || fraccionArrastre != nil {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 10, height: 10)
                                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                                .offset(x: max(0, min(ancho - 10, xThumb - 5)))
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                    .contentShape(Rectangle())
                    .onHover { encima in
                        withAnimation(Movimiento.cambioDeEstado(reducir: reducirMovimiento)) {
                            cursorEncima = encima
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { valor in
                                let f = min(max(Double(valor.location.x / ancho), 0), 1)
                                fraccionArrastre = f
                            }
                            .onEnded { valor in
                                let f = min(max(Double(valor.location.x / ancho), 0), 1)
                                fraccionArrastre = nil
                                alSaltarAFraccion?(f)
                            }
                    )
                }
                .frame(height: 14)

                Text(formatearSegundos(duracion))
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Paleta.textoDeApoyo)
                    .frame(width: 32, alignment: .trailing)
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
