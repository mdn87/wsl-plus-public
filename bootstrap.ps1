[CmdletBinding()]
param(
    [Parameter()]
    [string]$Distro,

    [Parameter()]
    [ValidateSet('home', 'restricted')]
    [string]$Policy = 'home',

    [Parameter()]
    [string]$Integration,

    [Parameter()]
    [ValidateSet('managed', 'augment')]
    [string]$Mode,

    [Parameter()]
    [switch]$Check,

    [Parameter()]
    [string]$ApplyPlan,

    [Parameter()]
    [switch]$SkipPackages
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WslExecutable {
    $candidate = Join-Path $env:WINDIR 'System32\wsl.exe'
    if (Test-Path -LiteralPath $candidate) {
        return $candidate
    }

    $command = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw 'wsl.exe was not found.'
    }
    return $command.Source
}

function Get-DefaultDistro {
    param([Parameter(Mandatory)][string]$WslExecutable)

    $items = & $WslExecutable --list --quiet
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to list WSL distributions.'
    }

    $clean = @(
        $items |
            ForEach-Object { ($_ -replace "`0", '').Trim() } |
            Where-Object { $_ }
    )

    if ($clean.Count -eq 0) {
        throw 'No WSL distributions are installed.'
    }

    return $clean[0]
}

function ConvertTo-NativeQuotedArgument {
    param([Parameter(Mandatory)][string]$Value)

    if ($Value -notmatch '[\s"]') {
        return $Value
    }

    $escaped = $Value -replace '(\\*)"', '$1$1\"'
    $escaped = $escaped -replace '(\\+)$', '$1$1'
    return '"' + $escaped + '"'
}

function Invoke-WslBinaryPipe {
    param(
        [Parameter(Mandatory)][string]$WslExecutable,
        [Parameter(Mandatory)][string]$Distribution,
        [Parameter(Mandatory)][string]$LinuxCommand,
        [Parameter(Mandatory)][string]$InputFile
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $WslExecutable
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true

    $arguments = @('-d', $Distribution, '--', 'bash', '-lc', $LinuxCommand)
    if ($startInfo.PSObject.Properties.Name -contains 'ArgumentList') {
        foreach ($argument in $arguments) {
            [void]$startInfo.ArgumentList.Add($argument)
        }
    }
    else {
        $startInfo.Arguments = ($arguments | ForEach-Object { ConvertTo-NativeQuotedArgument $_ }) -join ' '
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw 'Failed to start wsl.exe.'
    }

    $inputStream = [System.IO.File]::OpenRead($InputFile)
    $standardInput = $process.StandardInput.BaseStream
    try {
        $inputStream.CopyTo($standardInput)
        $standardInput.Flush()
    }
    finally {
        $inputStream.Dispose()
        $standardInput.Dispose()
    }

    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if ($stdout) {
        Write-Host $stdout.TrimEnd()
    }
    if ($stderr) {
        Write-Host $stderr.TrimEnd()
    }
    if ($process.ExitCode -ne 0) {
        throw "WSL archive transfer failed with exit code $($process.ExitCode)."
    }
}

$wsl = Get-WslExecutable
if (-not $Distro) {
    $Distro = Get-DefaultDistro -WslExecutable $wsl
}

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$tar = Get-Command tar.exe -ErrorAction SilentlyContinue
if ($null -eq $tar) {
    throw 'tar.exe was not found. It is included with current Windows releases.'
}

$tempArchive = Join-Path ([System.IO.Path]::GetTempPath()) ("wsl-plus-{0}.tar.gz" -f [Guid]::NewGuid().ToString('N'))
$remoteRoot = '$HOME/.local/share/wsl-plus/bootstrap/current'

try {
    & $tar.Source -czf $tempArchive --exclude=.git --exclude='*.log' -C $repoRoot .
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to create the WSL Plus transfer archive.'
    }

    $extractCommand = "set -euo pipefail; rm -rf `"$remoteRoot`"; mkdir -p `"$remoteRoot`"; tar -xzf - -C `"$remoteRoot`"; find `"$remoteRoot`" -type f \( -name '*.sh' -o -name '*.bash' -o -name '*.conf' -o -name '*.apt' -o -name '*.toml' \) -exec sed -i 's/$//' {} +; sed -i 's/$//' `"$remoteRoot/bin/wsl-plus`" `"$remoteRoot/bin/wsl-plus-session`"; chmod 0755 `"$remoteRoot/install.sh`" `"$remoteRoot/doctor.sh`" `"$remoteRoot/rollback.sh`" `"$remoteRoot/bin/wsl-plus`" `"$remoteRoot/bin/wsl-plus-session`""
    $extractCommand += "; sed -i 's/\x0D$//' `"$remoteRoot/bin/wsl-plus-ssh-agent`"; chmod 0755 `"$remoteRoot/bin/wsl-plus-ssh-agent`""
    Invoke-WslBinaryPipe -WslExecutable $wsl -Distribution $Distro -LinuxCommand $extractCommand -InputFile $tempArchive

    # Integration and mode are omitted unless the caller asked for a specific
    # one, so defaults/<policy>.conf stays the single source of truth.
    $installerArguments = @('--policy', $Policy)
    if ($Integration) {
        $installerArguments += @('--integration', $Integration)
    }
    if ($Mode) {
        $installerArguments += @('--mode', $Mode)
    }
    if ($Check) {
        $installerArguments += '--check'
    }
    if ($ApplyPlan) {
        $installerArguments += @('--apply-plan', $ApplyPlan)
    }
    if ($SkipPackages) {
        $installerArguments += '--skip-packages'
    }

    $quotedArguments = $installerArguments | ForEach-Object {
        $singleQuote = [string][char]39
        $doubleQuote = [string][char]34
        $shellEscape = $singleQuote + $doubleQuote + $singleQuote + $doubleQuote + $singleQuote
        $singleQuote + $_.Replace($singleQuote, $shellEscape) + $singleQuote
    }
    $installCommand = "cd `"$remoteRoot`" && ./install.sh " + ($quotedArguments -join ' ')

    & $wsl -d $Distro -- bash -lc $installCommand
    if ($LASTEXITCODE -ne 0) {
        throw "WSL Plus installer failed with exit code $LASTEXITCODE."
    }
}
finally {
    Remove-Item -LiteralPath $tempArchive -Force -ErrorAction SilentlyContinue
}
