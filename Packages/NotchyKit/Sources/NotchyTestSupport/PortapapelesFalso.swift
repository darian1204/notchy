import Foundation
import NotchyCore

/// Portapapeles simulado en memoria para pruebas unitarias y de contrato.
@MainActor
public final class PortapapelesFalso: PuertoDePortapapeles {
    public private(set) var conteoDeCambios = 0
    public private(set) var muestraActual = MuestraDePortapapeles(conteo: 0, tipos: [], carga: .vacia)
    public private(set) var elementosEscritos: [ElementoDePortapapeles] = []
    public private(set) var vecesLimpiado = 0

    public init() {}

    public func simularCopia(
        tipos: [String] = ["public.utf8-plain-text"],
        appOrigen: String? = "Notas",
        bundleOrigen: String? = "com.apple.Notes",
        carga: CargaDePortapapeles
    ) {
        conteoDeCambios += 1
        let esSensible = tipos.contains { Self.tiposSensibles.contains($0) }
        muestraActual = MuestraDePortapapeles(
            conteo: conteoDeCambios,
            tipos: tipos,
            appOrigen: appOrigen,
            bundleOrigen: bundleOrigen,
            carga: esSensible ? .sensible : carga
        )
    }

    public func leerActual() -> MuestraDePortapapeles {
        muestraActual
    }

    @discardableResult
    public func escribir(_ elemento: ElementoDePortapapeles) -> Int {
        conteoDeCambios += 1
        elementosEscritos.append(elemento)
        muestraActual = MuestraDePortapapeles(
            conteo: conteoDeCambios,
            tipos: ["public.utf8-plain-text"],
            appOrigen: "Notchy",
            bundleOrigen: NotchyInfo.identificador,
            carga: .texto(elemento.texto)
        )
        return conteoDeCambios
    }

    public func limpiar() {
        conteoDeCambios += 1
        vecesLimpiado += 1
        muestraActual = MuestraDePortapapeles(conteo: conteoDeCambios, tipos: [], carga: .vacia)
    }
}
