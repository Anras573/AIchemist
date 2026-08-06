#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Windows counterpart to tools/bootstrap-machine.sh.
.DESCRIPTION
    Installs machine dependencies via winget/npm/uv, initializes mempalace,
    pulls the markitdown Docker image, and registers the AIchemist plugin
    with Claude Code and GitHub Copilot CLI. Mirrors the macOS bash script's
    install/doctor commands and exit-status conventions.
.USAGE
    tools/bootstrap-machine.ps1 [install|doctor]
#>

param(
    [Parameter(Position = 0)]
    [ValidateSet('install', 'doctor', 'help', '-h', '--help')]
    [string]$Command = 'install'
)

Set-StrictMode -Version Latest

$PluginName = 'aichemist'
$MarkitdownImage = 'mcp/markitdown@sha256:1cef3bf502503310ed0884441874ccf6cdaac20136dc1179797fa048269dc4cb'
$MempalaceHome = Join-Path $HOME '.mempalace'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$script:MissingCount = 0

# id: winget package identifier. action: message shown when missing/failed.
$WingetPackages = @(
    @{ Id = 'jqlang.jq'; Cmd = 'jq'; Action = 'winget install --id jqlang.jq -e' }
    @{ Id = 'Python.Python.3.12'; Cmd = 'python'; Action = 'winget install --id Python.Python.3.12 -e' }
    @{ Id = 'OpenJS.NodeJS.LTS'; Cmd = 'node'; Action = 'winget install --id OpenJS.NodeJS.LTS -e' }
    @{ Id = 'astral-sh.uv'; Cmd = 'uv'; Action = 'winget install --id astral-sh.uv -e' }
    @{ Id = 'Docker.DockerDesktop'; Cmd = 'docker'; Action = 'winget install --id Docker.DockerDesktop -e' }
    @{ Id = 'PostgreSQL.PostgreSQL.17'; Cmd = 'psql'; Action = 'winget install --id PostgreSQL.PostgreSQL.17 -e' }
    @{ Id = 'Obsidian.Obsidian'; Cmd = $null; Action = 'winget install --id Obsidian.Obsidian -e'; Required = $false }
)

function Write-Log { param([string]$Message) Write-Host "==> $Message" }
function Write-Ok { param([string]$Message) Write-Host "READY: $Message" }
function Write-Warn { param([string]$Message) Write-Host "WARN: $Message" -ForegroundColor Yellow }
function Die { param([string]$Message) Write-Host "ERROR: $Message" -ForegroundColor Red; exit 1 }

function Show-Usage {
    @'
Usage: tools/bootstrap-machine.ps1 [install|doctor]

Commands:
  install   Install machine dependencies, plugin tool dependencies, and plugin registrations (default)
  doctor    Validate dependency + plugin health and print actionable fixes
'@
}

function Assert-Windows {
    if (-not $IsWindows) {
        Die 'This bootstrap script currently supports Windows only. Use tools/bootstrap-machine.sh on macOS.'
    }
}

function Assert-Winget {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Die 'winget is required. Install "App Installer" from the Microsoft Store and rerun this script.'
    }
}

function Add-Missing {
    param([string]$Label, [string]$Action, [bool]$Required = $true)

    Write-Host "MISSING: $Label"
    Write-Host "  ACTION: $Action"
    if ($Required) { $script:MissingCount++ }
}

function Test-CommandPresent {
    param([string]$Cmd, [string]$Action, [bool]$Required = $true)

    if (Get-Command $Cmd -ErrorAction SilentlyContinue) {
        Write-Ok $Cmd
    } else {
        Add-Missing $Cmd $Action $Required
    }
}

function Test-EnvPresent {
    param([string]$Name, [string]$Action, [bool]$Required = $true)

    if ([Environment]::GetEnvironmentVariable($Name)) {
        Write-Ok "env $Name"
    } else {
        Add-Missing "env $Name" $Action $Required
    }
}

function Sync-EnvPath {
    # Long-running / reused PowerShell hosts don't auto-pick-up PATH entries that
    # winget (or Add-PathEntry) wrote to the registry after this process started.
    $machine = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $env:PATH = "$machine;$user"
}

function Add-PathEntry {
    param([string]$Dir)

    if ([string]::IsNullOrWhiteSpace($Dir) -or -not (Test-Path $Dir)) { return }

    $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    if (($userPath -split ';') -notcontains $Dir) {
        [Environment]::SetEnvironmentVariable('PATH', "$userPath;$Dir", 'User')
        Write-Log "Added $Dir to user PATH"
    }
    if (($env:PATH -split ';') -notcontains $Dir) {
        $env:PATH = "$env:PATH;$Dir"
    }
}

function Repair-InstalledPaths {
    Write-Log 'Syncing PATH for tools installed outside winget (pip/uv Scripts and bin dirs)'

    Add-PathEntry (Join-Path $HOME '.local\bin')

    if (Get-Command python -ErrorAction SilentlyContinue) {
        $scriptsDir = (python -c "import sysconfig; print(sysconfig.get_path('scripts'))" 2>$null | Select-Object -Last 1)
        Add-PathEntry $scriptsDir
    }

    $pgRoot = 'C:\Program Files\PostgreSQL'
    if (Test-Path $pgRoot) {
        $latest = Get-ChildItem $pgRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object { [int]$_.Name } -Descending | Select-Object -First 1
        if ($latest) { Add-PathEntry (Join-Path $latest.FullName 'bin') }
    }
}

function Install-WingetPackages {
    foreach ($pkg in $WingetPackages) {
        Write-Log "Installing $($pkg.Id) via winget"
        winget install --id $pkg.Id -e --accept-package-agreements --accept-source-agreements --silent 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "winget install $($pkg.Id) returned exit code $LASTEXITCODE (may already be installed)"
        }
    }
}

function Install-NpmTools {
    Write-Log 'Installing npm global tools'
    npm install -g '@playwright/cli@latest' '@pnp/cli-microsoft365' '@beads/bd' | Out-Host
}

function Install-PipTools {
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        Write-Warn "'python' not found; skipping pip tool installs."
        return
    }
    Write-Log 'Installing pip tools (lizard)'
    python -m pip install --upgrade lizard | Out-Host
}

function Install-MempalaceTool {
    Write-Log 'Installing/upgrading mempalace via uv tool'
    $installed = uv tool list 2>$null | Select-String -Pattern 'mempalace' -Quiet
    if ($installed) {
        uv tool upgrade mempalace | Out-Host
    } else {
        uv tool install mempalace | Out-Host
    }
}

function Initialize-Mempalace {
    if (Test-Path $MempalaceHome) {
        Write-Ok "mempalace initialized ($MempalaceHome)"
        return
    }

    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        Die "'uv' is required to initialize mempalace."
    }
    Write-Log "Initializing mempalace at $MempalaceHome"
    New-Item -ItemType Directory -Force -Path $MempalaceHome | Out-Null
    uv tool run --from mempalace mempalace init $MempalaceHome --yes | Out-Host
}

function Get-MarkitdownImage {
    docker info *>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn 'Docker daemon is not running; skipping markitdown image pull for now.'
        return
    }

    Write-Log 'Pulling markitdown image'
    docker pull $MarkitdownImage | Out-Host
}

function Install-PluginClaude {
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        Write-Warn "'claude' CLI not found; skipping Claude plugin registration."
        return
    }

    Write-Log "Installing $PluginName for Claude Code from local path"
    claude plugin install $RepoRoot | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Warn 'Claude plugin install returned non-zero. Verify with: claude plugin list'
    }
}

function Install-PluginCopilot {
    if (-not (Get-Command copilot -ErrorAction SilentlyContinue)) {
        Write-Warn "'copilot' CLI not found; skipping Copilot plugin registration."
        return
    }

    Write-Log "Installing $PluginName for GitHub Copilot CLI from local path"
    copilot plugin install $RepoRoot | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Warn 'Copilot plugin install returned non-zero. Verify with: copilot plugin list'
    }
}

function Test-ObsidianPresent {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Obsidian\Obsidian.exe'),
        (Join-Path ${env:ProgramFiles} 'Obsidian\Obsidian.exe')
    )
    if ((Get-Command obsidian -ErrorAction SilentlyContinue) -or ($candidates | Where-Object { Test-Path $_ })) {
        Write-Ok 'obsidian'
    } else {
        Add-Missing 'obsidian' 'winget install --id Obsidian.Obsidian -e' $false
    }
}

function Invoke-Doctor {
    Assert-Windows
    Sync-EnvPath
    $script:MissingCount = 0

    Write-Host 'AIchemist machine doctor'
    Write-Host "Repo: $RepoRoot"
    Write-Host ''

    Test-CommandPresent 'winget' 'Install "App Installer" from the Microsoft Store.'
    Test-CommandPresent 'jq' 'winget install --id jqlang.jq -e'
    Test-CommandPresent 'python' 'winget install --id Python.Python.3.12 -e'
    Test-CommandPresent 'node' 'winget install --id OpenJS.NodeJS.LTS -e'
    Test-CommandPresent 'npm' 'winget install --id OpenJS.NodeJS.LTS -e'
    Test-CommandPresent 'uv' 'winget install --id astral-sh.uv -e'
    Test-CommandPresent 'docker' 'winget install --id Docker.DockerDesktop -e'
    Test-CommandPresent 'lizard' 'pip install lizard'
    Test-CommandPresent 'bd' 'npm install -g @beads/bd'
    Test-CommandPresent 'psql' 'winget install --id PostgreSQL.PostgreSQL -e (then add its bin/ dir to PATH)'
    Test-CommandPresent 'm365' 'npm install -g @pnp/cli-microsoft365'
    Test-CommandPresent 'playwright-cli' 'npm install -g @playwright/cli@latest'
    Test-CommandPresent 'mempalace' 'uv tool install mempalace'
    Test-CommandPresent 'claude' 'Install Claude Code CLI first, then rerun bootstrap.'
    Test-CommandPresent 'copilot' 'Install GitHub Copilot CLI first, then rerun bootstrap.'

    Test-ObsidianPresent

    Test-EnvPresent 'MSGRAPH_APP_ID' '$env:MSGRAPH_APP_ID = "<your-azure-app-id>"' $false
    Test-EnvPresent 'MSGRAPH_TENANT_ID' '$env:MSGRAPH_TENANT_ID = "<your-azure-tenant-id>"' $false
    Test-EnvPresent 'POSTGRES_URL' '$env:POSTGRES_URL = "postgresql://user:password@host:5432/database"' $false

    if (Test-Path $MempalaceHome) {
        Write-Ok "mempalace home ($MempalaceHome)"
    } else {
        Add-Missing "mempalace home ($MempalaceHome)" "uv tool run --from mempalace mempalace init $MempalaceHome --yes"
    }

    if (Get-Command docker -ErrorAction SilentlyContinue) {
        docker info *>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Ok 'docker daemon'
            docker image inspect $MarkitdownImage *>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Ok 'markitdown image'
            } else {
                Add-Missing 'markitdown image' "docker pull $MarkitdownImage"
            }
        } else {
            Add-Missing 'docker daemon' 'Open Docker Desktop and rerun doctor.'
        }
    }

    if (Get-Command claude -ErrorAction SilentlyContinue) {
        $found = claude plugin list 2>$null | Select-String -Pattern $PluginName -Quiet
        if ($found) {
            Write-Ok "claude plugin $PluginName"
        } else {
            Add-Missing "claude plugin $PluginName" "claude plugin install $RepoRoot"
        }
    }

    if (Get-Command copilot -ErrorAction SilentlyContinue) {
        $found = copilot plugin list 2>$null | Select-String -Pattern $PluginName -Quiet
        if ($found) {
            Write-Ok "copilot plugin $PluginName"
        } else {
            Add-Missing "copilot plugin $PluginName" "copilot plugin install $RepoRoot"
        }
    }

    Write-Host ''
    if ($script:MissingCount -eq 0) {
        Write-Host 'Doctor result: healthy'
        return 0
    }

    Write-Host "Doctor result: $($script:MissingCount) required item(s) need attention."
    return 1
}

function Invoke-Install {
    Assert-Windows
    Assert-Winget
    Install-WingetPackages
    Sync-EnvPath
    Install-NpmTools
    Install-PipTools
    Install-MempalaceTool
    Initialize-Mempalace
    Get-MarkitdownImage
    Install-PluginClaude
    Install-PluginCopilot
    Repair-InstalledPaths
    return (Invoke-Doctor)
}

switch ($Command) {
    'install' { exit (Invoke-Install) }
    'doctor' { exit (Invoke-Doctor) }
    default { Show-Usage }
}
