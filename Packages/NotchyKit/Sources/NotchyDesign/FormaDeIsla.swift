import SwiftUI

/// Silueta de la isla: cuelga del borde superior, con hombros que se abren hacia la barra de menús
/// y esquinas redondeadas abajo. Los dos radios se animan.
///
/// El cuerpo ocupa el rectángulo menos un `hombro` por lado: quien la use suma `2 * hombro` al ancho.
public struct FormaDeIsla: Shape {
    public var radioInferior: CGFloat
    public var hombro: CGFloat

    public init(radioInferior: CGFloat, hombro: CGFloat = Medidas.hombro) {
        self.radioInferior = radioInferior
        self.hombro = hombro
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(radioInferior, hombro) }
        set {
            radioInferior = newValue.first
            hombro = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        let hombro = max(0, min(self.hombro, rect.width / 4, rect.height / 2))
        let izquierda = rect.minX + hombro
        let derecha = rect.maxX - hombro
        let radio = max(0, min(radioInferior, (derecha - izquierda) / 2, rect.height - hombro))

        var forma = Path()
        forma.move(to: CGPoint(x: rect.minX, y: rect.minY))
        forma.addQuadCurve(
            to: CGPoint(x: izquierda, y: rect.minY + hombro), control: CGPoint(x: izquierda, y: rect.minY))
        forma.addLine(to: CGPoint(x: izquierda, y: rect.maxY - radio))
        forma.addQuadCurve(
            to: CGPoint(x: izquierda + radio, y: rect.maxY), control: CGPoint(x: izquierda, y: rect.maxY))
        forma.addLine(to: CGPoint(x: derecha - radio, y: rect.maxY))
        forma.addQuadCurve(
            to: CGPoint(x: derecha, y: rect.maxY - radio), control: CGPoint(x: derecha, y: rect.maxY))
        forma.addLine(to: CGPoint(x: derecha, y: rect.minY + hombro))
        forma.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: derecha, y: rect.minY))
        forma.closeSubpath()
        return forma
    }
}
