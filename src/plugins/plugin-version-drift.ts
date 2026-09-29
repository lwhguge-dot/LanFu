// Detects plugin version drift between config, manifests, and installs.
import type { OpenClawConfig } from "../config/types.js";
import type { PluginInstallRecord } from "../config/types.plugins.js";
import { parseClawHubPluginSpec } from "../infra/clawhub-spec.js";
import {
  parseRegistryNpmSpec,
  resolveOpenClawReleaseCohortVersion,
} from "../infra/npm-registry-spec.js";
import {
  normalizeUpdateChannel,
  resolveRegistryUpdateChannel,
  type UpdateChannel,
} from "../infra/update-channels.js";
import { normalizePluginsConfig, resolveEffectiveEnableState } from "./config-state.js";
import {
  resolveTrustedSourceLinkedOfficialClawHubInstall,
  resolveTrustedSourceLinkedOfficialNpmSpec,
} from "./official-external-install-records.js";

type PluginVersionDriftTargetResolution = {
  packageName: string;
  requestedTarget: string;
} & (
  | { status: "resolved"; version: string }
  /** The registry already serves `version`; no newer release exists to install. */
  | { status: "registry-current"; version: string }
  | { status: "unresolved"; error: string }
);

type PluginVersionDriftEntry = {
  pluginId: string;
  installedVersion: string;
  gatewayVersion: string;
  source: PluginInstallRecord["source"];
  packageName?: string;
  spec?: string;
  /** ClawHub package name for installs whose upgrade target lives in ClawHub, not npm. */
  clawhubPackage?: string;
  /** Catalog ClawHub spec, so a stale recorded pin resolves the way an update would. */
  clawhubOfficialSpec?: string;
  clawhubUrl?: string;
  clawhubUpdateChannel?: UpdateChannel;
  targetResolution?: PluginVersionDriftTargetResolution;
};

export type PluginVersionDriftReport = {
  gatewayVersion: string;
  drifts: PluginVersionDriftEntry[];
};

export type PluginVersionRestartReadiness =
  | {
      status: "resolved";
      report: PluginVersionDriftReport;
      runningGatewayVersion?: string;
    }
  | {
      status: "unresolved";
      reason: string;
      runningGatewayVersion?: string;
    };

function resolveExactNpmPinPackageName(entry: PluginVersionDriftEntry): string | undefined {
  if (entry.source !== "npm" || !entry.spec) {
    return undefined;
  }
  const parsed = parseRegistryNpmSpec(entry.spec);
  if (parsed?.selectorKind !== "exact-version") {
    return undefined;
  }
  return parsed.name;
}

/** Exact npm pins need a registry-confirmed package@version target; id-only updates preserve pins. */
export function resolvePluginVersionDriftUpdateCommand(
  entry: PluginVersionDriftEntry,
): string | undefined {
  // An unresolved target has no command to offer; a registry-current target would
  // only reinstall the version already present.
  if (
    entry.source === "clawhub" &&
    (entry.targetResolution?.status === "unresolved" ||
      entry.targetResolution?.status === "registry-current")
  ) {
    return undefined;
  }
  const exactNpmPackageName = resolveExactNpmPinPackageName(entry);
  if (exactNpmPackageName) {
    if (
      entry.targetResolution?.status !== "resolved" ||
      entry.targetResolution.packageName !== exactNpmPackageName ||
      entry.targetResolution.requestedTarget !==
        resolveOpenClawReleaseCohortVersion(entry.gatewayVersion)
    ) {
      return undefined;
    }
    const exactNpmTarget = `${exactNpmPackageName}@${entry.targetResolution.version}`;
    if (parseRegistryNpmSpec(exactNpmTarget)?.selectorKind === "exact-version") {
      return `openclaw plugins update ${exactNpmTarget}`;
    }
    return undefined;
  }
  return `openclaw plugins update ${entry.pluginId}`;
}

/**
 * Reports the registry version an install already holds when ClawHub publishes nothing
 * newer, together with the Gateway version the diagnostic asked for.
 */
export function resolvePluginVersionDriftRegistryLag(
  entry: PluginVersionDriftEntry,
): { registryVersion: string; expectedVersion: string } | undefined {
  const targetResolution = entry.targetResolution;
  return targetResolution?.status === "registry-current"
    ? {
        registryVersion: targetResolution.version,
        expectedVersion: targetResolution.requestedTarget,
      }
    : undefined;
}

async function resolveEntryTarget(
  entry: PluginVersionDriftEntry,
): Promise<PluginVersionDriftEntry> {
  // LanFu: no upstream ClawHub/npm registry is reachable; drift reports
  // surface the mismatch itself and never resolve a repair target over the
  // network.
  return entry;
}

/** Resolve registry repair targets only for diagnostics that display repair guidance. */
export async function resolvePluginVersionDriftTargets(
  report: PluginVersionDriftReport,
): Promise<PluginVersionDriftReport> {
  return {
    ...report,
    drifts: await Promise.all(report.drifts.map(resolveEntryTarget)),
  };
}

function isPluginEnabled(config: OpenClawConfig | undefined, pluginId: string): boolean {
  const normalizedPluginConfig = normalizePluginsConfig(config?.plugins);
  return resolveEffectiveEnableState({
    id: pluginId,
    origin: "global",
    config: normalizedPluginConfig,
    rootConfig: config,
  }).enabled;
}

function shouldCompareOfficialInstallToGateway(params: {
  pluginId: string;
  record: PluginInstallRecord;
}): boolean {
  const officialNpmSpec = resolveTrustedSourceLinkedOfficialNpmSpec(params);
  if (officialNpmSpec) {
    return parseRegistryNpmSpec(officialNpmSpec)?.selectorKind !== "exact-version";
  }
  const officialClawHubInstall = resolveTrustedSourceLinkedOfficialClawHubInstall(params);
  if (officialClawHubInstall) {
    if (officialClawHubInstall.clawhubSpec) {
      return !parseClawHubPluginSpec(officialClawHubInstall.clawhubSpec)?.version;
    }
    return (
      parseRegistryNpmSpec(officialClawHubInstall.npmSpec ?? "")?.selectorKind !== "exact-version"
    );
  }
  return false;
}

export function hasOfficialPluginVersionCandidates(params: {
  installRecords: Record<string, PluginInstallRecord>;
  config?: OpenClawConfig;
}): boolean {
  return Object.entries(params.installRecords).some(
    ([pluginId, record]) =>
      Boolean(record) &&
      isPluginEnabled(params.config, pluginId) &&
      shouldCompareOfficialInstallToGateway({ pluginId, record }),
  );
}

/** Exact cohort targets shared by automatic updates and Doctor's drift repair. */
export function resolveOfficialPluginCohortNpmSpecs(params: {
  gatewayVersion: string;
  installRecords: Record<string, PluginInstallRecord>;
  config?: OpenClawConfig;
}): Record<string, string> {
  const version = resolveOpenClawReleaseCohortVersion(params.gatewayVersion);
  const specs: Record<string, string> = {};
  for (const [pluginId, record] of Object.entries(params.installRecords)) {
    if (
      record.source !== "npm" ||
      !isPluginEnabled(params.config, pluginId) ||
      !shouldCompareOfficialInstallToGateway({ pluginId, record })
    ) {
      continue;
    }
    const official = resolveTrustedSourceLinkedOfficialNpmSpec({ pluginId, record });
    const packageName = official ? parseRegistryNpmSpec(official)?.name : undefined;
    if (
      packageName &&
      parseRegistryNpmSpec(`${packageName}@${version}`)?.selectorKind === "exact-version"
    ) {
      specs[pluginId] = `${packageName}@${version}`;
    }
  }
  return specs;
}

/**
 * Compare active official external plugin installs against an OpenClaw host
 * version and return any mismatches.
 *
 * @param params.gatewayVersion The host version the plugins must match.
 * @param params.installRecords The full set of recorded plugin installs (as
 *   produced by `loadInstalledPluginIndexInstallRecords`).
 * @param params.config The merged daemon-side OpenClawConfig (optional).
 *   Plugins inactive under the effective activation policy are skipped.
 *
 * The returned `drifts` list is sorted by `pluginId` for stable output.
 */
export function detectPluginVersionDrift(params: {
  gatewayVersion: string;
  installRecords: Record<string, PluginInstallRecord>;
  config?: OpenClawConfig;
}): PluginVersionDriftReport {
  const { gatewayVersion, installRecords, config } = params;
  const normalizedGateway = resolveOpenClawReleaseCohortVersion(gatewayVersion);
  const drifts: PluginVersionDriftEntry[] = [];

  for (const [pluginId, record] of Object.entries(installRecords)) {
    if (!record) {
      continue;
    }
    if (!isPluginEnabled(config, pluginId)) {
      continue;
    }
    if (
      !shouldCompareOfficialInstallToGateway({
        pluginId,
        record,
      })
    ) {
      continue;
    }
    const installedVersion = record.resolvedVersion ?? record.version;
    if (!installedVersion) {
      // No version recorded for this install — nothing to compare against.
      // Don't fabricate drift; surface tooling (status.print) can flag this
      // separately if desired.
      continue;
    }
    if (resolveOpenClawReleaseCohortVersion(installedVersion) === normalizedGateway) {
      continue;
    }
    // Admission above bound the recorded identities to the official catalog.
    // The installed source owns its package even when the catalog only advertises npm.
    const clawhubPackage =
      record.source === "clawhub"
        ? (record.clawhubPackage?.trim() ?? parseClawHubPluginSpec(record.spec ?? "")?.name)
        : undefined;
    const clawhubOfficialSpec = clawhubPackage
      ? resolveTrustedSourceLinkedOfficialClawHubInstall({ pluginId, record })?.clawhubSpec
      : undefined;
    drifts.push({
      pluginId,
      installedVersion,
      gatewayVersion,
      source: record.source,
      ...(record.resolvedName ? { packageName: record.resolvedName } : {}),
      ...(record.spec ? { spec: record.spec } : {}),
      ...(clawhubPackage
        ? {
            clawhubPackage,
            ...(clawhubOfficialSpec ? { clawhubOfficialSpec } : {}),
            spec: record.spec ?? record.resolvedSpec ?? `clawhub:${clawhubPackage}`,
            clawhubUrl: record.clawhubUrl ?? "https://clawhub.ai",
            clawhubUpdateChannel:
              normalizeUpdateChannel(config?.update?.channel) ??
              resolveRegistryUpdateChannel({ currentVersion: gatewayVersion }),
          }
        : {}),
    });
  }

  drifts.sort((a, b) => a.pluginId.localeCompare(b.pluginId));

  return {
    gatewayVersion,
    drifts,
  };
}
