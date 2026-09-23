# BOIB - Butlletí/Boletín Oficial de les Illes Balears
# Método: HTML (no hay API por fecha; el RSS https://www.caib.es/eboibfront/indexrss.do?lang=es solo
#   lista los ~14 últimos números, sin disposiciones).
#   1) Calendario anual https://www.caib.es/eboibfront/es/AAAA  -> enlaces
#      <a class="ordinario|extraordinario" href="/eboibfront/es/AAAA/<ID>/" title="BOIB ... del dia N">
#      agrupados por mes (table summary='Boletines Oficiales de <Mes> de AAAA'). Un día puede tener
#      ordinario + extraordinario(s).
#   2) Página del número https://www.caib.es/eboibfront/es/AAAA/<ID>/ -> enlaces a cada sección
#      (/eboibfront/es/AAAA/<ID>/seccion-.../<n>), y cada sección lista las disposiciones:
#      h2 = sección, h3 = subsección, h3.organisme = organismo (+<strong> órgano), ul.resolucions li p = título.
# Publica: ordinarios martes, jueves y sábado; extraordinarios cualquier día.

function Get-BoibHtml_ {
    param([string]$Url)
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36'
    $last = $null
    for ($i = 0; $i -lt 3; $i++) {
        try {
            $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -UserAgent $ua -TimeoutSec 60
            return [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
        } catch { $last = $_; Start-Sleep -Seconds 2 }
    }
    throw "BOIB: fallo al descargar $Url : $($last.Exception.Message)"
}

function ConvertFrom-BoibSeccion_ {
    param([string]$Html, [string]$Tipo)
    $clean = { param($s) [Net.WebUtility]::HtmlDecode(($s -replace '<[^>]+>', ' ' -replace '\s+', ' ')).Trim() }
    $ini = $Html.IndexOf('<h2>Secci')
    if ($ini -lt 0) { return @() }
    $fin = $Html.IndexOf('<!-- /columna central', $ini); if ($fin -lt 0) { $fin = $Html.Length }
    $body = $Html.Substring($ini, $fin - $ini)
    $pat = '(?s)<h2>(?<h2>.*?)</h2>|<h3>(?<h3>.*?)</h3>|<h3 class="organisme">(?<org>.*?)</h3>|<ul class="resolucions">(?<res>.*?)</ul>\s*</div>'
    $sec = ''; $sub = ''; $org = ''
    $out = @()
    foreach ($m in [regex]::Matches($body, $pat)) {
        if ($m.Groups['h2'].Success) { $sec = & $clean $m.Groups['h2'].Value; $sub = ''; $org = '' }
        elseif ($m.Groups['h3'].Success) { $sub = & $clean $m.Groups['h3'].Value; $org = '' }
        elseif ($m.Groups['org'].Success) {
            $o = $m.Groups['org'].Value -replace '<strong>', ' / ' -replace '</strong>', ''
            $org = & $clean $o
            $org = $org.Trim(' ', '/')
        } else {
            foreach ($it in [regex]::Matches($m.Groups['res'].Value, '(?s)<li>\s*<p>(?<tit>.*?)</p>(?<resto>.*?)(?=<li>\s*<p>|$)')) {
                $a = [regex]::Match($it.Groups['resto'].Value, 'aria-label="Exportar a HTML"[^>]*href="([^"]+)"')
                if (-not $a.Success) { $a = [regex]::Match($it.Groups['resto'].Value, 'href="([^"]+)"') }
                $u = [Net.WebUtility]::HtmlDecode($a.Groups[1].Value)
                if ($u.StartsWith('/')) { $u = 'https://www.caib.es' + $u }
                $s = $sec; if ($sub) { $s = "$sec / $sub" }
                if ($Tipo -eq 'extraordinario') { $s = "[Extraordinario] $s" }
                $out += [pscustomobject]@{
                    boletin = 'BOIB'; ambito = 'Illes Balears'
                    titulo = & $clean $it.Groups['tit'].Value
                    departamento = $org; seccion = $s; url = $u
                }
            }
        }
    }
    return $out
}

function Get-Disposiciones_boib {
    param([Parameter(Mandatory = $true)][datetime]$Fecha)
    [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
    $meses = @('Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre')
    $anio = $Fecha.Year
    $cal = Get-BoibHtml_ "https://www.caib.es/eboibfront/es/$anio"
    $mesTxt = $meses[$Fecha.Month - 1]
    $ini = $cal.IndexOf("summary='Boletines Oficiales de $mesTxt de $anio'")
    if ($ini -lt 0) { throw "BOIB: calendario anual $anio sin el mes $mesTxt (estructura cambiada?)" }
    $fin = $cal.IndexOf('</table>', $ini)
    $tabla = $cal.Substring($ini, $fin - $ini)
    $nums = @()
    foreach ($m in [regex]::Matches($tabla, '<a class="(?<tipo>\w+)" href="(?<href>/eboibfront/es/\d{4}/(?<id>\d+)/)" title="[^"]*del dia (?<dia>\d+)"')) {
        if ([int]$m.Groups['dia'].Value -eq $Fecha.Day) {
            $nums += [pscustomobject]@{ id = $m.Groups['id'].Value; tipo = $m.Groups['tipo'].Value; url = 'https://www.caib.es' + $m.Groups['href'].Value }
        }
    }
    if ($nums.Count -eq 0) { return @() }

    $out = @()
    foreach ($n in $nums) {
        $idx = Get-BoibHtml_ $n.url
        $secs = @([regex]::Matches($idx, 'href="(/eboibfront/es/\d{4}/' + $n.id + '/seccion-[^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
        if ($secs.Count -eq 0) { $out += ConvertFrom-BoibSeccion_ $idx $n.tipo; continue }
        foreach ($s in $secs) {
            $out += ConvertFrom-BoibSeccion_ (Get-BoibHtml_ ('https://www.caib.es' + $s)) $n.tipo
        }
    }
    return $out
}
