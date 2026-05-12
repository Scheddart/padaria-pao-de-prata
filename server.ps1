$root = 'C:\Users\kauas\padaria-pao-de-prata'
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add('http://localhost:3000/')
$listener.Start()
Write-Host 'Servidor rodando em http://localhost:3000'

while ($listener.IsListening) {
    $ctx  = $listener.GetContext()
    $req  = $ctx.Request
    $res  = $ctx.Response

    $urlPath = $req.Url.LocalPath
    if ($urlPath -eq '/') { $urlPath = '/index.html' }
    $file = Join-Path $root $urlPath.TrimStart('/').Replace('/', '\')

    if (!(Test-Path $file -PathType Leaf)) {
        $res.StatusCode = 404
        $res.Close()
        continue
    }

    $ext  = [IO.Path]::GetExtension($file)
    $mime = switch ($ext) {
        '.html' { 'text/html; charset=utf-8' }
        '.js'   { 'application/javascript' }
        '.css'  { 'text/css' }
        '.mp4'  { 'video/mp4' }
        '.json' { 'application/json' }
        default { 'application/octet-stream' }
    }

    $res.ContentType = $mime
    $res.Headers.Add('Accept-Ranges', 'bytes')
    $res.Headers.Add('Cache-Control', 'no-cache')

    $totalLen = (Get-Item $file).Length
    $rangeHdr = $req.Headers['Range']

    if ($rangeHdr -and $rangeHdr -match 'bytes=(\d+)-(\d*)') {
        $start = [long]$Matches[1]
        $end   = if ($Matches[2] -ne '') { [long]$Matches[2] } else { $totalLen - 1 }
        if ($end -ge $totalLen) { $end = $totalLen - 1 }
        $len   = $end - $start + 1

        $res.StatusCode = 206
        $res.Headers.Add('Content-Range', "bytes $start-$end/$totalLen")
        $res.ContentLength64 = $len

        $fs  = [IO.FileStream]::new($file, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $fs.Seek($start, [IO.SeekOrigin]::Begin) | Out-Null
        $buf  = New-Object byte[] 81920
        $rem  = $len
        while ($rem -gt 0) {
            $toRead = [Math]::Min($rem, $buf.Length)
            $read   = $fs.Read($buf, 0, $toRead)
            if ($read -eq 0) { break }
            try { $res.OutputStream.Write($buf, 0, $read) } catch { break }
            $rem -= $read
        }
        $fs.Dispose()
    } else {
        $res.ContentLength64 = $totalLen
        $fs  = [IO.FileStream]::new($file, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $buf = New-Object byte[] 81920
        while (($read = $fs.Read($buf, 0, $buf.Length)) -gt 0) {
            try { $res.OutputStream.Write($buf, 0, $read) } catch { break }
        }
        $fs.Dispose()
    }

    try { $res.Close() } catch {}
}
