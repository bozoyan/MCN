import type { PluginContext } from "../../sdk/index";
import definitions from "./definitions.json";
import { webSearch } from "./search";
import { webFetch } from "./fetch";
export function apply(context: PluginContext): void {
  context.tools.register({
    ...definitions.WebSearch,
    display: { summaryArg: "query", result: "items", resultPath: "results" },
    handler: (input, call) => webSearch(context, input, call),
  });
  context.tools.register({
    ...definitions.WebFetch,
    display: { summaryArg: "url", result: "text", resultPath: "content" },
    handler: (input, call) => webFetch(context, input, call),
  });
}
