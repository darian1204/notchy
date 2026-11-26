import Foundation
import Observation

/// Donde se guardan las preferencias. El adaptador real usa `UserDefaults`; las pruebas, memoria.
public protocol AlmacenDeAjustes: Sendable {
    func leer(_ clave: String) -> Data?
    func guardar(_ dato: Data?, en clave: String)
}

/// Preferencias de la app. Cada cambio se guarda al momento y avisa a quien observe,
/// así se aplican sin reiniciar (ISL-8).
@MainActor
@Observable
public final class Ajustes {
    /// Versión del formato guardado. Sube cuando una preferencia cambia de forma y necesita migrarse.
    public static let esquemaActual = 1

    public static var rutaDescargasPorDefecto: String {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads").path
    }

    public static var rutaVaultPorDefecto: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Documents/Obsidian")
            .path
    }

    /// Orden elegido de los módulos. Un módulo que no aparece aquí va al final.
    public var ordenDeModulos: [String] {
        didSet { alCambiar(ordenDeModulos, oldValue, .ordenDeModulos) }
    }
    public var modulosApagados: Set<String> {
        didSet { alCambiar(modulosApagados, oldValue, .modulosApagados) }
    }
    public var pantalla: PantallaPreferida {
        didSet { alCambiar(pantalla, oldValue, .pantalla) }
    }
    public var atajo: AtajoDeIsla {
        didSet { alCambiar(atajo, oldValue, .atajo) }
    }
    public var iconoEnBarraDeMenus: Bool {
        didSet { alCambiar(iconoEnBarraDeMenus, oldValue, .iconoEnBarraDeMenus) }
    }
    /// Registrar Notchy para iniciar al abrir sesión en macOS (SIS-3).
    public var iniciarAlAbrirSesion: Bool {
        didSet { alCambiar(iniciarAlAbrirSesion, oldValue, .iniciarAlAbrirSesion) }
    }
    /// Horas que vive cada copia del portapapeles (por defecto 1). Los fijados no se borran.
    public var horasRetencionPortapapeles: Int {
        didSet { alCambiar(horasRetencionPortapapeles, oldValue, .horasRetencionPortapapeles) }
    }
    /// Límite de elementos guardados en el portapapeles (CLP-5). Por defecto 2000 elementos.
    public var limiteElementosPortapapeles: Int {
        didSet { alCambiar(limiteElementosPortapapeles, oldValue, .limiteElementosPortapapeles) }
    }
    /// Identificadores de apps excluidas del portapapeles (CLP-2).
    public var appsExcluidasPortapapeles: Set<String> {
        didSet { alCambiar(appsExcluidasPortapapeles, oldValue, .appsExcluidasPortapapeles) }
    }
    /// Carpeta donde el Espejo guarda las fotos capturadas. Por defecto `~/Downloads`.
    public var carpetaFotosEspejo: String {
        didSet { alCambiar(carpetaFotosEspejo, oldValue, .carpetaFotosEspejo) }
    }
    /// Carpeta raíz del vault de Obsidian donde vive `00-inbox/inbox.md`.
    public var rutaVaultObsidian: String {
        didSet { alCambiar(rutaVaultObsidian, oldValue, .rutaVaultObsidian) }
    }
    /// Tema visual del panel de la isla (7 opciones).
    public var temaPanel: TemaDePanel {
        didSet { alCambiar(temaPanel, oldValue, .temaPanel) }
    }
    /// Tema de acento de la barra superior (9 opciones).
    public var temaBarra: TemaDeBarra {
        didSet { alCambiar(temaBarra, oldValue, .temaBarra) }
    }
    /// Estilo de la isla abierta: clásico o tarjetas.
    public var estiloDeIsla: EstiloDeIsla {
        didSet { alCambiar(estiloDeIsla, oldValue, .estiloDeIsla) }
    }
    /// Tarjetas del Inicio en estilo tarjetas, en orden. Entre 1 y 4, sin repetir.
    public var tarjetasDeInicio: [TarjetaDeInicioElegida] {
        didSet {
            let limpias = Self.normalizarTarjetas(tarjetasDeInicio)
            if limpias != tarjetasDeInicio { tarjetasDeInicio = limpias }
            alCambiar(tarjetasDeInicio, oldValue, .tarjetasDeInicio)
        }
    }
    /// A dónde van las notas del inbox: Obsidian o Notion.
    public var destinoDeInbox: DestinoDeInbox {
        didSet { alCambiar(destinoDeInbox, oldValue, .destinoDeInbox) }
    }
    /// Enlace o ID de la página de Notion que hace de inbox. El token va en el llavero, no aquí.
    public var paginaNotion: String {
        didSet { alCambiar(paginaNotion, oldValue, .paginaNotion) }
    }
    /// Liquid glass en la isla: apagado, píldoras, píldoras y tarjetas, o completo.
    public var vidrio: EstiloDeVidrio {
        didSet { alCambiar(vidrio, oldValue, .vidrio) }
    }
    /// Qué tan tintado se ve el vidrio: 0 es transparente y 1 es tintado, como en macOS.
    /// Quien lo pinta lo pasa por `limitarTintado`.
    public var tintadoDelVidrio: Double {
        didSet { alCambiar(tintadoDelVidrio, oldValue, .tintadoDelVidrio) }
    }
    public static let tintadoPorDefecto = 0.5
    /// Los 3 accesos rápidos del Inicio en estilo tarjetas, por id de módulo.
    public var accesosRapidos: [String] {
        didSet {
            // Asignar dentro de su propio didSet no vuelve a llamarlo.
            let limpios = Self.normalizarAccesos(accesosRapidos)
            if limpios != accesosRapidos { accesosRapidos = limpios }
            alCambiar(accesosRapidos, oldValue, .accesosRapidos)
        }
    }
    /// Mostrar el HUD de volumen, brillo y batería en el notch.
    public var hudSistemaActivo: Bool {
        didSet { alCambiar(hudSistemaActivo, oldValue, .hudSistemaActivo) }
    }
    /// Días que se conserva el audio de reuniones para poder retranscribir (D-25, por defecto 30).
    public var diasRetencionAudioReuniones: Int {
        didSet { alCambiar(diasRetencionAudioReuniones, oldValue, .diasRetencionAudioReuniones) }
    }
    /// Si se guardan en disco las pistas de audio de las reuniones (D-25).
    public var guardarAudioReuniones: Bool {
        didSet { alCambiar(guardarAudioReuniones, oldValue, .guardarAudioReuniones) }
    }
    /// Si al terminar una reunión se resume con Apple Intelligence y se deja en el inbox de Obsidian.
    public var resumirReunionesEnInbox: Bool {
        didSet { alCambiar(resumirReunionesEnInbox, oldValue, .resumirReunionesEnInbox) }
    }
    /// Si al terminar una reunión se separan las voces del micrófono con diarización en el dispositivo.
    public var separarVocesEnReuniones: Bool {
        didSet { alCambiar(separarVocesEnReuniones, oldValue, .separarVocesEnReuniones) }
    }
    /// Idioma inicial para la transcripción en vivo (GRB-3).
    public var idiomaTranscripcionPorDefecto: IdiomaDeTranscripcion {
        didSet { alCambiar(idiomaTranscripcionPorDefecto, oldValue, .idiomaTranscripcionPorDefecto) }
    }
    /// Preferir el micrófono interno cuando la salida es Bluetooth para evitar el modo llamada a 16 kHz (S3).
    public var preferirMicrofonoInternoConBluetooth: Bool {
        didSet {
            alCambiar(
                preferirMicrofonoInternoConBluetooth,
                oldValue,
                .preferirMicrofonoInternoConBluetooth
            )
        }
    }
    /// Herramientas de escritura del agente MCP que el usuario autorizó con "Siempre" (AGT-4).
    public var herramientasAgenteSiemprePermitidas: Set<String> {
        didSet {
            alCambiar(
                herramientasAgenteSiemprePermitidas,
                oldValue,
                .herramientasAgenteSiemprePermitidas
            )
        }
    }

    @ObservationIgnored private let almacen: any AlmacenDeAjustes
    @ObservationIgnored private var observadores: [@MainActor () -> Void] = []

    public init(almacen: any AlmacenDeAjustes) {
        self.almacen = almacen
        Self.migrar(almacen)
        ordenDeModulos = Self.leer(.ordenDeModulos, de: almacen) ?? []
        modulosApagados = Self.leer(.modulosApagados, de: almacen) ?? []
        pantalla = Self.leer(.pantalla, de: almacen) ?? .conNotch
        atajo = Self.leer(.atajo, de: almacen) ?? .controlOpcionEspacio
        iconoEnBarraDeMenus = Self.leer(.iconoEnBarraDeMenus, de: almacen) ?? false
        iniciarAlAbrirSesion = Self.leer(.iniciarAlAbrirSesion, de: almacen) ?? true
        horasRetencionPortapapeles = Self.leer(.horasRetencionPortapapeles, de: almacen) ?? 1
        limiteElementosPortapapeles = Self.leer(.limiteElementosPortapapeles, de: almacen) ?? 2000
        appsExcluidasPortapapeles = Self.leer(.appsExcluidasPortapapeles, de: almacen) ?? []
        carpetaFotosEspejo = Self.leer(.carpetaFotosEspejo, de: almacen) ?? Self.rutaDescargasPorDefecto
        rutaVaultObsidian = Self.leer(.rutaVaultObsidian, de: almacen) ?? Self.rutaVaultPorDefecto
        temaPanel = Self.leer(.temaPanel, de: almacen) ?? .obsidiana
        temaBarra = Self.leer(.temaBarra, de: almacen) ?? .clasico
        estiloDeIsla = Self.leer(.estiloDeIsla, de: almacen) ?? .clasico
        vidrio = Self.leer(.vidrio, de: almacen) ?? .apagado
        tintadoDelVidrio = Self.limitarTintado(Self.leer(.tintadoDelVidrio, de: almacen) ?? Self.tintadoPorDefecto)
        destinoDeInbox = Self.leer(.destinoDeInbox, de: almacen) ?? .obsidian
        paginaNotion = Self.leer(.paginaNotion, de: almacen) ?? ""
        tarjetasDeInicio = Self.normalizarTarjetas(
            Self.leer(.tarjetasDeInicio, de: almacen) ?? Self.tarjetasPorDefecto)
        accesosRapidos = Self.normalizarAccesos(Self.leer(.accesosRapidos, de: almacen) ?? Self.accesosPorDefecto)
        hudSistemaActivo = Self.leer(.hudSistemaActivo, de: almacen) ?? true
        diasRetencionAudioReuniones = Self.leer(.diasRetencionAudioReuniones, de: almacen) ?? 30
        guardarAudioReuniones = Self.leer(.guardarAudioReuniones, de: almacen) ?? true
        resumirReunionesEnInbox = Self.leer(.resumirReunionesEnInbox, de: almacen) ?? true
        separarVocesEnReuniones = Self.leer(.separarVocesEnReuniones, de: almacen) ?? true
        idiomaTranscripcionPorDefecto =
            Self.leer(.idiomaTranscripcionPorDefecto, de: almacen) ?? .espanolMexico
        preferirMicrofonoInternoConBluetooth =
            Self.leer(.preferirMicrofonoInternoConBluetooth, de: almacen) ?? true
        herramientasAgenteSiemprePermitidas =
            Self.leer(.herramientasAgenteSiemprePermitidas, de: almacen) ?? []
    }

    public var urlCarpetaInboxObsidian: URL {
        URL(fileURLWithPath: rutaVaultObsidian).appending(path: "00-inbox")
    }

    public var urlNotaInboxObsidian: URL {
        urlCarpetaInboxObsidian.appending(path: "inbox.md")
    }

    /// Llama a `accion` después de cada cambio guardado. Para quien no es una vista de SwiftUI.
    public func observar(_ accion: @escaping @MainActor () -> Void) {
        observadores.append(accion)
    }

    // MARK: Módulos

    public func estaActivo(_ id: String) -> Bool {
        !modulosApagados.contains(id)
    }

    public func activar(_ id: String, _ activo: Bool) {
        if activo {
            modulosApagados.remove(id)
        } else {
            modulosApagados.insert(id)
        }
    }

    /// Ordena los módulos disponibles: primero los del orden guardado, después los nuevos tal como llegan.
    public func ordenar(_ disponibles: [String]) -> [String] {
        let conocidos = ordenDeModulos.filter(disponibles.contains)
        return conocidos + disponibles.filter { !conocidos.contains($0) }
    }

    // MARK: Guardado

    enum Clave: String, CaseIterable {
        case esquema, ordenDeModulos, modulosApagados, pantalla, atajo, iconoEnBarraDeMenus, iniciarAlAbrirSesion
        case diasRetencionPortapapeles, horasRetencionPortapapeles, limiteElementosPortapapeles,
            appsExcluidasPortapapeles
        case carpetaFotosEspejo, rutaVaultObsidian, temaPanel, temaBarra, hudSistemaActivo
        case diasRetencionAudioReuniones, guardarAudioReuniones, idiomaTranscripcionPorDefecto
        case preferirMicrofonoInternoConBluetooth, resumirReunionesEnInbox, separarVocesEnReuniones
        case estiloDeIsla, accesosRapidos, herramientasAgenteSiemprePermitidas, vidrio
        case tarjetasDeInicio, destinoDeInbox, paginaNotion, tintadoDelVidrio
    }

    /// Restaura todas las preferencias a sus valores por defecto y limpia el almacén.
    public func restablecerValoresPorDefecto() {
        for clave in Clave.allCases where clave != .esquema {
            almacen.guardar(nil, en: clave.rawValue)
        }
        ordenDeModulos = []
        modulosApagados = []
        pantalla = .conNotch
        atajo = .controlOpcionEspacio
        iconoEnBarraDeMenus = false
        iniciarAlAbrirSesion = true
        horasRetencionPortapapeles = 1
        limiteElementosPortapapeles = 2000
        appsExcluidasPortapapeles = []
        carpetaFotosEspejo = Self.rutaDescargasPorDefecto
        rutaVaultObsidian = Self.rutaVaultPorDefecto
        temaPanel = .obsidiana
        temaBarra = .clasico
        estiloDeIsla = .clasico
        vidrio = .apagado
        tintadoDelVidrio = Self.tintadoPorDefecto
        destinoDeInbox = .obsidian
        paginaNotion = ""
        tarjetasDeInicio = Self.tarjetasPorDefecto
        accesosRapidos = Self.accesosPorDefecto
        hudSistemaActivo = true
        diasRetencionAudioReuniones = 30
        guardarAudioReuniones = true
        resumirReunionesEnInbox = true
        separarVocesEnReuniones = true
        idiomaTranscripcionPorDefecto = .espanolMexico
        preferirMicrofonoInternoConBluetooth = true
        herramientasAgenteSiemprePermitidas = []
    }

    // MARK: Tarjetas del Inicio

    public static let maximoDeTarjetas = 4
    public static let tarjetasPorDefecto = [
        TarjetaDeInicioElegida(.musica, .ancha),
        TarjetaDeInicioElegida(.inbox, .media),
        TarjetaDeInicioElegida(.bandeja, .angosta),
    ]

    /// Sin repetidas y entre 1 y 4. Vacía vuelve a las de por defecto.
    static func normalizarTarjetas(_ tarjetas: [TarjetaDeInicioElegida]) -> [TarjetaDeInicioElegida] {
        var resultado: [TarjetaDeInicioElegida] = []
        for tarjeta in tarjetas where !resultado.contains(where: { $0.tarjeta == tarjeta.tarjeta }) {
            resultado.append(tarjeta)
        }
        resultado = Array(resultado.prefix(maximoDeTarjetas))
        return resultado.isEmpty ? tarjetasPorDefecto : resultado
    }

    public var puedeAgregarTarjeta: Bool { tarjetasDeInicio.count < Self.maximoDeTarjetas }
    public var puedeQuitarTarjeta: Bool { tarjetasDeInicio.count > 1 }

    /// Tarjetas que no están en el Inicio.
    public var tarjetasDisponibles: [TarjetaDeInicio] {
        TarjetaDeInicio.allCases.filter { tarjeta in !tarjetasDeInicio.contains { $0.tarjeta == tarjeta } }
    }

    public func agregarTarjeta(_ tarjeta: TarjetaDeInicio, ancho: AnchoDeTarjeta = .media) {
        guard puedeAgregarTarjeta, !tarjetasDeInicio.contains(where: { $0.tarjeta == tarjeta }) else { return }
        tarjetasDeInicio.append(TarjetaDeInicioElegida(tarjeta, ancho))
    }

    public func quitarTarjeta(_ tarjeta: TarjetaDeInicio) {
        guard puedeQuitarTarjeta else { return }
        tarjetasDeInicio.removeAll { $0.tarjeta == tarjeta }
    }

    /// Mueve una tarjeta un lugar a la izquierda (`-1`) o a la derecha (`1`).
    public func moverTarjeta(_ tarjeta: TarjetaDeInicio, _ delta: Int) {
        guard let indice = tarjetasDeInicio.firstIndex(where: { $0.tarjeta == tarjeta }) else { return }
        let destino = indice + delta
        guard tarjetasDeInicio.indices.contains(destino) else { return }
        tarjetasDeInicio.swapAt(indice, destino)
    }

    public func cambiarAncho(de tarjeta: TarjetaDeInicio, a ancho: AnchoDeTarjeta) {
        guard let indice = tarjetasDeInicio.firstIndex(where: { $0.tarjeta == tarjeta }) else { return }
        tarjetasDeInicio[indice].ancho = ancho
    }

    // MARK: Accesos rápidos

    public static let cantidadDeAccesos = 3
    public static let accesosPorDefecto = ["colorpicker", "espejo", "grabadora"]

    /// Siempre 3 ids distintos y no vacíos; lo que falte se rellena con los de por defecto.
    static func normalizarAccesos(_ ids: [String]) -> [String] {
        var resultado: [String] = []
        for id in ids + accesosPorDefecto where !id.isEmpty && !resultado.contains(id) {
            resultado.append(id)
            if resultado.count == cantidadDeAccesos { break }
        }
        return resultado
    }

    /// Pone `id` en la posición `indice`. Si ya estaba en otra, intercambia los dos.
    public func cambiarAcceso(en indice: Int, por id: String) {
        guard accesosRapidos.indices.contains(indice), !id.isEmpty else { return }
        var nuevos = accesosRapidos
        if let anterior = nuevos.firstIndex(of: id) {
            nuevos.swapAt(anterior, indice)
        } else {
            nuevos[indice] = id
        }
        accesosRapidos = nuevos
    }

    /// Entre 0 y 1; lo que no es número vuelve al valor por defecto.
    public static func limitarTintado(_ valor: Double) -> Double {
        guard valor.isFinite else { return tintadoPorDefecto }
        return min(max(valor, 0), 1)
    }

    private func alCambiar<Valor: Codable & Equatable>(_ nuevo: Valor, _ anterior: Valor, _ clave: Clave) {
        guard nuevo != anterior else { return }
        almacen.guardar(try? JSONEncoder().encode(nuevo), en: clave.rawValue)
        for accion in observadores {
            accion()
        }
    }

    private static func leer<Valor: Codable>(_ clave: Clave, de almacen: any AlmacenDeAjustes) -> Valor? {
        guard let dato = almacen.leer(clave.rawValue) else { return nil }
        return try? JSONDecoder().decode(Valor.self, from: dato)
    }

    /// Sella el almacén con la versión del formato. Un almacén de una versión más nueva no se toca.
    static func migrar(_ almacen: any AlmacenDeAjustes) {
        let guardado: Int? = leer(.esquema, de: almacen)
        guard (guardado ?? 0) < esquemaActual else { return }
        almacen.guardar(try? JSONEncoder().encode(esquemaActual), en: Clave.esquema.rawValue)
    }
}
