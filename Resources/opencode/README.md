# OpenCode

Plantilla de la config que Notchy escribe al lanzar `opencode serve --pure` (hito M6). No se usa todavía.

- `VERSION`: versión de OpenCode con la que se probó (S6 de la fase 0). Subirla es una decisión, no una actualización automática.
- `opencode.plantilla.json`: Notchy rellena `{{PUERTO}}` y `{{TOKEN}}` en cada arranque con un puerto y un token aleatorios. Nunca se guardan en el repo.
- `permission`: todo negado por defecto. Cada herramienta se abre con su nombre `notchy_<herramienta>` en `allow` (lectura) o `ask` (escritura).
- `enabled_providers`: lista corta a propósito. No agregar suscripciones que su dueño prohíbe usar fuera de su app.
