import { p1363ToDer, toBase64 } from "./der";

const KEY = "dbs.device.privateKey";
const ID = "dbs.device.id";

export const DEMO_USER = { name: "Alex Tan", username: "alextan", otp: "123456" };

export class HttpError extends Error {
  status: number;
  code?: string;
  constructor(status: number, code?: string, message?: string) {
    super(message ?? code ?? `HTTP ${status}`);
    this.status = status;
    this.code = code;
  }
}

export async function postJson(url: string, body: unknown): Promise<unknown> {
  const r = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const text = await r.text();
  const json = text ? safeJson(text) : null;
  if (!r.ok) {
    const err = json as { code?: string; message?: string } | null;
    throw new HttpError(r.status, err?.code, err?.message);
  }
  return json;
}

export function safeJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

export function deviceId(): string | null {
  return localStorage.getItem(ID);
}

let binding: Promise<string> | null = null;

/** Silent first-run binding: a P-256 key in localStorage, registered with POST /auth/devices. */
export function ensureDevice(force = false): Promise<string> {
  const existing = deviceId();
  if (!force && existing && localStorage.getItem(KEY)) return Promise.resolve(existing);
  binding ??= bind().finally(() => {
    binding = null;
  });
  return binding;
}

async function bind(): Promise<string> {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const raw = new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey));
  const jwk = await crypto.subtle.exportKey("jwk", pair.privateKey);
  const res = (await postJson("/api/auth/auth/devices", {
    username: DEMO_USER.username,
    otp: DEMO_USER.otp,
    deviceName: `Web demo · ${navigator.platform || "browser"}`,
    publicKey: toBase64(raw),
  })) as { deviceId: string; userId: string };
  localStorage.setItem(KEY, JSON.stringify(jwk));
  localStorage.setItem(ID, String(res.deviceId));
  return String(res.deviceId);
}

export async function signNonce(nonce: string): Promise<string> {
  const jwk = JSON.parse(localStorage.getItem(KEY) ?? "null");
  if (!jwk) throw new Error("No device key");
  const key = await crypto.subtle.importKey("jwk", jwk, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const sig = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(nonce)),
  );
  return toBase64(p1363ToDer(sig));
}
