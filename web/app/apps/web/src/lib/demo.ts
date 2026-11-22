/** True in the public demo build (`pnpm build:demo`), whose backend runs in the browser. */
export const DEMO = import.meta.env.MODE === "demo";

/** A file from public/, under the build's base path (/ for the live demo, /demos/dbs/ for the public one). */
export function asset(path: string): string {
  return import.meta.env.BASE_URL + path.replace(/^\//, "");
}

export const PRIVACY_NOTE = "Demo. Nothing you enter leaves this device. Recent payees stay in this browser until you reset the demo in More.";
export const TIMING_NOTE = "Network times simulated from timings measured in a real banking app.";

/** Wipes everything the demo keeps in this browser and starts over. */
export function resetDemo() {
  for (const key of Object.keys(localStorage)) if (key.startsWith("dbs.")) localStorage.removeItem(key);
  location.reload();
}
