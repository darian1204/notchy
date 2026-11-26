import AppKit
import Foundation
import NotchyCore
import NotchyDesign
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Gestiona la nota rápida del Home. Escribe en `00-inbox/inbox.md` del vault de Obsidian o, si el
/// usuario lo elige en Ajustes, al final de una página de Notion.
@MainActor
@Observable
public final class GestorDeInboxObsidian {
    public var borrador = ""
    public private(set) var lineasRecientes: [String] = []
    public private(set) var mensajeEstado: String?
    /// Lo enviado a Notion en esta sesión, lo más nuevo primero. Notion no se lee de vuelta.
    private var enviadasANotion: [String] = []
    /// Último envío a Notion en la fila; el siguiente espera a que termine.
    @ObservationIgnored private var colaDeNotion: Task<String, any Error>?

    @ObservationIgnored private let ajustes: Ajustes
    @ObservationIgnored private let alAbrirURL: (@MainActor (URL) -> Void)?
    @ObservationIgnored private let secretos: (any PuertoDeSecretos)?
    @ObservationIgnored private let notion: ClienteDeNotion

    public init(
        ajustes: Ajustes,
        alAbrirURL: (@MainActor (URL) -> Void)? = nil,
        secretos: (any PuertoDeSecretos)? = nil,
        notion: ClienteDeNotion = ClienteDeNotion()
    ) {
        self.ajustes = ajustes
        self.alAbrirURL = alAbrirURL
        self.secretos = secretos
        self.notion = notion
        recargar()
    }

    public var destino: DestinoDeInbox { ajustes.destinoDeInbox }

    /// Texto de ayuda para el campo y los botones: "Obsidian" o "Notion".
    public var nombreDelDestino: String { destino.nombre }

    public var urlCarpetaInbox: URL {
        ajustes.urlCarpetaInboxObsidian
    }

    public var urlNotaInbox: URL {
        ajustes.urlNotaInboxObsidian
    }

    public func recargar() {
        if destino == .notion {
            lineasRecientes = Array(enviadasANotion.prefix(4))
            return
        }
        let url = urlNotaInbox
        guard let texto = try? String(contentsOf: url, encoding: .utf8) else {
            lineasRecientes = []
            return
        }
        lineasRecientes = Self.extraerLineasCapturadas(de: texto)
    }

    /// Manda el borrador al inbox. Lo vacía al instante; si el envío falla, vuelve al campo.
    @discardableResult
    public func guardarBorrador() -> Bool {
        let limpio = borrador.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { return false }
        if destino == .obsidian {
            let ok = escribirEnObsidian(limpio)
            if ok { borrador = "" }
            return ok
        }
        borrador = ""
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await agregar(limpio)
            } catch {
                if borrador.isEmpty { borrador = limpio }
            }
        }
        return true
    }

    /// Agrega una línea al destino elegido y espera a que quede guardada. Los envíos a Notion van en
    /// fila, en el orden en que llegan. Devuelve el mensaje para mostrar.
    @discardableResult
    public func agregar(_ linea: String) async throws -> String {
        let limpia = linea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpia.isEmpty else { throw NotchyError.datos("La nota está vacía") }
        switch destino {
        case .obsidian:
            guard escribirEnObsidian(limpia) else {
                throw NotchyError.datos(mensajeEstado ?? "No se pudo escribir en inbox.md")
            }
            return "Guardado en inbox.md"
        case .notion:
            let anterior = colaDeNotion
            let envio = Task { [weak self] () throws -> String in
                _ = await anterior?.result
                guard let self else { throw CancellationError() }
                return try await enviarANotion(limpia)
            }
            colaDeNotion = envio
            return try await envio.value
        }
    }

    private func enviarANotion(_ texto: String) async throws -> String {
        guard let pagina = Notion.idDePagina(ajustes.paginaNotion) else {
            mensajeEstado = "Falta la página de Notion en Ajustes"
            throw NotchyError.datos(mensajeEstado ?? "")
        }
        guard let token = secretos?.leer(ClavesDeSecretos.tokenNotion), !token.isEmpty else {
            mensajeEstado = "Falta el token de Notion en Ajustes"
            throw NotchyError.datos(mensajeEstado ?? "")
        }
        mensajeEstado = "Enviando a Notion…"
        do {
            try await notion.agregar(texto, aPagina: pagina, token: token)
        } catch {
            mensajeEstado = (error as? NotchyError)?.errorDescription ?? "No se pudo enviar a Notion"
            throw NotchyError.datos(mensajeEstado ?? "")
        }
        let primera = texto.components(separatedBy: .newlines).first ?? texto
        enviadasANotion.insert(primera, at: 0)
        enviadasANotion = Array(enviadasANotion.prefix(4))
        mensajeEstado = "Guardado en Notion"
        recargar()
        return "Enviado al inbox de Notion"
    }

    private func escribirEnObsidian(_ limpia: String) -> Bool {
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

    /// Abre el inbox en su app: la nota en Obsidian o la página en Notion.
    public func abrirInbox() {
        if destino == .notion {
            if let id = Notion.idDePagina(ajustes.paginaNotion), let url = Notion.urlDePagina(id) {
                alAbrirURL?(url)
            }
            return
        }
        abrirEnObsidian()
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

/// El módulo que muestra el hover cuando el usuario no eligió otro, con diseño de 3 columnas:
/// Reproductor a la izquierda, Files (imágenes/archivos de Bandeja, AirDrop y Portapapeles sin texto) al centro, y Notes (Obsidian Inbox editable en vivo) a la derecha.
@MainActor
public final class ModuloDeInicio: ModuloDeIsla {
    public let identidad = IdentidadDeModulo(
        id: ModulosBase.inicio, nombre: "Inicio", icono: "house.fill", color: 0xFFFFFF, lado: .izquierda)
    public var tamanoExpandido: CGSize {
        ajustes?.estiloDeIsla == .tarjetas ? Medidas.inicioTarjetas : Medidas.inicio
    }
    private let agenda: ModeloDeAgenda?
    private let ahoraSuena: ModeloDeAhoraSuena?
    private let portapapeles: ModeloDePortapapeles?
    private let bandeja: ModeloDeBandeja?
    private let airdrop: ModeloDeAirDrop?
    private let inbox: GestorDeInboxObsidian?
    private let alAbrirModulo: (@MainActor (String) -> Void)?
    private let ajustes: Ajustes?
    private let clima: ModeloDeClima?
    private let screenTime: ModeloDeScreenTime?
    private let monitor: ModeloDeMonitorSistema?
    private let grabadora: ModeloDeGrabadora?
    private let modulosDisponibles: (@MainActor () -> [IdentidadDeModulo])?

    public init(
        agenda: ModeloDeAgenda? = nil,
        ahoraSuena: ModeloDeAhoraSuena? = nil,
        portapapeles: ModeloDePortapapeles? = nil,
        bandeja: ModeloDeBandeja? = nil,
        airdrop: ModeloDeAirDrop? = nil,
        inbox: GestorDeInboxObsidian? = nil,
        alAbrirModulo: (@MainActor (String) -> Void)? = nil,
        ajustes: Ajustes? = nil,
        clima: ModeloDeClima? = nil,
        screenTime: ModeloDeScreenTime? = nil,
        monitor: ModeloDeMonitorSistema? = nil,
        grabadora: ModeloDeGrabadora? = nil,
        modulosDisponibles: (@MainActor () -> [IdentidadDeModulo])? = nil
    ) {
        self.ajustes = ajustes
        self.clima = clima
        self.screenTime = screenTime
        self.monitor = monitor
        self.grabadora = grabadora
        self.modulosDisponibles = modulosDisponibles
        self.agenda = agenda
        self.ahoraSuena = ahoraSuena
        self.portapapeles = portapapeles
        self.bandeja = bandeja
        self.airdrop = airdrop
        self.inbox = inbox
        self.alAbrirModulo = alAbrirModulo
    }

    public var vistaExpandida: AnyView {
        if ajustes?.estiloDeIsla == .tarjetas {
            return AnyView(
                VistaDeInicioTarjetas(
                    fuentes: FuentesDeInicioTarjetas(
                        agenda: agenda, ahoraSuena: ahoraSuena, portapapeles: portapapeles, bandeja: bandeja,
                        airdrop: airdrop, inbox: inbox, clima: clima, screenTime: screenTime, monitor: monitor,
                        grabadora: grabadora, ajustes: ajustes, modulosDisponibles: modulosDisponibles,
                        alAbrirModulo: alAbrirModulo
                    )))
        }
        return AnyView(
            VistaDeInicio(
                ahoraSuena: ahoraSuena,
                portapapeles: portapapeles,
                bandeja: bandeja,
                airdrop: airdrop,
                inbox: inbox,
                alAbrirModulo: alAbrirModulo
            ))
    }
}

struct VistaDeInicio: View {
    let ahoraSuena: ModeloDeAhoraSuena?
    let portapapeles: ModeloDePortapapeles?
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
                portapapeles: portapapeles,
                bandeja: bandeja,
                airdrop: airdrop,
                alAbrirBandeja: { alAbrirModulo?("bandeja") }
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

struct ColumnaMusicaInicio: View {
    let ahoraSuena: ModeloDeAhoraSuena?
    let alAbrirMusica: @MainActor () -> Void
    /// Lado de la carátula; el estilo tarjetas usa una más chica para dejar sitio a la franja de estado.
    var caratula: CGFloat = 62

    var body: some View {
        let estado = ahoraSuena?.estadoActual
        return VStack(alignment: .leading, spacing: 6) {
            Button(action: alAbrirMusica) {
                HStack(spacing: 10) {
                    CaratulaDeCancion(datos: estado?.caratulaPNG, tamano: caratula, radio: caratula < 62 ? 10 : 12)
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
            .buttonStyle(.presion)
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
                .buttonStyle(.presion)
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
                .buttonStyle(.presion)
                .accessibilityLabel(estado?.reproduciendo == true ? "Pausar" : "Reproducir")

                Button {
                    ahoraSuena?.siguiente()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Paleta.texto)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.presion)
                .accessibilityLabel("Siguiente canción")
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 2)
    }
}

/// Columna central "Files": muestra únicamente las imágenes/miniaturas sin descripción, incluyendo
/// lo que hay en Bandeja, AirDrop y Portapapeles (imágenes y archivos), listo para arrastrar o abrir.
struct ColumnaArchivosInicio: View {
    let portapapeles: ModeloDePortapapeles?
    let bandeja: ModeloDeBandeja?
    let airdrop: ModeloDeAirDrop?
    let alAbrirBandeja: @MainActor () -> Void
    /// Lado de cada miniatura en la cuadrícula; el estilo tarjetas usa una más chica.
    var miniatura: CGFloat = 58
    private var espacio: CGFloat { miniatura < 58 ? 5 : 8 }
    @State private var arrastrandoSobreArchivos = false

    /// Hasta 4 archivos visibles. Se detiene en cuanto junta 4 para no revisar en disco
    /// todo el historial del portapapeles en cada redibujo.
    private var urlsVisuales: [URL] {
        Self.urlsRecientes(portapapeles: portapapeles, bandeja: bandeja, airdrop: airdrop, limite: 4)
    }

    /// Archivos que existen en disco, sin repetir: primero la Bandeja, luego lo copiado y lo recibido por AirDrop.
    static func urlsRecientes(
        portapapeles: ModeloDePortapapeles?, bandeja: ModeloDeBandeja?, airdrop: ModeloDeAirDrop?, limite: Int
    ) -> [URL] {
        var lista: [URL] = []
        var vistas = Set<String>()
        func agregar(_ url: URL) {
            guard lista.count < limite else { return }
            let p = url.standardizedFileURL.path
            guard !vistas.contains(p), FileManager.default.fileExists(atPath: p) else { return }
            vistas.insert(p)
            lista.append(url)
        }
        for b in bandeja?.elementos ?? [] where lista.count < limite {
            agregar(b.urlParaArrastrar)
        }
        for c in portapapeles?.elementos ?? [] where lista.count < limite {
            if let ruta = c.rutaArchivo {
                agregar(URL(fileURLWithPath: ruta))
            }
        }
        for a in airdrop?.recibidos ?? [] where lista.count < limite {
            agregar(a.url)
        }
        return lista
    }

    var body: some View {
        let urls = urlsVisuales
        return ZStack {
            if urls.isEmpty {
                Button(action: alAbrirBandeja) {
                    VStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Paleta.agenda)
                        Text("Files")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Paleta.texto)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.presion)
            } else if urls.count == 1, let unica = urls.first {
                // Solo la imagen/miniatura grande sin descripción
                Button {
                    NSWorkspace.shared.open(unica)
                } label: {
                    MiniaturaDeArchivo(url: unica, tamano: min(96, miniatura * 1.65))
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                }
                .buttonStyle(.presion)
                .onDrag {
                    NSItemProvider(object: unica as NSURL)
                }
            } else {
                // Cuadrícula de hasta 4 imágenes/miniaturas sin texto de descripción
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: espacio), GridItem(.flexible(), spacing: espacio)],
                    spacing: espacio
                ) {
                    ForEach(urls, id: \.path) { url in
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            MiniaturaDeArchivo(url: url, tamano: miniatura)
                                .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                        }
                        .buttonStyle(.presion)
                        .onDrag {
                            NSItemProvider(object: url as NSURL)
                        }
                    }
                }
                .padding(miniatura < 58 ? 0 : 6)
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
            Task { @MainActor in
                var urls: [URL] = []
                for proveedor in proveedores {
                    let url: URL? = await withCheckedContinuation { continuacion in
                        _ = proveedor.loadObject(ofClass: URL.self) { url, _ in
                            continuacion.resume(returning: url)
                        }
                    }
                    if let url { urls.append(url) }
                }
                bandeja?.agregarEnSegundoPlano(urls)
            }
            return true
        }
    }
}

private struct ColumnaNotasInboxInicio: View {
    let inbox: GestorDeInboxObsidian?
    @FocusState private var campoEnfocado: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Paleta.portapapeles)
                Text("Notes")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Paleta.texto)

                Spacer(minLength: 0)

                Button {
                    inbox?.abrirEnObsidian()
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Paleta.portapapeles)
                }
                .buttonStyle(.presion)
                .help("Abrir 00-inbox/inbox.md en Obsidian")
                .accessibilityLabel("Abrir inbox en Obsidian")

                Button {
                    inbox?.abrirCarpetaEnFinder()
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(Paleta.textoDeApoyo)
                }
                .buttonStyle(.presion)
                .help("Abrir carpeta 00-inbox en Finder")
                .accessibilityLabel("Abrir carpeta inbox en Finder")
            }

            if let inbox {
                @Bindable var gestor = inbox
                HStack(spacing: 5) {
                    TextField("Escribe y pulsa ↵ para enviar al inbox…", text: $gestor.borrador)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Paleta.texto)
                        .focused($campoEnfocado)
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
                    .buttonStyle(.presion)
                    .disabled(gestor.borrador.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Guardar en el inbox de \(gestor.nombreDelDestino)")
                    .accessibilityLabel("Guardar en el inbox")
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(Paleta.superficieAlta, in: RoundedRectangle(cornerRadius: 8))
                .onTapGesture {
                    campoEnfocado = true
                }

                if inbox.lineasRecientes.isEmpty {
                    Spacer(minLength: 0)
                    VStack(spacing: 4) {
                        Image(systemName: "note.text")
                            .font(.system(size: 24))
                            .foregroundStyle(Paleta.portapapeles.opacity(0.85))
                        Text("Escribe arriba para guardar en el inbox de \(inbox.nombreDelDestino)")
                            .font(.system(size: 10))
                            .foregroundStyle(Paleta.textoDeApoyo)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        campoEnfocado = true
                    }
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
                    .contentShape(Rectangle())
                    .onTapGesture {
                        campoEnfocado = true
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
