[CmdletBinding()]
param([string]$OutputPath, [switch]$Installer, [string]$NsisPath)

$ErrorActionPreference = 'Stop'
$compiler = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
$automation = Join-Path $env:SystemRoot 'Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation\v4.0_3.0.0.0__31bf3856ad364e35\System.Management.Automation.dll'
if (!(Test-Path -LiteralPath $compiler) -or !(Test-Path -LiteralPath $automation)) {
    throw 'Execute o build no Windows PowerShell 5.1 com o .NET Framework instalado.'
}

if (!$OutputPath) { $OutputPath = Join-Path $PSScriptRoot 'dist\Mouse Scroll.exe' }
$output = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
New-Item -ItemType Directory -Path (Split-Path -Parent $output) -Force | Out-Null
$icon = Join-Path $PSScriptRoot 'assets\icon.ico'
$script = Join-Path $PSScriptRoot 'MouseScroll.ps1'
$image = Join-Path $PSScriptRoot 'assets\icon.png'
$source = Join-Path $PSScriptRoot 'MouseScrollLauncher.cs'
$nativeSource = Join-Path $PSScriptRoot 'MouseScroll.Native.cs'
$controlResources = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'assets\controls') -Filter '*.png' | ForEach-Object { '/resource:{0},{1}' -f $_.FullName, $_.Name })

& $compiler /nologo /target:winexe /platform:anycpu /optimize+ /codepage:65001 "/out:$output" "/win32icon:$icon" `
    "/reference:$automation" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Net.Http.dll /reference:System.Web.Extensions.dll `
    "/resource:$script,MouseScroll.ps1" "/resource:$icon,MouseScroll.ico" "/resource:$image,MouseScroll.png" "/resource:$nativeSource,MouseScroll.Native.cs" "/resource:$(Join-Path $PSScriptRoot 'assets\Lucide-LICENSE.txt'),Lucide-LICENSE.txt" @controlResources $source $nativeSource
if ($LASTEXITCODE -ne 0) { throw "Falha ao compilar Mouse Scroll (código $LASTEXITCODE)." }
Get-Item -LiteralPath $output
if ((Get-Item -LiteralPath $output).Length -gt 10000000) { throw 'O executável ultrapassou o limite de 10 MB.' }

if ($Installer) {
    $version = '1.1.0-preview.4'
    $releaseDirectory = Join-Path $PSScriptRoot "release\$version"
    New-Item -ItemType Directory -Path $releaseDirectory -Force | Out-Null
    $installerFile = Join-Path $releaseDirectory 'MouseScroll-Instalar.exe'
    $nsisCandidates = @(
        $NsisPath,
        (Join-Path ${env:ProgramFiles(x86)} 'NSIS\makensis.exe'),
        (Join-Path $env:LOCALAPPDATA 'electron-builder\Cache\nsis-3.0.4.1\nsis-3.0.4.1-1mx3n\makensis.exe')
    )
    $makensis = $nsisCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if (!$makensis) { throw 'Instale o NSIS 3 ou indique seu cache local para gerar o instalador.' }
    & $makensis /V2 /INPUTCHARSET UTF8 "/DPROJECT_DIR=$PSScriptRoot" "/DAPP_EXE=$output" "/DOUTPUT_FILE=$installerFile" (Join-Path $PSScriptRoot 'build\native-installer.nsi')
    if ($LASTEXITCODE -ne 0) { throw "Falha ao gerar instalador (código $LASTEXITCODE)." }
    if ((Get-Item -LiteralPath $installerFile).Length -gt 10000000) { throw 'O instalador ultrapassou o limite de 10 MB.' }
    $checksum = (Get-FileHash -LiteralPath $installerFile -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText("$installerFile.sha256", "$checksum  MouseScroll-Instalar.exe`n", [Text.UTF8Encoding]::new($false))
    Get-Item -LiteralPath $installerFile
}
