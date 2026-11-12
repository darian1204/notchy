# Arquitectura (resumen)

El detalle vive en el vault de Darian, en `03-proyectos/programacion/isla/`: `arquitectura/` (capas, módulos, datos y eventos, repo y entorno), `requisitos/`, `calidad/` y `roadmap/`. Si este resumen y el vault no coinciden, manda el vault.

## Idea

Una app agente (sin Dock) que dibuja un panel sobre el notch. Cada función es un módulo que se registra en la isla. Los módulos no tocan el sistema directamente: piden lo que necesitan por puertos de `IslaCore`, y `IslaPlatform` trae los adaptadores reales. Así los módulos se prueban con falsos.

## Capas

| Capa | Qué tiene | Depende de |
|---|---|---|
| IslaCore | Tipos, puertos, bus de eventos, ajustes, errores, logs | — |
| IslaDesign | Colores, medidas y componentes de SwiftUI | — |
| IslaStorage | Base SQLite con GRDB, migraciones, repositorios | Core |
| IslaPlatform | Adaptadores reales: audio, portapapeles, calendario, cámara | Core |
| IslaIsland | Panel del notch y su coordinador | Core, Design |
| IslaFeatures | Módulos de función | Core, Storage, Design |
| IslaAgent | Supervisor de OpenCode, servidor MCP, permisos | Core, Storage |
| IslaTestSupport | Falsos y datos de prueba | Core |

`App/` crea los adaptadores de `IslaPlatform` y se los pasa a los módulos.

## Hitos

M0 esqueleto · M1 isla base · M4 grabadora y reuniones · M5 notas de reunión · M2 portapapeles y bandeja · M3 agenda · M6 agente · M7 extras · M8 pulido. Ese es el orden de construcción.
