import NotchyCore
import NotchyDesign
import SwiftUI

/// Lo que se dibuja dentro del panel: la silueta con el tema elegido que crece desde el notch y,
/// expandida, la barra de módulos en las orejas y el contenido del módulo debajo.
public struct VistaDeIsla: View {
    private let coordinador: CoordinadorDeIsla
    @Environment(\.accessibilityReduceMotion) private var reducirMovimiento

    public init(coordinador: CoordinadorDeIsla) {
        self.coordinador = coordinador
    }

    public var body: some View {
        let tamano = coordinador.tamano
        let hombro = hombro
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                silueta
                if let modulo = coordinador.moduloAbierto {
                    contenido(de: modulo)
                        .frame(width: tamano.width, height: tamano.height)
                        .transition(entrada)
                } else if let modulo = coordinador.moduloEnAviso, let vistaAviso = modulo.vistaDeAviso {
                    vistaAviso
                        .frame(width: tamano.width, height: tamano.height)
                        .transition(entrada)
                } else if let hud = coordinador.hudActual, coordinador.grabacionActual == nil {
                    contenidoHUD(hud)
                        .frame(width: tamano.width, height: tamano.height)
                        .transition(.opacity)
                } else if let modulo = coordinador.moduloCompacto {
                    contenidoCompacto(de: modulo)
                        .frame(width: tamano.width, height: tamano.height)
                        .transition(.opacity)
                }
            }
            .frame(width: tamano.width + 2 * hombro, height: tamano.height)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Movimiento.cambioDeEstado(reducir: reducirMovimiento), value: coordinador.estado)
        .animation(Movimiento.cambioDeEstado(reducir: reducirMovimiento), value: coordinador.hudActual)
    }

    /// En reposo la isla es el notch: sin hombros, para no asomarse sobre la barra de menús.
    private var hombro: CGFloat {
        coordinador.geometria.tieneNotch && (coordinador.estado != .reposo || coordinador.hudActual != nil)
            ? Medidas.hombro : 0
    }

    private var radio: CGFloat {
        switch coordinador.estado {
        case .reposo, .compacto: Medidas.radioCompacto
        case .aviso, .expandido: Medidas.radioExpandido
        }
    }

    private var colorDePanel: Color {
        let tema = coordinador.registro.ajustes.temaPanel
        if coordinador.estado == .reposo && coordinador.hudActual == nil {
            return Paleta.fondo
        }
        if tema == .caratula, let hex = coordinador.hexCaratulaActual {
            return Color(hex: Self.oscurecerHex(hex, factor: 0.22))
        }
        return Color(hex: tema.hexBase)
    }

    private static func oscurecerHex(_ hex: UInt32, factor: Double) -> UInt32 {
        let r = UInt32(Double((hex >> 16) & 0xFF) * factor) & 0xFF
        let g = UInt32(Double((hex >> 8) & 0xFF) * factor) & 0xFF
        let b = UInt32(Double(hex & 0xFF) * factor) & 0xFF
        return (r << 16) | (g << 8) | b
    }

    @ViewBuilder private var silueta: some View {
        if coordinador.geometria.tieneNotch {
            FormaDeIsla(radioInferior: radio, hombro: hombro)
                .fill(
                    LinearGradient(
                        colors: [Paleta.fondo, colorDePanel],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        } else {
            RoundedRectangle(cornerRadius: min(radio, coordinador.tamano.height / 2))
                .fill(colorDePanel)
        }
    }

    private func contenido(de modulo: any ModuloDeIsla) -> some View {
        VStack(spacing: 0) {
            BarraDeModulos(coordinador: coordinador)
                .frame(height: coordinador.geometria.tamanoDeReposo.height)
            modulo.vistaExpandida
                .padding(.horizontal, Medidas.margenLateral)
                .padding(.top, Medidas.margenSuperior)
                .padding(.bottom, Medidas.margenInferior)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func contenidoHUD(_ hud: EstadoDeHUDSistema) -> some View {
        let colorBarra = colorAcentoBarra(porDefecto: 0xE09DB4)
        return HStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: hud.tipo.icono)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Paleta.texto)
                Text(hud.etiqueta)
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(Paleta.texto)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            Color.clear.frame(width: coordinador.geometria.pantalla.notch?.width ?? 0)

            HStack(spacing: 0) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Paleta.superficieAlta)
                            .frame(height: 5)
                        Capsule()
                            .fill(colorBarra)
                            .frame(width: max(4, geo.size.width * hud.nivel), height: 5)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(width: 48, height: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 10)
    }

    private func colorAcentoBarra(porDefecto: UInt32) -> Color {
        let tema = coordinador.registro.ajustes.temaBarra
        if tema == .caratula, let hex = coordinador.hexCaratulaActual {
            return Color(hex: hex)
        }
        return Color(hex: tema.hexAcento ?? porDefecto)
    }

    private func contenidoCompacto(de modulo: any ModuloDeIsla) -> some View {
        Button {
            coordinador.recibir(.elegirModulo(modulo.identidad.id))
        } label: {
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    if let orejaIzquierda = modulo.orejaIzquierdaCompacta {
                        orejaIzquierda
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                Color.clear.frame(width: coordinador.geometria.pantalla.notch?.width ?? 0)

                HStack(spacing: 4) {
                    if let orejaDerecha = modulo.orejaDerechaCompacta {
                        orejaDerecha
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(modulo.identidad.nombre)
    }

    /// Primero crece la forma; el contenido entra después con fundido y desenfoque.
    private var entrada: AnyTransition {
        let aparicion: AnyTransition =
            reducirMovimiento
            ? .opacity
            : .modifier(active: Desenfoque(radio: 6, opacidad: 0), identity: Desenfoque(radio: 0, opacidad: 1))
        return .asymmetric(
            insertion: aparicion.animation(Movimiento.entradaDeContenido(reducir: reducirMovimiento)),
            removal: .opacity.animation(.easeOut(duration: 0.1)))
    }
}

private struct Desenfoque: ViewModifier {
    let radio: CGFloat
    let opacidad: Double

    func body(content: Content) -> some View {
        content.blur(radius: radio).opacity(opacidad)
    }
}

/// Íconos de los módulos en las orejas, a los lados del notch, y el engrane a la derecha.
/// Nunca hay contenido en el hueco de la cámara.
struct BarraDeModulos: View {
    let coordinador: CoordinadorDeIsla

    var body: some View {
        let modulos = coordinador.registro.activos.map(\.identidad)
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    if modulos.count > 1 {
                        ForEach(modulos.filter { $0.lado == .izquierda }) { boton($0) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(width: coordinador.geometria.pantalla.notch?.width ?? 0)

            HStack(spacing: 2) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        if modulos.count > 1 {
                            ForEach(modulos.filter { $0.lado == .derecha }) { boton($0) }
                        }
                    }
                }
                engrane
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Medidas.margenLateral)
    }

    private func colorParaIcono(_ modulo: IdentidadDeModulo) -> Color {
        let tema = coordinador.registro.ajustes.temaBarra
        if tema == .caratula, let hex = coordinador.hexCaratulaActual {
            return Color(hex: hex)
        }
        if let hexTema = tema.hexAcento {
            return Color(hex: hexTema)
        }
        return Color(hex: modulo.color)
    }

    private func boton(_ modulo: IdentidadDeModulo) -> some View {
        let abierto = coordinador.moduloAbierto?.identidad.id == modulo.id
        let grabandoEnEsteModulo =
            modulo.id == "grabadora" && (coordinador.grabacionActual?.activa == true)
        return Button {
            coordinador.recibir(.elegirModulo(modulo.id))
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: modulo.icono)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        grabandoEnEsteModulo
                            ? Paleta.grabadora
                            : (abierto ? colorParaIcono(modulo) : Paleta.textoDeApoyo)
                    )
                    .frame(width: 21, height: 22)
                if grabandoEnEsteModulo {
                    Circle()
                        .fill(Paleta.grabadora)
                        .frame(width: 5, height: 5)
                        .offset(x: -2, y: 2)
                }
            }
            .background(
                abierto ? Paleta.superficieAlta : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(modulo.nombre)
        .accessibilityLabel(modulo.nombre)
        .accessibilityAddTraits(abierto ? .isSelected : [])
    }

    private var engrane: some View {
        Menu {
            if let abrirAjustes = coordinador.alAbrirAjustes {
                Button("Ajustes…", action: abrirAjustes)
                Divider()
            }
            Button("Salir de Notchy") { coordinador.alSalir?() }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Paleta.textoDeApoyo)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Ajustes y salir")
        .accessibilityLabel("Ajustes y salir")
    }
}
