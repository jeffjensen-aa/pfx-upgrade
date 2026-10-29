[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$InputPfx,

    [Parameter(Position = 1)]
    [string]$OutputPfx,

    [Parameter(Position = 2)]
    [string]$ChainFile,

    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Show-Usage {
    $scriptName = Split-Path -Leaf $PSCommandPath
    Write-Host "Usage: .\$scriptName <input.pfx> <output.pfx> [chain.pem]"
    Write-Host 'Converts a legacy PFX to an OpenSSL 3-compatible PFX.'
    Write-Host 'OpenSSL interactively prompts for source, key, and output passwords.'
}

function Show-Progress {
    param(
        [Parameter(Mandatory)]
        [int]$Percent,

        [Parameter(Mandatory)]
        [string]$Label
    )

    $filled = [Math]::Floor($Percent / 10)
    $bar = ('#' * $filled).PadRight(10, '-')
    Write-Host "[$bar] $($Percent.ToString().PadLeft(3))% $Label"
}

function Invoke-OpenSsl {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $providerDirectory = Split-Path -Parent $script:OpenSslPath
    $providerArguments = @()
    if (Test-Path -LiteralPath (Join-Path $providerDirectory 'legacy.dll') -PathType Leaf) {
        $providerArguments = @('-provider-path', $providerDirectory)
    }
    & $script:OpenSslPath @Arguments @providerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "OpenSSL failed with exit code $LASTEXITCODE."
    }
}

if ($Help) {
    Show-Usage
    exit 0
}

if ([string]::IsNullOrWhiteSpace($InputPfx) -or
    [string]::IsNullOrWhiteSpace($OutputPfx)) {
    Show-Usage
    exit 2
}

$tempDirectory = $null

try {
    $inputPath = [IO.Path]::GetFullPath($InputPfx)
    $outputPath = [IO.Path]::GetFullPath($OutputPfx)
    $outputDirectory = Split-Path -Parent $outputPath

    if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
        throw "Input PFX not found: $inputPath"
    }
    if (Test-Path -LiteralPath $outputPath) {
        throw "Output already exists: $outputPath"
    }
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        throw "Output directory not found: $outputDirectory"
    }

    $chainPath = $null
    if (-not [string]::IsNullOrWhiteSpace($ChainFile)) {
        $chainPath = [IO.Path]::GetFullPath($ChainFile)
        if (-not (Test-Path -LiteralPath $chainPath -PathType Leaf)) {
            throw "Chain file not found: $chainPath"
        }
    }

    $localOpenSsl = Join-Path $HOME '.local\pfx-upgrade\openssl-3.5.9\bin\openssl.exe'
    if (Test-Path -LiteralPath $localOpenSsl -PathType Leaf) {
        $script:OpenSslPath = $localOpenSsl
    }
    else {
        $opensslCommand = Get-Command openssl -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $opensslCommand) {
            throw 'OpenSSL was not found. Run setup-openssl.ps1 or add OpenSSL 3 to PATH.'
        }
        $script:OpenSslPath = $opensslCommand.Source
    }

    $versionOutput = & $script:OpenSslPath version 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to determine the OpenSSL version.'
    }
    $versionText = ($versionOutput | ForEach-Object { "$_" }) -join ' '
    if ($versionText -notmatch '^OpenSSL\s+3\.') {
        throw "OpenSSL 3.x is required for -legacy support; found: $versionText"
    }

    $tempDirectory = Join-Path $outputDirectory ('.pfx-upgrade-' + [Guid]::NewGuid().ToString('N'))
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $directorySecurity = [Security.AccessControl.DirectorySecurity]::new()
    $directorySecurity.SetAccessRuleProtection($true, $false)
    $directorySecurity.SetOwner($currentSid)
    $accessRule = [Security.AccessControl.FileSystemAccessRule]::new(
        $currentSid,
        [Security.AccessControl.FileSystemRights]::FullControl,
        [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
            [Security.AccessControl.InheritanceFlags]::ObjectInherit,
        [Security.AccessControl.PropagationFlags]::None,
        [Security.AccessControl.AccessControlType]::Allow
    )
    $directorySecurity.AddAccessRule($accessRule)
    [void][IO.Directory]::CreateDirectory($tempDirectory)
    Set-Acl -LiteralPath $tempDirectory -AclObject $directorySecurity

    Show-Progress 10 'Extracting certificate (OpenSSL may prompt for the PFX password)'
    Invoke-OpenSsl -Arguments @(
        'pkcs12', '-legacy', '-in', $inputPath, '-clcerts', '-nokeys',
        '-out', (Join-Path $tempDirectory 'cert.pem')
    )

    Show-Progress 40 'Extracting encrypted private key (OpenSSL will prompt for passwords)'
    Invoke-OpenSsl -Arguments @(
        'pkcs12', '-legacy', '-in', $inputPath, '-nocerts',
        '-out', (Join-Path $tempDirectory 'key.pem')
    )

    $exportArguments = @(
        'pkcs12', '-export', '-in', (Join-Path $tempDirectory 'cert.pem'),
        '-inkey', (Join-Path $tempDirectory 'key.pem')
    )
    if ($chainPath) {
        $exportArguments += @('-certfile', $chainPath)
    }
    $stagedPfx = Join-Path $tempDirectory 'new.pfx'
    $exportArguments += @('-out', $stagedPfx)

    Show-Progress 75 'Exporting new PFX (OpenSSL will prompt for passwords)'
    Invoke-OpenSsl -Arguments $exportArguments

    [IO.File]::Move($stagedPfx, $outputPath)
    Show-Progress 100 "Conversion complete: $outputPath"
}
catch {
    [Console]::Error.WriteLine("Error: {0}", $_.Exception.Message)
    exit 1
}
finally {
    if ($tempDirectory -and (Test-Path -LiteralPath $tempDirectory)) {
        try {
            Remove-Item -LiteralPath $tempDirectory -Recurse -Force -ErrorAction Stop
        }
        catch {
            [Console]::Error.WriteLine(
                'Warning: unable to remove temporary directory: {0}',
                $tempDirectory
            )
        }
    }
}
