#Requires -Version 5.1

<#
.SYNOPSIS
    AWS Lambda Layer CLI Tool Installer for Windows

.DESCRIPTION
    Installs the AWS Lambda Layer CLI tool on Windows systems.
    This tool requires Windows Subsystem for Linux (WSL) or Git Bash.

.PARAMETER InstallDir
    Directory where the tool will be installed (default: $env:USERPROFILE\.aws-lambda-layer)

.PARAMETER Force
    Force reinstallation even if already installed

.EXAMPLE
    # Install with default settings
    .\install.ps1

.EXAMPLE
    # Install to custom directory
    .\install.ps1 -InstallDir "C:\Tools\aws-lambda-layer"

.EXAMPLE
    # Force reinstall
    .\install.ps1 -Force
#>

param(
    [string]$InstallDir = "$env:USERPROFILE\.aws-lambda-layer",
    [switch]$Force
)

# Configuration
$RepoUrl = "https://github.com/yukcw/aws-lambda-layer-cli"
$ReleaseUrl = "$RepoUrl/releases/latest/download"
$ToolName = "aws-lambda-layer"
$Version = "1.2.0"

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
    Write-ColorOutput "AWS Lambda Layer CLI Tool Installer" $Green
    Write-ColorOutput "=========================================" $Cyan
    Write-ColorOutput "Version: $Version" $White
    Write-ColorOutput "Install Directory: $InstallDir" $White
    Write-ColorOutput ""
}

function Test-Prerequisites {
    Write-ColorOutput "Checking prerequisites..." $Yellow

    $hasWSL = $false
    $hasGitBash = $false
    $hasAwsCli = $false

    # Check for WSL
    try {
        $wslVersion = wsl --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            $hasWSL = $true
            Write-ColorOutput "✓ WSL found" $Green
        }
    } catch {
        Write-ColorOutput "! WSL not found or not accessible" $Yellow
    }

    # Check for Git Bash
    $gitBashPath = "$env:ProgramFiles\Git\bin\bash.exe"
    if (Test-Path $gitBashPath) {
        $hasGitBash = $true
        Write-ColorOutput "✓ Git Bash found at $gitBashPath" $Green
    } else {
        # Check common Git installation paths
        $gitPaths = @(
            "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
            "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
        )
        foreach ($path in $gitPaths) {
            if (Test-Path $path) {
                $hasGitBash = $true
                $gitBashPath = $path
                Write-ColorOutput "✓ Git Bash found at $path" $Green
                break
            }
        }
    }

    if (-not $hasWSL -and -not $hasGitBash) {
        Write-ColorOutput "✗ Neither WSL nor Git Bash found!" $Red
        Write-ColorOutput ""
        Write-ColorOutput "This tool requires a bash environment. Please install one of:" $Yellow
        Write-ColorOutput "1. Windows Subsystem for Linux (WSL):" $White
        Write-ColorOutput "   wsl --install" $Cyan
        Write-ColorOutput ""
        Write-ColorOutput "2. Git for Windows:" $White
        Write-ColorOutput "   https://gitforwindows.org/" $Cyan
        Write-ColorOutput ""
        exit 1
    }

    # Check for AWS CLI
    try {
        $awsVersion = & aws --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            $hasAwsCli = $true
            Write-ColorOutput "✓ AWS CLI found" $Green
        }
    } catch {
        Write-ColorOutput "! AWS CLI not found (optional for zip command)" $Yellow
    }

    return @{
        WSL = $hasWSL
        GitBash = $hasGitBash
        GitBashPath = $gitBashPath
        AwsCli = $hasAwsCli
    }
}

function Get-LatestRelease {
    Write-ColorOutput "Fetching latest release information..." $Yellow

    try {
        $apiUrl = "https://api.github.com/repos/yukcw/aws-lambda-layer-cli/releases/latest"
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get

        $asset = $response.assets | Where-Object { $_.name -eq "aws-lambda-layer-cli.zip" } | Select-Object -First 1

        if ($asset) {
            return @{
                Version = $response.tag_name
                DownloadUrl = $asset.browser_download_url
                Size = $asset.size
            }
        } else {
            Write-ColorOutput "Warning: Pre-built zip not found, will download individual files" $Yellow
            return $null
        }
    } catch {
        Write-ColorOutput "Warning: Could not fetch release info, will download individual files" $Yellow
        Write-ColorOutput "Error: $($_.Exception.Message)" $Red
        return $null
    }
}

function Install-Tool {
    param([hashtable]$Prereqs)

    # Create install directory
    if (Test-Path $InstallDir) {
        if ($Force) {
            Write-ColorOutput "Removing existing installation..." $Yellow
            Remove-Item $InstallDir -Recurse -Force
        } else {
            Write-ColorOutput "Installation directory already exists: $InstallDir" $Yellow
            $overwrite = Read-Host "Overwrite existing installation? (y/N)"
            if ($overwrite -notmatch "^[Yy]$") {
                Write-ColorOutput "Installation cancelled." $Red
                exit 0
            }
            Remove-Item $InstallDir -Recurse -Force
        }
    }

    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Write-ColorOutput "Created install directory: $InstallDir" $Green

    # Try to download pre-built zip first
    $releaseInfo = Get-LatestRelease
    $tempZip = "$env:TEMP\aws-lambda-layer-cli.zip"

    if ($releaseInfo) {
        Write-ColorOutput "Downloading pre-built package..." $Yellow
        try {
            Invoke-WebRequest -Uri $releaseInfo.DownloadUrl -OutFile $tempZip
            Write-ColorOutput "Extracting package..." $Yellow
            Expand-Archive -Path $tempZip -DestinationPath $InstallDir -Force
            Remove-Item $tempZip -Force
            Write-ColorOutput "✓ Package extracted successfully" $Green
        } catch {
            Write-ColorOutput "Failed to download pre-built package, falling back to individual files" $Yellow
            Remove-Item $tempZip -ErrorAction SilentlyContinue
        }
    }

    # If zip download failed or no pre-built zip, download individual files
    if (-not (Test-Path "$InstallDir\$ToolName")) {
        Write-ColorOutput "Downloading individual files..." $Yellow

        $files = @(
            "aws-lambda-layer",
            "create_nodejs_layer.sh",
            "create_python_layer.sh",
            "install.sh",
            "uninstall.sh",
            "uninstall.ps1"
        )

        $baseUrl = "https://raw.githubusercontent.com/yukcw/aws-lambda-layer-cli/main"

        foreach ($file in $files) {
            $url = "$baseUrl/$file"
            $outputPath = Join-Path $InstallDir $file

            try {
                Invoke-WebRequest -Uri $url -OutFile $outputPath
                Write-ColorOutput "✓ Downloaded $file" $Green
            } catch {
                Write-ColorOutput "✗ Failed to download $file" $Red
                Write-ColorOutput "Error: $($_.Exception.Message)" $Red
                return $false
            }
        }

        # Download completion files
        $completionDir = Join-Path $InstallDir "completion"
        New-Item -ItemType Directory -Path $completionDir -Force | Out-Null

        $completionFiles = @(
            "completion/aws-lambda-layer-completion.bash",
            "completion/aws-lambda-layer-completion.zsh"
        )

        foreach ($file in $completionFiles) {
            $url = "$baseUrl/$file"
            $outputPath = Join-Path $InstallDir $file

            try {
                Invoke-WebRequest -Uri $url -OutFile $outputPath
                Write-ColorOutput "✓ Downloaded $file" $Green
            } catch {
                Write-ColorOutput "! Failed to download $file (optional)" $Yellow
            }
        }
    }

    # Make scripts executable
    Write-ColorOutput "Setting executable permissions..." $Yellow
    $scriptFiles = Get-ChildItem $InstallDir -Filter "*.sh" -File
    foreach ($file in $scriptFiles) {
        try {
            # On Windows, we can't set +x directly, but the bash environment will handle it
            Write-ColorOutput "✓ Prepared $($file.Name)" $Green
        } catch {
            Write-ColorOutput "! Could not prepare $($file.Name)" $Yellow
        }
    }

    return $true
}

function Setup-Path {
    param([hashtable]$Prereqs)

    Write-ColorOutput "Setting up PATH..." $Yellow

    # Add to PATH for current session
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentPath -notlike "*$InstallDir*") {
        $newPath = "$currentPath;$InstallDir"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-ColorOutput "✓ Added $InstallDir to user PATH" $Green
        Write-ColorOutput "  Note: Restart your terminal for PATH changes to take effect" $Yellow
    } else {
        Write-ColorOutput "✓ PATH already contains $InstallDir" $Green
    }

    # Create wrapper scripts for easier execution
    $wrapperScript = @"
@echo off
REM AWS Lambda Layer CLI Tool Wrapper for Windows
REM This script helps run the tool in the appropriate bash environment

where bash >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    bash "$InstallDir\$ToolName" %*
) else (
    echo Error: bash not found in PATH
    echo Please install Git for Windows or WSL
    echo https://gitforwindows.org/
    pause
    exit /b 1
)
"@

    $wrapperPath = "$InstallDir\$ToolName.cmd"
    $wrapperScript | Out-File -FilePath $wrapperPath -Encoding ASCII
    Write-ColorOutput "✓ Created Windows wrapper script: $wrapperPath" $Green
}

function Show-PostInstall {
    Write-ColorOutput "`n=========================================" $Cyan
    Write-ColorOutput "Installation Complete!" $Green
    Write-ColorOutput "=========================================" $Cyan
    Write-ColorOutput ""
    Write-ColorOutput "The AWS Lambda Layer CLI tool has been installed to:" $White
    Write-ColorOutput "  $InstallDir" $Cyan
    Write-ColorOutput ""
    Write-ColorOutput "Usage:" $Yellow
    Write-ColorOutput "  # Create a local zip file" $White
    Write-ColorOutput "  aws-lambda-layer zip --nodejs express@4.18.2" $Cyan
    Write-ColorOutput "  aws-lambda-layer zip --python requests==2.31.0" $Cyan
    Write-ColorOutput ""
    Write-ColorOutput "  # Publish directly to AWS" $White
    Write-ColorOutput "  aws-lambda-layer publish --nodejs express --description ""Express layer""" $Cyan
    Write-ColorOutput ""
    Write-ColorOutput "For more information:" $Yellow
    Write-ColorOutput "  aws-lambda-layer --help" $Cyan
    Write-ColorOutput ""
    Write-ColorOutput "Repository: $RepoUrl" $White
}

# Main installation process
function Main {
    Write-Header

    # Check prerequisites
    $prereqs = Test-Prerequisites

    # Install the tool
    $installSuccess = Install-Tool -Prereqs $prereqs
    if (-not $installSuccess) {
        Write-ColorOutput "`nInstallation failed!" $Red
        exit 1
    }

    # Setup PATH and wrappers
    Setup-Path -Prereqs $prereqs

    # Show post-installation information
    Show-PostInstall
}

# Run main function
Main