# Genera la newsletter (HTML en docs\) y el archivo de tres bloques para la carpeta SIO,
# a partir de datos\<edicion>.json (descarga) y clasificacion\<edicion>.json (criterio de Claude).
# Uso: powershell -ExecutionPolicy Bypass -File scripts\publicar.ps1 -Edicion AAAA-MM-DD [-SinPush]
param(
    [string]$Edicion = (Get-Date).ToString('yyyy-MM-dd'),
    [string]$CarpetaSIO = 'C:\Users\Usuario\Downloads\SIO - IA\ASPM\boletines',
    [switch]$SinPush
)
$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
$utf8 = New-Object Text.UTF8Encoding $false
function Leer-Json($p) { [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8) | ConvertFrom-Json }
function Esc($s) { [Net.WebUtility]::HtmlEncode("$s") }

$datos = Leer-Json (Join-Path $raiz "datos\$Edicion.json")
$clas = Leer-Json (Join-Path $raiz "clasificacion\$Edicion.json")

$porId = @{}
foreach ($it in $datos.items) { $porId[$it.id] = $it }
$usados = @{}
function Resolver($lista) {
    $out = @()
    foreach ($c in @($lista)) {
        if ($null -eq $c) { continue }
        $it = $porId[$c.id]
        if ($null -eq $it) { Write-Warning "id desconocido en la clasificación: $($c.id)"; continue }
        $usados[$c.id] = $true
        $out += [pscustomobject]@{ c = $c; it = $it }
    }
    return $out
}
$afecta = @(Resolver $clas.afecta)
$conviene = @(Resolver $clas.conviene)
$descartados = @($datos.items | Where-Object { -not $usados.ContainsKey($_.id) })
# Notificaciones a personas con nombre: no se reproduce el título (datos personales de terceros)
$omitir = @{}
foreach ($id in @($clas.omitir_titulo)) { if ($id) { $omitir["$id"] = $true } }
foreach ($it in $descartados) {
    if ($omitir.ContainsKey($it.id)) { $it.titulo = 'Notificación o acto dirigido a una persona física (título omitido por privacidad)' }
}
$noticias = @($clas.noticias | Where-Object { $_ })

$meses = 'enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'
function FechaLarga($iso) { $d = [datetime]::ParseExact($iso, 'yyyy-MM-dd', $null); "$($d.Day) de $($meses[$d.Month-1]) de $($d.Year)" }
$cubre = (@($datos.fechas) | ForEach-Object { FechaLarga $_ }) -join ', '

# ---------- Correo de reenvío ----------
# Cada tarjeta lleva un botón que abre un borrador en Gmail (Google Workspace de 22q13.org.es).
# El texto lo escribe Claude en el campo "correo" de la clasificación (ver estilo-correo.md);
# si falta, se genera uno genérico con el titular, el plazo y el enlace.
function Correo($c, $titular, $plazo, $url, [switch]$Tramite) {
    if ($c.correo -and $c.correo.cuerpo) { return [pscustomobject]@{ asunto = "$($c.correo.asunto)"; cuerpo = "$($c.correo.cuerpo)" } }
    $asunto = $titular; if ($plazo) { $asunto += " - Plazo: $plazo" }
    $cuerpo = "Buenos días familia 😊`n`nOs hago llegar información sobre esto: $titular.`n"
    if ($plazo) { $cuerpo += "`nPlazo: $plazo`n" }
    $cuerpo += "`nMás información: $url`n"
    if ($Tramite) { $cuerpo += "`nSi tenéis dudas o queréis que lo veamos juntos, por favor decídmelo y lo comentamos sin problema.`n" }
    else { $cuerpo += "`nSi tenéis dudas, por favor decídmelo y lo comentamos sin problema.`n" }
    $cuerpo += "`nMuchas gracias.`n`nUn saludo,"
    return [pscustomobject]@{ asunto = $asunto; cuerpo = $cuerpo }
}
# Al pulsar el botón, el saludo se adapta a la hora: «Buenos días» antes de las 14:00, «Buenas tardes» después.
$scriptSaludo = '<script>document.addEventListener("click",function(e){var a=e.target.closest&&e.target.closest("a.reenviar");if(!a)return;var t=new Date().getHours()>=14,de=encodeURIComponent(t?"Buenos días":"Buenas tardes"),a2=encodeURIComponent(t?"Buenas tardes":"Buenos días");a.href=a.href.replace(de,a2);});</script>'
function Boton($m) {
    $u = 'https://mail.google.com/mail/?view=cm&fs=1&su=' + [Uri]::EscapeDataString($m.asunto) + '&body=' + [Uri]::EscapeDataString(($m.cuerpo -replace "`r", ''))
    "<a class=`"reenviar`" href=`"$(Esc $u)`" target=`"_blank`" rel=`"noopener`">✉ Reenviar por correo</a>"
}

# ---------- HTML ----------
function Tarjetas($lista, $clase) {
    if ($lista.Count -eq 0) { return '<p class="vacio">Nada hoy en este bloque.</p>' }
    $sb = New-Object Text.StringBuilder
    foreach ($x in $lista) {
        $c = $x.c; $it = $x.it
        $titular = $c.titular; if (-not $titular) { $titular = $it.titulo }
        [void]$sb.Append("<article class=`"card $clase`"><div class=`"tags`"><span class=`"tag`">$(Esc $it.boletin)</span><span class=`"tag`">$(Esc (FechaLarga $it.fecha))</span>")
        if ($c.plazo) { [void]$sb.Append("<span class=`"tag plazo`">Plazo: $(Esc $c.plazo)</span>") }
        [void]$sb.Append("</div><h3>$(Esc $titular)</h3>")
        if ($c.por_que) { [void]$sb.Append("<p>$(Esc $c.por_que)</p>") }
        $m = Correo $c $titular $c.plazo $it.url -Tramite
        [void]$sb.Append("<p class=`"orig`">$(Esc $it.departamento) · $(Esc $it.titulo)</p><p class=`"acciones`"><a href=`"$(Esc $it.url)`" target=`"_blank`" rel=`"noopener`">Leer en la fuente oficial →</a>$(Boton $m)</p></article>")
    }
    return $sb.ToString()
}

function Pagina($prefijo, $archivoHtml) {
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append(@"
<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Boletín ASPM · $(Esc (FechaLarga $Edicion))</title><link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Montserrat:wght@400;500;600;700&display=swap"><link rel="stylesheet" href="${prefijo}estilo.css"></head><body><div class="wrap">
<header class="top"><a href="https://22q13.org.es/" target="_blank" rel="noopener"><img class="logo" src="${prefijo}logo-aspm.png" alt="Asociación Síndrome Phelan-McDermid" width="200" height="58"></a><div class="kicker">Boletín ASPM · Discapacidad, dependencia y familias</div><h1>$(Esc (FechaLarga $Edicion))</h1>
<div class="meta">Boletines revisados: $(Esc $cubre) · $($datos.items.Count) disposiciones leídas · <a href="${archivoHtml}">Histórico y buscador</a></div></header>
"@)
    if ($clas.resumen) { [void]$sb.Append("<div class=`"resumen`">$(Esc $clas.resumen)</div>") }
    [void]$sb.Append("<h2 class=`"b1`">1. Te afecta directamente <span class=`"n`">$($afecta.Count)</span></h2>" + (Tarjetas $afecta 'b1'))
    [void]$sb.Append("<h2>2. Conviene que lo sepas <span class=`"n`">$($conviene.Count)</span></h2>" + (Tarjetas $conviene ''))
    [void]$sb.Append("<h2>Noticias del sector <span class=`"n`">$($noticias.Count)</span></h2>")
    if ($noticias.Count -eq 0) { [void]$sb.Append('<p class="vacio">Sin noticias destacables hoy.</p>') }
    foreach ($n in $noticias) {
        [void]$sb.Append("<div class=`"noticia`"><a href=`"$(Esc $n.url)`" target=`"_blank`" rel=`"noopener`"><strong>$(Esc $n.titulo)</strong></a><div class=`"src`">$(Esc $n.fuente)$(if ($n.fecha) { ' · ' + (Esc $n.fecha) })</div><div>$(Esc $n.resumen)</div><p class=`"acciones`">$(Boton (Correo $n $n.titulo '' $n.url))</p></div>")
    }
    [void]$sb.Append("<h2>3. Descartado <span class=`"n`">$($descartados.Count)</span></h2><p class=`"orig`">Una línea por disposición, para comprobar que no se ha colado nada relevante.</p>")
    foreach ($g in ($descartados | Group-Object boletin | Sort-Object { if ($_.Name -eq 'BOE') { '0' } else { $_.Name } })) {
        [void]$sb.Append("<details><summary>$(Esc $g.Name) — $($g.Count)</summary><ul>")
        foreach ($it in $g.Group) {
            $t = $it.titulo; if ($t.Length -gt 220) { $t = $t.Substring(0, 220) + '…' }
            [void]$sb.Append("<li><a href=`"$(Esc $it.url)`" target=`"_blank`" rel=`"noopener`">$(Esc $t)</a></li>")
        }
        [void]$sb.Append('</ul></details>')
    }
    [void]$sb.Append('<h2>Estado de las fuentes</h2><table class="fuentes"><tr><th>Boletín</th><th>Fecha</th><th>Estado</th><th>Nº</th></tr>')
    foreach ($f in $datos.fuentes) {
        $cls = ''; $txt = $f.estado
        if ($f.estado -eq 'error') { $cls = ' class="err"'; $txt = 'error: ' + $f.error }
        [void]$sb.Append("<tr><td>$(Esc $f.fuente)</td><td>$(Esc $f.fecha)</td><td$cls>$(Esc $txt)</td><td>$($f.n)</td></tr>")
    }
    [void]$sb.Append('</table>')
    [void]$sb.Append("<footer>Selección automática hecha con IA a partir de los boletines oficiales. Comprueba siempre el texto en la fuente oficial antes de actuar. · <a href=`"${archivoHtml}`">Histórico y buscador</a></footer></div>$scriptSaludo</body></html>")
    return $sb.ToString()
}

$docs = Join-Path $raiz 'docs'
New-Item -ItemType Directory -Force (Join-Path $docs 'ediciones') | Out-Null
[IO.File]::WriteAllText((Join-Path $docs "ediciones\$Edicion.html"), (Pagina '../' '../archivo.html'), $utf8)
[IO.File]::WriteAllText((Join-Path $docs 'index.html'), (Pagina '' 'archivo.html'), $utf8)

# Histórico acumulado (bloques 1 y 2 + noticias de todas las ediciones) para el buscador.
# Fuente de verdad: historico\entradas.json; la web lo lee desde docs\historico.js (funciona también abriendo el archivo local).
$histFile = Join-Path $raiz 'historico\entradas.json'
New-Item -ItemType Directory -Force (Split-Path $histFile) | Out-Null
$hist = @()
# (en PS 5.1 ConvertFrom-Json entrega el array como un solo objeto: ForEach-Object lo desenrolla)
if (Test-Path $histFile) { $hist = @(Leer-Json $histFile | ForEach-Object { $_ } | Where-Object { $_.edicion -ne $Edicion }) }
foreach ($par in @(@('afecta', $afecta), @('conviene', $conviene))) {
    foreach ($x in @($par[1])) {
        $tit = $x.c.titular; if (-not $tit) { $tit = $x.it.titulo }
        $m = Correo $x.c $tit $x.c.plazo $x.it.url -Tramite
        $hist += [pscustomobject]@{ edicion = $Edicion; fecha = $x.it.fecha; tipo = $par[0]; titulo = $tit; texto = "$($x.c.por_que)"
            fuente = $x.it.boletin; plazo = "$($x.c.plazo)"; url = $x.it.url; original = $x.it.titulo; asunto = $m.asunto; cuerpo = $m.cuerpo }
    }
}
foreach ($n in $noticias) {
    $m = Correo $n $n.titulo '' $n.url
    $hist += [pscustomobject]@{ edicion = $Edicion; fecha = $Edicion; tipo = 'noticia'; titulo = $n.titulo; texto = "$($n.resumen)"
        fuente = "$($n.fuente)"; plazo = ''; url = $n.url; original = "$($n.fecha)"; asunto = $m.asunto; cuerpo = $m.cuerpo }
}
$hist = @($hist | Sort-Object edicion -Descending)
$histJson = ConvertTo-Json -InputObject $hist -Depth 3
[IO.File]::WriteAllText($histFile, $histJson, $utf8)
[IO.File]::WriteAllText((Join-Path $docs 'historico.js'), "window.HISTORICO = $histJson;", $utf8)

# Página de histórico: buscador + lista de ediciones
$eds = Get-ChildItem (Join-Path $docs 'ediciones') -Filter *.html | Sort-Object Name -Descending
$li = ($eds | ForEach-Object { "<li><a href=`"ediciones/$($_.Name)`">$(Esc (FechaLarga $_.BaseName))</a></li>" }) -join ''
$li = @"
<div class="buscador"><input id="q" type="search" placeholder="Buscar en todas las ediciones (p. ej. dependencia, Galicia, CUME…)" aria-label="Buscar">
<select id="tipo" aria-label="Tipo"><option value="">Todo</option><option value="afecta">1. Te afecta directamente</option><option value="conviene">2. Conviene que lo sepas</option><option value="noticia">Noticias</option></select></div>
<p id="cuenta" class="orig"></p><div id="res"></div>
<h2>Todas las ediciones</h2><ul class="archivo">$li</ul>
<script src="historico.js"></script>
<script>
(function () {
  var datos = window.HISTORICO || [], q = document.getElementById('q'), tipo = document.getElementById('tipo'),
      res = document.getElementById('res'), cuenta = document.getElementById('cuenta');
  var etiquetas = { afecta: '1. Te afecta', conviene: '2. Conviene saber', noticia: 'Noticia' };
  function norm(s) { return (s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase(); }
  function esc(s) { var d = document.createElement('div'); d.textContent = s || ''; return d.innerHTML; }
  function gmail(e) { return 'https://mail.google.com/mail/?view=cm&fs=1&su=' + encodeURIComponent(e.asunto || '') + '&body=' + encodeURIComponent(e.cuerpo || ''); }
  function fecha(iso) { var p = iso.split('-'); return p[2] + '/' + p[1] + '/' + p[0]; }
  function pintar() {
    var t = norm(q.value).split(/\s+/).filter(Boolean), k = tipo.value;
    var lista = datos.filter(function (e) {
      if (k && e.tipo !== k) return false;
      var h = norm([e.titulo, e.texto, e.fuente, e.original, e.plazo].join(' '));
      return t.every(function (w) { return h.indexOf(w) >= 0; });
    });
    cuenta.textContent = lista.length + (lista.length === 1 ? ' resultado' : ' resultados') + ' en ' + datos.length + ' entradas guardadas';
    res.innerHTML = lista.slice(0, 200).map(function (e) {
      return '<article class="card' + (e.tipo === 'afecta' ? ' b1' : '') + '"><div class="tags"><span class="tag">' + etiquetas[e.tipo] + '</span><span class="tag">' + esc(e.fuente) + '</span><span class="tag">Edición ' + fecha(e.edicion) + '</span>' +
        (e.plazo ? '<span class="tag plazo">Plazo: ' + esc(e.plazo) + '</span>' : '') + '</div><h3>' + esc(e.titulo) + '</h3>' +
        (e.texto ? '<p>' + esc(e.texto) + '</p>' : '') + '<p class="acciones"><a href="' + esc(e.url) + '" target="_blank" rel="noopener">Abrir la fuente →</a><a href="ediciones/' + e.edicion + '.html">Ver la edición</a>' +
        (e.cuerpo ? '<a class="reenviar" href="' + esc(gmail(e)) + '" target="_blank" rel="noopener">✉ Reenviar por correo</a>' : '') + '</p></article>';
    }).join('');
  }
  q.addEventListener('input', pintar); tipo.addEventListener('change', pintar); pintar();
})();
</script>
"@
$arch = "<!doctype html><html lang=`"es`"><head><meta charset=`"utf-8`"><meta name=`"viewport`" content=`"width=device-width,initial-scale=1`"><title>Boletín ASPM · Histórico</title><link rel=`"preconnect`" href=`"https://fonts.googleapis.com`"><link rel=`"preconnect`" href=`"https://fonts.gstatic.com`" crossorigin><link rel=`"stylesheet`" href=`"https://fonts.googleapis.com/css2?family=Montserrat:wght@400;500;600;700&display=swap`"><link rel=`"stylesheet`" href=`"estilo.css`"></head><body><div class=`"wrap`"><header class=`"top`"><a href=`"https://22q13.org.es/`" target=`"_blank`" rel=`"noopener`"><img class=`"logo`" src=`"logo-aspm.png`" alt=`"Asociación Síndrome Phelan-McDermid`" width=`"200`" height=`"58`"></a><div class=`"kicker`">Boletín ASPM</div><h1>Histórico</h1><div class=`"meta`"><a href=`"index.html`">← Última edición</a></div></header>$li</div>$scriptSaludo</body></html>"
[IO.File]::WriteAllText((Join-Path $docs 'archivo.html'), $arch, $utf8)
if (-not (Test-Path (Join-Path $docs '.nojekyll'))) { [IO.File]::WriteAllText((Join-Path $docs '.nojekyll'), '', $utf8) }

# ---------- Markdown para la carpeta SIO ----------
function Limpio($s) { ("$s" -replace '\r?\n', ' ').Trim() }
$md = New-Object Text.StringBuilder
[void]$md.AppendLine("# Boletines — $Edicion")
[void]$md.AppendLine('')
[void]$md.AppendLine("> Generado automáticamente cada mañana. Boletines revisados: $cubre · $($datos.items.Count) disposiciones.")
[void]$md.AppendLine("> Web: https://sio-aspm.github.io/boletin-aspm/ediciones/$Edicion.html")
[void]$md.AppendLine('')
if ($clas.resumen) { [void]$md.AppendLine((Limpio $clas.resumen)); [void]$md.AppendLine('') }
foreach ($bloque in @(@('## 1. Me afecta directamente', $afecta), @('## 2. Conviene que sepa', $conviene))) {
    [void]$md.AppendLine($bloque[0]); [void]$md.AppendLine('')
    if (@($bloque[1]).Count -eq 0) { [void]$md.AppendLine('*(nada hoy)*') }
    foreach ($x in @($bloque[1])) {
        $tit = $x.c.titular; if (-not $tit) { $tit = $x.it.titulo }
        $pl = ''; if ($x.c.plazo) { $pl = " **Plazo: $(Limpio $x.c.plazo).**" }
        [void]$md.AppendLine("- **$(Limpio $tit)** ($($x.it.boletin), $($x.it.fecha)).$pl $(Limpio $x.c.por_que) [Enlace]($($x.it.url))")
    }
    [void]$md.AppendLine('')
}
[void]$md.AppendLine('## Noticias del sector'); [void]$md.AppendLine('')
if ($noticias.Count -eq 0) { [void]$md.AppendLine('*(sin noticias destacables)*') }
foreach ($n in $noticias) { [void]$md.AppendLine("- [$(Limpio $n.titulo)]($($n.url)) — $(Limpio $n.fuente). $(Limpio $n.resumen)") }
[void]$md.AppendLine('')
[void]$md.AppendLine("## 3. Descartado ($($descartados.Count))"); [void]$md.AppendLine('')
foreach ($it in $descartados) { [void]$md.AppendLine("- $($it.boletin) · $(Limpio $it.titulo) [↗]($($it.url))") }
[void]$md.AppendLine('')
$errs = @($datos.fuentes | Where-Object { $_.estado -eq 'error' })
if ($errs.Count -gt 0) {
    [void]$md.AppendLine('## Fuentes con error'); [void]$md.AppendLine('')
    foreach ($e in $errs) { [void]$md.AppendLine("- $($e.fuente) ($($e.fecha)): $(Limpio $e.error)") }
}
New-Item -ItemType Directory -Force $CarpetaSIO | Out-Null
[IO.File]::WriteAllText((Join-Path $CarpetaSIO "$Edicion.md"), $md.ToString(), $utf8)

# ---------- Estado y publicación ----------
New-Item -ItemType Directory -Force (Join-Path $raiz 'estado') | Out-Null
[IO.File]::WriteAllText((Join-Path $raiz 'estado\ultima-fecha.txt'), @($datos.fechas)[-1], $utf8)
Write-Host "Generado: afecta=$($afecta.Count) conviene=$($conviene.Count) noticias=$($noticias.Count) descartados=$($descartados.Count)"

if (-not $SinPush) {
    $git = 'C:\Program Files\Git\cmd\git.exe'
    Push-Location $raiz
    try {
        & $git add -A
        & $git commit -q -m "Edición $Edicion"
        & $git push -q origin main
        if ($LASTEXITCODE -ne 0) { throw "git push falló (código $LASTEXITCODE)" }
        Write-Host 'Publicado en GitHub Pages.'
    } finally { Pop-Location }
}
