import type { ApiInit, ApiResponse, Service } from "paynow-form/src/bridge";
import { safeJson } from "./device";
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
  const first = await send(service, path, init, await session.token({ interactive }));
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
