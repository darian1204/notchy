# Reglas para agentes

Aplican a cualquier agente que toque este repo. La fuente de verdad del diseño es el vault de Darian (`03-proyectos/programacion/isla/`); este archivo resume lo que no se negocia.

## Antes de tocar nada

- Confirma repo, rama y `git status`.
- Corre `scripts/check` antes de dar algo por terminado. Si falla una vez y no es obvio por qué, detente y escala; no iteres en bucle.

## Capas

Todo el código vive en `Packages/IslaKit`. `App/` solo ensambla.

| Capa | Puede importar |
|---|---|
| IslaCore | nada del proyecto |
| IslaDesign | nada del proyecto (solo SwiftUI) |
| IslaStorage | IslaCore, GRDB |
| IslaPlatform | IslaCore |
| IslaIsland | IslaCore, IslaDesign |
| IslaFeatures | IslaCore, IslaStorage, IslaDesign |
| IslaAgent | IslaCore, IslaStorage, MCP |
| IslaTestSupport | IslaCore |

- IslaFeatures nunca importa IslaPlatform: habla con el sistema por puertos definidos en IslaCore.
- La regla está en dos lugares que deben coincidir: `Packages/IslaKit/Package.swift` y `scripts/check`.
- Sin dependencias externas nuevas sin permiso de Darian. Hoy son GRDB y el SDK de MCP.

## Código

- Swift 6 con concurrencia estricta. Las advertencias son errores en `scripts/check`.
- Formato con `xcrun swift-format format -i -r App Packages/IslaKit`.
- Pruebas con Swift Testing, una carpeta por capa. Lo nuevo entra con pruebas.
- Nombres y comentarios en español; términos técnicos en inglés cuando así se usan.

## Firma y permisos

- No cambies `PRODUCT_BUNDLE_IDENTIFIER`, `DEVELOPMENT_TEAM` ni el estilo de firma: reinicia los permisos del sistema.
- `App/Info.plist` y `App/Isla.entitlements` se escriben a mano. Un permiso nuevo necesita su texto de uso y su línea en `scripts/check`.
- Sin App Sandbox y con Hardened Runtime; no lo cambies.

## Git

- Autor único: `Darian Maynez <darian1204@users.noreply.github.com>`.
- Nunca agregues `Co-Authored-By` ni ninguna atribución a un agente, ni en commits ni en PRs.
- `main` siempre compila. Trabajo en `feat/<módulo>-<tema>`.
- Mensajes en español: "Módulo: qué cambió".
- Una etiqueta por hito (`m0`, `m1`…).
- Lo sensible (permisos, agente, datos de reuniones) pasa por una auditoría del `git diff` antes de unir.

## Privacidad

- Nada sale del Mac salvo lo que el agente manda al proveedor que Darian eligió.
- Sin telemetría, sin actualizador, sin analítica.
- Nunca escribas en el repo tokens, contraseñas, audio, transcripciones ni contenido del portapapeles. `scripts/check` busca secretos, pero no los detecta todos.
- El agente no puede usar suscripciones que su dueño prohíbe fuera de su app (Claude Pro/Max, Antigravity): solo los proveedores de `enabled_providers`.
