// Drives the real journeys in headless Chrome and saves screenshots.
// Live: `pnpm build`, then `pnpm --filter web preview` (or dev) on 5173, and the services on 8081-8086.
// Demo (`--demo`): `pnpm build:demo`, then `pnpm --filter web preview:demo`, which serves the static files at
// http://localhost:4173/demos/dbs/. Every request that isn't to that origin is blocked and fails the run.
import { chromium } from "playwright-core";
import { mkdirSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const DEMO = process.argv.includes("--demo");
const shots = join(root, "screenshots", process.env.STUB ? "stub" : "");
mkdirSync(shots, { recursive: true });
const BASE = process.env.BASE_URL ?? (DEMO ? "http://localhost:4173/demos/dbs/" : "http://localhost:5173");
const QRCode = createRequire(join(root, "packages", "sgqr", "package.json"))("qrcode");
const CHROME = process.env.CHROME ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

const browser = await chromium.launch({ executablePath: CHROME, headless: true });
const context = await browser.newContext({ viewport: { width: 460, height: 900 }, deviceScaleFactor: 3 });

// STUB=1 answers /api/** in the browser with a contract-shaped fake, for when the services are down.
async function installStub(ctx) {
  const tokens = new Set();
  const directory = {
    "MOBILE:91234567": ["TAN ** **NG", "OCBC"], "MOBILE:98765432": ["LIM ** **AH", "UOB"],
    "UEN:201912345K": ["KOPI **** PTE LTD", "DBS"], "MOBILE:90000001": ["SLOW ** **ER", "OCBC", 3000],
    "MOBILE:90000002": ["REJ ** **ED", "REJECT"],
  };
  let available = 2345.67, used = 0, version = 1;
  const payments = new Map();
  const json = (route, status, body, headers = {}) =>
    route.fulfill({ status, contentType: "application/json", headers, body: body == null ? "" : JSON.stringify(body) });
  const mint = () => {
    const exp = Math.floor(Date.now() / 1000) + 300;
    const t = `h.${Buffer.from(JSON.stringify({ sub: "u-1", exp })).toString("base64url")}.s${Math.random()}`;
    tokens.add(t);
    return { accessToken: t, refreshToken: "r" + Math.random(), expiresAt: new Date(exp * 1000).toISOString() };
  };
  await ctx.route("**/api/**", async (route) => {
    const req = route.request();
    const url = new URL(req.url());
    const path = url.pathname.replace(/^\/api\/[a-z]+/, "");
    const body = req.postData() ? JSON.parse(req.postData()) : null;
    if (path === "/auth/devices") return json(route, 201, { deviceId: "dev-1", userId: "u-1" });
    if (path === "/auth/attest") return json(route, 200, { attestationId: "att-1" });
    if (path === "/auth/challenge") return json(route, 200, { nonce: "n" + Math.random(), expiresAt: Date.now() + 60000 });
    if (path === "/auth/session" || path === "/auth/refresh") return json(route, 200, mint());
    const auth = (req.headers()["authorization"] ?? "").replace("Bearer ", "");
    if (!tokens.has(auth)) return json(route, 401, { code: "UNAUTHORIZED", message: "Token expired" });
    if (path === "/accounts/summary") {
      const etag = `"v${version}"`;
      if (req.headers()["if-none-match"] === etag) return route.fulfill({ status: 304, headers: { ETag: etag } });
      return json(route, 200, {
        displayName: "ALEX TAN",
        accounts: [
          { id: "acc-1", name: "Everyday Savings", numberMasked: "•••• 1234", balance: available.toLocaleString("en-SG", { minimumFractionDigits: 2 }), available: available.toFixed(2), currency: "SGD" },
          { id: "acc-2", name: "Bonus Savings", numberMasked: "•••• 5678", balance: "10,120.00", available: "10120.00", currency: "SGD" },
        ],
        paynowDailyLimit: "5000.00", paynowUsedToday: used.toFixed(2), updatedAt: new Date().toISOString(),
      }, { ETag: etag });
    }
    if (path === "/paynow/lookup") {
      const key = `${url.searchParams.get("type")}:${url.searchParams.get("value")}`;
      const hit = directory[key];
      if (!hit) return json(route, 404, { code: "PROXY_NOT_FOUND", message: "Not found" });
      if (hit[2]) { await new Promise((r) => setTimeout(r, 2000)); return json(route, 504, { code: "DIRECTORY_TIMEOUT", message: "Timed out" }); }
      return json(route, 200, { proxyType: url.searchParams.get("type"), proxyValue: url.searchParams.get("value"), maskedName: hit[0], bankCode: hit[1] });
    }
    if (path === "/payments/paynow") {
      const key = req.headers()["idempotency-key"];
      if (!payments.has(key)) {
        const hit = directory[`${body.proxyType}:${body.proxyValue}`];
        const amt = Number(body.amount);
        if (amt > available) return json(route, 422, { code: "INSUFFICIENT_FUNDS", message: "" });
        available -= amt; used += amt; version++;
        payments.set(key, { paymentId: "pay-" + key.slice(0, 8), amount: body.amount, maskedName: hit[0], bank: hit[1], at: Date.now() });
      }
      return json(route, 202, { paymentId: payments.get(key).paymentId, status: "PENDING" });
    }
    const m = path.match(/^\/payments\/(.+)$/);
    if (m) {
      const p = [...payments.values()].find((x) => x.paymentId === m[1]);
      await new Promise((r) => setTimeout(r, 400));
      const rejected = p.bank === "REJECT";
      return json(route, 200, { paymentId: p.paymentId, status: rejected ? "REJECTED" : "SETTLED", reason: rejected ? "BENEFICIARY_BANK_REJECTED" : undefined, amount: p.amount, maskedName: p.maskedName, settledAt: new Date().toISOString() });
    }
    return json(route, 404, { code: "NOT_FOUND", message: path });
  });
}
if (process.env.STUB) await installStub(context);

// Privacy: the demo may load its own files and nothing else. Any other origin is blocked and recorded,
// and so is any /api call that reaches the network, since the demo answers those inside the page.
const origin = new URL(BASE).origin;
const leaks = [];
const typed = new Set();
if (DEMO) {
  await context.route("**/*", (route) => {
    const url = new URL(route.request().url());
    if (url.origin !== origin && !["data:", "blob:"].includes(url.protocol)) {
      leaks.push(`blocked ${route.request().method()} ${url.href}`);
      return route.abort("blockedbyclient");
    }
    if (url.pathname.startsWith("/api/")) leaks.push(`network ${route.request().method()} ${url.pathname}`);
    return route.continue();
  });
  // A typed number may not appear in any query string, body, or path outside the demo's own files.
  // (The bundled sample QR images carry seeded numbers in their file names.)
  const base = new URL(BASE).pathname;
  context.on("request", (req) => {
    const url = new URL(req.url());
    const ownFile = url.origin === origin && url.pathname.startsWith(base) && req.method() === "GET";
    const seen = `${ownFile ? "" : url.pathname} ${url.search} ${req.postData() ?? ""}`;
    for (const t of typed) if (seen.includes(t)) leaks.push(`request carries ${t}: ${req.url()}`);
  });
}
const page = await context.newPage();
const errors = [];
page.on("pageerror", (e) => errors.push(e.message));
page.on("console", (m) => m.type() === "error" && errors.push(m.text()));

const screen = page.locator('[data-testid="screen"]');
const form = page.frameLocator('[data-testid="paynow-frame"]');
const shot = async (name) => {
  await screen.screenshot({ path: join(shots, `${DEMO ? "demo-" : ""}${name}.png`) });
  console.log("  saved", name);
};
const results = [];
async function step(name, fn) {
  try {
    await fn();
    results.push(["PASS", name]);
    console.log("PASS", name);
  } catch (e) {
    results.push(["FAIL", name, e.message.split("\n")[0]]);
    console.log("FAIL", name, "-", e.message.split("\n")[0]);
    await shot(`fail-${name.replace(/\W+/g, "-")}`).catch(() => {});
  }
}
const screenIs = (name) => page.waitForSelector(`[data-screen="${name}"]`, { timeout: 15000 });
const faceIdShown = () => page.waitForSelector('[data-testid="faceid"]', { timeout: 5000 });
const faceIdGone = () => page.waitForSelector('[data-testid="faceid"]', { state: "detached", timeout: 8000 });

await step("device binds silently on load", async () => {
  await page.goto(BASE);
  await page.waitForFunction(() => !!localStorage.getItem("dbs.device.id"), null, { timeout: 15000 });
  await page.waitForTimeout(400);
  await shot("01-entry");
});

if (DEMO) {
  await step("demo: the privacy line shows on the entry screen", async () => {
    await page.waitForSelector('[data-testid="privacy-note"]:has-text("Demo. Nothing you enter leaves this device. Recent payees stay in this browser until you reset the demo in More.")');
  });
}

await step("Peek hint chevrons loop with transform and opacity only", async () => {
  const chev = await page.$$eval(".entry-peek-chev", (els) =>
    els.map((el) => {
      const cs = getComputedStyle(el);
      return { name: cs.animationName, duration: cs.animationDuration, timing: cs.animationTimingFunction, dir: cs.getPropertyValue("--chev-in").trim() };
    }),
  );
  const want = [{ name: "peek-chev", duration: "2.4s", timing: "linear", dir: "1" }, { name: "peek-chev", duration: "2.4s", timing: "linear", dir: "-1" }];
  if (JSON.stringify(chev) !== JSON.stringify(want)) throw new Error(JSON.stringify(chev));
  const gaps = await page.evaluate(() => {
    const [l, r] = [...document.querySelectorAll(".entry-peek-chev")].map((e) => e.getBoundingClientRect());
    const t = document.querySelector(".entry-peek > span:nth-child(2)").getBoundingClientRect();
    return [Math.round(t.left - l.right), Math.round(r.left - t.right)];
  });
  if (gaps.some((g) => Math.abs(g - 22) > 8)) throw new Error(`chevron gaps ${gaps}`);
});

// Records whether Face ID or the skeleton ever showed during a hold.
const watchPeek = () =>
  page.evaluate(() => {
    const seen = { faceid: false, skeleton: false };
    const look = () => {
      if (document.querySelector('[data-testid="faceid"]')) seen.faceid = true;
      if (document.querySelector('[data-testid="peek-skeleton"]')) seen.skeleton = true;
    };
    const mo = new MutationObserver(look);
    mo.observe(document.body, { childList: true, subtree: true });
    window.__peekSeen = () => (mo.disconnect(), look(), seen);
  });
const peekSeen = () => page.evaluate(() => window.__peekSeen());
const phase = (p) => page.waitForSelector(`[data-testid="peek-overlay"][data-phase="${p}"]`, { timeout: 15000 });
async function holdPeek() {
  const box = await page.locator('[data-testid="peek"]').boundingBox();
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
}

await step("Peek: hold blurs in place, skeleton, then balance and 3 transactions, no Face ID", async () => {
  await page.evaluate(() => window.__dbsDemo.peekTimeScale(10));
  await watchPeek();
  await holdPeek();
  await page.waitForTimeout(300);
  await shot("peek-1");
  await phase("bars");
  await page.waitForTimeout(150);
  await shot("peek-2");
  await phase("blank");
  await page.waitForTimeout(150);
  await shot("peek-3");
  await phase("expanded");
  await page.waitForSelector('[data-testid="peek-balance"]:has-text("SGD")');
  const rows = await page.locator('[data-testid="peek-tx"]').count();
  if (rows !== 3) throw new Error(`${rows} transaction rows`);
  await page.waitForSelector('.peek-more:has-text("Latest transactions (within last 30 days)")');
  await page.waitForSelector('.peek-asof:has-text("As of")');
  await page.waitForTimeout(2600);
  await shot("peek-4");
  await screenIs("entry");
  await page.mouse.up();
  await page.waitForSelector('[data-testid="peek-overlay"]', { state: "detached", timeout: 5000 });
  const seen = await peekSeen();
  if (seen.faceid) throw new Error("Face ID showed during Peek");
  if (!seen.skeleton) throw new Error("no skeleton on the first hold");
  await page.evaluate(() => window.__dbsDemo.peekTimeScale(1));
});

await step("Peek: a repeat hold shows the balance on the first frame", async () => {
  await watchPeek();
  await holdPeek();
  await page.waitForSelector('[data-testid="peek-balance"]:has-text("SGD")', { timeout: 100 });
  await phase("expanded");
  await page.mouse.up();
  await page.waitForSelector('[data-testid="peek-overlay"]', { state: "detached", timeout: 5000 });
  const seen = await peekSeen();
  if (seen.skeleton) throw new Error("skeleton showed on a repeat hold");
  if (seen.faceid) throw new Error("Face ID showed during Peek");
  await screenIs("entry");
});

await step("Face ID cancel drops the intent and stays on entry", async () => {
  await page.click('[data-testid="tile-login"]');
  await faceIdShown();
  await page.click('[data-testid="faceid-cancel"]');
  await faceIdGone();
  await screenIs("entry");
});

await step("Scan & Pay: Face ID then scanner", async () => {
  await page.click('[data-testid="tile-scan"]');
  await faceIdShown();
  await page.waitForTimeout(350);
  await shot("02-faceid");
  await faceIdGone();
  await screenIs("scanner");
  await page.waitForTimeout(600);
  await shot("03-scanner");
});

await step("non-PayNow QR shows the error and keeps scanning", async () => {
  await page.click('[data-testid="sample-not-paynow-nets"]');
  await page.waitForSelector('[data-testid="toast"]:has-text("This QR isn\'t a PayNow code")');
  await shot("04-scanner-not-paynow");
  await screenIs("scanner");
});

await step("sample QR opens the form with TAN ** **NG", async () => {
  await page.click('[data-testid="sample-mobile-91234567-12.50"]');
  await screenIs("form");
  await form.locator('[data-testid="name"]').filter({ hasText: "TAN ** **NG" }).waitFor({ timeout: 10000 });
  const amount = await form.locator('[data-testid="amount"]').inputValue();
  if (amount !== "12.50") throw new Error(`amount ${amount}`);
  await page.waitForTimeout(300);
  await shot("05-form-qr");
});

await step("Pay (no second Face ID) then sent", async () => {
  await form.locator('[data-testid="pay"]').click();
  const sawFaceId = await page.locator('[data-testid="faceid"]').isVisible();
  if (sawFaceId) throw new Error("Face ID asked again at Pay");
  await screenIs("sent");
  await page.waitForSelector('[data-testid="sent-amount"]:has-text("SGD 12.50")');
  await page.waitForTimeout(400);
  await shot("06-sent");
});

await step("Done lands on Home with the greeting", async () => {
  await page.click('[data-testid="sent-done"]');
  await screenIs("tabs");
  await page.waitForSelector('[data-testid="greeting"]:has-text("Hi, ALEX TAN!")');
  await page.waitForSelector('[data-testid="balance"]:has-text("SGD")', { timeout: 10000 });
  await page.waitForTimeout(400);
  await shot("07-home");
});

await step("balance-hide toggle persists", async () => {
  await page.click('[data-testid="eye"]');
  await page.waitForSelector('[data-testid="balance"]:has-text("••••••")');
  const v = await page.evaluate(() => localStorage.getItem("dbs.hideBalance"));
  if (v !== "1") throw new Error("not persisted");
  await shot("08-home-hidden");
  await page.click('[data-testid="eye"]');
});

await step("tabs keep scroll position", async () => {
  const home = page.locator('[data-testid="pane-home"] .scroll');
  const want = await home.evaluate((el) => ((el.scrollTop = 180), el.scrollTop));
  if (want < 50) throw new Error(`Home doesn't scroll (${want})`);
  await page.click('[data-testid="tab-pay"]');
  await page.waitForTimeout(300);
  await shot("09-pay-transfer");
  await page.click('[data-testid="tab-home"]');
  const top = await home.evaluate((el) => el.scrollTop);
  if (Math.abs(top - want) > 2) throw new Error(`scrollTop ${top}, expected ${want}`);
  await home.evaluate((el) => (el.scrollTop = 0));
});

await step("failed refresh keeps data and shows Updated N min ago", async () => {
  // Let the refresh the last tab tap started land first, since the measured summary takes 600 ms.
  await page.waitForTimeout(DEMO ? 1200 : 0);
  if (DEMO) await page.evaluate(() => window.__dbsDemoNetwork.offline.add("account"));
  else await page.route("**/api/account/**", (r) => r.abort());
  try {
    await page.click('[data-testid="tab-pay"]');
    await page.click('[data-testid="tab-home"]');
    await page.waitForSelector('[data-testid="stale"]:has-text("min ago")', { timeout: 8000 });
    await page.waitForSelector('[data-testid="balance"]:has-text("SGD")');
    await shot("10-home-stale");
  } finally {
    if (DEMO) await page.evaluate(() => window.__dbsDemoNetwork.offline.delete("account"));
    else await page.unroute("**/api/account/**");
  }
});

await step("log out returns to entry", async () => {
  await page.click('[data-testid="logout"]');
  await screenIs("entry");
});

await step("PayNow: Face ID then menu", async () => {
  await page.click('[data-testid="tile-paynow"]');
  await faceIdShown();
  await faceIdGone();
  await screenIs("paynowMenu");
  await shot("11-paynow-menu");
});

await step("PayNow to mobile 91234567: lookup, Pay, sent", async () => {
  await page.click('[data-testid="menu-mobile"]');
  await screenIs("form");
  await form.locator('[data-testid="proxy-input"]').waitFor();
  await shot("12-form-menu-empty");
  if (DEMO) await page.waitForSelector('[data-testid="privacy-note"]:has-text("Nothing you enter leaves this device")');
  await form.locator('[data-testid="proxy-input"]').fill("91234567");
  typed.add("91234567");
  await form.locator('[data-testid="name-skeleton"]').waitFor({ timeout: 3000 }).catch(() => {});
  await form.locator('[data-testid="name"]').filter({ hasText: "TAN ** **NG" }).waitFor({ timeout: 10000 });
  await form.locator('[data-testid="amount"]').fill("5");
  await page.waitForTimeout(200);
  await shot("13-form-menu-filled");
  await form.locator('[data-testid="pay"]').click();
  await screenIs("sent");
  await page.waitForSelector('[data-testid="sent-amount"]:has-text("SGD 5.00")');
  await shot("14-sent-mobile");
});

await step("Recent payees: a paid payee is one tap away, and Clear wipes them", async () => {
  await page.click('[data-testid="sent-done"]');
  await screenIs("tabs");
  await page.click('[data-testid="home-paynow"]');
  await screenIs("paynowMenu");
  await page.waitForSelector('[data-testid="recent-91234567"]:has-text("TAN ** **NG")');
  await shot("20-recent-payees");
  const stored = await page.evaluate(() => JSON.parse(localStorage.getItem("dbs.recentPayees")));
  if (stored[0]?.proxyValue !== "91234567" || stored[0]?.maskedName !== "TAN ** **NG") throw new Error(JSON.stringify(stored));
  await page.click('[data-testid="recent-91234567"]');
  await screenIs("form");
  await form.locator('[data-testid="name"]').filter({ hasText: "TAN ** **NG" }).waitFor({ timeout: 10000 });
  await form.locator("#pf-close").click();
  await screenIs("paynowMenu");
  await page.click('[data-testid="recent-clear"]');
  await page.waitForSelector('[data-testid="recent-payees"]', { state: "detached" });
  if (await page.evaluate(() => localStorage.getItem("dbs.recentPayees"))) throw new Error("not wiped");
  await page.click('[data-testid="menu-close"]');
  await screenIs("tabs");
  await page.click('[data-testid="home-paynow"]');
  await screenIs("paynowMenu");
});

await step("over the balance shows Not enough in this account", async () => {
  await page.click('[data-testid="menu-mobile"]');
  await form.locator('[data-testid="proxy-input"]').fill("98765432");
  await form.locator('[data-testid="name"]').waitFor({ timeout: 10000 });
  await form.locator('[data-testid="amount"]').fill("4000");
  await form.locator('[data-testid="amount-error"]').filter({ hasText: "Not enough in this account" }).waitFor();
  if (await form.locator('[data-testid="pay"]').isEnabled()) throw new Error("Pay enabled");
  await shot("15-form-not-enough");
});

await step("80000000 is not found", async () => {
  await form.locator('[data-testid="proxy-input"]').fill("80000000");
  await form.locator('[data-testid="lookup-error"]').filter({ hasText: "No PayNow account for this number" }).waitFor({ timeout: 10000 });
  if (await form.locator('[data-testid="pay"]').isEnabled()) throw new Error("Pay enabled");
  await shot("16-form-not-found");
});

await step("90000001 times out with Retry", async () => {
  await form.locator('[data-testid="proxy-input"]').fill("90000001");
  await form.locator('[data-testid="lookup-error"]').filter({ hasText: "Couldn't check the name" }).waitFor({ timeout: 15000 });
  await form.locator('[data-testid="lookup-retry"]').waitFor();
  await shot("17-form-timeout");
});

await step("a 401 runs one Face ID re-check and carries on", async () => {
  await page.evaluate(() => window.__dbsDemo.expireAccessToken());
  await form.locator('[data-testid="proxy-input"]').fill("98765432");
  await faceIdShown();
  await faceIdGone();
  await form.locator('[data-testid="name"]').filter({ hasText: "LIM ** **AH" }).waitFor({ timeout: 10000 });
});

await step("idle asks Face ID on the next action and keeps the form", async () => {
  await form.locator('[data-testid="amount"]').fill("1.20");
  await page.evaluate(() => window.__dbsDemo.goIdle());
  await form.locator('[data-testid="pay"]').click();
  await faceIdShown();
  await shot("18-idle-recheck");
  await faceIdGone();
  await screenIs("sent");
});

await step("rejected payee shows the rejection", async () => {
  await page.click('[data-testid="sent-done"]');
  await page.click('[data-testid="tab-pay"]');
  await page.click('[data-testid="pay-scan"]');
  await screenIs("scanner");
  await page.click('[data-testid="sample-mobile-90000002-rejected"]');
  await form.locator('[data-testid="name"]').waitFor({ timeout: 10000 });
  await form.locator('[data-testid="pay"]').click();
  await form.locator('[data-testid="rejected"]').waitFor({ timeout: 20000 });
  await shot("19-rejected");
});

// A static personal PayNow QR as banking apps make them: mobile proxy, editable amount, no amount and no name.
function personalQr(mobile) {
  const tlv = (t, v) => t + String(v.length).padStart(2, "0") + v;
  const crc = (str) => {
    let c = 0xffff;
    for (const ch of str) {
      c ^= ch.charCodeAt(0) << 8;
      for (let i = 0; i < 8; i++) c = c & 0x8000 ? ((c << 1) ^ 0x1021) & 0xffff : (c << 1) & 0xffff;
    }
    return c.toString(16).toUpperCase().padStart(4, "0");
  };
  const s = tlv("00", "01") + tlv("01", "11") +
    tlv("26", tlv("00", "SG.PAYNOW") + tlv("01", "0") + tlv("02", `+65${mobile}`) + tlv("03", "1")) +
    tlv("52", "0000") + tlv("53", "702") + tlv("58", "SG") + tlv("60", "Singapore") + "6304";
  return s + crc(s);
}

await step("a real personal PayNow QR for an unseeded number uploads and pays through to Sent", async () => {
  const seeded = ["91234567", "98765432", "90000001", "90000002"];
  let mobile;
  do mobile = "9" + String(Math.floor(Math.random() * 1e7)).padStart(7, "0");
  while (seeded.includes(mobile));
  typed.add(mobile);
  const png = await QRCode.toBuffer(personalQr(mobile), { width: 480, margin: 4 });
  if (await page.locator('[data-screen="form"]').count()) await form.locator("#pf-close").click();
  await page.waitForSelector('[data-screen="scanner"], [data-screen="tabs"]');
  if (await page.locator('[data-screen="tabs"]').count()) {
    await page.click('[data-testid="tab-pay"]');
    await page.click('[data-testid="pay-scan"]');
  }
  await screenIs("scanner");
  await page.setInputFiles('[data-testid="upload-input"]', { name: "paynow.png", mimeType: "image/png", buffer: png });
  await screenIs("form");
  const name = form.locator('[data-testid="name"]').filter({ hasText: /^[A-Z]+ \*\* \*\*[A-Z]{2}/ });
  await name.waitFor({ timeout: 10000 });
  const masked = (await name.innerText()).split("\n")[0].trim();
  const amount = form.locator('[data-testid="amount"]');
  if (!(await amount.isEditable())) throw new Error("amount isn't editable");
  await amount.fill("3.40");
  await page.waitForTimeout(200);
  await shot("21-form-real-qr");
  await form.locator('[data-testid="pay"]').click();
  await screenIs("sent");
  await page.waitForSelector('[data-testid="sent-amount"]:has-text("SGD 3.40")');
  await page.waitForSelector(`.sent-to:has-text("${masked}")`);
  await shot("22-sent-real-qr");
  console.log(`  paid ${mobile} (${masked})`);
});

if (DEMO) {
  await step("demo: More has the timing line and Reset demo wipes the demo storage", async () => {
    await page.click('[data-testid="sent-done"]');
    await screenIs("tabs");
    await page.click('[data-testid="tab-more"]');
    await page.waitForSelector('[data-testid="timing-note"]:has-text("Network times simulated from timings measured in a real banking app.")');
    await page.locator('[data-testid="about-demo"]').scrollIntoViewIfNeeded();
    await shot("23-more-about");
    const before = await page.evaluate(() => Object.keys(localStorage).filter((k) => k.startsWith("dbs.")).length);
    if (before < 3) throw new Error(`only ${before} demo keys before reset`);
    await page.click('[data-testid="reset-demo"]');
    await page.waitForLoadState("load");
    await screenIs("entry");
    const left = await page.evaluate(() => JSON.parse(localStorage.getItem("dbs.demo.bank") ?? "{}"));
    if (left.payments && Object.keys(left.payments).length) throw new Error("payments survived the reset");
    if (await page.evaluate(() => localStorage.getItem("dbs.recentPayees"))) throw new Error("recent payees survived");
  });

  await step("demo: a fresh visitor sees the seeded balance after a reload", async () => {
    await page.reload();
    await page.waitForFunction(() => !!localStorage.getItem("dbs.device.id"), null, { timeout: 15000 });
    await page.click('[data-testid="tile-login"]');
    await faceIdShown();
    await faceIdGone();
    await screenIs("tabs");
    await page.waitForSelector('[data-testid="balance"]:has-text("12,465.67")', { timeout: 10000 });
  });

  await step("demo privacy: nothing left the browser and no other origin was asked", async () => {
    const probe = await page.evaluate(() => fetch("https://example.com/").then(() => "reached", () => "blocked"));
    if (probe !== "blocked") throw new Error("an external request got through");
    const real = leaks.filter((l) => !l.includes("example.com"));
    if (real.length) throw new Error(real.slice(0, 5).join("; "));
  });
}

console.log("\nconsole/page errors:", errors.length ? errors.slice(0, 8) : "none");
const failed = results.filter((r) => r[0] === "FAIL");
console.log(`\n${results.length - failed.length}/${results.length} passed`);
await browser.close();
process.exit(failed.length ? 1 : 0);
