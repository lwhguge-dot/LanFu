// Qa Lab tests cover Crabline channel-driver integration with local provider servers.
import type { OpenClawCrablineChannelDriverSelection } from "@openclaw/crabline";
import { fetchWithSsrFGuard } from "openclaw/plugin-sdk/ssrf-runtime";
import { withTempDir } from "openclaw/plugin-sdk/test-env";
import { describe, expect, it } from "vitest";
import { createQaBusState } from "./bus-state.js";
import { createQaCrablineTransportAdapter } from "./crabline-transport.js";

function createSelection(channel: OpenClawCrablineChannelDriverSelection["channel"] = "matrix") {
  return {
    capabilityMatrixPath: "crabline-channel-driver-capabilities.json",
    channel,
    channelDriver: "crabline",
    providerReadinessArtifactPath: "crabline-provider-readiness.json",
  } as const;
}

function requireString(value: unknown, label: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`${label} is required`);
  }
  return value;
}

describe("crabline transport", () => {
  it("rejects canonical sender-policy flows on Crabline bridges", async () => {
    await withTempDir("qa-crabline-transport-", async (outputDir) => {
      await expect(
        createQaCrablineTransportAdapter({
          outputDir,
          transportPolicy: { senderAllowlist: ["driver"] },
          selection: createSelection("matrix"),
          state: createQaBusState(),
        }),
      ).rejects.toThrow("Crabline matrix does not support the requested group transport policy");
    });
  });

  it("binds Mattermost config and normalizes transport targets", async () => {
    await withTempDir("qa-crabline-transport-", async (outputDir) => {
      const transport = await createQaCrablineTransportAdapter({
        outputDir,
        selection: createSelection("mattermost"),
        state: createQaBusState(),
      });

      try {
        expect(transport.requiredPluginIds).toEqual(["mattermost"]);
        const mattermostGatewayConfig = transport.createGatewayConfig({
          baseUrl: "http://127.0.0.1:1",
        }) as { channels?: { mattermost?: Record<string, unknown> } };
        expect(mattermostGatewayConfig).toMatchObject({
          channels: {
            mattermost: {
              baseUrl: expect.stringMatching(/^http:\/\/127\.0\.0\.1:\d+$/u),
              botToken: "crabline-mattermost-token",
              enabled: true,
              network: { dangerouslyAllowPrivateNetwork: true },
            },
          },
        });
        expect(transport.createRuntimeEnvPatch?.()).toMatchObject({
          MATTERMOST_BOT_TOKEN: "crabline-mattermost-token",
          MATTERMOST_URL: expect.stringMatching(/^http:\/\/127\.0\.0\.1:\d+$/u),
        });
        expect(transport.buildAgentDelivery({ target: "group:qa-channel" })).toMatchObject({
          channel: "mattermost",
          replyChannel: "mattermost",
          replyTo: expect.stringMatching(/^channel:[a-z0-9]{26}$/u),
          to: expect.stringMatching(/^channel:[a-z0-9]{26}$/u),
        });
        expect(
          transport.buildAgentDelivery({ target: "group:qa-channel", threadId: "post-root" }),
        ).toMatchObject({
          channel: "mattermost",
          threadId: expect.stringMatching(/^[a-z0-9]{26}$/u),
        });
        expect(mattermostGatewayConfig.channels?.mattermost?.streaming).toEqual({ mode: "off" });

        await expect(
          transport.state.addInboundMessage({
            conversation: { id: "qa-channel", kind: "group" },
            senderId: "alice",
            senderName: "Alice",
            text: "Mattermost baseline marker check.",
          }),
        ).resolves.toMatchObject({
          conversation: { id: "qa-channel", kind: "group" },
          direction: "inbound",
          senderId: "alice",
          text: "Mattermost baseline marker check.",
        });
      } finally {
        await transport.cleanupAfterGatewayStop?.();
      }
    });
  });

  it("correlates Mattermost's authoritative inbound channel with symbolic QA state", async () => {
    await withTempDir("qa-crabline-transport-", async (outputDir) => {
      const transport = await createQaCrablineTransportAdapter({
        outputDir,
        selection: createSelection("mattermost"),
        state: createQaBusState(),
      });

      try {
        await transport.state.addInboundMessage({
          conversation: { id: "alice", kind: "direct" },
          senderId: "alice",
          senderName: "Alice",
          text: "Mattermost baseline marker check.",
        });
        const env = transport.createRuntimeEnvPatch?.() ?? {};
        const mattermostUrl = requireString(env.MATTERMOST_URL, "Mattermost URL");
        const botToken = requireString(env.MATTERMOST_BOT_TOKEN, "Mattermost bot token");
        const mattermostRequest = async <T>(apiPath: string, init?: RequestInit) => {
          const headers = new Headers(init?.headers);
          headers.set("authorization", `Bearer ${botToken}`);
          headers.set("content-type", "application/json");
          const { response, release } = await fetchWithSsrFGuard({
            url: `${mattermostUrl}/api/v4${apiPath}`,
            init: {
              ...init,
              headers,
            },
            policy: { allowPrivateNetwork: true },
            auditContext: "qa-lab-crabline-mattermost-transport-test",
          });
          try {
            expect(response.ok).toBe(true);
            return (await response.json()) as T;
          } finally {
            await release();
          }
        };
        const bot = await mattermostRequest<{ id: string }>("/users/me");
        const alice = await mattermostRequest<{ id: string }>("/users/username/alice");
        const directChannel = await mattermostRequest<{ id: string }>("/channels/direct", {
          body: JSON.stringify([bot.id, alice.id]),
          method: "POST",
        });
        const outboundPost = await mattermostRequest<{ channel_id: string }>("/posts", {
          body: JSON.stringify({
            channel_id: directChannel.id,
            message: "assistant via fake mattermost",
          }),
          method: "POST",
        });
        expect(outboundPost.channel_id).toBe(directChannel.id);

        await expect(
          transport.waitForOutbound({
            conversation: { id: "alice", kind: "direct" },
            textIncludes: "assistant via fake mattermost",
            timeoutMs: 1_000,
          }),
        ).resolves.toMatchObject({
          conversation: { id: "alice", kind: "direct" },
          text: "assistant via fake mattermost",
        });
      } finally {
        await transport.cleanupAfterGatewayStop?.();
      }
    });
  });

  it("binds Matrix config and normalizes transport targets", async () => {
    await withTempDir("qa-crabline-transport-", async (outputDir) => {
      const transport = await createQaCrablineTransportAdapter({
        outputDir,
        selection: createSelection("matrix"),
        state: createQaBusState(),
      });

      try {
        expect(transport.requiredPluginIds).toEqual(["matrix"]);
        const matrixGatewayConfig = transport.createGatewayConfig({
          baseUrl: "http://127.0.0.1:1",
        }) as { channels?: { matrix?: Record<string, unknown> } };
        expect(matrixGatewayConfig).toMatchObject({
          channels: {
            matrix: {
              accessToken: expect.any(String),
              enabled: true,
              encryption: false,
              homeserver: expect.stringMatching(/^http:\/\/127\.0\.0\.1:\d+$/u),
              network: { dangerouslyAllowPrivateNetwork: true },
              userId: "@openclaw:matrix.test",
            },
          },
        });
        expect(matrixGatewayConfig.channels?.matrix?.streaming).toEqual({
          mode: "off",
          block: { enabled: false },
        });
        expect(matrixGatewayConfig.channels?.matrix?.blockStreaming).toBeUndefined();
        expect(transport.createRuntimeEnvPatch?.()).toMatchObject({
          MATRIX_ACCESS_TOKEN: expect.any(String),
          MATRIX_BASE_URL: expect.stringMatching(/^http:\/\/127\.0\.0\.1:\d+$/u),
          MATRIX_USER_ID: "@openclaw:matrix.test",
        });

        const roomId = "main";
        const delivery = transport.buildAgentDelivery({ target: `group:${roomId}` });
        expect(delivery).toEqual({
          channel: "matrix",
          replyChannel: "matrix",
          replyTo: expect.stringMatching(/^room:![a-f0-9]{16}:matrix-qa\.test$/u),
          to: expect.stringMatching(/^room:![a-f0-9]{16}:matrix-qa\.test$/u),
        });
        expect(transport.buildAgentDelivery({ target: "!qa:matrix.test" })).toEqual({
          channel: "matrix",
          replyChannel: "matrix",
          replyTo: "room:!qa:matrix.test",
          to: "room:!qa:matrix.test",
        });
        expect(transport.buildAgentDelivery({ target: "matrix:room:!qa:matrix.test" })).toEqual({
          channel: "matrix",
          replyChannel: "matrix",
          replyTo: "room:!qa:matrix.test",
          to: "room:!qa:matrix.test",
        });
        expect(
          transport.buildAgentDelivery({ target: "group:main", threadId: "$event:matrix.test" }),
        ).toMatchObject({
          channel: "matrix",
          threadId: "$event:matrix.test",
        });
        expect(() => transport.buildAgentDelivery({ target: "group:" })).toThrow(
          "invalid qa-channel group target",
        );
        expect(() =>
          transport.buildAgentDelivery({ target: "thread:main/$event:matrix.test" }),
        ).toThrow("Matrix thread targets require OpenClaw QA thread forwarding");
        await expect(
          transport.state.addInboundMessage({
            conversation: { id: "  ", kind: "group" },
            senderId: "driver",
            senderName: "Alice",
            text: "Matrix invalid blank room.",
          }),
        ).rejects.toThrow("Matrix QA conversation id must be non-empty");
        await expect(
          transport.state.addInboundMessage({
            conversation: { id: roomId, kind: "group" },
            senderId: "driver",
            senderName: "Alice",
            text: "Matrix baseline marker check.",
          }),
        ).resolves.toMatchObject({
          conversation: { id: roomId, kind: "group" },
          direction: "inbound",
          id: expect.stringMatching(/^\$[A-Za-z0-9_-]{43}$/u),
          senderId: "driver",
          text: "Matrix baseline marker check.",
        });
      } finally {
        await transport.cleanupAfterGatewayStop?.();
      }
    });
  });

  it("normalizes native Matrix room message sends into outbound state", async () => {
    await withTempDir("qa-crabline-transport-", async (outputDir) => {
      const transport = await createQaCrablineTransportAdapter({
        outputDir,
        selection: createSelection("matrix"),
        state: createQaBusState(),
      });

      try {
        const roomId = "main";
        await transport.state.addInboundMessage({
          conversation: { id: roomId, kind: "group" },
          senderId: "driver",
          senderName: "Alice",
          text: "Provision Matrix room.",
        });
        await transport.state.reset();
        const delivery = transport.buildAgentDelivery({ target: `group:${roomId}` });
        const providerRoomId = delivery.to.replace(/^room:/u, "");
        const env = transport.createRuntimeEnvPatch?.() ?? {};
        const matrixBaseUrl = requireString(env.MATRIX_BASE_URL, "Matrix base URL");
        const accessToken = requireString(env.MATRIX_ACCESS_TOKEN, "Matrix access token");
        const { response, release } = await fetchWithSsrFGuard({
          url: `${matrixBaseUrl}/_matrix/client/v3/rooms/${encodeURIComponent(providerRoomId)}/send/m.room.message/qa-matrix-send`,
          init: {
            body: JSON.stringify({ body: "assistant via fake matrix", msgtype: "m.text" }),
            headers: {
              authorization: `Bearer ${accessToken}`,
              "content-type": "application/json",
            },
            method: "PUT",
          },
          policy: { allowPrivateNetwork: true },
          auditContext: "qa-lab-crabline-matrix-transport-test",
        });
        await release();
        expect(response.ok).toBe(true);

        await expect(
          transport.waitForOutbound({
            conversation: { id: roomId, kind: "group" },
            textIncludes: "assistant via fake matrix",
            timeoutMs: 1_000,
          }),
        ).resolves.toMatchObject({
          conversation: { id: roomId, kind: "group" },
          text: "assistant via fake matrix",
        });
      } finally {
        await transport.cleanupAfterGatewayStop?.();
      }
    });
  });
});
