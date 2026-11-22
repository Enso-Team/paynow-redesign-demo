import { writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import QRCode from "qrcode";
import { buildPaynowQR, crc16 } from "../src/index.ts";

const dir = join(dirname(fileURLToPath(import.meta.url)), "..", "samples");
mkdirSync(dir, { recursive: true });

function nets() {
  const tlv = (t, v) => t + String(v.length).padStart(2, "0") + v;
  let s = tlv("00", "01") + tlv("01", "11") + tlv("33", tlv("00", "SG.COM.NETS") + tlv("01", "1234567890")) +
    tlv("52", "5812") + tlv("53", "702") + tlv("58", "SG") + tlv("59", "HAWKER STALL") + tlv("60", "Singapore") + "6304";
  return s + crc16(s);
}

const samples = {
  "mobile-91234567-12.50": buildPaynowQR({
    proxyType: "MOBILE", proxyValue: "+6591234567", amount: "12.50", amountEditable: false,
    expiry: "20301231", reference: "INV-2041", merchantName: "TAN AH SENG",
  }),
  "uen-201912345K-editable": buildPaynowQR({
    proxyType: "UEN", proxyValue: "201912345K", amountEditable: true, merchantName: "KOPI CORNER PTE LTD",
  }),
  "not-paynow-nets": nets(),
  "mobile-90000002-rejected": buildPaynowQR({
    proxyType: "MOBILE", proxyValue: "+6590000002", amount: "5.00", amountEditable: false, merchantName: "REJECTED DEMO",
  }),
  "mobile-90000001-slow": buildPaynowQR({
    proxyType: "MOBILE", proxyValue: "+6590000001", amount: "3.20", amountEditable: true, merchantName: "SLOW DEMO",
  }),
};

const index = [];
for (const [name, raw] of Object.entries(samples)) {
  writeFileSync(join(dir, `${name}.txt`), raw + "\n");
  await QRCode.toFile(join(dir, `${name}.png`), raw, { width: 480, margin: 4, errorCorrectionLevel: "M" });
  index.push({ name, file: `${name}.png`, raw });
}
writeFileSync(join(dir, "index.json"), JSON.stringify(index, null, 2) + "\n");
console.log(`wrote ${index.length} samples to ${dir}`);
