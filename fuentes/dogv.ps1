# DOGV - Diari Oficial de la Generalitat Valenciana
# Fuente: API REST JSON del nuevo portal (la que usa la web Angular), en castellano (lang=es_es).
#   Calendario: https://dogv.gva.es/dogv-portal/dogv/calendar?startDate=AAAA-M-D&endDate=AAAA-M-D
#   Sumario:    https://dogv.gva.es/dogv-portal/dogv?date=AAAA-MM-DD&lang=es_es
#   Bis/ter:    https://dogv.gva.es/dogv-portal/dogv/{numeroDogv}/versionesSumario  -> [1,2,...]
#               https://dogv.gva.es/dogv-portal/dogv/{numeroDogv}?ordenSumario=N&lang=es_es
# Publica de lunes a viernes (laborables). Algunos dias hay DOGV "bis" (esBis=true).
# Enlace humano por disposicion: https://dogv.gva.es/es/resultat-dogv?signatura=<codigoInsercion>

function Get-Disposiciones_dogv {
    param([Parameter(Mandatory)][datetime]$Fecha)

    [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36'
    $api = 'https://dogv.gva.es/dogv-portal/dogv'

    $get = {
        param($u)
        try { $r = Invoke-WebRequest -Uri $u -UseBasicParsing -UserAgent $ua -TimeoutSec 60 -Headers @{ Accept = 'application/json' } }
        catch { throw "DOGV: fallo al descargar $u : $($_.Exception.Message)" }
        $txt = [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
        try { $txt | ConvertFrom-Json } catch { throw "DOGV: respuesta no JSON en $u" }
    }

    $d = $Fecha.ToString('yyyy-M-d')
    $cal = & $get "$api/calendar?startDate=$d&endDate=$d"   # PS 5.1: ConvertFrom-Json devuelve el array como un solo objeto
    $iso = $Fecha.ToString('yyyy-MM-dd')
    $dia = @(foreach ($c in $cal) { if ($c.fecha -eq $iso) { $c } })
    if ($dia.Count -eq 0) { return @() }

    $sum = & $get "$api`?date=$iso&lang=es_es"
    if (-not $sum.cabecera) { throw "DOGV: sumario del $iso sin cabecera" }
    $sumarios = New-Object System.Collections.ArrayList
    [void]$sumarios.Add($sum)

    $esBis = $false
    foreach ($x in $dia) { if ($x.esBis) { $esBis = $true } }
    if ($esBis) {
        $num = $sum.cabecera.numeroDogv
        $vers = & $get "$api/$num/versionesSumario"
        foreach ($v in $vers) {
            if ([int]$v -ne 1) { [void]$sumarios.Add((& $get "$api/$num`?ordenSumario=$v&lang=es_es")) }
        }
    }

    $out = New-Object System.Collections.ArrayList
    $vistos = @{}
    foreach ($s in $sumarios) {
        foreach ($p in $s.disposiciones) {
            if ($null -eq $p) { continue }
            if ($p.borrador) { continue }
            $key = [string]$p.id
            if ($vistos.ContainsKey($key)) { continue }
            $vistos[$key] = 1
            $sec = [string]$p.seccion.descripcion
            if ($p.subseccion -and $p.subseccion.descripcion) { $sec = "$sec - $($p.subseccion.descripcion)" }
            $url = $null
            if ($p.codigoInsercion) { $url = 'https://dogv.gva.es/es/resultat-dogv?signatura=' + $p.codigoInsercion }
            elseif ($p.urlPdf) { $url = 'https://dogv.gva.es/datos' + $p.urlPdf }
            [void]$out.Add([pscustomobject]@{
                boletin      = 'DOGV'
                ambito       = 'Comunitat Valenciana'
                titulo       = (([string]$p.titulo) -replace '\s+', ' ').Trim()
                departamento = [string]$p.organismo
                seccion      = $sec
                url          = $url
            })
        }
    }
    if ($out.Count -eq 0) { throw "DOGV: el calendario marca publicacion el $iso pero el sumario no trae disposiciones" }
    return $out.ToArray()
}
