import { describe, expect, it } from "vitest";
import { findProxy, javaHash } from "./directory";

// Answers recorded from the running Java mock-directory, so the browser stub names proxies the same way.
const FROM_JAVA: [string, string, string, string][] = [
  ["MOBILE", "81234567", "TOH ** **FM", "OCBC"],
  ["MOBILE", "99887766", "YEO ** **KL", "UOB"],
  ["MOBILE", "93456781", "LIM ** **YA", "OCBC"],
  ["MOBILE", "88888888", "CHAN ** **MK", "UOB"],
  ["MOBILE", "90000003", "GOH ** **LY", "DBS"],
  ["MOBILE", "97531246", "LIM ** **SB", "OCBC"],
  ["MOBILE", "80000099", "ONG ** **TJ", "UOB"],
  ["UEN", "53312345A", "GOLDEN **** PTE LTD", "UOB"],
  ["UEN", "T08LL1234A", "HAPPY **** PTE LTD", "UOB"],
  ["UEN", "199901234Z", "KOPI **** PTE LTD", "DBS"],
  ["UEN", "202012345M", "MARINA **** PTE LTD", "OCBC"],
];

describe("mock directory", () => {
  it("hashes like Java's String.hashCode", () => {
    expect(javaHash("")).toBe(0);
    expect(javaHash("hello")).toBe(99162322);
  });

  it.each(FROM_JAVA)("names %s %s like the Java service", (type, value, name, bank) => {
    expect(findProxy(type, value)?.proxy).toEqual({ proxyType: type, proxyValue: value, maskedName: name, bankCode: bank });
  });

  it("answers the seeded proxies as seeded", () => {
    expect(findProxy("MOBILE", "91234567")?.proxy.maskedName).toBe("TAN ** **NG");
    expect(findProxy("UEN", "201912345k")?.proxy.maskedName).toBe("KOPI **** PTE LTD");
    expect(findProxy("MOBILE", "90000001")?.latencyMs).toBe(3000);
    expect(findProxy("MOBILE", "90000002")?.proxy.bankCode).toBe("REJECT");
  });

  it("returns 404 for numbers starting 8000000 and malformed proxies", () => {
    expect(findProxy("MOBILE", "80000000")).toBeNull();
    expect(findProxy("MOBILE", "80000001")).toBeNull();
    expect(findProxy("MOBILE", "71234567")).toBeNull();
    expect(findProxy("UEN", "SHORT")).toBeNull();
  });

  it("gives the same name every time", () => {
    expect(findProxy("MOBILE", "93456781")).toEqual(findProxy("MOBILE", "93456781"));
  });
});
