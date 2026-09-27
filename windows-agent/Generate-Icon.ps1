# Geometric power mark. Generate multi-resolution Windows icon without external assets.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$assetPath = Join-Path $PSScriptRoot 'assets'
New-Item -ItemType Directory -Path $assetPath -Force | Out-Null
$frames = @()
foreach ($size in @(16, 20, 24, 32, 48, 64, 128, 256)) {
    $canvas = [System.Drawing.Bitmap]::new(1024, 1024)
    $g = [System.Drawing.Graphics]::FromImage($canvas)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $path.AddArc(32, 32, 320, 320, 180, 90)
    $path.AddArc(672, 32, 320, 320, 270, 90)
    $path.AddArc(672, 672, 320, 320, 0, 90)
    $path.AddArc(32, 672, 320, 320, 90, 90)
    $path.CloseFigure()
    $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
        [System.Drawing.Point]::new(0, 0), [System.Drawing.Point]::new(1024, 1024),
        [System.Drawing.Color]::FromArgb(59, 130, 246), [System.Drawing.Color]::FromArgb(29, 78, 216))
    $g.FillPath($brush, $path)
    $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::White, 88)
    $pen.StartCap = $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawArc($pen, 264, 280, 496, 496, -48, 276)
    $g.DrawLine($pen, 512, 230, 512, 495)
    $bitmap = [System.Drawing.Bitmap]::new($size, $size)
    $scaled = [System.Drawing.Graphics]::FromImage($bitmap)
    $scaled.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $scaled.DrawImage($canvas, 0, 0, $size, $size)
    $stream = [System.IO.MemoryStream]::new()
    $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    $frames += @{ Size = $size; Bytes = $stream.ToArray() }
    if ($size -eq 256) { $bitmap.Save((Join-Path $assetPath 'WakeMyPcAgent.png'), [System.Drawing.Imaging.ImageFormat]::Png) }
    $stream.Dispose(); $scaled.Dispose(); $bitmap.Dispose()
    $pen.Dispose(); $brush.Dispose(); $path.Dispose(); $g.Dispose(); $canvas.Dispose()
}
$file = [System.IO.File]::Create((Join-Path $assetPath 'WakeMyPcAgent.ico'))
$writer = [System.IO.BinaryWriter]::new($file)
try {
    $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$frames.Count)
    $offset = 6 + 16 * $frames.Count
    foreach ($frame in $frames) {
        $dimension = if ($frame.Size -eq 256) { 0 } else { $frame.Size }
        $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
        $writer.Write([byte]0); $writer.Write([byte]0)
        $writer.Write([uint16]1); $writer.Write([uint16]32)
        $writer.Write([uint32]$frame.Bytes.Length); $writer.Write([uint32]$offset)
        $offset += $frame.Bytes.Length
    }
    foreach ($frame in $frames) { $writer.Write([byte[]]$frame.Bytes) }
} finally { $writer.Dispose(); $file.Dispose() }
