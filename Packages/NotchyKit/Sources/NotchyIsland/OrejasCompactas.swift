import NotchyCore
import NotchyDesign
import SwiftUI

/// Orejas de la isla cerrada, al estilo de la Dynamic Island: la actividad principal a los lados del
/// notch, más grande al pasar el cursor, o una actividad breve de unos segundos.
struct VistaDeOrejas: View {
    let coordinador: CoordinadorDeIsla
    let contenido: CoordinadorDeIsla.ContenidoDeOrejas
    let acento: Color?
    @Environment(\.accessibilityReduceMotion) private var reducirMovimiento

    var body: some View {
        Button(action: abrir) {
            HStack(spacing: 0) {
                izquierda
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                Color.clear.frame(width: coordinador.geometria.pantalla.notch?.width ?? 0)
                derecha
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .id(clave)
            .transition(cambio)
            .contentShape(Rectangle())
        }
        .buttonStyle(.presion)
        .accessibilityLabel(etiqueta)
    }

    /// Cambiar de actividad (o ampliarla) vuelve a montar el contenido para que entre con escala.
    private var clave: String {
        switch contenido {
        case .modulo(let modulo, let ampliado): "\(modulo.identidad.id)-\(ampliado)"
        case .breve(let hud): "breve-\(hud.tipo.rawValue)"
        }
    }

    private var cambio: AnyTransition {
        reducirMovimiento ? .opacity : .scale(scale: 0.85).combined(with: .opacity)
    }

    @ViewBuilder private var izquierda: some View {
        switch contenido {
        case .modulo(let modulo, let ampliado):
            (ampliado ? modulo.orejaIzquierdaAmpliada : nil) ?? modulo.orejaIzquierdaCompacta
        case .breve(let hud):
            IconoDeActividadBreve(hud: hud, acento: acento)
        }
    }

    @ViewBuilder private var derecha: some View {
        switch contenido {
        case .modulo(let modulo, let ampliado):
            (ampliado ? modulo.orejaDerechaAmpliada : nil) ?? modulo.orejaDerechaCompacta
        case .breve(let hud):
            DatoDeActividadBreve(hud: hud, acento: acento)
        }
    }

    private var etiqueta: String {
        switch contenido {
        case .modulo(let modulo, _): modulo.identidad.nombre
        case .breve(let hud): "\(hud.tipo.rawValue) \(hud.etiqueta)"
        }
    }

    private func abrir() {
        switch contenido {
        case .modulo(let modulo, _): coordinador.recibir(.elegirModulo(modulo.identidad.id))
        case .breve(let hud):
            if let id = hud.tipo.modulo { coordinador.recibir(.elegirModulo(id)) }
        }
    }
}

/// Color de cada actividad breve: verde al cargar, rojo con batería baja, acento para archivos.
func colorDeActividadBreve(_ tipo: TipoDeHUD, acento: Color?) -> Color {
    switch tipo {
    case .cargando: Color(hex: 0x34C759)
    case .bateriaBaja: Paleta.grabadora
    case .archivos, .airdropEnviado, .airdropRecibido: acento ?? Color(hex: 0x5AA9FF)
    case .volumen, .silencio, .brillo, .desconectado: Paleta.texto
    }
}

struct IconoDeActividadBreve: View {
    let hud: EstadoDeHUDSistema
    let acento: Color?

    var body: some View {
        Image(systemName: hud.tipo.icono)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(colorDeActividadBreve(hud.tipo, acento: acento))
            .contentTransition(.symbolEffect(.replace))
    }
}

/// Barra de nivel para volumen y brillo; texto para batería y archivos.
struct DatoDeActividadBreve: View {
    let hud: EstadoDeHUDSistema
    let acento: Color?

    var body: some View {
        if hud.tipo.conBarra {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Paleta.texto.opacity(0.22))
                    Capsule()
                        .fill(acento ?? Paleta.texto)
                        .frame(width: max(5, geo.size.width * hud.nivel))
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(width: 40, height: 5)
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: hud.nivel)
        } else if let simbolo = hud.simbolo {
            // Archivos: el ícono de su clase (imagen, video, PDF…) y el número si son varios.
            HStack(spacing: 4) {
                Image(systemName: simbolo)
                    .font(.system(size: 13, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                if hud.cantidad > 1 {
                    Text("\(hud.cantidad)")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText())
                }
            }
            .foregroundStyle(Paleta.texto)
            .accessibilityLabel(hud.etiqueta)
        } else {
            Text(hud.etiqueta)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(hud.tipo == .bateriaBaja ? Paleta.grabadora : Paleta.texto)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
    }
}

/// Burbuja de la segunda actividad, separada a la derecha del notch.
struct BurbujaDeActividad: View {
    let coordinador: CoordinadorDeIsla
    let contenido: CoordinadorDeIsla.ContenidoDeBurbuja
    let acento: Color?
    let lado: CGFloat

    var body: some View {
        Button(action: abrir) {
            interior
                .frame(width: lado, height: lado)
                .background(Paleta.fondo, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.presion)
        .accessibilityLabel(etiqueta)
    }

    @ViewBuilder private var interior: some View {
        switch contenido {
        case .modulo(let modulo):
            (modulo.burbujaCompacta ?? modulo.orejaIzquierdaCompacta)
                .scaleEffect(0.9)
        case .breve(let hud):
            IconoDeActividadBreve(hud: hud, acento: acento)
                .scaleEffect(0.85)
        }
    }

    private var etiqueta: String {
        switch contenido {
        case .modulo(let modulo): modulo.identidad.nombre
        case .breve(let hud): hud.etiqueta
        }
    }

    private func abrir() {
        switch contenido {
        case .modulo(let modulo): coordinador.recibir(.elegirModulo(modulo.identidad.id))
        case .breve(let hud):
            if let id = hud.tipo.modulo { coordinador.recibir(.elegirModulo(id)) }
        }
    }
}
