[CmdletBinding()]
param(
    [ValidateSet('Interface', 'List', 'Apply', 'StartupApply', 'EnableStartup', 'DisableStartup')]
    [string]$Mode = 'Interface',
    [ValidateSet(0, 1)]
    [int]$Direction = 1,
    [string]$RequestingSid
)

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$sid = $identity.User.Value
$taskName = "MouseScroll-$sid"
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$pnpUtil = Join-Path $env:SystemRoot 'System32\pnputil.exe'
$logPath = Join-Path $env:LOCALAPPDATA 'MouseScroll.log'
$installDir = Join-Path $env:ProgramFiles "MouseScroll\$sid"
$installedScript = Join-Path $installDir 'MouseScroll.ps1'

function Get-Mice {
    $root = 'HKLM:\SYSTEM\CurrentControlSet\Enum'
    $mouseClass = '{4d36e96f-e325-11ce-bfc1-08002be10318}'
    foreach ($bus in Get-ChildItem -LiteralPath $root) {
        foreach ($device in Get-ChildItem -LiteralPath $bus.PSPath -ErrorAction SilentlyContinue) {
            foreach ($instance in Get-ChildItem -LiteralPath $device.PSPath -ErrorAction SilentlyContinue) {
                $properties = Get-ItemProperty -LiteralPath $instance.PSPath -ErrorAction SilentlyContinue
                if ($properties.ClassGUID -ne $mouseClass) { continue }
                $parameters = Join-Path $instance.PSPath 'Device Parameters'
                $wheel = (Get-ItemProperty -LiteralPath $parameters -ErrorAction SilentlyContinue).FlipFlopWheel
                [pscustomobject]@{
                    InstanceId = "$($bus.PSChildName)\$($device.PSChildName)\$($instance.PSChildName)"
                    Driver = $properties.Service
                    Parameters = $parameters
                    Direction = $wheel
                    Supported = ($properties.Service -eq 'mouhid' -or $null -ne $wheel)
                }
            }
        }
    }
}

function Set-MouseDirection {
    $connected = @(& $pnpUtil /enum-devices /class Mouse /connected)
    $canDetectConnected = $LASTEXITCODE -eq 0
    $changed = 0
    $supported = 0
    $needsReconnect = $false
    $failed = [Collections.Generic.List[string]]::new()
    foreach ($mouse in Get-Mice) {
        if (!$mouse.Supported) { continue }
        $supported++
        if ($null -ne $mouse.Direction -and $mouse.Direction -eq $Direction) { continue }
        try {
            if (!(Test-Path -LiteralPath $mouse.Parameters)) {
                New-Item -Path $mouse.Parameters | Out-Null
            }
            New-ItemProperty -LiteralPath $mouse.Parameters -Name FlipFlopWheel -PropertyType DWord -Value $Direction -Force | Out-Null
            if ((Get-ItemPropertyValue -LiteralPath $mouse.Parameters -Name FlipFlopWheel) -ne $Direction) {
                throw 'O valor gravado diverge do solicitado.'
            }
            $changed++
        } catch {
            $failed.Add($mouse.InstanceId)
            continue
        }
        if (!$canDetectConnected) {
            $needsReconnect = $true
            continue
        }
        $pattern = ':\s*' + [regex]::Escape($mouse.InstanceId) + '\s*$'
        if ($connected -match $pattern) {
            & $pnpUtil /restart-device $mouse.InstanceId | Out-Null
            if ($LASTEXITCODE -ne 0) { $needsReconnect = $true }
        }
    }
    $summary = "Registros compatíveis: $supported. Alterados: $changed."
    if ($needsReconnect) { $summary += ' Reconecte o mouse ou reinicie o Windows para aplicar.' }
    if ($failed.Count) { $summary += " Falha em: $($failed -join ', ')." }
    Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format s) $summary" -Encoding UTF8
    if ($failed.Count) { throw $summary }
    $summary
}

function Set-Startup {
    if ($Mode -eq 'DisableStartup') {
        if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        }
        return
    }

    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    Copy-Item -LiteralPath $PSCommandPath -Destination $installedScript -Force
    $arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Mode StartupApply -Direction {1}' -f $installedScript, $Direction
    $action = New-ScheduledTaskAction -Execute $windowsPowerShell -Argument $arguments
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
    $principal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
}

if ($Mode -eq 'List') {
    Get-Mice
    return
}

if ($Mode -ne 'Interface') {
    try {
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'Esta ação precisa de permissão de administrador.'
        }
        if ($RequestingSid -and $RequestingSid -ne $sid -and $Mode -in 'EnableStartup', 'DisableStartup') {
            throw 'Para configurar a inicialização, entre no Windows com uma conta administradora.'
        }
        if ($Mode -in 'Apply', 'StartupApply') {
            $summary = Set-MouseDirection
            if ($Mode -eq 'Apply') {
                Add-Type -AssemblyName System.Windows.Forms
                [void][Windows.Forms.MessageBox]::Show($summary, 'Mouse Scroll')
            }
        } else {
            Set-Startup
        }
        exit 0
    } catch {
        if ($Mode -eq 'StartupApply') {
            Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format s) $_" -Encoding UTF8
        } else {
            Add-Type -AssemblyName System.Windows.Forms
            [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Mouse Scroll')
        }
        exit 1
    }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;

public static class MouseScrollShell
{
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
}
'@
[void][MouseScrollShell]::SetCurrentProcessExplicitAppUserModelID('LeoSalema.MouseScroll')
[Windows.Forms.Application]::EnableVisualStyles()

$surface = [Drawing.Color]::FromArgb(241, 245, 252)
$ink = [Drawing.Color]::FromArgb(22, 34, 58)
$muted = [Drawing.Color]::FromArgb(73, 89, 117)
$accent = [Drawing.Color]::FromArgb(71, 72, 203)
$white = [Drawing.Color]::White

$form = [Windows.Forms.Form]@{
    Text = 'Mouse Scroll'
    ClientSize = [Drawing.Size]::new(820, 540)
    StartPosition = 'CenterScreen'
    FormBorderStyle = 'FixedSingle'
    MaximizeBox = $false
    Font = [Drawing.Font]::new('Segoe UI', 10)
    BackColor = $surface
    ForeColor = $ink
}
$icon = [Drawing.Icon]::new((Join-Path $PSScriptRoot 'MouseScroll.ico'))
$form.Icon = $icon
$header = [Windows.Forms.Panel]@{ Left = 0; Top = 0; Width = 820; Height = 108; BackColor = $ink; ForeColor = $white }
$mark = [Windows.Forms.PictureBox]@{
    Left = 24; Top = 22; Width = 64; Height = 64; SizeMode = 'Zoom'
    Image = [Drawing.Bitmap]::new((Join-Path $PSScriptRoot 'MouseScroll.png'))
}
$title = [Windows.Forms.Label]@{
    Text = 'Mouse Scroll'; Left = 104; Top = 18; Width = 660; Height = 43
    Font = [Drawing.Font]::new('Segoe UI', 23, [Drawing.FontStyle]::Bold)
}
$subtitle = [Windows.Forms.Label]@{
    Text = 'Ajuste a direção da roda em conexões com e sem fio.'
    Left = 107; Top = 66; Width = 650; Height = 24; ForeColor = [Drawing.Color]::FromArgb(207, 219, 243)
}
$header.Controls.AddRange(@($mark, $title, $subtitle))
$devicesTitle = [Windows.Forms.Label]@{
    Text = 'Mouses encontrados'; Left = 24; Top = 126; Width = 490; Height = 28
    Font = [Drawing.Font]::new('Segoe UI', 12, [Drawing.FontStyle]::Bold)
}
$list = [Windows.Forms.ListView]@{
    Left = 24; Top = 165; Width = 772; Height = 194
    View = 'Details'; FullRowSelect = $true; BorderStyle = 'FixedSingle'; ForeColor = $ink
}
[void]$list.Columns.Add('Dispositivo no Windows', 505)
[void]$list.Columns.Add('Driver', 100)
[void]$list.Columns.Add('Direção', 130)
$status = [Windows.Forms.Label]@{
    Left = 24; Top = 367; Width = 772; Height = 25; ForeColor = $muted
}
$settings = [Windows.Forms.Panel]@{ Left = 24; Top = 400; Width = 772; Height = 111; BackColor = $white }
$directionLabel = [Windows.Forms.Label]@{ Text = 'Direção da rolagem'; Left = 14; Top = 9; Width = 310; Height = 26 }
$startupLabel = [Windows.Forms.Label]@{ Text = 'Início com o Windows'; Left = 388; Top = 9; Width = 360; Height = 26 }
$directionBox = [Windows.Forms.ComboBox]@{
    Left = 14; Top = 45; Width = 126; DropDownStyle = 'DropDownList'
}
[void]$directionBox.Items.AddRange(@('Invertida', 'Padrão'))
$directionBox.SelectedIndex = 0
$settings.Controls.AddRange(@($directionLabel, $startupLabel, $directionBox))
$form.Controls.AddRange(@($header, $devicesTitle, $list, $status, $settings))

function Update-Interface {
    $list.Items.Clear()
    foreach ($mouse in Get-Mice) {
        $label = if (!$mouse.Supported) { 'Sem suporte' } elseif ($mouse.Direction -eq 1) { 'Invertida' } else { 'Padrão' }
        $item = $list.Items.Add($mouse.InstanceId)
        if ($item.Index % 2 -eq 1) { $item.BackColor = $surface }
        [void]$item.SubItems.Add([string]$mouse.Driver)
        [void]$item.SubItems.Add($label)
    }
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    $startup = if ($task -and $task.State -ne 'Disabled') {
        if ($task.Actions.Arguments -match '-Direction 1(?:\s|$)') { 'Ativa (invertida)' } else { 'Ativa (padrão)' }
    } else { 'Desativada' }
    $status.Text = "Mouses encontrados: $($list.Items.Count)    |    Iniciar com Windows: $startup"
}

function Invoke-ElevatedAction([string]$action) {
    $selected = if ($directionBox.SelectedIndex -eq 0) { 1 } else { 0 }
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode {1} -Direction {2} -RequestingSid {3}' -f $PSCommandPath, $action, $selected, $sid
    try {
        Start-Process -FilePath $windowsPowerShell -Verb RunAs -WindowStyle Hidden -ArgumentList $arguments -Wait
    } catch {
        [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Mouse Scroll')
    }
    Update-Interface
}

function Add-Button($parent, [string]$label, [int]$left, [int]$top, [int]$width, [scriptblock]$click, [switch]$primary) {
    $button = [Windows.Forms.Button]@{
        Text = $label; Left = $left; Top = $top; Width = $width; Height = 34
        FlatStyle = 'Flat'; BackColor = $white; ForeColor = $ink
    }
    $button.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(194, 205, 226)
    if ($primary) {
        $button.BackColor = $accent
        $button.ForeColor = $white
        $button.FlatAppearance.BorderSize = 0
    }
    $button.Add_Click($click)
    $parent.Controls.Add($button)
}

Add-Button $form 'Atualizar lista' 666 122 130 { Update-Interface }
Add-Button $settings 'Aplicar a todos' 150 41 160 { Invoke-ElevatedAction Apply } -Primary
Add-Button $settings 'Ativar' 388 41 102 { Invoke-ElevatedAction EnableStartup }
Add-Button $settings 'Desativar' 500 41 102 { Invoke-ElevatedAction DisableStartup }
$settings.Controls.Add([Windows.Forms.Label]@{
    Text = 'Usa a direção selecionada ao clicar em Ativar.'
    Left = 388; Top = 81; Width = 370; Height = 23; ForeColor = $muted
})
$form.Add_Shown({ Update-Interface })
[void]$form.ShowDialog()
$mark.Image.Dispose()
$form.Dispose()
$icon.Dispose()
