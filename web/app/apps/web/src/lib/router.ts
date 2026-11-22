import { parseSgqr, SgqrError } from "sgqr";
import type { PaynowInit } from "paynow-form/src/bridge";
import { getState, go, setState, toast, type Screen } from "./store";
import { FaceIdCancelled, session } from "./session";
import { refreshAccounts, resetAccounts } from "./accounts";

export type Intent =
  | { kind: "login" }
  | { kind: "scanAndPay" }
  | { kind: "payNow" }
  | { kind: "payQR"; payload: string }
  | { kind: "overseas" }
  | { kind: "apply" };

const JOURNEY: Partial<Record<Intent["kind"], string>> = {
  login: "Log in",
  scanAndPay: "Scan & Pay",
  payNow: "PayNow",
};

let pending: Intent | null = null;

export function pendingIntent() {
  return pending;
}

function here(): Screen {
  return getState().screen;
}

/** Every tap lands here. Journeys that need data ask Face ID once, then go straight to their screen. */
export async function dispatch(intent: Intent): Promise<void> {
  if (pending) return;
  pending = intent;
  try {
    const label = JOURNEY[intent.kind];
    const fromSignedIn =
      here().name !== "entry" && getState().signedIn && session.hasSession() && !session.isIdle();
    if (label && !fromSignedIn) {
      let ok = false;
      let unreachable = false;
      try {
        ok = await session.start(label);
      } catch {
        unreachable = true;
      }
      if (!ok) {
        pending = null;
        if (!getState().signedIn) go({ name: "entry" });
        if (unreachable) toast("Can't reach Demo Bank right now. Try again.");
        return;
      }
      setState({ signedIn: true });
      void refreshAccounts({ interactive: false });
    }
    const held = pending ?? intent;
    pending = null;
    land(held);
  } finally {
    pending = null;
  }
}

function land(intent: Intent) {
  const back = here();
  switch (intent.kind) {
    case "login":
      setState({ tab: "home" });
      go({ name: "tabs" });
      return;
    case "scanAndPay":
      go({ name: "scanner", back });
      return;
    case "payNow":
      go({ name: "paynowMenu", back });
      return;
    case "payQR":
      openQr(intent.payload);
      return;
    case "overseas":
      go({ name: "placeholder", title: "Overseas Transfer", back });
      return;
    case "apply":
      go({ name: "placeholder", title: "Apply & More Services", back });
      return;
  }
}

/** Decodes a scanned payload. Returns the error text for a code that isn't PayNow, so the scanner keeps going. */
export function qrToInit(payload: string): PaynowInit | string {
  try {
    const qr = parseSgqr(payload);
    return {
      proxyType: qr.proxyType,
      proxyValue: qr.proxyValue,
      amount: qr.amount,
      amountEditable: qr.amountEditable,
      reference: qr.reference,
      source: "qr",
    };
  } catch (e) {
    return e instanceof SgqrError ? e.message : "This QR isn't a PayNow code";
  }
}

function openQr(payload: string) {
  const init = qrToInit(payload);
  if (typeof init === "string") {
    toast(init);
    return;
  }
  go({ name: "form", init, back: here() });
}

export function openMenuForm(proxyType: "MOBILE" | "UEN") {
  go({ name: "form", init: { proxyType, amountEditable: true, source: "menu" }, back: here() });
}

export function signOut() {
  session.end();
}

session.onEnded(() => {
  resetAccounts();
  setState({ signedIn: false, tab: "home", faceId: null });
  go({ name: "entry" });
});

export { FaceIdCancelled };
