#Requires -Version 5.1

<#
.SYNOPSIS
    AWS Lambda Layer CLI Tool Uninstaller for Windows

.DESCRIPTION
    Uninstalls the AWS Lambda Layer CLI tool from Windows systems.

.PARAMETER InstallDir
    Directory where the tool is installed (default: $env:USERPROFILE\.aws-lambda-layer-cli)

.PARAMETER Force
    Force uninstallation without confirmation

.EXAMPLE
    # Uninstall with default settings
    .\uninstall.ps1

.EXAMPLE
    # Uninstall from custom directory
    .\uninstall.ps1 -InstallDir "C:\Tools\aws-lambda-layer"

.EXAMPLE
    # Force uninstall
    .\uninstall.ps1 -Force
#>

param(
    [string]$InstallDir = "",
    [switch]$Force
)

# Determine InstallDir if not provided
if ([string]::IsNullOrEmpty($InstallDir)) {
    if ($env:USERPROFILE) {
        $InstallDir = Join-Path $env:USERPROFILE ".aws-lambda-layer-cli"
    } elseif ($env:HOME) {
        $InstallDir = Join-Path $env:HOME ".aws-lambda-layer-cli"
    } else {
        Write-Error "Could not determine home directory. Please specify -InstallDir."
        exit 1
    }
}

# Colors for output
$Green = "Green"
$Yellow = "Yellow"
$Red = "Red"
$Cyan = "Cyan"
$White = "White"

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = $White
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-Header {
    Write-ColorOutput "`n=========================================" $Cyan
    Write-ColorOutput "AWS Lambda Layer CLI Tool Uninstaller" $Green
    Write-ColorOutput "=========================================" $Cyan
    Write-ColorOutput "Install Directory: $InstallDir" $White
    Write-ColorOutput ""
}

function Test-Installation {
    Write-ColorOutput "Checking installation..." $Yellow

    if (-not (Test-Path $InstallDir)) {
        Write-ColorOutput "Installation directory not found: $InstallDir" $Yellow
        Write-ColorOutput "The tool doesn't appear to be installed." $White
        return $false
    }

    $mainScript = Join-Path $InstallDir "aws-lambda-layer-cli"
    if (-not (Test-Path $mainScript)) {
        Write-ColorOutput "Main script not found: $mainScript" $Yellow
        Write-ColorOutput "This doesn't look like a valid installation." $White
        return $false
    }

    Write-ColorOutput "✓ Found installation at $InstallDir" $Green
    return $true
}

function Remove-FromPath {
    Write-ColorOutput "Removing from PATH..." $Yellow

    # Get current user PATH
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    
    # Remove our directory from PATH if present
    if ($currentPath -like "*$InstallDir*") {
        # Split PATH into array, filter out our directory, and rejoin
        $pathArray = $currentPath -split ';' | Where-Object { $_ -ne $InstallDir -and $_ -ne "$InstallDir\" }
        $newPath = $pathArray -join ';'
        
        # Update PATH
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-ColorOutput "✓ Removed $InstallDir from user PATH" $Green
        Write-ColorOutput "  Note: Restart your terminal for PATH changes to take effect" $Yellow
    } else {
        Write-ColorOutput "✓ $InstallDir not found in user PATH" $Green
    }
}

function Remove-Installation {
    Write-ColorOutput "Removing installation files..." $Yellow

    try {
        # Remove the entire installation directory
        Remove-Item $InstallDir -Recurse -Force
        Write-ColorOutput "✓ Removed installation directory" $Green
        return $true
    } catch {
        Write-ColorOutput "✗ Failed to remove installation directory" $Red
        Write-ColorOutput "Error: $($_.Exception.Message)" $Red
        return $false
    }
}

function Show-PostUninstall {
    Write-ColorOutput "`n=========================================" $Cyan
    Write-ColorOutput "Uninstallation Complete!" $Green
    Write-ColorOutput "=========================================" $Cyan
    Write-ColorOutput ""
    Write-ColorOutput "The AWS Lambda Layer CLI tool has been removed from your system." $White
    Write-ColorOutput ""
    Write-ColorOutput "What was removed:" $Yellow
    Write-ColorOutput "  • Installation directory: $InstallDir" $White
    Write-ColorOutput "  • PATH entry (if present)" $White
    Write-ColorOutput ""
    Write-ColorOutput "Note: You may need to restart your terminal for PATH changes to take effect." $Yellow
}

# Main uninstallation process
function Main {
    Write-Header

    # Check NPM
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        $npmList = npm list -g aws-lambda-layer-cli --depth=0 2>$null
        if ($npmList -match "aws-lambda-layer-cli@") {
            Write-ColorOutput "Detected NPM installation." $Yellow
            Write-ColorOutput "Removing NPM package..." $White
            npm uninstall -g aws-lambda-layer-cli
        }
    }

    # Check PyPI
    if (Get-Command pip -ErrorAction SilentlyContinue) {
        pip show aws-lambda-layer-cli 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-ColorOutput "Detected PyPI installation." $Yellow
            Write-ColorOutput "Removing PyPI package..." $White
            pip uninstall -y aws-lambda-layer-cli
        }
    }

    # Check if tool is installed
    $isInstalled = Test-Installation
    if (-not $isInstalled) {
        if (-not $Force) {
            $continue = Read-Host "Continue with uninstallation anyway? (y/N)"
            if ($continue -notmatch "^[Yy]$") {
                Write-ColorOutput "Uninstallation cancelled." $Red
                exit 0
            }
        }
    }

    # Confirm uninstallation unless forced
    if (-not $Force) {
        Write-ColorOutput "This will remove the AWS Lambda Layer CLI tool from your system." $Yellow
        $confirm = Read-Host "Are you sure you want to continue? (y/N)"
        if ($confirm -notmatch "^[Yy]$") {
            Write-ColorOutput "Uninstallation cancelled." $Red
            exit 0
        }
    }

    # Remove from PATH
    Remove-FromPath

    # Remove installation files
    $uninstallSuccess = Remove-Installation
    if (-not $uninstallSuccess) {
        Write-ColorOutput "`nUninstallation failed!" $Red
        exit 1
    }

    # Show post-uninstallation information
    Show-PostUninstall
}

# Run main function
Main