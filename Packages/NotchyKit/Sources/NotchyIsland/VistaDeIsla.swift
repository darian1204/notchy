import NotchyCore
import NotchyDesign
import SwiftUI

/// Lo que se dibuja dentro del panel: la silueta negra que crece desde el notch y, expandida,
/// la barra de módulos en las orejas y el contenido del módulo debajo.
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
                }
            }
            .frame(width: tamano.width + 2 * hombro, height: tamano.height)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Movimiento.cambioDeEstado(reducir: reducirMovimiento), value: coordinador.estado)
    }

    /// En reposo la isla es el notch: sin hombros, para no asomarse sobre la barra de menús.
    private var hombro: CGFloat {
        coordinador.geometria.tieneNotch && coordinador.estado != .reposo ? Medidas.hombro : 0
    }

    private var radio: CGFloat {
        switch coordinador.estado {
        case .reposo, .compacto: Medidas.radioCompacto
        case .aviso, .expandido: Medidas.radioExpandido
        }
    }

    @ViewBuilder private var silueta: some View {
        if coordinador.geometria.tieneNotch {
            FormaDeIsla(radioInferior: radio, hombro: hombro).fill(Paleta.fondo)
        } else {
            // Sin notch la isla flota bajo la barra de menús: píldora con las cuatro esquinas redondas.
            RoundedRectangle(cornerRadius: min(radio, coordinador.tamano.height / 2)).fill(Paleta.fondo)
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
            HStack(spacing: 4) {
                // Con un solo módulo no hay a dónde cambiar: la barra queda limpia.
                if modulos.count > 1 {
                    ForEach(modulos.filter { $0.lado == .izquierda }) { boton($0) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(width: coordinador.geometria.pantalla.notch?.width ?? 0)

            HStack(spacing: 4) {
                if modulos.count > 1 {
                    ForEach(modulos.filter { $0.lado == .derecha }) { boton($0) }
                }
                engrane
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Medidas.margenLateral)
    }

    private func boton(_ modulo: IdentidadDeModulo) -> some View {
        let abierto = coordinador.moduloAbierto?.identidad.id == modulo.id
        return Button {
            coordinador.recibir(.elegirModulo(modulo.id))
        } label: {
            Image(systemName: modulo.icono)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(abierto ? Color(hex: modulo.color) : Paleta.textoDeApoyo)
                .frame(width: 24, height: 24)
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
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Paleta.textoDeApoyo)
                .frame(width: 24, height: 24)
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
