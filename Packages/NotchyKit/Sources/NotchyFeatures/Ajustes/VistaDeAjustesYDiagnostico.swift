import NotchyCore
import NotchyDesign
import SwiftUI

/// Ventana de Ajustes y panel de Permisos y Diagnóstico (ISL-8, SIS-1, SIS-2).
public struct VistaDeAjustesYDiagnostico: View {
    private let modelo: ModeloDeAjustesYDiagnostico
    private let alAbrirEnlace: (@MainActor (URL) -> Void)?
    private let alBorrarHistorialPortapapeles: (@MainActor () -> Void)?
    private let alSalir: (@MainActor () -> Void)?

    public init(
        modelo: ModeloDeAjustesYDiagnostico,
        alAbrirEnlace: (@MainActor (URL) -> Void)? = nil,
        alBorrarHistorialPortapapeles: (@MainActor () -> Void)? = nil,
        alSalir: (@MainActor () -> Void)? = nil
    ) {
        self.modelo = modelo
        self.alAbrirEnlace = alAbrirEnlace
        self.alBorrarHistorialPortapapeles = alBorrarHistorialPortapapeles
        self.alSalir = alSalir
    }

    public var body: some View {
        @Bindable var ajustes = modelo.ajustes
        TabView {
            Tab("General", systemImage: "slider.horizontal.3") {
                pestanaGeneral(ajustes: $ajustes)
            }
            Tab("Módulos", systemImage: "square.grid.2x2") {
                pestanaModulos()
            }
            Tab("Permisos y diagnóstico", systemImage: "checkmark.shield") {
                pestanaDiagnostico()
            }
        }
        .frame(width: 520, height: 460)
        .onAppear {
            modelo.refrescar()
        }
    }

    private func pestanaGeneral(ajustes: Bindable<Ajustes>) -> some View {
        Form {
            Section("Isla y pantalla") {
                Picker("Pantalla de la isla", selection: ajustes.pantalla) {
                    Text("Pantalla con notch (o principal si no hay)").tag(PantallaPreferida.conNotch)
                    Text("Siempre en la pantalla principal").tag(PantallaPreferida.principal)
                }
                .accessibilityLabel("Pantalla de la isla")

                Picker("Atajo global para abrir o cerrar", selection: ajustes.atajo) {
                    ForEach(AtajoDeIsla.allCases, id: \.self) { atajo in
                        Text(atajo.etiqueta).tag(atajo)
                    }
                }
                .accessibilityLabel("Atajo global para abrir o cerrar")
            }

            Section("Portapapeles") {
                Picker("Retención por antigüedad", selection: ajustes.diasRetencionPortapapeles) {
                    Text("7 días").tag(7)
                    Text("30 días").tag(30)
                    Text("90 días").tag(90)
                }
                .accessibilityLabel("Retención por antigüedad del portapapeles")

                Picker("Límite de elementos", selection: ajustes.limiteElementosPortapapeles) {
                    Text("500 elementos").tag(500)
                    Text("2000 elementos").tag(2000)
                    Text("5000 elementos").tag(5000)
                }
                .accessibilityLabel("Límite de elementos del portapapeles")

                if let alBorrarHistorialPortapapeles {
                    HStack {
                        Text("Los elementos fijados no se borran por retención.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Borrar todo el portapapeles", role: .destructive, action: alBorrarHistorialPortapapeles)
                            .controlSize(.small)
                            .accessibilityLabel("Borrar todo el portapapeles")
                    }
                }
            }

            Section("Barra de menús") {
                Toggle("Mostrar ícono en la barra de menús", isOn: ajustes.iconoEnBarraDeMenus)
                    .accessibilityLabel("Mostrar ícono en la barra de menús")
                Text("Ofrece acceso rápido al estado de la isla, a esta ventana y a Salir de Notchy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let alSalir {
                Section {
                    HStack {
                        Spacer()
                        Button("Salir de Notchy", role: .destructive, action: alSalir)
                            .accessibilityLabel("Salir de Notchy")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func pestanaModulos() -> some View {
        let modulos = modelo.modulosOrdenados
        return Form {
            Section("Módulos activos y su orden") {
                ForEach(Array(modulos.enumerated()), id: \.element.id) { indice, modulo in
                    HStack(spacing: 10) {
                        Image(systemName: modulo.icono)
                            .foregroundStyle(Color(hex: modulo.color))
                            .frame(width: 20)
                        Text(modulo.nombre)
                        Spacer()
                        Button {
                            modelo.moverModuloArriba(modulo.id)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(indice == 0)
                        .help("Subir \(modulo.nombre)")
                        .accessibilityLabel("Subir \(modulo.nombre)")

                        Button {
                            modelo.moverModuloAbajo(modulo.id)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(indice + 1 >= modulos.count)
                        .help("Bajar \(modulo.nombre)")
                        .accessibilityLabel("Bajar \(modulo.nombre)")

                        Toggle(
                            "",
                            isOn: Binding(
                                get: { modelo.estaModuloActivo(modulo.id) },
                                set: { modelo.cambiarModuloActivo(modulo.id, $0) }
                            )
                        )
                        .labelsHidden()
                        .disabled(modulo.id == ModulosBase.inicio && modulos.count == 1)
                        .accessibilityLabel("Activar \(modulo.nombre)")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func pestanaDiagnostico() -> some View {
        Form {
            Section("Permisos del sistema") {
                ForEach(PermisoDelSistema.allCases) { permiso in
                    filaPermiso(permiso)
                }
            }

            Section("Estado del sistema") {
                LabeledContent("Base de datos") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Label(
                            modelo.diagnosticoDeBase.estaBien ? "Lista" : "Atención",
                            systemImage: modelo.diagnosticoDeBase.estaBien
                                ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(modelo.diagnosticoDeBase.estaBien ? .green : .orange)
                        Text(modelo.diagnosticoDeBase.detalle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let arreglo = modelo.diagnosticoDeBase.comoArreglarlo {
                            Text(arreglo)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                LabeledContent("Motor del agente (OpenCode)") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Label(
                            modelo.estadoDeOpenCode.estaListo ? "Instalado" : "Falta instalar",
                            systemImage: modelo.estadoDeOpenCode.estaListo
                                ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(modelo.estadoDeOpenCode.estaListo ? .green : .orange)
                        Text(modelo.estadoDeOpenCode.detalle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(modelo.diagnosticoDeModulos) { modulo in
                    LabeledContent("Módulo: \(modulo.nombre)") {
                        etiquetaSalud(modulo)
                    }
                }
            }

            Section {
                HStack {
                    Button("Actualizar diagnóstico") {
                        modelo.refrescar()
                    }
                    .accessibilityLabel("Actualizar diagnóstico")
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func filaPermiso(_ permiso: PermisoDelSistema) -> some View {
        let estado = modelo.estado(de: permiso)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(permiso.nombre).font(.body.weight(.medium))
                    Text(permiso.paraQueSirve)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(estado.etiqueta)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color(de: estado))

                switch estado {
                case .sinPedir:
                    Button("Pedir permiso") {
                        Task { await modelo.pedirPermiso(permiso) }
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Pedir permiso de \(permiso.nombre)")
                case .denegado, .restringido:
                    if let url = permiso.enlaceDeAjustesDelSistema, let alAbrirEnlace {
                        Button("Abrir Ajustes") {
                            alAbrirEnlace(url)
                        }
                        .controlSize(.small)
                        .accessibilityLabel("Abrir Ajustes del Sistema para \(permiso.nombre)")
                    }
                case .concedido:
                    EmptyView()
                }
            }
            if estado == .denegado || estado == .restringido {
                Text("Cómo activarlo: \(permiso.comoConcederlo)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func etiquetaSalud(_ modulo: DiagnosticoDeModulo) -> some View {
        Group {
            if !modulo.activo {
                Text("Apagado").font(.caption).foregroundStyle(.secondary)
            } else {
                switch modulo.salud {
                case .listo:
                    Label("Listo", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                case .faltaPermiso(let cual):
                    Label("Falta permiso: \(cual)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                case .error(let detalle):
                    Label(detalle, systemImage: "xmark.octagon.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func color(de estado: EstadoDePermiso) -> Color {
        switch estado {
        case .concedido: .green
        case .sinPedir: .secondary
        case .denegado, .restringido: .orange
        }
    }
}
