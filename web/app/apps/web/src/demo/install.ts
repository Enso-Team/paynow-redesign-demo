import { createBank, type Bank } from "./bank";
import { MEASURED, networkMs } from "./latency";

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/**
 * The demo build answers every /api/<service>/... call in this tab, from the visitor's own localStorage.
 * Each call waits its measured time first. Nothing leaves the browser.
 */
/** Services the e2e run takes offline, so the demo shows a failed refresh the way a dropped network does. */
export const offline = new Set<string>();

export function installDemoBackend(): Bank {
  const bank = createBank({ storage: localStorage, now: () => Date.now(), sleep, settleMs: MEASURED["fast.settle"] });
  const realFetch = window.fetch.bind(window);
  window.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
    const req = new Request(input, init);
    const url = new URL(req.url, location.href);
    const m = url.origin === location.origin ? /^\/api\/([a-z]+)(\/.*)$/.exec(url.pathname) : null;
    if (!m) return realFetch(input, init);
    const [, service, path] = m;
    if (offline.has(service)) throw new TypeError("Failed to fetch");
    const text = await req.text();
    let body: unknown = null;
    try {
      body = text ? JSON.parse(text) : null;
    } catch {
      return new Response(JSON.stringify({ code: "BAD_REQUEST", message: "Body isn't JSON" }), { status: 400 });
    }
    await sleep(networkMs(req.method, path));
    const res = await bank.handle({ service, method: req.method, path, query: url.searchParams, headers: req.headers, body });
    const headers = new Headers(res.headers);
    if (res.body !== undefined) headers.set("Content-Type", "application/json");
    return new Response(res.body === undefined || res.status === 304 ? null : JSON.stringify(res.body), { status: res.status, headers });
  };
  return bank;
}

Object.assign(window, { __dbsDemoNetwork: { offline } });
