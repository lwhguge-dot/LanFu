/* @vitest-environment jsdom */

import type { LitElement } from "lit";
import { afterEach, expect, it } from "vitest";
import { setCurrentThemeBranding } from "../app/theme-branding.ts";
import "./lanfu-mark.ts";

afterEach(() => {
  document.body.replaceChildren();
  delete document.documentElement.dataset.themeMascot;
  setCurrentThemeBranding({ mascot: "claw", critters: [] });
});

it("renders the approved LanFu circular mark and swaps to the neutral mark", async () => {
  setCurrentThemeBranding({ mascot: "claw", critters: [] });
  const mascot = document.createElement("lanfu-mark") as LitElement & { size: number };
  mascot.size = 48;
  document.body.append(mascot);
  await mascot.updateComplete;

  const mark = mascot.shadowRoot?.querySelector("img");
  expect(mark).not.toBeNull();
  expect(mark?.getAttribute("src")).toBe("/lanfu-mark.png");
  expect(mascot.shadowRoot?.querySelector("canvas")).toBeNull();
  expect(mascot.style.getPropertyValue("--lanfu-mark-size")).toBe("48px");

  setCurrentThemeBranding({ mascot: "none", critters: [] });
  document.documentElement.dataset.themeMascot = "none";
  await Promise.resolve();
  await mascot.updateComplete;
  expect(mascot.shadowRoot?.querySelector("img")).toBeNull();
  expect(mascot.shadowRoot?.querySelector(".lanfu-mark--neutral svg")).not.toBeNull();

  setCurrentThemeBranding({ mascot: "claw", critters: [] });
  document.documentElement.dataset.themeMascot = "claw";
  await Promise.resolve();
  await mascot.updateComplete;
  expect(mascot.shadowRoot?.querySelector("img")).not.toBeNull();
});
