// Qa Lab plugin module implements Crabline channel-driver transport behavior against local provider servers.
import fs from "node:fs/promises";
import path from "node:path";
import {
  createOpenClawCrablineChannelReportNotes,
  runOpenClawCrablineProviderReadiness,
  startOpenClawCrablineAdapter,
  type OpenClawCrablineChannelDriverSelection,
  type OpenClawCrablineInbound,
  type StartedOpenClawCrablineCorrelatedAdapter,
} from "@openclaw/crabline";
import type { OpenClawConfig } from "openclaw/plugin-sdk/config-contracts";
import { fetchWithSsrFGuard } from "openclaw/plugin-sdk/ssrf-runtime";
import { isRecord, readStringValue } from "openclaw/plugin-sdk/string-coerce-runtime";
import { createQaBusState, type QaBusState } from "./bus-state.js";
import {
  createCrablineProviderCorrelation,
  createCrablineProviderDelivery,
  createCrablineProviderInboundInput,
  resolveCrablineStateConversation,
} from "./crabline-provider-targets.js";
import { readQaJsonResponse } from "./ignored-response-body.js";
import { buildQaConversationTarget, parseQaTarget } from "./qa-bus-protocol.js";
import {
  QaStateBackedTransportAdapter,
  type QaTransportActionName,
  type QaTransportGatewayConfig,
  type QaTransportPolicy,
  type QaTransportReportParams,
  type QaTransportState,
  waitForQaTransportAccountReady,
} from "./qa-transport.js";
import type { QaBusInboundMessageInput, QaBusOutboundMessageInput } from "./runtime-api.js";

type QaCrablineTransportState = QaTransportState & {
  cleanup: () => Promise<void>;
  observeEvent: (event: unknown) => void;
  rememberProviderTarget: (providerTargetKey: string, target: QaCrablineTarget) => void;
  resetTransport: () => void;
};

type QaCrablineTarget = Pick<QaBusInboundMessageInput, "conversation" | "threadId">;

function qaTargetForInput(input: QaBusInboundMessageInput): QaCrablineTarget {
  return {
    conversation: { ...input.conversation },
    ...(input.threadId ? { threadId: input.threadId } : {}),
  };
}

async function postCrablineInbound(params: {
  adapter: StartedOpenClawCrablineCorrelatedAdapter;
  providerInbound: OpenClawCrablineInbound;
}) {
  const { response, release } = await fetchWithSsrFGuard({
    url: params.adapter.manifest.endpoints.adminInboundUrl,
    init: {
      body: JSON.stringify(params.providerInbound.providerBody),
      headers: {
        "content-type": "application/json",
        "x-crabline-admin-token": params.adapter.manifest.adminToken,
      },
      method: "POST",
    },
    policy: { allowPrivateNetwork: true },
    auditContext: `qa-lab-crabline-${params.adapter.channel}-inbound`,
  });
  const label = `Crabline ${params.adapter.channel} inbound injection failed`;
  const result = await readQaJsonResponse<unknown>(response, release, label);
  let providerMessageId: string | undefined;
  if (params.adapter.channel === "matrix" && isRecord(result) && isRecord(result.event)) {
    providerMessageId = readStringValue(result.event.event_id);
  }
  return { providerMessageId, response: result };
}

function createCrablineState(params: {
  adapter: StartedOpenClawCrablineCorrelatedAdapter;
  state: QaBusState;
}): QaCrablineTransportState {
  const baseState = params.state;
  const targetByProviderTarget = new Map<string, QaCrablineTarget>();
  const resetTransport = () => {
    targetByProviderTarget.clear();
  };

  return {
    reset() {
      resetTransport();
      baseState.reset();
    },
    resetTransport,
    getSnapshot: baseState.getSnapshot.bind(baseState),
    observeEvent(event) {
      const observation = params.adapter.createOutboundObservation({ event });
      const target = observation?.providerTargetKeys
        .map((key) => targetByProviderTarget.get(key))
        .find((candidate) => candidate !== undefined);
      const outbound: QaBusOutboundMessageInput | null = observation
        ? target
          ? {
              accountId: observation.accountId,
              senderId: observation.senderId,
              senderName: observation.senderName,
              text: observation.text,
              to: buildQaConversationTarget({
                chatType: target.conversation.kind,
                conversationId: target.conversation.id,
              }),
              threadId: target.threadId,
            }
          : observation.fallbackTarget
            ? {
                accountId: observation.accountId,
                senderId: observation.senderId,
                senderName: observation.senderName,
                text: observation.text,
                to: observation.fallbackTarget,
              }
            : null
        : null;
      if (outbound) {
        baseState.addOutboundMessage(outbound);
      }
    },
    async addInboundMessage(input: QaBusInboundMessageInput) {
      const providerInbound = params.adapter.createInbound({
        input: createCrablineProviderInboundInput(params.adapter, input),
      });
      const ingress = await postCrablineInbound({
        adapter: params.adapter,
        providerInbound,
      });
      // Register only the provider identity confirmed by successful ingress. Provider servers may
      // realize a symbolic target as a different native conversation than the provisional input.
      targetByProviderTarget.set(
        params.adapter.resolveInboundProviderTargetKey({
          inbound: providerInbound,
          response: ingress.response,
        }),
        qaTargetForInput(input),
      );
      return baseState.addInboundMessage(
        {
          ...input,
          conversation: resolveCrablineStateConversation({
            adapter: params.adapter,
            input,
            providerInbound,
          }),
        },
        ingress.providerMessageId,
      );
    },
    rememberProviderTarget(providerTargetKey, target) {
      targetByProviderTarget.set(providerTargetKey, target);
    },
    addOutboundMessage: baseState.addOutboundMessage.bind(baseState),
    readMessage: baseState.readMessage.bind(baseState),
    searchMessages: baseState.searchMessages.bind(baseState),
    waitFor: baseState.waitFor.bind(baseState),
    async cleanup() {
      await params.adapter.close();
    },
  };
}

class QaCrablineTransport extends QaStateBackedTransportAdapter {
  readonly #adapter: StartedOpenClawCrablineCorrelatedAdapter;
  readonly #selection: OpenClawCrablineChannelDriverSelection;
  readonly #state: QaCrablineTransportState;
  readonly resetTransport: () => void;

  constructor(params: {
    adapter: StartedOpenClawCrablineCorrelatedAdapter;
    selection: OpenClawCrablineChannelDriverSelection;
    state: QaCrablineTransportState;
  }) {
    super({
      id: "crabline",
      label: `crabline local ${params.selection.channel}`,
      accountId: params.adapter.accountId,
      requiredPluginIds: params.adapter.requiredPluginIds,
      state: params.state,
    });
    this.#adapter = params.adapter;
    this.#selection = params.selection;
    this.#state = params.state;
    this.resetTransport = params.state.resetTransport;
  }

  createGatewayConfig = (params: { baseUrl: string }): QaTransportGatewayConfig =>
    this.#adapter.createGatewayConfig(params) as QaTransportGatewayConfig;

  waitReady = (params: Parameters<QaStateBackedTransportAdapter["waitReady"]>[0]) =>
    waitForQaTransportAccountReady({
      ...params,
      accountId: this.#adapter.accountId,
      channel: this.#adapter.channel,
    });

  buildAgentDelivery = ({ target, threadId }: { target: string; threadId?: string }) => {
    const parsed = parseQaTarget(target);
    if (parsed.threadId && threadId && parsed.threadId !== threadId) {
      throw new Error("Crabline delivery received conflicting thread targets");
    }
    const logicalTarget = {
      conversation: { id: parsed.conversationId, kind: parsed.chatType },
      threadId: threadId ?? parsed.threadId,
    };
    // Matrix and Mattermost require OpenClaw to forward threads separately at the
    // Gateway request boundary instead of passing them into Crabline delivery setup.
    const providerThreadId =
      this.#selection.channel === "matrix" || this.#selection.channel === "mattermost"
        ? undefined
        : logicalTarget.threadId;
    const { delivery, providerTargetKey } = createCrablineProviderDelivery(
      this.#adapter,
      target,
      providerThreadId,
    );
    let deliveryThreadId = logicalTarget.threadId;
    if (providerThreadId === undefined && logicalTarget.threadId) {
      const providerCorrelation = createCrablineProviderCorrelation(this.#adapter, logicalTarget);
      this.#state.rememberProviderTarget(providerTargetKey, {
        conversation: logicalTarget.conversation,
      });
      this.#state.rememberProviderTarget(providerCorrelation.providerTargetKey, logicalTarget);
      if (this.#selection.channel === "mattermost") {
        if (!providerCorrelation.threadId) {
          throw new Error("Crabline Mattermost correlation did not resolve a native thread root");
        }
        deliveryThreadId = providerCorrelation.threadId;
      }
    } else {
      this.#state.rememberProviderTarget(providerTargetKey, logicalTarget);
    }
    return {
      ...delivery,
      ...(deliveryThreadId ? { threadId: deliveryThreadId } : {}),
    };
  };

  createRuntimeEnvPatch = () => this.#adapter.createProviderReadinessEnv({});

  handleAction = async (_params: {
    action: QaTransportActionName;
    args: Record<string, unknown>;
    cfg: OpenClawConfig;
    accountId?: string | null;
  }) => {
    throw new Error(`Crabline channel-driver transport does not support ${_params.action} yet.`);
  };

  createReportNotes = (_params: QaTransportReportParams) => [
    `Runs OpenClaw's ${this.#selection.channel} channel plugin against a Crabline local provider server.`,
    "No live channel service or external credential lease is required.",
  ];

  captureArtifacts = async ({ outputDir }: { outputDir: string }) => {
    const readiness = await runOpenClawCrablineProviderReadiness({
      adapter: this.#adapter,
      outputDir,
      selection: this.#selection,
    });
    return {
      artifacts: [
        {
          kind: "channel-capability-matrix" as const,
          path: readiness.capabilityMatrixPath,
        },
        {
          kind: "channel-driver-smoke" as const,
          path: readiness.providerReadinessArtifactPath,
        },
      ],
      reportNotes: createOpenClawCrablineChannelReportNotes(this.#selection),
    };
  };

  async cleanupAfterGatewayStop() {
    await this.#state.cleanup();
  }
}

export async function createQaCrablineTransportAdapter(params: {
  outputDir: string;
  transportPolicy?: QaTransportPolicy;
  selection: OpenClawCrablineChannelDriverSelection;
  state?: QaBusState;
}) {
  const requiresGroupPolicy =
    params.transportPolicy?.requireGroupMention === true ||
    params.transportPolicy?.senderAllowlist !== undefined;
  if (requiresGroupPolicy) {
    throw new Error(
      `Crabline ${params.selection.channel} does not support the requested group transport policy; use a live channel adapter`,
    );
  }
  const recorderPath = path.join(
    params.outputDir,
    "artifacts",
    "crabline",
    `${params.selection.channel}-provider-server.jsonl`,
  );
  await fs.mkdir(path.dirname(recorderPath), { recursive: true });
  let observeEvent = (_event: unknown) => {};
  const adapter = await startOpenClawCrablineAdapter({
    channel: params.selection.channel,
    onEvent: (event) => observeEvent(event),
    openclawConfig: {},
    recorderPath,
  });

  const state = createCrablineState({
    adapter,
    state: params.state ?? createQaBusState(),
  });
  observeEvent = state.observeEvent;
  return new QaCrablineTransport({
    adapter,
    selection: params.selection,
    state,
  });
}

export async function createQaCrablineTransportDefinition(
  params: Parameters<typeof createQaCrablineTransportAdapter>[0],
) {
  const transport = await createQaCrablineTransportAdapter(params);
  return {
    id: transport.id,
    label: transport.label,
    accountId: transport.accountId,
    requiredPluginIds: transport.requiredPluginIds,
    supportedActions: transport.supportedActions,
    sendInbound: transport.sendInbound.bind(transport),
    createGatewayConfig: transport.createGatewayConfig,
    waitReady: transport.waitReady,
    buildAgentDelivery: transport.buildAgentDelivery,
    handleAction: transport.handleAction,
    createReportNotes: transport.createReportNotes,
    resetTransport: transport.resetTransport,
    ...(transport.createRuntimeEnvPatch
      ? { createRuntimeEnvPatch: transport.createRuntimeEnvPatch }
      : {}),
    captureArtifacts: transport.captureArtifacts,
    cleanupAfterGatewayStop: transport.cleanupAfterGatewayStop.bind(transport),
  };
}
