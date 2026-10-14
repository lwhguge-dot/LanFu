import {
  DEFAULT_AGENT_COMPACTION_RESERVE_TOKENS_FLOOR,
  parseNonNegativeByteSize,
  resolveCronStyleNow,
  resolveEffectiveCompactionReserveTokens,
  SILENT_REPLY_TOKEN,
  type MemoryFlushPlan,
  type OpenClawConfig,
} from "openclaw/plugin-sdk/memory-core-host-runtime-core";
import { resolveMemoryCoreNowMs } from "./time.js";

const DEFAULT_MEMORY_FLUSH_SOFT_TOKENS = 4000;
const DEFAULT_MEMORY_FLUSH_FORCE_TRANSCRIPT_BYTES = 2 * 1024 * 1024;

const MEMORY_FLUSH_TARGET_HINT =
  "只把值得长期保留的记忆写入 memory/YYYY-MM-DD.md（没有 memory/ 目录就创建）。记忆内容用简体中文书写。";
const MEMORY_FLUSH_APPEND_ONLY_HINT =
  "如果 memory/YYYY-MM-DD.md 已存在，只允许追加新内容，绝不覆盖已有条目。";
const MEMORY_FLUSH_READ_ONLY_HINT =
  "本次落盘过程中，把 MEMORY.md、DREAMS.md、SOUL.md、AGENTS.md 等工作区引导/参考文件视为只读；绝不改写、替换或编辑它们。";
const MEMORY_FLUSH_REQUIRED_HINTS = [
  MEMORY_FLUSH_TARGET_HINT,
  MEMORY_FLUSH_APPEND_ONLY_HINT,
  MEMORY_FLUSH_READ_ONLY_HINT,
];

const DEFAULT_MEMORY_FLUSH_PROMPT = [
  "压缩前的记忆落盘。",
  MEMORY_FLUSH_TARGET_HINT,
  MEMORY_FLUSH_READ_ONLY_HINT,
  MEMORY_FLUSH_APPEND_ONLY_HINT,
  "不要创建带时间戳的变体文件（如 YYYY-MM-DD-HHMM.md）；始终使用规范的 YYYY-MM-DD.md 文件名。",
  `如果没有值得保存的内容，回复 ${SILENT_REPLY_TOKEN}。`,
].join(" ");

const DEFAULT_MEMORY_FLUSH_SYSTEM_PROMPT = [
  "压缩前的记忆落盘回合。",
  "会话即将自动压缩；把值得长期保留的记忆写入磁盘。",
  MEMORY_FLUSH_TARGET_HINT,
  MEMORY_FLUSH_READ_ONLY_HINT,
  MEMORY_FLUSH_APPEND_ONLY_HINT,
  `可以回复，但通常回复 ${SILENT_REPLY_TOKEN} 即可。`,
].join(" ");

function formatDateStampInTimezone(nowMs: number, timezone: string): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date(nowMs));
  const year = parts.find((part) => part.type === "year")?.value;
  const month = parts.find((part) => part.type === "month")?.value;
  const day = parts.find((part) => part.type === "day")?.value;
  if (year && month && day) {
    return `${year}-${month}-${day}`;
  }
  return new Date(resolveMemoryCoreNowMs(nowMs)).toISOString().slice(0, 10);
}

function normalizeNonNegativeInt(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return null;
  }
  const int = Math.floor(value);
  return int >= 0 ? int : null;
}

function ensureNoReplyHint(text: string): string {
  if (text.includes(SILENT_REPLY_TOKEN)) {
    return text;
  }
  return `${text}\n\nIf no user-visible reply is needed, start with ${SILENT_REPLY_TOKEN}.`;
}

function ensureMemoryFlushSafetyHints(text: string): string {
  let next = text.trim();
  for (const hint of MEMORY_FLUSH_REQUIRED_HINTS) {
    if (!next.includes(hint)) {
      next = next ? `${next}\n\n${hint}` : hint;
    }
  }
  return next;
}

function appendCurrentTimeLine(text: string, timeLine: string): string {
  const trimmed = text.trimEnd();
  if (!trimmed) {
    return timeLine;
  }
  if (trimmed.includes("Current time:")) {
    return trimmed;
  }
  return `${trimmed}\n${timeLine}`;
}

export function buildMemoryFlushPlan(
  params: {
    cfg?: OpenClawConfig;
    nowMs?: number;
    contextWindowTokens?: number;
  } = {},
): MemoryFlushPlan | null {
  const resolved = params;
  const nowMs = resolveMemoryCoreNowMs(resolved.nowMs);
  const cfg = resolved.cfg;
  const defaults = cfg?.agents?.defaults?.compaction?.memoryFlush;
  if (defaults?.enabled === false) {
    return null;
  }

  let softThresholdTokens =
    normalizeNonNegativeInt(defaults?.softThresholdTokens) ?? DEFAULT_MEMORY_FLUSH_SOFT_TOKENS;
  const forceFlushTranscriptBytes =
    parseNonNegativeByteSize(defaults?.forceFlushTranscriptBytes) ??
    DEFAULT_MEMORY_FLUSH_FORCE_TRANSCRIPT_BYTES;
  let reserveTokensFloor = DEFAULT_AGENT_COMPACTION_RESERVE_TOKENS_FLOOR;
  const contextWindowTokens = normalizeNonNegativeInt(params.contextWindowTokens);
  if (contextWindowTokens !== null && contextWindowTokens > 0) {
    reserveTokensFloor = resolveEffectiveCompactionReserveTokens({
      contextTokenBudget: contextWindowTokens,
      reserveTokens: reserveTokensFloor,
    });
    softThresholdTokens = Math.min(
      softThresholdTokens,
      Math.floor((contextWindowTokens - reserveTokensFloor) / 2),
    );
  }

  const { timeLine, userTimezone } = resolveCronStyleNow(cfg ?? {}, nowMs);
  const dateStamp = formatDateStampInTimezone(nowMs, userTimezone);
  const relativePath = `memory/${dateStamp}.md`;

  const promptBase = ensureNoReplyHint(ensureMemoryFlushSafetyHints(DEFAULT_MEMORY_FLUSH_PROMPT));
  const systemPrompt = ensureNoReplyHint(
    ensureMemoryFlushSafetyHints(DEFAULT_MEMORY_FLUSH_SYSTEM_PROMPT),
  );

  return {
    softThresholdTokens,
    forceFlushTranscriptBytes,
    reserveTokensFloor,
    model: defaults?.model?.trim() || undefined,
    prompt: appendCurrentTimeLine(promptBase.replaceAll("YYYY-MM-DD", dateStamp), timeLine),
    systemPrompt: systemPrompt.replaceAll("YYYY-MM-DD", dateStamp),
    relativePath,
  };
}
