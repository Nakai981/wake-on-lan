# Rebuild the app's geometric launcher icons without external assets.
Add-Type -AssemblyName System.Drawing
function Write-WakeIcon([string]$Path, [int]$Size) {
    $bitmap = [System.Drawing.Bitmap]::new($Size, $Size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::FromArgb(246,247,242))
    $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(36,116,91), $Size * 0.07)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $graphics.DrawArc($pen, [single]($Size * 0.24), [single]($Size * 0.24), [single]($Size * 0.52), [single]($Size * 0.52), [single](-48), [single](276))
    $graphics.DrawLine($pen, [single]($Size * 0.5), [single]($Size * 0.19), [single]($Size * 0.5), [single]($Size * 0.49))
    $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $pen.Dispose(); $graphics.Dispose(); $bitmap.Dispose()
}
$projectRoot = Split-Path $PSScriptRoot -Parent
$densities = @{ 'mdpi' = 48; 'hdpi' = 72; 'xhdpi' = 96; 'xxhdpi' = 144; 'xxxhdpi' = 192 }
foreach ($density in $densities.Keys) {
    Write-WakeIcon (Join-Path $projectRoot "android/app/src/main/res/mipmap-$density/ic_launcher.png") $densities[$density]
}
$iconRoot = Join-Path $projectRoot 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
$catalog = Get-Content (Join-Path $iconRoot 'Contents.json') -Raw | ConvertFrom-Json
foreach ($entry in $catalog.images) {
    if ($entry.filename) {
        $size = [double]($entry.size.Split('x')[0]) * [double]($entry.scale.Replace('x', ''))
        Write-WakeIcon (Join-Path $iconRoot $entry.filename) ([int]$size)
    }
}
