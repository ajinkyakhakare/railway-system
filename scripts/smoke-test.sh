#!/usr/bin/env bash
# Task I1 | Owner group: Integration (I1) | Purpose: end-to-end smoke test of the running backend.
#
# Requirements: bash, curl, jq. The backend must be running with the demo configuration
# (app.auth.dev-mode=true so the payment OTP is returned as devOtp, app.payment.mode=MOCK).
#
# Usage:   ./scripts/smoke-test.sh
#          BASE_URL=http://localhost:8080/api/v1 ./scripts/smoke-test.sh
#
# Every step prints PASS or FAIL. The script stops with exit code 1 at the first failure and
# prints "ALL PASS" (exit code 0) when every step succeeds.

set -u
set -o pipefail

BASE_URL="${BASE_URL:-http://localhost:8080/api/v1}"

# ---------------------------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------------------------
STEP=0     # step counter shown in the output
CUR=""     # name of the step that is running
CODE=""    # HTTP status of the last request
RESP=""    # body of the last request

# Start a new step.
begin() {
  STEP=$((STEP + 1))
  CUR="$1"
}

# Report success of the current step (optional detail text).
pass() {
  printf 'PASS  [%02d] %s%s\n' "$STEP" "$CUR" "${1:+ ($1)}"
}

# Report failure of the current step and stop the whole script.
fail() {
  printf 'FAIL  [%02d] %s - %s\n' "$STEP" "$CUR" "$1"
  exit 1
}

# Make one HTTP call. Sets CODE (status) and RESP (body).
#   api METHOD PATH [TOKEN] [JSON_BODY]
api() {
  local method="$1" path="$2" token="${3:-}" body="${4:-}"
  local args=(-sS -X "$method" -H 'Accept: application/json' -w $'\n%{http_code}')
  if [ -n "$token" ]; then
    args+=(-H "Authorization: Bearer $token")
  fi
  if [ -n "$body" ]; then
    args+=(-H 'Content-Type: application/json' -d "$body")
  fi
  local out
  if ! out=$(curl "${args[@]}" "$BASE_URL$path" 2>&1); then
    CODE="000"
    RESP="$out"
    return 0
  fi
  CODE="${out##*$'\n'}"
  RESP="${out%$'\n'*}"
}

# Text of the error envelope, or the raw body when it is not JSON.
error_text() {
  local text
  text=$(echo "$RESP" | jq -r '(.error.code // "?") + ": " + (.error.message // "")' 2>/dev/null)
  if [ -z "$text" ]; then
    text="$RESP"
  fi
  echo "$text"
}

# The last response must be HTTP 2xx and {"success":true,...}.
require_success() {
  case "$CODE" in
    2??) ;;
    *) fail "HTTP $CODE - $(error_text)" ;;
  esac
  if ! echo "$RESP" | jq -e '.success == true' >/dev/null 2>&1; then
    fail "response is not a success envelope: $RESP"
  fi
}

# Read one value from the last response (jq filter). Prints "null" when missing.
val() {
  echo "$RESP" | jq -r "$1"
}

# The jq filter must evaluate to true on the last response, else fail with the given message.
check() {
  if ! echo "$RESP" | jq -e "$1" >/dev/null 2>&1; then
    fail "$2 - response was: $RESP"
  fi
}

# Date N days from today as yyyy-MM-dd (GNU date, with a fallback for macOS/BSD date).
date_plus_days() {
  date -d "+$1 days" +%F 2>/dev/null || date -v+"$1"d +%F
}

# Log in and store the JWT in TOKEN. Handles the optional login OTP (dev mode returns devOtp).
#   login_user STEP_NAME EMAIL PASSWORD
TOKEN=""
login_user() {
  local email="$2" password="$3"
  begin "$1"
  api POST /auth/login "" "$(jq -n --arg e "$email" --arg p "$password" '{email:$e,password:$p}')"
  require_success
  TOKEN=$(val '.data.token // empty')
  if [ -z "$TOKEN" ]; then
    # Login OTP is switched on: verify with the devOtp returned by the server.
    local challenge otp
    challenge=$(val '.data.challengeId // empty')
    otp=$(val '.data.devOtp // empty')
    if [ -z "$challenge" ] || [ -z "$otp" ]; then
      fail "no token returned and no devOtp available (is app.auth.dev-mode=true?)"
    fi
    api POST /auth/verify-otp "" \
      "$(jq -n --argjson c "$challenge" --arg o "$otp" '{challengeId:$c,otp:$o}')"
    require_success
    TOKEN=$(val '.data.token // empty')
  fi
  if [ -z "$TOKEN" ]; then
    fail "login did not return a token"
  fi
  pass "$email"
}

# ---------------------------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------------------------
for tool in curl jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "FAIL  [00] pre-flight - '$tool' is required but not installed"
    exit 1
  fi
done

JOURNEY_DATE=$(date_plus_days 2)
echo "Smoke test against $BASE_URL (journey date $JOURNEY_DATE)"
echo "----------------------------------------------------------------------"

# ---------------------------------------------------------------------------------------------
# 1. Health
# ---------------------------------------------------------------------------------------------
begin "health"
api GET /health
case "$CODE" in
  2??) ;;
  *) fail "HTTP $CODE - $RESP" ;;
esac
# The health payload may or may not be wrapped in the {"data":...} envelope; accept both.
HEALTH_STATUS=$(val '(.data // .) | .status')
HEALTH_DB=$(val '(.data // .) | .db')
if [ "$HEALTH_STATUS" != "UP" ] || [ "$HEALTH_DB" != "UP" ]; then
  fail "expected status UP and db UP, got status=$HEALTH_STATUS db=$HEALTH_DB"
fi
pass "status=UP db=UP"

# ---------------------------------------------------------------------------------------------
# 2. Login as the passenger Asha
# ---------------------------------------------------------------------------------------------
login_user "login passenger" "asha@railway.test" "Test@1234"
PASSENGER_TOKEN="$TOKEN"

# ---------------------------------------------------------------------------------------------
# 3. Train search Mumbai CSMT (2) -> Pune (1) on today + 2
#    Train 11001 (Mumbai Pune Express) has Sleeper coaches, which the booking below needs.
# ---------------------------------------------------------------------------------------------
begin "search trains 2 -> 1"
api GET "/trains/search?fromStationId=2&toStationId=1&date=$JOURNEY_DATE"
require_success
RUN_ID=$(val '[.data[] | select(.trainNo == "11001")][0].runId // empty')
if [ -z "$RUN_ID" ]; then
  fail "train 11001 not found in the search result - was the seed data and run generation loaded?"
fi
pass "runId=$RUN_ID"

# ---------------------------------------------------------------------------------------------
# 4. Availability of that run
# ---------------------------------------------------------------------------------------------
begin "availability for run"
api GET "/availability?runId=$RUN_ID"
require_success
check '[.data[] | select(.classCode == "SL")] | length >= 1' "no SL row in availability"
SL_TEXT=$(val '[.data[] | select(.classCode == "SL")][0].availabilityText')
pass "SL: $SL_TEXT"

# ---------------------------------------------------------------------------------------------
# 5. Fare quote for passengers 1 and 2 in Sleeper
# ---------------------------------------------------------------------------------------------
begin "fare quote passengers 1,2 SL"
api GET "/fares/quote?runId=$RUN_ID&classCode=SL&fromStationId=2&toStationId=1&passengerIds=1,2" \
  "$PASSENGER_TOKEN"
require_success
check '.data.totalFare > 0 and (.data.passengers | length) == 2' "quote must have 2 passengers and a positive total"
QUOTE_TOTAL=$(val '.data.totalFare')
pass "totalFare=$QUOTE_TOTAL"

# ---------------------------------------------------------------------------------------------
# 6. Book the ticket
# ---------------------------------------------------------------------------------------------
begin "book ticket passengers [1,2] SL"
BOOK_BODY=$(jq -n --argjson r "$RUN_ID" \
  '{runId:$r, classCode:"SL", fromStationId:2, toStationId:1, passengerIds:[1,2]}')
api POST /bookings "$PASSENGER_TOKEN" "$BOOK_BODY"
require_success
check '(.data.pnr | test("^[0-9]{10}$")) and (.data.passengers | length) == 2' "booking must return a 10 digit PNR and 2 passengers"
BOOKING_ID=$(val '.data.bookingId')
PNR=$(val '.data.pnr')
FIRST_BP_ID=$(val '.data.passengers[0].bookingPassengerId')
pass "bookingId=$BOOKING_ID pnr=$PNR"

# ---------------------------------------------------------------------------------------------
# 7. Payment OTP (dev mode returns the OTP in devOtp)
# ---------------------------------------------------------------------------------------------
begin "request payment OTP"
api POST /auth/payment-otp "$PASSENGER_TOKEN" '{}'
require_success
CHALLENGE_ID=$(val '.data.challengeId // empty')
DEV_OTP=$(val '.data.devOtp // empty')
if [ -z "$CHALLENGE_ID" ] || [ -z "$DEV_OTP" ]; then
  fail "challengeId/devOtp missing (is app.auth.dev-mode=true?)"
fi
pass "challengeId=$CHALLENGE_ID"

# ---------------------------------------------------------------------------------------------
# 8. Create the payment order with the OTP
# ---------------------------------------------------------------------------------------------
begin "create payment order"
ORDER_BODY=$(jq -n --argjson b "$BOOKING_ID" --argjson c "$CHALLENGE_ID" --arg o "$DEV_OTP" \
  '{bookingId:$b, otpChallengeId:$c, otp:$o}')
api POST /payments/orders "$PASSENGER_TOKEN" "$ORDER_BODY"
require_success
check '.data.paymentId != null and .data.mode == "MOCK"' "expected a MOCK payment order (set app.payment.mode=MOCK)"
PAYMENT_ID=$(val '.data.paymentId')
pass "paymentId=$PAYMENT_ID amount=$(val '.data.amount')"

# ---------------------------------------------------------------------------------------------
# 9. Confirm the mock payment as successful
# ---------------------------------------------------------------------------------------------
begin "mock-confirm payment"
CONFIRM_BODY=$(jq -n --argjson p "$PAYMENT_ID" '{paymentId:$p, success:true}')
api POST /payments/mock-confirm "$PASSENGER_TOKEN" "$CONFIRM_BODY"
require_success
check '.data.paymentStatus == "SUCCESS" and .data.bookingStatus == "CONFIRMED"' "expected paymentStatus SUCCESS and bookingStatus CONFIRMED"
pass "payment SUCCESS, booking CONFIRMED"

# ---------------------------------------------------------------------------------------------
# 10. My bookings must contain the new PNR
# ---------------------------------------------------------------------------------------------
begin "my bookings contains PNR"
api GET /bookings/my "$PASSENGER_TOKEN"
require_success
check "[.data[] | select(.pnr == \"$PNR\")] | length == 1" "PNR $PNR not found in /bookings/my"
pass "pnr=$PNR"

# ---------------------------------------------------------------------------------------------
# 11. Public ticket lookup by PNR
# ---------------------------------------------------------------------------------------------
begin "ticket lookup by PNR"
api GET "/tickets/$PNR"
require_success
check ".data.pnr == \"$PNR\" and .data.bookingStatus == \"CONFIRMED\" and (.data.passengers | length) == 2" "ticket must be CONFIRMED with 2 passengers"
pass "2 passengers, CONFIRMED"

# ---------------------------------------------------------------------------------------------
# 12. Cancellation preview for the first passenger
# ---------------------------------------------------------------------------------------------
begin "cancellation preview"
api GET "/cancellations/preview?bookingPassengerId=$FIRST_BP_ID" "$PASSENGER_TOKEN"
require_success
check '(.data.estimatedRefund | type) == "number" and (.data.deductionPercent | type) == "number"' "preview must contain numeric estimatedRefund and deductionPercent"
pass "deduction=$(val '.data.deductionPercent')% estimatedRefund=$(val '.data.estimatedRefund')"

# ---------------------------------------------------------------------------------------------
# 13. Cancel the first passenger
# ---------------------------------------------------------------------------------------------
begin "cancel passenger"
CANCEL_BODY=$(jq -n --argjson b "$FIRST_BP_ID" '{bookingPassengerId:$b, reason:"Smoke test cancellation"}')
api POST /cancellations "$PASSENGER_TOKEN" "$CANCEL_BODY"
require_success
check '.data.cancellationId != null and (.data.refundAmount | type) == "number"' "cancellation must return cancellationId and refundAmount"
CANCELLATION_ID=$(val '.data.cancellationId')
pass "cancellationId=$CANCELLATION_ID refund=$(val '.data.refundAmount')"

# ---------------------------------------------------------------------------------------------
# 14. My refunds must contain that cancellation
# ---------------------------------------------------------------------------------------------
begin "my refunds"
api GET /refunds/my "$PASSENGER_TOKEN"
require_success
check "[.data[] | select(.cancellationId == $CANCELLATION_ID)] | length == 1" "refund for cancellation $CANCELLATION_ID not found"
pass "refund found"

# ---------------------------------------------------------------------------------------------
# 15. Public live train status
# ---------------------------------------------------------------------------------------------
begin "ops status"
api GET /ops/status
require_success
check '.data | type == "array"' "ops status must be a list"
pass "$(val '.data | length') run(s) today"

# ---------------------------------------------------------------------------------------------
# 16. Login as admin
# ---------------------------------------------------------------------------------------------
login_user "login admin" "admin@railway.test" "Test@1234"
ADMIN_TOKEN="$TOKEN"

# ---------------------------------------------------------------------------------------------
# 17. Admin dashboard summary
# ---------------------------------------------------------------------------------------------
begin "admin dashboard summary"
api GET /admin/dashboard/summary "$ADMIN_TOKEN"
require_success
check '(.data.totalBookings | type) == "number" and .data.totalBookings >= 1' "summary must contain totalBookings >= 1"
pass "totalBookings=$(val '.data.totalBookings') confirmed=$(val '.data.confirmedBookings')"

# ---------------------------------------------------------------------------------------------
# 18. Popular routes report
# ---------------------------------------------------------------------------------------------
begin "admin popular routes"
api GET /admin/reports/popular-routes "$ADMIN_TOKEN"
require_success
check '(.data | type) == "array" and (.data | length) >= 1' "popular routes must be a non-empty list"
pass "$(val '.data | length') route(s), top: $(val '.data[0].routeName')"

echo "----------------------------------------------------------------------"
echo "ALL PASS ($STEP steps)"
exit 0
