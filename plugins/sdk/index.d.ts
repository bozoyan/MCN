export type Json =
  | null
  | boolean
  | number
  | string
  | Json[]
  | { [key: string]: Json };
export type JsonObject = { [key: string]: Json };
export interface ToolCall {
  readonly callId: string;
  readonly cancelled: boolean;
}
export interface ToolDisplay {
  title?: string;
  summaryArg?: string;
  result?: "items" | "text" | "json";
  resultPath?: string;
}
export interface ToolRegistration {
  name: string;
  description: string;
  inputSchema: Json;
  display?: ToolDisplay;
  handler(input: JsonObject, call: ToolCall): Promise<JsonObject>;
}
/** Result of a settings-page action. */
export interface ActionResult {
  ok: boolean;
  /**
   * "unauthorized", "network" and "timeout" are shown with host wording;
   * any other code is shown as a generic failure.
   */
  code?: string;
  /** Written to the host log only; never shown to the user. */
  message?: string;
}
export interface HttpRequest {
  method?: "GET" | "POST" | "PUT" | "PATCH" | "DELETE" | "HEAD";
  headers?: Record<string, string>;
  body?: string;
  timeoutMs?: number;
  maxBytes?: number;
  responseType?: "text" | "base64";
}
export interface HttpResponse {
  status: number;
  url: string;
  headers: Record<string, string>;
  body: string;
}
export interface PluginContext {
  readonly plugin: { readonly id: string; readonly version: string };
  readonly tools: { register(tool: ToolRegistration): void };
  /**
   * Handlers for actions declared in plugin.json `actions`. Every declared
   * action must be registered. While an action runs, settings.get and
   * secrets.get return the unsaved values from the settings form.
   */
  readonly actions: {
    register(
      name: string,
      handler: (call: ToolCall) => Promise<ActionResult>,
    ): void;
  };
  readonly http: {
    fetch(url: string, init?: HttpRequest): Promise<HttpResponse>;
  };
  readonly log: {
    info(message: string, data?: Json): void;
    warn(message: string, data?: Json): void;
    error(message: string, data?: Json): void;
  };
  /** Plugin storage calls fail explicitly until implemented by the host. */
  readonly storage: {
    get(key: string): Promise<Json | null>;
    set(key: string, value: Json): Promise<void>;
    remove(key: string): Promise<void>;
  };
  readonly settings: { get(key: string): Promise<Json | null> };
  readonly secrets: { get(key: string): Promise<string | null> };
}
export interface PluginHostError extends Error {
  readonly code: string;
}
