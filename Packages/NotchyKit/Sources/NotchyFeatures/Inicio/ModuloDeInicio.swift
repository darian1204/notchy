import NotchyCore
import NotchyDesign
import SwiftUI

/// Lo que abre el hover: una tarjeta por módulo con lo más reciente de cada uno.
/// En M1 las tarjetas están vacías; cada módulo llena la suya cuando llega.
@MainActor
public final class ModuloDeInicio: ModuloDeIsla {
    public let identidad = IdentidadDeModulo(
        id: ModulosBase.inicio, nombre: "Inicio", icono: "house.fill", color: 0xFFFFFF, lado: .izquierda)
    public let tamanoExpandido = Medidas.inicio

    public init() {}

    public var vistaExpandida: AnyView { AnyView(VistaDeInicio()) }
}

struct VistaDeInicio: View {
    var body: some View {
        HStack(spacing: Medidas.separacion) {
            TarjetaVacia(titulo: "Agenda", icono: "calendar", color: Paleta.agenda)
            TarjetaVacia(titulo: "Ahora suena", icono: "music.note", color: Paleta.musica)
            TarjetaVacia(titulo: "Último copiado", icono: "doc.on.clipboard", color: Paleta.portapapeles)
            TarjetaVacia(titulo: "Acciones", icono: "bolt.fill", color: Paleta.agente)
        }
    }
}

private struct TarjetaVacia: View {
    let titulo: String
    let icono: String
    let color: Color

    var body: some View {
        Tarjeta {
            VStack(alignment: .leading, spacing: 6) {
                Label(titulo, systemImage: icono).rotulo(color)
                Spacer(minLength: 0)
                Text("Aún sin conectar").textoDeApoyo()
            }
        }
        .accessibilityElement(children: .combine)
    }
}
