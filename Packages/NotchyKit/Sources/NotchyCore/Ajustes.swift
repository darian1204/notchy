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
            .appending(path: "Documents/Personal Darian")
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
    /// Días de retención del portapapeles (CLP-5). Por defecto 30 días.
    public var diasRetencionPortapapeles: Int {
        didSet { alCambiar(diasRetencionPortapapeles, oldValue, .diasRetencionPortapapeles) }
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
        diasRetencionPortapapeles = Self.leer(.diasRetencionPortapapeles, de: almacen) ?? 30
        limiteElementosPortapapeles = Self.leer(.limiteElementosPortapapeles, de: almacen) ?? 2000
        appsExcluidasPortapapeles = Self.leer(.appsExcluidasPortapapeles, de: almacen) ?? []
        carpetaFotosEspejo = Self.leer(.carpetaFotosEspejo, de: almacen) ?? Self.rutaDescargasPorDefecto
        rutaVaultObsidian = Self.leer(.rutaVaultObsidian, de: almacen) ?? Self.rutaVaultPorDefecto
        temaPanel = Self.leer(.temaPanel, de: almacen) ?? .obsidiana
        temaBarra = Self.leer(.temaBarra, de: almacen) ?? .clasico
        hudSistemaActivo = Self.leer(.hudSistemaActivo, de: almacen) ?? true
        diasRetencionAudioReuniones = Self.leer(.diasRetencionAudioReuniones, de: almacen) ?? 30
        guardarAudioReuniones = Self.leer(.guardarAudioReuniones, de: almacen) ?? true
        idiomaTranscripcionPorDefecto =
            Self.leer(.idiomaTranscripcionPorDefecto, de: almacen) ?? .espanolMexico
        preferirMicrofonoInternoConBluetooth =
            Self.leer(.preferirMicrofonoInternoConBluetooth, de: almacen) ?? true
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

    enum Clave: String {
        case esquema, ordenDeModulos, modulosApagados, pantalla, atajo, iconoEnBarraDeMenus
        case diasRetencionPortapapeles, limiteElementosPortapapeles, appsExcluidasPortapapeles
        case carpetaFotosEspejo, rutaVaultObsidian, temaPanel, temaBarra, hudSistemaActivo
        case diasRetencionAudioReuniones, guardarAudioReuniones, idiomaTranscripcionPorDefecto
        case preferirMicrofonoInternoConBluetooth
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
