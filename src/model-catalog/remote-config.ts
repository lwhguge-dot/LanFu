import type { OpenClawConfig } from "../config/types.openclaw.js";

const DEFAULT_REMOTE_MODEL_CATALOG_URL = "https://catalog.openclaw.ai/models/v1/catalog.json";

export function isRemoteModelCatalogRefreshEnabled(config: OpenClawConfig): boolean {
  return config.models?.catalogRefresh?.enabled !== false;
}

// LanFu: fetching a catalog over the network is opt-in only; the bundled
// catalog ships in-product, and local overlay/pricing reads of cached data
// keep their original default via isRemoteModelCatalogRefreshEnabled.
export function isRemoteModelCatalogFetchEnabled(config: OpenClawConfig): boolean {
  return config.models?.catalogRefresh?.enabled === true;
}

export function resolveRemoteCatalogUrl(config: OpenClawConfig): string {
  return config.models?.catalogRefresh?.url?.trim() || DEFAULT_REMOTE_MODEL_CATALOG_URL;
}
