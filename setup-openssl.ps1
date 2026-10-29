[CmdletBinding()]
param(
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$version = '3.5.9'
$installerUrl = 'https://slproweb.com/download/Win64OpenSSL_Light-3_5_9.exe'
$expectedSha256 = '9f4773a32d8a5da770f57ff5ef2dfa7f6c28e9eef2f5bc2e25ac54e6ee1581dc'

function Show-Usage {
    $scriptName = Split-Path -Leaf $PSCommandPath
    Write-Host "Usage: .\$scriptName"
    Write-Host "Downloads and installs OpenSSL $version (3.5 LTS) for this user."
    Write-Host 'The installer is SHA-256 verified before it is launched.'
}

if ($Help) {
    Show-Usage
    exit 0
}

try {
    if (-not [Environment]::Is64BitOperatingSystem -or
        $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
        throw 'This script currently supports 64-bit Intel/AMD Windows only.'
    }

    $installRoot = Join-Path $HOME ".local\pfx-upgrade\openssl-$version"
    $opensslPath = Join-Path $installRoot 'bin\openssl.exe'
    if (Test-Path -LiteralPath $opensslPath -PathType Leaf) {
        $installedVersion = (& $opensslPath version 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $installedVersion -match "^OpenSSL\s+$([regex]::Escape($version))\b") {
            & $opensslPath list -providers -provider-path (Split-Path -Parent $opensslPath) -provider legacy
            if ($LASTEXITCODE -ne 0) {
                throw 'The installed OpenSSL legacy provider could not be loaded.'
            }
            Write-Host "OpenSSL $version is already available at $opensslPath"
            exit 0
        }
        throw "The target already contains an unexpected OpenSSL installation: $installRoot"
    }
    if (Test-Path -LiteralPath $installRoot) {
        throw "The target already exists; move it aside or remove it before setup: $installRoot"
    }

    $downloadDirectory = Join-Path $HOME '.local\pfx-upgrade\downloads'
    [void][IO.Directory]::CreateDirectory($downloadDirectory)
    $installerPath = Join-Path $downloadDirectory "Win64OpenSSL_Light-3_5_9.exe"

    Write-Progress -Activity 'Setting up OpenSSL 3.5.9' -Status 'Downloading Windows installer' -PercentComplete 10
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath

    Write-Progress -Activity 'Setting up OpenSSL 3.5.9' -Status 'Verifying installer SHA-256' -PercentComplete 65
    $actualSha256 = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualSha256 -ne $expectedSha256) {
        Remove-Item -LiteralPath $installerPath -Force
        throw "Installer checksum mismatch. Expected $expectedSha256; received $actualSha256."
    }

    Write-Progress -Activity 'Setting up OpenSSL 3.5.9' -Status 'Run the installer and accept its prompts' -PercentComplete 80
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $installRoot))
    $installer = Start-Process -FilePath $installerPath `
        -ArgumentList "/DIR=`"$installRoot`"" -Wait -PassThru
    if ($installer.ExitCode -ne 0) {
        throw "OpenSSL installer exited with code $($installer.ExitCode)."
    }

    if (-not (Test-Path -LiteralPath $opensslPath -PathType Leaf)) {
        throw "Installer completed, but OpenSSL was not found at the expected path: $opensslPath"
    }
    $installedVersion = (& $opensslPath version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $installedVersion -notmatch "^OpenSSL\s+$([regex]::Escape($version))\b") {
        throw "Installed OpenSSL version could not be verified: $installedVersion"
    }
    & $opensslPath list -providers -provider-path (Split-Path -Parent $opensslPath) -provider legacy
    if ($LASTEXITCODE -ne 0) {
        throw 'The installed OpenSSL legacy provider could not be loaded.'
    }

    Write-Progress -Activity 'Setting up OpenSSL 3.5.9' -Completed
    Write-Host "OpenSSL $version installed at $opensslPath"
}
catch {
    Write-Progress -Activity 'Setting up OpenSSL 3.5.9' -Completed
    [Console]::Error.WriteLine("Error: {0}", $_.Exception.Message)
    exit 1
}
