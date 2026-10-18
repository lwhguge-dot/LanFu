// Fal API module exposes the plugin public contract.
import type { ProviderPlugin } from "openclaw/plugin-sdk/provider-model-shared";

const PROVIDER_ID = "fal";

export function createFalProvider(): ProviderPlugin {
  return {
    id: PROVIDER_ID,
    label: "fal",
    docsPath: "/providers/models",
    envVars: ["FAL_KEY"],
    auth: [
      {
        id: "api-key",
        kind: "api_key",
        label: "fal API key",
        hint: "图像、视频与音乐生成 API 密钥",
        run: async () => ({ profiles: [] }),
        wizard: {
          choiceId: "fal-api-key",
          choiceLabel: "fal API key",
          choiceHint: "图像、视频与音乐生成 API 密钥",
          groupId: "fal",
          groupLabel: "fal",
          groupHint: "图像、视频与音乐生成",
          onboardingScopes: ["image-generation", "music-generation"],
        },
      },
    ],
  };
}
