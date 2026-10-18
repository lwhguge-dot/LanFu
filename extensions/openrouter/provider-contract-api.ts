// Openrouter API module exposes the plugin public contract.
import type { ProviderPlugin } from "openclaw/plugin-sdk/provider-model-shared";

export function createOpenrouterProvider(): ProviderPlugin {
  return {
    id: "openrouter",
    label: "OpenRouter",
    docsPath: "/providers/models",
    envVars: ["OPENROUTER_API_KEY"],
    auth: [
      {
        id: "api-key",
        kind: "api_key",
        label: "OpenRouter API key",
        hint: "API 密钥",
        run: async () => ({ profiles: [] }),
        wizard: {
          choiceId: "openrouter-api-key",
          choiceLabel: "OpenRouter API key",
          groupId: "openrouter",
          groupLabel: "OpenRouter",
          groupHint: "OAuth 或 API 密钥",
          onboardingScopes: ["text-inference", "music-generation"],
        },
      },
      {
        id: "oauth",
        kind: "oauth",
        label: "OpenRouter OAuth",
        hint: "浏览器登录",
        run: async () => ({ profiles: [] }),
        wizard: {
          choiceId: "openrouter-oauth",
          choiceLabel: "OpenRouter OAuth",
          choiceHint: "浏览器登录",
          groupId: "openrouter",
          groupLabel: "OpenRouter",
          groupHint: "OAuth 或 API 密钥",
          methodId: "oauth",
          onboardingScopes: ["text-inference", "music-generation"],
          onboardingFeatured: true,
        },
      },
    ],
  };
}
