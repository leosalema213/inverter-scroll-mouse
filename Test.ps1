[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$testDirectory = Join-Path $PSScriptRoot 'test-output\native-tests'
New-Item -ItemType Directory -Path $testDirectory -Force | Out-Null
$executable = Join-Path $testDirectory 'NativeTests.exe'
& $compiler /nologo /target:exe /codepage:65001 "/out:$executable" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Net.Http.dll /reference:System.Web.Extensions.dll (Join-Path $PSScriptRoot 'MouseScroll.Native.cs') (Join-Path $PSScriptRoot 'tests\NativeTests.cs')
if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar os testes nativos.' }
& $executable (Join-Path $testDirectory ([Guid]::NewGuid().ToString('N')))
if ($LASTEXITCODE -ne 0) { throw 'Os testes nativos falharam.' }
