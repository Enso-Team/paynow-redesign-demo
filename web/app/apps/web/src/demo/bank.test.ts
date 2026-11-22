import { beforeEach, describe, expect, it } from "vitest";
import { createBank, STATE_KEY, type BankResponse } from "./bank";
import { derToP1363, p1363ToDer, toBase64 } from "../lib/der";
import { networkMs, MEASURED } from "./latency";

class MemoryStorage {
  data = new Map<string, string>();
  getItem(k: string) {
    return this.data.get(k) ?? null;
  }
  setItem(k: string, v: string) {
    this.data.set(k, v);
  }
}

let clock = Date.parse("2026-11-20T09:30:00Z");
let storage: MemoryStorage;
const deps = () => ({
  storage,
  now: () => clock,
  sleep: async (ms: number) => {
    clock += ms;
  },
  settleMs: 2000,
});

async function newKey() {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const raw = new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey));
  const sign = async (nonce: string) =>
    toBase64(p1363ToDer(new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, pair.privateKey, new TextEncoder().encode(nonce)))));
  return { publicKey: toBase64(raw), sign };
}

function client(bank = createBank(deps())) {
  let token = "";
  const call = (service: string, method: string, url: string, body?: unknown, headers: Record<string, string> = {}) => {
    const u = new URL(url, "http://demo");
    const h = new Headers(headers);
    if (token && !h.has("Authorization")) h.set("Authorization", `Bearer ${token}`);
    return bank.handle({ service, method, path: u.pathname, query: u.searchParams, headers: h, body: body ?? null }) as Promise<
      BankResponse & { body: Record<string, any> }
    >;
  };
  return {
    call,
    bank,
    setToken: (t: string) => (token = t),
    async signIn(scope?: "peek", key?: Awaited<ReturnType<typeof newKey>>, deviceScope?: string) {
      const k = key ?? (await newKey());
      const reg = await call("auth", "POST", "/auth/devices", { username: "alextan", otp: "123456", deviceName: "t", publicKey: k.publicKey, ...(deviceScope ? { scope: deviceScope } : {}) });
      const deviceId = reg.body.deviceId;
      const { body: ch } = await call("auth", "POST", "/auth/challenge", { deviceId });
      const s = await call("auth", "POST", "/auth/session", { deviceId, nonce: ch.nonce, signature: await k.sign(ch.nonce), ...(scope ? { scope } : {}) });
      return { deviceId, key: k, session: s };
    },
  };
}

beforeEach(() => {
  storage = new MemoryStorage();
  clock = Date.parse("2026-11-20T09:30:00Z");
});

describe("demo bank: auth", () => {
  it("binds a device with the OTP and opens a session from a signed nonce", async () => {
    const c = client();
    const bad = await c.call("auth", "POST", "/auth/devices", { username: "alextan", otp: "000000", publicKey: "x" });
    expect([bad.status, bad.body.code]).toEqual([401, "BAD_OTP"]);
    const { session, deviceId, key } = await c.signIn();
    expect(session.status).toBe(200);
    expect(session.body.refreshToken).toBeTruthy();
    const claims = JSON.parse(atob(session.body.accessToken.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
    expect(claims).toMatchObject({ sub: "user-1", deviceId });
    expect(claims.exp * 1000 - clock).toBeLessThanOrEqual(5 * 60_000);

    const { body: ch } = await c.call("auth", "POST", "/auth/challenge", { deviceId });
    const wrong = await c.call("auth", "POST", "/auth/session", { deviceId, nonce: ch.nonce, signature: await key.sign("other") });
    expect(wrong.body.code).toBe("BAD_SIGNATURE");
    const used = await c.call("auth", "POST", "/auth/session", { deviceId, nonce: ch.nonce, signature: await key.sign(ch.nonce) });
    expect(used.body.code).toBe("NONCE_EXPIRED");
    expect((await c.call("auth", "POST", "/auth/challenge", { deviceId: "nope" })).body.code).toBe("DEVICE_UNKNOWN");
  });

  it("rolls refresh tokens and rejects a used one", async () => {
    const c = client();
    const { session } = await c.signIn();
    const r1 = await c.call("auth", "POST", "/auth/refresh", { refreshToken: session.body.refreshToken });
    expect(r1.status).toBe(200);
    const r2 = await c.call("auth", "POST", "/auth/refresh", { refreshToken: session.body.refreshToken });
    expect([r2.status, r2.body.code]).toEqual([401, "REFRESH_EXPIRED"]);
  });

  it("keeps the device across a reload of the page", async () => {
    const c = client();
    const { deviceId, key } = await c.signIn();
    const again = client();
    const { body: ch } = await again.call("auth", "POST", "/auth/challenge", { deviceId });
    const s = await again.call("auth", "POST", "/auth/session", { deviceId, nonce: ch.nonce, signature: await key.sign(ch.nonce) });
    expect(s.status).toBe(200);
  });
});

describe("demo bank: Peek scope", () => {
  it("a Peek pass reads /accounts/peek and nothing else", async () => {
    const c = client();
    const { session: peek } = await c.signIn("peek");
    expect(peek.body.refreshToken).toBeUndefined();
    c.setToken(peek.body.accessToken);
    const p = await c.call("account", "GET", "/accounts/peek");
    expect(p.status).toBe(200);
    expect(p.headers?.["Cache-Control"]).toBe("no-store");
    expect(p.body.balance).toBe("2,345.67");
    expect(p.body.transactions).toEqual([
      { type: "FAST Payment / Receipt", date: "2026-11-18", amount: "500.00" },
      { type: "NETS Purchase", date: "2026-11-16", amount: "-8.40" },
      { type: "PayNow Transfer", date: "2026-11-11", amount: "-25.00" },
    ]);
    for (const [svc, m, path] of [
      ["account", "GET", "/accounts/summary"],
      ["lookup", "GET", "/paynow/lookup?type=MOBILE&value=91234567"],
      ["payment", "POST", "/payments/paynow"],
      ["payment", "GET", "/payments/x"],
    ]) {
      expect((await c.call(svc, m, path, {}, { "Idempotency-Key": "k" })).body.code).toBe("SCOPE_NOT_ALLOWED");
    }
    clock += 61_000;
    expect((await c.call("account", "GET", "/accounts/peek")).status).toBe(401);
  });

  it("a peek-scope device can't open a full session, and a bad scope is 400", async () => {
    const c = client();
    const k = await newKey();
    const { deviceId } = await c.signIn("peek", k, "peek");
    const { body: ch } = await c.call("auth", "POST", "/auth/challenge", { deviceId });
    const full = await c.call("auth", "POST", "/auth/session", { deviceId, nonce: ch.nonce, signature: await k.sign(ch.nonce) });
    expect([full.status, full.body.code]).toEqual([403, "SCOPE_NOT_ALLOWED"]);
    const bad = await c.call("auth", "POST", "/auth/session", { deviceId, nonce: "n", signature: "s", scope: "admin" });
    expect(bad.body.code).toBe("BAD_SCOPE");
  });
});

describe("demo bank: summary, lookup and payments", () => {
  async function signedIn() {
    const c = client();
    const { session } = await c.signIn();
    c.setToken(session.body.accessToken);
    return c;
  }
  const available = async (c: Awaited<ReturnType<typeof signedIn>>) =>
    (await c.call("account", "GET", "/accounts/summary")).body.accounts[0].available;

  it("serves the summary with an ETag and 304", async () => {
    const c = await signedIn();
    const s = await c.call("account", "GET", "/accounts/summary");
    expect(s.body).toMatchObject({ displayName: "ALEX TAN", paynowDailyLimit: "5000.00", paynowUsedToday: "0.00" });
    expect(s.body.accounts.map((a: { balance: string }) => a.balance)).toEqual(["2,345.67", "10,120.00"]);
    const again = await c.call("account", "GET", "/accounts/summary", null, { "If-None-Match": s.headers!.ETag });
    expect(again.status).toBe(304);
  });

  it("looks up seeded, made-up, missing and slow proxies", async () => {
    const c = await signedIn();
    const hit = await c.call("lookup", "GET", "/paynow/lookup?type=MOBILE&value=91234567");
    expect(hit.body).toEqual({ proxyType: "MOBILE", proxyValue: "91234567", maskedName: "TAN ** **NG", bankCode: "OCBC" });
    expect((await c.call("lookup", "GET", "/paynow/lookup?type=MOBILE&value=81234567")).body.maskedName).toBe("TOH ** **FM");
    expect((await c.call("lookup", "GET", "/paynow/lookup?type=MOBILE&value=80000000")).status).toBe(404);
    const start = clock;
    const slow = await c.call("lookup", "GET", "/paynow/lookup?type=MOBILE&value=90000001");
    expect([slow.status, slow.body.code, clock - start]).toEqual([504, "DIRECTORY_TIMEOUT", 2000]);
    expect((await c.call("lookup", "GET", "/paynow/lookup?type=MOBILE&value=123")).body.code).toBe("INVALID_PROXY");
  });

  it("rate-limits lookups at 30 a minute", async () => {
    const c = await signedIn();
    for (let i = 0; i < 30; i++) await c.call("lookup", "GET", "/paynow/lookup?type=MOBILE&value=91234567");
    expect((await c.call("lookup", "GET", "/paynow/lookup?type=MOBILE&value=91234567")).body.code).toBe("RATE_LIMITED");
  });

  it("holds, then settles after the FAST time, and repeats are idempotent", async () => {
    const c = await signedIn();
    const pay = { fromAccountId: "acc-1", proxyType: "MOBILE", proxyValue: "91234567", amount: "12.50", currency: "SGD", reference: "t" };
    const r = await c.call("payment", "POST", "/payments/paynow", pay, { "Idempotency-Key": "key-1" });
    expect(r.status).toBe(202);
    expect(r.body.status).toBe("PENDING");
    expect(await available(c)).toBe("2333.17");
    expect((await c.call("account", "GET", "/accounts/summary")).body.accounts[0].balance).toBe("2,345.67");

    const start = clock;
    const done = await c.call("payment", "GET", `/payments/${r.body.paymentId}?waitMs=5000`);
    expect(done.body).toMatchObject({ status: "SETTLED", amount: "12.50", maskedName: "TAN ** **NG" });
    expect(clock - start).toBeLessThanOrEqual(2000);
    expect((await c.call("account", "GET", "/accounts/summary")).body.accounts[0].balance).toBe("2,333.17");
    expect((await c.call("account", "GET", "/accounts/summary")).body.paynowUsedToday).toBe("12.50");

    const repeat = await c.call("payment", "POST", "/payments/paynow", pay, { "Idempotency-Key": "key-1" });
    expect(repeat.body.paymentId).toBe(r.body.paymentId);
    expect(await available(c)).toBe("2333.17");

    const peek = await c.call("account", "GET", "/accounts/peek");
    expect(peek.body.transactions[0]).toEqual({ type: "PayNow Transfer", date: "2026-11-20", amount: "-12.50" });
  });

  it("rejects 90000002 at FAST and releases the hold", async () => {
    const c = await signedIn();
    const before = await available(c);
    const r = await c.call("payment", "POST", "/payments/paynow", { fromAccountId: "acc-1", proxyType: "MOBILE", proxyValue: "90000002", amount: "20.00" }, { "Idempotency-Key": "k2" });
    const done = await c.call("payment", "GET", `/payments/${r.body.paymentId}?waitMs=5000`);
    expect([done.body.status, done.body.reason]).toEqual(["REJECTED", "BENEFICIARY_BANK_REJECTED"]);
    expect(await available(c)).toBe(before);
    expect((await c.call("account", "GET", "/accounts/summary")).body.paynowUsedToday).toBe("0.00");
  });

  it("refuses over-balance, over-limit, unknown proxies and a missing key", async () => {
    const c = await signedIn();
    const pay = (amount: string, proxyValue = "91234567", fromAccountId = "acc-1", key = crypto.randomUUID()) =>
      c.call("payment", "POST", "/payments/paynow", { fromAccountId, proxyType: "MOBILE", proxyValue, amount }, { "Idempotency-Key": key });
    expect((await pay("3000.00")).body.code).toBe("INSUFFICIENT_FUNDS");
    expect((await pay("5000.01", "91234567", "acc-2")).body.code).toBe("LIMIT_EXCEEDED");
    expect([(await pay("1.00", "80000000")).status, (await pay("1.00", "80000000")).body.code]).toEqual([422, "PROXY_NOT_FOUND"]);
    expect((await pay("1.001")).body.code).toBe("INVALID_AMOUNT");
    const noKey = await c.call("payment", "POST", "/payments/paynow", { fromAccountId: "acc-1", proxyType: "MOBILE", proxyValue: "91234567", amount: "1" });
    expect(noKey.body.code).toBe("MISSING_IDEMPOTENCY_KEY");
  });

  it("keeps each visitor's account in their storage across reloads", async () => {
    const c = await signedIn();
    const r = await c.call("payment", "POST", "/payments/paynow", { fromAccountId: "acc-1", proxyType: "MOBILE", proxyValue: "91234567", amount: "100.00" }, { "Idempotency-Key": "k3" });
    clock += 2500;
    const later = client();
    const { session } = await later.signIn();
    later.setToken(session.body.accessToken);
    expect((await later.call("account", "GET", "/accounts/summary")).body.accounts[0].balance).toBe("2,245.67");
    expect(JSON.parse(storage.getItem(STATE_KEY)!).payments[r.body.paymentId].status).toBe("SETTLED");
    storage = new MemoryStorage();
    const someoneElse = client();
    const s2 = await someoneElse.signIn();
    someoneElse.setToken(s2.session.body.accessToken);
    expect((await someoneElse.call("account", "GET", "/accounts/summary")).body.accounts[0].balance).toBe("2,345.67");
  });
});

describe("measured latency", () => {
  it("uses the shared table for the same endpoints as the services", () => {
    expect(networkMs("POST", "/auth/session")).toBe(300);
    expect(networkMs("GET", "/paynow/lookup")).toBe(500);
    expect(networkMs("GET", "/accounts/summary")).toBe(600);
    expect(networkMs("POST", "/payments/paynow")).toBe(300);
    expect(networkMs("POST", "/auth/challenge")).toBe(0);
    expect(MEASURED["fast.settle"]).toBe(2000);
  });
});

describe("derToP1363", () => {
  it("round-trips with p1363ToDer", () => {
    const raw = crypto.getRandomValues(new Uint8Array(64));
    raw[0] = 0;
    raw[32] = 0x90;
    expect(Array.from(derToP1363(p1363ToDer(raw)))).toEqual(Array.from(raw));
  });
});
