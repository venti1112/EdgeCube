# proto generated code sync check (Windows PowerShell)
#
# Regenerates openapi.yaml to a temp dir and diffs against committed gen/.
# Any diff means the spec and generated code are out of sync.
#
# Usage:
#   .\check.ps1            # Check all languages
#   .\check.ps1 dart       # Dart only
#   .\check.ps1 rust
#   .\check.ps1 kotlin
param(
    [ValidateSet("all", "dart", "rust", "kotlin")]
    [string]$Target = "all"
)

$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot

$Spec = "openapi.yaml"
$CLI = "2.40.1"

$GenConf = @{
    "dart"   = @{ G = "dart-dio"; L = "";       P = "pubName=edgecube_api_client,useEnumExtension=true,allowUnicodeIdentifiers=true" }
    "rust"   = @{ G = "rust";     L = "";       P = "packageName=edgecube_api" }
    "kotlin" = @{ G = "kotlin";   L = "jvm-ktor"; P = "packageName=com.venti1112.edgecube.api" }
}

function Log($msg) { Write-Host "[check] $msg" -ForegroundColor Cyan }

$tmp = Join-Path $env:TEMP "edgecube-check-$(Get-Random)"
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
    if ($Target -eq "all") { $langs = @("dart", "rust", "kotlin") }
    else { $langs = @($Target) }

    $fail = $false

    foreach ($lang in $langs) {
        $conf = $GenConf[$lang]
        $dest = "gen\$lang"

        if (!(Test-Path $dest)) {
            Log "$dest missing - run .\gen.ps1 first"
            $fail = $true
            continue
        }

        Log "Regenerating $lang ..."

        $extra = @()
        if ($conf.L) { $extra = @("--library=$($conf.L)") }

        npx --yes "@openapitools/openapi-generator-cli@$CLI" generate `
            -i $Spec -g $conf.G -o "$tmp\$lang" `
            --additional-properties=$($conf.P) @extra `
            --skip-validate-spec *> $null

        if ($lang -eq "dart") {
            Log "dart build_runner ..."
            Push-Location "$tmp\$lang"
            dart run build_runner build --delete-conflicting-outputs *> $null
            Pop-Location
        }

        Log "Comparing $lang ..."

        $skipNames = @('.gitignore', 'pubspec.lock')
        $skipDirs  = '\.dart_tool', '\\build\\', '\.gradle'

        $srcFiles = Get-ChildItem -Path $dest -Recurse -File |
            Where-Object { $skipNames -notcontains $_.Name } |
            Where-Object { $_.DirectoryName -notmatch ($skipDirs -join '|') }

        $tmpFiles = Get-ChildItem -Path "$tmp\$lang" -Recurse -File |
            Where-Object { $skipNames -notcontains $_.Name } |
            Where-Object { $_.DirectoryName -notmatch ($skipDirs -join '|') }

        $srcRel = $srcFiles | ForEach-Object { $_.FullName.Replace((Resolve-Path $dest).Path + "\", "") } | Sort-Object
        $tmpRel = $tmpFiles | ForEach-Object { $_.FullName.Replace((Resolve-Path "$tmp\$lang").Path + "\", "") } | Sort-Object

        $missing = Compare-Object $srcRel $tmpRel | Where-Object { $_.SideIndicator -eq '<=' }
        $extra   = Compare-Object $srcRel $tmpRel | Where-Object { $_.SideIndicator -eq '=>' }

        $hasDiff = $false

        if ($missing) {
            $hasDiff = $true
            Log "$lang files in gen but not in temp"
            $missing | ForEach-Object { Write-Host "  - $($_.InputObject)" -ForegroundColor Yellow }
        }
        if ($extra) {
            $hasDiff = $true
            Log "$lang files in temp but not in gen"
            $extra | ForEach-Object { Write-Host "  + $($_.InputObject)" -ForegroundColor Yellow }
        }

        foreach ($rel in $srcRel) {
            $sf = Join-Path $dest $rel
            $tf = Join-Path "$tmp\$lang" $rel
            if (!(Test-Path $tf)) { continue }
            $h1 = (Get-FileHash $sf -Algorithm MD5).Hash
            $h2 = (Get-FileHash $tf -Algorithm MD5).Hash
            if ($h1 -ne $h2) {
                $hasDiff = $true
                Log "$lang content differs: $rel"
            }
        }

        if ($hasDiff) {
            Log "$lang OUT OF SYNC"
            $fail = $true
        } else {
            Log "$lang OK"
        }
    }

    if ($fail) { exit 1 }
    Log "All OK"
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
