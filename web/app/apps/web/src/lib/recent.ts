import { useSyncExternalStore } from "react";

export interface RecentPayee {
  proxyType: "MOBILE" | "UEN";
  proxyValue: string;
  maskedName: string;
}

export const RECENT_KEY = "dbs.recentPayees";
const MAX = 5;
const listeners = new Set<() => void>();
let cache: { text: string | null; list: RecentPayee[] } = { text: null, list: [] };

function read(): RecentPayee[] {
  const text = localStorage.getItem(RECENT_KEY);
  if (text !== cache.text) {
    let list: RecentPayee[] = [];
    try {
      list = text ? (JSON.parse(text) as RecentPayee[]) : [];
    } catch {
      list = [];
    }
    cache = { text, list };
  }
  return cache.list;
}

function write(list: RecentPayee[]) {
  if (list.length) localStorage.setItem(RECENT_KEY, JSON.stringify(list));
  else localStorage.removeItem(RECENT_KEY);
  listeners.forEach((l) => l());
}

/** Keeps a paid proxy and its masked name on this device, newest first. */
export function addRecentPayee(p: RecentPayee) {
  const rest = read().filter((r) => !(r.proxyType === p.proxyType && r.proxyValue === p.proxyValue));
  write([p, ...rest].slice(0, MAX));
}

export function clearRecentPayees() {
  write([]);
}

export function useRecentPayees(): RecentPayee[] {
  return useSyncExternalStore((l) => {
    listeners.add(l);
    return () => listeners.delete(l);
  }, read);
}
