# Correos de la BB.DD. de personas de ASPM agrupados por comunidad autónoma, para el CCO del
# botón «Reenviar por correo» de la copia local del boletín. Lo usa publicar.ps1.
# Nunca se escribe nada de esto en docs\ ni en el repositorio (la web es pública).
# Get-Destinatarios [<ruta del Excel>] -> @{ ccaa = [ordered]@{ 'Madrid' = @('a@b.es', …) }; avisos = @(…) }

# Nombres tal y como están en la columna COMUNIDAD AUTÓNOMA de la BB.DD.
$CCAA = 'Andalucía','Aragón','Asturias','Canarias','Cantabria','Castilla-La Mancha','Castilla y León','Cataluña',
    'Ceuta','Comunidad Valenciana','Extremadura','Galicia','Illes Balears','La Rioja','Madrid','Melilla','Murcia',
    'Navarra','País Vasco'

# Ámbito de cada boletín (campo «ambito» de fuentes\*.ps1) -> nombre de la BB.DD. «Estatal» no tiene CC.AA.
$AmbitoCCAA = @{ 'Comunidad de Madrid' = 'Madrid'; 'Principado de Asturias' = 'Asturias'; 'Región de Murcia' = 'Murcia'
    'Comunitat Valenciana' = 'Comunidad Valenciana' }
function CCAA-De-Ambito($ambito) {
    if ($AmbitoCCAA.ContainsKey("$ambito")) { return $AmbitoCCAA["$ambito"] }
    if ($CCAA -contains "$ambito") { return "$ambito" }
    return ''
}

# Para las filas que solo tienen provincia (sobre todo la hoja CONTACTOS SIO)
$ProvinciaCCAA = @{}
foreach ($p in @(
    @('Andalucía', 'Almería','Cádiz','Córdoba','Granada','Huelva','Jaén','Málaga','Sevilla'),
    @('Aragón', 'Huesca','Teruel','Zaragoza'),
    @('Asturias', 'Asturias','Oviedo'),
    @('Canarias', 'Las Palmas','Santa Cruz de Tenerife','Tenerife','Gran Canaria'),
    @('Cantabria', 'Cantabria','Santander'),
    @('Castilla-La Mancha', 'Albacete','Ciudad Real','Cuenca','Guadalajara','Toledo'),
    @('Castilla y León', 'Ávila','Burgos','León','Palencia','Salamanca','Segovia','Soria','Valladolid','Zamora'),
    @('Cataluña', 'Barcelona','Girona','Gerona','Lleida','Lérida','Tarragona'),
    @('Ceuta', 'Ceuta'), @('Melilla', 'Melilla'),
    @('Comunidad Valenciana', 'Alicante','Alacant','Castellón','Castelló','Valencia','València'),
    @('Extremadura', 'Badajoz','Cáceres'),
    @('Galicia', 'A Coruña','La Coruña','Lugo','Ourense','Orense','Pontevedra'),
    @('Illes Balears', 'Illes Balears','Islas Baleares','Baleares','Mallorca','Menorca','Ibiza'),
    @('La Rioja', 'La Rioja','Rioja'),
    @('Madrid', 'Madrid'), @('Murcia', 'Murcia'), @('Navarra', 'Navarra'),
    @('País Vasco', 'Álava','Araba','Gipuzkoa','Guipúzcoa','Bizkaia','Vizcaya'))) {
    foreach ($prov in $p[1..($p.Count - 1)]) { $ProvinciaCCAA[$prov.ToLower()] = $p[0] }
}
function Normal-CCAA($ccaa, $provincia) {
    $c = "$ccaa".Trim()
    $hit = $CCAA | Where-Object { $_ -eq $c } | Select-Object -First 1
    if ($hit) { return $hit }
    $c2 = CCAA-De-Ambito $c; if ($c2) { return $c2 }
    $p = "$provincia".Trim().ToLower()
    if ($ProvinciaCCAA.ContainsKey($p)) { return $ProvinciaCCAA[$p] }
    return ''
}

function Get-Destinatarios([string]$Ruta = 'C:\Users\Usuario\Downloads\7. DOC. REVISAR\Socios\BASE DE DATOS ASPM (socios y afectados + otras personas).xlsx') {
    . 'C:\Users\Usuario\Downloads\SIO - IA\herramientas\base-datos-personas\leer-xlsx.ps1'
    $porCCAA = [ordered]@{}; foreach ($c in $CCAA) { $porCCAA[$c] = New-Object Collections.Generic.List[string] }
    $avisos = @()
    $vistos = @{}
    function Anadir($email, $ccaa) {
        foreach ($e in ("$email" -split '[;,\s]+')) {
            $e = $e.Trim().ToLower()
            if ($e -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { continue }
            $k = "$ccaa|$e"; if ($vistos.ContainsKey($k)) { continue }
            $vistos[$k] = $true; $porCCAA[$ccaa].Add($e)
        }
    }
    # PERSONAS: todas con email, menos las BAJA y las que viven fuera de España
    foreach ($p in @(Leer-Xlsx $Ruta 'PERSONAS')) {
        if (-not $p.EMAIL -or $p.TIPO -eq 'BAJA') { continue }
        if ($p.'PAÍS' -and $p.'PAÍS' -ne 'España') { continue }
        $c = Normal-CCAA $p.'COMUNIDAD AUTÓNOMA' $p.PROVINCIA
        if ($c) { Anadir $p.EMAIL $c }
        elseif ($p.'COMUNIDAD AUTÓNOMA') { $avisos += "PERSONAS fila $($p._fila): comunidad autónoma «$($p.'COMUNIDAD AUTÓNOMA')» no reconocida" }
    }
    # CONTACTOS SIO: solo las que tienen una provincia de España
    foreach ($p in @(Leer-Xlsx $Ruta 'CONTACTOS SIO')) {
        if (-not $p.EMAIL) { continue }
        if ($p.'PAÍS' -and $p.'PAÍS' -ne 'España') { continue }
        $c = Normal-CCAA '' $p.PROVINCIA
        if ($c) { Anadir $p.EMAIL $c }
    }
    return @{ ccaa = $porCCAA; avisos = $avisos }
}
