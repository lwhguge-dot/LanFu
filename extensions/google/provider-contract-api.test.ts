import { describe, expect, it } from "vitest";
import { createGoogleGeminiCliProvider, createGoogleProvider } from "./provider-contract-api.js";

describe("google provider contract", () => {
  it("exposes Google AI Studio API-key setup", () => {
    const provider = createGoogleProvider();

    expect(provider.auth).toEqual([
      expect.objectContaining({
        id: "api-key",
        label: "Google AI Studio API key",
        hint: "通过 aistudio.google.com/apikey 使用 API 密钥",
        wizard: expect.objectContaining({
          choiceLabel: "Google AI Studio API key",
          groupHint: "支持 API 密钥方式",
        }),
      }),
    ]);
  });

  it("keeps Gemini CLI as a runtime-only compatibility provider", () => {
    const provider = createGoogleGeminiCliProvider();

    expect(provider.label).toBe("Gemini CLI runtime");
    expect(provider.auth).toEqual([]);
    expect(provider.envVars).toEqual([]);
    expect(provider.wizard).toBeUndefined();
  });
});
