# BOC - Boletín Oficial de Canarias
# Método: HTML.
#   1) Archivo anual https://www.gobiernodecanarias.org/boc/archivo/AAAA/  -> enlaces
#      "/boc/AAAA/NNN/index.html" con texto "BOC Nº N - D de <mes> de AAAA - <día>".
#   2) Sumario del número https://www.gobiernodecanarias.org/boc/AAAA/NNN/index.html
#      h4 = sección, h3.titboc = subsección, h5 = consejería/organismo, li.justificado_boc = disposición.
#   Enlace devuelto: versión HTML /boc/AAAA/NNN/<n>.html (el PDF oficial está en
#   https://sede.gobiernodecanarias.org/boc/boc-a-AAAA-NNN-<n>.pdf).
# Publica: lunes a viernes.

function Get-BoccHtml_ {
    param([string]$Url)
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36'
    $last = $null
    for ($i = 0; $i -lt 3; $i++) {
        try {
            $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -UserAgent $ua -TimeoutSec 60
            return [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
        } catch { $last = $_; Start-Sleep -Seconds 2 }
    }
    throw "BOC Canarias: fallo al descargar $Url : $($last.Exception.Message)"
}

function Get-Disposiciones_boc_canarias {
    param([Parameter(Mandatory = $true)][datetime]$Fecha)
    [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
    $meses = @('enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre')
    $base = 'https://www.gobiernodecanarias.org'
    $arch = Get-BoccHtml_ "$base/boc/archivo/$($Fecha.Year)/"
    if ($arch -notmatch '/boc/\d{4}/\d+/index\.html') { throw 'BOC Canarias: archivo anual sin enlaces reconocibles (estructura cambiada?)' }
    $txtFecha = "- $($Fecha.Day) de $($meses[$Fecha.Month - 1]) de $($Fecha.Year) -"
    $nums = @([regex]::Matches($arch, '(?s)href="(/boc/\d{4}/\d+/index\.html)"[^>]*>(.*?)</a>') |
        Where-Object { ($_.Groups[2].Value -replace '\s+', ' ') -like "*$txtFecha*" } |
        ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    if ($nums.Count -eq 0) { return @() }

    $clean = { param($s) [Net.WebUtility]::HtmlDecode(($s -replace '<[^>]+>', ' ' -replace '\s+', ' ')).Trim() }
    $pat = '(?s)<h4>(?<h4>.*?)</h4>|<h3 class="titboc">(?<h3>.*?)</h3>|<h5>(?<h5>.*?)</h5>|<li class="justificado_boc">(?<li>.*?)</li>'
    $out = @()
    foreach ($n in $nums) {
        $html = Get-BoccHtml_ ($base + $n)
        $sec = ''; $sub = ''; $dep = ''
        foreach ($m in [regex]::Matches($html, $pat)) {
            if ($m.Groups['h4'].Success) { $sec = & $clean $m.Groups['h4'].Value; $sub = ''; $dep = '' }
            elseif ($m.Groups['h3'].Success) { $sub = & $clean $m.Groups['h3'].Value; $dep = '' }
            elseif ($m.Groups['h5'].Success) { $dep = & $clean $m.Groups['h5'].Value }
            else {
                $li = $m.Groups['li'].Value
                $t = [regex]::Match($li, '(?s)</b>\s*</a>\s*<a[^>]*>(.*?)</a>')
                if (-not $t.Success) { continue }
                $h = [regex]::Match($li, 'href="([^"]+\.html)"')
                if ($h.Success) { $u = $h.Groups[1].Value } else { $u = [regex]::Match($li, 'href="([^"]+)"').Groups[1].Value }
                if ($u.StartsWith('/')) { $u = $base + $u }
                $s = $sec; if ($sub) { $s = "$sec / $sub" }
                $out += [pscustomobject]@{
                    boletin = 'BOC'; ambito = 'Canarias'
                    titulo = & $clean $t.Groups[1].Value
                    departamento = $dep; seccion = $s; url = $u
                }
            }
        }
    }
    return $out
}
