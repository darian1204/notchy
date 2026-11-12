import NotchyCore

/// Conecta las preferencias del atajo global y el estado de la isla con el registrador de teclas.
/// Registra el atajo elegido sin reiniciar (ISL-8) y solo prende Escape cuando la isla se abrió sin el cursor encima.
@MainActor
public final class ControladorDeAtajo {
    private let coordinador: CoordinadorDeIsla
    private let ajustes: Ajustes
    private let registrador: any RegistradorDeAtajos

    public private(set) var atajoActivo = false

    public init(coordinador: CoordinadorDeIsla, ajustes: Ajustes, registrador: any RegistradorDeAtajos) {
        self.coordinador = coordinador
        self.ajustes = ajustes
        self.registrador = registrador

        registrador.alPulsarAtajo = { [weak self] in
            self?.coordinador.recibir(.atajo)
        }
        registrador.alPulsarEscape = { [weak self] in
            self?.coordinador.recibir(.escape)
        }

        ajustes.observar { [weak self] in self?.aplicarAtajo() }
        coordinador.observar { [weak self] in self?.sincronizarEscape() }

        aplicarAtajo()
        sincronizarEscape()
    }

    public func detener() {
        registrador.activarEscape(false)
        _ = registrador.registrar(.ninguno)
        atajoActivo = false
    }

    private func aplicarAtajo() {
        atajoActivo = registrador.registrar(ajustes.atajo)
    }

    private func sincronizarEscape() {
        registrador.activarEscape(coordinador.abiertaSinCursor)
    }
}
