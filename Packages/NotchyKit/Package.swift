// swift-tools-version: 6.2
import Foundation
import PackageDescription

// scripts/check compila con NOTCHY_ESTRICTO=1: las advertencias del paquete son errores.
let estricto = ProcessInfo.processInfo.environment["NOTCHY_ESTRICTO"] == "1"
var ajustes: [SwiftSetting] = [.enableUpcomingFeature("MemberImportVisibility")]
if estricto {
    ajustes.append(.treatAllWarnings(as: .error))
}

let grdb: Target.Dependency = .product(name: "GRDB", package: "GRDB.swift")
let mcp: Target.Dependency = .product(name: "MCP", package: "swift-sdk")
let fluidAudio: Target.Dependency = .product(name: "FluidAudio", package: "FluidAudio")

// Capa y de qué depende. La misma regla la revisa scripts/check contra los import.
let capas: [(nombre: String, dependencias: [Target.Dependency])] = [
    ("NotchyCore", []),
    ("NotchyDesign", []),
    ("NotchyStorage", ["NotchyCore", grdb]),
    ("NotchyPlatform", ["NotchyCore", fluidAudio]),
    ("NotchyIsland", ["NotchyCore", "NotchyDesign"]),
    ("NotchyFeatures", ["NotchyCore", "NotchyStorage", "NotchyDesign"]),
    ("NotchyAgent", ["NotchyCore", "NotchyStorage", mcp]),
    ("NotchyTestSupport", ["NotchyCore"]),
]

// Lo que cada carpeta de pruebas necesita además de su capa.
let extrasDePruebas: [String: [Target.Dependency]] = [
    "NotchyStorage": [grdb],
    "NotchyAgent": [mcp],
]

var targets: [Target] = []
for capa in capas {
    targets.append(.target(name: capa.nombre, dependencies: capa.dependencias, swiftSettings: ajustes))
    var dependencias: [Target.Dependency] = [.target(name: capa.nombre)]
    if capa.nombre != "NotchyTestSupport" {
        dependencias.append("NotchyTestSupport")
    }
    dependencias += extrasDePruebas[capa.nombre] ?? []
    targets.append(.testTarget(name: capa.nombre + "Tests", dependencies: dependencias, swiftSettings: ajustes))
}

let package = Package(
    name: "NotchyKit",
    platforms: [.macOS("27.0")],
    products: capas.map { .library(name: $0.nombre, targets: [$0.nombre]) },
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.12.1"),
        .package(url: "https://github.com/FluidInference/FluidAudio", exact: "0.18.4", traits: ["Diarizer"]),
    ],
    targets: targets,
    swiftLanguageModes: [.v6]
)
