import { safeJson } from "./device";
import { deviceSession } from "./session";

export interface PeekTransaction {
  type: string;
  date: string;
  amount: string;
}

export interface PeekBalance {
  balance: string;
  currency: string;
  asOf: string;
  transactions: PeekTransaction[];
}

export const PEEK_CACHE_MS = 60_000;

/** Stretches the Peek animation for screenshots. 1 is real time. */
export const peekTiming = { scale: 1 };
const PASS_MARGIN_MS = 5_000;

interface Pass {
  token: string;
  expiresAt: number;
}

export interface PeekDeps {
  /** A fresh read-only pass from the device key. Never asks Face ID. */
  getPass: () => Promise<Pass>;
  /** GET /accounts/peek with the pass. */
  get: (token: string) => Promise<{ status: number; body: unknown }>;
  now: () => number;
}

/** Peek Balance data: a narrow read-only pass, and the last result kept for a minute so a repeat hold is instant. */
export function createPeek(deps: PeekDeps) {
  let pass: Pass | null = null;
  let cached: { data: PeekBalance; at: number } | null = null;
  let inflight: Promise<PeekBalance> | null = null;

  const token = async (renew: boolean) => {
    if (renew || !pass || pass.expiresAt - deps.now() < PASS_MARGIN_MS) pass = await deps.getPass();
    return pass.token;
  };

  const fetchOnce = async (): Promise<PeekBalance> => {
    let r = await deps.get(await token(false));
    if (r.status === 401) r = await deps.get(await token(true));
    if (r.status !== 200) throw new Error(`Peek failed (${r.status})`);
    const data = r.body as PeekBalance;
    cached = { data, at: deps.now() };
    return data;
  };

  return {
    cached(): PeekBalance | null {
      return cached && deps.now() - cached.at < PEEK_CACHE_MS ? cached.data : null;
    },
    load(): Promise<PeekBalance> {
      const hit = this.cached();
      if (hit) return Promise.resolve(hit);
      inflight ??= fetchOnce().finally(() => {
        inflight = null;
      });
      return inflight;
    },
  };
}

function expiry(body: { accessToken: string; expiresAt?: unknown }): number {
  if (typeof body.expiresAt === "string") {
    const t = Date.parse(body.expiresAt);
    if (Number.isFinite(t)) return t;
  }
  if (typeof body.expiresAt === "number") return body.expiresAt < 1e12 ? body.expiresAt * 1000 : body.expiresAt;
  return Date.now() + 30_000;
}

export const peek = createPeek({
  getPass: async () => {
    const body = (await deviceSession("peek")) as { accessToken: string; expiresAt?: unknown };
    return { token: body.accessToken, expiresAt: expiry(body) };
  },
  get: async (token) => {
    const r = await fetch("/api/account/accounts/peek", { headers: { Authorization: `Bearer ${token}` }, cache: "no-store" });
    const text = await r.text();
    return { status: r.status, body: text ? safeJson(text) : null };
  },
  now: () => Date.now(),
});

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** "20 Nov 2026, 5:32 PM" */
export function formatAsOf(iso: string): string {
  const d = new Date(iso);
  const h = d.getHours() % 12 || 12;
  const ampm = d.getHours() < 12 ? "AM" : "PM";
  return `${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}, ${h}:${String(d.getMinutes()).padStart(2, "0")} ${ampm}`;
}

/** "2026-11-19" → "19 Nov" */
export function formatDay(date: string): string {
  const [, m, d] = date.split("-").map(Number);
  return `${d} ${MONTHS[m - 1]}`;
}

/** "-12.50" → "-12.50", "500" → "+500.00", with thousands separators. */
export function formatSigned(amount: string): string {
  const n = Number(amount);
  const abs = Math.abs(n).toLocaleString("en-SG", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  return `${n < 0 ? "-" : "+"}${abs}`;
}
