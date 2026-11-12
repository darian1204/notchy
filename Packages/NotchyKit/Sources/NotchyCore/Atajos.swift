/// Puerto para registrar el atajo global de la isla y la tecla Escape cuando la isla se abre sin cursor.
@MainActor
public protocol RegistradorDeAtajos: AnyObject {
    /// Llamado cuando el usuario pulsa el atajo global.
    var alPulsarAtajo: (@MainActor () -> Void)? { get set }
    /// Llamado cuando el usuario pulsa Escape mientras `escActivo` está encendido.
    var alPulsarEscape: (@MainActor () -> Void)? { get set }

    /// Registra la combinación elegida (o la quita si es `.ninguno`). Devuelve `true` si quedó activa.
    @discardableResult
    func registrar(_ atajo: AtajoDeIsla) -> Bool

    /// Activa o desactiva la captura de Escape. Solo se prende cuando la isla se abrió sin el cursor encima.
    func activarEscape(_ activo: Bool)
}
