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
        $wslInstallStatus = wsl --status 2>$null
        if ($LASTEXITCODE -eq 0) {
            $hasWSL = $true
            Write-ColorOutput "✓ WSL found" $Green
        }
    } catch {
        Write-ColorOutput "! WSL not found or not accessible" $Yellow
    }

    # Check for Git Bash
    $gitBashPath = $null
    $possiblePaths = @(
        "$env:ProgramFiles\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $gitBashPath = $path
            break
        }
    }

    # If not found in standard locations, check PATH
    if (-not $gitBashPath) {
        $bashCmd = Get-Command bash -ErrorAction SilentlyContinue
        if ($bashCmd) {
            $path = $bashCmd.Source
            # Filter out WSL bash (usually in System32)
            if ($path -notlike "*\System32\bash.exe") {
                $gitBashPath = $path
            }
        }
    }

    if ($gitBashPath) {
        $hasGitBash = $true
        Write-ColorOutput "✓ Git Bash found at $gitBashPath" $Green
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
    $hasZipWSL = $false
    $hasZipGitBash = $false
    $hasPythonWSL = $false
    $hasVenvWSL = $false
    $hasPythonGitBash = $false
    $hasNodeWSL = $false
    $hasNodeGitBash = $false

    # Check for zip in WSL
    if ($hasWSL) {
        try {
            $wslZip = wsl zip --version 2>$null
            if ($LASTEXITCODE -eq 0) { 
                $hasZipWSL = $true
                Write-ColorOutput "✓ zip found in WSL" $Green 
            } else {
                Write-ColorOutput "! zip not found in WSL" $Yellow
            }
        } catch { Write-ColorOutput "! Failed to check zip in WSL" $Yellow }

        try {
            # Check for python3 or python
            $wslPython = wsl bash -c "command -v python3 || command -v python" 2>$null
            if ($LASTEXITCODE -eq 0) {
                $hasPythonWSL = $true
                Write-ColorOutput "✓ python found in WSL" $Green
            } else {
                Write-ColorOutput "! python not found in WSL" $Yellow
            }
        } catch { Write-ColorOutput "! Failed to check python in WSL" $Yellow }

        try {
            # Check for python3-venv
            $wslVenv = wsl bash -c "python3 -c 'import venv' 2>/dev/null || python -c 'import venv' 2>/dev/null" 2>$null
            if ($LASTEXITCODE -eq 0) {
                $hasVenvWSL = $true
                Write-ColorOutput "✓ python venv module found in WSL" $Green
            } else {
                Write-ColorOutput "! python venv module not found in WSL" $Yellow
            }
        } catch { Write-ColorOutput "! Failed to check python venv in WSL" $Yellow }

        try {
            $wslNode = wsl node --version 2>$null
            if ($LASTEXITCODE -eq 0) {
                $hasNodeWSL = $true
                Write-ColorOutput "✓ node found in WSL" $Green
            } else {
                Write-ColorOutput "! node not found in WSL" $Yellow
            }
        } catch { Write-ColorOutput "! Failed to check node in WSL" $Yellow }
    }

    # Check for dependencies in Windows (for Git Bash)
    if ($hasGitBash) {
        function Check-WindowsTool {
            param($Name, $ExeName)
            $cmd = Get-Command $ExeName -ErrorAction SilentlyContinue
            if ($cmd) {
                if ($cmd.Version -and $cmd.Version.ToString() -ne "0.0.0.0") {
                    Write-ColorOutput "✓ $Name found ($($cmd.Version))" $Green
                    return $true
                }
            }
            Write-ColorOutput "! $Name not found in Windows PATH" $Yellow
            return $false
        }

        $hasZipGitBash = Check-WindowsTool "zip" "zip.exe"
        $hasPythonGitBash = Check-WindowsTool "python" "python.exe"
        $hasNodeGitBash = Check-WindowsTool "node" "node.exe"
    }

    return @{
        WSL = $hasWSL
        GitBash = $hasGitBash
        GitBashPath = $gitBashPath
        AwsCli = $hasAwsCli
        ZipWSL = $hasZipWSL
        ZipGitBash = $hasZipGitBash
        PythonWSL = $hasPythonWSL
        VenvWSL = $hasVenvWSL
        PythonGitBash = $hasPythonGitBash
        NodeWSL = $hasNodeWSL
        NodeGitBash = $hasNodeGitBash
    }
}

function Install-Dependencies {
    param([hashtable]$Prereqs)

    # Handle WSL zip installation
    if ($Prereqs.WSL -and -not $Prereqs.ZipWSL) {
        $installZip = Read-Host "Zip not found in WSL. Try to install it? (Y/n)"
        if ($installZip -match "^[Yy]|^$") {
            Write-ColorOutput "Attempting to install zip in WSL (you may be asked for your sudo password)..." $Cyan
            try {
                # Try apt-get (Debian/Ubuntu)
                Write-ColorOutput "Running: wsl sudo apt-get update && sudo apt-get install -y zip" $White
                wsl sudo apt-get update
                wsl sudo apt-get install -y zip
                
                if ($LASTEXITCODE -eq 0) {
                    Write-ColorOutput "✓ zip installed in WSL" $Green
                    $Prereqs.ZipWSL = $true
                } else {
                    Write-ColorOutput "✗ Failed to install zip automatically." $Red
                    Write-ColorOutput "Please run 'sudo apt-get install zip' (or equivalent) inside WSL manually." $Yellow
                }
            } catch {
                Write-ColorOutput "✗ Failed to execute WSL commands." $Red
            }
        }
    }

    # Handle Git Bash zip installation
    if ($Prereqs.GitBash -and -not $Prereqs.ZipGitBash) {
        # Check if GnuWin32 is already installed but not in PATH
        $gnuWin32Path = "${env:ProgramFiles(x86)}\GnuWin32\bin"
        if (Test-Path $gnuWin32Path) {
            $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
            if ($currentPath -notlike "*$gnuWin32Path*") {
                $newPath = "$currentPath;$gnuWin32Path"
                [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
                Write-ColorOutput "✓ Found GnuWin32 Zip at $gnuWin32Path" $Green
                Write-ColorOutput "✓ Added GnuWin32 to user PATH" $Green
                Write-ColorOutput "  Note: You may need to restart your terminal for PATH changes to take effect." $Yellow
                $Prereqs.ZipGitBash = $true
            }
        }

        if (-not $Prereqs.ZipGitBash) {
            $installZip = Read-Host "Zip not found in Git Bash. Try to install GnuWin32 Zip with winget? (Y/n)"
            if ($installZip -match "^[Yy]|^$") {
                Write-ColorOutput "Attempting to install GnuWin32 Zip..." $Cyan
                try {
                    $wingetVersion = & winget --version 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        & winget install --id GnuWin32.Zip -e --source winget
                        if ($LASTEXITCODE -eq 0) {
                            Write-ColorOutput "✓ GnuWin32 Zip installed" $Green
                            
                            # Add GnuWin32 to PATH
                            if (Test-Path $gnuWin32Path) {
                                $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
                                if ($currentPath -notlike "*$gnuWin32Path*") {
                                    $newPath = "$currentPath;$gnuWin32Path"
                                    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
                                    Write-ColorOutput "✓ Added $gnuWin32Path to user PATH" $Green
                                }
                            }

                            Write-ColorOutput "  Note: You may need to restart your terminal for PATH changes to take effect." $Yellow
                            $Prereqs.ZipGitBash = $true
                        } else {
                            Write-ColorOutput "✗ Failed to install GnuWin32 Zip." $Red
                            Write-ColorOutput "Please install 'zip' manually (e.g. 'winget install GnuWin32.Zip')." $Yellow
                        }
                    } else {
                        Write-ColorOutput "winget not found. Please install 'zip' manually." $Yellow
                    }
                } catch {
                    Write-ColorOutput "Error running winget." $Red
                }
            }
        }
    }

    if (-not $Prereqs.PythonWSL -or -not $Prereqs.VenvWSL -or -not $Prereqs.NodeWSL -or -not $Prereqs.PythonGitBash -or -not $Prereqs.NodeGitBash -or -not $Prereqs.AwsCli) {
        Write-ColorOutput "`nChecking for missing dependencies..." $Yellow
        
        # Handle WSL dependencies
        if ($Prereqs.WSL) {
            if (-not $Prereqs.PythonWSL -or -not $Prereqs.VenvWSL -or -not $Prereqs.NodeWSL) {
                $installWslDeps = Read-Host "Missing dependencies in WSL. Try to install them? (Y/n)"
                if ($installWslDeps -match "^[Yy]|^$") {
                    Write-ColorOutput "Attempting to install dependencies in WSL..." $Cyan
                    try {
                        Write-ColorOutput "Running: wsl sudo apt-get update" $White
                        wsl sudo apt-get update
                        
                        if (-not $Prereqs.PythonWSL) {
                            Write-ColorOutput "Installing Python in WSL..." $Cyan
                            wsl sudo apt-get install -y python3 python3-pip python3-venv
                        } elseif (-not $Prereqs.VenvWSL) {
                            Write-ColorOutput "Installing Python venv in WSL..." $Cyan
                            wsl sudo apt-get install -y python3-venv
                        }
                        if (-not $Prereqs.NodeWSL) {
                            Write-ColorOutput "Installing Node.js in WSL..." $Cyan
                            wsl sudo apt-get install -y nodejs npm
                        }
                    } catch {
                        Write-ColorOutput "✗ Failed to execute WSL commands." $Red
                    }
                }
            }
        }

        # Handle Git Bash / Windows dependencies
        # If Git Bash is present but missing deps, we install them in Windows so Git Bash inherits them
        if ($Prereqs.GitBash) {
            if (-not $Prereqs.PythonGitBash -or -not $Prereqs.NodeGitBash -or -not $Prereqs.AwsCli) {
                # Check if winget is available
                try {
                    $wingetVersion = & winget --version 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        $installDeps = Read-Host "Missing Windows dependencies (for Git Bash). Try to install them with winget? (Y/n)"
                        if ($installDeps -match "^[Yy]|^$") {
                            if (-not $Prereqs.PythonGitBash) {
                                Write-ColorOutput "Installing Python..." $Cyan
                                & winget install --id Python.Python.3.12 -e --source winget
                            }
                            if (-not $Prereqs.NodeGitBash) {
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