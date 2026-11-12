# Isla

App personal para el notch de mi MacBook Air M4: portapapeles, agenda, bandeja de archivos, música, reuniones transcritas en el propio Mac y un agente de voz. Solo macOS 27, solo arm64, solo para uso mío.

Estado: **M0**, el esqueleto. La app abre sin ventana y sin pedir permisos; las capas están vacías.

## Requisitos

- Xcode 27.2 (Swift 6.4) con un certificado Apple Development del equipo `3GB89AS998`.
- OpenCode en la versión de `Resources/opencode/VERSION` (hace falta desde M6).

## Uso

| Comando | Qué hace |
|---|---|
| `scripts/check` | Formato, regla de capas, plist, secretos, paquete en modo estricto con pruebas, app y firma. Tiene que pasar antes de unir a `main` |
| `scripts/run` | Compila, firma y abre la app de depuración |
| `scripts/verificar-firma` | Muestra identidad, equipo y entitlements de la app compilada |

Los registros largos quedan en `build/logs`. Para trabajar solo en el paquete: `swift test --package-path Packages/IslaKit`.

## Estructura

```
App/                 arranque, Info.plist, entitlements y assets
Config/              ajustes de compilación (.xcconfig)
Packages/IslaKit/    todas las capas y sus pruebas
Resources/opencode/  plantilla de config, prompt del agente y versión fijada
scripts/             check, run, verificar-firma
docs/                resumen de arquitectura
```

La app es delgada: solo ensambla. Las capas y sus reglas están en `docs/arquitectura.md` y en `AGENTS.md`.

## No cambiar sin pensarlo

El identificador `dev.darian.isla` y el equipo de firma viven en `Config/Base.xcconfig`. Cambiarlos reinicia todos los permisos del sistema.
