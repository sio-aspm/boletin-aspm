# BOCYL - Boletin Oficial de Castilla y Leon
# Fuente: sumario HTML por fecha (no hay XML/JSON diario; el RSS solo da el ultimo boletin).
#   https://bocyl.jcyl.es/boletin.do?fechaBoletin=DD/MM/AAAA
# Publica de lunes a viernes. Los dias sin boletin devuelven una pagina de error generica
# ("La pagina no esta disponible"); para distinguirlo de un fallo real se consulta el boletin
# anterior y su enlace "Siguiente".

function Get-Disposiciones_bocyl {
    param([Parameter(Mandatory)][datetime]$Fecha)

    [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36'

    $fetch = {
        param($f)
        $u = 'https://bocyl.jcyl.es/boletin.do?fechaBoletin=' + $f.ToString('dd/MM/yyyy')
        try { $r = Invoke-WebRequest -Uri $u -UseBasicParsing -UserAgent $ua -TimeoutSec 60 }
        catch { throw "BOCYL: fallo al descargar $u : $($_.Exception.Message)" }
        [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
    }
    $clean = { param($s) ([Net.WebUtility]::HtmlDecode(($s -replace '<[^>]+>', ' ')) -replace '\s+', ' ').Trim() }

    $html = & $fetch $Fecha
    # El boletin mas reciente se titula "ULTIMO BOLETIN PUBLICADO": se acepta si trae disposiciones de esa fecha
    $esUltimo = ($html -match '<title>\s*ULTIMO BOLET') -and $html.Contains('BOCYL-D-' + $Fecha.ToString('ddMMyyyy'))
    if (($html -notmatch '<title>\s*SUMARIO DEL BOLET') -and -not $esUltimo) {
        # Posible dia sin boletin: buscar el boletin anterior y mirar su "Siguiente"
        for ($i = 1; $i -le 10; $i++) {
            $prev = & $fetch ($Fecha.AddDays(-$i))
            if ($prev -match '<title>\s*SUMARIO DEL BOLET') {
                $m = [regex]::Match($prev, 'class="siguiente" href="boletin\.do\?fechaBoletin=(\d\d/\d\d/\d{4})"')
                if ($m.Success) {
                    $sig = [datetime]::ParseExact($m.Groups[1].Value, 'dd/MM/yyyy', $null)
                    if ($sig -gt $Fecha.Date) { return @() }
                }
                elseif ($Fecha.Date -ge (Get-Date).Date) { return @() }  # aun no publicado
                break
            }
        }
        throw "BOCYL: no se pudo obtener el sumario del $($Fecha.ToString('yyyy-MM-dd')) (pagina de error del servidor)"
    }

    $ini = $html.IndexOf('<div id="resultados">')
    if ($ini -lt 0) { throw 'BOCYL: estructura HTML inesperada (no hay div#resultados)' }
    $body = $html.Substring($ini)
    $body = [regex]::Replace($body, '<!--[\s\S]*?-->', '')

    $rx = '<h3[^>]*>([\s\S]*?)</h3>|<h4[^>]*>([\s\S]*?)</h4>|<h5[^>]*>([\s\S]*?)</h5>|<p>([\s\S]*?)</p>\s*<ul class="descargaBoletin">([\s\S]*?)</ul>'
    $h3 = ''; $h4 = ''; $dep = ''
    $out = New-Object System.Collections.ArrayList
    foreach ($m in [regex]::Matches($body, $rx)) {
        if ($m.Groups[1].Success) { $h3 = & $clean $m.Groups[1].Value; $h4 = ''; $dep = '' }
        elseif ($m.Groups[2].Success) { $h4 = & $clean $m.Groups[2].Value; $dep = '' }
        elseif ($m.Groups[3].Success) { $dep = & $clean $m.Groups[3].Value }
        else {
            $links = $m.Groups[5].Value
            $url = $null
            $mh = [regex]::Match($links, "href='(html/[^']+\.do)'")
            if ($mh.Success) { $url = 'https://bocyl.jcyl.es/' + $mh.Groups[1].Value }
            else {
                $mp = [regex]::Match($links, "href='([^']+\.pdf)'")
                if ($mp.Success) { $url = $mp.Groups[1].Value }
            }
            $sec = $h3
            if ($h4) { $sec = "$h3 - $h4" }
            [void]$out.Add([pscustomobject]@{
                boletin      = 'BOCYL'
                ambito       = 'Castilla y León'
                titulo       = & $clean $m.Groups[4].Value
                departamento = $dep
                seccion      = $sec
                url          = $url
            })
        }
    }
    if ($out.Count -eq 0) { throw 'BOCYL: sumario descargado pero no se encontraron disposiciones (cambio de estructura?)' }
    return $out.ToArray()
}
