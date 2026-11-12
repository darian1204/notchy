import NotchyCore
import NotchyDesign
import SwiftUI

/// Lo que abre el hover: una tarjeta por módulo con lo más reciente de cada uno.
@MainActor
public final class ModuloDeInicio: ModuloDeIsla {
    public let identidad = IdentidadDeModulo(
        id: ModulosBase.inicio, nombre: "Inicio", icono: "house.fill", color: 0xFFFFFF, lado: .izquierda)
    public let tamanoExpandido = Medidas.inicio
    private let portapapeles: ModeloDePortapapeles?
    private let alAbrirModulo: (@MainActor (String) -> Void)?

    public init(
        portapapeles: ModeloDePortapapeles? = nil,
        alAbrirModulo: (@MainActor (String) -> Void)? = nil
    ) {
        self.portapapeles = portapapeles
        self.alAbrirModulo = alAbrirModulo
    }

    public var vistaExpandida: AnyView {
        AnyView(VistaDeInicio(portapapeles: portapapeles, alAbrirModulo: alAbrirModulo))
    }
}

struct VistaDeInicio: View {
    let portapapeles: ModeloDePortapapeles?
    let alAbrirModulo: (@MainActor (String) -> Void)?

    var body: some View {
        HStack(spacing: Medidas.separacion) {
            TarjetaVacia(titulo: "Agenda", icono: "calendar", color: Paleta.agenda)
            TarjetaVacia(titulo: "Ahora suena", icono: "music.note", color: Paleta.musica)
            TarjetaPortapapeles(portapapeles: portapapeles) {
                alAbrirModulo?("portapapeles")
            }
            TarjetaVacia(titulo: "Acciones", icono: "bolt.fill", color: Paleta.agente)
        }
    }
}

private struct TarjetaPortapapeles: View {
    let portapapeles: ModeloDePortapapeles?
    let alTocar: @MainActor () -> Void

    var body: some View {
        let ultimo = portapapeles?.elementos.first
        return Button(action: alTocar) {
            Tarjeta {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Último copiado", systemImage: "doc.on.clipboard")
                        .rotulo(Paleta.portapapeles)
                    Spacer(minLength: 0)
                    if let ultimo {
                        Text(ultimo.texto.replacingOccurrences(of: "\n", with: " "))
                            .textoDeCuerpo()
                            .lineLimit(2)
                        if let app = ultimo.appOrigen {
                            Text(app).textoDeApoyo().lineLimit(1)
                        }
                    } else {
                        Text("Sin elementos copiados").textoDeApoyo()
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Abrir Portapapeles")
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
