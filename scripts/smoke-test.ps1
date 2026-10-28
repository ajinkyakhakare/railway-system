# Task I1 | Owner group: Integration (I1) | Purpose: end-to-end smoke test of the running backend (PowerShell version).
#
# Requirements: Windows PowerShell 5.1 or PowerShell 7+. The backend must be running with the demo
# configuration (app.auth.dev-mode=true so the payment OTP is returned as devOtp,
# app.payment.mode=MOCK).
#
# Usage:   .\scripts\smoke-test.ps1
#          .\scripts\smoke-test.ps1 -BaseUrl http://localhost:8081/api/v1
#
# Every step prints PASS or FAIL. The script stops with exit code 1 at the first failure and
# prints "ALL PASS" (exit code 0) when every step succeeds.

param(
    [string]$BaseUrl = "http://localhost:8081/api/v1"
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------------------------
$script:Step = 0     # step counter shown in the output
$script:Cur = ""     # name of the step that is running

# Start a new step.
function Begin-Step([string]$Name) {
    $script:Step++
    $script:Cur = $Name
}

# Report success of the current step (optional detail text).
function Pass-Step([string]$Detail = "") {
    $suffix = ""
    if ($Detail) { $suffix = " ($Detail)" }
    Write-Host ("PASS  [{0:00}] {1}{2}" -f $script:Step, $script:Cur, $suffix) -ForegroundColor Green
}

# Report failure of the current step and stop the whole script with exit code 1.
function Fail-Step([string]$Message) {
    Write-Host ("FAIL  [{0:00}] {1} - {2}" -f $script:Step, $script:Cur, $Message) -ForegroundColor Red
    exit 1
}

# Make one HTTP call. Returns an object with Ok (bool), Body (parsed JSON) and Error (text).
function Invoke-Api([string]$Method, [string]$Path, [string]$Token = "", $Body = $null) {
    $headers = @{ Accept = "application/json" }
    if ($Token) { $headers["Authorization"] = "Bearer $Token" }

    $params = @{
        Method      = $Method
        Uri         = "$BaseUrl$Path"
        Headers     = $headers
        ErrorAction = "Stop"
    }
    if ($null -ne $Body) {
        $params["Body"] = ($Body | ConvertTo-Json -Depth 6 -Compress)
        $params["ContentType"] = "application/json"
    }

    try {
        $parsed = Invoke-RestMethod @params
        return [pscustomobject]@{ Ok = $true; Body = $parsed; Error = $null }
    }
    catch {
        # Try to read the JSON error envelope sent by the server (differs between PS 5.1 and 7).
        $text = $null
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $text = $_.ErrorDetails.Message
        }
        elseif ($_.Exception.Response) {
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $text = $reader.ReadToEnd()
            }
            catch { $text = $null }
        }
        if (-not $text) { $text = $_.Exception.Message }
        return [pscustomobject]@{ Ok = $false; Body = $null; Error = $text }
    }
}

# The call must have succeeded and carry {"success":true,...}.
function Assert-Success($Result) {
    if (-not $Result.Ok) { Fail-Step $Result.Error }
    if ($Result.Body.success -ne $true) { Fail-Step "response is not a success envelope" }
}

# Fail with the message unless the condition is true.
function Assert-That([bool]$Condition, [string]$Message) {
    if (-not $Condition) { Fail-Step $Message }
}

# Log in and return the JWT. Handles the optional login OTP (dev mode returns devOtp).
function Get-LoginToken([string]$StepName, [string]$Email, [string]$Password) {
    Begin-Step $StepName
    $r = Invoke-Api POST "/auth/login" "" @{ email = $Email; password = $Password }
    Assert-Success $r
    $token = $r.Body.data.token
    if (-not $token) {
        # Login OTP is switched on: verify with the devOtp returned by the server.
        $challenge = $r.Body.data.challengeId
        $otp = [string]$r.Body.data.devOtp
        if (-not $challenge -or -not $otp) {
            Fail-Step "no token returned and no devOtp available (is app.auth.dev-mode=true?)"
        }
        $v = Invoke-Api POST "/auth/verify-otp" "" @{ challengeId = [long]$challenge; otp = $otp }
        Assert-Success $v
        $token = $v.Body.data.token
    }
    if (-not $token) { Fail-Step "login did not return a token" }
    Pass-Step $Email
    return [string]$token
}

# ---------------------------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------------------------
$JourneyDate = (Get-Date).AddDays(2).ToString("yyyy-MM-dd")
Write-Host "Smoke test against $BaseUrl (journey date $JourneyDate)"
Write-Host "----------------------------------------------------------------------"

# ---------------------------------------------------------------------------------------------
# 1. Health
# ---------------------------------------------------------------------------------------------
Begin-Step "health"
$r = Invoke-Api GET "/health"
if (-not $r.Ok) { Fail-Step $r.Error }
# The health payload may or may not be wrapped in the {"data":...} envelope; accept both.
$health = $r.Body
if ($null -ne $r.Body.data) { $health = $r.Body.data }
Assert-That (($health.status -eq "UP") -and ($health.db -eq "UP")) `
    "expected status UP and db UP, got status=$($health.status) db=$($health.db)"
Pass-Step "status=UP db=UP"

# ---------------------------------------------------------------------------------------------
# 2. Login as the passenger Asha
# ---------------------------------------------------------------------------------------------
$passengerToken = Get-LoginToken "login passenger" "asha@railway.test" "Test@1234"

# ---------------------------------------------------------------------------------------------
# 3. Train search Mumbai CSMT (2) -> Pune (1) on today + 2
#    Train 11001 (Mumbai Pune Express) has Sleeper coaches, which the booking below needs.
# ---------------------------------------------------------------------------------------------
Begin-Step "search trains 2 -> 1"
$r = Invoke-Api GET "/trains/search?fromStationId=2&toStationId=1&date=$JourneyDate"
Assert-Success $r
$train = @($r.Body.data) | Where-Object { $_.trainNo -eq "11001" } | Select-Object -First 1
Assert-That ($null -ne $train) `
    "train 11001 not found in the search result - was the seed data and run generation loaded?"
$runId = [long]$train.runId
Pass-Step "runId=$runId"

# ---------------------------------------------------------------------------------------------
# 4. Availability of that run
# ---------------------------------------------------------------------------------------------
Begin-Step "availability for run"
$r = Invoke-Api GET "/availability?runId=$runId"
Assert-Success $r
$sl = @($r.Body.data) | Where-Object { $_.classCode -eq "SL" } | Select-Object -First 1
Assert-That ($null -ne $sl) "no SL row in availability"
Pass-Step "SL: $($sl.availabilityText)"

# ---------------------------------------------------------------------------------------------
# 5. Fare quote for passengers 1 and 2 in Sleeper
# ---------------------------------------------------------------------------------------------
Begin-Step "fare quote passengers 1,2 SL"
$r = Invoke-Api GET "/fares/quote?runId=$runId&classCode=SL&fromStationId=2&toStationId=1&passengerIds=1,2" $passengerToken
Assert-Success $r
Assert-That (([decimal]$r.Body.data.totalFare -gt 0) -and (@($r.Body.data.passengers).Count -eq 2)) `
    "quote must have 2 passengers and a positive total"
Pass-Step "totalFare=$($r.Body.data.totalFare)"

# ---------------------------------------------------------------------------------------------
# 6. Book the ticket
# ---------------------------------------------------------------------------------------------
Begin-Step "book ticket passengers [1,2] SL"
$bookBody = @{
    runId         = $runId
    classCode     = "SL"
    fromStationId = 2
    toStationId   = 1
    passengerIds  = @(1, 2)
}
$r = Invoke-Api POST "/bookings" $passengerToken $bookBody
Assert-Success $r
$booking = $r.Body.data
Assert-That (([string]$booking.pnr -match '^[0-9]{10}$') -and (@($booking.passengers).Count -eq 2)) `
    "booking must return a 10 digit PNR and 2 passengers"
$bookingId = [long]$booking.bookingId
$pnr = [string]$booking.pnr
$firstBpId = [long]@($booking.passengers)[0].bookingPassengerId
Pass-Step "bookingId=$bookingId pnr=$pnr"

# ---------------------------------------------------------------------------------------------
# 7. Payment OTP (dev mode returns the OTP in devOtp)
# ---------------------------------------------------------------------------------------------
Begin-Step "request payment OTP"
$r = Invoke-Api POST "/auth/payment-otp" $passengerToken @{}
Assert-Success $r
$challengeId = $r.Body.data.challengeId
$devOtp = [string]$r.Body.data.devOtp
Assert-That (($null -ne $challengeId) -and ($devOtp -ne "")) `
    "challengeId/devOtp missing (is app.auth.dev-mode=true?)"
Pass-Step "challengeId=$challengeId"

# ---------------------------------------------------------------------------------------------
# 8. Create the payment order with the OTP
# ---------------------------------------------------------------------------------------------
Begin-Step "create payment order"
$orderBody = @{
    bookingId      = $bookingId
    otpChallengeId = [long]$challengeId
    otp            = $devOtp
}
$r = Invoke-Api POST "/payments/orders" $passengerToken $orderBody
Assert-Success $r
Assert-That (($null -ne $r.Body.data.paymentId) -and ($r.Body.data.mode -eq "MOCK")) `
    "expected a MOCK payment order (set app.payment.mode=MOCK)"
$paymentId = [long]$r.Body.data.paymentId
Pass-Step "paymentId=$paymentId amount=$($r.Body.data.amount)"

# ---------------------------------------------------------------------------------------------
# 9. Confirm the mock payment as successful
# ---------------------------------------------------------------------------------------------
Begin-Step "mock-confirm payment"
$r = Invoke-Api POST "/payments/mock-confirm" $passengerToken @{ paymentId = $paymentId; success = $true }
Assert-Success $r
Assert-That (($r.Body.data.paymentStatus -eq "SUCCESS") -and ($r.Body.data.bookingStatus -eq "CONFIRMED")) `
    "expected paymentStatus SUCCESS and bookingStatus CONFIRMED"
Pass-Step "payment SUCCESS, booking CONFIRMED"

# ---------------------------------------------------------------------------------------------
# 10. My bookings must contain the new PNR
# ---------------------------------------------------------------------------------------------
Begin-Step "my bookings contains PNR"
$r = Invoke-Api GET "/bookings/my" $passengerToken
Assert-Success $r
$mine = @($r.Body.data) | Where-Object { [string]$_.pnr -eq $pnr }
Assert-That (@($mine).Count -eq 1) "PNR $pnr not found in /bookings/my"
Pass-Step "pnr=$pnr"

# ---------------------------------------------------------------------------------------------
# 11. Public ticket lookup by PNR
# ---------------------------------------------------------------------------------------------
Begin-Step "ticket lookup by PNR"
$r = Invoke-Api GET "/tickets/$pnr"
Assert-Success $r
$t = $r.Body.data
Assert-That (([string]$t.pnr -eq $pnr) -and ($t.bookingStatus -eq "CONFIRMED") -and (@($t.passengers).Count -eq 2)) `
    "ticket must be CONFIRMED with 2 passengers"
Pass-Step "2 passengers, CONFIRMED"

# ---------------------------------------------------------------------------------------------
# 12. Cancellation preview for the first passenger
# ---------------------------------------------------------------------------------------------
Begin-Step "cancellation preview"
$r = Invoke-Api GET "/cancellations/preview?bookingPassengerId=$firstBpId" $passengerToken
Assert-Success $r
$p = $r.Body.data
Assert-That (($null -ne $p.estimatedRefund) -and ($null -ne $p.deductionPercent)) `
    "preview must contain estimatedRefund and deductionPercent"
Pass-Step "deduction=$($p.deductionPercent)% estimatedRefund=$($p.estimatedRefund)"

# ---------------------------------------------------------------------------------------------
# 13. Cancel the first passenger
# ---------------------------------------------------------------------------------------------
Begin-Step "cancel passenger"
$r = Invoke-Api POST "/cancellations" $passengerToken @{ bookingPassengerId = $firstBpId; reason = "Smoke test cancellation" }
Assert-Success $r
Assert-That (($null -ne $r.Body.data.cancellationId) -and ($null -ne $r.Body.data.refundAmount)) `
    "cancellation must return cancellationId and refundAmount"
$cancellationId = [long]$r.Body.data.cancellationId
Pass-Step "cancellationId=$cancellationId refund=$($r.Body.data.refundAmount)"

# ---------------------------------------------------------------------------------------------
# 14. My refunds must contain that cancellation
# ---------------------------------------------------------------------------------------------
Begin-Step "my refunds"
$r = Invoke-Api GET "/refunds/my" $passengerToken
Assert-Success $r
$refund = @($r.Body.data) | Where-Object { [long]$_.cancellationId -eq $cancellationId }
Assert-That (@($refund).Count -eq 1) "refund for cancellation $cancellationId not found"
Pass-Step "refund found"

# ---------------------------------------------------------------------------------------------
# 15. Public live train status
# ---------------------------------------------------------------------------------------------
Begin-Step "ops status"
$r = Invoke-Api GET "/ops/status"
Assert-Success $r
Pass-Step "$(@($r.Body.data).Count) run(s) today"

# ---------------------------------------------------------------------------------------------
# 16. Login as admin
# ---------------------------------------------------------------------------------------------
$adminToken = Get-LoginToken "login admin" "admin@railway.test" "Test@1234"

# ---------------------------------------------------------------------------------------------
# 17. Admin dashboard summary
# ---------------------------------------------------------------------------------------------
Begin-Step "admin dashboard summary"
$r = Invoke-Api GET "/admin/dashboard/summary" $adminToken
Assert-Success $r
$s = $r.Body.data
Assert-That (($null -ne $s.totalBookings) -and ([long]$s.totalBookings -ge 1)) `
    "summary must contain totalBookings >= 1"
Pass-Step "totalBookings=$($s.totalBookings) confirmed=$($s.confirmedBookings)"

# ---------------------------------------------------------------------------------------------
# 18. Popular routes report
# ---------------------------------------------------------------------------------------------
Begin-Step "admin popular routes"
$r = Invoke-Api GET "/admin/reports/popular-routes" $adminToken
Assert-Success $r
$routes = @($r.Body.data)
Assert-That ($routes.Count -ge 1) "popular routes must be a non-empty list"
Pass-Step "$($routes.Count) route(s), top: $($routes[0].routeName)"

Write-Host "----------------------------------------------------------------------"
Write-Host "ALL PASS ($($script:Step) steps)" -ForegroundColor Green
exit 0
