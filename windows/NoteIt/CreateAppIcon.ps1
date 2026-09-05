$ErrorActionPreference = 'Stop'

$iconPath = Join-Path $PSScriptRoot 'AppIcon.ico'
if (Test-Path $iconPath) {
    Write-Host "App icon already exists: $iconPath"
    return
}

Add-Type -AssemblyName System.Drawing

$bitmap = New-Object System.Drawing.Bitmap(256, 256, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))

$blue = [System.Drawing.Color]::FromArgb(0, 120, 215)
$white = [System.Drawing.Color]::FromArgb(255, 255, 255)
$blueBrush = New-Object System.Drawing.SolidBrush($blue)
$whiteBrush = New-Object System.Drawing.SolidBrush($white)

$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$roundedRect = [System.Drawing.Rectangle]::new(18, 18, 220, 220)
$radius = 42
$path.AddArc($roundedRect.X, $roundedRect.Y, $radius, $radius, 180, 90)
$path.AddArc($roundedRect.Right - $radius, $roundedRect.Y, $radius, $radius, 270, 90)
$path.AddArc($roundedRect.Right - $radius, $roundedRect.Bottom - $radius, $radius, $radius, 0, 90)
$path.AddArc($roundedRect.X, $roundedRect.Bottom - $radius, $radius, $radius, 90, 90)
$path.CloseFigure()
$graphics.FillPath($blueBrush, $path)

$notePath = New-Object System.Drawing.Drawing2D.GraphicsPath
$noteRect = [System.Drawing.Rectangle]::new(58, 64, 140, 130)
$notePath.AddArc($noteRect.X, $noteRect.Y, 18, 18, 180, 90)
$notePath.AddArc($noteRect.Right - 18, $noteRect.Y, 18, 18, 270, 90)
$notePath.AddArc($noteRect.Right - 18, $noteRect.Bottom - 18, 18, 18, 0, 90)
$notePath.AddArc($noteRect.X, $noteRect.Bottom - 18, 18, 18, 90, 90)
$notePath.CloseFigure()
$graphics.FillPath($whiteBrush, $notePath)

$graphics.FillRectangle($blueBrush, 90, 92, 76, 10)
$graphics.FillRectangle($blueBrush, 90, 118, 74, 8)
$graphics.FillRectangle($blueBrush, 90, 134, 66, 8)

$graphics.Dispose()
$icon = [System.Drawing.Icon]::FromHandle($bitmap.GetHicon())
$stream = [System.IO.File]::Open($iconPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
$icon.Save($stream)
$stream.Close()
$icon.Dispose()
$bitmap.Dispose()

Write-Host "Created app icon: $iconPath"
