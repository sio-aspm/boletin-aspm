# DOE - Diario Oficial de Extremadura
# Fuente: sumario HTML por fecha (el RSS solo cubre los ultimos diarios, no un dia concreto).
#   Ordinario:      https://doe.juntaex.es/ultimosdoe/mostrardoe.php?fecha=AAAAMMDD&t=o
#   Extraordinario: https://doe.juntaex.es/ultimosdoe/mostrardoe.php?fecha=AAAAMMDD&t=e
# Codificacion: ISO-8859-1/Windows-1252 (NO UTF-8). Dia sin diario -> "D.O.E. No encontrado".
# Publica de lunes a viernes laborables (no el 8 de septiembre, Dia de Extremadura, ni festivos).

function Get-Disposiciones_doe {
    param([Parameter(Mandatory)][datetime]$Fecha)

    [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36'
    $enc = [Text.Encoding]::GetEncoding(1252)
    $ymd = $Fecha.ToString('yyyyMMdd')

    $clean = { param($s) ([Net.WebUtility]::HtmlDecode(($s -replace '<[^>]+>', ' ')) -replace '\s+', ' ').Trim() }
    $rx = '<div class="justificado">([\s\S]*?)</div>|<span class="d\d">([^<]+)</span>|<span class="DOE6">([^<]+)</span>|<p><span class="DOE2">([^<]+)</span></p>'

    $out = New-Object System.Collections.ArrayList
    $hayDiario = $false
    foreach ($tipo in 'o', 'e') {
        $u = "https://doe.juntaex.es/ultimosdoe/mostrardoe.php?fecha=$ymd&t=$tipo"
        try { $r = Invoke-WebRequest -Uri $u -UseBasicParsing -UserAgent $ua -TimeoutSec 60 }
        catch { throw "DOE: fallo al descargar $u : $($_.Exception.Message)" }
        $html = $enc.GetString($r.RawContentStream.ToArray())
        if ($html -match 'D\.O\.E\. No encontrado') { continue }
        $ini = $html.IndexOf('class="Contenido_DOE"')
        if ($ini -lt 0) { throw "DOE: estructura HTML inesperada en $u" }
        $hayDiario = $true
        $body = $html.Substring($ini)
        $sec = ''; $sub = ''; $dep = ''
        foreach ($m in [regex]::Matches($body, $rx)) {
            if ($m.Groups[2].Success) { $sec = & $clean $m.Groups[2].Value; $sub = ''; $dep = '' }
            elseif ($m.Groups[3].Success) { $sub = & $clean $m.Groups[3].Value; $dep = '' }
            elseif ($m.Groups[4].Success) { $dep = & $clean $m.Groups[4].Value }
            else {
                $raw = $m.Groups[1].Value
                $mt = [regex]::Match($raw, '<span class="DOE4">([\s\S]*?)</span>')
                if (-not $mt.Success) { continue }
                $materia = [regex]::Match($raw, '<span class="DOE2">([\s\S]*?)</span>')
                $tit = & $clean $mt.Groups[1].Value
                if ($materia.Success) { $tit = ((& $clean $materia.Groups[1].Value) + ' ' + $tit).Trim() }
                $mp = [regex]::Match($raw, 'href="(/pdfs/[^"]+\.pdf)"')
                $url = $null
                if ($mp.Success) { $url = 'https://doe.juntaex.es' + $mp.Groups[1].Value }
                $s = $sec
                if ($sub) { $s = "$sec - $sub" }
                if ($tipo -eq 'e') { $s = "EXTRAORDINARIO - $s" }
                [void]$out.Add([pscustomobject]@{
                    boletin      = 'DOE'
                    ambito       = 'Extremadura'
                    titulo       = $tit
                    departamento = $dep
                    seccion      = $s
                    url          = $url
                })
            }
        }
    }
    if (-not $hayDiario) { return @() }
    if ($out.Count -eq 0) { throw "DOE: diario del $($Fecha.ToString('yyyy-MM-dd')) descargado pero sin disposiciones reconocibles" }
    return $out.ToArray()
}
