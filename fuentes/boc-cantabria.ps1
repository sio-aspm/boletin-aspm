# BOC - Boletín Oficial de Cantabria
# Método:
#   1) Calendario JSON (el que usa la web): POST https://boc.cantabria.es/boces/busquedaBoletines.do?mes=M&year=AAAA
#      -> [{id, fecBolString "22 de septiembre de 2026", tipoBol, numBol, ...}]
#      tipoBol 0 = ordinario, 1 = un extraordinario, 3 = varios extraordinarios ese día.
#   2) Sumario HTML de cada boletín:
#      ordinario        https://boc.cantabria.es/boces/verBoletin.do?idBolOrd=<id>
#      extraordinario   https://boc.cantabria.es/boces/verBoletinExtraordinario.do?id=<id>
#      varios extraord. https://boc.cantabria.es/boces/verBoletin.do?dia=D&mes=M&anio=AAAA&tipoBol=1 (lista de ids)
#      span.titulo2 = sección, span.spanH5 = subsección, span.spanH4 = organismo, span.spanH6 = unidad,
#      <p> = título, verAnuncioAction.do?idAnuBlob=N = PDF de la disposición (único enlace por anuncio).
#   (Existe también XML por boletín: verXmlAction.do?idBlob=<id>, con sumario completo pero SIN enlaces.)
# Publica: lunes a viernes (+ extraordinarios).

function Get-BocCantHtml_ {
    param([string]$Url, [string]$Method = 'Get')
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36'
    $last = $null
    for ($i = 0; $i -lt 3; $i++) {
        try {
            $r = Invoke-WebRequest -Uri $Url -Method $Method -UseBasicParsing -UserAgent $ua -TimeoutSec 60
            $bytes = $r.RawContentStream.ToArray()
            $enc = [Text.Encoding]::UTF8
            $ct = "$($r.Headers['Content-Type'])"
            if ($ct -match 'charset=(iso-8859-1|windows-1252|latin1)') { $enc = [Text.Encoding]::GetEncoding('windows-1252') }
            return $enc.GetString($bytes)
        } catch { $last = $_; Start-Sleep -Seconds 2 }
    }
    throw "BOC Cantabria: fallo al descargar $Url : $($last.Exception.Message)"
}

function ConvertFrom-BocCantSumario_ {
    param([string]$Html, [string]$Etiqueta)
    $base = 'https://boc.cantabria.es/boces/'
    $clean = { param($s) [Net.WebUtility]::HtmlDecode(($s -replace '<[^>]+>', ' ' -replace '\s+', ' ')).Trim() }
    $ini = $Html.IndexOf('class="descargaXML"')
    if ($ini -lt 0) { throw 'BOC Cantabria: sumario sin estructura reconocible' }
    $fin = $Html.IndexOf('<footer', $ini); if ($fin -lt 0) { $fin = $Html.Length }
    $body = $Html.Substring($ini, $fin - $ini)
    $pat = '(?s)<span class="titulo2[^"]*">(?<sec>.*?)</span>|<span class="spanH5">(?<sub>.*?)</span>|<span class="spanH4">(?<dep>.*?)</span>|<span class="spanH6">(?<uni>.*?)</span>|<p>(?<tit>.*?)</p>\s*<div class="enlacesDoc">(?<links>.*?)</div>\s*</div>'
    $sec = ''; $sub = ''; $dep = ''; $uni = ''
    $out = @()
    foreach ($m in [regex]::Matches($body, $pat)) {
        if ($m.Groups['sec'].Success) { $sec = & $clean $m.Groups['sec'].Value; $sub = ''; $dep = ''; $uni = '' }
        elseif ($m.Groups['sub'].Success) { $sub = & $clean $m.Groups['sub'].Value; $dep = ''; $uni = '' }
        elseif ($m.Groups['dep'].Success) { $dep = & $clean $m.Groups['dep'].Value; $uni = '' }
        elseif ($m.Groups['uni'].Success) { $uni = & $clean $m.Groups['uni'].Value }
        else {
            $a = [regex]::Match($m.Groups['links'].Value, 'href="([^"]+)"')
            $u = [Net.WebUtility]::HtmlDecode($a.Groups[1].Value)
            if ($u -and $u -notmatch '^https?:') { $u = $base + $u }
            $s = $sec; if ($sub) { $s = "$sec / $sub" }
            if ($Etiqueta) { $s = "[$Etiqueta] $s" }
            $d = $dep; if ($uni) { $d = "$dep / $uni" }
            $out += [pscustomobject]@{
                boletin = 'BOC'; ambito = 'Cantabria'
                titulo = & $clean $m.Groups['tit'].Value
                departamento = $d; seccion = $s; url = $u
            }
        }
    }
    return $out
}

function Get-Disposiciones_boc_cantabria {
    param([Parameter(Mandatory = $true)][datetime]$Fecha)
    [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
    $base = 'https://boc.cantabria.es/boces/'
    $meses = @('enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre')
    $json = Get-BocCantHtml_ ($base + "busquedaBoletines.do?mes=$($Fecha.Month)&year=$($Fecha.Year)") 'Post'
    try { $cal = @((ConvertFrom-Json $json) | ForEach-Object { $_ }) } catch { throw 'BOC Cantabria: el calendario no devolvió JSON válido' }
    $txt = '{0:00} de {1} de {2}' -f $Fecha.Day, $meses[$Fecha.Month - 1], $Fecha.Year
    $dia = @($cal | Where-Object { $_.fecBolString -eq $txt })
    if ($dia.Count -eq 0) { return @() }

    $out = @()
    foreach ($b in $dia) {
        if ("$($b.tipoBol)" -eq '0') {
            $out += ConvertFrom-BocCantSumario_ (Get-BocCantHtml_ ($base + "verBoletin.do?idBolOrd=$($b.id)")) ''
        } elseif ("$($b.tipoBol)" -eq '1') {
            $out += ConvertFrom-BocCantSumario_ (Get-BocCantHtml_ ($base + "verBoletinExtraordinario.do?id=$($b.id)")) 'Extraordinario'
        } else {
            $lista = Get-BocCantHtml_ ($base + "verBoletin.do?dia=$($Fecha.Day)&mes=$($Fecha.Month)&anio=$($Fecha.Year)&tipoBol=1")
            $ids = @([regex]::Matches($lista, 'verBoletinExtraordinario\.do\?id=(\d+)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
            if ($ids.Count -eq 0) { throw "BOC Cantabria: no se encontraron los extraordinarios del $txt" }
            foreach ($id in $ids) {
                $out += ConvertFrom-BocCantSumario_ (Get-BocCantHtml_ ($base + "verBoletinExtraordinario.do?id=$id")) 'Extraordinario'
            }
        }
    }
    return $out
}
