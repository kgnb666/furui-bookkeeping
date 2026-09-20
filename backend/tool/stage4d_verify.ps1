# Stage 4-D self check: next-month spending forecast (real HTTP against a running backend).
# Usage: powershell -ExecutionPolicy Bypass -File tool\stage4d_verify.ps1 -Base http://127.0.0.1:8080/api
# ASCII-only source: Chinese literals are built from Unicode code points so the script
# survives Windows PowerShell 5.1 without a UTF-8 BOM.
param(
    [string]$Base = 'http://127.0.0.1:8080/api',
    [string]$LogPath = ''
)

$ErrorActionPreference = 'Stop'

# 餐饮 (can yin) — the only category this script needs
$cCanyin = [string]([char]0x9910) + [string]([char]0x996E)

function Post-Json($uri, $payload, $token) {
    $json = $payload | ConvertTo-Json -Depth 6 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $headers = @{}
    if ($token) { $headers['Authorization'] = "Bearer $token" }
    return Invoke-RestMethod -Uri $uri -Method Post -Headers $headers `
        -ContentType 'application/json; charset=utf-8' -Body $bytes
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
    Post-Json "$Base/auth/register" @{ username = $name; password = $pass; nickname = $name } | Out-Null
    $login = Post-Json "$Base/auth/login" @{ username = $name; password = $pass }
    return $login.data.token
}

function Add-Expense($token, $amount, $date) {
    Post-Json "$Base/bills" @{
        type     = '1'
        amount   = $amount
        category = $cCanyin
        billDate = $date
        merchant = 'forecast-check'
        remark   = 'stage4d-check'
    } $token | Out-Null
}

function Count-QueryLines($path) {
    if (-not $path -or -not (Test-Path $path)) { return -1 }
    # 后端进程一直持有日志句柄，必须用 FileShare.ReadWrite 才能读到
    $stream = New-Object System.IO.FileStream($path, [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $reader = New-Object System.IO.StreamReader($stream)
    $count = 0
    try {
        $line = $reader.ReadLine()
        while ($null -ne $line) {
            if ($line.Contains('Preparing:')) { $count++ }
            $line = $reader.ReadLine()
        }
    } finally {
        $reader.Close()
        $stream.Close()
    }
    return $count
}

$today = Get-Date
$current = $today.ToString('yyyy-MM')
$target = $today.AddMonths(1).ToString('yyyy-MM')
$m1 = $today.AddMonths(-1); $m2 = $today.AddMonths(-2); $m3 = $today.AddMonths(-3)
$m5 = $today.AddMonths(-5)
$stamp = [DateTimeOffset]::Now.ToUnixTimeSeconds()
$pass = 'Test123456'
$fail = @()

Write-Output "current month : $current"
Write-Output "target month  : $target"

# --- account A: three complete months of history ---------------------------
$userA = "s4d_a_$stamp"
$tokenA = New-Account $userA $pass
Add-Expense $tokenA '1250.00' ($m1.ToString('yyyy-MM') + '-15')
Add-Expense $tokenA '1180.00' ($m2.ToString('yyyy-MM') + '-15')
Add-Expense $tokenA '1320.00' ($m3.ToString('yyyy-MM') + '-15')
# current month data must NOT take part in the forecast
Add-Expense $tokenA '5000.00' ($current + '-05')

# --- account B: one complete month only (INSUFFICIENT_DATA) ----------------
$userB = "s4d_b_$stamp"
$tokenB = New-Account $userB $pass
Add-Expense $tokenB '1000.00' ($m1.ToString('yyyy-MM') + '-10')

# --- account C: empty (NO_DATA) -------------------------------------------
$userC = "s4d_c_$stamp"
$tokenC = New-Account $userC $pass

# --- account D: gap months (m1 / m3 / m5) ---------------------------------
$userD = "s4d_d_$stamp"
$tokenD = New-Account $userD $pass
Add-Expense $tokenD '1200.00' ($m1.ToString('yyyy-MM') + '-15')
Add-Expense $tokenD '1000.00' ($m3.ToString('yyyy-MM') + '-15')
Add-Expense $tokenD '900.00' ($m5.ToString('yyyy-MM') + '-15')

# ==================== checks ====================

$respA = Get-Json "$Base/insights/forecast?month=$current" $tokenA
$a = $respA.data
Write-Output "A status      : $($a.status) / confidence=$($a.confidence)"
Write-Output "A month       : $($a.month) -> $($a.targetMonth)"
Write-Output "A predicted   : $($a.predictedAmount)  previous=$($a.previousMonthAmount)  diff=$($a.predictedDifference)  pct=$($a.predictedChangePercent)"
Write-Output "A current     : $($a.currentMonthAmount) after $($a.elapsedDays) days"
foreach ($s in $a.sampleMonths) { Write-Output ("  sample {0} amount={1} weight={2}" -f $s.month, $s.amount, $s.weight) }

if ($a.status -ne 'OK') { $fail += "A: expected OK, got $($a.status)" }
if ($a.month -ne $current) { $fail += "A: month=$($a.month)" }
if ($a.targetMonth -ne $target) { $fail += "A: targetMonth=$($a.targetMonth)" }
if ($a.predictedAmount -ne '1238.33') { $fail += "A: predicted=$($a.predictedAmount) (expect 1238.33)" }
if ($a.previousMonthAmount -ne '1250.00') { $fail += "A: previous=$($a.previousMonthAmount)" }
if ($a.predictedDifference -ne '-11.67') { $fail += "A: difference=$($a.predictedDifference)" }
if ($a.predictedChangePercent -ne '-0.93') { $fail += "A: percent=$($a.predictedChangePercent)" }
if ($a.currentMonthAmount -ne '5000.00') { $fail += "A: currentMonthAmount=$($a.currentMonthAmount)" }
if ($a.sampleMonths.Count -ne 3) { $fail += "A: sampleMonths=$($a.sampleMonths.Count)" }
else {
    if ($a.sampleMonths[0].weight -ne 3) { $fail += "A: first weight=$($a.sampleMonths[0].weight)" }
    if ($a.sampleMonths[1].weight -ne 2) { $fail += "A: second weight=$($a.sampleMonths[1].weight)" }
    if ($a.sampleMonths[2].weight -ne 1) { $fail += "A: third weight=$($a.sampleMonths[2].weight)" }
    if ($a.sampleMonths[0].month -eq $current) { $fail += 'A: current month leaked into samples' }
}

$respB = Get-Json "$Base/insights/forecast?month=$current" $tokenB
Write-Output "B status      : $($respB.data.status)"
if ($respB.data.status -ne 'INSUFFICIENT_DATA') { $fail += "B: expected INSUFFICIENT_DATA, got $($respB.data.status)" }
if ($respB.data.predictedAmount -ne '0.00') { $fail += "B: predicted should stay 0.00" }

$respC = Get-Json "$Base/insights/forecast?month=$current" $tokenC
Write-Output "C status      : $($respC.data.status)"
if ($respC.data.status -ne 'NO_DATA') { $fail += "C: expected NO_DATA, got $($respC.data.status)" }

$respD = Get-Json "$Base/insights/forecast?month=$current" $tokenD
$d = $respD.data
Write-Output "D status      : $($d.status) predicted=$($d.predictedAmount)"
foreach ($s in $d.sampleMonths) { Write-Output ("  sample {0} amount={1} weight={2}" -f $s.month, $s.amount, $s.weight) }
if ($d.status -ne 'OK') { $fail += "D: expected OK, got $($d.status)" }
if ($d.predictedAmount -ne '1083.33') { $fail += "D: predicted=$($d.predictedAmount) (expect 1083.33)" }
if ($d.sampleMonths.Count -ne 3) { $fail += "D: sampleMonths=$($d.sampleMonths.Count)" }
else {
    if ($d.sampleMonths[0].month -ne $m1.ToString('yyyy-MM')) { $fail += "D: first sample=$($d.sampleMonths[0].month)" }
    if ($d.sampleMonths[1].month -ne $m3.ToString('yyyy-MM')) { $fail += "D: second sample=$($d.sampleMonths[1].month)" }
    if ($d.sampleMonths[2].month -ne $m5.ToString('yyyy-MM')) { $fail += "D: third sample=$($d.sampleMonths[2].month)" }
}

# user isolation: an empty account must never see another account's numbers
if ($respC.data.predictedAmount -ne '0.00' -or $respC.data.sampleMonths.Count -ne 0) {
    $fail += 'isolation: empty account received another user data'
}

# parameter + auth guards
$s401 = Get-Status "$Base/insights/forecast?month=$current" $null
$sBadShort = Get-Status "$Base/insights/forecast?month=2026-9" $tokenA
$sBadText = Get-Status "$Base/insights/forecast?month=abc" $tokenA
$sNoParam = Get-Status "$Base/insights/forecast" $tokenA
Write-Output "no token      : $s401"
Write-Output "month=2026-9  : $sBadShort"
Write-Output "month=abc     : $sBadText"
Write-Output "month missing : $sNoParam"
if ($s401 -ne 401) { $fail += "auth: expected 401, got $s401" }
if ($sBadShort -ne 400) { $fail += "month format: expected 400, got $sBadShort" }
if ($sBadText -ne 400) { $fail += "month text: expected 400, got $sBadText" }
if ($sNoParam -ne 400) { $fail += "month missing: expected 400, got $sNoParam" }

# non-current months must not produce a forecast
$future = Get-Json "$Base/insights/forecast?month=$target" $tokenA
$past = Get-Json ("$Base/insights/forecast?month=" + $m1.ToString('yyyy-MM')) $tokenA
Write-Output "future month  : $($future.data.status)"
Write-Output "past month    : $($past.data.status)"
if ($future.data.status -ne 'NOT_APPLICABLE') { $fail += "future month: $($future.data.status)" }
if ($past.data.status -ne 'NOT_APPLICABLE') { $fail += "past month: $($past.data.status)" }
if ($future.data.predictedAmount -ne '0.00') { $fail += 'future month returned an amount' }

# query count: one request must issue exactly one aggregate SELECT
if ($LogPath) {
    $before = Count-QueryLines $LogPath
    Get-Json "$Base/insights/forecast?month=$current" $tokenA | Out-Null
    Start-Sleep -Milliseconds 400
    $after = Count-QueryLines $LogPath
    $delta = $after - $before
    Write-Output "sql statements for one forecast request: $delta"
    if ($delta -ne 1) { $fail += "query count: expected 1, got $delta" }
}

Write-Output ''
if ($fail.Count -gt 0) {
    Write-Output 'STAGE 4-D SELF CHECK FAILED'
    foreach ($f in $fail) { Write-Output " - $f" }
    exit 1
}
Write-Output 'STAGE 4-D SELF CHECK PASSED'
Write-Output "accounts: A=$userA B=$userB C=$userC D=$userD"
