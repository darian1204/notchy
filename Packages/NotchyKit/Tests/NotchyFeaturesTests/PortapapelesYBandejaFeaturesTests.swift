import AppKit
import Foundation
import NotchyCore
import NotchyStorage
import NotchyTestSupport
import Testing

@testable import NotchyFeatures

@MainActor
@Suite struct PortapapelesYBandejaFeaturesTests {
    @Test func ignoraCopiasSensiblesYAppsExcluidas() throws {
        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        ajustes.appsExcluidasPortapapeles = ["com.1password.mac"]
        let puerto = PortapapelesFalso()
        let base = try BaseDeDatos.enMemoria()
        let modelo = ModeloDePortapapeles(
            puerto: puerto,
            repositorio: RepositorioDePortapapeles(base),
            carpetaImagenes: nil,
            ajustes: ajustes
        )

        // Copia marcada como concealed: no deja rastro (CLP-2).
        puerto.simularCopia(
            tipos: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"],
            carga: .texto("mi-clave-secreta")
        )
        modelo.revisarSiCambio()
        #expect(modelo.elementos.isEmpty)

        // Copia de una app excluida: no se guarda (CLP-2).
        puerto.simularCopia(
            appOrigen: "1Password",
            bundleOrigen: "com.1password.mac",
            carga: .texto("otra-clave")
        )
        modelo.revisarSiCambio()
        #expect(modelo.elementos.isEmpty)

        // Copia normal de Contraseñas de Apple (sin marca concealed): se guarda y se puede borrar (S9, CLP-7).
        puerto.simularCopia(
            appOrigen: "Contraseñas",
            bundleOrigen: "com.apple.Passwords",
            carga: .texto("clave-guardada")
        )
        modelo.revisarSiCambio()
        #expect(modelo.elementos.count == 1)

        // Borrar ese elemento lo quita del historial y limpia también el portapapeles activo (CLP-7).
        let guardado = try #require(modelo.elementos.first)
        modelo.borrar(guardado)
        #expect(modelo.elementos.isEmpty)
        #expect(puerto.vecesLimpiado == 1)
    }

    @Test func clasificaEnlacesGuardaImagenesYCopiaAlSistemaSinDuplicar() throws {
        let carpeta = FileManager.default.temporaryDirectory.appending(path: "notchy-clip-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: carpeta) }

        let ajustes = Ajustes(almacen: AlmacenEnMemoria())
        let puerto = PortapapelesFalso()
        let base = try BaseDeDatos.enMemoria()
        let modelo = ModeloDePortapapeles(
            puerto: puerto,
            repositorio: RepositorioDePortapapeles(base),
            carpetaImagenes: carpeta,
            ajustes: ajustes
        )

        puerto.simularCopia(appOrigen: "Safari", carga: .texto("https://supabase.com/docs"))
        modelo.revisarSiCambio()
        #expect(modelo.elementos.first?.tipo == .enlace)

        puerto.simularCopia(appOrigen: "Capturas", carga: .imagenPNG(Data([0x89, 0x50, 0x4E, 0x47])))
        modelo.revisarSiCambio()
        #expect(modelo.elementos.count == 2)
        let imagen = try #require(modelo.elementos.first)
        #expect(imagen.tipo == .imagen)
        let rutaImagen = try #require(imagen.rutaArchivo)
        #expect(FileManager.default.fileExists(atPath: rutaImagen))

        // Copiar desde Notchy escribe al sistema y una revisión posterior no duplica.
        let enlace = try #require(modelo.elementos.last)
        modelo.copiarAlSistema(enlace)
        modelo.revisarSiCambio()
        #expect(modelo.elementos.count == 2)
        #expect(puerto.elementosEscritos.last?.id == enlace.id)

        // Borrar todo elimina también los archivos de imagen en disco (CLP-5).
        modelo.borrarTodo()
        #expect(modelo.elementos.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: rutaImagen))
    }

    @Test func bandejaCopiaArchivosYNuncaBorraElOriginal() throws {
        let raiz = FileManager.default.temporaryDirectory.appending(path: "notchy-tray-\(UUID().uuidString)")
        let origenDir = raiz.appending(path: "origen")
        let bandejaDir = raiz.appending(path: "tray")
        try FileManager.default.createDirectory(at: origenDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: raiz) }

        let archivoOriginal = origenDir.appending(path: "informe.txt")
        try Data("contenido importante".utf8).write(to: archivoOriginal)

        let base = try BaseDeDatos.enMemoria()
        let modelo = ModeloDeBandeja(
            repositorio: RepositorioDeBandeja(base),
            carpetaBandeja: bandejaDir
        )

        #expect(modelo.agregarArchivos([archivoOriginal]) == 1)
        let item = try #require(modelo.elementos.first)
        #expect(item.nombre == "informe.txt")
        #expect(FileManager.default.fileExists(atPath: item.rutaCopia))
        #expect(item.archivoDisponible)

        // Quitar de la bandeja borra la copia interna, pero el archivo original sigue intacto (BND-3).
        modelo.quitar(item.id)
        #expect(modelo.elementos.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: item.rutaCopia))
        #expect(FileManager.default.fileExists(atPath: archivoOriginal.path))
    }

    @Test func shelfSeVaciaALosDiezMinutos() throws {
        let raiz = FileManager.default.temporaryDirectory.appending(path: "notchy-tray-\(UUID().uuidString)")
        let origen = raiz.appending(path: "nota.txt")
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: raiz) }
        try Data("hola".utf8).write(to: origen)

        let modelo = ModeloDeBandeja(
            repositorio: RepositorioDeBandeja(try BaseDeDatos.enMemoria()),
            carpetaBandeja: raiz.appending(path: "tray")
        )
        #expect(modelo.agregarArchivos([origen]) == 1)
        let item = try #require(modelo.elementos.first)

        #expect(modelo.limpiarVencidos(ahora: item.creado.addingTimeInterval(9 * 60)) == 0)
        #expect(modelo.limpiarVencidos(ahora: item.creado.addingTimeInterval(10 * 60)) == 1)
        #expect(modelo.elementos.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: item.rutaCopia))
        #expect(FileManager.default.fileExists(atPath: origen.path))
    }

    @Test func miniaturaNoPasaDeSesentaYCuatroPixeles() throws {
        let raiz = FileManager.default.temporaryDirectory.appending(path: "notchy-mini-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let rep = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 800, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0))
        try #require(rep.representation(using: .png, properties: [:])).write(to: raiz)

        let mini = try #require(ModeloDeBandeja.miniatura(de: raiz))
        #expect(max(mini.size.width, mini.size.height) <= 64)
    }
}
