import { useSyncExternalStore } from "react";
import { api } from "./api";

export interface Account {
  id: string;
  name: string;
  numberMasked: string;
  balance: string;
  available: string;
  currency: string;
}

export interface Summary {
  displayName: string;
  accounts: Account[];
  paynowDailyLimit: string;
  paynowUsedToday: string;
  updatedAt?: string;
}

export interface AccountsState {
  summary: Summary | null;
  etag: string | null;
  lastSuccess: number | null;
  failed: boolean;
  loading: boolean;
}

let state: AccountsState = { summary: null, etag: null, lastSuccess: null, failed: false, loading: false };
const listeners = new Set<() => void>();
const set = (p: Partial<AccountsState>) => {
  state = { ...state, ...p };
  listeners.forEach((l) => l());
};

export function useAccounts(): AccountsState {
  return useSyncExternalStore(
    (l) => {
      listeners.add(l);
      return () => listeners.delete(l);
    },
    () => state,
  );
}

export function resetAccounts() {
  set({ summary: null, etag: null, lastSuccess: null, failed: false, loading: false });
}

let inflight: Promise<void> | null = null;

/** Background refresh keeps the last data on failure and flags it, so Home can say "Updated N min ago". */
export function refreshAccounts(opts: { interactive: boolean }): Promise<void> {
  inflight ??= (async () => {
    set({ loading: !state.summary });
    try {
      const headers: Record<string, string> = {};
      if (state.etag && state.summary) headers["If-None-Match"] = state.etag;
      const r = await api("account", "/accounts/summary", { headers }, { interactive: opts.interactive });
      if (r.status === 304) set({ lastSuccess: Date.now(), failed: false });
      else if (r.status === 200) {
        set({ summary: r.body as Summary, etag: r.headers.get("ETag"), lastSuccess: Date.now(), failed: false });
      } else set({ failed: true });
    } catch {
      set({ failed: true });
    } finally {
      set({ loading: false });
      inflight = null;
    }
  })();
  return inflight;
}

export function totalAvailable(s: Summary): number {
  return s.accounts.reduce((sum, a) => sum + Number(a.available || 0), 0);
}

export function formatMoney(n: number): string {
  return n.toLocaleString("en-SG", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}
