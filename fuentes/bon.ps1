# BON - Boletin Oficial de Navarra
# Metodo: scraping HTML (no hay API/XML de sumario). Dos pasos:
#   1) Indice mensual -> numeros de boletin de ese dia (puede haber varios: ordinario + EXTRAORDINARIO)
#      https://bon.navarra.es/es/boletines/-/boletinmes/AAAA/M
#   2) Sumario de cada numero:
#      https://bon.navarra.es/es/boletin/-/sumario/AAAA/NNN
# Enlace a cada anuncio: https://bon.navarra.es/es/anuncio/-/texto/AAAA/NNN/K
# Publica de lunes a viernes (laborables). HTML UTF-8. Compatible con Windows PowerShell 5.1.

function Get-Disposiciones_bon {
    param([Parameter(Mandatory = $true)][datetime]$Fecha)

    [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36'
    $f = $Fecha.Date

    function _get([string]$u) {
        $r = Invoke-WebRequest -Uri $u -UseBasicParsing -UserAgent $ua -TimeoutSec 120
        return [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
    }
    function _clean([string]$s) {
        $s = $s -replace '<br\s*/?>', ' - '
        $s = $s -replace '<[^>]+>', ' '
        $s = [System.Net.WebUtility]::HtmlDecode($s)
        return (($s -replace '\s+', ' ').Trim())
    }

    # 1) Numeros de boletin del dia
    $uMes = 'https://bon.navarra.es/es/boletines/-/boletinmes/{0}/{1}' -f $f.Year, $f.Month
    try { $hMes = _get $uMes } catch { throw "BON: no se pudo leer el indice mensual $uMes : $($_.Exception.Message)" }
    $ms = [regex]::Matches($hMes, 'href="https://bon\.navarra\.es/es/boletin/-/sumario/(\d{4})/(\d+)"\s+title="N\S*\s*(\d+)\s*\|\s*(\d{1,2}) de ')
    if ($ms.Count -eq 0 -and $hMes -notmatch 'No se han encontrado') {
        throw "BON: el indice mensual no contiene boletines reconocibles (formato cambiado?) $uMes"
    }
    $nums = @()
    foreach ($m in $ms) {
        if ([int]$m.Groups[4].Value -eq $f.Day -and [int]$m.Groups[1].Value -eq $f.Year) { $nums += [int]$m.Groups[2].Value }
    }
    $nums = @($nums | Sort-Object -Unique)
    if ($nums.Count -eq 0) { return , @() }   # no hubo boletin ese dia

    $out = New-Object System.Collections.Generic.List[object]
    foreach ($num in $nums) {
        $uSum = 'https://bon.navarra.es/es/boletin/-/sumario/{0}/{1}' -f $f.Year, $num
        try { $h = _get $uSum } catch { throw "BON: no se pudo leer el sumario $uSum : $($_.Exception.Message)" }
        $i = $h.IndexOf('b-sumario')
        if ($i -lt 0) { throw "BON: sumario sin bloque 'b-sumario' (formato cambiado?) $uSum" }
        $body = $h.Substring($i)
        $esExtra = ($hMes -match ('sumario/{0}/{1}"[^>]*>[^<]*<br\s*/?>\s*EXTRAORDINARIO' -f $f.Year, $num))

        $amb = ''; $sec = ''; $sub = ''; $den = ''
        $rx = '<p class="hd r-hn\d b-(ambito|seccion|subseccion|denominacion)">(.*?)</p>|<a href="(https://bon\.navarra\.es/es/anuncio/-/texto/\d{4}/\d+/\d+)"[^>]*>(.*?)</a>'
        foreach ($m in [regex]::Matches($body, $rx, 'Singleline')) {
            if ($m.Groups[1].Success) {
                $v = _clean $m.Groups[2].Value
                switch ($m.Groups[1].Value) {
                    'ambito'       { $amb = $v; $sec = ''; $sub = ''; $den = '' }
                    'seccion'      { $sec = $v; $sub = ''; $den = '' }
                    'subseccion'   { $sub = $v; $den = '' }
                    'denominacion' { $den = $v }
                }
                continue
            }
            $partes = @($amb, $sec, $sub) | Where-Object { $_ }
            $seccion = ($partes -join ' - ')
            if ($esExtra) { $seccion = "[EXTRAORDINARIO] $seccion" }
            # Algunos enlaces llevan un '>' dentro del atributo title: quedarse con el texto tras el ultimo '">'
            $tit = $m.Groups[4].Value
            $k = $tit.LastIndexOf('">')
            if ($k -ge 0) { $tit = $tit.Substring($k + 2) }
            $out.Add([pscustomobject]@{
                boletin      = 'BON'
                ambito       = 'Navarra'
                titulo       = _clean $tit
                departamento = $den
                seccion      = $seccion
                url          = $m.Groups[3].Value
            })
        }
    }
    return , $out.ToArray()
}
