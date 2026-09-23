# BOCM - Boletin Oficial de la Comunidad de Madrid
# Metodo: XML oficial del sumario (open data) por numero de boletin.
#   https://www.bocm.es/boletin/CM_Boletin_BOCM/AAAA/MM/DD/BOCM-AAAAMMDDNNN.xml
# El numero NNN se obtiene de https://www.bocm.es/boletines.rss (ultimos 20 boletines).
# Para fechas mas antiguas se estima el numero (lunes-sabado) y se prueba un rango.
# Publica de lunes a sabado. Compatible con Windows PowerShell 5.1.
# Nota: el XML repite secciones de forma acumulativa -> se deduplica por identificador.

function Get-Disposiciones_bocm {
    param([Parameter(Mandatory = $true)][datetime]$Fecha)

    [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36'
    $f = $Fecha.Date
    $ymd = $f.ToString('yyyyMMdd')

    function _get([string]$u) {
        $r = Invoke-WebRequest -Uri $u -UseBasicParsing -UserAgent $ua -TimeoutSec 120
        return [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
    }

    # 1) Localizar numero de boletin en el RSS de ultimos boletines
    try { $rss = _get 'https://www.bocm.es/boletines.rss' }
    catch { throw "BOCM: no se pudo leer boletines.rss: $($_.Exception.Message)" }

    $lista = @()
    foreach ($m in [regex]::Matches($rss, 'bocm\.es/boletin/bocm-(\d{8})-(\d+)<')) {
        $lista += [pscustomobject]@{ fecha = [datetime]::ParseExact($m.Groups[1].Value, 'yyyyMMdd', $null); num = [int]$m.Groups[2].Value }
    }
    if ($lista.Count -eq 0) { throw 'BOCM: boletines.rss no contiene boletines (formato cambiado?)' }

    $candidatos = @()
    $hit = $lista | Where-Object { $_.fecha -eq $f } | Select-Object -First 1
    $masAntigua = ($lista | Sort-Object fecha | Select-Object -First 1)
    if ($hit) {
        $candidatos = @($hit.num)
    }
    elseif ($f -ge $masAntigua.fecha) {
        return , @()   # dentro del rango del RSS y sin boletin -> no se publico
    }
    else {
        if ($f.DayOfWeek -eq 'Sunday') { return , @() }
        # estimar: contar dias lun-sab entre la fecha y la mas antigua del RSS (solo mismo anio)
        if ($f.Year -ne $masAntigua.fecha.Year) { throw "BOCM: fecha fuera del rango soportado (anio distinto al del RSS). Consultar https://www.bocm.es/advanced-search" }
        $n = 0; $d = $f
        while ($d -lt $masAntigua.fecha) { if ($d.DayOfWeek -ne 'Sunday') { $n++ }; $d = $d.AddDays(1) }
        $est = $masAntigua.num - $n
        foreach ($k in 0, 1, 2, 3, 4, 5, 6, -1, -2) { if (($est + $k) -gt 0) { $candidatos += ($est + $k) } }
    }

    # 2) Descargar el XML del sumario (la carpeta a veces es la fecha o el dia anterior)
    $xmlTxt = $null; $ultimoError = $null
    foreach ($num in $candidatos) {
        foreach ($dir in @($f, $f.AddDays(-1))) {
            $u = 'https://www.bocm.es/boletin/CM_Boletin_BOCM/{0}/BOCM-{1}{2}.xml' -f $dir.ToString('yyyy/MM/dd'), $ymd, $num
            try { $xmlTxt = _get $u; break } catch { $ultimoError = $_.Exception.Message }
        }
        if ($xmlTxt) { break }
    }
    if (-not $xmlTxt) {
        if ($hit) { throw "BOCM: existe el boletin $($hit.num) del $ymd pero no se pudo leer su XML: $ultimoError" }
        Write-Warning "BOCM: no se encontro boletin para $ymd (posible festivo). Sumario humano: https://www.bocm.es/advanced-search"
        return , @()
    }

    try { $x = [xml]$xmlTxt } catch { throw "BOCM: XML del sumario no valido: $($_.Exception.Message)" }

    $out = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($n in $x.SelectNodes('//disposicion')) {
        $id = [string]$n.identificador
        if (-not $id -or $seen.ContainsKey($id)) { continue }
        $seen[$id] = 1
        $org = ''; $apa = ''; $sec = ''
        $p = $n.ParentNode
        while ($p -and $p.NodeType -eq 'Element') {
            switch ($p.LocalName) {
                'organismo' { if (-not $org) { $org = $p.GetAttribute('nombre') } }
                'apartado'  { if (-not $apa) { $apa = $p.GetAttribute('nombre') } }
                'seccion'   { if (-not $sec) { $sec = $p.GetAttribute('nombre') } }
            }
            $p = $p.ParentNode
        }
        $tit = ([string]$n.titulo -replace '\s+', ' ').Trim()
        $tit = $tit -replace ('^[' + [char]0x2013 + '\-]\s*'), ''
        $seccion = (($sec -replace '\s+', ' ').Trim())
        if ($apa) { $seccion = $seccion + ' - ' + (($apa -replace '\s+', ' ').Trim()) }
        $url = [string]$n.url_html
        if (-not $url) { $url = 'https://www.bocm.es/' + $id.ToLower() }
        $out.Add([pscustomobject]@{
            boletin      = 'BOCM'
            ambito       = 'Comunidad de Madrid'
            titulo       = $tit
            departamento = (($org -replace '\s+', ' ').Trim() -replace ':$', '')
            seccion      = $seccion
            url          = $url
        })
    }
    return , $out.ToArray()
}
