# DOCM - Diario Oficial de Castilla-La Mancha
# Fuente: sumario HTML por fecha (no hay XML/JSON diario publico estable).
#   https://docm.jccm.es/docm/cambiarBoletin.do?fecha=AAAAMMDD
# Publica de lunes a viernes (laborables). La misma pagina trae un calendario del mes: las
# celdas 'noTieneDogv' son dias sin diario, y los enlaces del dia permiten detectar numeros
# extraordinarios (se leen todos).

function Get-Disposiciones_docm {
    param([Parameter(Mandatory)][datetime]$Fecha)

    [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36'
    $base = 'https://docm.jccm.es/docm/'
    $ymd = $Fecha.ToString('yyyyMMdd')

    $fetch = {
        param($u)
        try { $r = Invoke-WebRequest -Uri $u -UseBasicParsing -UserAgent $ua -TimeoutSec 60 }
        catch { throw "DOCM: fallo al descargar $u : $($_.Exception.Message)" }
        [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
    }
    $clean = { param($s) ([Net.WebUtility]::HtmlDecode(($s -replace '<[^>]+>', ' ')) -replace '\s+', ' ' -replace ' ([,.;:])', '$1').Trim() }

    $html = & $fetch ($base + 'cambiarBoletin.do?fecha=' + $ymd)

    # Enlaces del calendario para este dia (ordinario y posibles extraordinarios)
    $urls = New-Object System.Collections.ArrayList
    foreach ($m in [regex]::Matches($html, 'href="(/docm/cambiarBoletin\.do\?fecha=' + $ymd + '[^"]*)"')) {
        $u = 'https://docm.jccm.es' + [Net.WebUtility]::HtmlDecode($m.Groups[1].Value)
        if (-not $urls.Contains($u)) { [void]$urls.Add($u) }
    }

    if ($html -notmatch 'class = "fechaDiario"') {
        $dia = $Fecha.Day.ToString()
        if ($urls.Count -eq 0 -and $html -match ("class='noTieneDogv'>\s*" + $dia + '\s*<')) { return @() }
        if ($urls.Count -eq 0 -and $Fecha.Date -ge (Get-Date).Date) { return @() }
        throw "DOCM: no se pudo obtener el diario del $($Fecha.ToString('yyyy-MM-dd'))"
    }

    $pages = New-Object System.Collections.ArrayList
    [void]$pages.Add($html)
    $plain = 'https://docm.jccm.es/docm/cambiarBoletin.do?fecha=' + $ymd
    foreach ($u in $urls) { if ($u -ne $plain) { [void]$pages.Add((& $fetch $u)) } }

    $rx = '<h3 class = "cabeceraCategoria">([\s\S]*?)</h3>|<li>([^<]+)<div|<h4 class = "tituloOrganismo">([\s\S]*?)</h4>|<p class = "sumario">([\s\S]*?)</p>'
    $out = New-Object System.Collections.ArrayList
    $vistos = @{}
    foreach ($p in $pages) {
        $ini = $p.IndexOf('id = "contenido"')
        if ($ini -lt 0) { $ini = 0 }
        $body = [regex]::Replace($p.Substring($ini), '<script[\s\S]*?</script>', '')
        $sec = ''; $sub = ''; $dep = ''
        foreach ($m in [regex]::Matches($body, $rx)) {
            if ($m.Groups[1].Success) { $sec = & $clean $m.Groups[1].Value; $sub = ''; $dep = '' }
            elseif ($m.Groups[2].Success) { $sub = & $clean $m.Groups[2].Value; $dep = '' }
            elseif ($m.Groups[3].Success) { $dep = & $clean $m.Groups[3].Value }
            else {
                $raw = $m.Groups[4].Value
                $mh = [regex]::Match($raw, 'href="\./([^"]+)"')
                $url = $null
                if ($mh.Success) { $url = $base + [Net.WebUtility]::HtmlDecode($mh.Groups[1].Value) }
                if ($url -and $vistos.ContainsKey($url)) { continue }
                if ($url) { $vistos[$url] = 1 }
                $tit = (& $clean $raw) -replace '\s*\[NID [^\]]+\]\s*$', ''
                $s = $sec
                if ($sub) { $s = "$sec - $sub" }
                [void]$out.Add([pscustomobject]@{
                    boletin      = 'DOCM'
                    ambito       = 'Castilla-La Mancha'
                    titulo       = $tit
                    departamento = $dep
                    seccion      = $s
                    url          = $url
                })
            }
        }
    }
    if ($out.Count -eq 0) { throw 'DOCM: diario descargado pero sin disposiciones reconocibles (cambio de estructura?)' }
    return $out.ToArray()
}
