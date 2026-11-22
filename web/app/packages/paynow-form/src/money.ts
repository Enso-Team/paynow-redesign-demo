export function toCents(value: string | undefined | null): number | null {
  if (value == null) return null;
  const clean = String(value).replace(/,/g, "").trim();
  if (!/^\d+(\.\d{0,2})?$/.test(clean)) return null;
  const [whole, frac = ""] = clean.split(".");
  return Number(whole) * 100 + Number((frac + "00").slice(0, 2));
}

export function fromCents(cents: number): string {
  const whole = Math.floor(cents / 100);
  const frac = String(cents % 100).padStart(2, "0");
  return `${whole}.${frac}`;
}

export function display(cents: number): string {
  const whole = Math.floor(cents / 100).toLocaleString("en-SG");
  return `${whole}.${String(cents % 100).padStart(2, "0")}`;
}

export function isAmountInput(value: string): boolean {
  return /^\d{0,7}(\.\d{0,2})?$/.test(value);
}

export function uuid(): string {
  const c = globalThis.crypto;
  if (c && typeof c.randomUUID === "function") return c.randomUUID();
  const b = new Uint8Array(16);
  c.getRandomValues(b);
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  const h = Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

export function maskProxy(type: "MOBILE" | "UEN", value: string): string {
  if (type === "MOBILE") return `MOBILE, +65 •••• ${value.slice(-4)}`;
  return `UEN •••••${value.slice(-4)}`;
}

export function initials(name: string): string {
  const words = name
    .split(/\s+/)
    .map((w) => w.replace(/[^A-Za-z]/g, ""))
    .filter(Boolean);
  return ((words[0]?.[0] ?? "") + (words[1]?.[0] ?? "")).toUpperCase() || "PN";
}
