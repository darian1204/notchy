import Foundation
import Testing

@testable import NotchyCore

@Suite struct PermisosYDiagnosticoTests {
    @Test func cadaPermisoTieneNombreExplicacionYEnlace() {
        for permiso in PermisoDelSistema.allCases {
            #expect(!permiso.nombre.isEmpty)
            #expect(!permiso.paraQueSirve.isEmpty)
            #expect(permiso.comoConcederlo.contains(permiso.nombre))
            #expect(permiso.enlaceDeAjustesDelSistema != nil)
        }
    }

    @Test func estadosDePermisoInformanConcesion() {
        #expect(EstadoDePermiso.concedido.estaConcedido)
        #expect(!EstadoDePermiso.sinPedir.estaConcedido)
        #expect(!EstadoDePermiso.denegado.estaConcedido)
        #expect(!EstadoDePermiso.restringido.estaConcedido)
    }

    @Test func estadoDeOpenCodeInformaDisponibilidad() {
        let instalado = EstadoDeOpenCode.instalado(ruta: "/opt/homebrew/bin/opencode")
        #expect(instalado.estaListo)
        #expect(instalado.detalle.contains("/opt/homebrew/bin/opencode"))

        let ausente = EstadoDeOpenCode.noEncontrado
        #expect(!ausente.estaListo)
        #expect(ausente.detalle.contains("brew install opencode"))
    }
}
