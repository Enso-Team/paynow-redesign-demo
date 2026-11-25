import type { ApiInit, ApiResponse, Service } from "paynow-form/src/bridge";
import { askFaceId } from "./faceid";
import { ensureDevice, postJson, signNonce, safeJson } from "./device";
import { SessionEnded, session } from "./session";

async function send(service: Service, path: string, init: ApiInit, token: string): Promise<ApiResponse & { headers: Headers }> {
  const headers: Record<string, string> = { Authorization: `Bearer ${token}`, ...(init.headers ?? {}) };
  let body: string | undefined;
  if (init.body !== undefined) {
    headers["Content-Type"] = "application/json";
    body = JSON.stringify(init.body);
  }
  const r = await fetch(`/api/${service}${path}`, {
    method: init.method ?? (body ? "POST" : "GET"),
    headers,
    body,
    cache: "no-store",
  });
  const text = await r.text();
  return { status: r.status, body: text ? safeJson(text) : null, headers: r.headers };
}

/** The fraud check at Pay: a second Face ID signs this exact payment, then the call is sent again. */
async function sendOrStepUp(service: Service, path: string, init: ApiInit, token: string) {
  const first = await send(service, path, init, token);
  const code = (first.body as { code?: string } | null)?.code;
  if (first.status !== 403 || code !== "STEP_UP_REQUIRED" || !(await askFaceId("Confirm payment"))) return first;
  const body = init.body as { fromAccountId: string; proxyType: string; proxyValue: string; amount: string };
  const idempotencyKey = init.headers?.["Idempotency-Key"] ?? "";
  const { fromAccountId, proxyType, proxyValue, amount } = body;
  const text = [fromAccountId, proxyType, proxyValue, amount, idempotencyKey].join("|");
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
  const binding = [...hash].map((b) => b.toString(16).padStart(2, "0")).join("");
  const deviceId = await ensureDevice();
  const { nonce } = (await postJson("/api/auth/auth/challenge", { deviceId })) as { nonce: string };
  const r = await fetch("/api/auth/auth/step-up", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      deviceId, nonce, signature: await signNonce(`${nonce}.${binding}`),
      payment: { fromAccountId, proxyType, proxyValue, amount, idempotencyKey },
    }),
  });
  if (!r.ok) return first;
  const { stepUpToken } = (await r.json()) as { stepUpToken: string };
  return send(service, path, { ...init, headers: { ...init.headers, "X-Step-Up-Token": stepUpToken } }, token);
}

/**
 * Calls a service with the session token. A 401 runs the one Face ID re-check and retries;
 * a second 401 ends the session, which sends the user back to the entry screen.
 * Background calls (interactive: false) never ask Face ID.
 */
export async function api(
  service: Service,
  path: string,
  init: ApiInit = {},
  opts: { interactive?: boolean } = {},
): Promise<ApiResponse & { headers: Headers }> {
  const interactive = opts.interactive ?? true;
  const first = await sendOrStepUp(service, path, init, await session.token({ interactive }));
  if (first.status !== 401) return first;
  if (!interactive) throw new SessionEnded();
  await session.recheck();
  const second = await send(service, path, init, await session.token({ interactive }));
  if (second.status === 401) {
    session.end();
    throw new SessionEnded();
  }
  return second;
}
