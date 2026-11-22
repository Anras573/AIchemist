# Shows a non-blocking Windows tray balloon notification.
# Invoked by notify.sh (backgrounded) so it never stalls the calling hook.
param(
    [string]$Title = "Notification",
    [string]$Message = ""
)

Add-Type -AssemblyName System.Windows.Forms

$icon = New-Object System.Windows.Forms.NotifyIcon
$icon.Icon = [System.Drawing.SystemIcons]::Information
$icon.BalloonTipTitle = $Title
$icon.BalloonTipText = $Message
$icon.Visible = $true
$icon.ShowBalloonTip(5000)

Start-Sleep -Seconds 5
$icon.Dispose()
