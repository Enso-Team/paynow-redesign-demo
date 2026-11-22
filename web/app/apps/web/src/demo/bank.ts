/**
 * The demo build's backend, in the browser. It answers the same endpoints, bodies and error codes as the
 * services in CONTRACTS.md, for one Alex Tan whose accounts live in this visitor's localStorage.
 * Network time is added by the fetch shim (install.ts), the way the measured profile adds it to the services.
 */
import { derToP1363, fromBase64 } from "../lib/der";
import { findProxy, type Proxy } from "./directory";

export interface BankRequest {
  service: string;
  method: string;
  path: string;
  query: URLSearchParams;
  headers: Headers;
  body: unknown;
}

export interface BankResponse {
  status: number;
  headers?: Record<string, string>;
  body?: unknown;
}

export interface BankDeps {
  storage: Pick<Storage, "getItem" | "setItem">;
  now: () => number;
  sleep: (ms: number) => Promise<void>;
  /** mock-fast's settle time, from the measured table. */
  settleMs: number;
}

export const STATE_KEY = "dbs.demo.bank";
const USER = { id: "user-1", username: "alextan", displayName: "Alex Tan" };
const OTP = "123456";
const ACCESS_TTL = 5 * 60_000;
const REFRESH_TTL = 30 * 60_000;
const NONCE_TTL = 60_000;
const PEEK_TTL = 60_000;
const DAILY_LIMIT = 500_000;
const DIRECTORY_TIMEOUT = 2_000;
const LOOKUP_CACHE = 60_000;
const LOOKUP_RATE = 30;
const MAX_WAIT = 30_000;
const DAY = 86_400_000;

interface Device {
  userId: string;
  publicKey: string;
  name: string;
  scope: "full" | "peek";
}

interface Payment {
  id: string;
  key: string;
  userId: string;
  fromAccountId: string;
  proxyType: string;
  proxyValue: string;
  maskedName: string;
  bankCode: string;
  amount: number;
  reference: string | null;
  status: "PENDING" | "SETTLED" | "REJECTED";
  reason: string | null;
  createdAt: number;
  settlesAt: number;
  settledAt: number | null;
}

/** Amounts are integer cents. */
interface State {
  devices: Record<string, Device>;
  accounts: { id: string; userId: string; name: string; numberMasked: string; balance: number; currency: string }[];
  holds: Record<string, { accountId: string; amount: number; status: "HELD" | "CAPTURED" | "RELEASED" }>;
  usage: Record<string, number>;
  transactions: { id: string; accountId: string; type: string; amount: number; postedAt: number }[];
  payments: Record<string, Payment>;
}

interface Claims {
  userId: string;
  deviceId: string;
  exp: number;
  scope?: string;
}

class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

const fail = (status: number, code: string, message: string) => new ApiError(status, code, message);

function seed(now: number): State {
  return {
    devices: {},
    accounts: [
      { id: "acc-1", userId: USER.id, name: "Everyday Savings", numberMasked: "•••• 1234", balance: 234_567, currency: "SGD" },
      { id: "acc-2", userId: USER.id, name: "Bonus Savings", numberMasked: "•••• 5678", balance: 1_012_000, currency: "SGD" },
    ],
    holds: {},
    usage: {},
    transactions: seedTransactions(now),
    payments: {},
  };
}

/** Seed rows dated relative to each start, as the account service's data.sql does. */
function seedTransactions(now: number): State["transactions"] {
  return [
    { id: "seed-1", accountId: "acc-1", type: "FAST Payment / Receipt", amount: 50_000, postedAt: now - 2 * DAY },
    { id: "seed-2", accountId: "acc-1", type: "NETS Purchase", amount: -840, postedAt: now - 4 * DAY },
    { id: "seed-3", accountId: "acc-1", type: "PayNow Transfer", amount: -2_500, postedAt: now - 9 * DAY },
    { id: "seed-4", accountId: "acc-1", type: "GIRO Payment", amount: -6_000, postedAt: now - 41 * DAY },
  ];
}

const sgDay = (t: number) => new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Singapore" }).format(new Date(t));
const plain = (cents: number) => `${cents < 0 ? "-" : ""}${Math.floor(Math.abs(cents) / 100)}.${String(Math.abs(cents) % 100).padStart(2, "0")}`;
const display = (cents: number) =>
  (cents / 100).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

function randomToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function b64url(obj: unknown): string {
  return btoa(JSON.stringify(obj)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** Parses a decimal amount into cents. Null when it isn't positive with at most 2 decimals. */
function cents(value: unknown): number | null {
  const s = typeof value === "number" ? String(value) : typeof value === "string" ? value.trim() : "";
  const m = /^(\d+)(?:\.(\d{1,2}))?0*$/.exec(s);
  if (!m) return null;
  const c = Number(m[1]) * 100 + Number((m[2] ?? "").padEnd(2, "0"));
  return c > 0 ? c : null;
}

function validProxy(type: string | null, value: string | null) {
  const ok =
    value != null &&
    ((type === "MOBILE" && /^[89]\d{7}$/.test(value)) || (type === "UEN" && /^[A-Za-z0-9]{9,10}$/.test(value)));
  if (!ok) throw fail(400, "INVALID_PROXY", "Not a valid PayNow mobile number or UEN");
}

async function verifySignature(publicKey: string, nonce: string, signature: string): Promise<boolean> {
  try {
    const key = await crypto.subtle.importKey("raw", fromBase64(publicKey), { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
    const raw = fromBase64(signature);
    const sig: Uint8Array<ArrayBuffer> = raw.length === 64 ? raw : derToP1363(raw);
    return await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, sig, new TextEncoder().encode(nonce));
  } catch {
    return false;
  }
}

async function validPublicKey(publicKey: string): Promise<boolean> {
  try {
    await crypto.subtle.importKey("raw", fromBase64(publicKey), { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
    return true;
  } catch {
    return false;
  }
}

async function etagOf(body: unknown): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify(body))));
  return `"${Array.from(digest.slice(0, 12), (b) => b.toString(16).padStart(2, "0")).join("")}"`;
}

export function createBank(deps: BankDeps) {
  const { storage, now } = deps;
  // Tokens, nonces, the lookup cache and the rate limit live in memory for the life of the page.
  const tokens = new Map<string, Claims>();
  const refreshTokens = new Map<string, { deviceId: string; expiresAt: number }>();
  const nonces = new Map<string, { deviceId: string; expiresAt: number }>();
  const lookupCache = new Map<string, { proxy: Proxy; expiresAt: number }>();
  const lookupCalls = new Map<string, number[]>();

  const load = (): State => {
    const text = storage.getItem(STATE_KEY);
    if (text) {
      try {
        return JSON.parse(text) as State;
      } catch {
        /* a broken state starts over */
      }
    }
    return seed(now());
  };
  const save = (s: State) => storage.setItem(STATE_KEY, JSON.stringify(s));

  {
    const s = load();
    const fresh = new Map(seedTransactions(now()).map((t) => [t.id, t]));
    s.transactions = s.transactions.map((t) => fresh.get(t.id) ?? t);
    save(s);
  }

  /** Reads, changes and writes the stored state in one step, settling any payment whose FAST time has passed. */
  const tx = <T>(fn: (s: State) => T): T => {
    const s = load();
    settleDue(s);
    const out = fn(s);
    save(s);
    return out;
  };

  function settleDue(s: State) {
    for (const p of Object.values(s.payments)) {
      if (p.status !== "PENDING" || now() < p.settlesAt) continue;
      const hold = s.holds[p.id];
      if (p.bankCode === "REJECT") {
        if (hold?.status === "HELD") {
          const day = sgDay(now());
          s.usage[day] = Math.max(0, (s.usage[day] ?? 0) - hold.amount);
          hold.status = "RELEASED";
        }
        p.status = "REJECTED";
        p.reason = "BENEFICIARY_BANK_REJECTED";
      } else {
        if (hold?.status === "HELD") {
          const acc = s.accounts.find((a) => a.id === hold.accountId);
          if (acc) acc.balance -= hold.amount;
          hold.status = "CAPTURED";
          s.transactions.push({ id: p.id, accountId: hold.accountId, type: "PayNow Transfer", amount: -hold.amount, postedAt: p.settlesAt });
        }
        p.status = "SETTLED";
      }
      p.settledAt = p.settlesAt;
    }
  }

  const sign = (userId: string, deviceId: string, exp: number, scope?: string) => {
    const claims = { sub: userId, deviceId, ...(scope ? { scope } : {}), iat: Math.floor(now() / 1000), exp: Math.floor(exp / 1000) };
    const token = `${b64url({ alg: "HS256", typ: "JWT" })}.${b64url(claims)}.${randomToken()}`;
    tokens.set(token, { userId, deviceId, exp, scope });
    return token;
  };

  const issue = (userId: string, deviceId: string) => {
    const expiresAt = now() + ACCESS_TTL;
    const refreshToken = randomToken();
    refreshTokens.set(refreshToken, { deviceId, expiresAt: now() + REFRESH_TTL });
    return { accessToken: sign(userId, deviceId, expiresAt), refreshToken, expiresAt: new Date(expiresAt).toISOString() };
  };

  /** The Bearer token's userId. A scoped token reaches only endpoints that allow its scope. */
  const userId = (headers: Headers, allowedScope?: string): string => {
    const auth = headers.get("Authorization");
    if (!auth?.startsWith("Bearer ")) throw fail(401, "UNAUTHORIZED", "Missing Bearer token");
    const claims = tokens.get(auth.slice(7).trim());
    if (!claims) throw fail(401, "UNAUTHORIZED", "Invalid token");
    if (claims.exp < now()) throw fail(401, "TOKEN_EXPIRED", "Session expired");
    if (claims.scope && claims.scope !== allowedScope) throw fail(403, "SCOPE_NOT_ALLOWED", "This token can't reach this endpoint");
    return claims.userId;
  };

  const device = (s: State, id: unknown): Device => {
    const d = typeof id === "string" ? s.devices[id] : undefined;
    if (!d) throw fail(401, "DEVICE_UNKNOWN", "This device isn't registered");
    return d;
  };

  /** The directory call the lookup and payment services make, with its 2 s timeout. */
  const resolve = async (type: string, value: string): Promise<Proxy> => {
    const hit = findProxy(type, value);
    if (!hit) throw fail(404, "PROXY_NOT_FOUND", "No PayNow account for this proxy");
    if (hit.latencyMs >= DIRECTORY_TIMEOUT) {
      await deps.sleep(DIRECTORY_TIMEOUT);
      throw fail(504, "DIRECTORY_TIMEOUT", "The PayNow directory didn't answer in time");
    }
    if (hit.latencyMs > 0) await deps.sleep(hit.latencyMs);
    return hit.proxy;
  };

  type Body = Record<string, unknown>;
  type Handler = (req: BankRequest, body: Body, params: string[]) => Promise<BankResponse> | BankResponse;

  const routes: [string, string, RegExp, Handler][] = [
    ["auth", "POST", /^\/auth\/devices$/, async (_req, b) => {
      if (b.username !== USER.username || b.otp !== OTP) throw fail(401, "BAD_OTP", "The username or one-time password is wrong");
      if (typeof b.publicKey !== "string") throw fail(400, "BAD_REQUEST", "publicKey is required");
      if (!(await validPublicKey(b.publicKey))) throw fail(400, "BAD_PUBLIC_KEY", "publicKey must be a base64 X9.63 P-256 public key");
      const scope = b.scope == null ? "full" : b.scope;
      if (scope !== "full" && scope !== "peek") throw fail(400, "BAD_SCOPE", 'scope must be "full", "peek" or left out');
      const deviceId = crypto.randomUUID();
      tx((s) => {
        s.devices[deviceId] = { userId: USER.id, publicKey: b.publicKey as string, name: String(b.deviceName || "Device"), scope };
      });
      return { status: 201, body: { deviceId, userId: USER.id } };
    }],
    ["auth", "POST", /^\/auth\/challenge$/, (_req, b) => {
      tx((s) => device(s, b.deviceId));
      const nonce = randomToken();
      const expiresAt = now() + NONCE_TTL;
      for (const [n, v] of nonces) if (v.expiresAt < now()) nonces.delete(n);
      nonces.set(nonce, { deviceId: String(b.deviceId), expiresAt });
      return { status: 200, body: { nonce, expiresAt: new Date(expiresAt).toISOString() } };
    }],
    ["auth", "POST", /^\/auth\/session$/, async (_req, b) => {
      if (b.scope != null && b.scope !== "peek") throw fail(400, "BAD_SCOPE", 'scope must be "peek" or left out');
      const d = tx((s) => device(s, b.deviceId));
      const nonce = nonces.get(String(b.nonce));
      if (!nonce || nonce.deviceId !== b.deviceId || nonce.expiresAt < now()) {
        throw fail(401, "NONCE_EXPIRED", "The challenge expired. Ask for a new one");
      }
      nonces.delete(String(b.nonce));
      if (typeof b.signature !== "string" || !(await verifySignature(d.publicKey, String(b.nonce), b.signature))) {
        throw fail(401, "BAD_SIGNATURE", "The signature doesn't match this device");
      }
      if (d.scope === "peek" && b.scope !== "peek") throw fail(403, "SCOPE_NOT_ALLOWED", "This device key only opens Peek Balance");
      if (b.scope === "peek") {
        const expiresAt = now() + PEEK_TTL;
        return { status: 200, body: { accessToken: sign(d.userId, String(b.deviceId), expiresAt, "peek"), expiresAt: new Date(expiresAt).toISOString() } };
      }
      return { status: 200, body: issue(d.userId, String(b.deviceId)) };
    }],
    ["auth", "POST", /^\/auth\/refresh$/, (_req, b) => {
      const key = String(b.refreshToken ?? "");
      const row = refreshTokens.get(key);
      refreshTokens.delete(key);
      const d = row && tx((s) => s.devices[row.deviceId]);
      if (!row || !d || row.expiresAt < now()) throw fail(401, "REFRESH_EXPIRED", "The session ended. Sign in again");
      return { status: 200, body: issue(d.userId, row.deviceId) };
    }],
    ["account", "GET", /^\/accounts\/summary$/, async (req) => {
      const uid = userId(req.headers);
      const body: Record<string, unknown> = tx((s) => {
        const accounts = s.accounts
          .filter((a) => a.userId === uid)
          .sort((a, b) => a.id.localeCompare(b.id))
          .map((a) => {
            const held = Object.values(s.holds).filter((h) => h.accountId === a.id && h.status === "HELD").reduce((n, h) => n + h.amount, 0);
            return { id: a.id, name: a.name, numberMasked: a.numberMasked, balance: display(a.balance), available: plain(a.balance - held), currency: a.currency };
          });
        return {
          displayName: USER.displayName.toUpperCase(),
          accounts,
          paynowDailyLimit: plain(DAILY_LIMIT),
          paynowUsedToday: plain(s.usage[sgDay(now())] ?? 0),
        };
      });
      const etag = await etagOf(body);
      const headers = { ETag: etag, "Cache-Control": "no-cache" };
      const match = req.headers.get("If-None-Match");
      if (match && match.replace(/W\//g, "").split(/\s*,\s*/).includes(etag)) return { status: 304, headers };
      return { status: 200, headers, body: { ...body, updatedAt: new Date(now()).toISOString() } };
    }],
    ["account", "GET", /^\/accounts\/peek$/, (req) => {
      const uid = userId(req.headers, "peek");
      return tx((s) => {
        const acc = s.accounts.filter((a) => a.userId === uid).sort((a, b) => a.id.localeCompare(b.id))[0];
        if (!acc) throw fail(404, "ACCOUNT_NOT_FOUND", "No deposit account");
        const since = now() - 30 * DAY;
        const transactions = s.transactions
          .filter((t) => t.accountId === acc.id && t.postedAt >= since)
          .sort((a, b) => b.postedAt - a.postedAt)
          .slice(0, 3)
          .map((t) => ({ type: t.type, date: sgDay(t.postedAt), amount: plain(t.amount) }));
        return {
          status: 200,
          headers: { "Cache-Control": "no-store" },
          body: { balance: display(acc.balance), currency: acc.currency, asOf: new Date(now()).toISOString(), transactions },
        };
      });
    }],
    ["lookup", "GET", /^\/paynow\/lookup$/, async (req) => {
      const uid = userId(req.headers);
      const window = (lookupCalls.get(uid) ?? []).filter((t) => t > now() - 60_000);
      lookupCalls.set(uid, window);
      if (window.length >= LOOKUP_RATE) throw fail(429, "RATE_LIMITED", "Too many lookups. Try again in a minute");
      window.push(now());
      const type = req.query.get("type");
      const value = req.query.get("value");
      if (type == null || value == null) throw fail(400, "BAD_REQUEST", "type and value are required");
      const t = type.toUpperCase();
      const v = value.trim().toUpperCase();
      validProxy(t, v);
      const key = `${t}:${v}`;
      const hit = lookupCache.get(key);
      if (hit && hit.expiresAt > now()) return { status: 200, body: hit.proxy };
      const proxy = await resolve(t, v);
      lookupCache.set(key, { proxy, expiresAt: now() + LOOKUP_CACHE });
      return { status: 200, body: proxy };
    }],
    ["payment", "POST", /^\/payments\/paynow$/, async (req, b) => {
      const uid = userId(req.headers);
      const key = req.headers.get("Idempotency-Key");
      if (!key || !key.trim() || key.length > 64) throw fail(400, "MISSING_IDEMPOTENCY_KEY", "Send an Idempotency-Key header");
      const accepted = (p: Payment): BankResponse => {
        if (p.userId !== uid) throw fail(409, "IDEMPOTENCY_KEY_REUSED", "This Idempotency-Key belongs to another payment");
        return { status: 202, body: { paymentId: p.id, status: p.status } };
      };
      const byKey = () => tx((s) => Object.values(s.payments).find((p) => p.key === key));
      const existing = byKey();
      if (existing) return accepted(existing);

      const type = typeof b.proxyType === "string" ? b.proxyType.toUpperCase() : null;
      const value = typeof b.proxyValue === "string" ? b.proxyValue.trim().toUpperCase() : null;
      validProxy(type, value);
      if (b.fromAccountId == null) throw fail(400, "BAD_REQUEST", "fromAccountId is required");
      const amount = cents(b.amount);
      if (amount == null) throw fail(400, "INVALID_AMOUNT", "Amount must be positive with at most 2 decimals");
      if (b.currency != null && b.currency !== "SGD") throw fail(400, "UNSUPPORTED_CURRENCY", "Only SGD is supported");

      let proxy: Proxy;
      try {
        proxy = await resolve(type!, value!);
      } catch (e) {
        if (e instanceof ApiError && e.code === "PROXY_NOT_FOUND") throw fail(422, "PROXY_NOT_FOUND", e.message);
        throw e;
      }

      return tx((s) => {
        const again = Object.values(s.payments).find((p) => p.key === key);
        if (again) return accepted(again);
        const acc = s.accounts.find((a) => a.id === b.fromAccountId && a.userId === uid);
        if (!acc) throw fail(404, "ACCOUNT_NOT_FOUND", "No such account");
        const held = Object.values(s.holds).filter((h) => h.accountId === acc.id && h.status === "HELD").reduce((n, h) => n + h.amount, 0);
        if (amount > acc.balance - held) throw fail(422, "INSUFFICIENT_FUNDS", "Not enough in this account");
        const day = sgDay(now());
        if ((s.usage[day] ?? 0) + amount > DAILY_LIMIT) throw fail(422, "LIMIT_EXCEEDED", "Over your PayNow daily limit");
        s.usage[day] = (s.usage[day] ?? 0) + amount;
        const id = crypto.randomUUID();
        s.holds[id] = { accountId: acc.id, amount, status: "HELD" };
        s.payments[id] = {
          id, key, userId: uid, fromAccountId: acc.id, proxyType: type!, proxyValue: value!,
          maskedName: proxy.maskedName, bankCode: proxy.bankCode, amount,
          reference: typeof b.reference === "string" ? b.reference : null,
          status: "PENDING", reason: null, createdAt: now(), settlesAt: now() + deps.settleMs, settledAt: null,
        };
        return { status: 202, body: { paymentId: id, status: "PENDING" } };
      });
    }],
    ["payment", "GET", /^\/payments\/([^/]+)$/, async (req, _b, [id]) => {
      const uid = userId(req.headers);
      const wait = Math.min(Math.max(Number(req.query.get("waitMs") ?? 0) || 0, 0), MAX_WAIT);
      const deadline = now() + wait;
      for (;;) {
        const p = tx((s) => s.payments[id]);
        if (!p || p.userId !== uid) throw fail(404, "PAYMENT_NOT_FOUND", "No such payment");
        if (p.status !== "PENDING" || now() >= deadline) {
          return {
            status: 200,
            body: {
              paymentId: p.id, status: p.status, ...(p.reason ? { reason: p.reason } : {}),
              amount: plain(p.amount), maskedName: p.maskedName,
              ...(p.settledAt ? { settledAt: new Date(p.settledAt).toISOString() } : {}),
            },
          };
        }
        await deps.sleep(Math.min(100, Math.max(1, Math.min(p.settlesAt, deadline) - now())));
      }
    }],
  ];

  return {
    async handle(req: BankRequest): Promise<BankResponse> {
      try {
        const matches = routes.filter(([svc, , re]) => svc === req.service && re.test(req.path));
        if (!matches.length) throw fail(404, "NOT_FOUND", `No endpoint ${req.path}`);
        const route = matches.find(([, m]) => m === req.method);
        if (!route) throw fail(405, "METHOD_NOT_ALLOWED", `Request method '${req.method}' is not supported`);
        const params = route[2].exec(req.path)!.slice(1).map(decodeURIComponent);
        const body = (req.body && typeof req.body === "object" ? req.body : {}) as Body;
        return await route[3](req, body, params);
      } catch (e) {
        if (e instanceof ApiError) return { status: e.status, body: { code: e.code, message: e.message } };
        return { status: 500, body: { code: "INTERNAL", message: "Something went wrong" } };
      }
    },
  };
}

export type Bank = ReturnType<typeof createBank>;
