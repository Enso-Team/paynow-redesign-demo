#!/usr/bin/env bash
# End-to-end checks against the running stack (scripts/up.sh first). Needs curl, openssl and jq.
# Set LATENCY_PROFILE=measured when the stack runs with that profile, so the timing check expects the measured delays.
set -uo pipefail

AUTH=http://localhost:8081; ACCOUNT=http://localhost:8082; LOOKUP=http://localhost:8083; PAYMENT=http://localhost:8084
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  PASS  $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL  $1"; echo "        $2"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }

# req METHOD URL [BODY] [extra curl args...] -> sets STATUS, BODY and HEADERS
req() {
  local method="$1" url="$2" data="${3:-}"; shift 3 2>/dev/null || shift $#
  local args=(-s -X "$method" -o "$WORK/body" -D "$WORK/headers" -w '%{http_code}' -H 'Content-Type: application/json')
  [ -n "${TOKEN:-}" ] && args+=(-H "Authorization: Bearer $TOKEN")
  [ -n "$data" ] && args+=(--data "$data")
  STATUS="$(curl "${args[@]}" "$@" "$url")"
  BODY="$(cat "$WORK/body")"
}
field() { jq -r "$1 // empty" <<<"$BODY"; }
uuid() { uuidgen | tr 'A-Z' 'a-z'; }
available() {
  local saved="$BODY" s="$STATUS"
  req GET "$ACCOUNT/accounts/summary"
  jq -r '.accounts[] | select(.id == "acc-1") | .available' <<<"$BODY"
  BODY="$saved"; STATUS="$s"
}
attest() { # attest DEVICE_ID -> sets ATTEST
  req POST "$AUTH/auth/attest" "{\"deviceId\":\"$1\",\"platform\":\"e2e\",\"osVersion\":\"1\",\"appVersion\":\"1\",\"signals\":[]}"
  ATTEST="$(field .attestationId)"
}
session() { # session DEVICE KEYFILE -> sets TOKEN with a fresh attestation
  attest "$1"
  req POST "$AUTH/auth/challenge" "{\"deviceId\":\"$1\"}"
  local nonce sig; nonce="$(field .nonce)"
  sig="$(printf '%s' "$nonce" | openssl dgst -sha256 -sign "$2" | base64 | tr -d '\n')"
  req POST "$AUTH/auth/session" "{\"deviceId\":\"$1\",\"nonce\":\"$nonce\",\"signature\":\"$sig\",\"attestationId\":\"$ATTEST\"}"
  TOKEN="$(field .accessToken)"
}
stepup() { # stepup TYPE VALUE AMOUNT KEY [ACCOUNT] -> sets STEPUP
  local account="${5:-acc-1}" nonce binding sig
  req POST "$AUTH/auth/challenge" "{\"deviceId\":\"$DEVICE\"}"; nonce="$(field .nonce)"
  binding="$(printf '%s' "$account|$1|$2|$3|$4" | openssl dgst -sha256 -hex | awk '{print $NF}')"
  sig="$(printf '%s' "$nonce.$binding" | openssl dgst -sha256 -sign "$WORK/key.pem" | base64 | tr -d '\n')"
  req POST "$AUTH/auth/step-up" "{\"deviceId\":\"$DEVICE\",\"nonce\":\"$nonce\",\"signature\":\"$sig\",\"payment\":{\"fromAccountId\":\"$account\",\"proxyType\":\"$1\",\"proxyValue\":\"$2\",\"amount\":\"$3\",\"idempotencyKey\":\"$4\"}}"
  STEPUP="$(field .stepUpToken)"
}
poll() { # poll PAYMENT_ID -> waits until the status leaves PENDING (up to ~30 s)
  for _ in 1 2 3 4 5 6; do
    req GET "$PAYMENT/payments/$1?waitMs=5000"
    [ "$(field .status)" != "PENDING" ] && return
  done
}

echo "Device binding"
openssl ecparam -name prime256v1 -genkey -noout -out "$WORK/key.pem" 2>/dev/null
PUB="$(openssl ec -in "$WORK/key.pem" -pubout -outform DER 2>/dev/null | tail -c 65 | base64 | tr -d '\n')"
req POST "$AUTH/auth/devices" "{\"username\":\"alextan\",\"otp\":\"000000\",\"deviceName\":\"e2e\",\"publicKey\":\"$PUB\"}"
check "wrong OTP is 401 BAD_OTP" "$STATUS $(field .code)" "401 BAD_OTP"
req POST "$AUTH/auth/devices" "{\"username\":\"alextan\",\"otp\":\"123456\",\"deviceName\":\"e2e\",\"publicKey\":\"$PUB\"}"
check "register device is 201" "$STATUS" "201"
DEVICE="$(field .deviceId)"
check "register returns userId" "$(field .userId)" "user-1"

echo "Device attestation"
req POST "$AUTH/auth/attest" "{\"deviceId\":\"$DEVICE\",\"platform\":\"iOS\",\"signals\":[\"cydia\"]}"
check "a jailbroken device is 403 DEVICE_COMPROMISED" "$STATUS $(field .code)" "403 DEVICE_COMPROMISED"
req POST "$AUTH/auth/challenge" "{\"deviceId\":\"$DEVICE\"}"
N0="$(field .nonce)"; S0="$(printf '%s' "$N0" | openssl dgst -sha256 -sign "$WORK/key.pem" | base64 | tr -d '\n')"
req POST "$AUTH/auth/session" "{\"deviceId\":\"$DEVICE\",\"nonce\":\"$N0\",\"signature\":\"$S0\"}"
check "a session with no attestation is 403 ATTESTATION_REQUIRED" "$STATUS $(field .code)" "403 ATTESTATION_REQUIRED"
attest "$DEVICE"
check "a clean device is attested" "$STATUS $(field .verdict)" "200 TRUSTED"

echo "Challenge and session"
req POST "$AUTH/auth/challenge" "{\"deviceId\":\"$DEVICE\"}"
NONCE="$(field .nonce)"
check "challenge returns a nonce" "$STATUS $([ -n "$NONCE" ] && echo yes)" "200 yes"
SIG="$(printf '%s' "$NONCE" | openssl dgst -sha256 -sign "$WORK/key.pem" | base64 | tr -d '\n')"
req POST "$AUTH/auth/session" "{\"deviceId\":\"$DEVICE\",\"nonce\":\"$NONCE\",\"signature\":\"$SIG\",\"attestationId\":\"$ATTEST\"}"
check "signed nonce gives a session" "$STATUS" "200"
TOKEN="$(field .accessToken)"; REFRESH="$(field .refreshToken)"
req POST "$AUTH/auth/session" "{\"deviceId\":\"$DEVICE\",\"nonce\":\"$NONCE\",\"signature\":\"$SIG\"}"
check "a used nonce is 401 NONCE_EXPIRED" "$STATUS $(field .code)" "401 NONCE_EXPIRED"
req POST "$AUTH/auth/challenge" "{\"deviceId\":\"$DEVICE\"}"
N2="$(field .nonce)"
req POST "$AUTH/auth/session" "{\"deviceId\":\"$DEVICE\",\"nonce\":\"$N2\",\"signature\":\"$SIG\"}"
check "a wrong signature is 401 BAD_SIGNATURE" "$STATUS $(field .code)" "401 BAD_SIGNATURE"
req POST "$AUTH/auth/challenge" "{\"deviceId\":\"no-such-device\"}"
check "an unknown device is 401 DEVICE_UNKNOWN" "$STATUS $(field .code)" "401 DEVICE_UNKNOWN"
req POST "$AUTH/auth/refresh" "{\"refreshToken\":\"$REFRESH\"}"
check "refresh gives new tokens" "$STATUS" "200"
TOKEN="$(field .accessToken)"
req POST "$AUTH/auth/refresh" "{\"refreshToken\":\"$REFRESH\"}"
check "a used refresh token is 401 REFRESH_EXPIRED" "$STATUS $(field .code)" "401 REFRESH_EXPIRED"

echo "Accounts summary"
req GET "$ACCOUNT/accounts/summary"
check "summary is 200" "$STATUS" "200"
check "summary displayName" "$(field .displayName)" "ALEX TAN"
check "summary has two accounts" "$(jq '.accounts | length' <<<"$BODY")" "2"
check "summary daily limit" "$(field .paynowDailyLimit)" "5000.00"
ETAG="$(grep -i '^etag:' "$WORK/headers" | cut -d' ' -f2- | tr -d '\r')"
req GET "$ACCOUNT/accounts/summary" "" -H "If-None-Match: $ETAG"
check "same ETag is 304" "$STATUS" "304"
SAVED="$TOKEN"; TOKEN=""
req GET "$ACCOUNT/accounts/summary"
check "no token is 401" "$STATUS" "401"
TOKEN="$SAVED"

echo "Peek Balance pass"
req POST "$AUTH/auth/challenge" "{\"deviceId\":\"$DEVICE\"}"
PN="$(field .nonce)"
PSIG="$(printf '%s' "$PN" | openssl dgst -sha256 -sign "$WORK/key.pem" | base64 | tr -d '\n')"
req POST "$AUTH/auth/session" "{\"deviceId\":\"$DEVICE\",\"nonce\":\"$PN\",\"signature\":\"$PSIG\",\"scope\":\"admin\"}"
check "an unknown scope is 400 BAD_SCOPE" "$STATUS $(field .code)" "400 BAD_SCOPE"
req POST "$AUTH/auth/challenge" "{\"deviceId\":\"$DEVICE\"}"
PN="$(field .nonce)"
PSIG="$(printf '%s' "$PN" | openssl dgst -sha256 -sign "$WORK/key.pem" | base64 | tr -d '\n')"
req POST "$AUTH/auth/session" "{\"deviceId\":\"$DEVICE\",\"nonce\":\"$PN\",\"signature\":\"$PSIG\",\"scope\":\"peek\"}"
check "scope peek gives a token" "$STATUS" "200"
PEEK="$(field .accessToken)"
check "a peek pass has no refresh token" "$(jq 'has("refreshToken")' <<<"$BODY")" "false"
PEEK_SCOPE="$(cut -d. -f2 <<<"$PEEK" | tr '_-' '/+' | awk '{ while (length($0) % 4) $0 = $0 "="; print }' | base64 -d 2>/dev/null | jq -r .scope)"
check "the peek token's scope claim is peek" "$PEEK_SCOPE" "peek"
PEEK_TTL="$(( $(date -d "$(field .expiresAt)" +%s 2>/dev/null || date -j -u -f '%Y-%m-%dT%H:%M:%S' "$(field .expiresAt | cut -c1-19)" +%s) - $(date -u +%s) ))"
check "the peek token lasts at most 60 s" "$([ "$PEEK_TTL" -le 60 ] && echo yes)" "yes"
SAVED="$TOKEN"; TOKEN="$PEEK"
req GET "$ACCOUNT/accounts/peek"
check "peek token reads /accounts/peek" "$STATUS $(field .currency)" "200 SGD"
check "peek shows the first deposit account's balance" "$(field .balance)" "$(TOKEN="$SAVED"; req GET "$ACCOUNT/accounts/summary"; jq -r '.accounts[0].balance' <<<"$BODY")"
check "peek has an asOf time" "$([ -n "$(field .asOf)" ] && echo yes)" "yes"
check "peek lists 3 transactions" "$(jq '.transactions | length' <<<"$BODY")" "3"
check "each transaction has type, date and amount" "$(jq '[.transactions[] | select(.type and .date and .amount)] | length' <<<"$BODY")" "3"
CUTOFF="$(date -u -v-30d +%Y-%m-%d 2>/dev/null || date -u -d '30 days ago' +%Y-%m-%d)"
check "transactions are from the last 30 days" "$(jq --arg c "$CUTOFF" '[.transactions[] | select(.date < $c)] | length' <<<"$BODY")" "0"
check "transactions are newest first" "$(jq '[.transactions[].date] == ([.transactions[].date] | sort | reverse)' <<<"$BODY")" "true"
req GET "$ACCOUNT/accounts/summary"
check "peek token on /accounts/summary is 403 SCOPE_NOT_ALLOWED" "$STATUS $(field .code)" "403 SCOPE_NOT_ALLOWED"
req GET "$LOOKUP/paynow/lookup?type=MOBILE&value=91234567"
check "peek token on lookup is 403 SCOPE_NOT_ALLOWED" "$STATUS $(field .code)" "403 SCOPE_NOT_ALLOWED"
req POST "$PAYMENT/payments/paynow" '{"fromAccountId":"acc-1","proxyType":"MOBILE","proxyValue":"91234567","amount":"1.00","currency":"SGD"}' -H "Idempotency-Key: $(uuid)"
check "peek token on POST /payments/paynow is 403 SCOPE_NOT_ALLOWED" "$STATUS $(field .code)" "403 SCOPE_NOT_ALLOWED"
req GET "$PAYMENT/payments/no-such-payment"
check "peek token on GET /payments/{id} is 403 SCOPE_NOT_ALLOWED" "$STATUS $(field .code)" "403 SCOPE_NOT_ALLOWED"
TOKEN="$SAVED"
req GET "$ACCOUNT/accounts/peek"
check "a full session also reads /accounts/peek" "$STATUS" "200"
TOKEN=""
req GET "$ACCOUNT/accounts/peek"
check "peek with no token is 401" "$STATUS" "401"
TOKEN="$SAVED"

echo "Peek-only device key"
openssl ecparam -name prime256v1 -genkey -noout -out "$WORK/peek.pem" 2>/dev/null
PEEK_PUB="$(openssl ec -in "$WORK/peek.pem" -pubout -outform DER 2>/dev/null | tail -c 65 | base64 | tr -d '\n')"
peek_sign() { printf '%s' "$1" | openssl dgst -sha256 -sign "$WORK/peek.pem" | base64 | tr -d '\n'; }
TOKEN=""
req POST "$AUTH/auth/devices" "{\"username\":\"alextan\",\"otp\":\"123456\",\"deviceName\":\"e2e peek\",\"publicKey\":\"$PEEK_PUB\",\"scope\":\"admin\"}"
check "registering with an unknown scope is 400 BAD_SCOPE" "$STATUS $(field .code)" "400 BAD_SCOPE"
req POST "$AUTH/auth/devices" "{\"username\":\"alextan\",\"otp\":\"123456\",\"deviceName\":\"e2e peek\",\"publicKey\":\"$PEEK_PUB\",\"scope\":\"peek\"}"
check "register a peek-scope device is 201" "$STATUS" "201"
PEEK_DEVICE="$(field .deviceId)"
req POST "$AUTH/auth/challenge" "{\"deviceId\":\"$PEEK_DEVICE\"}"
PN="$(field .nonce)"
req POST "$AUTH/auth/session" "{\"deviceId\":\"$PEEK_DEVICE\",\"nonce\":\"$PN\",\"signature\":\"$(peek_sign "$PN")\",\"scope\":\"peek\"}"
check "a peek-scope device gets a peek pass" "$STATUS $(jq 'has("refreshToken")' <<<"$BODY")" "200 false"
TOKEN="$(field .accessToken)"
req GET "$ACCOUNT/accounts/peek"
check "the peek-scope device's pass reads /accounts/peek" "$STATUS" "200"
TOKEN=""
req POST "$AUTH/auth/challenge" "{\"deviceId\":\"$PEEK_DEVICE\"}"
PN="$(field .nonce)"
req POST "$AUTH/auth/session" "{\"deviceId\":\"$PEEK_DEVICE\",\"nonce\":\"$PN\",\"signature\":\"$(peek_sign "$PN")\"}"
check "a peek-scope device asking for a full session is 403 SCOPE_NOT_ALLOWED" "$STATUS $(field .code)" "403 SCOPE_NOT_ALLOWED"
TOKEN="$SAVED"

echo "Lookup"
req GET "$LOOKUP/paynow/lookup?type=MOBILE&value=91234567"
check "91234567 is found" "$STATUS $(field .maskedName) $(field .bankCode)" "200 TAN ** **NG OCBC"
req GET "$LOOKUP/paynow/lookup?type=MOBILE&value=80000000"
check "80000000 is 404 PROXY_NOT_FOUND" "$STATUS $(field .code)" "404 PROXY_NOT_FOUND"
req GET "$LOOKUP/paynow/lookup?type=MOBILE&value=90000001"
check "90000001 is 504 DIRECTORY_TIMEOUT" "$STATUS $(field .code)" "504 DIRECTORY_TIMEOUT"
LOOKUP_MS="$(curl -s -o /dev/null -w '%{time_total}' -H "Authorization: Bearer $TOKEN" "$LOOKUP/paynow/lookup?type=MOBILE&value=98765432" | awk '{ printf "%d", $1 * 1000 }')"
if [ "${LATENCY_PROFILE:-}" = "measured" ]; then
  check "measured profile: a lookup takes at least 500 ms (${LOOKUP_MS} ms)" "$([ "$LOOKUP_MS" -ge 500 ] && echo yes)" "yes"
else
  check "no latency profile: a lookup takes under 500 ms (${LOOKUP_MS} ms)" "$([ "$LOOKUP_MS" -lt 500 ] && echo yes)" "yes"
fi

echo "Payment to 91234567"
BEFORE="$(available)"
KEY="$(uuid)"
PAY='{"fromAccountId":"acc-1","proxyType":"MOBILE","proxyValue":"91234567","amount":"12.50","currency":"SGD","reference":"e2e"}'
stepup MOBILE 91234567 12.50 "$KEY"
req POST "$PAYMENT/payments/paynow" "$PAY" -H "Idempotency-Key: $KEY" -H "X-Step-Up-Token: $STEPUP"
check "payment is 202 PENDING" "$STATUS $(field .status)" "202 PENDING"
PID1="$(field .paymentId)"
poll "$PID1"
check "payment settles" "$(field .status) $(field .amount) $(field .maskedName)" "SETTLED 12.50 TAN ** **NG"
AFTER="$(available)"
check "balance goes down by 12.50" "$(echo "$BEFORE - $AFTER" | bc)" "12.50"
TOKEN="$PEEK" req GET "$ACCOUNT/accounts/peek"
check "the settled payment tops Peek's transactions" "$(jq -r '.transactions[0] | "\(.type) \(.amount)"' <<<"$BODY")" "PayNow Transfer -12.50"
req POST "$PAYMENT/payments/paynow" "$PAY" -H "Idempotency-Key: $KEY"
check "same Idempotency-Key returns the same paymentId" "$STATUS $(field .paymentId)" "202 $PID1"
check "and the balance doesn't move again" "$(available)" "$AFTER"

echo "Rejected payment to 90000002"
RKEY="$(uuid)"; stepup MOBILE 90000002 20.00 "$RKEY"
BEFORE="$(available)"
req POST "$PAYMENT/payments/paynow" '{"fromAccountId":"acc-1","proxyType":"MOBILE","proxyValue":"90000002","amount":"20.00","currency":"SGD","reference":"e2e"}' -H "Idempotency-Key: $RKEY" -H "X-Step-Up-Token: $STEPUP"
check "payment is 202 PENDING" "$STATUS $(field .status)" "202 PENDING"
poll "$(field .paymentId)"
check "payment is REJECTED by the bank" "$(field .status) $(field .reason)" "REJECTED BENEFICIARY_BANK_REJECTED"
check "the hold is released" "$(available)" "$BEFORE"

echo "Over-balance payment"
OKEY="$(uuid)"; stepup MOBILE 91234567 3000.00 "$OKEY"
req POST "$PAYMENT/payments/paynow" '{"fromAccountId":"acc-1","proxyType":"MOBILE","proxyValue":"91234567","amount":"3000.00","currency":"SGD","reference":"e2e"}' -H "Idempotency-Key: $OKEY" -H "X-Step-Up-Token: $STEPUP"
check "3000.00 from acc-1 is 422 INSUFFICIENT_FUNDS" "$STATUS $(field .code)" "422 INSUFFICIENT_FUNDS"
UKEY="$(uuid)"; stepup MOBILE 80000000 1.00 "$UKEY"
req POST "$PAYMENT/payments/paynow" '{"fromAccountId":"acc-1","proxyType":"MOBILE","proxyValue":"80000000","amount":"1.00","currency":"SGD"}' -H "Idempotency-Key: $UKEY" -H "X-Step-Up-Token: $STEPUP"
check "an unknown proxy is 422 PROXY_NOT_FOUND" "$STATUS $(field .code)" "422 PROXY_NOT_FOUND"

echo "Fraud check and step-up"
NEWPAYEE="9$(printf '%07d' $((RANDOM * RANDOM % 10000000)))"
K1="$(uuid)"
P1="{\"fromAccountId\":\"acc-1\",\"proxyType\":\"MOBILE\",\"proxyValue\":\"$NEWPAYEE\",\"amount\":\"1.00\",\"currency\":\"SGD\"}"
req POST "$PAYMENT/payments/paynow" "$P1" -H "Idempotency-Key: $K1"
check "a new payee is 403 STEP_UP_REQUIRED" "$STATUS $(field .code)" "403 STEP_UP_REQUIRED"
stepup MOBILE "$NEWPAYEE" 1.00 "$K1"
req POST "$PAYMENT/payments/paynow" "$P1" -H "Idempotency-Key: $(uuid)" -H "X-Step-Up-Token: $STEPUP"
check "a step-up for another payment is 403 STEP_UP_INVALID" "$STATUS $(field .code)" "403 STEP_UP_INVALID"
SAVED="$TOKEN"; TOKEN="$STEPUP"
req GET "$ACCOUNT/accounts/summary"
check "a step-up token opens nothing else" "$STATUS $(field .code)" "403 SCOPE_NOT_ALLOWED"
TOKEN="$SAVED"
req POST "$PAYMENT/payments/paynow" "$P1" -H "Idempotency-Key: $K1" -H "X-Step-Up-Token: $STEPUP"
check "the matching step-up pays" "$STATUS" "202"
poll "$(field .paymentId)"
req POST "$PAYMENT/payments/paynow" "$P1" -H "Idempotency-Key: $(uuid)"
check "the payee is known after it settles" "$STATUS" "202"
poll "$(field .paymentId)"
req POST "$PAYMENT/payments/paynow" '{"fromAccountId":"acc-2","proxyType":"MOBILE","proxyValue":"91234567","amount":"1000.01","currency":"SGD"}' -H "Idempotency-Key: $(uuid)"
check "S\$1,000.01 to a known payee is 403 STEP_UP_REQUIRED" "$STATUS $(field .code)" "403 STEP_UP_REQUIRED"

echo "Latency multiplier"
for pair in 1:600 3:1800; do
  m="${pair%%:*}"; want="${pair##*:}"
  ms="$(curl -s -o /dev/null -w '%{time_total}' -H "Authorization: Bearer $TOKEN" -H "X-Latency-Multiplier: $m" "$ACCOUNT/accounts/summary" | awk '{ printf "%d", $1 * 1000 }')"
  check "${m}x summary takes $want ms or a little more (${ms} ms)" "$([ "$ms" -ge "$want" ] && [ "$ms" -lt $((want + 400)) ] && echo yes)" "yes"
done
req GET "$ACCOUNT/accounts/summary" "" -H "X-Latency-Multiplier: 50"
check "any other multiplier is 400" "$STATUS $(field .code)" "400 BAD_REQUEST"

echo "Traces"
RUN="$(uuid)"
TRACE="{\"run_id\":\"$RUN\",\"flow\":\"router\",\"multiplier\":1,\"source\":\"e2e\",\"spans\":[{\"name\":\"x\",\"kind\":\"ui\",\"start_ms\":0,\"end_ms\":1,\"critical_path\":true}]}"
SAVED="$TOKEN"; TOKEN=""
req POST "$AUTH/auth/traces" "$TRACE"
check "a trace with no session is 401" "$STATUS" "401"
TOKEN="$SAVED"
req POST "$AUTH/auth/traces" "$TRACE"
check "a trace is stored" "$STATUS" "201"
req GET "$AUTH/auth/traces/latest?flow=router&multiplier=1"
check "the latest trace comes back" "$STATUS $(field .run_id)" "200 $RUN"
req POST "$AUTH/auth/traces" '{"run_id":"x","spans":[]}'
check "a malformed trace is 400" "$STATUS" "400"

echo "Kill switch"
session "$DEVICE" "$WORK/key.pem"
req GET "$ACCOUNT/accounts/summary"
check "the session works" "$STATUS" "200"
req POST "$AUTH/auth/devices/revoke" '{}'
check "revoke" "$STATUS $(field .revoked)" "200 true"
for url in "$ACCOUNT/accounts/summary" "$LOOKUP/paynow/lookup?type=MOBILE&value=91234567" "$PAYMENT/payments/x"; do
  req GET "$url"
  check "the very next request is 401 DEVICE_REVOKED: ${url#http://localhost:}" "$STATUS $(field .code)" "401 DEVICE_REVOKED"
done

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
