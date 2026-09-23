# Boletín ASPM

Lectura diaria del **BOE** y de los **17 boletines autonómicos**, filtrada con criterio para el
trabajo social en la Asociación Síndrome Phelan-McDermid: discapacidad, dependencia, CUME, familia
numerosa y ayudas a familias. Incluye noticias del sector.

**Web:** https://sio-aspm.github.io/boletin-aspm/

- `fuentes/` — un lector por boletín (PowerShell).
- `scripts/descargar.ps1` — descarga las disposiciones del día → `datos/`.
- `criterio.md` — criterio de selección.
- `clasificacion/` — clasificación diaria hecha con IA según el criterio.
- `scripts/publicar.ps1` — genera la newsletter en `docs/` (GitHub Pages).

Selección automática: comprueba siempre el texto en la fuente oficial antes de actuar.
