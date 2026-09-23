# DOGC - Diari Oficial de la Generalitat de Catalunya
# Fuente: API REST JSON interna del portal (la que usa la web del sumario), en castellano.
#   1) POST https://portaldogc.gencat.cat/eadop-rest/api/dogc/calendarDOGC  (month, year, language=es)
#      -> por cada dia: hasDOGC y linkDOGC con numDOGC
#   2) POST https://portaldogc.gencat.cat/eadop-rest/api/dogc/summaryDOGC   (numDOGC, language=es)
#      -> sumaris[].section[].header[] (departamento) .document[] / .subheader[].document[]
# Publica de lunes a viernes (no en festivos de Cataluna). No incluye el "Suplemento" (numSuplement).

function Get-Disposiciones_dogc {
    param([Parameter(Mandatory)][datetime]$Fecha)

    [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36'
    $api = 'https://portaldogc.gencat.cat/eadop-rest/api/dogc/'

    $post = {
        param($metodo, $body)
        try {
            $r = Invoke-WebRequest -Uri ($api + $metodo) -Method Post -Body $body -UseBasicParsing -UserAgent $ua -TimeoutSec 60
        }
        catch { throw "DOGC: fallo en $metodo : $($_.Exception.Message)" }
        $txt = [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
        try { $txt | ConvertFrom-Json } catch { throw "DOGC: respuesta no JSON en $metodo" }
    }

    $cal = & $post 'calendarDOGC' @{ month = $Fecha.Month.ToString(); year = $Fecha.Year.ToString(); language = 'es' }
    if (-not $cal.calendar) { throw "DOGC: calendario vacio o con error ($($cal.errorCode) $($cal.errorDescription))" }
    $clave = $Fecha.ToString('dd/MM/yyyy')
    $dia = @($cal.calendar | Where-Object { $_.date -eq $clave })
    if ($dia.Count -eq 0 -or -not $dia[0].hasDOGC) { return @() }

    $nums = @()
    foreach ($d in $dia) {
        $m = [regex]::Match([string]$d.linkDOGC, 'numDOGC=([^&]+)')
        if ($m.Success) { $nums += $m.Groups[1].Value }
    }
    if ($nums.Count -eq 0) { throw "DOGC: el calendario marca publicacion el $clave pero sin numero de DOGC" }

    $out = New-Object System.Collections.ArrayList
    $mk = {
        param($doc, $sec, $dep)
        $id = [regex]::Match([string]$doc.linkDownloadDocumentPDF, 'documentId=(\d+)').Groups[1].Value
        $url = $doc.linkDownloadDocumentPDF
        if ($id) { $url = 'https://dogc.gencat.cat/es/document-del-dogc/?documentId=' + $id }
        [pscustomobject]@{
            boletin      = 'DOGC'
            ambito       = 'Cataluña'
            titulo       = (([string]$doc.title) -replace '\s+', ' ').Trim()
            departamento = $dep
            seccion      = $sec
            url          = $url
        }
    }

    foreach ($n in $nums) {
        $sum = & $post 'summaryDOGC' @{ numDOGC = $n; language = 'es' }
        if (-not $sum.sumaris) { throw "DOGC: sumario $n vacio o con error ($($sum.errorCode) $($sum.errorDescription))" }
        foreach ($s in $sum.sumaris) {
            foreach ($sec in @($s.section)) {
                if ($null -eq $sec) { continue }
                foreach ($doc in @($sec.document)) { if ($doc) { [void]$out.Add((& $mk $doc $sec.title '')) } }
                foreach ($h in @($sec.header)) {
                    if ($null -eq $h) { continue }
                    foreach ($doc in @($h.document)) { if ($doc) { [void]$out.Add((& $mk $doc $sec.title $h.title)) } }
                    foreach ($sh in @($h.subheader)) {
                        if ($null -eq $sh) { continue }
                        $dep = $h.title
                        if ($sh.title) { $dep = "$($h.title) - $($sh.title)" }
                        foreach ($doc in @($sh.document)) { if ($doc) { [void]$out.Add((& $mk $doc $sec.title $dep)) } }
                    }
                }
            }
        }
    }
    if ($out.Count -eq 0) { throw "DOGC: DOGC $($nums -join ',') sin disposiciones reconocibles (cambio de estructura?)" }
    return $out.ToArray()
}
