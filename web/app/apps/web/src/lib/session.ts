import { DEMO } from "./demo";
import { askFaceId } from "./faceid";
import { deviceId, ensureDevice, HttpError, postJson, signNonce } from "./device";

export const IDLE_MS = 5 * 60 * 1000;
const REFRESH_AHEAD_MS = 60 * 1000;

export class FaceIdCancelled extends Error {
  constructor() {
    super("Face ID cancelled");
  }
}

export class SessionEnded extends Error {
  constructor() {
    super("Session ended");
  }
}

interface Tokens {
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
}

function parseExpiry(value: unknown, token: string): number {
  try {
    const payload = JSON.parse(atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
    if (typeof payload.exp === "number") return payload.exp * 1000;
  } catch {
    /* fall back to expiresAt */
  }
  if (typeof value === "number") return value < 1e12 ? value * 1000 : value;
  if (typeof value === "string") {
    const n = Number(value);
    if (Number.isFinite(n)) return n < 1e12 ? n * 1000 : n;
    const t = Date.parse(value);
    if (Number.isFinite(t)) return t;
  }
  return Date.now() + 5 * 60 * 1000;
}

function toTokens(body: unknown): Tokens {
  const b = body as { accessToken: string; refreshToken: string; expiresAt: unknown };
  return { accessToken: b.accessToken, refreshToken: b.refreshToken, expiresAt: parseExpiry(b.expiresAt, b.accessToken) };
}

type Listener = (event: "ended") => void;

/** Owns the session token. Face ID runs only through start() and the one re-check. */
class SessionManager {
  private tokens: Tokens | null = null;
  private lastTouch = Date.now();
  private lapsed = false;
  private journey = "Demo Bank";
  private recheckRun: Promise<void> | null = null;
  private refreshRun: Promise<void> | null = null;
  private listeners = new Set<Listener>();
  now = () => Date.now();

  onEnded(l: Listener) {
    this.listeners.add(l);
    return () => this.listeners.delete(l);
  }

  /** A tap after the idle window still counts as lapsed until Face ID runs again. */
  touch() {
    if (this.tokens && this.now() - this.lastTouch > IDLE_MS) this.lapsed = true;
    this.lastTouch = this.now();
  }

  isIdle() {
    return this.lapsed || this.now() - this.lastTouch > IDLE_MS;
  }

  private fresh(t: Tokens) {
    this.tokens = t;
    this.lapsed = false;
    this.lastTouch = this.now();
  }

  hasSession() {
    return this.tokens !== null;
  }

  /** A journey's one Face ID, with the session fetched behind the animation. */
  async start(label: string): Promise<boolean> {
    this.journey = label;
    const session = this.create().then(
      (t) => ({ ok: true as const, t }),
      (e) => ({ ok: false as const, e }),
    );
    const ok = await askFaceId(label);
    if (!ok) return false;
    const r = await session;
    if (!r.ok) throw r.e;
    this.fresh(r.t);
    return true;
  }

  /** The token for a call. Idle asks Face ID once more, then carries on. */
  async token(opts: { interactive: boolean }): Promise<string> {
    if (!this.tokens) {
      if (!opts.interactive) throw new SessionEnded();
      await this.recheck();
    } else if (this.isIdle()) {
      if (!opts.interactive) throw new SessionEnded();
      await this.recheck();
    } else if (this.tokens.expiresAt - this.now() < REFRESH_AHEAD_MS) {
      try {
        await this.refresh();
      } catch (e) {
        if (!opts.interactive) throw e;
        await this.recheck();
      }
    }
    this.lastTouch = this.now();
    return this.tokens!.accessToken;
  }

  /** The single Face ID re-check, shared by every caller waiting on it. */
  recheck(): Promise<void> {
    this.recheckRun ??= (async () => {
      const session = this.create().then(
        (t) => ({ ok: true as const, t }),
        (e) => ({ ok: false as const, e }),
      );
      const ok = await askFaceId(this.journey);
      if (!ok) throw new FaceIdCancelled();
      const r = await session;
      if (!r.ok) throw r.e;
      this.fresh(r.t);
    })().finally(() => {
      this.recheckRun = null;
    });
    return this.recheckRun;
  }

  refresh(): Promise<void> {
    const current = this.tokens;
    if (!current) return Promise.reject(new SessionEnded());
    this.refreshRun ??= postJson("/api/auth/auth/refresh", { refreshToken: current.refreshToken })
      .then((body) => {
        this.tokens = toTokens(body);
      })
      .finally(() => {
        this.refreshRun = null;
      });
    return this.refreshRun;
  }

  /** Quiet refresh while the app is in use. */
  async keepAlive() {
    if (!this.tokens || this.isIdle()) return;
    if (this.tokens.expiresAt - this.now() < REFRESH_AHEAD_MS * 1.5) {
      await this.refresh().catch(() => undefined);
    }
  }

  end() {
    this.tokens = null;
    this.lapsed = false;
    this.listeners.forEach((l) => l("ended"));
  }

  private async create(): Promise<Tokens> {
    return toTokens(await deviceSession());
  }

  debugExpireAccess() {
    if (this.tokens) this.tokens = { ...this.tokens, accessToken: "expired.invalid.token" };
  }

  debugIdle() {
    this.lastTouch = this.now() - IDLE_MS - 1000;
  }

  get device() {
    return deviceId();
  }
}

export const session = new SessionManager();

/**
 * Proves the device key with a fresh challenge and returns the auth service's token body.
 * `scope: "peek"` asks for the read-only Peek pass, which needs no Face ID.
 */
export async function deviceSession(scope?: "peek", retry = true): Promise<unknown> {
  const id = await ensureDevice();
  try {
    const attested = scope || DEMO ? null : ((await postJson("/api/auth/auth/attest", {
      deviceId: id, platform: "web", osVersion: navigator.platform, appVersion: "demo", signals: [],
    })) as { attestationId: string });
    const { nonce } = (await postJson("/api/auth/auth/challenge", { deviceId: id })) as { nonce: string };
    const signature = await signNonce(nonce);
    return await postJson("/api/auth/auth/session", { deviceId: id, nonce, signature, ...(scope ? { scope } : {}), ...(attested ?? {}) });
  } catch (e) {
    if (retry && e instanceof HttpError && (e.code === "DEVICE_UNKNOWN" || e.status === 404)) {
      await ensureDevice(true);
      return deviceSession(scope, false);
    }
    if (retry && e instanceof HttpError && e.code === "NONCE_EXPIRED") return deviceSession(scope, false);
    throw e;
  }
}
