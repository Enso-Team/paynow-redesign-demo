import { useSyncExternalStore } from "react";
import type { PaynowInit, PaynowResult } from "paynow-form/src/bridge";

export type TabId = "home" | "pay" | "wealth" | "apply" | "more";

export type Screen =
  | { name: "entry" }
  | { name: "tabs" }
  | { name: "scanner"; back: Screen }
  | { name: "paynowMenu"; back: Screen }
  | { name: "form"; init: PaynowInit; back: Screen }
  | { name: "sent"; result: PaynowResult }
  | { name: "placeholder"; title: string; back: Screen }
  | { name: "token" };

export interface FaceIdRequest {
  label: string;
  resolve: (ok: boolean) => void;
}

export interface State {
  screen: Screen;
  tab: TabId;
  toast: { id: number; text: string } | null;
  faceId: FaceIdRequest | null;
  signedIn: boolean;
}

let state: State = {
  screen: { name: "entry" },
  tab: "home",
  toast: null,
  faceId: null,
  signedIn: false,
};
const listeners = new Set<() => void>();

export function getState(): State {
  return state;
}

export function setState(patch: Partial<State> | ((s: State) => Partial<State>)) {
  const p = typeof patch === "function" ? patch(state) : patch;
  state = { ...state, ...p };
  listeners.forEach((l) => l());
}

export function subscribe(l: () => void) {
  listeners.add(l);
  return () => listeners.delete(l);
}

export function useStore<T>(select: (s: State) => T): T {
  return useSyncExternalStore(subscribe, () => select(state));
}

export function go(screen: Screen) {
  setState({ screen, toast: null });
}

let toastId = 0;
export function toast(text: string, ms = 2600) {
  const id = ++toastId;
  setState({ toast: { id, text } });
  setTimeout(() => {
    if (state.toast?.id === id) setState({ toast: null });
  }, ms);
}
