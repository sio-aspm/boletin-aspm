# Descarga el BOE y los boletines autonómicos de todas las fechas pendientes.
# Uso: powershell -ExecutionPolicy Bypass -File scripts\descargar.ps1 [-Edicion AAAA-MM-DD] [-Desde AAAA-MM-DD]
# Genera datos\<edicion>.json (todo) y datos\<edicion>.tsv (lista compacta para clasificar).
param(
    [string]$Edicion = (Get-Date).ToString('yyyy-MM-dd'),
    [string]$Desde = ''
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$raiz = Split-Path -Parent $PSScriptRoot
$utf8 = New-Object Text.UTF8Encoding $false

# Fechas a cubrir: desde el día siguiente a la última edición procesada (máx. 7 días atrás) hasta hoy
$hoy = [datetime]::ParseExact($Edicion, 'yyyy-MM-dd', $null)
$ultimaFile = Join-Path $raiz 'estado\ultima-fecha.txt'
if ($Desde) {
    $inicio = [datetime]::ParseExact($Desde, 'yyyy-MM-dd', $null)
} elseif (Test-Path $ultimaFile) {
    $inicio = [datetime]::ParseExact((Get-Content $ultimaFile -Raw).Trim(), 'yyyy-MM-dd', $null).AddDays(1)
} else {
    $inicio = $hoy
}
if ($inicio -lt $hoy.AddDays(-6)) { $inicio = $hoy.AddDays(-6) }
if ($inicio -gt $hoy) { $inicio = $hoy }
$fechas = @()
for ($d = $inicio; $d -le $hoy; $d = $d.AddDays(1)) { $fechas += $d }

# Cargar todas las fuentes (una función Get-Disposiciones_<codigo> por archivo)
$fuentes = Get-ChildItem (Join-Path $raiz 'fuentes') -Filter *.ps1 | Sort-Object Name
foreach ($f in $fuentes) { . $f.FullName }

$items = New-Object System.Collections.ArrayList
$estado = New-Object System.Collections.ArrayList
foreach ($fecha in $fechas) {
    foreach ($f in $fuentes) {
        $codigo = $f.BaseName
        $fn = 'Get-Disposiciones_' + ($codigo -replace '-', '_')
        $reg = [ordered]@{ fuente = $codigo.ToUpper(); fecha = $fecha.ToString('yyyy-MM-dd'); estado = 'ok'; n = 0; error = '' }
        try {
            $res = @(& $fn -Fecha $fecha)
            $n = 0
            foreach ($r in $res) {
                if (-not $r.titulo) { continue }
                $n++
                [void]$items.Add([ordered]@{
                    id = ($codigo.ToUpper() + '-' + $fecha.ToString('MMdd') + '-' + $n)
                    fecha = $fecha.ToString('yyyy-MM-dd')
                    boletin = $r.boletin; ambito = $r.ambito
                    seccion = "$($r.seccion)"; departamento = "$($r.departamento)"
                    titulo = (("$($r.titulo)") -replace '\s+', ' ').Trim()
                    url = "$($r.url)"
                })
            }
            $reg.n = $n
            if ($n -eq 0) { $reg.estado = 'sin publicación' }
        } catch {
            $reg.estado = 'error'
            $reg.error = $_.Exception.Message
        }
        [void]$estado.Add($reg)
        Write-Host ("{0} {1,-14} {2,-16} {3}" -f $reg.fecha, $reg.fuente, $reg.estado, $reg.n)
    }
}

$datosDir = Join-Path $raiz 'datos'
New-Item -ItemType Directory -Force $datosDir | Out-Null
$obj = [ordered]@{
    edicion = $Edicion
    fechas = @($fechas | ForEach-Object { $_.ToString('yyyy-MM-dd') })
    fuentes = $estado.ToArray()
    items = $items.ToArray()
}
[IO.File]::WriteAllText((Join-Path $datosDir "$Edicion.json"), ($obj | ConvertTo-Json -Depth 5), $utf8)

# Lista compacta para que Claude la lea entera
$sb = New-Object Text.StringBuilder
[void]$sb.AppendLine("id`tboletin`tseccion`tdepartamento`ttitulo")
foreach ($it in $items) {
    $t = $it.titulo
    if ($t.Length -gt 450) { $t = $t.Substring(0, 450) + '…' }
    [void]$sb.AppendLine(($it.id, $it.boletin, $it.seccion, $it.departamento, $t) -join "`t")
}
[IO.File]::WriteAllText((Join-Path $datosDir "$Edicion.tsv"), $sb.ToString(), $utf8)
Write-Host "TOTAL: $($items.Count) disposiciones en $($fechas.Count) fecha(s). Errores: $(@($estado | Where-Object { $_.estado -eq 'error' }).Count)"
