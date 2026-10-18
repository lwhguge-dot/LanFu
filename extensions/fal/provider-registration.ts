// Fal provider module implements model/runtime integration.
import { createProviderApiKeyAuthMethod } from "openclaw/plugin-sdk/provider-entry";
import type { ProviderPlugin } from "openclaw/plugin-sdk/provider-model-shared";
import { applyFalConfig } from "./onboard.js";

const PROVIDER_ID = "fal";

export function createFalProvider(): ProviderPlugin {
  return {
    id: PROVIDER_ID,
    label: "fal",
    docsPath: "/providers/models",
    envVars: ["FAL_KEY"],
    auth: [
      createProviderApiKeyAuthMethod({
        providerId: PROVIDER_ID,
        methodId: "api-key",
        label: "fal API key",
        hint: "图像、视频与音乐生成 API 密钥",
        optionKey: "falApiKey",
        flagName: "--fal-api-key",
        envVar: "FAL_KEY",
        promptMessage: "Enter fal API key",
        expectedProviders: ["fal"],
        applyConfig: (cfg) => applyFalConfig(cfg),
        wizard: {
          choiceId: "fal-api-key",
          choiceLabel: "fal API key",
          choiceHint: "图像、视频与音乐生成 API 密钥",
          groupId: "fal",
          groupLabel: "fal",
          groupHint: "图像、视频与音乐生成",
          onboardingScopes: ["image-generation", "music-generation"],
        },
      }),
    ],
  };
}
