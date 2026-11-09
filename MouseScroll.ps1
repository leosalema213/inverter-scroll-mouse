[CmdletBinding()]
param(
    [ValidateSet('Interface', 'List', 'Status', 'Apply', 'StartupApply', 'EnableStartup', 'DisableStartup')]
    [string]$Mode = 'Interface',
    [ValidateSet(0, 1)]
    [int]$Direction = 1,
    [string]$RequestingSid,
    [switch]$Quiet,
    [string]$ProfileDirectory,
    [string]$CaptureDirectory
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

if ($Mode -eq 'Status') {
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    $startupDirection = if ($task -and $task.Actions.Arguments -match '-Direction 1(?:\s|$)') { 1 } else { 0 }
    [pscustomobject]@{
        Sid = $sid
        Mice = @(Get-Mice)
        StartupEnabled = [bool]($task -and $task.State -ne 'Disabled')
        StartupDirection = $startupDirection
    } | ConvertTo-Json -Depth 5 -Compress
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
            if ($Mode -eq 'Apply' -and !$Quiet) {
                Add-Type -AssemblyName System.Windows.Forms
                [void][Windows.Forms.MessageBox]::Show($summary, 'Mouse Scroll')
            }
        } else {
            Set-Startup
        }
        exit 0
    } catch {
        if ($Mode -eq 'StartupApply' -or $Quiet) {
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
if (!('MouseScrollUpdates' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'MouseScroll.Native.cs') -ReferencedAssemblies System.dll, System.Core.dll, System.Windows.Forms.dll, System.Drawing.dll, System.Net.Http.dll, System.Web.Extensions.dll
}
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

$surface = [Drawing.ColorTranslator]::FromHtml('#101010')
$ink = [Drawing.ColorTranslator]::FromHtml('#ededed')
$muted = [Drawing.ColorTranslator]::FromHtml('#999999')
$accent = [Drawing.ColorTranslator]::FromHtml('#e5e5e5')
$white = [Drawing.ColorTranslator]::FromHtml('#191919')
if (!$ProfileDirectory) { $ProfileDirectory = Join-Path $env:APPDATA 'mouse-scroll' }
$preferencesPath = Join-Path $ProfileDirectory 'preferences.json'
$preferences = @{ version = 1; theme = 'system'; direction = 1 }
if (Test-Path -LiteralPath $preferencesPath) {
    $saved = Get-Content -LiteralPath $preferencesPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($saved.version -ne 1 -or $saved.theme -notin 'light', 'dark', 'system' -or $saved.direction -notin 0, 1) {
        throw 'As preferências são inválidas. O arquivo original foi preservado.'
    }
    $preferences.theme = $saved.theme
    $preferences.direction = [int]$saved.direction
}
$updates = [MouseScrollUpdates]::new((Join-Path $ProfileDirectory 'updates'))
$controlImages = @{}
$controlAssetDirectory = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'assets\controls')) { Join-Path $PSScriptRoot 'assets\controls' } else { $PSScriptRoot }
foreach ($name in 'sun', 'moon', 'settings') {
    foreach ($theme in 'dark', 'light') { $controlImages["$name-$theme"] = [Drawing.Bitmap]::new((Join-Path $controlAssetDirectory "$name-$theme.png")) }
}
$script:lastUpdateState = ''
$script:dismissedUpdate = ''
$script:updateDialog = $null
$script:configDialog = $null
$script:adminBusy = $false

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
$iconPath = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'assets\icon.ico')) { Join-Path $PSScriptRoot 'assets\icon.ico' } else { Join-Path $PSScriptRoot 'MouseScroll.ico' }
$imagePath = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'assets\icon.png')) { Join-Path $PSScriptRoot 'assets\icon.png' } else { Join-Path $PSScriptRoot 'MouseScroll.png' }
$icon = [Drawing.Icon]::new($iconPath)
$form.Icon = $icon
$header = [Windows.Forms.Panel]@{ Left = 0; Top = 0; Width = 820; Height = 108 }
$mark = [Windows.Forms.PictureBox]@{
    Left = 24; Top = 22; Width = 64; Height = 64; SizeMode = 'Zoom'
    Image = [Drawing.Bitmap]::new($imagePath)
}
$title = [Windows.Forms.Label]@{
    Text = 'Mouse Scroll'; Left = 104; Top = 18; Width = 550; Height = 43
    Font = [Drawing.Font]::new('Segoe UI', 23, [Drawing.FontStyle]::Bold)
}
$subtitle = [Windows.Forms.Label]@{
    Text = 'Ajuste a direção da roda em conexões com e sem fio.'
    Left = 107; Top = 66; Width = 620; Height = 24
}
$header.Controls.AddRange(@($mark, $title, $subtitle))
$devicesTitle = [Windows.Forms.Label]@{
    Text = 'Mouses encontrados'; Left = 24; Top = 126; Width = 490; Height = 28
    Font = [Drawing.Font]::new('Segoe UI', 12, [Drawing.FontStyle]::Bold)
}
$list = [MouseScrollDeviceList]@{
    Left = 24; Top = 165; Width = 772; Height = 194
    View = 'Details'; FullRowSelect = $true; BorderStyle = 'FixedSingle'; ForeColor = $ink
}
[void]$list.Columns.Add('Dispositivo no Windows', 505)
[void]$list.Columns.Add('Driver', 100)
[void]$list.Columns.Add('Direção', 163)
$status = [Windows.Forms.Label]@{
    Left = 24; Top = 367; Width = 772; Height = 25; ForeColor = $muted
}
$settings = [Windows.Forms.Panel]@{ Left = 24; Top = 400; Width = 772; Height = 111; BackColor = $white }
$directionLabel = [Windows.Forms.Label]@{ Text = 'Direção da rolagem'; Left = 14; Top = 9; Width = 310; Height = 26 }
$startupLabel = [Windows.Forms.Label]@{ Text = 'Início com o Windows'; Left = 388; Top = 9; Width = 360; Height = 26 }
$directionBox = [MouseScrollComboBox]@{
    Left = 14; Top = 41; Width = 126
}
[void]$directionBox.Items.AddRange(@('Invertida', 'Padrão'))
$directionBox.SelectedIndex = if ($preferences.direction -eq 1) { 0 } else { 1 }
$directionBox.ItemHeight += 34 - $directionBox.Height
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
        Save-Preferences
        Save-ConfigurationSnapshot
        $script:adminBusy = $true
        $settings.Enabled = $false
        Start-Process -FilePath $windowsPowerShell -Verb RunAs -WindowStyle Hidden -ArgumentList $arguments -Wait
    } catch {
        [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Mouse Scroll')
    } finally { $script:adminBusy = $false; $settings.Enabled = $true }
    Update-Interface
}

function Add-Button($parent, [string]$label, [int]$left, [int]$top, [int]$width, [scriptblock]$click, [switch]$primary) {
    $button = [Windows.Forms.Button]@{
        Text = $label; Left = $left; Top = $top; Width = $width; Height = 34
        FlatStyle = 'Flat'; BackColor = $white; ForeColor = $ink; Tag = 'secondary'
    }
    $button.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(194, 205, 226)
    if ($primary) {
        $button.Tag = 'primary'
        $button.BackColor = $accent
        $button.ForeColor = $white
        $button.FlatAppearance.BorderSize = 0
    }
    $button.Add_Click($click)
    $parent.Controls.Add($button)
}

function Save-Preferences {
    $preferences.direction = if ($directionBox.SelectedIndex -eq 0) { 1 } else { 0 }
    [MouseScrollPreferences]::Save($preferencesPath, ($preferences | ConvertTo-Json))
}

function Save-ConfigurationSnapshot {
    $folder = Join-Path $ProfileDirectory 'backups'
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    if ((Get-Item -LiteralPath $folder).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'A pasta de cópias não pode ser um link.' }
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    $snapshot = @{ version = 1; createdAt = [DateTime]::UtcNow.ToString('o'); preferences = $preferences; Sid = $sid; Mice = @(Get-Mice); StartupEnabled = [bool]$task; StartupArguments = [string]$task.Actions.Arguments }
    $file = Join-Path $folder (([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH-mm-ss.fffffffZ')) + '.json')
    $snapshot | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $file -Encoding UTF8
    Get-ChildItem -LiteralPath $folder -File | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}T[\d.\-]+Z\.json$' -and !($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } |
        Sort-Object Name -Descending | Select-Object -Skip 20 | ForEach-Object { Remove-Item -LiteralPath $_.FullName }
}

function Set-ControlTheme($parent) {
    foreach ($control in $parent.Controls) {
        $control.ForeColor = $ink
        if ($control -is [Windows.Forms.Button]) {
            if ($control.Tag -eq 'primary') { $control.BackColor = $accent; $control.ForeColor = $primaryInk }
            else { $control.BackColor = $white; $control.FlatAppearance.BorderColor = $line }
        } elseif ($control -is [Windows.Forms.ComboBox]) { $control.BackColor = $white }
        elseif ($control -is [Windows.Forms.Panel]) { $control.BackColor = $white }
        Set-ControlTheme $control
    }
}

function Set-InterfaceTheme {
    $dark = $preferences.theme -eq 'dark'
    if ($preferences.theme -eq 'system') {
        $system = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction SilentlyContinue
        $dark = $system.AppsUseLightTheme -eq 0
    }
    $script:darkTheme = $dark
    $colors = if ($dark) {
        @('#101010', '#ededed', '#999999', '#e5e5e5', '#191919', '#171717', '#343434', '#141414', '#f5edd9', '#222222', '#353535')
    } else {
        @('#f6f7f9', '#282938', '#7a7b88', '#7460d8', '#ffffff', '#ffffff', '#dedee6', '#f1f1ef', '#292824', '#f7f7fa', '#e6e0f7')
    }
    $script:surface, $script:ink, $script:muted, $script:accent, $script:white, $script:primaryInk, $script:line, $script:headerColor, $script:brandColor, $script:alternate, $script:selection = @($colors | ForEach-Object { [Drawing.ColorTranslator]::FromHtml($_) })
    $form.BackColor = $surface; $form.ForeColor = $ink
    Set-ControlTheme $form
    $header.BackColor = $headerColor; $title.ForeColor = $brandColor; $subtitle.ForeColor = $muted
    $status.ForeColor = $muted
    $list.BackColor = $white; $list.ForeColor = $ink
    $list.HeaderColor = $headerColor; $list.HeaderTextColor = $muted
    $list.AlternateColor = $alternate; $list.SelectionColor = $selection; $list.Invalidate()
    $startupHint.ForeColor = $muted
    $iconTheme = if ($dark) { 'dark' } else { 'light' }
    $themeButton.Image = $controlImages[$(if ($dark) { 'sun-dark' } else { 'moon-light' })]
    $configButton.Image = $controlImages["settings-$iconTheme"]
    $themeButton.BackColor = $headerColor; $configButton.BackColor = $headerColor
    $directionBox.BorderColor = $line; $directionBox.Invalidate()
    $themeButton.AccessibleName = if ($dark) { 'Usar tema claro' } else { 'Usar tema escuro' }
    foreach ($dialog in @($script:configDialog, $script:updateDialog)) {
        if ($dialog -and !$dialog.IsDisposed) { $dialog.BackColor = $surface; Set-ControlTheme $dialog }
    }
}

function New-AppDialog([string]$titleText, [int]$height) {
    $dialog = [Windows.Forms.Form]@{
        Text = $titleText; ClientSize = [Drawing.Size]::new(480, $height)
        StartPosition = 'CenterParent'; FormBorderStyle = 'FixedDialog'; MaximizeBox = $false; MinimizeBox = $false
        Font = $form.Font; Icon = $icon; BackColor = $surface; ForeColor = $ink; ShowInTaskbar = $false
    }
    return $dialog
}

function Show-UpdateDialog {
    if ($script:updateDialog -and !$script:updateDialog.IsDisposed) { $script:updateDialog.Activate(); return }
    $script:updateDialog = New-AppDialog 'Atualização do Mouse Scroll' 220
    $script:updateHeading = [Windows.Forms.Label]@{ Left = 22; Top = 20; Width = 430; Height = 26; Font = [Drawing.Font]::new('Segoe UI', 12, [Drawing.FontStyle]::Bold) }
    $script:updateBody = [Windows.Forms.Label]@{ Left = 22; Top = 57; Width = 430; Height = 64 }
    $script:updateProgress = [Windows.Forms.ProgressBar]@{ Left = 22; Top = 125; Width = 430; Height = 8; Maximum = 100 }
    $script:updateDialog.Controls.AddRange(@($script:updateHeading, $script:updateBody, $script:updateProgress))
    Add-Button $script:updateDialog 'Depois' 170 164 110 { $script:dismissedUpdate = $updates.State.Version; $script:updateDialog.Close() }
    Add-Button $script:updateDialog 'Baixar atualização' 290 164 162 {
        $current = $updates.State
        if ($current.Status -eq 'ready') {
            if ($script:adminBusy) { return }
            if ($updates.Install()) { $script:updateDialog.Close(); if ($script:configDialog) { $script:configDialog.Close() }; $form.Close() }
        } elseif ($current.Status -eq 'error') { $updates.Check() }
        else { $updates.Download() }
    } -Primary
    $script:updateAction = $script:updateDialog.Controls[$script:updateDialog.Controls.Count - 1]
    $script:updateDialog.Add_FormClosing({ $script:dismissedUpdate = $updates.State.Version })
    Set-InterfaceTheme
    Update-UpdateControls
    [void]$script:updateDialog.ShowDialog($form)
    $script:updateDialog.Dispose(); $script:updateDialog = $null
}

function Update-UpdateControls {
    $current = $updates.State
    if ($script:configDialog -and !$script:configDialog.IsDisposed) {
        $script:updatesStatus.Text = if ($current.Message) { $current.Message } else { 'Verificação automática ao abrir o aplicativo.' }
        $script:checkUpdates.Enabled = $current.Status -notin 'checking', 'installing'
        $script:checkUpdates.Text = if ($current.Status -in 'available', 'downloading', 'ready') { 'Ver atualização' } else { 'Verificar atualização' }
    }
    if ($script:updateDialog -and !$script:updateDialog.IsDisposed) {
        $script:updateHeading.Text = if ($current.Status -eq 'ready') { 'Pronto para atualizar' } elseif ($current.Status -eq 'error') { 'Não foi possível atualizar' } else { 'Nova versão disponível' }
        $script:updateBody.Text = if ($current.Status -eq 'ready') { "Mouse Scroll $($current.Version). O aplicativo será fechado e reaberto. Suas configurações serão mantidas." } elseif ($current.Status -eq 'available') { "Mouse Scroll $([MouseScrollInfo]::Version) → $($current.Version). Deseja baixar a atualização?" } else { $current.Message }
        $script:updateProgress.Visible = $current.Status -eq 'downloading'
        $script:updateProgress.Value = [Math]::Min(100, [Math]::Max(0, $current.Percent))
        $script:updateAction.Enabled = $current.Status -in 'available', 'ready', 'error'
        $script:updateAction.Text = if ($current.Status -eq 'ready') { 'Atualizar e reiniciar' } elseif ($current.Status -eq 'error') { 'Tentar novamente' } else { 'Baixar atualização' }
    }
}

function Show-Configuration {
    $script:configDialog = New-AppDialog 'Configurações' 230
    $versionLabel = [Windows.Forms.Label]@{ Text = "Mouse Scroll $([MouseScrollInfo]::Version)"; Left = 22; Top = 22; Width = 430; Height = 30; Font = [Drawing.Font]::new('Segoe UI', 12, [Drawing.FontStyle]::Bold) }
    $script:updatesStatus = [Windows.Forms.Label]@{ Left = 22; Top = 66; Width = 430; Height = 58 }
    $script:configDialog.Controls.AddRange(@($versionLabel, $script:updatesStatus))
    Add-Button $script:configDialog 'Verificar atualização' 22 140 190 {
        if ($updates.State.Status -in 'available', 'downloading', 'ready') { Show-UpdateDialog } else { $updates.Check() }
    }
    $script:checkUpdates = $script:configDialog.Controls[$script:configDialog.Controls.Count - 1]
    Add-Button $script:configDialog 'Concluir' 342 140 110 { $script:configDialog.Close() }
    $script:configDialog.CancelButton = $script:configDialog.Controls[$script:configDialog.Controls.Count - 1]
    if ($CaptureDirectory) {
        $configCaptureTimer = [Windows.Forms.Timer]@{ Interval = 350 }
        $configCaptureTimer.Add_Tick({
            $configCaptureTimer.Stop()
            $bitmap = [Drawing.Bitmap]::new($script:configDialog.Width, $script:configDialog.Height)
            $script:configDialog.DrawToBitmap($bitmap, [Drawing.Rectangle]::new(0, 0, $bitmap.Width, $bitmap.Height))
            $bitmap.Save((Join-Path $CaptureDirectory 'native-settings.png'), [Drawing.Imaging.ImageFormat]::Png)
            $bitmap.Dispose(); $script:configDialog.Close()
        })
        $script:configDialog.Add_Shown({ $configCaptureTimer.Start() })
    }
    Set-InterfaceTheme; Update-UpdateControls
    [void]$script:configDialog.ShowDialog($form)
    $script:configDialog.Dispose(); $script:configDialog = $null
}

Add-Button $form 'Atualizar lista' 666 122 130 { Update-Interface }
Add-Button $settings 'Aplicar a todos' 150 41 160 { Invoke-ElevatedAction Apply } -Primary
Add-Button $settings 'Ativar' 388 41 102 { Invoke-ElevatedAction EnableStartup }
Add-Button $settings 'Desativar' 500 41 102 { Invoke-ElevatedAction DisableStartup }
$startupHint = [Windows.Forms.Label]@{
    Text = 'Usa a direção selecionada ao clicar em Ativar.'
    Left = 388; Top = 81; Width = 370; Height = 23; ForeColor = $muted
}
$settings.Controls.Add($startupHint)
Add-Button $header '' 700 20 32 {
    $previousTheme = $preferences.theme
    $preferences.theme = if ($script:darkTheme) { 'light' } else { 'dark' }
    try { Save-Preferences; Set-InterfaceTheme } catch { $preferences.theme = $previousTheme; [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Mouse Scroll') }
}
$themeButton = $header.Controls[$header.Controls.Count - 1]
$themeButton.Height = 32; $themeButton.FlatAppearance.BorderSize = 0
Add-Button $header '' 750 20 32 { Show-Configuration }
$configButton = $header.Controls[$header.Controls.Count - 1]
$configButton.Height = 32; $configButton.FlatAppearance.BorderSize = 0
$configButton.AccessibleName = 'Configurações'
$tooltips = [Windows.Forms.ToolTip]::new()
$tooltips.SetToolTip($themeButton, 'Trocar tema claro / escuro')
$tooltips.SetToolTip($configButton, 'Configurações e atualizações')
$directionBox.Add_SelectedIndexChanged({ try { Save-Preferences } catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Mouse Scroll') } })
$updateTimer = [Windows.Forms.Timer]@{ Interval = 300 }
$updateTimer.Add_Tick({
    Update-UpdateControls
    $current = $updates.State
    if ($current.Status -in 'available', 'ready' -and $current.Version -ne $script:dismissedUpdate -and !$script:adminBusy) { Show-UpdateDialog }
})
$startupTimer = [Windows.Forms.Timer]@{ Interval = 2000 }
$startupTimer.Add_Tick({ $startupTimer.Stop(); $updates.Check() })
$form.Add_Shown({
    $list.Columns[2].Width = $list.ClientSize.Width - $list.Columns[0].Width - $list.Columns[1].Width
    Update-Interface; $startupTimer.Start(); $updateTimer.Start()
})
if ($CaptureDirectory) {
    # Local visual QA renders only this application's controls; it never applies mouse changes.
    $captureTimer = [Windows.Forms.Timer]@{ Interval = 700 }
    $captureTimer.Add_Tick({
        $captureTimer.Stop()
        try {
            New-Item -ItemType Directory -Path $CaptureDirectory -Force | Out-Null
            foreach ($theme in 'dark', 'light') {
                if ($preferences.theme -ne $theme) {
                    # System can already look like the target theme: exercise two clicks then.
                    if ($script:darkTheme -eq ($theme -eq 'dark')) { $themeButton.PerformClick() }
                    $themeButton.PerformClick()
                } else { Save-Preferences }
                Set-InterfaceTheme
                $restored = Get-Content -LiteralPath $preferencesPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($restored.theme -ne $theme) { throw 'O tema não foi persistido.' }
                if ($directionBox.Height -ne 34 -or $directionBox.Top -ne 41) { throw "Seletor desalinhado: $($directionBox.Bounds)" }
                $form.Refresh()
                $bitmap = [Drawing.Bitmap]::new($form.Width, $form.Height)
                $form.DrawToBitmap($bitmap, [Drawing.Rectangle]::new(0, 0, $form.Width, $form.Height))
                $bitmap.Save((Join-Path $CaptureDirectory "native-$theme.png"), [Drawing.Imaging.ImageFormat]::Png)
                $bitmap.Dispose()
            }
            if (!$script:darkTheme) { $themeButton.PerformClick() }
            Show-Configuration
            [IO.File]::WriteAllText((Join-Path $CaptureDirectory 'capture-result.txt'), 'OK: theme clicks, saved preferences, control alignment and settings.')
        } catch {
            [IO.File]::WriteAllText((Join-Path $CaptureDirectory 'capture-error.txt'), $_.Exception.ToString())
        } finally { $form.Close() }
    })
    $form.Add_Shown({ $captureTimer.Start() })
}
Set-InterfaceTheme
[void]$form.ShowDialog()
$updateTimer.Stop(); $updateTimer.Dispose(); $startupTimer.Dispose(); $updates.Dispose(); $tooltips.Dispose()
$mark.Image.Dispose()
$form.Dispose()
$icon.Dispose()
foreach ($image in $controlImages.Values) { $image.Dispose() }
