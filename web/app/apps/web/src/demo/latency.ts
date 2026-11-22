import measured from "@latency/measured.json";

/** The shared table in mockup/latency/measured.json, which the services' measured profile reads too. */
export const MEASURED: Record<string, number> = Object.fromEntries(
  Object.entries(measured).filter((e): e is [string, number] => typeof e[1] === "number"),
);

/** The same endpoints the services' MeasuredLatency filter delays. */
const ENDPOINTS: Record<string, string> = {
  "POST /auth/session": "auth.session",
  "POST /auth/refresh": "auth.refresh",
  "GET /accounts/summary": "account.summary",
  "GET /accounts/peek": "account.peek",
  "GET /paynow/lookup": "lookup",
  "POST /payments/paynow": "payment.submit",
};

export function networkMs(method: string, path: string): number {
  const key = ENDPOINTS[`${method} ${path}`];
  return key ? MEASURED[key] : 0;
}
