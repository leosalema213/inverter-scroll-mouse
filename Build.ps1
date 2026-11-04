[CmdletBinding()]
param([string]$OutputPath)

$ErrorActionPreference = 'Stop'
$compiler = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
$automation = Join-Path $env:SystemRoot 'Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation\v4.0_3.0.0.0__31bf3856ad364e35\System.Management.Automation.dll'
if (!(Test-Path -LiteralPath $compiler) -or !(Test-Path -LiteralPath $automation)) {
    throw 'Execute o build no Windows PowerShell 5.1 com o .NET Framework instalado.'
}

if (!$OutputPath) { $OutputPath = Join-Path $PSScriptRoot 'dist\Mouse Scroll.exe' }
$output = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
New-Item -ItemType Directory -Path (Split-Path -Parent $output) -Force | Out-Null
$icon = Join-Path $PSScriptRoot 'MouseScroll.ico'
$script = Join-Path $PSScriptRoot 'MouseScroll.ps1'
$image = Join-Path $PSScriptRoot 'MouseScroll.png'
$source = Join-Path $PSScriptRoot 'MouseScrollLauncher.cs'

& $compiler /nologo /target:winexe /platform:anycpu /optimize+ /codepage:65001 "/out:$output" "/win32icon:$icon" `
    "/reference:$automation" /reference:System.Windows.Forms.dll `
    "/resource:$script,MouseScroll.ps1" "/resource:$icon,MouseScroll.ico" "/resource:$image,MouseScroll.png" $source
if ($LASTEXITCODE -ne 0) { throw "Falha ao compilar Mouse Scroll (código $LASTEXITCODE)." }
Get-Item -LiteralPath $output
