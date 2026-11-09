param (
    [Alias("Local")]
    [switch]$Sign = $false
)

$ErrorActionPreference = "Stop"

if ($args -contains "--Local" -or $args -contains "--Sign" -or $args -contains "-Local" -or $args -contains "-Sign") {
    $Sign = $true
}

# Clean up debug JIT cache (kernel_blob.bin ~105MB) from previous flutter run
Remove-Item -Force -ErrorAction SilentlyContinue "build/flutter_assets/kernel_blob.bin", "build/windows/x64/runner/Release/data/flutter_assets/kernel_blob.bin"

# Resolve LASTFM_SECRET if not explicitly set in current shell session
if (-not $env:LASTFM_SECRET) {
    $userEnv = [Environment]::GetEnvironmentVariable("LASTFM_SECRET", "User")
    if ($userEnv) {
        $env:LASTFM_SECRET = $userEnv
    } else {
        $machineEnv = [Environment]::GetEnvironmentVariable("LASTFM_SECRET", "Machine")
        if ($machineEnv) {
            $env:LASTFM_SECRET = $machineEnv
        }
    }
}

if (-not $env:LASTFM_SECRET) {
    $envFiles = @(".env", ".env.local")
    foreach ($file in $envFiles) {
        if (Test-Path $file) {
            $match = Get-Content $file | Where-Object { $_ -match '^\s*LASTFM_SECRET\s*=' } | Select-Object -Last 1
            if ($match) {
                $env:LASTFM_SECRET = ($match -replace '^\s*LASTFM_SECRET\s*=\s*', '').Trim(' "''')
                break
            }
        }
    }
}

if ($env:LASTFM_SECRET) {
    Write-Host "[MSIX Build] Injected LASTFM_SECRET into build." -ForegroundColor Green
} else {
    Write-Warning "[MSIX Build] LASTFM_SECRET is not set! Scrobbling will be disabled in this MSIX build."
}

Write-Host "Building Windows application in release mode..." -ForegroundColor Cyan
flutter build windows --release --no-tree-shake-icons --dart-define=CHANNEL=store --dart-define=LASTFM_SECRET="$env:LASTFM_SECRET"
if ($LASTEXITCODE -ne 0) {
    Write-Error "flutter build windows failed with exit code $LASTEXITCODE. Aborting MSIX packaging."
    exit $LASTEXITCODE
}

# Ensure no leftover kernel_blob.bin in Release before packaging
Remove-Item -Force -ErrorAction SilentlyContinue "build/windows/x64/runner/Release/data/flutter_assets/kernel_blob.bin"

# Bundle VC Runtime DLLs into Release directory before packaging MSIX
$dlls = @("msvcp140.dll", "msvcp140_1.dll", "msvcp140_2.dll", "msvcp140_codecvt_ids.dll", "vcruntime140.dll", "vcruntime140_1.dll", "vcruntime140_threads.dll")
$destDir = "build/windows/x64/runner/Release"
foreach ($dll in $dlls) {
    $sysPath = Join-Path $env:SystemRoot "System32\$dll"
    if (Test-Path $sysPath) {
        Copy-Item $sysPath -Destination $destDir -Force
        Write-Host "Bundled $dll into Release directory."
    }
}

Write-Host "Packaging MSIX..." -ForegroundColor Cyan
dart run msix:create --build-windows false
if ($LASTEXITCODE -ne 0) {
    Write-Error "msix:create failed with exit code $LASTEXITCODE."
    exit $LASTEXITCODE
}

# Only sign when requested for local testing
if ($Sign) {
    powershell -ExecutionPolicy Bypass -File .\sign_msix.ps1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "sign_msix.ps1 failed with exit code $LASTEXITCODE."
        exit $LASTEXITCODE
    }
} else {
    Write-Host "Built unsigned MSIX ready for Microsoft Store submission."
    Write-Host "Tip: Run '.\build_msix.ps1 -Sign' (or '-Local') to build and sign for local testing."
}