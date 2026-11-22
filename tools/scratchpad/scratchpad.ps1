# Launcher for scratchpad.py on Windows: finds a usable Python (3.7+) and runs the tool.
# Usage: scratchpad.ps1 <command> [options]   (see `scratchpad.ps1 --help`)
$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot 'scratchpad.py'
$versionCheck = 'import sys; sys.exit(0 if sys.version_info >= (3, 7) else 1)'

# Each candidate is the executable plus any fixed arguments (the `py` launcher needs -3).
$candidates = @(
    @('python3'),
    @('python'),
    @('py', '-3')
)

$found = $null
foreach ($candidate in $candidates) {
    if (-not (Get-Command $candidate[0] -ErrorAction SilentlyContinue)) { continue }
    $fixed = @()
    if ($candidate.Count -gt 1) { $fixed = $candidate[1..($candidate.Count - 1)] }
    # The Microsoft Store "python3" stub exits non-zero, so the version check also rejects it.
    & $candidate[0] @fixed -c $versionCheck 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $found = @{ Exe = $candidate[0]; Fixed = $fixed }
        break
    }
}

if (-not $found) {
    [Console]::Error.WriteLine('scratchpad: Python 3.7+ is required but was not found (tried python3, python, py -3).')
    [Console]::Error.WriteLine("Install it with 'winget install Python.Python.3'.")
    exit 1
}

& $found.Exe @($found.Fixed) $script @args
exit $LASTEXITCODE
