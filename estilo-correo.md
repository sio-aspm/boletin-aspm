# Estilo de los correos de reenvío

> Cada tarjeta de la newsletter tiene un botón **«Reenviar por correo»** que abre un borrador en
> Gmail con asunto y texto ya escritos. El borrador solo se crea cuando ella pulsa el botón; nunca
> se crean borradores automáticamente. El texto lo redacta Claude cada mañana (campo `correo` de
> `clasificacion\AAAA-MM-DD.json`) siguiendo esta guía. Si ella corrige un correo, el ajuste va aquí.
>
> Ajustado el 2026-09-24 a partir de sus correos reales a familias (validado por ella).

## A quién va

Por defecto a **familias** (varias a la vez, en CCO). En la web pública el destinatario queda vacío.
En la **copia local** (`C:\Users\Usuario\boletin-aspm-privado\index.html`, desde el 2026-10-26) el
botón pregunta a qué comunidades se envía —marcada la del boletín, o todas si es estatal— y pone en
CCO los correos de la BB.DD. de personas de esas comunidades: todas las personas con email de la
hoja PERSONAS (menos BAJA y residentes fuera de España) y las de CONTACTOS SIO con provincia de
España. Si son demasiadas para el enlace de Gmail, las copia al portapapeles para pegarlas en CCO.

## Forma

- **Asunto:** `Tema - detalle`, con guion, corto y sin punto final. Si hay plazo, el detalle es el
  plazo: `Ayudas transporte escolar Galicia - Plazo hasta el 23 de octubre`. Sin plazo, el detalle
  concreta: `Reforma dependencia y discapacidad - Qué cambia para las familias`.
- **Cuerpo**, texto plano (Gmail no admite formato en el enlace), en este orden:
  1. `Buenos días familia 😊` — **siempre literal así**: al pulsar el botón por la tarde, la web lo
     cambia sola a `Buenas tardes familia 😊`.
  2. Directa al grano, sin «por si os resulta útil»: `Os hago llegar información sobre…` (trámites,
     ayudas) o `Os comparto esta noticia sobre…` (noticias).
  3. **Qué es**, en 2-4 frases llanas, sin jerga administrativa. A quién beneficia. Si ayuda, una
     lista corta con guiones.
  4. `Plazo: …` en línea propia, si lo hay.
  5. `Más información: <url>` en línea propia (fuente oficial o noticia original).
  6. Cierre: `Si tenéis dudas o queréis que lo veamos juntos, por favor decídmelo y lo comentamos
     sin problema.` (en noticias: `Si tenéis dudas, por favor decídmelo y lo comentamos sin problema.`)
  7. `Muchas gracias.` y `Un saludo,` — la firma la añade Gmail sola.
- Trato de **vosotros**, cercano y cálido. Castellano. Solo el 😊 del saludo, ningún otro emoji.
- Nunca datos de una familia concreta ni nada de la carpeta SIO: la web es pública.
- Máximo ~900 caracteres de cuerpo (el enlace de Gmail tiene límite de longitud).
