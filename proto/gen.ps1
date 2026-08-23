# EdgeCube proto code generator (Windows PowerShell)
#
# Usage:
#   .\gen.ps1            # Generate all languages
#   .\gen.ps1 dart       # Dart only (Flutter UI client, dio)
#   .\gen.ps1 rust       # Rust only (desktop daemon reference)
#   .\gen.ps1 kotlin     # Kotlin only (Android daemon reference)
#
# Requires: Java 17+, npm/npx
param(
    [ValidateSet("all", "dart", "rust", "kotlin")]
    [string]$Target = "all"
)

$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot

$Spec = "openapi.yaml"
$CLI = "2.40.1"

function Log($msg) { Write-Host "[gen] $msg" -ForegroundColor Cyan }
function Err($msg) { Write-Host "[gen] $msg" -ForegroundColor Red; exit 1 }

if (!(Test-Path $Spec)) { Err "Spec not found: $Spec" }
if (!(Get-Command java -EA SilentlyContinue)) { Err "Java 17+ required" }

function Gen-Dart {
    $dest = if ($env:DEST) { $env:DEST } else { "gen\dart" }
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    Log "Generating Dart (dart-dio) -> $dest"
    npx --yes "@openapitools/openapi-generator-cli@$CLI" generate -i $Spec -g dart-dio -o $dest --additional-properties="pubName=edgecube_api_client,useEnumExtension=true,allowUnicodeIdentifiers=true" --skip-validate-spec
    if (!(Get-Command dart -EA SilentlyContinue)) { Err "dart required for build_runner" }
    Log "Running build_runner ..."
    Push-Location $dest
    dart run build_runner build --delete-conflicting-outputs *> $null
    Pop-Location
    Log "Dart done: $dest"
}

function Gen-Rust {
    $dest = if ($env:DEST) { $env:DEST } else { "gen\rust" }
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    Log "Generating Rust -> $dest"
    npx --yes "@openapitools/openapi-generator-cli@$CLI" generate -i $Spec -g rust -o $dest --additional-properties="packageName=edgecube_api" --skip-validate-spec
    Log "Rust done: $dest"
}

function Gen-Kotlin {
    $dest = if ($env:DEST) { $env:DEST } else { "gen\kotlin" }
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    Log "Generating Kotlin (ktor) -> $dest"
    npx --yes "@openapitools/openapi-generator-cli@$CLI" generate -i $Spec -g kotlin -o $dest --library=jvm-ktor --additional-properties="packageName=com.venti1112.edgecube.api" --skip-validate-spec
    Log "Kotlin done: $dest"
}

switch ($Target) {
    "all"    { Gen-Dart; Gen-Rust; Gen-Kotlin }
    "dart"   { Gen-Dart }
    "rust"   { Gen-Rust }
    "kotlin" { Gen-Kotlin }
}

Log "Done. Run .\check.ps1 to verify sync."
