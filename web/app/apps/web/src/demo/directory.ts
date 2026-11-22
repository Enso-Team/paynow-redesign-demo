/**
 * The mock PayNow directory, ported from services/mock-directory DirectoryController.java.
 * Seeded proxies answer as seeded. Any other well-formed proxy gets the same made-up name the Java service gives it.
 */
export interface Proxy {
  proxyType: string;
  proxyValue: string;
  maskedName: string;
  bankCode: string;
}

export const SEEDED: Record<string, { maskedName: string; bankCode: string; latencyMs: number }> = {
  "MOBILE:91234567": { maskedName: "TAN ** **NG", bankCode: "OCBC", latencyMs: 0 },
  "MOBILE:98765432": { maskedName: "LIM ** **AH", bankCode: "UOB", latencyMs: 0 },
  "UEN:201912345K": { maskedName: "KOPI **** PTE LTD", bankCode: "DBS", latencyMs: 0 },
  "MOBILE:90000001": { maskedName: "SLOW ** **ER", bankCode: "OCBC", latencyMs: 3000 },
  "MOBILE:90000002": { maskedName: "REJ ** **ED", bankCode: "REJECT", latencyMs: 0 },
};

const SURNAMES = ["TAN", "LIM", "LEE", "NG", "ONG", "WONG", "GOH", "CHUA", "CHAN", "KOH", "TEO", "ANG", "YEO", "TAY", "HO", "LOW", "TOH", "SIM", "CHONG", "CHIA"];
const COMPANY_WORDS = ["KOPI", "MAKAN", "LUCKY", "GOLDEN", "SUNRISE", "HAPPY", "MARINA", "ORCHID"];
const BANKS = ["DBS", "OCBC", "UOB"];
const LETTERS = "ABCDEFGHIJKLMNOPRSTUWY";

/** Java's String.hashCode: s[0]*31^(n-1) + … + s[n-1] in 32-bit signed arithmetic. */
export function javaHash(s: string): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (Math.imul(h, 31) + s.charCodeAt(i)) | 0;
  return h;
}

/** The made-up answer for a proxy that isn't seeded, or null for 404. Mobiles starting 8000000 stay unregistered. */
export function madeUp(type: string, value: string): Proxy | null {
  const mobile = type === "MOBILE" && /^[89]\d{7}$/.test(value) && !value.startsWith("8000000");
  const uen = type === "UEN" && /^[0-9A-Z]{9,10}$/.test(value);
  if (!mobile && !uen) return null;
  const h = Math.abs(javaHash(value));
  const div = (n: number) => Math.floor(h / n);
  const maskedName = mobile
    ? `${SURNAMES[h % SURNAMES.length]} ** **${LETTERS[div(7) % LETTERS.length]}${LETTERS[div(131) % LETTERS.length]}`
    : `${COMPANY_WORDS[h % COMPANY_WORDS.length]} **** PTE LTD`;
  return { proxyType: type, proxyValue: value, maskedName, bankCode: BANKS[div(17) % BANKS.length] };
}

/** GET /directory/proxies/{type}/{value}: the proxy and how long the directory takes to answer, or null for 404. */
export function findProxy(type: string, value: string): { proxy: Proxy; latencyMs: number } | null {
  const t = type.toUpperCase();
  const v = value.toUpperCase();
  const seeded = SEEDED[`${t}:${v}`];
  if (seeded) return { proxy: { proxyType: t, proxyValue: v, maskedName: seeded.maskedName, bankCode: seeded.bankCode }, latencyMs: seeded.latencyMs };
  const proxy = madeUp(t, v);
  return proxy ? { proxy, latencyMs: 0 } : null;
}
