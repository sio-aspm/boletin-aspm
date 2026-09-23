# BOPA - Boletín Oficial del Principado de Asturias
# Método: HTML del sumario por fecha (portal Liferay "miprincipado"), no hay API/RSS por fecha utilizable:
#   https://miprincipado.asturias.es/bopa/ultimos-boletines?p_r_p_summaryDate=DD%2FMM%2FAAAA
# Estructura: <div id="bopa-boletin"> h4 = sección (I. Principado de Asturias, IV. Administración Local...),
#   h5 = subsección, h6 = consejería/entidad, p.subAuthor = organismo dependiente, dl/dt = título,
#   dd/a = enlace a la disposición.
# OJO: si la fecha pedida no tiene boletín, el portal muestra el ÚLTIMO boletín publicado. Por eso se
#   comprueba la fecha real con el enlace al PDF del sumario /bopa/AAAA/MM/DD/AAAAMMDD.pdf.
# Publica: lunes a viernes.

function Get-Disposiciones_bopa {
    param([Parameter(Mandatory = $true)][datetime]$Fecha)
    [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36'
    $fDMY = $Fecha.ToString('dd/MM/yyyy', [Globalization.CultureInfo]::InvariantCulture)
    $url = 'https://miprincipado.asturias.es/bopa/ultimos-boletines?p_r_p_summaryDate=' + [uri]::EscapeDataString($fDMY)
    $html = $null; $err = $null
    for ($i = 0; $i -lt 3 -and $html -eq $null; $i++) {
        try {
            $r = Invoke-WebRequest -Uri $url -UseBasicParsing -UserAgent $ua -TimeoutSec 90
            $html = [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
        } catch { $err = $_; Start-Sleep -Seconds 2 }
    }
    if ($html -eq $null) { throw "BOPA: fallo al descargar el sumario: $($err.Exception.Message)" }

    $ini = $html.IndexOf('<div id="bopa-boletin">')
    if ($ini -lt 0) {
        if ($html -match 'SedeBopaSummaryWeb') { return @() }  # portal OK pero sin sumario
        throw 'BOPA: estructura de página no reconocida'
    }
    # Fecha real del boletín mostrado
    # (el input oculto p_r_p_dispositionDate solo repite la fecha pedida: no sirve para verificar)
    $m = [regex]::Match($html, 'href="/bopa/(\d{4})/(\d{2})/(\d{2})/\d{8}\.pdf"')
    if (-not $m.Success) { throw 'BOPA: no se pudo verificar la fecha del boletín mostrado (falta el PDF del sumario)' }
    $real = '{0}-{1}-{2}' -f $m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value
    if ($real -ne $Fecha.ToString('yyyy-MM-dd')) { return @() }

    $fin = $html.IndexOf('<hr class="gpa-divider', $ini)
    if ($fin -lt 0) { $fin = $html.Length }
    $body = $html.Substring($ini, $fin - $ini)
    $pat = '(?s)<h4[^>]*>(?<h4>.*?)</h4>|<h5[^>]*>(?<h5>.*?)</h5>|<h6[^>]*>(?<h6>.*?)</h6>|<p[^>]*class="subAuthor"[^>]*>(?<sa>.*?)</p>|<dt>(?<dt>.*?)</dt>\s*<dd>(?<dd>.*?)</dd>'
    $clean = { param($s) [Net.WebUtility]::HtmlDecode(($s -replace '<[^>]+>', ' ' -replace '\s+', ' ')).Trim() }
    $h4 = ''; $h5 = ''; $h6 = ''; $sa = ''
    $out = @()
    foreach ($x in [regex]::Matches($body, $pat)) {
        if ($x.Groups['h4'].Success) { $h4 = & $clean $x.Groups['h4'].Value; $h5 = ''; $h6 = ''; $sa = '' }
        elseif ($x.Groups['h5'].Success) { $h5 = & $clean $x.Groups['h5'].Value; $h6 = ''; $sa = '' }
        elseif ($x.Groups['h6'].Success) { $h6 = & $clean $x.Groups['h6'].Value; $sa = '' }
        elseif ($x.Groups['sa'].Success) { $sa = & $clean $x.Groups['sa'].Value }
        else {
            # quita la marca final "[Cód. 2026-07517]"
            $tit = & $clean ($x.Groups['dt'].Value -replace '(?s)<strong>\s*\[C[^\]]*\]\s*</strong>', '')
            $a = [regex]::Match($x.Groups['dd'].Value, 'href="([^"]*disposition[^"]*)"')
            if (-not $a.Success) { $a = [regex]::Match($x.Groups['dd'].Value, 'href="([^"]+)"') }
            $link = [Net.WebUtility]::HtmlDecode($a.Groups[1].Value)
            if ($link.StartsWith('/')) { $link = 'https://miprincipado.asturias.es' + $link }
            if ($h6) {
                $dep = $h6
                if ($h6 -match '^DE ') { $dep = "$h5 $h6" }
                if ($sa) { $dep = "$dep / $sa" }
            } else { $dep = $h5 }
            $sec = $h4; if ($h5 -and $h6) { $sec = "$h4 / $h5" }
            $out += [pscustomobject]@{
                boletin = 'BOPA'; ambito = 'Principado de Asturias'
                titulo = $tit; departamento = $dep; seccion = $sec; url = $link
            }
        }
    }
    return $out
}
