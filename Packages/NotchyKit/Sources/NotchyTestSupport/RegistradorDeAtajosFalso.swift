import NotchyCore

/// Registrador de atajos en memoria para pruebas.
@MainActor
public final class RegistradorDeAtajosFalso: RegistradorDeAtajos {
    public var alPulsarAtajo: (@MainActor () -> Void)?
    public var alPulsarEscape: (@MainActor () -> Void)?

    public private(set) var atajoRegistrado: AtajoDeIsla = .ninguno
    public private(set) var escapeActivo = false
    public var resultadoAlRegistrar = true

    public init() {}

    @discardableResult
    public func registrar(_ atajo: AtajoDeIsla) -> Bool {
        atajoRegistrado = atajo
        return resultadoAlRegistrar
    }

    public func activarEscape(_ activo: Bool) {
        escapeActivo = activo
    }

    public func simularAtajo() {
        alPulsarAtajo?()
    }

    public func simularEscape() {
        guard escapeActivo else { return }
        alPulsarEscape?()
    }
}
