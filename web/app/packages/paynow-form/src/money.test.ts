import { describe, expect, it } from "vitest";
import { display, fromCents, initials, isAmountInput, maskProxy, toCents, uuid } from "./money";

describe("money", () => {
  it("parses decimal strings to cents", () => {
    expect(toCents("12.5")).toBe(1250);
    expect(toCents("2,345.67")).toBe(234567);
    expect(toCents("0.01")).toBe(1);
    expect(toCents("abc")).toBeNull();
    expect(toCents("1.234")).toBeNull();
  });
  it("formats cents", () => {
    expect(fromCents(1250)).toBe("12.50");
    expect(display(500000)).toBe("5,000.00");
  });
  it("accepts amount typing up to two decimals", () => {
    expect(isAmountInput("")).toBe(true);
    expect(isAmountInput("12.")).toBe(true);
    expect(isAmountInput("12.505")).toBe(false);
  });
});

describe("display helpers", () => {
  it("masks proxies", () => {
    expect(maskProxy("MOBILE", "91234567")).toBe("MOBILE, +65 •••• 4567");
    expect(maskProxy("UEN", "201912345K")).toBe("UEN •••••345K");
  });
  it("takes initials from masked names", () => {
    expect(initials("TAN ** **NG")).toBe("TN");
    expect(initials("KOPI **** PTE LTD")).toBe("KP");
  });
  it("makes v4 UUIDs", () => {
    expect(uuid()).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  });
});
