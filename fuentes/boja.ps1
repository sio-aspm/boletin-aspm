# BOJA - Boletín Oficial de la Junta de Andalucía
# Método: 1) Atom "Boletín completo" (https://www.juntadeandalucia.es/boja/distribucion/boja.xml),
#            que trae los últimos ~3 días (ordinarios + extraordinarios/complementarios) con
#            sección, consejería, título y enlace. Es la vía rápida para el uso diario.
#         2) Si la fecha ya no está en el feed: se localiza el nº de boletín ordinario por
#            estimación (días laborables desde el último del feed) comprobando la fecha del <h1>
#            de https://www.juntadeandalucia.es/boja/AAAA/N/ y se parsea el sumario HTML
#            (más complementarios /AAAA/N/c01/, c02...).
# Publica: lunes a viernes (no sábados/domingos ni festivos).

function Get-BojaHtml_ {
    param([string]$Url)
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36'
    $last = $null
    for ($i = 0; $i -lt 3; $i++) {
        try {
            $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -UserAgent $ua -TimeoutSec 60
            return [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
        } catch {
            $last = $_
            $resp = $_.Exception.Response
            if ($resp -ne $null -and [int]$resp.StatusCode -eq 404) { return $null }
            Start-Sleep -Seconds 2
        }
    }
    throw "BOJA: fallo al descargar $Url : $($last.Exception.Message)"
}

function ConvertFrom-BojaSumarioHtml_ {
    param([string]$Html, [string]$BaseUrl)
    $out = @()
    $ini = $Html.IndexOf('start content-main-summary')
    $fin = $Html.IndexOf('end content-main-summary')
    if ($ini -lt 0 -or $fin -lt $ini) { throw "BOJA: estructura de sumario no reconocida en $BaseUrl" }
    $body = $Html.Substring($ini, $fin - $ini)
    $pat = '(?s)<h2>(?<h2>.*?)</h2>|<h3>(?<h3>.*?)</h3>|<p class="h5[^"]*">(?<dep>.*?)</p>|<div class="item[^"]*">\s*<p>(?<tit>.*?)</p>.*?href="(?<url>/boja/[^"]+)"\s+class="item_html"'
    $sec = ''; $sub = ''; $dep = ''
    foreach ($m in [regex]::Matches($body, $pat)) {
        if ($m.Groups['h2'].Success) { $sec = [Net.WebUtility]::HtmlDecode(($m.Groups['h2'].Value -replace '<[^>]+>', '').Trim()); $sub = ''; $dep = '' }
        elseif ($m.Groups['h3'].Success) { $sub = [Net.WebUtility]::HtmlDecode(($m.Groups['h3'].Value -replace '<[^>]+>', '').Trim()); $dep = '' }
        elseif ($m.Groups['dep'].Success) { $dep = [Net.WebUtility]::HtmlDecode(($m.Groups['dep'].Value -replace '<[^>]+>', '').Trim()) }
        else {
            $s = $sec; if ($sub) { $s = "$sec / $sub" }
            $out += [pscustomobject]@{
                boletin = 'BOJA'; ambito = 'Andalucía'
                titulo = [Net.WebUtility]::HtmlDecode(($m.Groups['tit'].Value -replace '<[^>]+>', '' -replace '\s+', ' ').Trim())
                departamento = $dep; seccion = $s
                url = 'https://www.juntadeandalucia.es' + $m.Groups['url'].Value
            }
        }
    }
    return $out
}

function ConvertFrom-BojaBoletin_ {
    # La página índice de un boletín solo muestra la 1ª sección; el resto está en /sNN (menú lateral)
    param([string]$Html, [string]$BaseUrl)
    $out = @(ConvertFrom-BojaSumarioHtml_ $Html $BaseUrl)
    $ini = $Html.IndexOf('listado_ordenado_boja raiz')
    if ($ini -lt 0) { return $out }
    $menu = $Html.Substring($ini, [Math]::Min($Html.Length, $Html.IndexOf('listado_pdf', $ini) + 1) - $ini)
    foreach ($m in [regex]::Matches($menu, '<li data-level="[^"]*"(?<act> class="actual")?>\s*<a href="(?<s>s\d+)"')) {
        if ($m.Groups['act'].Success) { continue }
        $u = $BaseUrl + $m.Groups['s'].Value
        $h = Get-BojaHtml_ $u
        if ($h) { $out += ConvertFrom-BojaSumarioHtml_ $h $u }
    }
    return $out
}

function Get-BojaFechaH1_ {
    param([string]$Html)
    $m = [regex]::Match($Html, '(?s)<span class="nota">.*?(\d{2}/\d{2}/\d{4})')
    if (-not $m.Success) { return $null }
    return [datetime]::ParseExact($m.Groups[1].Value, 'dd/MM/yyyy', $null)
}

function Get-BojaLaborables_ {
    param([datetime]$A, [datetime]$B)  # nº de días L-V en (A, B], con signo
    $sign = 1; if ($B -lt $A) { $t = $A; $A = $B; $B = $t; $sign = -1 }
    $n = 0; $d = $A.AddDays(1)
    while ($d -le $B) { if ($d.DayOfWeek -ne 'Saturday' -and $d.DayOfWeek -ne 'Sunday') { $n++ }; $d = $d.AddDays(1) }
    return $n * $sign
}

function Get-Disposiciones_boja {
    param([Parameter(Mandatory = $true)][datetime]$Fecha)
    [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
    $Fecha = $Fecha.Date
    if ($Fecha.DayOfWeek -eq 'Saturday' -or $Fecha.DayOfWeek -eq 'Sunday') { return @() }

    # --- 1) Feed Atom ---
    $xmlTxt = Get-BojaHtml_ 'https://www.juntadeandalucia.es/boja/distribucion/boja.xml'
    if (-not $xmlTxt) { throw 'BOJA: feed Atom no disponible (404)' }
    $x = [xml]$xmlTxt
    $entries = @($x.feed.entry)
    $fechasFeed = @($entries | ForEach-Object { ([datetime]$_.updated.Substring(0, 10)).Date })
    $minFeed = ($fechasFeed | Measure-Object -Minimum).Minimum
    if ($Fecha -ge $minFeed) {
        $out = @()
        foreach ($e in $entries) {
            if (([datetime]$e.updated.Substring(0, 10)).Date -ne $Fecha) { continue }
            $sec = ''; $sub = ''; $dep = ''
            foreach ($n in $e.content.div.ChildNodes) {
                if ($n.LocalName -eq 'p') {
                    $t = ($n.InnerText -replace '\s+', ' ').Trim()
                    if (-not $t) { continue }
                    if ($n.SelectSingleNode('*[local-name()="strong"]') -ne $null -or $t -match '^\d+(\.\d+)*\.\s') {
                        if ($t -match '^\d+\.\d+') { $sub = $t } else { $sec = $t; $sub = '' }
                        $dep = ''
                    } else { $dep = $t }
                } elseif ($n.LocalName -eq 'ul') {
                    foreach ($li in $n.ChildNodes) {
                        if ($li.LocalName -ne 'li') { continue }
                        $a = $li.SelectSingleNode('*[local-name()="a"]')
                        if ($a -eq $null) { continue }
                        $s = $sec; if ($sub) { $s = "$sec / $sub" }
                        $out += [pscustomobject]@{
                            boletin = 'BOJA'; ambito = 'Andalucía'
                            titulo = ($a.InnerText -replace '\s+', ' ').Trim()
                            departamento = $dep; seccion = $s
                            url = ($a.GetAttribute('href') -replace '^http:', 'https:')
                        }
                    }
                }
            }
        }
        return $out
    }

    # --- 2) Histórico: localizar nº de boletín ordinario ---
    $ultimo = $entries | Where-Object { $_.title -notmatch 'Extraordinario' } | Select-Object -First 1
    $numUlt = [int]([regex]::Match($ultimo.link.href, '/boja/\d{4}/(\d+)/').Groups[1].Value)
    $fecUlt = ([datetime]$ultimo.updated.Substring(0, 10)).Date
    if ($Fecha.Year -ne $fecUlt.Year) {
        throw "BOJA: fecha de otro año; búsqueda automática no soportada. Consulta https://www.juntadeandalucia.es/boja/$($Fecha.Year)/"
    }
    $cand = $numUlt - (Get-BojaLaborables_ $Fecha $fecUlt)
    $visto = @{}
    for ($k = 0; $k -lt 12; $k++) {
        if ($cand -lt 1) { $cand = 1 }
        if ($visto.ContainsKey($cand)) { break }
        $html = Get-BojaHtml_ "https://www.juntadeandalucia.es/boja/$($Fecha.Year)/$cand/"
        if (-not $html) { $visto[$cand] = $null; $cand--; continue }
        $f = Get-BojaFechaH1_ $html
        $visto[$cand] = $f
        if ($f -eq $Fecha) {
            $base = "https://www.juntadeandalucia.es/boja/$($Fecha.Year)/$cand/"
            $out = @(ConvertFrom-BojaBoletin_ $html $base)
            for ($c = 1; $c -le 9; $c++) {
                $cu = $base + ('c{0:00}/' -f $c)
                $ch = Get-BojaHtml_ $cu
                if (-not $ch) { break }
                $out += ConvertFrom-BojaBoletin_ $ch $cu
            }
            return $out
        }
        $diff = Get-BojaLaborables_ $f $Fecha
        if ($diff -eq 0) { $diff = [Math]::Sign(($Fecha - $f).Days) }
        $next = $cand + $diff
        # Si oscilamos entre dos números consecutivos, ese día no hubo boletín ordinario
        if ($visto.ContainsKey($next) -and $visto[$next] -ne $null) {
            if (($visto[$next] -lt $Fecha -and $f -gt $Fecha) -or ($visto[$next] -gt $Fecha -and $f -lt $Fecha)) { return @() }
        }
        $cand = $next
    }
    throw "BOJA: no se pudo localizar el boletín del $($Fecha.ToString('yyyy-MM-dd'))"
}
