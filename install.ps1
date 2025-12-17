<#
Backward-compatible wrapper. The real installer lives in scripts/install.ps1
#>

param(
    [string]$InstallDir = "$env:USERPROFILE\.aws-lambda-layer",
    [switch]$Force
)

$scriptPath = Join-Path $PSScriptRoot "scripts\install.ps1"

if (-not (Test-Path $scriptPath)) {
    Write-Error "Installer script not found: $scriptPath"
    exit 1
}

& $scriptPath -InstallDir $InstallDir -Force:$Force
exit $LASTEXITCODE
