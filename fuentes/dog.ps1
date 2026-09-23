# DOG - Diario Oficial de Galicia (version en castellano, sufijo _es)
# Fuente:
#   1) Calendario JSON: POST https://www.xunta.gal/diario-oficial-galicia/portalPublicoHome.do?method=getDiasDog
#      (mes, ano, idioma=es) -> dias con DOG publicado
#   2) Fragmentos HTML estaticos del sumario, uno por seccion con contenido:
#      https://www.xunta.gal/dog/Publicados/AAAA/AAAAMMDD/Secciones{N}_es.html  (N=1,2,3... hasta 404)
# Publica de lunes a viernes laborables. Para gallego cambiar _es por _gl.
# Limitacion: no se ha podido verificar el formato de los DOG "bis" (no hubo ninguno en las fechas probadas).

function Get-Disposiciones_dog {
    param([Parameter(Mandatory)][datetime]$Fecha)

    [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36'
    $clean = { param($s) ([Net.WebUtility]::HtmlDecode(($s -replace '<[^>]+>', ' ')) -replace '\s+', ' ').Trim() }

    # 1) Calendario
    try {
        $r = Invoke-WebRequest -Uri 'https://www.xunta.gal/diario-oficial-galicia/portalPublicoHome.do?method=getDiasDog' -Method Post `
            -Body @{ mes = $Fecha.Month.ToString(); ano = $Fecha.Year.ToString(); idioma = 'es' } -UseBasicParsing -UserAgent $ua -TimeoutSec 60
        $cal = [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray()) | ConvertFrom-Json
    }
    catch { throw "DOG: fallo al consultar el calendario: $($_.Exception.Message)" }
    $clave = $Fecha.ToString('dd/MM/yyyy')
    $publicado = $false
    foreach ($c in $cal) { if ($c.fecha -eq $clave) { $publicado = $true } }
    if (-not $publicado) { return @() }

    # 2) Secciones
    $base = 'https://www.xunta.gal/dog/Publicados/' + $Fecha.ToString('yyyy') + '/' + $Fecha.ToString('yyyyMMdd') + '/'
    $rx = '<p class="dog-toc-nivel-1">([\s\S]*?)</p>|<p class="dog-toc-nivel-2">([\s\S]*?)</p>|<p class="dog-toc-organismo">([\s\S]*?)</p>|<li class="dog-toc-sumario">\s*<a href="([^"]+)"[^>]*>([\s\S]*?)</a>'
    $out = New-Object System.Collections.ArrayList
    for ($n = 1; $n -le 12; $n++) {
        $u = $base + "Secciones${n}_es.html"
        $html = $null
        try {
            $r = Invoke-WebRequest -Uri $u -UseBasicParsing -UserAgent $ua -TimeoutSec 60
            $html = [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
        }
        catch {
            $code = 0
            if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
            if ($code -eq 404) { break }
            throw "DOG: fallo al descargar $u : $($_.Exception.Message)"
        }
        $n1 = ''; $n2 = ''; $dep = ''
        foreach ($m in [regex]::Matches($html, $rx)) {
            if ($m.Groups[1].Success) { $n1 = & $clean $m.Groups[1].Value; $n2 = ''; $dep = '' }
            elseif ($m.Groups[2].Success) { $n2 = & $clean $m.Groups[2].Value; $dep = '' }
            elseif ($m.Groups[3].Success) { $dep = & $clean $m.Groups[3].Value }
            else {
                $href = $m.Groups[4].Value
                if ($href -notmatch '^https?:') { $href = 'https://www.xunta.gal' + $href }
                $s = $n1
                if ($n2) { $s = "$n1 - $n2" }
                [void]$out.Add([pscustomobject]@{
                    boletin      = 'DOG'
                    ambito       = 'Galicia'
                    titulo       = & $clean $m.Groups[5].Value
                    departamento = $dep
                    seccion      = $s
                    url          = $href
                })
            }
        }
    }
    if ($out.Count -eq 0) { throw "DOG: el calendario marca DOG el $clave pero no se encontraron secciones/disposiciones en $base" }
    return $out.ToArray()
}
