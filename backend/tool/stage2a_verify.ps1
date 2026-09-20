# Stage 2-A self check against a running backend:
#   1) daily income/expense summary
#   2) bill list amount range filter (minAmount / maxAmount)
#   3) invalid amount range is rejected with 400
#   4) user data isolation
#
# Usage: powershell -ExecutionPolicy Bypass -File tool\stage2a_verify.ps1 -Base http://127.0.0.1:8080/api
#
# Note: this file is intentionally ASCII-only and sends the request body as UTF-8 bytes,
# so that Windows PowerShell 5.1 does not mangle Chinese category names.
param(
    [string]$Base = 'http://127.0.0.1:8080/api'
)

$ErrorActionPreference = 'Stop'
$suffix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() % 1000000
$today = (Get-Date).ToString('yyyy-MM-dd')
$utf8 = New-Object System.Text.UTF8Encoding($false)

# 分类名称与后端 common/Category.java 保持一致，这里用 Unicode 转义避免脚本编码问题
$catFood = [char]0x9910 + [char]0x996E     # 餐饮
$catLiving = [char]0x751F + [char]0x6D3B + [char]0x8D39   # 生活费

function Send($Method, $Path, $Token, $Payload) {
    $headers = @{}
    if ($Token) { $headers['Authorization'] = "Bearer $Token" }
    $params = @{
        Uri        = "$Base$Path"
        Method     = $Method
        TimeoutSec = 15
    }
    if ($headers.Count -gt 0) { $params['Headers'] = $headers }
    if ($Payload) {
        $params['ContentType'] = 'application/json; charset=utf-8'
        $params['Body'] = $utf8.GetBytes(($Payload | ConvertTo-Json -Compress))
    }
    try {
        return (Invoke-WebRequest @params -UseBasicParsing).Content | ConvertFrom-Json
    } catch {
        $response = $_.Exception.Response
        if (-not $response) { throw }
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), $utf8)
        return $reader.ReadToEnd() | ConvertFrom-Json
    }
}

function NewAccount($Username) {
    Send 'POST' '/auth/register' $null @{
        username = $Username; password = '123456'; nickname = 'selfcheck'
    } | Out-Null
    return (Send 'POST' '/auth/login' $null @{ username = $Username; password = '123456' }).data.token
}

function AddBill($Token, $Type, $Amount, $Category) {
    $result = Send 'POST' '/bills' $Token @{
        type = $Type; amount = $Amount; category = $Category
        billDate = $today; merchant = ''; remark = ''
    }
    if ($result.code -ne 0) { throw "create bill failed: $($result.message)" }
}

$userA = "stage2a_$suffix"
$userB = "stage2b_$suffix"
$tokenA = NewAccount $userA
$tokenB = NewAccount $userB
Write-Host "accounts: A=$userA B=$userB"

# A: expense 20.00 + expense 5.00 + income 100.00, all today
AddBill $tokenA '1' '20.00' $catFood
AddBill $tokenA '1' '5.00' $catFood
AddBill $tokenA '2' '100.00' $catLiving
# B: one unrelated expense used to prove isolation
AddBill $tokenB '1' '999.00' $catFood

$summaryA = (Send 'GET' '/statistics/daily-summary' $tokenA $null).data
$summaryB = (Send 'GET' '/statistics/daily-summary' $tokenB $null).data
Write-Host ("daily A: expense={0} income={1} (expect 25.00 / 100.00)" -f $summaryA.expense, $summaryA.income)
Write-Host ("daily B: expense={0} income={1} (expect 999.00 / 0.00)" -f $summaryB.expense, $summaryB.income)

$month = (Get-Date).ToString('yyyy-MM')
$range = (Send 'GET' "/bills?month=$month&minAmount=10&maxAmount=50" $tokenA $null).data
Write-Host ("range 10-50 -> {0} record(s), expect 1" -f $range.total)

$upperOnly = (Send 'GET' "/bills?month=$month&maxAmount=10" $tokenA $null).data
Write-Host ("range <=10 -> {0} record(s), expect 1" -f $upperOnly.total)

$bad = Send 'GET' '/bills?minAmount=50&maxAmount=10' $tokenA $null
Write-Host ("min>max -> code={0} message={1}" -f $bad.code, $bad.message)

$listB = (Send 'GET' '/bills' $tokenB $null).data
Write-Host ("B list total={0}, expect 1" -f $listB.total)

if ($summaryA.expense -ne '25.00') { throw 'daily expense wrong' }
if ($summaryA.income -ne '100.00') { throw 'daily income wrong' }
if ($summaryB.expense -ne '999.00') { throw 'user B daily summary wrong' }
if ($summaryB.income -ne '0.00') { throw 'user B income should be 0' }
if ($range.total -ne 1) { throw 'amount range filter wrong' }
if ($upperOnly.total -ne 1) { throw 'max-only range filter wrong' }
if ($bad.code -ne 400) { throw 'invalid amount range not rejected' }
if ($listB.total -ne 1) { throw 'user isolation broken' }

Write-Host 'STAGE 2-A SELF CHECK PASSED'
