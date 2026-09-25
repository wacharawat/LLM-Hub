#Requires -Version 5.1
<#
  LLM-Hub - one-click iOS build (from Windows)
  สั่ง GitHub Actions (macOS runner) build IPA ให้ แล้วดาวน์โหลดลง dist\

  Usage:
    .\scripts\build-ios.ps1

  ต้องมี: GitHub CLI (https://cli.github.com) + gh auth login แล้ว
  ไม่มี gh? จะเปิดหน้า Actions ให้กด "Run workflow" เอง แล้วโหลดไฟล์จากเว็บ
#>
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

# detect repo from git remote
$repo = "wacharawat/LLM-Hub"
try {
    $url = (git -C $root remote get-url origin) 2>$null
    if ($url -match 'github\.com[:/]([^/]+)/([^/\s]+?)(\.git)?$') { $repo = "$($Matches[1])/$($Matches[2])" }
} catch {}

$workflow = "build-ios-ipa.yml"
$page = "https://github.com/$repo/actions/workflows/$workflow"

function Get-Run {
    gh run list --repo $repo --workflow $workflow --limit 1 --json databaseId,status,conclusion,url,createdAt --jq '.[0]' 2>$null |
        ConvertFrom-Json
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "ไม่พบ GitHub CLI — เปิดหน้า Actions ให้กดปุ่ม 'Run workflow' แล้วโหลดไฟล์ IPA เอง" -ForegroundColor Yellow
    Start-Process $page
    exit 0
}

$authOk = $false
gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { $authOk = $true }
if (-not $authOk) {
    Write-Host "ยังไม่ได้ login — รัน: gh auth login" -ForegroundColor Red
    Start-Process $page
    exit 1
}

Write-Host "== สั่ง build iOS บน GitHub Actions ($repo) ==" -ForegroundColor Cyan
$before = (Get-Run).databaseId

gh workflow run $workflow --repo $repo --ref main
if ($LASTEXITCODE -ne 0) { Write-Host "[X] สั่ง workflow ไม่สำเร็จ" -ForegroundColor Red; exit 1 }
Write-Host "สั่งแล้ว — รอ CI build (ปกติ 15-45 นาที)"

# wait for the NEW run to appear
$run = $null
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep 5
    $run = Get-Run
    if ($run -and $run.databaseId -ne $before) { break }
    Write-Host "." -NoNewline
}
if (-not $run -or $run.databaseId -eq $before) {
    Write-Host "`n[!] ยังไม่เห็น run ใหม่ — เปิดดูเอง: $page" -ForegroundColor Yellow
    exit 1
}
Write-Host "`nRun: $($run.url)"

# wait until completed
while ($run.status -ne "completed") {
    Start-Sleep 20
    $run = Get-Run
    if (-not $run) { break }
    Write-Host "." -NoNewline
}
Write-Host ""

if ($run.conclusion -ne "success") {
    Write-Host "[X] Build ล้มเหลว — ดู log: $($run.url)" -ForegroundColor Red
    Start-Process $run.url
    exit 1
}

$dist = Join-Path $root "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null
gh run download $run.databaseId --repo $repo --name LLMHub-ipa --dir $dist
if ($LASTEXITCODE -ne 0) { Write-Host "[X] ดาวน์โหลด IPA ไม่สำเร็จ" -ForegroundColor Red; exit 1 }

$ipa = Get-ChildItem $dist -Filter "*.ipa" | Sort-Object LastWriteTime | Select-Object -Last 1
Write-Host "`n[OK] IPA พร้อมใช้:" -ForegroundColor Green
Write-Host "  $($ipa.FullName)"
Write-Host "`nลงมือถือ iPhone:" -ForegroundColor Cyan
Write-Host "  1. เปิด Sideloadly (https://sideloadly.io) บน Windows"
Write-Host "  2. เสียบ iPhone → เลือกอุปกรณ์ → ลากไฟล์ .ipa ใส่ -> Start"
Write-Host "  (Apple ID ฟรีเซ็นมีอายุ 7 วัน ต้องทำซ้ำทุกสัปดาห์)"
