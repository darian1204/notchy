import NotchyCore
import NotchyDesign
import SwiftUI

/// El módulo que muestra el hover cuando el usuario no eligió otro.
@MainActor
public final class ModuloDeInicio: ModuloDeIsla {
    public let identidad = IdentidadDeModulo(
        id: ModulosBase.inicio, nombre: "Inicio", icono: "house.fill", color: 0xFFFFFF, lado: .izquierda)
    public let tamanoExpandido = Medidas.inicio
    private let agenda: ModeloDeAgenda?
    private let ahoraSuena: ModeloDeAhoraSuena?
    private let portapapeles: ModeloDePortapapeles?
    private let alAbrirModulo: (@MainActor (String) -> Void)?

    public init(
        agenda: ModeloDeAgenda? = nil,
        ahoraSuena: ModeloDeAhoraSuena? = nil,
        portapapeles: ModeloDePortapapeles? = nil,
        alAbrirModulo: (@MainActor (String) -> Void)? = nil
    ) {
        self.agenda = agenda
        self.ahoraSuena = ahoraSuena
        self.portapapeles = portapapeles
        self.alAbrirModulo = alAbrirModulo
    }

    public var vistaExpandida: AnyView {
        AnyView(
            VistaDeInicio(
                agenda: agenda,
                ahoraSuena: ahoraSuena,
                portapapeles: portapapeles,
                alAbrirModulo: alAbrirModulo
            ))
    }
}

struct VistaDeInicio: View {
    let agenda: ModeloDeAgenda?
    let ahoraSuena: ModeloDeAhoraSuena?
    let portapapeles: ModeloDePortapapeles?
    let alAbrirModulo: (@MainActor (String) -> Void)?

    var body: some View {
        HStack(spacing: Medidas.separacion) {
            TarjetaAgenda(agenda: agenda) {
                alAbrirModulo?("agenda")
            }
            TarjetaAhoraSuena(ahoraSuena: ahoraSuena) {
                alAbrirModulo?("musica")
            }
            TarjetaPortapapeles(portapapeles: portapapeles) {
                alAbrirModulo?("portapapeles")
            }
            TarjetaVacia(titulo: "Acciones", icono: "bolt.fill", color: Paleta.agente)
        }
    }
}

private struct TarjetaAgenda: View {
    let agenda: ModeloDeAgenda?
    let alTocar: @MainActor () -> Void

    var body: some View {
        let eventos = agenda?.eventosDeHoy ?? []
        let pendientes = agenda?.pendientes ?? []
        return Button(action: alTocar) {
            Tarjeta {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Agenda", systemImage: "calendar")
                        .rotulo(Paleta.agenda)
                    Spacer(minLength: 0)
                    if let primero = eventos.first {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(primero.titulo)
                                .textoDeCuerpo()
                                .lineLimit(2)
                            HStack(spacing: 4) {
                                Text(hora(de: primero))
                                    .textoDeApoyo()
                                if let minutos = agenda?.minutosRestantes(para: primero) {
                                    Text(minutos == 0 ? "· ahora" : "· en \(minutos)m")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Paleta.agenda)
                                }
                            }
                            .lineLimit(1)
                        }
                    } else if let pendiente = pendientes.first {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pendiente.titulo)
                                .textoDeCuerpo()
                                .lineLimit(2)
                            Text("Pendiente · \(pendiente.lista)")
                                .textoDeApoyo()
                                .lineLimit(1)
                        }
                    } else {
                        Text("Sin eventos hoy").textoDeApoyo()
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Abrir Agenda")
    }

    private func hora(de evento: EventoDeCalendario) -> String {
        if evento.todoElDia { return "Todo el día" }
        let formateador = DateFormatter()
        formateador.locale = Locale(identifier: "es_MX")
        formateador.dateFormat = "HH:mm"
        return formateador.string(from: evento.inicio)
    }
}

private struct TarjetaAhoraSuena: View {
    let ahoraSuena: ModeloDeAhoraSuena?
    let alTocar: @MainActor () -> Void

    var body: some View {
        let estado = ahoraSuena?.estadoActual
        return Button(action: alTocar) {
            Tarjeta {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Label("Ahora suena", systemImage: "music.note")
                            .rotulo(Paleta.musica)
                        Spacer(minLength: 0)
                        if estado?.reproduciendo == true {
                            EspectroDeAudio(barras: 4, alto: 12, reproduciendo: true)
                                .frame(width: 16, height: 12)
                        }
                    }
                    Spacer(minLength: 0)
                    if let estado {
                        HStack(spacing: 8) {
                            CaratulaDeCancion(datos: estado.caratulaPNG, tamano: 32, radio: 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(estado.titulo)
                                    .textoDeCuerpo()
                                    .lineLimit(1)
                                Text(estado.artista ?? estado.appOrigen ?? "Reproduciendo")
                                    .textoDeApoyo()
                                    .lineLimit(1)
                            }
                        }
                    } else {
                        Text("Nada sonando").textoDeApoyo()
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Abrir Ahora suena")
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
