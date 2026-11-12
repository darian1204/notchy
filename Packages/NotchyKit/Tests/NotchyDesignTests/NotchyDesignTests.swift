import SwiftUI
import Testing

@testable import NotchyDesign

@Suite struct FormaDeIslaTests {
    private let marco = CGRect(x: 0, y: 0, width: 640, height: 208)

    @Test func noSeSaleDeSuMarco() {
        let limites = FormaDeIsla(radioInferior: 24).path(in: marco).boundingRect
        #expect(marco.insetBy(dx: -0.01, dy: -0.01).contains(limites))
        #expect(abs(limites.width - marco.width) < 0.01)
        #expect(abs(limites.height - marco.height) < 0.01)
    }

    @Test func elCuerpoDejaLibresLosHombros() {
        let forma = FormaDeIsla(radioInferior: 24, hombro: 10).path(in: marco)
        #expect(forma.contains(CGPoint(x: 320, y: 100)))
        // A media altura, la franja del hombro queda fuera del cuerpo.
        #expect(!forma.contains(CGPoint(x: 4, y: 100)))
        #expect(!forma.contains(CGPoint(x: 636, y: 100)))
        // Las esquinas de abajo están redondeadas.
        #expect(!forma.contains(CGPoint(x: 11, y: 207)))
    }

    @Test func aguantaMarcosDiminutos() {
        let forma = FormaDeIsla(radioInferior: 24, hombro: 10).path(in: CGRect(x: 0, y: 0, width: 8, height: 4))
        #expect(!forma.boundingRect.isNull)
    }

    @Test func losRadiosSeAniman() {
        var forma = FormaDeIsla(radioInferior: 12, hombro: 10)
        forma.animatableData = AnimatablePair(24, 4)
        #expect(forma.radioInferior == 24)
        #expect(forma.hombro == 4)
    }
}

@Suite struct MedidasTests {
    @Test func todoEstadoCabeEnElPanelFijo() {
        for estado in [
            Medidas.notch, Medidas.pildora, Medidas.compacto, Medidas.aviso,
            Medidas.inicio, Medidas.portapapeles, Medidas.bandeja,
        ] {
            #expect(estado.width + 2 * Medidas.hombro <= Medidas.panel.width)
            #expect(estado.height <= Medidas.panel.height)
        }
    }

    @Test func leeUnColorHexadecimal() {
        let color = ColorHex.componentes(0x5AA9FF)
        #expect(abs(color.rojo - 90.0 / 255) < 0.0001)
        #expect(abs(color.verde - 169.0 / 255) < 0.0001)
        #expect(color.azul == 1)
    }
}
