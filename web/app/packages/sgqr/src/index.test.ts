import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import {
  buildPaynowQR, crc16, isValidProxy, normalizeMobile, parseSgqr, parseTlv, SgqrError, NOT_PAYNOW_MESSAGE,
} from "./index";

const sample = (name: string) => readFileSync(fileURLToPath(new URL(`../samples/${name}.txt`, import.meta.url)), "utf8").trim();

describe("crc16", () => {
  it("matches the CCITT-FALSE check value", () => {
    expect(crc16("123456789")).toBe("29B1");
  });
  it("pads to four hex digits", () => {
    expect(crc16("")).toBe("FFFF");
  });
});

describe("parseTlv", () => {
  it("splits tags", () => {
    expect(parseTlv("000201010211")).toEqual([
      { tag: "00", value: "01" },
      { tag: "01", value: "11" },
    ]);
  });
  it("rejects a truncated value", () => {
    expect(() => parseTlv("0005abc")).toThrow(SgqrError);
  });
});

describe("parseSgqr", () => {
  it("reads the mobile sample at SGD 12.50 and strips +65", () => {
    const qr = parseSgqr(sample("mobile-91234567-12.50"));
    expect(qr).toMatchObject({
      proxyType: "MOBILE",
      proxyValue: "91234567",
      amount: "12.50",
      amountEditable: false,
      expiry: "20301231",
      reference: "INV-2041",
    });
  });

  it("reads the UEN sample with an editable amount", () => {
    const qr = parseSgqr(sample("uen-201912345K-editable"));
    expect(qr.proxyType).toBe("UEN");
    expect(qr.proxyValue).toBe("201912345K");
    expect(qr.amountEditable).toBe(true);
    expect(qr.amount).toBeUndefined();
  });

  it("rejects a NETS-only SGQR as not PayNow", () => {
    expect(() => parseSgqr(sample("not-paynow-nets"))).toThrow(NOT_PAYNOW_MESSAGE);
  });

  it("rejects plain text and URLs as not PayNow", () => {
    for (const s of ["hello", "https://example.com", ""]) {
      try {
        parseSgqr(s);
        throw new Error("expected failure");
      } catch (e) {
        expect(e).toBeInstanceOf(SgqrError);
        expect((e as SgqrError).code).toBe("NOT_PAYNOW");
        expect((e as Error).message).toBe("This QR isn't a PayNow code");
      }
    }
  });

  it("fails the CRC when a byte changes", () => {
    const raw = sample("mobile-91234567-12.50").replace("12.50", "92.50");
    try {
      parseSgqr(raw);
      throw new Error("expected failure");
    } catch (e) {
      expect((e as SgqrError).code).toBe("BAD_CRC");
    }
  });

  it("accepts a lowercase CRC", () => {
    const raw = sample("uen-201912345K-editable");
    const lower = raw.slice(0, -4) + raw.slice(-4).toLowerCase();
    expect(parseSgqr(lower).proxyValue).toBe("201912345K");
  });

  it("finds PayNow in any merchant template from 26 to 51", () => {
    const raw = buildPaynowQR({ proxyType: "MOBILE", proxyValue: "98765432" }).replace("2638", "5138");
    const body = raw.slice(0, -4);
    const fixed = body + crc16(body);
    expect(parseSgqr(fixed).proxyValue).toBe("98765432");
  });

  it("rejects an unsupported proxy type", () => {
    const tlv = (t: string, v: string) => t + String(v.length).padStart(2, "0") + v;
    let s = tlv("00", "01") + tlv("26", tlv("00", "SG.PAYNOW") + tlv("01", "3") + tlv("02", "S1234567A")) + "6304";
    s += crc16(s);
    expect(() => parseSgqr(s)).toThrow(NOT_PAYNOW_MESSAGE);
  });

  it("treats a missing amount as editable", () => {
    const raw = buildPaynowQR({ proxyType: "MOBILE", proxyValue: "91234567", amountEditable: false });
    expect(parseSgqr(raw).amountEditable).toBe(true);
  });
});

describe("proxies", () => {
  it("validates mobiles", () => {
    expect(isValidProxy("MOBILE", "91234567")).toBe(true);
    expect(isValidProxy("MOBILE", "81234567")).toBe(true);
    expect(isValidProxy("MOBILE", "61234567")).toBe(false);
    expect(isValidProxy("MOBILE", "9123456")).toBe(false);
  });
  it("validates UENs by length", () => {
    expect(isValidProxy("UEN", "201912345K")).toBe(true);
    expect(isValidProxy("UEN", "53312345D")).toBe(true);
    expect(isValidProxy("UEN", "12345678")).toBe(false);
    expect(isValidProxy("UEN", "12345678901")).toBe(false);
  });
  it("normalizes +65", () => {
    expect(normalizeMobile("+65 9123 4567")).toBe("91234567");
  });
});
