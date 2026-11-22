function trimInt(bytes: Uint8Array): Uint8Array {
  let i = 0;
  while (i < bytes.length - 1 && bytes[i] === 0) i++;
  const v = bytes.slice(i);
  if (v[0] & 0x80) {
    const out = new Uint8Array(v.length + 1);
    out.set(v, 1);
    return out;
  }
  return v;
}

export function p1363ToDer(sig: Uint8Array): Uint8Array {
  const half = sig.length / 2;
  const r = trimInt(sig.slice(0, half));
  const s = trimInt(sig.slice(half));
  const body = new Uint8Array(2 + r.length + 2 + s.length);
  body.set([0x02, r.length], 0);
  body.set(r, 2);
  body.set([0x02, s.length], 2 + r.length);
  body.set(s, 4 + r.length);
  const out = new Uint8Array(2 + body.length);
  out.set([0x30, body.length], 0);
  out.set(body, 2);
  return out;
}

export function toBase64(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
}

/** DER ECDSA signature → raw r||s, each padded to `size` bytes, which is what WebCrypto verifies. */
export function derToP1363(der: Uint8Array, size = 32): Uint8Array<ArrayBuffer> {
  if (der[0] !== 0x30) throw new Error("Not a DER signature");
  let i = 2;
  const int = () => {
    if (der[i] !== 0x02) throw new Error("Not a DER signature");
    const len = der[i + 1];
    const v = der.slice(i + 2, i + 2 + len);
    i += 2 + len;
    const trimmed = v.slice(Math.max(0, v.length - size));
    const out = new Uint8Array(size);
    out.set(trimmed, size - trimmed.length);
    return out;
  };
  const r = int();
  const s = int();
  const out = new Uint8Array(size * 2);
  out.set(r, 0);
  out.set(s, size);
  return out;
}

export function fromBase64(text: string): Uint8Array<ArrayBuffer> {
  const s = atob(text);
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
  return out;
}
