import AppKit
import Foundation
import NotchyCore
import NotchyDesign
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Gestiona la nota rápida del Home conectada directamente a `00-inbox/inbox.md` del vault de Obsidian.
@MainActor
@Observable
public final class GestorDeInboxObsidian {
    public var borrador = ""
    public private(set) var lineasRecientes: [String] = []
    public private(set) var mensajeEstado: String?

    @ObservationIgnored private let ajustes: Ajustes
    @ObservationIgnored private let alAbrirURL: (@MainActor (URL) -> Void)?

    public init(
        ajustes: Ajustes,
        alAbrirURL: (@MainActor (URL) -> Void)? = nil
    ) {
        self.ajustes = ajustes
        self.alAbrirURL = alAbrirURL
        recargar()
    }

    public var urlCarpetaInbox: URL {
        ajustes.urlCarpetaInboxObsidian
    }

    public var urlNotaInbox: URL {
        ajustes.urlNotaInboxObsidian
    }

    public func recargar() {
        let url = urlNotaInbox
        guard let texto = try? String(contentsOf: url, encoding: .utf8) else {
            lineasRecientes = []
            return
        }
        lineasRecientes = Self.extraerLineasCapturadas(de: texto)
    }

    @discardableResult
    public func guardarBorrador() -> Bool {
        let limpio = borrador.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { return false }
        let ok = agregarLinea(limpio)
        if ok {
            borrador = ""
        }
        return ok
    }

    @discardableResult
    public func agregarLinea(_ linea: String) -> Bool {
        let limpia = linea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpia.isEmpty else { return false }
        let carpeta = urlCarpetaInbox
        let archivo = urlNotaInbox
        do {
            try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
            let actual: String
            if let existente = try? String(contentsOf: archivo, encoding: .utf8) {
                actual = existente
            } else {
                actual = Self.plantillaInicialInbox
            }
            let separador = actual.hasSuffix("\n") ? "" : "\n"
            let actualizado = actual + separador + limpia + "\n"
            try actualizado.write(to: archivo, atomically: true, encoding: .utf8)
            mensajeEstado = "Guardado en inbox.md"
            recargar()
            return true
        } catch {
            mensajeEstado = "Error al escribir en inbox.md"
            return false
        }
    }

    public func abrirEnObsidian() {
        let vaultNombre = URL(fileURLWithPath: ajustes.rutaVaultObsidian).lastPathComponent
        var componentes = URLComponents()
        componentes.scheme = "obsidian"
        componentes.host = "open"
        componentes.queryItems = [
            URLQueryItem(name: "vault", value: vaultNombre),
            URLQueryItem(name: "file", value: "00-inbox/inbox"),
        ]
        if let urlObsidian = componentes.url {
            alAbrirURL?(urlObsidian)
        } else {
            alAbrirURL?(urlNotaInbox)
        }
    }

    public func abrirCarpetaEnFinder() {
        alAbrirURL?(urlCarpetaInbox)
    }

    static func extraerLineasCapturadas(de contenido: String) -> [String] {
        let lineas = contenido.components(separatedBy: .newlines)
        var separadores = 0
        var cuerpo: [String] = []
        for linea in lineas {
            let podada = linea.trimmingCharacters(in: .whitespaces)
            if podada == "---" {
                separadores += 1
                continue
            }
            if separadores >= 3 {
                if !podada.isEmpty {
                    cuerpo.append(podada)
                }
            }
        }
        return Array(cuerpo.suffix(4).reversed())
    }

    private static let plantillaInicialInbox = """
        ---
        tipo: inbox
        creado: 2026-10-13
        actualizado: 2026-11-12
        tags: [inbox]
        fuentes: []
        estado: semilla
        ---
        # Inbox

        Escribe abajo lo que sea, sin formato. `/inbox` lo procesa y deja esta nota vacía otra vez.

        ---
        """
}

/// El módulo que muestra el hover cuando el usuario no eligió otro, inspirado en el layout de 3 columnas:
/// Reproductor a la izquierda, Archivos (Bandeja / AirDrop) al centro y Notas (Obsidian Inbox) a la derecha.
@MainActor
public final class ModuloDeInicio: ModuloDeIsla {
    public let identidad = IdentidadDeModulo(
        id: ModulosBase.inicio, nombre: "Inicio", icono: "house.fill", color: 0xFFFFFF, lado: .izquierda)
    public let tamanoExpandido = Medidas.inicio
    private let agenda: ModeloDeAgenda?
    private let ahoraSuena: ModeloDeAhoraSuena?
    private let portapapeles: ModeloDePortapapeles?
    private let bandeja: ModeloDeBandeja?
    private let airdrop: ModeloDeAirDrop?
    private let inbox: GestorDeInboxObsidian?
    private let alAbrirModulo: (@MainActor (String) -> Void)?

    public init(
        agenda: ModeloDeAgenda? = nil,
        ahoraSuena: ModeloDeAhoraSuena? = nil,
        portapapeles: ModeloDePortapapeles? = nil,
        bandeja: ModeloDeBandeja? = nil,
        airdrop: ModeloDeAirDrop? = nil,
        inbox: GestorDeInboxObsidian? = nil,
        alAbrirModulo: (@MainActor (String) -> Void)? = nil
    ) {
        self.agenda = agenda
        self.ahoraSuena = ahoraSuena
        self.portapapeles = portapapeles
        self.bandeja = bandeja
        self.airdrop = airdrop
        self.inbox = inbox
        self.alAbrirModulo = alAbrirModulo
    }

    public var vistaExpandida: AnyView {
        AnyView(
            VistaDeInicio(
                ahoraSuena: ahoraSuena,
                bandeja: bandeja,
                airdrop: airdrop,
                inbox: inbox,
                alAbrirModulo: alAbrirModulo
            ))
    }
}

struct VistaDeInicio: View {
    let ahoraSuena: ModeloDeAhoraSuena?
    let bandeja: ModeloDeBandeja?
    let airdrop: ModeloDeAirDrop?
    let inbox: GestorDeInboxObsidian?
    let alAbrirModulo: (@MainActor (String) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            ColumnaMusicaInicio(ahoraSuena: ahoraSuena) {
                alAbrirModulo?("musica")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            divisorVertical

            ColumnaArchivosInicio(
                bandeja: bandeja,
                airdrop: airdrop,
                alAbrirBandeja: { alAbrirModulo?("bandeja") },
                alAbrirAirDrop: { alAbrirModulo?("airdrop") }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            divisorVertical

            ColumnaNotasInboxInicio(inbox: inbox)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 4)
    }

    private var divisorVertical: some View {
        Rectangle()
            .fill(Color.white.opacity(0.09))
            .frame(width: 1)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
    }
}

private struct ColumnaMusicaInicio: View {
    let ahoraSuena: ModeloDeAhoraSuena?
    let alAbrirMusica: @MainActor () -> Void

    var body: some View {
        let estado = ahoraSuena?.estadoActual
        return VStack(alignment: .leading, spacing: 6) {
            Button(action: alAbrirMusica) {
                HStack(spacing: 10) {
                    CaratulaDeCancion(datos: estado?.caratulaPNG, tamano: 62, radio: 12)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(estado?.titulo ?? "Nada sonando")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Paleta.texto)
                            .lineLimit(1)
                        Text(estado?.artista ?? estado?.appOrigen ?? "Música / Spotify")
                            .font(.system(size: 11))
                            .foregroundStyle(Paleta.textoDeApoyo)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Abrir Ahora suena")

            if let estado {
                BarraDeProgresoMusical(estado: estado)
            } else {
                HStack(spacing: 6) {
                    Text("0:00")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Paleta.textoDeApoyo)
                    Capsule()
                        .fill(Paleta.superficieAlta)
                        .frame(height: 3)
                    Text("0:00")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Paleta.textoDeApoyo)
                }
            }

            HStack(spacing: 18) {
                Button {
                    ahoraSuena?.anterior()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Paleta.texto)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Canción anterior")

                Button {
                    ahoraSuena?.alternarReproduccion()
                } label: {
                    Image(systemName: estado?.reproduciendo == true ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Paleta.fondo)
                        .frame(width: 32, height: 32)
                        .background(Paleta.texto, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(estado?.reproduciendo == true ? "Pausar" : "Reproducir")

                Button {
                    ahoraSuena?.siguiente()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Paleta.texto)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Siguiente canción")
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 2)
    }
}

private struct ColumnaArchivosInicio: View {
    let bandeja: ModeloDeBandeja?
    let airdrop: ModeloDeAirDrop?
    let alAbrirBandeja: @MainActor () -> Void
    let alAbrirAirDrop: @MainActor () -> Void
    @State private var arrastrandoSobreArchivos = false

    var body: some View {
        let elementosBandeja = bandeja?.elementos ?? []
        let recibidosAirDrop = airdrop?.recibidos ?? []
        return VStack(spacing: 8) {
            if let primeroBandeja = elementosBandeja.first {
                VStack(spacing: 6) {
                    MiniaturaDeArchivo(url: primeroBandeja.urlParaArrastrar, tamano: 44)
                        .onDrag {
                            NSItemProvider(object: primeroBandeja.urlParaArrastrar as NSURL)
                        }
                    Text(primeroBandeja.nombre)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Paleta.texto)
                        .lineLimit(1)
                    Text("\(elementosBandeja.count) en Bandeja · arrastra o abre")
                        .font(.system(size: 10))
                        .foregroundStyle(Paleta.textoDeApoyo)
                        .lineLimit(1)
                }
            } else if let primeroAirDrop = recibidosAirDrop.first {
                VStack(spacing: 6) {
                    MiniaturaDeArchivo(url: primeroAirDrop.url, tamano: 44)
                        .onDrag {
                            NSItemProvider(object: primeroAirDrop.url as NSURL)
                        }
                    Text(primeroAirDrop.nombre)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Paleta.texto)
                        .lineLimit(1)
                    Text("Recibido por AirDrop")
                        .font(.system(size: 10))
                        .foregroundStyle(Paleta.textoDeApoyo)
                        .lineLimit(1)
                }
            } else {
                Button(action: alAbrirBandeja) {
                    VStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(Paleta.agenda)
                        Text("Files")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Paleta.texto)
                        Text("Suelta archivos aquí")
                            .font(.system(size: 10))
                            .foregroundStyle(Paleta.textoDeApoyo)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Button("Bandeja", action: alAbrirBandeja)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Paleta.textoDeApoyo)
                    .buttonStyle(.plain)
                Text("·").foregroundStyle(Paleta.textoDeApoyo)
                Button("AirDrop", action: alAbrirAirDrop)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Paleta.airdrop)
                    .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    arrastrandoSobreArchivos ? Paleta.agenda : Color.clear,
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $arrastrandoSobreArchivos) { proveedores in
            for proveedor in proveedores {
                _ = proveedor.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        _ = bandeja?.agregarArchivos([url])
                    }
                }
            }
            return true
        }
    }
}

private struct ColumnaNotasInboxInicio: View {
    let inbox: GestorDeInboxObsidian?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    inbox?.abrirEnObsidian()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "note.text")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Paleta.portapapeles)
                        Text("Notes · Inbox")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Paleta.texto)
                    }
                }
                .buttonStyle(.plain)
                .help("Abrir 00-inbox/inbox.md en Obsidian")

                Spacer(minLength: 0)

                Button {
                    inbox?.abrirCarpetaEnFinder()
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(Paleta.textoDeApoyo)
                }
                .buttonStyle(.plain)
                .help("Abrir carpeta 00-inbox en Finder")
            }

            if let inbox {
                @Bindable var gestor = inbox
                HStack(spacing: 4) {
                    TextField("Nota rápida al inbox…", text: $gestor.borrador)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Paleta.texto)
                        .onSubmit {
                            _ = inbox.guardarBorrador()
                        }
                    Button {
                        _ = inbox.guardarBorrador()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(
                                gestor.borrador.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Paleta.textoDeApoyo : Paleta.portapapeles
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(gestor.borrador.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Guardar en 00-inbox/inbox.md")
                }
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(Paleta.superficieAlta, in: RoundedRectangle(cornerRadius: 8))

                if inbox.lineasRecientes.isEmpty {
                    Spacer(minLength: 0)
                    Button {
                        inbox.abrirEnObsidian()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "note.text")
                                .font(.system(size: 24))
                                .foregroundStyle(Paleta.portapapeles)
                            Text("Inbox limpio · escribe arriba")
                                .font(.system(size: 10))
                                .foregroundStyle(Paleta.textoDeApoyo)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(inbox.lineasRecientes.prefix(3).enumerated()), id: \.offset) { _, linea in
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Paleta.portapapeles)
                                    .frame(width: 4, height: 4)
                                Text(linea)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Paleta.textoDeApoyo)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, 2)
        .onAppear {
            inbox?.recargar()
        }
    }
}
