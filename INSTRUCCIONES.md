# Procedimiento diario — Boletín ASPM

> Lo ejecuta cada mañana la tarea programada "Boletín ASPM" de la app de Claude. Todo en
> castellano. Repositorio: `C:\Users\Usuario\boletin-aspm` (público, GitHub Pages).
> **Nunca** se escriben aquí ni en la web datos de familias ni nada de la carpeta SIO salvo el
> archivo diario de `ASPM\boletines\`.

`$ED` = fecha de hoy en formato AAAA-MM-DD.

## 1. Descargar

```powershell
cd C:\Users\Usuario\boletin-aspm
powershell -ExecutionPolicy Bypass -File scripts\descargar.ps1 -Edicion $ED
```

Cubre automáticamente los días que falten desde la última edición (si el PC estuvo apagado).
Si una fuente da error, no se detiene: queda anotado y sale en la web. Si **todas** fallan
(sin conexión), para aquí y dilo en el resumen final.

## 2. Clasificar con criterio

1. Lee `criterio.md` entero.
2. Lee `datos\$ED.tsv` **entero** (por tramos si es largo). Cada línea es una disposición:
   `id, boletín, sección, departamento, título`.
3. Decide para cada una: bloque 1 (`afecta`), bloque 2 (`conviene`) o descartado (no se anota;
   todo lo que no esté en los bloques 1 y 2 se descarta automáticamente).
   - Clasifica por lo que **significa**, no por palabras sueltas.
   - Si el título no basta para decidir, o si es una convocatoria (para sacar el plazo), **abre
     la URL** (está en `datos\$ED.json`) con WebFetch y lee lo necesario.
   - Anota en `omitir_titulo` los ids de notificaciones o actos dirigidos a personas físicas con
     nombre.
4. Escribe un `resumen` de 2-3 frases: lo más importante del día para ella. Si no hay nada en el
   bloque 1, dilo claramente ("Hoy no hay nada que te afecte directamente").

## 3. Investigar noticias del sector (España)

Con WebSearch y WebFetch busca noticias **de los últimos 3 días** en: CERMI, Plena Inclusión,
FEDER (enfermedades raras), IMSERSO, Ministerio de Derechos Sociales, Servimedia, Discapnet,
Confederación Autismo España y prensa generalista sobre discapacidad, dependencia, familia
numerosa, enfermedades raras y educación inclusiva. Selecciona de 3 a 8 que le sirvan a ella
según `criterio.md`. **Abre cada enlace** para comprobar que existe y es de esos días; nunca
inventes titulares ni URLs. Si no hay nada relevante, deja la lista vacía.

## 4. Escribir `clasificacion\$ED.json`

UTF-8. Formato exacto:

```json
{
  "edicion": "AAAA-MM-DD",
  "resumen": "…",
  "afecta":   [ { "id": "BOE-0922-12", "titular": "…", "por_que": "…", "plazo": "" } ],
  "conviene": [ { "id": "BOCM-0922-40", "titular": "…", "por_que": "…", "plazo": "" } ],
  "noticias": [ { "titulo": "…", "fuente": "CERMI", "fecha": "22 de septiembre de 2026", "url": "https://…", "resumen": "…" } ],
  "omitir_titulo": [ "DOE-0922-88" ]
}
```

Los `id` deben existir tal cual en el TSV.

## 5. Publicar

```powershell
powershell -ExecutionPolicy Bypass -File scripts\publicar.ps1 -Edicion $ED
```

Genera la web (`docs\`), el archivo `C:\Users\Usuario\Downloads\SIO - IA\ASPM\boletines\$ED.md`
y hace `git push`. Si el push falla (credenciales caducadas, sin red), el archivo local ya está
generado: dilo en el resumen final.

## 6. Resumen final (tu último mensaje)

Muy breve, para leerlo en segundos:
- Nº en bloque 1 y sus titulares (con plazo si lo hay).
- Nº en bloque 2 y nº de descartados.
- Fuentes con error, si las hay.
- Enlace: https://sio-aspm.github.io/boletin-aspm/
