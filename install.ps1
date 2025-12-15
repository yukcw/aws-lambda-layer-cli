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

    # Check for other dependencies
    $hasZip = $false
    $hasPython = $false
    $hasNode = $false

    try {
        $zipVersion = & zip --version 2>$null
        if ($LASTEXITCODE -eq 0) { $hasZip = $true; Write-ColorOutput "✓ zip found" $Green }
    } catch { Write-ColorOutput "! zip not found" $Yellow }

    try {
        $pythonVersion = & python --version 2>$null
        if ($LASTEXITCODE -eq 0) { $hasPython = $true; Write-ColorOutput "✓ python found" $Green }
    } catch { Write-ColorOutput "! python not found" $Yellow }

    try {
        $nodeVersion = & node --version 2>$null
        if ($LASTEXITCODE -eq 0) { $hasNode = $true; Write-ColorOutput "✓ node found" $Green }
    } catch { Write-ColorOutput "! node not found" $Yellow }

    return @{
        WSL = $hasWSL
        GitBash = $hasGitBash
        GitBashPath = $gitBashPath
        AwsCli = $hasAwsCli
        Zip = $hasZip
        Python = $hasPython
        Node = $hasNode
    }
}

function Install-Dependencies {
    param([hashtable]$Prereqs)

    if (-not $Prereqs.Zip -or -not $Prereqs.Python -or -not $Prereqs.Node -or -not $Prereqs.AwsCli) {
        Write-ColorOutput "`nChecking for missing dependencies..." $Yellow
        
        # Check if winget is available
        try {
            $wingetVersion = & winget --version 2>$null
            if ($LASTEXITCODE -eq 0) {
                $installDeps = Read-Host "Missing dependencies detected. Try to install them with winget? (Y/n)"
                if ($installDeps -match "^[Yy]|^$") {
                    if (-not $Prereqs.Zip) {
                        Write-ColorOutput "Installing 7zip (provides zip functionality)..." $Cyan
                        & winget install --id 7zip.7zip -e --source winget
                    }
                    if (-not $Prereqs.Python) {
                        Write-ColorOutput "Installing Python..." $Cyan
                        & winget install --id Python.Python.3.12 -e --source winget
                    }
                    if (-not $Prereqs.Node) {
                        Write-ColorOutput "Installing Node.js..." $Cyan
                        & winget install --id OpenJS.NodeJS.LTS -e --source winget
                    }
                    if (-not $Prereqs.AwsCli) {
                        Write-ColorOutput "Installing AWS CLI..." $Cyan
                        & winget install --id Amazon.AWSCLI -e --source winget
                    }
                    Write-ColorOutput "Dependencies installed. You may need to restart your terminal." $Green
                }
            } else {
                Write-ColorOutput "winget not found. Please install missing dependencies manually." $Yellow
            }
        } catch {
            Write-ColorOutput "winget not found. Please install missing dependencies manually." $Yellow
        }
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

    # Download individual files
    Write-ColorOutput "Downloading files..." $Yellow

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

    # Make scripts executable (for bash environment)
    Write-ColorOutput "Setting executable permissions..." $Yellow
    $scriptFiles = Get-ChildItem $InstallDir -Filter "*.sh" -File
    # Also include the main script
    $scriptFiles += Get-Item "$InstallDir\$ToolName" -ErrorAction SilentlyContinue
    
    foreach ($file in $scriptFiles) {
        try {
            # On Windows, we can't set +x directly, but we can ensure the file is readable
            # The bash environment will handle execution
            if ($file.Extension -eq ".sh" -or $file.Name -eq $ToolName) {
                # Ensure Unix line endings for bash scripts
                $content = Get-Content $file.FullName -Raw
                $content = $content -replace "`r`n", "`n"
                [System.IO.File]::WriteAllText($file.FullName, $content, [System.Text.Encoding]::ASCII)
                Write-ColorOutput "✓ Prepared $($file.Name)" $Green
            }
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

setlocal enabledelayedexpansion

set "WIN_PATH=$InstallDir"

REM Detect which bash is being used to determine path style
set "IS_WSL=0"
for /f "delims=" %%i in ('where bash') do (
    echo "%%i" | findstr /i "System32" >nul
    if !ERRORLEVEL! EQU 0 set "IS_WSL=1"
    goto :DETECT_DONE
)
:DETECT_DONE

if "!IS_WSL!"=="1" (
    REM WSL Environment - use wslpath
    where wsl >nul 2>nul
    if !ERRORLEVEL! EQU 0 (
        for /f "delims=" %%i in ('wsl wslpath -a "!WIN_PATH!"') do set "UNIX_PATH=%%i"
    ) else (
        REM Fallback for WSL if wsl.exe missing - assume /mnt/c/ style
        set "UNIX_PATH=!WIN_PATH:\=/!"
        if "!UNIX_PATH:~1,1!"==":" (
            set "DRIVE=!UNIX_PATH:~0,1!"
            REM Simple lowercase for common drives
            if /i "!DRIVE!"=="C" set "DRIVE=c"
            if /i "!DRIVE!"=="D" set "DRIVE=d"
            set "UNIX_PATH=/mnt/!DRIVE!!UNIX_PATH:~2!"
        )
    )
) else (
    REM Git Bash / Cygwin Environment
    where cygpath >nul 2>nul
    if !ERRORLEVEL! EQU 0 (
        for /f "delims=" %%i in ('cygpath "!WIN_PATH!"') do set "UNIX_PATH=%%i"
    ) else (
        REM Manual conversion fallback (Git Bash style /c/...)
        set "UNIX_PATH=!WIN_PATH:\=/!"
        if "!UNIX_PATH:~1,1!"==":" (
            set "UNIX_PATH=/!UNIX_PATH:~0,1!!UNIX_PATH:~2!"
        )
    )
)

where bash >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    REM Try to run with bash
    bash "!UNIX_PATH!/$ToolName" %*
    if !ERRORLEVEL! NEQ 0 (
        echo Error: Failed to execute aws-lambda-layer
        echo Please check that the script exists and is executable
        echo Script path: !UNIX_PATH!/$ToolName
        pause
        exit /b 1
    )
) else (
    echo Error: bash not found in PATH
    echo Please install Git for Windows or WSL
    echo https://gitforwindows.org/
    echo.
    echo Alternatively, you can run the script directly with:
    echo bash "!UNIX_PATH!/$ToolName" [arguments]
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

    # Install dependencies if needed
    Install-Dependencies -Prereqs $prereqs

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