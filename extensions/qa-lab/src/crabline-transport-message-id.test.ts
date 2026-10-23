import { withTempDir } from "openclaw/plugin-sdk/test-env";
import { describe, expect, it } from "vitest";
import { createQaBusState } from "./bus-state.js";
import { createQaCrablineTransportAdapter } from "./crabline-transport.js";

const PROVIDER_CASES = [
  {
    channel: "matrix",
    conversation: { id: "main", kind: "group" },
    senderId: "driver",
    nativeMessageId: /^\$[A-Za-z0-9_-]{43}$/u,
  },
] as const;

describe("Crabline provider-native inbound message identity", () => {
  it.each(PROVIDER_CASES)(
    "keeps $channel message IDs consistent across the returned message and bus state",
    async ({ channel, conversation, senderId, nativeMessageId }) => {
      await withTempDir("qa-crabline-message-id-", async (outputDir) => {
        const busState = createQaBusState();
        const transport = await createQaCrablineTransportAdapter({
          outputDir,
          selection: {
            capabilityMatrixPath: "crabline-channel-driver-capabilities.json",
            channel,
            channelDriver: "crabline",
            providerReadinessArtifactPath: "crabline-provider-readiness.json",
          },
          state: busState,
        });

        try {
          const inbound = await transport.sendInbound({
            conversation,
            senderId,
            senderName: "Alice",
            text: `${channel} provider-native identity`,
          });
          const snapshot = transport.state.getSnapshot();

          expect(inbound.id).toMatch(nativeMessageId);
          expect(snapshot.messages).toContainEqual(
            expect.objectContaining({ direction: "inbound", id: inbound.id }),
          );
          expect(snapshot.events).toContainEqual(
            expect.objectContaining({
              kind: "inbound-message",
              message: expect.objectContaining({ id: inbound.id }),
            }),
          );
          expect(busState.poll().events).toContainEqual(
            expect.objectContaining({
              kind: "inbound-message",
              message: expect.objectContaining({ id: inbound.id }),
            }),
          );
          expect(transport.state.readMessage({ messageId: inbound.id })).toMatchObject({
            direction: "inbound",
            id: inbound.id,
          });
        } finally {
          await transport.cleanupAfterGatewayStop?.();
        }
      });
    },
  );
});
