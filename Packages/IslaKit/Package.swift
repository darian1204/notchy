// swift-tools-version: 6.2
import Foundation
import PackageDescription

// scripts/check compila con ISLA_ESTRICTO=1: las advertencias del paquete son errores.
let estricto = ProcessInfo.processInfo.environment["ISLA_ESTRICTO"] == "1"
var ajustes: [SwiftSetting] = [.enableUpcomingFeature("MemberImportVisibility")]
if estricto {
    ajustes.append(.treatAllWarnings(as: .error))
}

let grdb: Target.Dependency = .product(name: "GRDB", package: "GRDB.swift")
let mcp: Target.Dependency = .product(name: "MCP", package: "swift-sdk")

// Capa y de qué depende. La misma regla la revisa scripts/check contra los import.
let capas: [(nombre: String, dependencias: [Target.Dependency])] = [
    ("IslaCore", []),
    ("IslaDesign", []),
    ("IslaStorage", ["IslaCore", grdb]),
    ("IslaPlatform", ["IslaCore"]),
    ("IslaIsland", ["IslaCore", "IslaDesign"]),
    ("IslaFeatures", ["IslaCore", "IslaStorage", "IslaDesign"]),
    ("IslaAgent", ["IslaCore", "IslaStorage", mcp]),
    ("IslaTestSupport", ["IslaCore"]),
]

// Lo que cada carpeta de pruebas necesita además de su capa.
let extrasDePruebas: [String: [Target.Dependency]] = [
    "IslaStorage": [grdb]
]

var targets: [Target] = []
for capa in capas {
    targets.append(.target(name: capa.nombre, dependencies: capa.dependencias, swiftSettings: ajustes))
    var dependencias: [Target.Dependency] = [.target(name: capa.nombre)]
    if capa.nombre != "IslaTestSupport" {
        dependencias.append("IslaTestSupport")
    }
    dependencias += extrasDePruebas[capa.nombre] ?? []
    targets.append(.testTarget(name: capa.nombre + "Tests", dependencies: dependencias, swiftSettings: ajustes))
}

let package = Package(
    name: "IslaKit",
    platforms: [.macOS("27.0")],
    products: capas.map { .library(name: $0.nombre, targets: [$0.nombre]) },
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.12.1"),
    ],
    targets: targets,
    swiftLanguageModes: [.v6]
)
