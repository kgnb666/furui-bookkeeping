# Stage 3 self check against a running backend:
#   1) category recommendation uses the user's own history (HIGH confidence)
#   2) no history -> only keyword fallback or NONE, never another user's habit
#   3) every recommendation carries an explainable reason
#   4) monthly insights return rule-based cards
#
# Usage: powershell -ExecutionPolicy Bypass -File tool\stage3_verify.ps1 -Base http://127.0.0.1:8080/api
#
# ASCII-only on purpose; request bodies are sent as UTF-8 bytes so that
# Windows PowerShell 5.1 does not mangle Chinese category names.
param(
    [string]$Base = 'http://127.0.0.1:8080/api'
)

$ErrorActionPreference = 'Stop'
$suffix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() % 1000000
$today = (Get-Date).ToString('yyyy-MM-dd')
$month = (Get-Date).ToString('yyyy-MM')
$utf8 = New-Object System.Text.UTF8Encoding($false)

# categories from backend Category.java, written as code points to stay ASCII
$catFood = [char]0x9910 + [char]0x996E          # can yin (餐饮)
$catShopping = [char]0x8D2D + [char]0x7269      # gou wu (购物)
$catTransport = [char]0x4EA4 + [char]0x901A     # jiao tong (交通)
$catLiving = [char]0x751F + [char]0x6D3B + [char]0x8D39   # sheng huo fei (生活费)
$merchant = [char]0x661F + [char]0x5DF4 + [char]0x514B   # xing ba ke (星巴克)

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
        # Invoke-WebRequest 在没有 charset 时会按 Latin-1 解字符串，这里统一按 UTF-8 重新解码
        $bytes = $response.RawContentStream.ToArray()
        return $utf8.GetString($bytes) | ConvertFrom-Json
    } catch {
        $response = $_.Exception.Response
        if (-not $response) { throw }
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), $utf8)
        return $reader.ReadToEnd() | ConvertFrom-Json
    }
}

function NewAccount($Username) {
    Send 'POST' '/auth/register' $null @{
        username = $Username; password = '123456'; nickname = 'stage3'
    } | Out-Null
    return (Send 'POST' '/auth/login' $null @{ username = $Username; password = '123456' }).data.token
}

function AddBill($Token, $Type, $Amount, $Category, $Merchant) {
    $result = Send 'POST' '/bills' $Token @{
        type = $Type; amount = $Amount; category = $Category
        billDate = $today; merchant = $Merchant; remark = ''
    }
    if ($result.code -ne 0) { throw "create bill failed: $($result.message)" }
}

$userA = "stage3a_$suffix"
$userB = "stage3b_$suffix"
$tokenA = NewAccount $userA
$tokenB = NewAccount $userB
Write-Host "accounts: A=$userA B=$userB"

# A records the same merchant as 餐饮 three times, plus one old 购物 record to create a conflict
AddBill $tokenA '1' '20.00' $catFood $merchant
AddBill $tokenA '1' '21.00' $catFood $merchant
AddBill $tokenA '1' '22.00' $catFood $merchant
Write-Host "A created 3 x $merchant -> food"

# B has no history at all
$query = "/categories/recommend?merchant=" + [System.Uri]::EscapeDataString($merchant) + "&type=EXPENSE"
$recA = (Send 'GET' $query $tokenA $null).data
$recB = (Send 'GET' $query $tokenB $null).data

Write-Host ("A recommend => category={0} confidence={1} score={2} samples={3}" -f `
        $recA.category, $recA.confidence, $recA.score, $recA.sampleCount)
Write-Host ("A reason    => {0}" -f $recA.reason)
Write-Host ("B recommend => category={0} confidence={1} score={2} samples={3}" -f `
        $recB.category, $recB.confidence, $recB.score, $recB.sampleCount)
Write-Host ("B reason    => {0}" -f $recB.reason)

if ($recA.category -ne $catFood) { throw 'A should be recommended food' }
if ($recA.confidence -ne 'HIGH') { throw 'A should be HIGH confidence' }
if ($recA.sampleCount -ne 3) { throw 'A should cite 3 historical records' }
if ([string]::IsNullOrWhiteSpace($recA.reason)) { throw 'recommendation must explain itself' }
if ($recB.sampleCount -ne 0) { throw 'B must not inherit A history' }
if ($recB.score -ge $recA.score) { throw 'B score must be lower than A' }
Write-Host 'user isolation OK: B did not inherit A habits'

# unknown merchant with no history and no keyword => NONE
$unknown = "/categories/recommend?merchant=" + [System.Uri]::EscapeDataString("zzz-unknown-shop") + "&type=EXPENSE"
$recNone = (Send 'GET' $unknown $tokenA $null).data
Write-Host ("unknown merchant => category={0} confidence={1} reason={2}" -f `
        $recNone.category, $recNone.confidence, $recNone.reason)
if ($recNone.confidence -ne 'NONE') { throw 'unknown merchant should have no recommendation' }
if ($recNone.confidence -ne 'NONE' -or $recNone.score -ne 0) { throw 'NONE result must carry score 0' }

# insights
$insightsA = (Send 'GET' "/insights/monthly?month=$month" $tokenA $null).data
Write-Host ("insights A => expense={0} top={1} percent={2} cards={3}" -f `
        $insightsA.expense, $insightsA.topCategory, $insightsA.topCategoryPercent, $insightsA.insights.Count)
Write-Host ("summary    => {0}" -f $insightsA.summary)
foreach ($card in $insightsA.insights) {
    Write-Host ("  [{0}] {1}" -f $card.type, $card.message)
}
if ($insightsA.expense -ne '63.00') { throw "insights expense should be 63.00, got $($insightsA.expense)" }
if ($insightsA.topCategory -ne $catFood) { throw 'top category should be food' }

# B balance check: insights must also be per-user
AddBill $tokenB '2' '5000.00' $catLiving ''
$insightsB = (Send 'GET' "/insights/monthly?month=$month" $tokenB $null).data
Write-Host ("insights B => expense={0} income={1} cards={2}" -f `
        $insightsB.expense, $insightsB.income, $insightsB.insights.Count)
if ($insightsB.income -ne '5000.00') { throw 'B insights must only contain B data' }
if ($insightsB.expense -ne '0.00') { throw 'B has no expense, A data leaked' }

Write-Host 'STAGE 3 SELF CHECK PASSED'
