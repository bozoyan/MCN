// 职责: 构造 Codemode 的隔离脚本 API、原生 JSON 序列化和显式输出确认流程。
// 关联文件:
//   lib/shared/services/ai/codemode/runtime.dart
//   lib/shared/agent/agent_tool_dispatcher.dart
import 'dart:convert';

/// Source and tool names are encoded as data; source is compiled inside an inner
/// async function, never interpolated into the trusted host wrapper's syntax.
String codemodePrelude(
  String source,
  List<String> toolNames, {
  required int inputBytes,
  required int outputBytes,
}) {
  // Keep API parameters outside the script's lexical scope, so local names can
  // shadow them. A fresh function also preserves script-level strict directives.
  final scriptBody = 'return (async function () {\n$source\n})();';
  return '''
(async () => {
  const parse = JSON.parse.bind(JSON);
  const stringify = JSON.stringify.bind(JSON);
  const keys = Object.keys.bind(Object);
  const proto = Object.getPrototypeOf.bind(Object);
  const descriptor = Object.getOwnPropertyDescriptor.bind(Object);
  const create = Object.create.bind(Object);
  const all = Promise.all.bind(Promise);
  const freeze = Object.freeze.bind(Object);
  const RangeErrorType = RangeError;
  const AsyncFunction = proto(async function() {}).constructor;
  const bridge = fjs.bridge_call.bind(fjs);
  const pendingOutput = [];
  const toolFailures = new WeakMap();
  const rememberToolFailure = toolFailures.set.bind(toolFailures);
  const readToolFailure = toolFailures.get.bind(toolFailures);
  let sequence = 0;
  let terminal = null;
  const failure = (code, details) => {
    const error = new Error(code);
    error.error_code = code;
    if (details) {
      for (const key of ['error', 'hint', 'recovery', 'result']) {
        if (descriptor(details, key)) error[key] = details[key];
      }
    }
    return error;
  };
  // Check the serialized tree, so getters/toJSON run only through JSON.stringify.
  const validateDepth = (value, depth = 0) => {
    if (depth > 64) throw failure('codemode_resource_limit');
    if (value !== null && typeof value === 'object') {
      for (const key of keys(value)) validateDepth(value[key], depth + 1);
    }
  };
  const bytes = (text) => {
    let size = 0;
    for (let i = 0; i < text.length; i++) {
      const c = text.charCodeAt(i);
      if (c < 128) size++;
      else if (c < 2048) size += 2;
      else if (c >= 0xd800 && c <= 0xdbff && i + 1 < text.length && text.charCodeAt(i + 1) >= 0xdc00 && text.charCodeAt(i + 1) <= 0xdfff) { size += 4; i++; }
      else size += 3;
    }
    return size;
  };
  const fatal = (code, diagnostics) => {
    terminal ??= code;
    const delivery = bridge(stringify({kind: 'output', sequence: ++sequence, error_code: code, diagnostics})).catch(() => {});
    pendingOutput.push(delivery);
    throw failure(code);
  };
  const depthFailure = (stage) => fatal('codemode_resource_limit', {
    failure_stage: stage, failure_reason: 'json_depth', limit: 64, observed: 65
  });
  const encode = (value, limit, stage) => {
    let json;
    try { json = stringify(value); }
    catch (error) {
      // Native stringify overflows the stack on deep trees before validateDepth runs.
      if (error instanceof RangeErrorType) return depthFailure(stage);
      return fatal('codemode_invalid_input', {
        failure_stage: stage, failure_reason: 'json_value'
      });
    }
    if (json === undefined) return undefined;
    const size = bytes(json);
    if (size > limit) return fatal('codemode_resource_limit', {
      failure_stage: stage, failure_reason: stage === 'tool_input' ? 'input_bytes' : 'output_bytes',
      limit, observed: size
    });
    try { validateDepth(parse(json)); }
    catch (_) { return depthFailure(stage); }
    return json;
  };
  const request = async (message) => {
    if (terminal) throw failure(terminal);
    const response = parse(await bridge(stringify(message)));
    if (!response.ok) {
      const error = failure(response.error_code, response);
      if (message.kind === 'tool') {
        // Keep an independent copy: scripts may annotate a caught Error before
        // rethrowing it, but that must not change the public tool diagnostic.
        rememberToolFailure(error, parse(stringify({tool: message.tool, ...response})));
      }
      throw error;
    }
    return response.result;
  };
  const toolNames = parse(${jsonEncode(jsonEncode(toolNames))});
  const toolFunctions = create(null);
  for (const name of toolNames) {
    toolFunctions[name] = (input) => request({kind: 'tool', tool: name, input: encode(input, $inputBytes, 'tool_input') ?? 'null'});
  }
  const tools = new Proxy(freeze(toolFunctions), {
    get(target, name) {
      if (typeof name !== 'string') return undefined;
      return target[name] || ((input, options) => request({kind: 'tool', tool: name, input: encode(input, $inputBytes, 'tool_input') ?? 'null', options: encode(options ?? {}, $inputBytes, 'tool_input')}));
    },
  });
  const discover = (method, input) => request({kind: 'discover', method, input: encode(input, $inputBytes, 'tool_input')});
  const listMcpServers = (options = {}) => discover('listMcpServers', options);
  const listTools = (options = {}) => discover('listTools', options);
  const searchTool = (query, options = {}) => discover('searchTool', {...options, query});
  const describeTool = (name) => discover('describeTool', {name});
  const text = (value) => {
    const json = encode(value, $outputBytes, 'output') ?? encode(String(value), $outputBytes, 'output');
    const delivery = request({kind: 'output', sequence: ++sequence, text: json});
    // Track rejection immediately; even a script that ignores text() cannot
    // create an unhandled bridge rejection or finish before accepted output.
    pendingOutput.push(delivery.catch((error) => { terminal ??= error.error_code; }));
  };
  try {
    const run = new AsyncFunction('tools', 'text', 'listMcpServers', 'listTools', 'searchTool', 'describeTool', ${jsonEncode(scriptBody)});
    const value = await run(tools, text, listMcpServers, listTools, searchTool, describeTool);
    const json = encode(value, $outputBytes, 'return_value');
    const hasReturn = json !== undefined;
    const result = hasReturn ? parse(json) : null;
    await all(pendingOutput);
    if (terminal) throw failure(terminal);
    return stringify({kind: 'codemode-result', ok: true, has_return: hasReturn, result});
  } catch (error) {
    await all(pendingOutput);
    const toolError = readToolFailure(error);
    if (toolError && !terminal) {
      return stringify({kind: 'codemode-result', ok: false, tool_error: toolError});
    }
    // Preserve native memory/stack classification after accepted output settles.
    throw error;
  }
})()
''';
}
