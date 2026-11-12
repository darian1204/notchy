import AppKit
import NotchyCore
import Testing

@testable import NotchyPlatform

@MainActor
@Suite struct AdaptadorDePortapapelesTests {
    private func crearPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("dev.darian.notchy.pruebas.\(UUID().uuidString)"))
    }

    @Test func leeYEscribeTexto() {
        let pb = crearPasteboard()
        defer { pb.releaseGlobally() }
        let adaptador = AdaptadorDePortapapeles(pasteboard: pb)

        let elemento = ElementoDePortapapeles(
            tipo: .texto, texto: "Hola Notchy", huella: "h1", bytes: 11)
        adaptador.escribir(elemento)

        let muestra = adaptador.leerActual()
        #expect(muestra.carga == .texto("Hola Notchy"))
    }

    @Test func descartaContenidoMarcadoComoSensible() {
        let pb = crearPasteboard()
        defer { pb.releaseGlobally() }
        let adaptador = AdaptadorDePortapapeles(pasteboard: pb)

        pb.clearContents()
        pb.setString("secreto", forType: .string)
        pb.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))

        let muestra = adaptador.leerActual()
        #expect(muestra.carga == .sensible)
    }
}
