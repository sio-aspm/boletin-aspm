# BOA - Boletín Oficial de Aragón
# Método: servicio Open Data del BOA (CGI BRSCGI, salida JSON, codificación ISO-8859-1/windows-1252):
#   https://www.boa.aragon.es/cgi-bin/EBOA/BRSCGI?CMD=VERLST&OUTPUTMODE=JSON&BASE=BZHT&DOCS=1-1000&SEC=OPENDATABOAJSONAPP&SORT=-PUBL&SEPARADOR=&PUBL-C=AAAAMMDD
# La base BZHT mezcla el BOA (secciones I-V) con los Boletines Oficiales de las Provincias de
# Huesca, Teruel y Zaragoza (secciones VI, VII, VIII). Por defecto se devuelven solo las secciones
# del BOA; con -IncluirBOP se incluyen también las provinciales.
# Si no hay boletín, el CGI devuelve una página HTML con "No se han recuperado documentos".
# Publica: BOA de lunes a viernes (el BOP de Zaragoza también sale algunos sábados).
# Enlace por disposición: ficha HTML  ...BRSCGI?CMD=VERDOC&BASE=BOLE&DOCN=<DOCN>

function Get-Disposiciones_boa {
    param([Parameter(Mandatory = $true)][datetime]$Fecha, [switch]$IncluirBOP)
    [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36'
    $f = $Fecha.ToString('yyyyMMdd')
    $url = "https://www.boa.aragon.es/cgi-bin/EBOA/BRSCGI?CMD=VERLST&OUTPUTMODE=JSON&BASE=BZHT&DOCS=1-1000&SEC=OPENDATABOAJSONAPP&SORT=-PUBL&SEPARADOR=&PUBL-C=$f"
    $txt = $null; $err = $null
    for ($i = 0; $i -lt 3 -and $txt -eq $null; $i++) {
        try {
            $r = Invoke-WebRequest -Uri $url -UseBasicParsing -UserAgent $ua -TimeoutSec 90
            $txt = [Text.Encoding]::GetEncoding('windows-1252').GetString($r.RawContentStream.ToArray())
        } catch { $err = $_; Start-Sleep -Seconds 2 }
    }
    if ($txt -eq $null) { throw "BOA: fallo al descargar el Open Data: $($err.Exception.Message)" }
    $t = $txt.TrimStart()
    if (-not $t.StartsWith('[')) {
        if ($t -match 'No se han recuperado documentos') { return @() }
        throw 'BOA: respuesta inesperada del servicio Open Data (ni JSON ni "sin documentos")'
    }
    try { $j = ConvertFrom-Json $txt } catch { throw "BOA: JSON no válido: $($_.Exception.Message)" }
    $out = @()
    foreach ($d in @($j)) {
        if ($d.FechaPublicacion -ne $f) { continue }
        if (-not $IncluirBOP -and $d.Seccion -match '^(VI|VII|VIII)\.') { continue }
        $sec = $d.Seccion; if ($d.Subseccion) { $sec = "$($d.Seccion) / $($d.Subseccion)" }
        $out += [pscustomobject]@{
            boletin = 'BOA'; ambito = 'Aragón'
            titulo = [Net.WebUtility]::HtmlDecode(($d.Titulo -replace '\s+', ' ').Trim())
            departamento = [Net.WebUtility]::HtmlDecode("$($d.Emisor)".Trim())
            seccion = $sec
            url = "https://www.boa.aragon.es/cgi-bin/EBOA/BRSCGI?CMD=VERDOC&BASE=BOLE&DOCN=$($d.DOCN)"
        }
    }
    return $out
}
