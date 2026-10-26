# Genera la newsletter (HTML en docs\) y el archivo de tres bloques para la carpeta SIO,
# a partir de datos\<edicion>.json (descarga) y clasificacion\<edicion>.json (criterio de Claude).
# Uso: powershell -ExecutionPolicy Bypass -File scripts\publicar.ps1 -Edicion AAAA-MM-DD [-SinPush]
param(
    [string]$Edicion = (Get-Date).ToString('yyyy-MM-dd'),
    [string]$CarpetaSIO = 'C:\Users\Usuario\Downloads\SIO - IA\ASPM\boletines',
    # Copia del boletín con los correos de las familias en el botón de reenvío. Fuera del repositorio: nunca se publica.
    [string]$CarpetaLocal = 'C:\Users\Usuario\boletin-aspm-privado',
    [switch]$SinPush
)
$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'destinatarios.ps1')
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
# data-ccaa: comunidad a la que va dirigida (vacío = estatal). Solo la usa la copia local para preseleccionar el CCO.
function Boton($m, $ccaa) {
    $u = 'https://mail.google.com/mail/?view=cm&fs=1&su=' + [Uri]::EscapeDataString($m.asunto) + '&body=' + [Uri]::EscapeDataString(($m.cuerpo -replace "`r", ''))
    "<a class=`"reenviar`" href=`"$(Esc $u)`" data-ccaa=`"$(Esc $ccaa)`" target=`"_blank`" rel=`"noopener`">✉ Reenviar por correo</a>"
}
# El campo opcional "ccaa" de la clasificación manda; si no, la del boletín (BOE y noticias: estatal).
function CCAA-Item($c, $it) { if ($c.ccaa) { return "$($c.ccaa)" }; if ($it) { return (CCAA-De-Ambito $it.ambito) }; return '' }

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
        [void]$sb.Append("<p class=`"orig`">$(Esc $it.departamento) · $(Esc $it.titulo)</p><p class=`"acciones`"><a href=`"$(Esc $it.url)`" target=`"_blank`" rel=`"noopener`">Leer en la fuente oficial →</a>$(Boton $m (CCAA-Item $c $it))</p></article>")
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
        [void]$sb.Append("<div class=`"noticia`"><a href=`"$(Esc $n.url)`" target=`"_blank`" rel=`"noopener`"><strong>$(Esc $n.titulo)</strong></a><div class=`"src`">$(Esc $n.fuente)$(if ($n.fecha) { ' · ' + (Esc $n.fecha) })</div><div>$(Esc $n.resumen)</div><p class=`"acciones`">$(Boton (Correo $n $n.titulo '' $n.url) (CCAA-Item $n $null))</p></div>")
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

# ---------- Copia local con destinatarios (CCO por comunidad autónoma) ----------
# Misma edición, pero el botón «Reenviar por correo» pregunta a qué CC.AA. se envía y pone en CCO
# los correos de la BB.DD. de personas (ver destinatarios.ps1). Solo existe en este PC.
# Si falla (Excel no encontrado…), la web pública se publica igual.
$scriptEnvio = @'
<style>
.aviso-local{background:#fff4e5;border:1px solid #f0b46a;border-radius:8px;padding:10px 14px;margin:0 0 18px;font-size:14px}
dialog.envio{max-width:560px;width:calc(100% - 32px);border:0;border-radius:12px;padding:20px 22px;box-shadow:0 10px 40px rgba(0,0,0,.25);font-family:inherit}
dialog.envio::backdrop{background:rgba(0,0,0,.35)}
dialog.envio h3{margin:0 0 6px}
dialog.envio .ccaa{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:4px 12px;margin:12px 0}
dialog.envio label{font-size:14px;cursor:pointer}
dialog.envio label span{color:#888}
dialog.envio .total{font-weight:600}
dialog.envio .botones{display:flex;gap:10px;justify-content:flex-end;margin-top:14px}
dialog.envio button{font:inherit;padding:8px 14px;border-radius:8px;border:1px solid #ccc;background:#fff;cursor:pointer}
dialog.envio button.ok{background:#2e7d32;border-color:#2e7d32;color:#fff}
dialog.envio button:disabled{opacity:.5;cursor:default}
</style>
<script>
(function () {
  var D = window.DESTINATARIOS || {}, nombres = Object.keys(D), LIMITE = 7500, actual = null;
  var dlg = document.createElement('dialog'); dlg.className = 'envio'; document.body.appendChild(dlg);
  function marcadas() { return [].slice.call(dlg.querySelectorAll('.ccaa input:checked')).map(function (i) { return i.value; }); }
  function correos() {
    var vistos = {}, out = [];
    marcadas().forEach(function (n) { (D[n] || []).forEach(function (e) { if (!vistos[e]) { vistos[e] = 1; out.push(e); } }); });
    return out;
  }
  function contar() {
    var n = correos().length, t = dlg.querySelector('.total');
    t.textContent = n + (n === 1 ? ' destinatario' : ' destinatarios') + ' en copia oculta (CCO)' + (n > 490 ? ' · Gmail admite unos 500 por correo: divide el envío en dos.' : '');
    dlg.querySelector('[data-ok]').disabled = n === 0;
  }
  function abrir(det) {
    var h = '<h3>¿A qué comunidades lo envío?</h3><p class="orig">' + (det
      ? 'Corresponde a <strong>' + det + '</strong>. ¿Quieres enviarlo también a alguna comunidad más?'
      : 'Es de ámbito estatal: están todas marcadas. Desmarca las que no quieras.') + '</p><div class="ccaa">';
    nombres.forEach(function (n) {
      var on = det ? n === det : true;
      h += '<label><input type="checkbox" value="' + n + '"' + (on ? ' checked' : '') + '> ' + n + ' <span>(' + D[n].length + ')</span></label>';
    });
    h += '</div><p class="orig"><a href="#" data-todas>Marcar todas</a> · <a href="#" data-ninguna>Ninguna</a></p><p class="total"></p>' +
      '<div class="botones"><button type="button" data-cancel>Cancelar</button><button type="button" class="ok" data-ok>Abrir borrador en Gmail</button></div>';
    dlg.innerHTML = h; contar(); dlg.showModal();
  }
  function copiar(texto) {
    var t = document.createElement('textarea'); t.value = texto; document.body.appendChild(t); t.select();
    try { document.execCommand('copy'); } catch (e) {} document.body.removeChild(t);
  }
  function enviar() {
    var p = new URL(actual.href).searchParams, lista = correos();
    var base = 'https://mail.google.com/mail/?view=cm&fs=1&su=' + encodeURIComponent(p.get('su') || '') + '&body=' + encodeURIComponent(p.get('body') || '');
    var url = base + '&bcc=' + encodeURIComponent(lista.join(','));
    if (url.length > LIMITE) {
      copiar(lista.join(', '));
      alert('Son muchas direcciones para meterlas en el enlace de Gmail.\n\nLas he copiado: en el borrador, pulsa «CCO» y pega (Ctrl+V).');
      url = base;
    }
    dlg.close(); window.open(url, '_blank', 'noopener');
  }
  dlg.addEventListener('change', contar);
  dlg.addEventListener('click', function (e) {
    var t = e.target;
    if (t.hasAttribute('data-cancel')) dlg.close();
    else if (t.hasAttribute('data-ok')) enviar();
    else if (t.hasAttribute('data-todas') || t.hasAttribute('data-ninguna')) {
      e.preventDefault(); var v = t.hasAttribute('data-todas');
      [].forEach.call(dlg.querySelectorAll('.ccaa input'), function (i) { i.checked = v; }); contar();
    }
  });
  document.addEventListener('click', function (e) {
    var a = e.target.closest && e.target.closest('a.reenviar'); if (!a) return;
    e.preventDefault(); actual = a; abrir(a.getAttribute('data-ccaa') || '');
  });
})();
</script>
'@
try {
    $dest = Get-Destinatarios
    foreach ($a in $dest.avisos) { Write-Warning $a }
    $web = 'https://sio-aspm.github.io/boletin-aspm/'
    $local = (Pagina $web "${web}archivo.html")
    $aviso = '<div class="aviso-local"><strong>Copia local con los correos de las familias.</strong> Solo existe en este ordenador: no la compartas ni la subas. «Reenviar por correo» pone las direcciones en copia oculta según la comunidad autónoma.</div>'
    $local = $local.Replace('</header>', "</header>$aviso")
    $local = $local.Replace('</body>', "<script>window.DESTINATARIOS = $(ConvertTo-Json -InputObject $dest.ccaa -Depth 3 -Compress);</script>$scriptEnvio</body>")
    New-Item -ItemType Directory -Force $CarpetaLocal | Out-Null
    [IO.File]::WriteAllText((Join-Path $CarpetaLocal 'index.html'), $local, $utf8)
} catch {
    Write-Warning "No se pudo generar la copia local con destinatarios: $($_.Exception.Message)"
}

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
