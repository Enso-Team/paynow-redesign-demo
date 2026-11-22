import { cpSync, existsSync, mkdirSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const pub = join(here, "..", "public");
const form = join(here, "..", "..", "..", "packages", "paynow-form", "dist", "index.html");
const samples = join(here, "..", "..", "..", "packages", "sgqr", "samples");

if (!existsSync(form)) {
  console.error("paynow-form is not built. Run: pnpm --filter paynow-form build");
  process.exit(1);
}
mkdirSync(join(pub, "paynow-form"), { recursive: true });
cpSync(form, join(pub, "paynow-form", "index.html"));
mkdirSync(join(pub, "samples"), { recursive: true });
for (const f of readdirSync(samples)) cpSync(join(samples, f), join(pub, "samples", f));
console.log("copied paynow-form bundle and SGQR samples into public/");
