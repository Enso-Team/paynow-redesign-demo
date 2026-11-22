import { describe, expect, it } from "vitest";
import { p1363ToDer } from "./der";

describe("p1363ToDer", () => {
  it("wraps r and s as DER integers", () => {
    const sig = new Uint8Array(64);
    sig[31] = 1;
    sig[63] = 2;
    expect(Array.from(p1363ToDer(sig))).toEqual([0x30, 6, 2, 1, 1, 2, 1, 2]);
  });

  it("pads a high bit with a zero byte", () => {
    const sig = new Uint8Array(64).fill(0xff);
    const der = p1363ToDer(sig);
    expect(der[0]).toBe(0x30);
    expect(der[1]).toBe(70);
    expect(Array.from(der.slice(2, 5))).toEqual([2, 33, 0]);
  });

  it("verifies with WebCrypto after converting back", async () => {
    const key = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
    const msg = new TextEncoder().encode("nonce-123");
    const raw = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key.privateKey, msg));
    const der = p1363ToDer(raw);
    const { createVerify, createPublicKey } = await import("node:crypto");
    const jwk = await crypto.subtle.exportKey("jwk", key.publicKey);
    const pub = createPublicKey({ key: jwk as never, format: "jwk" });
    const v = createVerify("SHA256");
    v.update(Buffer.from(msg));
    expect(v.verify(pub, Buffer.from(der))).toBe(true);
  });
});
