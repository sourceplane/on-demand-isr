import { defineConfig } from "vitest/config";
import * as path from "node:path";

// The tests import the app's own modules by path (../../apps/web/…). Three
// things the app's build provides are stood in for here: `server-only`, which
// throws outside a React Server Components build, is a no-op; the pages' JSX
// is compiled with React's automatic runtime (the app's tsconfig preserves it
// for Next.js); and the stylesheets are not processed (CSS-module class names
// read as undefined, which no test asserts on).
const app = path.resolve(__dirname, "../../apps/web");

export default defineConfig({
  resolve: {
    alias: [
      { find: /^server-only$/, replacement: path.resolve(__dirname, "src/server-only.ts") },
      { find: /^@app\//, replacement: `${app}/` },
    ],
  },
  esbuild: { jsx: "automatic" },
  test: {
    include: ["src/**/*.test.ts", "src/**/*.test.tsx"],
    environment: "node",
  },
});
