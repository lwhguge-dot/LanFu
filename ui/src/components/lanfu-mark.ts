import { css, html, LitElement, type PropertyValues } from "lit";
import { property } from "lit/decorators.js";
import { currentThemeBranding, neutralMark } from "./neutral-mark.ts";

const DEFAULT_SIZE = 120;
const LANFU_MARK_SRC = "/lanfu-mark.png";

/**
 * Shared LanFu identity mark.
 *
 * The mark is intentionally static: it uses the approved blue circular LanFu
 * logo rather than the former animated cartoon mascot. Mood/tease remain part
 * of the public component contract so existing surfaces can migrate without
 * changing their templates.
 */
class LanFuMark extends LitElement {
  static override styles = css`
    :host {
      display: inline-block;
      width: var(--lanfu-mark-size, 120px);
      height: var(--lanfu-mark-size, 120px);
      overflow: visible;
      contain: layout style;
      pointer-events: none;
      line-height: 0;
    }

    img,
    .lanfu-mark--neutral,
    .lanfu-mark--neutral svg {
      display: block;
      width: 100%;
      height: 100%;
    }

    img {
      object-fit: contain;
      user-select: none;
    }
  `;

  @property({ reflect: true }) mood = "idle";
  @property({ type: Number }) size = DEFAULT_SIZE;
  @property({ type: Boolean }) tease = false;

  private themeObserver: MutationObserver | null = null;

  override connectedCallback(): void {
    super.connectedCallback();
    this.setAttribute("aria-hidden", "true");
    if (typeof MutationObserver !== "undefined") {
      this.themeObserver = new MutationObserver(() => this.requestUpdate());
      this.themeObserver.observe(document.documentElement, {
        attributes: true,
        attributeFilter: ["data-theme-mascot"],
      });
    }
  }

  override disconnectedCallback(): void {
    this.themeObserver?.disconnect();
    this.themeObserver = null;
    super.disconnectedCallback();
  }

  protected override updated(changed: PropertyValues<this>): void {
    if (changed.has("size")) {
      this.style.setProperty("--lanfu-mark-size", `${this.resolvedSize}px`);
    }
  }

  /** Kept as a compatibility no-op for callers that previously triggered animation. */
  catchOnce(): void {
    // The approved LanFu logo is static by design.
  }

  override render() {
    return currentThemeBranding().mascot === "none"
      ? html`<span class="lanfu-mark--neutral">${neutralMark}</span>`
      : html`<img src=${LANFU_MARK_SRC} alt="" draggable="false" />`;
  }

  private get resolvedSize(): number {
    return Number.isFinite(this.size) && this.size > 0 ? this.size : DEFAULT_SIZE;
  }
}

if (!customElements.get("lanfu-mark")) {
  customElements.define("lanfu-mark", LanFuMark);
}
