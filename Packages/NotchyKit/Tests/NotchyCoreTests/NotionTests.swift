import NotchyTestSupport
import Testing

@testable import NotchyCore

@MainActor
@Suite struct NotionTests {
    private let id = "1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d"
    private let conGuiones = "1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d"

    @Test func leeElIdDeUnEnlace() {
        #expect(Notion.idDePagina("https://www.notion.so/darian/Inbox-\(id)") == conGuiones)
        #expect(Notion.idDePagina("https://www.notion.so/Inbox-\(id)?pvs=4") == conGuiones)
        #expect(Notion.idDePagina("https://www.notion.so/\(id)#abc") == conGuiones)
    }

    @Test func enUnaVistaPreviaUsaLaPaginaDelParametroP() {
        let base = "ffffffffffffffffffffffffffffffff"
        #expect(Notion.idDePagina("https://www.notion.so/\(base)?v=1&p=\(id)&pm=s") == conGuiones)
    }

    @Test func losTrozosRespetanUTF16SinCortarEmojis() {
        let emojis = String(repeating: "👍🏽", count: 700)  // 4 unidades UTF-16 cada uno
        let trozos = Notion.parrafos(de: emojis)
        #expect(trozos.allSatisfy { $0.utf16.count <= Notion.maximoPorBloque })
        #expect(trozos.joined() == emojis)
    }

    @Test func leeElIdSueltoConOSinGuiones() {
        #expect(Notion.idDePagina(id) == conGuiones)
        #expect(Notion.idDePagina(conGuiones) == conGuiones)
        #expect(Notion.idDePagina("  \(id.uppercased())  ") == conGuiones)
    }

    @Test func rechazaLoQueNoEsUnaPagina() {
        #expect(Notion.idDePagina("") == nil)
        #expect(Notion.idDePagina("https://www.notion.so/Inbox") == nil)
        #expect(Notion.idDePagina("hola") == nil)
    }

    @Test func unParrafoPorLineaYTrozosDe2000() {
        #expect(Notion.parrafos(de: "uno\n\n  dos  \n") == ["uno", "dos"])
        let larga = String(repeating: "a", count: 4500)
        #expect(Notion.parrafos(de: larga).map(\.count) == [2000, 2000, 500])
    }

    @Test func destinoPorDefectoObsidianYPersiste() {
        let almacen = AlmacenEnMemoria()
        let ajustes = Ajustes(almacen: almacen)
        #expect(ajustes.destinoDeInbox == .obsidian)
        ajustes.destinoDeInbox = .notion
        ajustes.paginaNotion = id
        let otra = Ajustes(almacen: almacen)
        #expect(otra.destinoDeInbox == .notion)
        #expect(otra.paginaNotion == id)
    }
}
