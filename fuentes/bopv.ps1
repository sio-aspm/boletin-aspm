# BOPV / EHAA - Boletin Oficial del Pais Vasco (version en castellano)
# Metodo: scraping del sumario HTML (ISO-8859-1 / Windows-1252) por numero de boletin:
#   https://www.euskadi.eus/web01-bopv/es/bopv2/datos/AAAA/MM/sAA_NNNN.shtml
# No hay indice fecha->numero legible: se toma el ultimo numero del RSS
#   https://www.euskadi.eus/bopv2/datos/Ultimo.xml   (titulo "Boletin N 182, fecha 23/09/2026")
# se estima el numero por dias laborables (L-V) y se corrige leyendo la fecha del propio sumario.
# El RSS solo trae titulo+enlace del ultimo boletin (sin departamento) -> se usa el sumario HTML.
# Publica de lunes a viernes. Compatible con Windows PowerShell 5.1.

function Get-Disposiciones_bopv {
    param([Parameter(Mandatory = $true)][datetime]$Fecha)

    [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36'
    $enc = [Text.Encoding]::GetEncoding(1252)
    $f = $Fecha.Date
    $base = 'https://www.euskadi.eus/web01-bopv/es/bopv2/datos'
    $meses = @{ 'enero' = 1; 'febrero' = 2; 'marzo' = 3; 'abril' = 4; 'mayo' = 5; 'junio' = 6; 'julio' = 7; 'agosto' = 8; 'septiembre' = 9; 'setiembre' = 9; 'octubre' = 10; 'noviembre' = 11; 'diciembre' = 12 }

    function _get([string]$u) {
        $r = Invoke-WebRequest -Uri $u -UseBasicParsing -UserAgent $ua -TimeoutSec 90
        return $enc.GetString($r.RawContentStream.ToArray())
    }
    function _clean([string]$s) {
        $s = $s -replace '<[^>]+>', ' '
        $s = [System.Net.WebUtility]::HtmlDecode($s)
        return (($s -replace '\s+', ' ').Trim())
    }
    function _laborables([datetime]$a, [datetime]$b) {
        # numero de dias L-V en (a, b]  (negativo si b < a)
        $sign = 1
        if ($b -lt $a) { $t = $a; $a = $b; $b = $t; $sign = -1 }
        $n = 0; $d = $a.AddDays(1)
        while ($d -le $b) { if ($d.DayOfWeek -ne 'Saturday' -and $d.DayOfWeek -ne 'Sunday') { $n++ }; $d = $d.AddDays(1) }
        return $sign * $n
    }
    # Devuelve @{fecha; html} o $null si no existe ese numero en esa carpeta
    function _sumario([int]$num, [datetime]$mes) {
        $u = '{0}/{1}/s{2}_{3}.shtml' -f $base, $mes.ToString('yyyy/MM'), $mes.ToString('yy'), $num.ToString('0000')
        try { $h = _get $u }
        catch {
            if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) { return $null }
            throw "BOPV: fallo al leer $u : $($_.Exception.Message)"
        }
        $m = [regex]::Match($h, 'tituGeneral">\s*Sumario[^<]*<span>\s*(\d+)\s*</span>\s*,\s*\w+\s+(\d{1,2})\s+de\s+(\w+)\s+de\s+(\d{4})')
        if (-not $m.Success) { return $null }   # pagina generica (numero inexistente)
        $mm = $meses[$m.Groups[3].Value.ToLower()]
        if (-not $mm) { throw "BOPV: mes no reconocido '$($m.Groups[3].Value)' en $u" }
        return @{ fecha = (Get-Date -Year ([int]$m.Groups[4].Value) -Month $mm -Day ([int]$m.Groups[2].Value)).Date; html = $h; url = $u; num = $num }
    }

    if ($f.DayOfWeek -eq 'Saturday' -or $f.DayOfWeek -eq 'Sunday') { return , @() }

    # 1) Ultimo boletin (RSS)
    try { $rss = _get 'https://www.euskadi.eus/bopv2/datos/Ultimo.xml' }
    catch { throw "BOPV: no se pudo leer Ultimo.xml: $($_.Exception.Message)" }
    $m = [regex]::Match($rss, '<title>[^<]*?(\d+)\s*,\s*fecha\s*(\d{2})/(\d{2})/(\d{4})</title>')
    if (-not $m.Success) { throw 'BOPV: Ultimo.xml sin numero/fecha reconocibles (formato cambiado?)' }
    $ultNum = [int]$m.Groups[1].Value
    $ultFecha = (Get-Date -Year ([int]$m.Groups[4].Value) -Month ([int]$m.Groups[3].Value) -Day ([int]$m.Groups[2].Value)).Date
    if ($f -gt $ultFecha) { return , @() }   # todavia no publicado

    # 2) Estimar y corregir
    $est = $ultNum - (_laborables $f $ultFecha)
    if ($f.Year -ne $ultFecha.Year) { throw 'BOPV: solo se soporta el anio en curso (la numeracion se reinicia cada anio).' }
    $probados = @{}
    $encontrado = $null
    $offsets = @(0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6, 8, -8, 10, -10)
    for ($vuelta = 0; $vuelta -lt 4 -and -not $encontrado; $vuelta++) {
        $ajuste = $null
        foreach ($o in $offsets) {
            $n = $est + $o
            if ($n -lt 1 -or $probados.ContainsKey($n)) { continue }
            $probados[$n] = 1
            $s = _sumario $n $f
            if (-not $s) { continue }
            if ($s.fecha -eq $f) { $encontrado = $s; break }
            $ajuste = _laborables $s.fecha $f   # >0 si hay que avanzar
            if ($ajuste -eq 0) { $ajuste = [Math]::Sign(($f - $s.fecha).Days) }
            $est = $n + $ajuste
            break
        }
        if (-not $encontrado -and $null -eq $ajuste) { break }
    }
    if (-not $encontrado) {
        Write-Warning "BOPV: no se localizo boletin para $($f.ToString('yyyy-MM-dd')) (festivo?). Ultimo: $base/Ultimo.shtml"
        return , @()
    }

    # 3) Puede haber mas de un boletin el mismo dia (extraordinario): mirar siguientes numeros
    $sumarios = @($encontrado)
    $k = $encontrado.num
    while ($true) {
        $k++
        if ($k -gt $ultNum) { break }
        $s = _sumario $k $f
        if ($s -and $s.fecha -eq $f) { $sumarios += $s } else { break }
    }
    # y anteriores
    $k = $encontrado.num
    while ($k -gt 1) {
        $k--
        $s = _sumario $k $f
        if ($s -and $s.fecha -eq $f) { $sumarios = @($s) + $sumarios } else { break }
    }

    $out = New-Object System.Collections.Generic.List[object]
    foreach ($s in $sumarios) {
        $h = $s.html
        $carpeta = $s.url.Substring(0, $s.url.LastIndexOf('/') + 1)
        $sec = ''; $sub = ''; $org = ''
        $rx = '<h4 class="BOPVSumarioSeccion">(.*?)</h4>|<h5 class="BOPVSumarioSubSeccion">(.*?)</h5>|<h5 class="BOPVSumarioOrganismo">(.*?)</h5>|<p class="BOPVSumarioTitulo"><a href="([^"]+)">(.*?)</a>'
        foreach ($m in [regex]::Matches($h, $rx, 'Singleline')) {
            if ($m.Groups[1].Success) { $v = _clean $m.Groups[1].Value; if ($v) { $sec = $v; $sub = '' }; continue }
            if ($m.Groups[2].Success) { $v = _clean $m.Groups[2].Value; if ($v) { $sub = $v }; continue }
            if ($m.Groups[3].Success) { $v = _clean $m.Groups[3].Value; if ($v) { $org = $v }; continue }
            $href = $m.Groups[4].Value
            if ($href -notmatch '^https?://') {
                if ($href.StartsWith('/')) { $href = 'https://www.euskadi.eus' + $href } else { $href = $carpeta + $href }
            }
            $seccion = (@($sec, $sub) | Where-Object { $_ }) -join ' - '
            if ($s.num -ne $encontrado.num) { $seccion = "[Boletin $($s.num)] $seccion" }
            $out.Add([pscustomobject]@{
                boletin      = 'BOPV'
                ambito       = ('Pa' + [char]0x00ED + 's Vasco')
                titulo       = _clean $m.Groups[5].Value
                departamento = $org
                seccion      = $seccion
                url          = $href
            })
        }
    }
    return , $out.ToArray()
}
