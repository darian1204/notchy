import Foundation
import Testing

@testable import NotchyTestSupport

@Test func elAlmacenEnMemoriaCumpleElContrato() {
    let almacen = AlmacenEnMemoria()
    #expect(almacen.leer("nada") == nil)
    almacen.guardar(Data([1]), en: "dato")
    #expect(almacen.leer("dato") == Data([1]))
    almacen.guardar(nil, en: "dato")
    #expect(almacen.leer("dato") == nil)
    #expect(almacen.claves.isEmpty)
}
