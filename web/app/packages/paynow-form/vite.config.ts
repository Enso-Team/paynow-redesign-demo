import { defineConfig, type Plugin } from "vite";
import react from "@vitejs/plugin-react";

function inlineIntoHtml(): Plugin {
  return {
    name: "inline-into-html",
    enforce: "post",
    generateBundle(_options, bundle) {
      const htmlFile = Object.values(bundle).find((f) => f.fileName.endsWith(".html"));
      if (!htmlFile || htmlFile.type !== "asset") return;
      let html = String(htmlFile.source);
      for (const [name, file] of Object.entries(bundle)) {
        const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        if (file.type === "chunk") {
          const code = file.code.replace(/<\/script/gi, "<\\/script");
          html = html.replace(
            new RegExp(`<script[^>]*src="[^"]*${escaped}"[^>]*></script>`),
            () => `<script type="module">${code}</script>`,
          );
          delete bundle[name];
        } else if (name.endsWith(".css")) {
          html = html.replace(
            new RegExp(`<link[^>]*href="[^"]*${escaped}"[^>]*>`),
            () => `<style>${String(file.source)}</style>`,
          );
          delete bundle[name];
        }
      }
      htmlFile.source = html;
    },
  };
}

export default defineConfig({
  base: "./",
  plugins: [react(), inlineIntoHtml()],
  build: {
    outDir: "dist",
    emptyOutDir: true,
    assetsInlineLimit: 100_000_000,
    cssCodeSplit: false,
  },
  server: { port: 5174 },
});
