import { describe, expect, it, vi } from "vitest";
import { createPeek, formatDay, formatSigned, PEEK_CACHE_MS, type PeekBalance } from "./peek";

const DATA: PeekBalance = {
  balance: "2,345.67",
  currency: "SGD",
  asOf: "2026-11-20T09:32:00Z",
  transactions: [{ type: "PayNow Transfer", date: "2026-11-19", amount: "-12.50" }],
};

function setup(statuses: number[] = [200]) {
  let now = 1_000_000;
  let passes = 0;
  const getPass = vi.fn(async () => ({ token: `pass-${++passes}`, expiresAt: now + 60_000 }));
  const get = vi.fn(async () => ({ status: statuses.shift() ?? 200, body: DATA }));
  const peek = createPeek({ getPass, get, now: () => now });
  return { peek, getPass, get, advance: (ms: number) => (now += ms) };
}

describe("peek", () => {
  it("has nothing cached before the first hold", () => {
    expect(setup().peek.cached()).toBeNull();
  });

  it("serves a repeat hold from the cache without a request", async () => {
    const { peek, get } = setup();
    await peek.load();
    expect(peek.cached()).toEqual(DATA);
    await peek.load();
    expect(get).toHaveBeenCalledTimes(1);
  });

  it("fetches again once the cache is a minute old", async () => {
    const { peek, get, advance } = setup();
    await peek.load();
    advance(PEEK_CACHE_MS);
    expect(peek.cached()).toBeNull();
    await peek.load();
    expect(get).toHaveBeenCalledTimes(2);
  });

  it("shares one request between overlapping holds", async () => {
    const { peek, get } = setup();
    await Promise.all([peek.load(), peek.load()]);
    expect(get).toHaveBeenCalledTimes(1);
  });

  it("reuses the pass until it nearly expires", async () => {
    const { peek, getPass, advance } = setup();
    await peek.load();
    advance(PEEK_CACHE_MS);
    await peek.load();
    expect(getPass).toHaveBeenCalledTimes(2);
  });

  it("gets a new pass and retries once on a 401", async () => {
    const { peek, getPass, get } = setup([401, 200]);
    await expect(peek.load()).resolves.toEqual(DATA);
    expect(getPass).toHaveBeenCalledTimes(2);
    expect(get).toHaveBeenLastCalledWith("pass-2");
  });

  it("fails on a second 401", async () => {
    const { peek } = setup([401, 401]);
    await expect(peek.load()).rejects.toThrow("401");
    expect(peek.cached()).toBeNull();
  });
});

describe("formatting", () => {
  it("signs amounts and adds separators", () => {
    expect(formatSigned("-12.50")).toBe("-12.50");
    expect(formatSigned("1500")).toBe("+1,500.00");
  });

  it("shortens dates", () => {
    expect(formatDay("2026-11-09")).toBe("9 Nov");
  });
});
