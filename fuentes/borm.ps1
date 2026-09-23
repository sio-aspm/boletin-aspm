# BORM - Boletin Oficial de la Region de Murcia
# Metodo: API REST interna de la sede (la que usa la web AngularJS), devuelve XML UTF-8.
#   https://www.borm.es/services/boletin/fecha/DD-MM-AAAA/sumario
# 404 = ese dia no hubo boletin. Publica de lunes a sabado.
# Enlace humano de cada anuncio: https://www.borm.es/#/home/anuncio/DD-MM-AAAA/NUMERO
# Compatible con Windows PowerShell 5.1.

function Get-Disposiciones_borm {
    param([Parameter(Mandatory = $true)][datetime]$Fecha)

    [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36'
    $dmy = $Fecha.ToString('dd-MM-yyyy')
    $u = "https://www.borm.es/services/boletin/fecha/$dmy/sumario"

    try {
        $r = Invoke-WebRequest -Uri $u -UseBasicParsing -UserAgent $ua -TimeoutSec 90
    }
    catch {
        $code = $null
        if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
        if ($code -eq 404) { return , @() }   # no hubo boletin ese dia
        throw "BORM: fallo al leer $u : $($_.Exception.Message)"
    }

    $txt = [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
    try { $x = [xml]$txt } catch { throw "BORM: respuesta no es XML valido ($u)" }

    $ambito = 'Regi' + [char]0x00F3 + 'n de Murcia'   # ASCII-safe en el .ps1 (PS 5.1 lee sin BOM como ANSI)
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($a in $x.SelectNodes('/SumarioBoletinDTO/anunciosBoletin/anunciosBoletin')) {
        $dep = ([string]$a.anunciante).Trim()
        $sub = ([string]$a.subAnunciante).Trim()
        if ($sub) { if ($dep) { $dep = "$dep / $sub" } else { $dep = $sub } }
        $sec = ([string]$a.apartado).Trim()
        $sap = ([string]$a.subApartado).Trim()
        if ($sap) { $sec = "$sec - $sap" }
        $fp = ([string]$a.fechaPublicacion).Trim()
        if (-not $fp) { $fp = $dmy }
        $out.Add([pscustomobject]@{
            boletin      = 'BORM'
            ambito       = $ambito
            titulo       = (([string]$a.sumario) -replace '\s+', ' ').Trim()
            departamento = $dep
            seccion      = $sec
            url          = "https://www.borm.es/#/home/anuncio/$fp/$($a.numero)"
        })
    }
    return , $out.ToArray()
}
