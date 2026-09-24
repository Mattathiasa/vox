import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { resolve } from "node:path";

// GitHub Pages serves the repo at https://mattathiasa.github.io/vox/
export default defineConfig({
  base: process.env.VOX_SITE_BASE ?? "/vox/",
  plugins: [react()],
  server: { fs: { allow: [".."] } },
  build: {
    rollupOptions: {
      input: { main: resolve(__dirname, "index.html"), demo: resolve(__dirname, "demo/index.html") },
    },
  },
});
