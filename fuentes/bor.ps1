# BOR - Boletin Oficial de La Rioja
# Metodo: endpoint AJAX (JSON) que usa el calendario de la portada del BOR:
#   POST https://web.larioja.org/apps/ckan-client/public/bor/getBors
#        body: date=<fecha estilo JS, p.ej. "Tue Sep 22 2026 00:00:00 GMT+0000">&numero=&getDetalleBOR=true
#   -> data.fechas (dias con BOR), data.fechas_extra (dias con extraordinario), data.bor (HTML del sumario)
# Enlace a cada anuncio (version HTML): https://web.larioja.org/bor-portada/boranuncio?n=<referencia>
# Publica de lunes a viernes. Sumario humano: https://web.larioja.org/bor-portada?fecha=AAAA-MM-DD
# Limitacion: los dias con BOR extraordinario la API solo devuelve uno de los dos boletines (se avisa).
# Compatible con Windows PowerShell 5.1.

function Get-Disposiciones_bor {
    param([Parameter(Mandatory = $true)][datetime]$Fecha)

    [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36'
    $f = $Fecha.Date
    $ci = [Globalization.CultureInfo]::InvariantCulture
    $jsDate = $f.ToString('ddd MMM dd yyyy', $ci) + ' 00:00:00 GMT+0000'
    $u = 'https://web.larioja.org/apps/ckan-client/public/bor/getBors'

    function _clean([string]$s) {
        $s = $s -replace '<[^>]+>', ' '
        $s = [System.Net.WebUtility]::HtmlDecode($s)
        return (($s -replace '\s+', ' ').Trim())
    }

    try {
        $r = Invoke-WebRequest -Uri $u -Method Post -UseBasicParsing -UserAgent $ua -TimeoutSec 90 `
            -Body @{ date = $jsDate; numero = ''; getDetalleBOR = 'true' }
        $txt = [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
    }
    catch { throw "BOR: fallo en la llamada a $u : $($_.Exception.Message)" }

    try { $j = $txt | ConvertFrom-Json } catch { throw "BOR: respuesta no es JSON ($($txt.Substring(0, [Math]::Min(200, $txt.Length))))" }
    if ($j.status -ne 'success' -or $null -eq $j.data) { throw "BOR: respuesta con estado '$($j.status)'" }

    $iso = $f.ToString('yyyy-MM-dd')
    $b = [string]$j.data.bor
    if (@($j.data.fechas) -notcontains $iso -or $b -match 'No hay ning') { return , @() }
    if (@($j.data.fechas_extra) -contains $iso) {
        Write-Warning "BOR: el $iso hubo BOR extraordinario; la API solo devuelve uno. Revisar https://web.larioja.org/bor-portada?fecha=$iso"
    }

    $out = New-Object System.Collections.Generic.List[object]
    $sec = ''; $sub = ''; $org = ''; $com = ''
    $rx = '<h([3-6])[^>]*>(.*?)</h\1>|<li class="anuncio_text">(.*?)</li>'
    foreach ($m in [regex]::Matches($b, $rx, 'Singleline')) {
        if ($m.Groups[1].Success) {
            $v = _clean $m.Groups[2].Value
            switch ($m.Groups[1].Value) {
                '3' { $sec = $v; $sub = ''; $org = ''; $com = '' }
                '4' { $sub = $v; $org = ''; $com = '' }
                '5' { $org = $v; $com = '' }
                '6' { $com = $v }
            }
            continue
        }
        $li = $m.Groups[3].Value
        $a = [regex]::Match($li, '<a href="([^"]*)"[^>]*title="Texto[^"]*"[^>]*>(.*?)</a>', 'Singleline')
        if (-not $a.Success) { continue }
        $pdf = ($a.Groups[1].Value -replace '\s+', '')
        $html = [regex]::Match($li, 'href="(https://web\.larioja\.org/bor-portada/boranuncio\?n=[^"]*)"')
        $url = $pdf
        if ($html.Success) { $url = ($html.Groups[1].Value -replace '\s+', '') }
        $dep = $org
        if ($com) { if ($dep) { $dep = "$dep / $com" } else { $dep = $com } }
        $out.Add([pscustomobject]@{
            boletin      = 'BOR'
            ambito       = 'La Rioja'
            titulo       = _clean $a.Groups[2].Value
            departamento = $dep
            seccion      = ((@($sec, $sub) | Where-Object { $_ }) -join ' - ')
            url          = $url
        })
    }
    if ($out.Count -eq 0) { throw "BOR: habia boletin el $iso pero no se extrajo ningun anuncio (formato cambiado?)" }
    return , $out.ToArray()
}
