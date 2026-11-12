import Foundation
import NotchyCore

/// Falso de `PuertoDeAhoraSuena` para pruebas sin procesos ni MediaRemote.
@MainActor
public final class AhoraSuenaFalso: PuertoDeAhoraSuena {
    public private(set) var activo = false
    public private(set) var comandosEnviados: [ComandoDeReproduccion] = []
    public var resultadoDePrueba = true
    private var oyente: (@MainActor (EstadoDeAhoraSuena?) -> Void)?

    public init() {}

    public func iniciar(alCambiar: @escaping @MainActor (EstadoDeAhoraSuena?) -> Void) {
        activo = true
        oyente = alCambiar
    }

    public func detener() {
        activo = false
        oyente = nil
    }

    public func enviar(_ comando: ComandoDeReproduccion) {
        comandosEnviados.append(comando)
    }

    public func probarAdaptador() async -> Bool {
        resultadoDePrueba
    }

    public func emitir(_ estado: EstadoDeAhoraSuena?) {
        oyente?(estado)
    }
}
