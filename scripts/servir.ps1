# Servidor local mínimo para ver la newsletter en http://localhost:8080/
param([int]$Puerto = 8080)
$raiz = Join-Path (Split-Path -Parent $PSScriptRoot) 'docs'
$tipos = @{ '.html' = 'text/html; charset=utf-8'; '.css' = 'text/css; charset=utf-8'; '.js' = 'application/javascript'; '.png' = 'image/png'; '.svg' = 'image/svg+xml' }
$l = New-Object Net.HttpListener
$l.Prefixes.Add("http://localhost:$Puerto/")
$l.Start()
Write-Host "Sirviendo $raiz en http://localhost:$Puerto/"
while ($l.IsListening) {
    $ctx = $l.GetContext()
    $ruta = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
    if ($ruta -eq '' -or $ruta.EndsWith('/')) { $ruta += 'index.html' }
    $archivo = [IO.Path]::GetFullPath((Join-Path $raiz $ruta))
    if ($archivo.StartsWith($raiz) -and (Test-Path $archivo -PathType Leaf)) {
        $bytes = [IO.File]::ReadAllBytes($archivo)
        $ext = [IO.Path]::GetExtension($archivo).ToLower()
        if ($tipos.ContainsKey($ext)) { $ctx.Response.ContentType = $tipos[$ext] }
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
        $ctx.Response.StatusCode = 404
    }
    $ctx.Response.Close()
}
