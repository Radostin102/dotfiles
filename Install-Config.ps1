# Installation script for Windows

$ErrorActionPreference = "Stop"

# 1. PRE-FLIGHT CHECK: Ensure we are NOT running as Admin for the main script
$is_admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($is_admin) {
    Write-Warning "You are running this script as Administrator."
    Write-Warning "The VS Code 'User Setup' should be installed as a Standard User to prevent permission issues."
    $continue = Read-Host "Do you want to continue anyway? (Recommended: n) [y/n]"
    if ($continue.ToLower() -ne 'y') {
        Exit
    }
}

function Install-VSCode {
    Write-Host "Downloading Visual Studio Code (User Setup)..." -ForegroundColor Cyan
    $vscodeInstaller = "$env:TEMP\VSCodeUserSetup.exe"

    try {
        Invoke-WebRequest -Uri "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64-user" -OutFile $vscodeInstaller
    }
    catch {
        Write-Error "Failed to download VS Code. Check your internet connection."
        return
    }

    Write-Host "Installing Visual Studio Code..." -ForegroundColor Cyan
    # /verysilent: No GUI
    # /mergetasks=!runcode: Do not launch code after install
    Start-Process -FilePath $vscodeInstaller -ArgumentList "/verysilent /mergetasks=!runcode" -Wait

    Remove-Item $vscodeInstaller -ErrorAction SilentlyContinue
    Write-Host "Visual Studio Code installed successfully." -ForegroundColor Green
}

function Install-Fonts-Admin {
    Write-Host "Preparing to install fonts..." -ForegroundColor Cyan
    Write-Host "A UAC prompt will appear to authorize Font Installation (Requires Admin)." -ForegroundColor Yellow

    # We create a temporary script to handle the Admin-level work
    $fontScriptPath = "$env:TEMP\InstallFontsTemp.ps1"

    $scriptContent = @"
    `$ErrorActionPreference = 'Stop'
    Write-Host 'Downloading JetBrains Mono Font...' -ForegroundColor Cyan
    `$fontZip = "`$env:TEMP\JetBrainsMono.zip"
    `$fontExtractDir = "`$env:TEMP\JetBrainsMono"
    `$fontDest = "`$env:windir\Fonts"
    `$registryKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"

    try {
        # Download
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip" -OutFile `$fontZip

        # Extract
        Expand-Archive -Path `$fontZip -DestinationPath `$fontExtractDir -Force

        # Install
        `$ttfFiles = Get-ChildItem -Path `$fontExtractDir -Recurse -Filter "*.ttf"
        foreach (`$file in `$ttfFiles) {
            `$fileName = `$file.Name
            Copy-Item -Path `$file.FullName -Destination `$fontDest -Force

            # Registry Entry
            `$regValueName = `$file.BaseName + " (TrueType)"
            Set-ItemProperty -Path `$registryKey -Name `$regValueName -Value `$fileName
        }
        Write-Host "Fonts installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Error "Error installing fonts: `$_"
        Read-Host "Press Enter to close..."
    }
    finally {
        # Cleanup temp files inside the admin context
        Remove-Item `$fontZip -Force -ErrorAction SilentlyContinue
        Remove-Item `$fontExtractDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
"@

    # Save the heredoc to a file
    $scriptContent | Out-File -FilePath $fontScriptPath -Encoding UTF8

    # Run the temp script as Administrator
    try {
        Start-Process PowerShell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$fontScriptPath`"" -Wait
    }
    catch {
        Write-Warning "Font installation cancelled or failed."
    }

    # Cleanup the script file
    Remove-Item $fontScriptPath -ErrorAction SilentlyContinue
}

function Configure-VSCode {
    # 1. Close VS Code
    Write-Host "Closing running VSCode instances..." -ForegroundColor Cyan
    Get-Process -Name "Code" -ErrorAction SilentlyContinue | Stop-Process -Force

    # 2. Locate Code Executable
    $codeCommand = "code"
    # Current session won't see the new PATH variable immediately after install, so we look for the file directly
    $manualPath = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd"

    if (Test-Path $manualPath) {
        $codeCommand = $manualPath
    } elseif (-not (Get-Command "code" -ErrorAction SilentlyContinue)) {
        Write-Warning "Could not find 'code' command. Please restart PowerShell and try again."
        return
    }

    # 3. Install Extensions
    Write-Host "Installing extensions..." -ForegroundColor Cyan
    & $codeCommand --install-extension enkia.tokyo-night --force
    & $codeCommand --install-extension PKief.material-icon-theme --force

    # 4. Copy Settings
    Write-Host "Applying VSCode user settings..." -ForegroundColor Cyan
    # Assumes settings.json is in a folder named 'vscode' next to this script
    $settingsSource = Join-Path $PSScriptRoot "vscode\settings.json"
    $settingsDestDir = "$env:APPDATA\Code\User"
    $settingsDest = Join-Path $settingsDestDir "settings.json"

    if (Test-Path $settingsSource) {
        if (-not (Test-Path $settingsDestDir)) {
            New-Item -ItemType Directory -Path $settingsDestDir -Force | Out-Null
        }
        Copy-Item -Path $settingsSource -Destination $settingsDest -Force
        Write-Host "Settings applied." -ForegroundColor Green
    } else {
        Write-Warning "Source settings file not found at: $settingsSource"
        Write-Warning "Skipping 'settings.json' copy."
    }

    # 5. Install Fonts (Trigger separate Admin process)
    Install-Fonts-Admin
}

# --- Main Logic ---

Clear-Host
Write-Host "=== VS Code User Setup Script ===" -ForegroundColor Magenta

$vscodeInstalled = $false
if (Test-Path "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe") {
    $vscodeInstalled = $true
} elseif (Get-Command "code" -ErrorAction SilentlyContinue) {
    $vscodeInstalled = $true
}

if ($vscodeInstalled) {
    Write-Host "VSCode is detected." -ForegroundColor Yellow
    $response = (Read-Host "Do you want to re-apply the configuration? (y/n)").Trim().ToLower()
    if ($response -eq "y") {
        Configure-VSCode
    } else {
        Write-Host "Skipping configuration."
    }
} else {
    Write-Host "VSCode is NOT detected." -ForegroundColor Yellow
    $response = (Read-Host "Do you want to install VSCode? (y/n)").Trim().ToLower()
    if ($response -eq "y") {
        Install-VSCode

        # Ask to configure after install
        $responseConfig = (Read-Host "Do you want to apply the configuration? (y/n)").Trim().ToLower()
        if ($responseConfig -eq "y") {
            Configure-VSCode
        }
    } else {
        Write-Host "Skipping installation."
    }
}

Write-Host "Done." -ForegroundColor Green
Pause
