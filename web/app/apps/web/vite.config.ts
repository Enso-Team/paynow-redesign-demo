import { defineConfig, type ProxyOptions } from "vite";
import react from "@vitejs/plugin-react";
import { fileURLToPath } from "node:url";

const latency = fileURLToPath(new URL("../../../../latency", import.meta.url));

export const PORTS = {
  auth: 8081,
  account: 8082,
  lookup: 8083,
  payment: 8084,
  directory: 8085,
  fast: 8086,
} as const;

const proxy: Record<string, ProxyOptions> = Object.fromEntries(
  Object.entries(PORTS).map(([service, port]) => [
    `^/api/${service}/`,
    {
      target: `http://localhost:${port}`,
      changeOrigin: true,
      rewrite: (path: string) => path.replace(new RegExp(`^/api/${service}`), ""),
    },
  ]),
);

/**
 * `--mode demo` builds the public demo: a static site under /demos/dbs/ whose backend runs in the browser (src/demo).
 * Every other mode talks to the services through the /api proxy.
 */
export default defineConfig(({ mode }) => {
  const demo = mode === "demo";
  return {
    plugins: [react()],
    base: demo ? "/demos/dbs/" : "/",
    resolve: { alias: { "@latency": latency } },
    build: { outDir: demo ? "dist-demo" : "dist", emptyOutDir: true },
    server: { port: 5173, strictPort: true, proxy, fs: { allow: ["../..", latency] } },
    preview: demo ? { port: 4173, strictPort: true } : { port: 5173, strictPort: true, proxy },
  };
});
