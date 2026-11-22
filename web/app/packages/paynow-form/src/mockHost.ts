import type { PaynowHost, PaynowInit } from "./bridge";

const directory: Record<string, { maskedName: string; bankCode: string; latency?: number }> = {
  "MOBILE:91234567": { maskedName: "TAN ** **NG", bankCode: "OCBC" },
  "MOBILE:98765432": { maskedName: "LIM ** **AH", bankCode: "UOB" },
  "UEN:201912345K": { maskedName: "KOPI **** PTE LTD", bankCode: "DBS" },
  "MOBILE:90000001": { maskedName: "SLOW ** **ER", bankCode: "OCBC", latency: 3000 },
  "MOBILE:90000002": { maskedName: "REJ ** **ED", bankCode: "REJECT" },
};

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

export function installMockHost() {
  const payments = new Map<string, { id: string; bank: string; amount: string; name: string }>();
  const host: PaynowHost = {
    async api(service, path, init) {
      await wait(250);
      const url = new URL(path, "http://mock");
      if (service === "account") {
        return {
          status: 200,
          body: {
            displayName: "ALEX TAN",
            accounts: [
              { id: "acc-1", name: "Everyday Savings", numberMasked: "•••• 1234", balance: "2,345.67", available: "2345.67", currency: "SGD" },
              { id: "acc-2", name: "Bonus Savings", numberMasked: "•••• 5678", balance: "10,120.00", available: "10120.00", currency: "SGD" },
            ],
            paynowDailyLimit: "5000.00",
            paynowUsedToday: "0.00",
          },
        };
      }
      if (service === "lookup") {
        const key = `${url.searchParams.get("type")}:${url.searchParams.get("value")}`;
        const hit = directory[key];
        if (!hit) return { status: 404, body: { code: "PROXY_NOT_FOUND", message: "Not found" } };
        if (hit.latency && hit.latency > 2000) {
          await wait(2000);
          return { status: 504, body: { code: "DIRECTORY_TIMEOUT", message: "Timed out" } };
        }
        return { status: 200, body: { proxyType: url.searchParams.get("type"), proxyValue: url.searchParams.get("value"), ...hit } };
      }
      if (url.pathname === "/payments/paynow") {
        const key = init?.headers?.["Idempotency-Key"] ?? "";
        const b = init?.body as { proxyType: string; proxyValue: string; amount: string };
        const hit = directory[`${b.proxyType}:${b.proxyValue}`];
        if (!payments.has(key)) payments.set(key, { id: "pay-" + key.slice(0, 8), bank: hit?.bankCode ?? "", amount: b.amount, name: hit?.maskedName ?? "" });
        return { status: 202, body: { paymentId: payments.get(key)!.id, status: "PENDING" } };
      }
      const p = [...payments.values()].find((x) => url.pathname.endsWith(x.id));
      await wait(600);
      return {
        status: 200,
        body: { paymentId: p?.id, status: p?.bank === "REJECT" ? "REJECTED" : "SETTLED", amount: p?.amount, maskedName: p?.name },
      };
    },
    done(result) {
      document.title = `done:${result.status}`;
      console.log("paynow done", result);
    },
    close() {
      console.log("paynow close");
    },
  };
  window.paynowHost = host;
  const params = new URLSearchParams(location.search);
  if (!window.__PAYNOW_INIT__) {
    const init: PaynowInit = params.get("qr")
      ? { proxyType: "MOBILE", proxyValue: "91234567", amount: "12.50", amountEditable: false, source: "qr" }
      : { proxyType: (params.get("type") as "MOBILE" | "UEN") ?? "MOBILE", amountEditable: true, source: "menu" };
    window.__PAYNOW_INIT__ = init;
  }
}
