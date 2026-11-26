import NotchyCore
import NotchyDesign
import SwiftUI

/// Muestra en Ajustes cómo queda la isla con el nivel, el tintado y el tema elegidos, sobre un fondo
/// de colores para que se note la refracción. Usa los mismos materiales que la isla real.
struct VistaPreviaDeVidrio: View {
    let estilo: EstiloDeVidrio
    let tintado: Double
    /// Color del tema del panel ya resuelto.
    let colorDePanel: Color

    private var vidrio: VidrioDeIsla {
        VidrioDeIsla(
            pildoras: estilo.pildoras,
            tarjetas: estilo.tarjetas,
            fondo: estilo.fondo,
            tintado: Ajustes.limitarTintado(tintado)
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            fondoDeEscritorio
            isla
        }
        .frame(height: 168)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .environment(\.vidrioDeIsla, vidrio)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vista previa del liquid glass")
    }

    /// Fondo fijo con manchas de color: el vidrio necesita algo detrás para verse.
    private var fondoDeEscritorio: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x6FA8DC), Color(hex: 0x3E7F5A)],
                startPoint: .top,
                endPoint: .bottom
            )
            Circle().fill(Color(hex: 0xF4C45A)).frame(width: 120).offset(x: -120, y: 30).blur(radius: 18)
            Circle().fill(Color(hex: 0xE0628A)).frame(width: 110).offset(x: 130, y: 50).blur(radius: 20)
            Capsule().fill(Color.white.opacity(0.7)).frame(width: 140, height: 26).offset(x: 40, y: -40)
                .blur(radius: 6)
        }
    }

    private var isla: some View {
        let forma = UnevenRoundedRectangle(
            bottomLeadingRadius: 26,
            bottomTrailingRadius: 26,
            style: .continuous
        )
        return VStack(spacing: 10) {
            HStack(spacing: 6) {
                pildora("house.fill", activa: true)
                pildora("square.stack.3d.up.fill", activa: false)
                pildora("sparkles", activa: false)
            }
            HStack(spacing: 8) {
                tarjeta(icono: "music.note", ancho: 120)
                tarjeta(icono: "tray.fill", ancho: 80)
            }
        }
        .padding(.top, 22)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .background { fondoDeIsla(forma) }
        .padding(.horizontal, 24)
    }

    @ViewBuilder private func fondoDeIsla(_ forma: UnevenRoundedRectangle) -> some View {
        let color = colorDePanel
        if vidrio.fondo {
            let velo = LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.1),
                    .init(color: .black.opacity(0.75), location: 0.14),
                    .init(color: .black.opacity(0.35), location: 0.2),
                    .init(color: .black.opacity(0), location: 0.28),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            forma.fill(vidrio.capa(color, minimo: 0.12))
                .glassEffect(vidrio.material(), in: forma)
                .overlay {
                    forma.fill(velo)
                    forma.stroke(velo, lineWidth: 3)
                }
        } else {
            forma.fill(LinearGradient(colors: [.black, color], startPoint: .top, endPoint: .bottom))
        }
    }

    private func pildora(_ simbolo: String, activa: Bool) -> some View {
        Image(systemName: simbolo)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(activa ? Color.white : Color.white.opacity(0.7))
            .frame(width: 40, height: 22)
            .superficieDeIsla(.pildora, en: Capsule(), alta: activa)
    }

    private func tarjeta(icono: String, ancho: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icono)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Capsule().fill(Color.white.opacity(0.75)).frame(width: ancho * 0.6, height: 5)
            Capsule().fill(Color.white.opacity(0.4)).frame(width: ancho * 0.4, height: 5)
        }
        .padding(10)
        .frame(width: ancho, height: 62, alignment: .topLeading)
        .superficieDeIsla(.tarjeta, en: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
