import NotchyCore
import NotchyDesign
import SwiftUI

/// Una cosa activa ahora, lista para mostrarse en el Flujo.
struct ElementoDeFlujo: Identifiable, Equatable {
    let id: String
    let titulo: String
    let detalle: String
    let valor: String
    let simbolo: String
    let color: UInt32
    /// Módulo que se abre al tocarlo.
    let modulo: String
    var enVivo = false
}

/// Qué entra al Flujo. Función pura para poder probarla sin modelos.
enum CalculoDeFlujo {
    /// Lo copiado hace más de esto ya no cuenta como activo.
    static let vigenciaDeCopiado: TimeInterval = 15 * 60
    /// Eventos que empiezan dentro de este margen.
    static let margenDeEvento: TimeInterval = 3 * 60 * 60

    struct Entrada {
        var grabando = false
        var segundosGrabando = 0
        var tituloDeGrabacion: String?
        var eventos: [EventoDeCalendario] = []
        var archivosEnBandeja = 0
        var ultimoCopiado: ElementoDePortapapeles?
        var cancion: String?
        var artista: String?
        var ahora = Date.now
    }

    static func elementos(_ entrada: Entrada) -> [ElementoDeFlujo] {
        var lista: [ElementoDeFlujo] = []
        if entrada.grabando {
            lista.append(
                ElementoDeFlujo(
                    id: "grabando", titulo: "Grabando", detalle: entrada.tituloDeGrabacion ?? "Nota de voz",
                    valor: cronometro(entrada.segundosGrabando), simbolo: "mic.fill", color: Paleta.hexGrabadora,
                    modulo: "grabadora", enVivo: true))
        }
        let ahora = entrada.ahora
        if let evento =
            entrada.eventos
            .filter({ !$0.todoElDia && $0.fin > ahora && $0.inicio.timeIntervalSince(ahora) <= margenDeEvento })
            .min(by: { $0.inicio < $1.inicio })
        {
            let minutos = Int(evento.inicio.timeIntervalSince(ahora) / 60)
            let valor = minutos <= 0 ? "ahora" : (minutos < 60 ? "en \(minutos) min" : "en \(minutos / 60) h")
            let hora = evento.inicio.formatted(date: .omitted, time: .shortened)
            lista.append(
                ElementoDeFlujo(
                    id: "evento", titulo: evento.titulo,
                    detalle: [hora, evento.ubicacion].compactMap { $0 }.joined(separator: " · "),
                    valor: valor, simbolo: "calendar", color: Paleta.hexAgenda, modulo: "agenda"))
        }
        if entrada.archivosEnBandeja > 0 {
            let n = entrada.archivosEnBandeja
            lista.append(
                ElementoDeFlujo(
                    id: "bandeja", titulo: "Bandeja", detalle: n == 1 ? "1 archivo" : "\(n) archivos",
                    valor: "\(n)", simbolo: "tray.fill", color: Paleta.hexBandeja, modulo: "bandeja"))
        }
        if let copiado = entrada.ultimoCopiado, ahora.timeIntervalSince(copiado.creado) <= vigenciaDeCopiado {
            let minutos = max(0, Int(ahora.timeIntervalSince(copiado.creado) / 60))
            lista.append(
                ElementoDeFlujo(
                    id: "portapapeles", titulo: "Portapapeles",
                    detalle: copiado.texto.trimmingCharacters(in: .whitespacesAndNewlines),
                    valor: minutos == 0 ? "ahora" : "hace \(minutos) min", simbolo: "doc.on.clipboard",
                    color: Paleta.hexPortapapeles, modulo: "portapapeles"))
        }
        if let cancion = entrada.cancion {
            lista.append(
                ElementoDeFlujo(
                    id: "musica", titulo: cancion, detalle: entrada.artista ?? "Sonando",
                    valor: "", simbolo: "music.note", color: Paleta.hexMusica, modulo: "musica"))
        }
        return lista
    }

    static func cronometro(_ segundos: Int) -> String {
        let s = max(0, segundos)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Pestaña "Flujo" del estilo tarjetas: lo que está pasando ahora. No tiene ícono en la barra clásica.
@MainActor
public final class ModuloDeFlujo: ModuloDeIsla {
    public let identidad = IdentidadDeModulo(
        id: ModulosBase.flujo, nombre: "Flujo", icono: "square.stack.3d.up.fill", color: 0xFFFFFF, lado: .izquierda)
    public let tamanoExpandido = Medidas.inicioTarjetas
    public var enBarraClasica: Bool { false }
    public var insignia: Int? {
        let total = elementos.count
        return total > 0 ? total : nil
    }

    private let agenda: ModeloDeAgenda?
    private let grabadora: ModeloDeGrabadora?
    private let bandeja: ModeloDeBandeja?
    private let portapapeles: ModeloDePortapapeles?
    private let ahoraSuena: ModeloDeAhoraSuena?
    private let alAbrirModulo: (@MainActor (String) -> Void)?

    public init(
        agenda: ModeloDeAgenda? = nil,
        grabadora: ModeloDeGrabadora? = nil,
        bandeja: ModeloDeBandeja? = nil,
        portapapeles: ModeloDePortapapeles? = nil,
        ahoraSuena: ModeloDeAhoraSuena? = nil,
        alAbrirModulo: (@MainActor (String) -> Void)? = nil
    ) {
        self.agenda = agenda
        self.grabadora = grabadora
        self.bandeja = bandeja
        self.portapapeles = portapapeles
        self.ahoraSuena = ahoraSuena
        self.alAbrirModulo = alAbrirModulo
    }

    var elementos: [ElementoDeFlujo] {
        let sonando = ahoraSuena?.estadoActual.flatMap { $0.reproduciendo ? $0 : nil }
        return CalculoDeFlujo.elementos(
            .init(
                grabando: grabadora?.grabando ?? false,
                segundosGrabando: grabadora?.segundosTranscurridos ?? 0,
                tituloDeGrabacion: grabadora?.reunionActual?.titulo,
                eventos: agenda?.eventosDelMes ?? [],
                archivosEnBandeja: bandeja?.elementos.count ?? 0,
                ultimoCopiado: portapapeles?.elementos.first,
                cancion: sonando?.titulo,
                artista: sonando?.artista
            ))
    }

    public var vistaExpandida: AnyView {
        AnyView(VistaDeFlujo(modulo: self, alAbrirModulo: alAbrirModulo))
    }
}

private struct VistaDeFlujo: View {
    let modulo: ModuloDeFlujo
    let alAbrirModulo: (@MainActor (String) -> Void)?

    var body: some View {
        // El reloj refresca cronómetros y "en N min" aunque ningún modelo cambie.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let elementos = modulo.elementos
            if elementos.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 22))
                        .foregroundStyle(Paleta.decorativo)
                    Text("Nada activo ahora").textoDeApoyo()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8
                ) {
                    ForEach(elementos.prefix(6)) { elemento in
                        fila(elemento)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private func fila(_ elemento: ElementoDeFlujo) -> some View {
        let color = Color(hex: elemento.color)
        return Button {
            alAbrirModulo?(elemento.modulo)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: elemento.simbolo)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        if elemento.enVivo {
                            Circle().fill(Paleta.grabadora).frame(width: 6, height: 6)
                        }
                        Text(elemento.titulo)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Paleta.texto)
                            .lineLimit(1)
                    }
                    Text(elemento.detalle).textoDeApoyo().lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(elemento.valor)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(elemento.id == "evento" ? color : Paleta.texto)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Paleta.superficie, in: RoundedRectangle(cornerRadius: Medidas.radioDeTarjetaInterna))
            .overlay(
                RoundedRectangle(cornerRadius: Medidas.radioDeTarjetaInterna).strokeBorder(Paleta.bordeSuave)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(elemento.titulo), \(elemento.detalle), \(elemento.valor)")
    }
}
