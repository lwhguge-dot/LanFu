/**
 * Compatibility subpath for bundled channel config schemas.
 *
 * Bundled channels own their config schemas through the manifest registry, so
 * this subpath only re-exports the generic primitives. New plugins should
 * import the primitives from openclaw/plugin-sdk/channel-config-schema
 * directly.
 */

export {
  AllowFromListSchema,
  ChannelGroupEntrySchema,
  BlockStreamingCoalesceSchema,
  buildCatchallMultiAccountChannelSchema,
  buildChannelConfigSchema,
  buildNestedDmConfigSchema,
  buildGroupEntrySchema,
  buildMultiAccountChannelSchema,
  ContextVisibilityModeSchema,
  DmConfigSchema,
  DmPolicySchema,
  GroupPolicySchema,
  MarkdownConfigSchema,
  ReplyRuntimeConfigSchemaShape,
  requireAllowlistAllowFrom,
  requireOpenAllowFrom,
  ToolPolicySchema,
} from "./channel-config-schema.js";
