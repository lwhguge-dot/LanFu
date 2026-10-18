import { createLazyRuntimeModule } from "openclaw/plugin-sdk/lazy-runtime";
import type { ProviderAuthMethod } from "openclaw/plugin-sdk/plugin-entry";
import type { OAuthCredential } from "openclaw/plugin-sdk/provider-auth";

const PROVIDER_ID = "xai";
const XAI_OAUTH_METHOD_ID = "oauth";
const XAI_OAUTH_CHOICE_ID = "xai-oauth";
const XAI_DEVICE_CODE_METHOD_ID = "device-code";
const XAI_DEVICE_CODE_CHOICE_ID = "xai-device-code";

const loadXaiOAuthRuntime = createLazyRuntimeModule(() => import("./xai-oauth.js"));

export function createXaiOAuthAuthMethod(): ProviderAuthMethod {
  return {
    id: XAI_OAUTH_METHOD_ID,
    label: "xAI OAuth",
    hint: "适合远程的浏览器登录（无需 localhost 回调）",
    kind: "oauth",
    wizard: {
      choiceId: XAI_OAUTH_CHOICE_ID,
      choiceLabel: "xAI OAuth",
      choiceHint: "适合远程的浏览器登录（无需 localhost 回调）",
      groupId: PROVIDER_ID,
      groupLabel: "xAI (Grok)",
      groupHint: "API 密钥或 OAuth",
      methodId: XAI_OAUTH_METHOD_ID,
    },
    run: async (ctx) => (await loadXaiOAuthRuntime()).loginXaiDeviceCode(ctx),
  };
}

export function createXaiDeviceCodeAuthMethod(): ProviderAuthMethod {
  return {
    id: XAI_DEVICE_CODE_METHOD_ID,
    label: "xAI device code",
    hint: "Deprecated alias for xAI OAuth device-code login",
    kind: "device_code",
    wizard: {
      choiceId: XAI_DEVICE_CODE_CHOICE_ID,
      choiceLabel: "xAI device code",
      choiceHint: "xAI OAuth 设备码登录的兼容别名",
      assistantVisibility: "manual-only",
      groupId: PROVIDER_ID,
      groupLabel: "xAI (Grok)",
      groupHint: "API 密钥或 OAuth",
      methodId: XAI_DEVICE_CODE_METHOD_ID,
    },
    run: async (ctx) => (await loadXaiOAuthRuntime()).loginXaiDeviceCode(ctx),
  };
}

export async function refreshXaiOAuthCredential(
  credential: OAuthCredential,
): Promise<OAuthCredential> {
  return await (await loadXaiOAuthRuntime()).refreshXaiOAuthCredential(credential);
}
