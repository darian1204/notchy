import Foundation
import MCP
import Network
import NotchyCore
import NotchyStorage
import OSLog

/// Supervisor de OpenCode, servidor MCP y permisos del agente.
public enum NotchyAgentCapa {
    public static let nombre = "NotchyAgent"
}

/// Servidor MCP local de Notchy que escucha exclusivamente en `127.0.0.1` y exige `Authorization: Bearer <token>` (AGT-3, AGT-4, RNF-5).
public actor ServidorMCPDeNotchy {
    public nonisolated let token: String
    public private(set) var puerto: UInt16 = 0

    private let herramientas: any PuertoDeHerramientasDelAgente
    private let corredorDePermisos: CorredorDePermisos
    private let log = Registro.de(.agente)
    private let colaRed = DispatchQueue(label: "com.darian.notchy.mcp.red")
    private var listener: NWListener?
    private var servidorMCP: Server?
    private var transporteHTTP: StatelessHTTPServerTransport?

    public init(
        herramientas: any PuertoDeHerramientasDelAgente,
        corredorDePermisos: CorredorDePermisos,
        token: String = ServidorMCPDeNotchy.generarTokenAleatorio()
    ) {
        self.herramientas = herramientas
        self.corredorDePermisos = corredorDePermisos
        self.token = token
    }

    /// Genera un token aleatorio de 32 bytes codificado en hexadecimal (64 caracteres).
    public static func generarTokenAleatorio() -> String {
        var generador = SystemRandomNumberGenerator()
        return (0..<32)
            .map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &generador)) }
            .joined()
    }

    /// Compara dos cadenas en tiempo constante respecto a su contenido.
    public static func comparacionTiempoConstante(_ a: String, _ b: String) -> Bool {
        let bytesA = Array(a.utf8)
        let bytesB = Array(b.utf8)
        var diferencia: UInt8 = bytesA.count == bytesB.count ? 0 : 1
        let longitud = max(bytesA.count, bytesB.count)
        for indice in 0..<longitud {
            let byteA = indice < bytesA.count ? bytesA[indice] : 0
            let byteB = indice < bytesB.count ? bytesB[indice] : 0
            diferencia |= (byteA ^ byteB)
        }
        return diferencia == 0 && !bytesA.isEmpty
    }

    /// Verifica la cabecera `Authorization: Bearer <token>` en tiempo constante.
    public static func autorizacionValida(cabecera: String?, tokenEsperado: String) -> Bool {
        guard let cabecera else { return false }
        let prefijo = "bearer "
        guard cabecera.count > prefijo.count,
            cabecera.prefix(prefijo.count).lowercased() == prefijo
        else {
            return false
        }
        let recibido = String(cabecera.dropFirst(prefijo.count)).trimmingCharacters(in: .whitespaces)
        return comparacionTiempoConstante(recibido, tokenEsperado)
    }

    /// Arranca el transporte MCP y el listener TCP en `127.0.0.1` en un puerto libre.
    @discardableResult
    public func arrancar() async throws -> UInt16 {
        if let actual = listener, puerto > 0, actual.state == .ready {
            return puerto
        }

        try await asegurarTransporteHTTPIniciado()

        let parametros = NWParameters.tcp
        parametros.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let nuevoListener = try NWListener(using: parametros)

        nuevoListener.newConnectionHandler = { [weak self] conexion in
            guard let self else {
                conexion.cancel()
                return
            }
            Task {
                await self.atenderConexion(conexion)
            }
        }

        let puertoAsignado: UInt16 = try await withCheckedThrowingContinuation { continuacion in
            let estadoResuelto = CajaContinuacionPuerto(continuacion)
            nuevoListener.stateUpdateHandler = { estado in
                switch estado {
                case .ready:
                    let p = nuevoListener.port?.rawValue ?? 0
                    estadoResuelto.resolver(.success(p))
                case .failed(let error):
                    estadoResuelto.resolver(.failure(error))
                case .cancelled:
                    estadoResuelto.resolver(
                        .failure(NotchyError.datos("Listener MCP cancelado durante el arranque")))
                default:
                    break
                }
            }
            nuevoListener.start(queue: colaRed)
        }

        self.listener = nuevoListener
        self.puerto = puertoAsignado
        log.info("Servidor MCP escuchando en 127.0.0.1:\(puertoAsignado, privacy: .public)")
        return puertoAsignado
    }

    /// Detiene el listener local y el servidor MCP.
    public func detener() async {
        listener?.cancel()
        listener = nil
        puerto = 0
        if let servidorMCP {
            await servidorMCP.stop()
        }
        servidorMCP = nil
        transporteHTTP = nil
    }

    /// Conecta una instancia del servidor MCP a un transporte arbitrario (p. ej. `InMemoryTransport` en pruebas).
    public func conectar(transporte: any Transport) async throws -> Server {
        let servidor = await construirServidorMCP()
        try await servidor.start(transport: transporte)
        return servidor
    }

    /// Procesa una petición HTTP validando primero `Authorization: Bearer <token>` (401 si falta o no coincide).
    public func manejarPeticionHTTP(_ peticion: HTTPRequest) async -> HTTPResponse {
        guard Self.autorizacionValida(cabecera: peticion.header("Authorization"), tokenEsperado: token)
        else {
            return .error(
                statusCode: 401,
                .invalidRequest("No autorizado: falta o no coincide el token Bearer")
            )
        }
        do {
            let transporte = try await asegurarTransporteHTTPIniciado()
            return await transporte.handleRequest(peticion)
        } catch {
            return .error(
                statusCode: 500,
                .internalError("No se pudo iniciar el transporte MCP")
            )
        }
    }

    // MARK: - Construcción del servidor MCP y herramientas

    @discardableResult
    private func asegurarTransporteHTTPIniciado() async throws -> StatelessHTTPServerTransport {
        if let transporteHTTP {
            return transporteHTTP
        }
        let pipeline = StandardValidationPipeline(validators: [
            OriginValidator.localhost(),
            ContentTypeValidator(),
            ProtocolVersionValidator(),
        ])
        let nuevoTransporte = StatelessHTTPServerTransport(validationPipeline: pipeline)
        let servidor = await construirServidorMCP()
        try await servidor.start(transport: nuevoTransporte)
        self.servidorMCP = servidor
        self.transporteHTTP = nuevoTransporte
        return nuevoTransporte
    }

    private func construirServidorMCP() async -> Server {
        let servidor = Server(
            name: "notchy",
            version: "1.0.0",
            capabilities: .init(tools: .init(listChanged: false))
        )

        await servidor.withMethodHandler(ListTools.self) { (_: ListTools.Parameters) in
            ListTools.Result(tools: Self.definicionesDeHerramientas)
        }

        await servidor.withMethodHandler(CallTool.self) { [weak self] (parametros: CallTool.Parameters) in
            guard let self else {
                return CallTool.Result(
                    content: [.text(text: "Servidor MCP no disponible", annotations: nil, _meta: nil)],
                    isError: true
                )
            }
            return await self.ejecutarHerramienta(
                nombre: parametros.name,
                argumentos: parametros.arguments ?? [:]
            )
        }

        return servidor
    }

    public static let definicionesDeHerramientas: [Tool] = [
        Tool(
            name: "agenda_hoy",
            description:
                "Devuelve los eventos de hoy del Calendario y los pendientes de Recordatorios (hora, título, ubicación).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
            ]),
            annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
        ),
        Tool(
            name: "portapapeles_recientes",
            description: "Devuelve los últimos N textos copiados al portapapeles (N <= 20).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "limite": .object([
                        "type": .string("integer"),
                        "description": .string("Cantidad máxima de textos recientes (1 a 20)."),
                    ])
                ]),
            ]),
            annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
        ),
        Tool(
            name: "bandeja_archivos",
            description: "Lista los nombres de archivo presentes en la bandeja (Shelf), sin rutas completas.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
            ]),
            annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
        ),
        Tool(
            name: "reuniones_recientes",
            description: "Lista las reuniones recientes con título, fecha, duración y nota Markdown si existe.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "limite": .object([
                        "type": .string("integer"),
                        "description": .string("Cantidad máxima de reuniones a consultar (1 a 20)."),
                    ])
                ]),
            ]),
            annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
        ),
        Tool(
            name: "ahora_suena",
            description: "Devuelve qué canción o contenido multimedia suena actualmente en el Mac.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
            ]),
            annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
        ),
        Tool(
            name: "inbox_agregar",
            description: "Agrega una línea a 00-inbox/inbox.md del vault de Obsidian (requiere permiso del usuario).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "texto": .object([
                        "type": .string("string"),
                        "description": .string("Línea de texto a guardar en el inbox de Obsidian."),
                    ])
                ]),
                "required": .array([.string("texto")]),
            ]),
            annotations: .init(readOnlyHint: false, destructiveHint: false, openWorldHint: false)
        ),
        Tool(
            name: "portapapeles_copiar",
            description: "Copia el texto indicado al portapapeles del sistema (requiere permiso del usuario).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "texto": .object([
                        "type": .string("string"),
                        "description": .string("Texto a copiar al portapapeles."),
                    ])
                ]),
                "required": .array([.string("texto")]),
            ]),
            annotations: .init(readOnlyHint: false, destructiveHint: false, openWorldHint: false)
        ),
    ]

    private func ejecutarHerramienta(
        nombre: String,
        argumentos: [String: Value]
    ) async -> CallTool.Result {
        let nombreBase =
            nombre.hasPrefix("notchy_")
            ? String(nombre.dropFirst("notchy_".count))
            : nombre

        let herramientas = self.herramientas
        let corredor = self.corredorDePermisos

        switch nombreBase {
        case "agenda_hoy":
            let items = await herramientas.agendaHoy()
            return resultadoJSON(items)

        case "portapapeles_recientes":
            let pedido = argumentos["limite"]?.intValue ?? 10
            let limite = min(max(pedido, 1), 20)
            let textos = await MainActor.run { herramientas.portapapelesRecientes(limite: limite) }
            return resultadoJSON(textos)

        case "bandeja_archivos":
            let nombres = await MainActor.run { herramientas.bandejaArchivos() }
            return resultadoJSON(nombres)

        case "reuniones_recientes":
            let pedido = argumentos["limite"]?.intValue ?? 5
            let limite = min(max(pedido, 1), 20)
            let reuniones = await MainActor.run { herramientas.reunionesRecientes(limite: limite) }
            return resultadoJSON(reuniones)

        case "ahora_suena":
            let estado = await MainActor.run { herramientas.ahoraSuena() }
            if let estado {
                return resultadoJSON(estado)
            }
            return CallTool.Result(
                content: [.text(text: "No hay reproducción activa", annotations: nil, _meta: nil)],
                isError: false
            )

        case "inbox_agregar":
            guard let texto = argumentos["texto"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                !texto.isEmpty
            else {
                return CallTool.Result(
                    content: [.text(text: "Falta el argumento 'texto'", annotations: nil, _meta: nil)],
                    isError: true
                )
            }
            do {
                let mensaje = try await corredor.ejecutarConPermiso(
                    herramienta: "inbox_agregar",
                    argumentos: ["texto": texto]
                ) {
                    try herramientas.inboxAgregar(texto: texto)
                }
                return CallTool.Result(
                    content: [.text(text: mensaje, annotations: nil, _meta: nil)],
                    isError: false
                )
            } catch let error as ErrorDePermisoAgente {
                return CallTool.Result(
                    content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)],
                    isError: true
                )
            } catch {
                return CallTool.Result(
                    content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)],
                    isError: true
                )
            }

        case "portapapeles_copiar":
            guard let texto = argumentos["texto"]?.stringValue, !texto.isEmpty else {
                return CallTool.Result(
                    content: [.text(text: "Falta el argumento 'texto'", annotations: nil, _meta: nil)],
                    isError: true
                )
            }
            do {
                let mensaje = try await corredor.ejecutarConPermiso(
                    herramienta: "portapapeles_copiar",
                    argumentos: ["texto": texto]
                ) {
                    try herramientas.portapapelesCopiar(texto: texto)
                }
                return CallTool.Result(
                    content: [.text(text: mensaje, annotations: nil, _meta: nil)],
                    isError: false
                )
            } catch let error as ErrorDePermisoAgente {
                return CallTool.Result(
                    content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)],
                    isError: true
                )
            } catch {
                return CallTool.Result(
                    content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)],
                    isError: true
                )
            }

        default:
            return CallTool.Result(
                content: [.text(text: "Herramienta desconocida: \(nombre)", annotations: nil, _meta: nil)],
                isError: true
            )
        }
    }

    private func resultadoJSON<T: Encodable>(_ valor: T) -> CallTool.Result {
        let codificador = JSONEncoder()
        codificador.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let texto =
            (try? codificador.encode(valor)).flatMap { String(data: $0, encoding: .utf8) }
            ?? "[]"
        return CallTool.Result(
            content: [.text(text: texto, annotations: nil, _meta: nil)],
            isError: false
        )
    }

    // MARK: - HTTP mínimo sobre Network.framework (127.0.0.1)

    private func atenderConexion(_ conexion: NWConnection) async {
        conexion.start(queue: colaRed)
        guard let datosPeticion = await leerPeticionHTTPCompleta(de: conexion),
            let peticion = Self.parsearPeticionHTTP(datosPeticion)
        else {
            let respuesta400 = Self.serializarRespuestaHTTP(
                .error(statusCode: 400, .parseError("Petición HTTP inválida"))
            )
            await enviarYCerrar(datos: respuesta400, en: conexion)
            return
        }

        let respuesta = await manejarPeticionHTTP(peticion)
        let bytesRespuesta = Self.serializarRespuestaHTTP(respuesta)
        await enviarYCerrar(datos: bytesRespuesta, en: conexion)
    }

    private func leerPeticionHTTPCompleta(de conexion: NWConnection) async -> Data? {
        var acumulado = Data()
        let separador = Data("\r\n\r\n".utf8)

        while acumulado.count < 1_048_576 {
            guard let trozo = await recibirTrozo(de: conexion), !trozo.isEmpty else {
                return acumulado.isEmpty ? nil : acumulado
            }
            acumulado.append(trozo)

            if let rangoCabeceras = acumulado.range(of: separador) {
                let finCabeceras = rangoCabeceras.upperBound
                let cabecerasTexto = String(data: acumulado[..<rangoCabeceras.lowerBound], encoding: .utf8) ?? ""
                let longitudEsperada = Self.extraerContentLength(de: cabecerasTexto)
                let bytesCuerpoActual = acumulado.count - finCabeceras
                if bytesCuerpoActual >= longitudEsperada {
                    return acumulado
                }
            }
        }
        return acumulado
    }

    private func recibirTrozo(de conexion: NWConnection) async -> Data? {
        await withCheckedContinuation { continuacion in
            conexion.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { datos, _, terminado, error in
                if let datos, !datos.isEmpty {
                    continuacion.resume(returning: datos)
                } else if terminado || error != nil {
                    continuacion.resume(returning: nil)
                } else {
                    continuacion.resume(returning: Data())
                }
            }
        }
    }

    private func enviarYCerrar(datos: Data, en conexion: NWConnection) async {
        await withCheckedContinuation { (continuacion: CheckedContinuation<Void, Never>) in
            conexion.send(
                content: datos,
                completion: .contentProcessed { _ in
                    conexion.cancel()
                    continuacion.resume()
                }
            )
        }
    }

    private static func extraerContentLength(de textoCabeceras: String) -> Int {
        for linea in textoCabeceras.components(separatedBy: "\r\n").dropFirst() {
            let partes = linea.split(separator: ":", maxSplits: 1)
            guard partes.count == 2 else { continue }
            if partes[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length",
                let valor = Int(partes[1].trimmingCharacters(in: .whitespaces))
            {
                return max(0, valor)
            }
        }
        return 0
    }

    static func parsearPeticionHTTP(_ datos: Data) -> HTTPRequest? {
        let separador = Data("\r\n\r\n".utf8)
        guard let rango = datos.range(of: separador),
            let bloqueCabeceras = String(data: datos[..<rango.lowerBound], encoding: .utf8)
        else {
            return nil
        }

        let lineas = bloqueCabeceras.components(separatedBy: "\r\n")
        guard let primera = lineas.first else { return nil }
        let componentes = primera.split(separator: " ")
        guard componentes.count >= 2 else { return nil }
        let metodo = String(componentes[0])
        let ruta = String(componentes[1])

        var cabeceras: [String: String] = [:]
        for linea in lineas.dropFirst() {
            let partes = linea.split(separator: ":", maxSplits: 1)
            guard partes.count == 2 else { continue }
            let nombre = partes[0].trimmingCharacters(in: .whitespaces)
            let valor = partes[1].trimmingCharacters(in: .whitespaces)
            cabeceras[nombre] = valor
        }

        let inicioCuerpo = rango.upperBound
        let longitudCuerpo = extraerContentLength(de: bloqueCabeceras)
        let cuerpo: Data?
        if inicioCuerpo < datos.count {
            let disponible = datos.subdata(in: inicioCuerpo..<datos.count)
            cuerpo = longitudCuerpo > 0 ? Data(disponible.prefix(longitudCuerpo)) : disponible
        } else {
            cuerpo = nil
        }

        return HTTPRequest(method: metodo, headers: cabeceras, body: cuerpo, path: ruta)
    }

    static func serializarRespuestaHTTP(_ respuesta: HTTPResponse) -> Data {
        let cuerpo = respuesta.bodyData ?? Data()
        let codigo = respuesta.statusCode
        var lineas: [String] = [
            "HTTP/1.1 \(codigo) \(fraseEstadoHTTP(codigo))",
            "Content-Length: \(cuerpo.count)",
            "Connection: close",
        ]
        var incluyeContentType = false
        for (clave, valor) in respuesta.headers {
            if clave.lowercased() == "content-type" {
                incluyeContentType = true
            }
            lineas.append("\(clave): \(valor)")
        }
        if !incluyeContentType, !cuerpo.isEmpty {
            lineas.append("Content-Type: application/json")
        }
        var salida = Data((lineas.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        salida.append(cuerpo)
        return salida
    }

    private static func fraseEstadoHTTP(_ codigo: Int) -> String {
        switch codigo {
        case 200: "OK"
        case 202: "Accepted"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 406: "Not Acceptable"
        case 415: "Unsupported Media Type"
        default: "Error"
        }
    }
}

private final class CajaContinuacionPuerto: @unchecked Sendable {
    private let candado = NSLock()
    private var continuacion: CheckedContinuation<UInt16, any Error>?

    init(_ continuacion: CheckedContinuation<UInt16, any Error>) {
        self.continuacion = continuacion
    }

    func resolver(_ resultado: Result<UInt16, any Error>) {
        candado.lock()
        let actual = continuacion
        continuacion = nil
        candado.unlock()
        actual?.resume(with: resultado)
    }
}

/// Coordina el arranque del servidor MCP y la escritura de `opencode.json` (0600) al iniciar el módulo Agente.
@MainActor
public final class CoordinadorServidorMCPAgente: PuertoServidorMCPAgente {
    public let servidor: ServidorMCPDeNotchy
    private let rutas: RutasDeDatos?
    private let alConfigurarOpenCode: @MainActor (URL) -> Void
    private let log = Registro.de(.agente)

    public init(
        servidor: ServidorMCPDeNotchy,
        rutas: RutasDeDatos?,
        alConfigurarOpenCode: @escaping @MainActor (URL) -> Void
    ) {
        self.servidor = servidor
        self.rutas = rutas
        self.alConfigurarOpenCode = alConfigurarOpenCode
    }

    public func arrancar() async throws {
        let puerto = try await servidor.arrancar()
        if let rutas {
            let urlConfig = try GeneradorConfigOpenCode.escribirEnDisco(
                rutas: rutas,
                puerto: puerto,
                token: servidor.token
            )
            alConfigurarOpenCode(urlConfig)
            log.info("Configuración de OpenCode escrita en Application Support (puerto \(puerto, privacy: .public))")
        }
    }

    public func detener() async {
        await servidor.detener()
    }
}
