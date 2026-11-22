import { useMemo, useRef } from "react";
import type { PaynowHost, PaynowInit } from "paynow-form/src/bridge";
import { api } from "../lib/api";
import { refreshAccounts } from "../lib/accounts";
import { session } from "../lib/session";
import { go, setState, type Screen } from "../lib/store";
import { asset, DEMO, PRIVACY_NOTE } from "../lib/demo";
import { addRecentPayee, type RecentPayee } from "../lib/recent";

/** Hosts the same paynow-form bundle iOS loads, in an iframe, behind window.paynowHost. */
export function FormHost({ init, back }: { init: PaynowInit; back: Screen }) {
  const frame = useRef<HTMLIFrameElement>(null);
  /** Each submitted payment's proxy, so a settled one can join Recent payees. */
  const proxies = useRef(new Map<string, Omit<RecentPayee, "maskedName">>());

  const host = useMemo<PaynowHost>(
    () => ({
      async api(service, path, req) {
        const r = await api(service, path, req ?? {});
        const sent = req?.body as { proxyType?: RecentPayee["proxyType"]; proxyValue?: string } | undefined;
        const paymentId = (r.body as { paymentId?: string } | null)?.paymentId;
        if (service === "payment" && path === "/payments/paynow" && paymentId && sent?.proxyType && sent.proxyValue) {
          proxies.current.set(paymentId, { proxyType: sent.proxyType, proxyValue: sent.proxyValue });
        }
        return { status: r.status, body: r.body };
      },
      done(result) {
        void refreshAccounts({ interactive: false });
        const proxy = proxies.current.get(result.paymentId);
        if (result.status === "SETTLED" && proxy) addRecentPayee({ ...proxy, maskedName: result.maskedName });
        if (result.status === "SETTLED") go({ name: "sent", result });
        else {
          setState({ tab: "home" });
          go({ name: "tabs" });
        }
      },
      close() {
        go(back);
      },
    }),
    [back],
  );

  const onLoad = () => {
    const w = frame.current?.contentWindow;
    if (!w) return;
    w.paynowHost = host;
    w.addEventListener("pointerdown", () => session.touch(), true);
    w.addEventListener("keydown", () => session.touch(), true);
    w.paynowForm?.open(init);
  };

  return (
    <div className={DEMO ? "form-host form-host-demo" : "form-host"}>
      <iframe
        ref={frame}
        title="PayNow Transfer"
        src={asset("paynow-form/index.html")}
        onLoad={onLoad}
        data-testid="paynow-frame"
      />
      {DEMO && (
        <div className="demo-note demo-note-form" data-testid="privacy-note">
          {PRIVACY_NOTE}
        </div>
      )}
    </div>
  );
}
