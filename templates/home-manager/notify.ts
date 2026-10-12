// Minimal Pi extension: registers /notify and announces the session.
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.registerCommand("notify", {
    description: "Send a desktop notification with the session summary",
    handler: async (_args, ctx) => {
      ctx.notify({ title: "Pi", body: "Session finished" });
    },
  });
}
