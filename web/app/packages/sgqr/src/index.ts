export type ProxyType = "MOBILE" | "UEN";

export interface PaynowQR {
  proxyType: ProxyType;
  proxyValue: string;
  amount?: string;
  amountEditable: boolean;
  expiry?: string;
  reference?: string;
  merchantName?: string;
  merchantCity?: string;
}

export type SgqrErrorCode = "NOT_PAYNOW" | "BAD_CRC";

export const NOT_PAYNOW_MESSAGE = "This QR isn't a PayNow code";
export const BAD_CRC_MESSAGE = "This QR code couldn't be read. Try again.";

export class SgqrError extends Error {
  code: SgqrErrorCode;
  constructor(code: SgqrErrorCode) {
    super(code === "BAD_CRC" ? BAD_CRC_MESSAGE : NOT_PAYNOW_MESSAGE);
    this.code = code;
    this.name = "SgqrError";
  }
}

export interface Tlv {
  tag: string;
  value: string;
}

export function parseTlv(input: string): Tlv[] {
  const out: Tlv[] = [];
  let i = 0;
  while (i < input.length) {
    const tag = input.slice(i, i + 2);
    const lenText = input.slice(i + 2, i + 4);
    if (!/^\d\d$/.test(tag) || !/^\d\d$/.test(lenText)) throw new SgqrError("NOT_PAYNOW");
    const len = Number(lenText);
    const value = input.slice(i + 4, i + 4 + len);
    if (value.length !== len) throw new SgqrError("NOT_PAYNOW");
    out.push({ tag, value });
    i += 4 + len;
  }
  return out;
}

export function crc16(input: string): string {
  let crc = 0xffff;
  const bytes = new TextEncoder().encode(input);
  for (const b of bytes) {
    crc ^= b << 8;
    for (let k = 0; k < 8; k++) {
      crc = crc & 0x8000 ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff;
    }
  }
  return crc.toString(16).toUpperCase().padStart(4, "0");
}

function subTags(value: string): Map<string, string> {
  return new Map(parseTlv(value).map((t) => [t.tag, t.value]));
}

export function normalizeMobile(value: string): string {
  const compact = value.replace(/[\s-]/g, "");
  return compact.startsWith("+65") ? compact.slice(3) : compact;
}

export function isValidProxy(type: ProxyType, value: string): boolean {
  if (type === "MOBILE") return /^[89]\d{7}$/.test(value);
  return /^[0-9A-Za-z]{9,10}$/.test(value);
}

export function parseSgqr(raw: string): PaynowQR {
  const input = raw.trim();
  if (!/^000201/.test(input)) throw new SgqrError("NOT_PAYNOW");
  const tags = parseTlv(input);
  const last = tags[tags.length - 1];
  if (!last || last.tag !== "63" || last.value.length !== 4) throw new SgqrError("NOT_PAYNOW");
  if (crc16(input.slice(0, input.length - 4)) !== last.value.toUpperCase()) throw new SgqrError("BAD_CRC");

  let paynow: Map<string, string> | undefined;
  for (const t of tags) {
    const n = Number(t.tag);
    if (n < 26 || n > 51) continue;
    let subs: Map<string, string>;
    try {
      subs = subTags(t.value);
    } catch {
      continue;
    }
    if (subs.get("00")?.toUpperCase() === "SG.PAYNOW") {
      paynow = subs;
      break;
    }
  }
  if (!paynow) throw new SgqrError("NOT_PAYNOW");

  const typeCode = paynow.get("01");
  const rawValue = paynow.get("02");
  if (!rawValue || (typeCode !== "0" && typeCode !== "2")) throw new SgqrError("NOT_PAYNOW");
  const proxyType: ProxyType = typeCode === "0" ? "MOBILE" : "UEN";
  const proxyValue = proxyType === "MOBILE" ? normalizeMobile(rawValue) : rawValue.trim().toUpperCase();

  const top = new Map(tags.map((t) => [t.tag, t.value]));
  const result: PaynowQR = {
    proxyType,
    proxyValue,
    amountEditable: paynow.get("03") !== "0",
  };
  const amount = top.get("54");
  if (amount) result.amount = amount;
  const expiry = paynow.get("04");
  if (expiry) result.expiry = expiry;
  const additional = top.get("62");
  if (additional) {
    try {
      const ref = subTags(additional).get("01");
      if (ref) result.reference = ref;
    } catch {
      /* the bill reference is optional */
    }
  }
  const name = top.get("59");
  if (name) result.merchantName = name;
  const city = top.get("60");
  if (city) result.merchantCity = city;
  if (!result.amount) result.amountEditable = true;
  return result;
}

function tlv(tag: string, value: string): string {
  return tag + String(value.length).padStart(2, "0") + value;
}

export interface BuildOptions {
  proxyType: ProxyType;
  proxyValue: string;
  amount?: string;
  amountEditable?: boolean;
  expiry?: string;
  reference?: string;
  merchantName?: string;
  merchantCity?: string;
}

export function buildPaynowQR(o: BuildOptions): string {
  const account =
    tlv("00", "SG.PAYNOW") +
    tlv("01", o.proxyType === "MOBILE" ? "0" : "2") +
    tlv("02", o.proxyValue) +
    tlv("03", o.amountEditable === false ? "0" : "1") +
    (o.expiry ? tlv("04", o.expiry) : "");
  let s =
    tlv("00", "01") +
    tlv("01", o.amount ? "12" : "11") +
    tlv("26", account) +
    tlv("52", "0000") +
    tlv("53", "702") +
    (o.amount ? tlv("54", o.amount) : "") +
    tlv("58", "SG") +
    tlv("59", o.merchantName ?? "NA") +
    tlv("60", o.merchantCity ?? "Singapore") +
    (o.reference ? tlv("62", tlv("01", o.reference)) : "");
  s += "6304";
  return s + crc16(s);
}
