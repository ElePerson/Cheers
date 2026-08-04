import { describe, expect, it } from "vitest";
import { parseCfg } from "./WorkbenchDrawer";

describe("workbench scene config", () => {
  it("preserves native multi-scene navigation state", () => {
    const config = parseCfg(JSON.stringify({
      environment: "cheers-code-project",
      bindings: { "dev/plan.yaml": "builtin:kanban" },
      scene_state: {
        version: 1,
        order: ["cheers-code-project", "cheers-research-lab"],
        titles: {
          "cheers-code-project": "Code project",
          "cheers-research-lab": "Research lab",
        },
        items: {
          "cheers-code-project": ["dev/plan.yaml"],
          "cheers-research-lab": ["lab/experiments.yaml"],
        },
      },
    }));

    expect(config.scene_state?.order).toEqual([
      "cheers-code-project",
      "cheers-research-lab",
    ]);
    expect(config.scene_state?.items["cheers-code-project"]).toEqual(["dev/plan.yaml"]);
  });
});
