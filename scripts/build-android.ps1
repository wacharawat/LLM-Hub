#Requires -Version 5.1
<#
  LLM-Hub - one-click Android build (Windows)
  Builds a PREMIUM-UNLOCKED debug APK (DEBUG_PREMIUM=true).

  Usage:
    .\scripts\build-android.ps1            # build APK -> dist\
    .\scripts\build-android.ps1 -Install   # build + install to connected device (adb)
    .\scripts\build-android.ps1 -Clean     # clean then build

  Requirements:
    - JDK 17+  (https://adoptium.net)
    - Android SDK (Android Studio หรือ standalone) + env ANDROID_HOME
    - NDK 29.0.13113456 / CMake 3.31.6 (script จะติดตั้งให้เองถ้า sdkmanager เจอ)
#>
param(
    [switch]$Install,
    [switch]$Clean
)

$ErrorActionPreference = "Stop"
$root  = Split-Path -Parent $PSScriptRoot
$android = Join-Path $root "android"
$NDK_VER   = "29.0.13113456"
$CMAKE_VER = "3.31.6"

Write-Host "== LLM-Hub Android auto build ==" -ForegroundColor Cyan

# ---------- 1. Java ----------
$javaExe = $null
if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME "bin\java.exe"))) {
    $javaExe = Join-Path $env:JAVA_HOME "bin\java.exe"
} elseif (Get-Command java -ErrorAction SilentlyContinue) {
    $javaExe = "java"
}
if (-not $javaExe) {
    Write-Host "[X] ไม่พบ Java — ติดตั้ง JDK 17+ ก่อน: https://adoptium.net" -ForegroundColor Red
    exit 1
}
$javaLine = (& $javaExe -version 2>&1 | Select-Object -First 1) -join ""
Write-Host "Java : $javaLine"
$major = 0
if ($javaLine -match 'version "(\d+)') { $major = [int]$Matches[1] }
elseif ($javaLine -match '(\d+)\.\d+\.\d+') { $major = [int]$Matches[1] }
if ($major -lt 17) {
    Write-Host "[X] ต้องใช้ JDK 17+ (เจอ $major)" -ForegroundColor Red
    exit 1
}

# ---------- 2. Android SDK ----------
$sdk = $env:ANDROID_HOME
if (-not $sdk) { $sdk = $env:ANDROID_SDK_ROOT }
$lpPath = Join-Path $android "local.properties"
$props = New-Object 'System.Collections.Generic.Dictionary[string,string]'
if (Test-Path $lpPath) {
    Get-Content $lpPath | ForEach-Object {
        if ($_ -match '^\s*([^#=!]+)\s*=\s*(.*)$') { $props[$Matches[1].Trim()] = $Matches[2].Trim() }
    }
    if (-not $sdk -and $props.ContainsKey("sdk.dir")) {
        $sdk = $props["sdk.dir"] -replace '\\\\', '\' -replace '^\\"', ''
    }
}
if (-not $sdk -or -not (Test-Path $sdk)) {
    Write-Host "[X] ไม่พบ Android SDK — ติดตั้ง Android Studio หรือตั้ง ANDROID_HOME" -ForegroundColor Red
    exit 1
}
Write-Host "SDK  : $sdk"

# ---------- 3. local.properties (sdk.dir + DEBUG_PREMIUM=true) ----------
$sdkDirWin = $sdk -replace '\\', '/'
$props["sdk.dir"] = $sdkDirWin
$props["DEBUG_PREMIUM"] = "true"
$lines = foreach ($k in $props.Keys) { "$k=$($props[$k])" }
Set-Content -Path $lpPath -Value ($lines -join "`r`n") -Encoding ASCII
Write-Host "local.properties -> DEBUG_PREMIUM=true (ปลดพรีเมียม)"

# ---------- 4. NDK / CMake ----------
function Ensure-SdkComponent([string]$id, [string]$dir, [string]$label) {
    if (Test-Path $dir) { return }
    Write-Host "ยังไม่มี $label — กำลังติดตั้ง $id ..."
    $candidates = @()
    $candidates += Join-Path $sdk "cmdline-tools\latest\bin\sdkmanager.bat"
    $ct = Join-Path $sdk "cmdline-tools"
    if (Test-Path $ct) {
        Get-ChildItem $ct -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $candidates += Join-Path $_.FullName "bin\sdkmanager.bat"
        }
    }
    $sm = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $sm) {
        Write-Host "[!] ไม่พบ sdkmanager — ให้ Gradle ดาวน์โหลดเอง หรือเปิด Android Studio แล้ว Tools > SDK Manager" -ForegroundColor Yellow
        return
    }
    cmd /c "(for /l %i in (1,1,30) do @echo y) | `"$sm`" --licenses >nul 2>&1"
    cmd /c "`"$sm`" `"$id`""
    if (-not (Test-Path $dir)) {
        Write-Host "[!] ติดตั้ง $label ไม่สำเร็จ — ลองติดตั้งเอง: sdkmanager `"$id`"" -ForegroundColor Yellow
    }
}
Ensure-SdkComponent "ndk;$NDK_VER"   (Join-Path $sdk "ndk\$NDK_VER")   "NDK $NDK_VER"
Ensure-SdkComponent "cmake;$CMAKE_VER" (Join-Path $sdk "cmake\$CMAKE_VER") "CMake $CMAKE_VER"

# ---------- 5. Build ----------
Push-Location $android
try {
    if ($Clean) { & .\gradlew.bat clean; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE } }
    Write-Host "`n>> gradlew assembleDebug ..." -ForegroundColor Cyan
    & .\gradlew.bat assembleDebug
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[X] Build ล้มเหลว (exit $LASTEXITCODE)" -ForegroundColor Red
        exit $LASTEXITCODE
    }
} finally { Pop-Location }

# ---------- 6. Collect APK ----------
$apk = Get-ChildItem (Join-Path $android "app\build\outputs\apk") -Recurse -Filter "*.apk" -ErrorAction SilentlyContinue |
       Sort-Object LastWriteTime | Select-Object -Last 1
if (-not $apk) { Write-Host "[X] ไม่เจอไฟล์ APK" -ForegroundColor Red; exit 1 }

$dist = Join-Path $root "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$outName = "LLMHub-premium-{0:yyyyMMdd-HHmm}.apk" -f (Get-Date)
$out = Join-Path $dist $outName
Copy-Item $apk.FullName $out -Force

$mb = [math]::Round($apk.Length / 1MB, 1)
Write-Host "`n[OK] APK พร้อมใช้ ($mb MB):" -ForegroundColor Green
Write-Host "  $out"

# ---------- 7. Optional install ----------
if ($Install) {
    if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
        Write-Host "[X] ไม่พบ adb — เพิ่ม platform-tools ลง PATH" -ForegroundColor Red; exit 1
    }
    $devices = (adb devices) -join "`n"
    if ($devices -notmatch "`tdevice") {
        Write-Host "[X] ไม่พบมือถือที่เชื่อมต่อ (เปิด USB debugging แล้วเสียบสาย)" -ForegroundColor Red; exit 1
    }
    adb install -r $out
    Write-Host "[OK] ลงมือถือแล้ว" -ForegroundColor Green
}
