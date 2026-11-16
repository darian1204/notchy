import Foundation
import Testing

@testable import NotchyPlatform

struct AdaptadorDeNotificacionesDelSistemaTests {
    @Test func decodificaElPlistDeNotificationCenter() throws {
        let plist: [String: Any] = [
            "app": "com.apple.MobileSMS",
            "req": ["titl": "Lebebe", "subt": "", "body": "¿Ya saliste?", "date": 784_000_000.0],
        ]
        let datos = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let contenido = try #require(AdaptadorDeNotificacionesDelSistema.decodificar(datos))
        #expect(contenido.titulo == "Lebebe")
        #expect(contenido.subtitulo == nil)
        #expect(contenido.cuerpo == "¿Ya saliste?")
        #expect(contenido.fecha == Date(timeIntervalSinceReferenceDate: 784_000_000))
    }

    @Test func ignoraBlobsSinContenido() throws {
        let datos = try PropertyListSerialization.data(fromPropertyList: ["req": [:]], format: .binary, options: 0)
        #expect(AdaptadorDeNotificacionesDelSistema.decodificar(datos) == nil)
    }
}
