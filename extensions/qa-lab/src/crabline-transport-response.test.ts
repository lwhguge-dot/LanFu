// Qa Lab tests cover bounded Crabline provider responses and failed-body cleanup.
import type { OpenClawCrablineChannelDriverSelection } from "@openclaw/crabline";
import { withTempDir } from "openclaw/plugin-sdk/test-env";
import { afterEach, describe, expect, it, vi } from "vitest";
import { createQaBusState } from "./bus-state.js";
import { createQaCrablineTransportAdapter } from "./crabline-transport.js";

afterEach(() => {
  vi.unstubAllGlobals();
});

function createSelection() {
  return {
    capabilityMatrixPath: "crabline-channel-driver-capabilities.json",
    channel: "matrix",
    channelDriver: "crabline",
    providerReadinessArtifactPath: "crabline-provider-readiness.json",
  } as const satisfies OpenClawCrablineChannelDriverSelection;
}

describe("crabline transport responses", () => {
  it("rejects oversized successful inbound responses before parsing provider metadata", async () => {
    await withTempDir("qa-crabline-transport-", async (outputDir) => {
      const transport = await createQaCrablineTransportAdapter({
        outputDir,
        selection: createSelection(),
        state: createQaBusState(),
      });
      vi.stubGlobal(
        "fetch",
        vi.fn(
          async () =>
            new Response(
              JSON.stringify({
                update: { message: { message_id: 42, padding: "x".repeat(1024 * 1024) } },
              }),
            ),
        ),
      );

      try {
        await expect(
          transport.sendInbound({
            conversation: { id: "main", kind: "group" },
            senderId: "driver",
            senderName: "Alice",
            text: "Oversized response marker.",
          }),
        ).rejects.toThrow("JSON response exceeds 1048576 bytes");
      } finally {
        await transport.cleanupAfterGatewayStop();
      }
    });
  });

  it("cancels a failed inbound response before surfacing the provider error", async () => {
    await withTempDir("qa-crabline-transport-", async (outputDir) => {
      const transport = await createQaCrablineTransportAdapter({
        outputDir,
        selection: createSelection(),
        state: createQaBusState(),
      });
      const cancel = vi.fn(() => {
        throw new Error("cancel failed");
      });
      vi.stubGlobal(
        "fetch",
        vi.fn(
          async () =>
            new Response(new ReadableStream<Uint8Array>({ cancel }), {
              status: 503,
            }),
        ),
      );

      try {
        await expect(
          transport.sendInbound({
            conversation: { id: "main", kind: "group" },
            senderId: "driver",
            senderName: "Alice",
            text: "Matrix failure marker.",
          }),
        ).rejects.toThrow("Crabline matrix inbound injection failed with HTTP 503");
        expect(cancel).toHaveBeenCalledOnce();
      } finally {
        await transport.cleanupAfterGatewayStop();
      }
    });
  });
});
