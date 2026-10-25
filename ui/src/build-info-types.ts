export type ControlUiBuildInfo = Readonly<{
  version: string | null;
  commit: string | null;
  commitAt: string | null;
  builtAt: string | null;
  branch: string | null;
  dirty: boolean | null;
  release: boolean;
  buildId: string;
  /** LanFu product version (lanfu.productVersion) stamped at packaging time.
   * Advisory identity for the About page; excluded from the build id. */
  productVersion?: string | null;
}>;
