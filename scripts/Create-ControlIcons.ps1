# Exact Sun, Moon and Settings geometry from Organon's lucide-react 1.62.0.
# Lucide/Feather licenses: assets/Lucide-LICENSE.txt. WPF is used only at build time.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationCore, WindowsBase
$paths = @{
    sun = @('M12 2v2', 'M12 20v2', 'm4.93 4.93 1.41 1.41', 'm17.66 17.66 1.41 1.41', 'M2 12h2', 'M20 12h2', 'm6.34 17.66-1.41 1.41', 'm19.07 4.93-1.41 1.41')
    moon = @('M20.985 12.486a9 9 0 1 1-9.473-9.472c.405-.022.617.46.402.803a6 6 0 0 0 8.268 8.268c.344-.215.825-.004.803.401')
    settings = @('M9.671 4.136a2.34 2.34 0 0 1 4.659 0 2.34 2.34 0 0 0 3.319 1.915 2.34 2.34 0 0 1 2.33 4.033 2.34 2.34 0 0 0 0 3.831 2.34 2.34 0 0 1-2.33 4.033 2.34 2.34 0 0 0-3.319 1.915 2.34 2.34 0 0 1-4.659 0 2.34 2.34 0 0 0-3.32-1.915 2.34 2.34 0 0 1-2.33-4.033 2.34 2.34 0 0 0 0-3.831A2.34 2.34 0 0 1 6.35 6.051a2.34 2.34 0 0 0 3.319-1.915')
}
$folder = Join-Path $PSScriptRoot '..\assets\controls'
New-Item -ItemType Directory -Path $folder -Force | Out-Null
foreach ($theme in 'dark', 'light') {
    $color = if ($theme -eq 'dark') { '#999999' } else { '#7a7b88' }
    $brush = [Windows.Media.BrushConverter]::new().ConvertFromString($color)
    $pen = [Windows.Media.Pen]::new($brush, 2)
    $pen.StartLineCap = $pen.EndLineCap = [Windows.Media.PenLineCap]::Round
    $pen.LineJoin = [Windows.Media.PenLineJoin]::Round
    foreach ($name in $paths.Keys) {
        $visual = [Windows.Media.DrawingVisual]::new()
        $drawing = $visual.RenderOpen()
        $drawing.PushTransform([Windows.Media.ScaleTransform]::new(0.75, 0.75))
        foreach ($path in $paths[$name]) { $drawing.DrawGeometry($null, $pen, [Windows.Media.Geometry]::Parse($path)) }
        if ($name -ne 'moon') {
            $radius = if ($name -eq 'sun') { 4 } else { 3 }
            $drawing.DrawEllipse($null, $pen, [Windows.Point]::new(12,12), $radius, $radius)
        }
        $drawing.Pop(); $drawing.Close()
        $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new(18,18,96,96,[Windows.Media.PixelFormats]::Pbgra32)
        $bitmap.Render($visual)
        $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
        $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $stream = [IO.File]::Create((Join-Path $folder "$name-$theme.png"))
        try { $encoder.Save($stream) } finally { $stream.Dispose() }
    }
}
