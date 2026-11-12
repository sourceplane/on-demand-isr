// The Worker's environment as the app reads it through getCloudflareContext()
// (lib/settings.ts). `wrangler types` would generate this from wrangler.jsonc;
// it is kept by hand so the build needs no rendered config. The GitHub App's
// three settings are optional Worker secrets: absent until the owner connects
// an App.
declare global {
  interface CloudflareEnv {
    ASSETS: {
      fetch(
        input: string | URL | Request,
        init?: RequestInit,
      ): Promise<Response>;
    };
    GITHUB_APP_ID?: string;
    GITHUB_APP_PK_PEM?: string;
    GITHUB_WEBHOOK_SECRET?: string;
  }
}

export {};
