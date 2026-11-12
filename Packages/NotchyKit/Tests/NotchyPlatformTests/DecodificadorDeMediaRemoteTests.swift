import Foundation
import NotchyCore
import NotchyPlatform
import Testing

struct DecodificadorDeMediaRemoteTests {
    @Test func procesaCargaYDiffs() {
        var decodificador = DecodificadorDeMediaRemote()
        let fecha = Date(timeIntervalSince1970: 2_000)
        let pngBase64 = Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString()

        let inicial = """
            {"type":"data","diff":false,"payload":{"title":"Intro","artist":"The xx","album":"xx","playing":true,"duration":127.5,"elapsedTime":12.0,"bundleIdentifier":"com.apple.Music","artworkData":"\(pngBase64)"}}
            """
        let estado1 = decodificador.procesar(
            linea: inicial,
            en: fecha,
            resolverNombreApp: { _ in "Música" }
        )
        #expect(estado1?.titulo == "Intro")
        #expect(estado1?.artista == "The xx")
        #expect(estado1?.appOrigen == "Música")
        #expect(estado1?.reproduciendo == true)
        #expect(estado1?.duracionSegundos == 127.5)
        #expect(estado1?.transcurridoSegundos == 12.0)
        #expect(estado1?.caratulaPNG == Data([0x89, 0x50, 0x4E, 0x47]))

        let diffPausa = """
            {"type":"data","diff":true,"payload":{"playing":false,"elapsedTime":18.5}}
            """
        let estado2 = decodificador.procesar(
            linea: diffPausa,
            en: fecha,
            resolverNombreApp: { _ in "Música" }
        )
        #expect(estado2?.titulo == "Intro")
        #expect(estado2?.artista == "The xx")
        #expect(estado2?.reproduciendo == false)
        #expect(estado2?.transcurridoSegundos == 18.5)
        #expect(estado2?.caratulaPNG == Data([0x89, 0x50, 0x4E, 0x47]))

        let vacio = """
            {"type":"data","diff":false,"payload":{}}
            """
        let estado3 = decodificador.procesar(linea: vacio, en: fecha)
        #expect(estado3 == nil)
    }

    @Test func detectaRutasDeMediaRemote() {
        let rutas = RutasDeMediaRemote.detectar()
        #expect(rutas != nil)
        #expect(rutas?.scriptPerl.hasSuffix("mediaremote-adapter.pl") == true)
        #expect(rutas?.framework.hasSuffix("MediaRemoteAdapter.framework") == true)
    }
}
