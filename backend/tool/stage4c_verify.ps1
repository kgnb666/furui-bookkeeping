# Stage 4-C self check: seed 4 months of data and verify the three anomaly rules.
# Usage: powershell -ExecutionPolicy Bypass -File tool\stage4c_verify.ps1 -Base http://127.0.0.1:8080/api
param([string]$Base = 'http://127.0.0.1:8080/api')

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$suffix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() % 1000000

# categories from Category.java as code points (ASCII-only script)
$food = [char]0x9910 + [char]0x996E          # can yin
$shop = [char]0x8D2D + [char]0x7269          # gou wu
$ent = [char]0x5A31 + [char]0x4E50           # yu le

function Send($Method, $Path, $Token, $Payload) {
    $headers = @{}
    if ($Token) { $headers['Authorization'] = "Bearer $Token" }
    $params = @{ Uri = "$Base$Path"; Method = $Method; TimeoutSec = 20 }
    if ($headers.Count -gt 0) { $params['Headers'] = $headers }
    if ($Payload) {
        $params['ContentType'] = 'application/json; charset=utf-8'
        $params['Body'] = $utf8.GetBytes(($Payload | ConvertTo-Json -Compress))
    }
    try {
        $response = Invoke-WebRequest @params -UseBasicParsing
        return $utf8.GetString($response.RawContentStream.ToArray()) | ConvertFrom-Json
    } catch {
        $response = $_.Exception.Response
        if (-not $response) { throw }
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), $utf8)
        return $reader.ReadToEnd() | ConvertFrom-Json
    }
}

function NewAccount($Username) {
    Send 'POST' '/auth/register' $null @{ username = $Username; password = '123456'; nickname = 'anomaly' } | Out-Null
    return (Send 'POST' '/auth/login' $null @{ username = $Username; password = '123456' }).data.token
}

function AddBill($Token, $Amount, $Category, $Date) {
    $result = Send 'POST' '/bills' $Token @{
        type = '1'; amount = $Amount; category = $Category; billDate = $Date; merchant = ''; remark = ''
    }
    if ($result.code -ne 0) { throw "create bill failed: $($result.message)" }
}

$user = "s4c_$suffix"
$token = NewAccount $user
Write-Host "account=$user"

#  4  100  400
foreach ($month in @('06', '07', '08')) {
    for ($i = 1; $i -le 4; $i++) {
        AddBill $token '100.00' $food "2026-$month-0$i"
    }
}
# target month: food 10 records x 120 (total 1200, count 10, delta 6 >= 5)
foreach ($day in @('01', '02', '03', '04', '05', '06', '07', '08', '09', '10')) {
    AddBill $token '120.00' $food "2026-09-$day"
}
# ""
for ($i = 1; $i -le 3; $i++) {
    AddBill $token '50.00' $shop "2026-08-1$i"
    AddBill $token '45.00' $ent "2026-09-0$i"
}

Write-Host "seeded: food 4x100 (Jun/Jul/Aug), food 10x120 (Sep), plus noise"

$response = (Send 'GET' '/insights/anomalies?month=2026-09' $token $null).data
Write-Host "status=$($response.status)  baselineMonths=$($response.baselineMonths -join ',')"
Write-Host "message=$($response.message)"
foreach ($item in $response.items) {
    Write-Host ("  [{0}/{1}] {2}: {3}" -f $item.type, $item.severity, $item.category, $item.message)
}

$types = $response.items | ForEach-Object { $_.type }
if ($types -notcontains 'CATEGORY_SPIKE') { throw 'expected a CATEGORY_SPIKE' }
if ($types -notcontains 'FREQUENCY_SPIKE') { throw 'expected a FREQUENCY_SPIKE' }

$spike = $response.items | Where-Object { $_.type -eq 'CATEGORY_SPIKE' } | Select-Object -First 1
if ($spike.currentAmount -ne '1200.00') { throw "category spike amount wrong: $($spike.currentAmount)" }
if ($spike.baselineAmount -ne '400.00') { throw "category spike baseline wrong: $($spike.baselineAmount)" }
if ($spike.difference -ne '800.00') { throw "category spike difference wrong: $($spike.difference)" }
if ($spike.changePercent -ne '200.00') { throw "category spike percent wrong: $($spike.changePercent)" }
if ($spike.severity -ne 'HIGH') { throw "expected HIGH severity, got $($spike.severity)" }

$freq = $response.items | Where-Object { $_.type -eq 'FREQUENCY_SPIKE' } | Select-Object -First 1
if ($freq.currentAmount -ne '10') { throw "frequency current wrong: $($freq.currentAmount)" }
if ($freq.baselineAmount -ne '4') { throw "frequency baseline wrong: $($freq.baselineAmount)" }
if ($freq.difference -ne '6') { throw "frequency delta wrong: $($freq.difference)" }

#  5  20  300 
$singleUser = "s4c_single_$suffix"
$singleToken = NewAccount $singleUser
for ($i = 1; $i -le 5; $i++) {
    AddBill $singleToken '20.00' $food "2026-08-0$i"
}
AddBill $singleToken '300.00' $food '2026-09-10'

$single = (Send 'GET' '/insights/anomalies?month=2026-09' $singleToken $null).data
$large = $single.items | Where-Object { $_.type -eq 'LARGE_TRANSACTION' } | Select-Object -First 1
if (-not $large) { throw 'expected a LARGE_TRANSACTION' }
Write-Host ("  [LARGE_TRANSACTION/{0}] {1}: {2}" -f $large.severity, $large.category, $large.message)
if ($large.baselineAmount -ne '20.00') { throw "large baseline wrong: $($large.baselineAmount)" }
if ($large.currentAmount -ne '300.00') { throw "large amount wrong: $($large.currentAmount)" }
if ($large.billDate -ne '2026-09-10') { throw "large date wrong: $($large.billDate)" }

# 
$newUser = "s4c_new_$suffix"
$newToken = NewAccount $newUser
AddBill $newToken '100.00' $food '2026-09-05'
$fresh = (Send 'GET' '/insights/anomalies?month=2026-09' $newToken $null).data
Write-Host "fresh account status=$($fresh.status)  message=$($fresh.message)"
if ($fresh.status -ne 'NOT_ENOUGH_BASELINE') { throw "expected NOT_ENOUGH_BASELINE, got $($fresh.status)" }

# 
$emptyUser = "s4c_empty_$suffix"
$emptyToken = NewAccount $emptyUser
$empty = (Send 'GET' '/insights/anomalies?month=2026-09' $emptyToken $null).data
if ($empty.status -ne 'NO_DATA') { throw "expected NO_DATA, got $($empty.status)" }

# 
$calm = (Send 'GET' '/insights/anomalies?month=2026-08' $token $null).data
Write-Host "calm month status=$($calm.status)"
if ($calm.status -ne 'NO_ANOMALY') { throw "expected NO_ANOMALY for 2026-08, got $($calm.status)" }

# 
$bad = Send 'GET' '/insights/anomalies?month=2025-08' $token $null
if ($bad.code -ne 400) { throw "expected 400 for month older than 12 months, got $($bad.code)" }
$malformed = Send 'GET' '/insights/anomalies?month=2026-13-01' $token $null
if ($malformed.code -ne 400) { throw "expected 400 for malformed month, got $($malformed.code)" }

# 
$other = (Send 'GET' '/insights/anomalies?month=2026-09' $newToken $null).data
if ($other.items.Count -ne 0) { throw 'fresh account should not see another user anomalies' }

Write-Host 'STAGE 4-C SELF CHECK PASSED'

