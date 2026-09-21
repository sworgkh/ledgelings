# Build a release Ledgelings.exe for Windows x64: one self-contained folder under win/build.
#   powershell -ExecutionPolicy Bypass -File win/publish.ps1
#   powershell -ExecutionPolicy Bypass -File win/publish.ps1 -SingleFile   # one exe, needs no .NET installed
param([switch]$SingleFile)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$out = Join-Path $PSScriptRoot "build"
$args = @("publish", "Ledgelings/Ledgelings.csproj", "-c", "Release", "-r", "win-x64", "-o", $out, "-nologo")
if ($SingleFile) { $args += @("--self-contained", "true", "-p:PublishSingleFile=true", "-p:IncludeNativeLibrariesForSelfExtract=true") }
else { $args += @("--self-contained", "false") }
& dotnet @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "built $out\Ledgelings.exe"
