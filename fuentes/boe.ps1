# BOE — API de datos abiertos (JSON). Publica de lunes a sábado.
function Get-Disposiciones_boe {
    param([datetime]$Fecha)
    $url = "https://www.boe.es/datosabiertos/api/boe/sumario/" + $Fecha.ToString('yyyyMMdd')
    try {
        $resp = Invoke-WebRequest -UseBasicParsing -Uri $url -Headers @{ Accept = 'application/json' } -TimeoutSec 60
    } catch {
        # La API devuelve 404 los días sin BOE (domingos)
        if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) { return @() }
        throw "BOE: error descargando $url - $($_.Exception.Message)"
    }
    $json = [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json
    $out = New-Object System.Collections.ArrayList

    function Add-Items($items, $seccion, $dpto) {
        foreach ($it in @($items)) {
            if ($null -eq $it) { continue }
            $link = $it.url_html
            if (-not $link) { $link = "https://www.boe.es/diario_boe/txt.php?id=" + $it.identificador }
            [void]$out.Add([pscustomobject]@{
                boletin = 'BOE'; ambito = 'Estatal'; titulo = $it.titulo
                departamento = $dpto; seccion = $seccion; url = $link
            })
        }
    }

    foreach ($diario in @($json.data.sumario.diario)) {
        foreach ($sec in @($diario.seccion)) {
            foreach ($dep in @($sec.departamento)) {
                if ($dep.item) { Add-Items $dep.item $sec.nombre $dep.nombre }
                foreach ($epi in @($dep.epigrafe)) {
                    if ($epi -and $epi.item) { Add-Items $epi.item $sec.nombre $dep.nombre }
                }
            }
        }
    }
    return $out.ToArray()
}
