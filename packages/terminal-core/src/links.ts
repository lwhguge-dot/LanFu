export function formatDocsLink(
  _path: string | undefined | null,
  _label?: string,
  _opts?: { fallback?: string; force?: boolean },
): string {
  // LanFu intranet build: the upstream public docs site is not reachable for
  // employees, so docs links render as nothing.
  return "";
}
