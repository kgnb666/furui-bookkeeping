# Stage 4-C step 3 verification helper (frontend integration).
# ASCII-only source: Chinese literals are built from Unicode code points so the
# script survives PowerShell 5.1 without a UTF-8 BOM.
$ErrorActionPreference = 'Stop'

$base = 'http://127.0.0.1:8080/api'
$cCanyin = [string]([char]0x9910) + [string]([char]0x996E)      # can yin
$cJiaotong = [string]([char]0x4EA4) + [string]([char]0x901A)    # jiao tong
$cGouwu = [string]([char]0x8D2D) + [string]([char]0x7269)       # gou wu

function Post-Json($uri, $payload, $token) {
    $json = $payload | ConvertTo-Json -Depth 6 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $headers = @{}
    if ($token) { $headers['Authorization'] = "Bearer $token" }
    return Invoke-RestMethod -Uri $uri -Method Post -Headers $headers `
        -ContentType 'application/json; charset=utf-8' -Body $bytes
}

# Windows PowerShell 5.1 falls back to Latin-1 when a JSON response carries no
# charset, so Chinese text comes back as mojibake. Re-encode to recover it.
function Fix-Text($s) {
    if ($null -eq $s -or $s -eq '') { return $s }
    $bytes = [System.Text.Encoding]::GetEncoding(28591).GetBytes([string]$s)
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Get-Json($uri, $token) {
    $headers = @{}
    if ($token) { $headers['Authorization'] = "Bearer $token" }
    return Invoke-RestMethod -Uri $uri -Method Get -Headers $headers
}

function Get-Status($uri, $token) {
    $headers = @{}
    if ($token) { $headers['Authorization'] = "Bearer $token" }
    try {
        $r = Invoke-WebRequest -Uri $uri -Method Get -Headers $headers -UseBasicParsing
        return [int]$r.StatusCode
    } catch {
        return [int]$_.Exception.Response.StatusCode
    }
}

function New-Account($name, $pass) {
    Post-Json "$base/auth/register" @{ username = $name; password = $pass; nickname = $name } | Out-Null
    $login = Post-Json "$base/auth/login" @{ username = $name; password = $pass }
    return $login.data.token
}

function Add-Bill($token, $type, $amount, $category, $date, $merchant) {
    Post-Json "$base/bills" @{
        type     = $type
        amount   = $amount
        category = $category
        billDate = $date
        merchant = $merchant
        remark   = 'stage4c-ui-verify'
    } $token | Out-Null
}

$ts = [DateTimeOffset]::Now.ToUnixTimeSeconds()
$pass = 'Test123456'
$userA = "st4cui_a_$ts"
$userB = "st4cui_b_$ts"

$tokenA = New-Account $userA $pass
$tokenB = New-Account $userB $pass

# --- user A: seed history + current month --------------------------------
# CATEGORY_SPIKE (HIGH): 400 / 400 / 400 -> 1200
Add-Bill $tokenA '1' 400 $cCanyin '2026-06-08' 'CanteenA'
Add-Bill $tokenA '1' 400 $cCanyin '2026-07-08' 'CanteenA'
Add-Bill $tokenA '1' 400 $cCanyin '2026-08-08' 'CanteenA'
Add-Bill $tokenA '1' 1200 $cCanyin '2026-09-08' 'CanteenA'

# FREQUENCY_SPIKE (MEDIUM): 3 -> 8 bills, each 10 (sum stays below the spike gap)
foreach ($d in @('2026-06-03', '2026-06-11', '2026-06-19')) { Add-Bill $tokenA '1' 10 $cJiaotong $d 'MetroLine' }
foreach ($d in @('2026-07-03', '2026-07-11', '2026-07-19')) { Add-Bill $tokenA '1' 10 $cJiaotong $d 'MetroLine' }
foreach ($d in @('2026-08-03', '2026-08-11', '2026-08-19')) { Add-Bill $tokenA '1' 10 $cJiaotong $d 'MetroLine' }
foreach ($d in @('2026-09-01', '2026-09-03', '2026-09-05', '2026-09-07', '2026-09-09', '2026-09-11', '2026-09-13', '2026-09-15')) {
    Add-Bill $tokenA '1' 10 $cJiaotong $d 'MetroLine'
}

# LARGE_TRANSACTION (HIGH): median 20 -> 300 on 2026-09-10
foreach ($d in @('2026-07-05', '2026-07-12', '2026-07-19', '2026-07-26', '2026-08-02')) {
    Add-Bill $tokenA '1' 20 $cGouwu $d 'CampusMart'
}
Add-Bill $tokenA '1' 300 $cGouwu '2026-09-10' 'DigitalStore'

# --- assertions ----------------------------------------------------------
$fail = @()

$resp = Get-Json "$base/insights/anomalies?month=2026-09" $tokenA
$data = $resp.data
Write-Output "A status      : $($data.status)"
Write-Output "A message     : $(Fix-Text $data.message)"
Write-Output "A baseline    : $($data.baselineMonths -join ',')"
Write-Output "A item count  : $($data.items.Count)"
foreach ($it in $data.items) {
    Write-Output ("  - {0}/{1} {2} | {3} | cur={4} base={5} diff={6} pct={7} merchant={8} date={9}" -f `
        $it.type, $it.severity, (Fix-Text $it.severityLabel), (Fix-Text $it.title), $it.currentAmount, `
        $it.baselineAmount, $it.difference, $it.changePercent, $it.merchant, $it.billDate)
}

if ($data.status -ne 'OK') { $fail += "A: expected status OK, got $($data.status)" }
if ($data.items.Count -lt 3) { $fail += "A: expected at least 3 anomaly items, got $($data.items.Count)" }
if ($data.items.Count -gt 5) { $fail += "A: expected at most 5 anomaly items, got $($data.items.Count)" }

$types = @($data.items | ForEach-Object { $_.type })
foreach ($want in @('CATEGORY_SPIKE', 'LARGE_TRANSACTION', 'FREQUENCY_SPIKE')) {
    if ($types -notcontains $want) { $fail += "A: missing anomaly type $want" }
}

$large = $data.items | Where-Object { $_.type -eq 'LARGE_TRANSACTION' } | Select-Object -First 1
if (-not $large) {
    $fail += 'A: LARGE_TRANSACTION payload missing'
} else {
    if (-not $large.merchant) { $fail += 'A: LARGE_TRANSACTION merchant is empty' }
    if (-not $large.billDate) { $fail += 'A: LARGE_TRANSACTION billDate is empty' }
    if ($large.currentAmount -ne '300.00') { $fail += "A: LARGE_TRANSACTION currentAmount=$($large.currentAmount)" }
}

$spike = $data.items | Where-Object { $_.type -eq 'CATEGORY_SPIKE' } | Select-Object -First 1
if (-not $spike) { $fail += 'A: CATEGORY_SPIKE payload missing' }
elseif ((Fix-Text $spike.category) -ne $cCanyin) { $fail += "A: CATEGORY_SPIKE category=$(Fix-Text $spike.category)" }

# user B must not see anything from user A
$respB = Get-Json "$base/insights/anomalies?month=2026-09" $tokenB
Write-Output "B status      : $($respB.data.status)"
Write-Output "B item count  : $($respB.data.items.Count)"
if ($respB.data.status -ne 'NO_DATA') { $fail += "B: expected NO_DATA, got $($respB.data.status)" }
if ($respB.data.items.Count -ne 0) { $fail += 'B: expected zero items' }

# not enough baseline account (one bill only)
$userC = "st4cui_c_$ts"
$tokenC = New-Account $userC $pass
Add-Bill $tokenC '1' 50 $cCanyin '2026-09-05' 'CanteenA'
$respC = Get-Json "$base/insights/anomalies?month=2026-09" $tokenC
Write-Output "C status      : $($respC.data.status)"
if ($respC.data.status -ne 'NOT_ENOUGH_BASELINE') { $fail += "C: expected NOT_ENOUGH_BASELINE, got $($respC.data.status)" }

# parameter + auth guards
$s401 = Get-Status "$base/insights/anomalies?month=2026-09" $null
$sBadFormat = Get-Status "$base/insights/anomalies?month=2026-9" $tokenA
$sOutOfRange = Get-Status "$base/insights/anomalies?month=2025-01" $tokenA
$sFuture = Get-Status "$base/insights/anomalies?month=2026-12" $tokenA
Write-Output "no token      : $s401"
Write-Output "bad format    : $sBadFormat"
Write-Output "out of range  : $sOutOfRange"
Write-Output "future month  : $sFuture"
if ($s401 -ne 401) { $fail += "auth: expected 401, got $s401" }
if ($sBadFormat -ne 400) { $fail += "month: expected 400, got $sBadFormat" }
if ($sOutOfRange -ne 400) { $fail += "month range: expected 400, got $sOutOfRange" }
if ($sFuture -ne 400) { $fail += "future month: expected 400, got $sFuture" }

# userId injection must not be honoured
$respInjected = Get-Json "$base/insights/anomalies?month=2026-09&userId=1" $tokenB
Write-Output "B + userId=1  : $($respInjected.data.status) / items=$($respInjected.data.items.Count)"
if ($respInjected.data.items.Count -ne 0) { $fail += 'injection: B received items through userId parameter' }

Write-Output ''
if ($fail.Count -gt 0) {
    Write-Output 'STAGE 4-C UI SELF CHECK FAILED'
    foreach ($f in $fail) { Write-Output " - $f" }
    exit 1
}
Write-Output 'STAGE 4-C UI SELF CHECK PASSED'
Write-Output "accountA=$userA accountB=$userB accountC=$userC"
