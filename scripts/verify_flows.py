#!/usr/bin/env python3
"""Runs both dependency chains against the live services from this Mac and prints every backend span.

Backend spans are real HTTP calls. There is no phone here, so Face ID and the scan are fixed stand-in waits,
the same in both flows, and there are no UI spans. Record on the iPhone for those.
Writes sequential.json and router.json to the directory given (default: a temp directory).
"""
import base64, hashlib, json, pathlib, subprocess, sys, tempfile, threading, time, urllib.error, urllib.request, uuid

AUTH, ACCOUNT, LOOKUP, PAYMENT = (f"http://localhost:{p}" for p in (8081, 8082, 8083, 8084))
MULTIPLIER, FACE_ID, SCAN = 3, 1.2, 2.5
PAYEE, AMOUNT = "91234567", "1.00"
out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp())
out.mkdir(parents=True, exist_ok=True)
key = out / "key.pem"


class Run:
    def __init__(self):
        self.spans, self.t0 = [], time.monotonic()

    def now(self):
        return (time.monotonic() - self.t0) * 1000

    def wait(self, name, kind, secs):
        start = self.now()
        time.sleep(secs)
        self.spans.append(dict(name=name, kind=kind, start_ms=start, end_ms=self.now(), critical_path=True))

    def call(self, method, base, path, body=None, token=None, headers=None, name=None):
        req = urllib.request.Request(base + path, method=method, data=None if body is None else json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json", "X-Latency-Multiplier": str(MULTIPLIER),
                                              **({"Authorization": f"Bearer {token}"} if token else {}), **(headers or {})})
        start = self.now()
        with urllib.request.urlopen(req, timeout=30) as res:
            data, timing = json.load(res), res.headers.get("Server-Timing", "")
        durations = dict(p.strip().split(";dur=") for p in timing.split(",") if ";dur=" in p)
        self.spans.append(dict(name=name or f"{method} {path.split('?')[0]}", kind="backend", start_ms=start, end_ms=self.now(),
                               critical_path=True, status=res.status, server_delay_ms=float(durations.get("delay", 0)),
                               server_app_ms=float(durations.get("app", 0))))
        return data

    def span(self, name):
        return next(s for s in self.spans if s["name"] == name)


def sign(text):
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", str(key)], input=text.encode(), capture_output=True, check=True).stdout
    return base64.b64encode(der).decode()


def attest(run):
    return run.call("POST", AUTH, "/auth/attest", dict(deviceId=device, platform="mac-check", osVersion="", appVersion="", signals=[]))["attestationId"]


def session(run, attestation):
    nonce = run.call("POST", AUTH, "/auth/challenge", dict(deviceId=device))["nonce"]
    return run.call("POST", AUTH, "/auth/session", dict(deviceId=device, nonce=nonce, signature=sign(nonce), attestationId=attestation))["accessToken"]


def pay(run, token):
    idem = str(uuid.uuid4())
    body = dict(fromAccountId="acc-1", proxyType="MOBILE", proxyValue=PAYEE, amount=AMOUNT, currency="SGD", reference="verify")
    payment = run.call("POST", PAYMENT, "/payments/paynow", body, token, {"Idempotency-Key": idem})["paymentId"]
    while run.call("GET", PAYMENT, f"/payments/{payment}?waitMs=5000", token=token, name="GET /payments/{id}")["status"] == "PENDING":
        pass


def sequential():
    run = Run()
    run.wait("Scan (stand-in)", "user", SCAN)
    attestation = attest(run)
    run.wait("Face ID (stand-in)", "biometric", FACE_ID)
    token = session(run, attestation)
    run.call("GET", ACCOUNT, "/accounts/summary", token=token)
    run.call("GET", LOOKUP, f"/paynow/lookup?type=MOBILE&value={PAYEE}", token=token)
    pay(run, token)
    return run


def router():
    run, box = Run(), {}
    worker = threading.Thread(target=lambda: box.update(id=attest(run)))
    worker.start()
    run.wait("Face ID (stand-in)", "biometric", FACE_ID)
    worker.join()
    token = session(run, box["id"])
    home = threading.Thread(target=lambda: run.call("GET", ACCOUNT, "/accounts/summary", token=token))
    home.start()
    run.wait("Scan (stand-in)", "user", SCAN)
    run.call("GET", LOOKUP, f"/paynow/lookup?type=MOBILE&value={PAYEE}", token=token)
    home.join()
    pay(run, token)
    run.span("POST /auth/attest")["critical_path"] = run.span("POST /auth/attest")["end_ms"] > run.span("Face ID (stand-in)")["end_ms"]
    run.span("GET /accounts/summary")["critical_path"] = run.span("GET /accounts/summary")["end_ms"] > run.span("GET /paynow/lookup")["end_ms"]
    return run


subprocess.run(["openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", str(key)], check=True, capture_output=True)
public = subprocess.run(["openssl", "ec", "-in", str(key), "-pubout", "-outform", "DER"], check=True, capture_output=True).stdout[-65:]
device = Run().call("POST", AUTH, "/auth/devices", dict(username="alextan", otp="123456", deviceName="verify",
                                                        publicKey=base64.b64encode(public).decode()))["deviceId"]
try:
    for name, flow in (("sequential", sequential), ("router", router)):
        run = flow()
        spans = sorted(run.spans, key=lambda s: s["start_ms"])
        (out / f"{name}.json").write_text(json.dumps(dict(
            run_id=str(uuid.uuid4()), flow=name, multiplier=MULTIPLIER, source="Mac check, no phone", biometric_mocked=True, spans=spans,
            note="Backend calls are real. Face ID and the scan are fixed stand-ins, and UI is not measured. Phone runs replace this."), indent=1))
        print(f"\n{name} at {MULTIPLIER}x")
        for s in spans:
            print(f"  {s['start_ms']:7.0f} {s['end_ms'] - s['start_ms']:6.0f} ms  {s['kind']:9} {'path' if s['critical_path'] else 'OFF '}  {s['name']}")
finally:
    key.unlink()
print(f"\nTraces in {out}")
