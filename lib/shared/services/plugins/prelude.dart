// 职责: 生成插件注册、调用与 JSON 桥接的受限上下文。
// 关联文件:
//   lib/shared/services/plugins/host.dart
import 'dart:convert';

String pluginPrelude(String id, String version) =>
    r'''
const __handlers = Object.create(null);
const __actions = Object.create(null);
let __registering = true;
let __registrationError = null;
const __pendingRegistrations = [];
class PluginHostError extends Error {
  constructor(code, message) { super(message); this.name = "PluginHostError"; this.code = code; }
}
async function __bridge(message) {
  const reply = JSON.parse(await fjs.bridge_call(JSON.stringify(message)));
  if (!reply.ok) throw new PluginHostError(reply.code, reply.error);
  return reply.result;
}
function __call(method, args) {
  if (__registering) { __registrationError = 'Host API unavailable during apply'; throw new Error(__registrationError); }
  return __bridge({kind:'call', method, args});
}
const context = Object.freeze({
  plugin: Object.freeze(__IDENTITY__),
  tools: Object.freeze({register(tool) {
    if (!__registering) throw new Error('Registration is closed');
    if (typeof tool.handler !== 'function' || __handlers[tool.name]) {
      __registrationError = 'Invalid or duplicate handler'; throw new Error(__registrationError);
    }
    const {handler, ...definition} = tool;
    __handlers[tool.name] = handler;
    __pendingRegistrations.push(__bridge({kind:'register', definition}));
  }}),
  actions: Object.freeze({register(name, handler) {
    if (!__registering) throw new Error('Registration is closed');
    if (typeof name !== 'string' || typeof handler !== 'function' || __actions[name]) {
      __registrationError = 'Invalid or duplicate action'; throw new Error(__registrationError);
    }
    __actions[name] = handler;
    __pendingRegistrations.push(__bridge({kind:'register', action: name}));
  }}),
  http: Object.freeze({fetch(url, init = {}) {return __call('http.fetch', {url, ...init});}}),
  log: Object.freeze(Object.fromEntries(['info','warn','error'].map(level => [level, (message, data) => __call('log.' + level, {message, data})]))),
  storage: Object.freeze({get() {return __call('storage.get', {});}, set() {return __call('storage.set', {});}, remove() {return __call('storage.remove', {});}}),
  settings: Object.freeze({get(key) {return __call('settings.get', {key});}}),
  secrets: Object.freeze({get(key) {return __call('secrets.get', {key});}})
});
async function __apply() {
  try {
    if (typeof __revericPlugin?.apply !== 'function') throw new Error('Missing apply');
    await __revericPlugin.apply(context);
    await Promise.all(__pendingRegistrations);
    if (__registrationError) throw new Error(__registrationError);
    await __bridge({kind: "register", complete: true});
  } finally { __registering = false; }
}
'''
        .replaceFirst(
          '__IDENTITY__',
          jsonEncode({'id': id, 'version': version}),
        );
String pluginInvokeAction(String action, String callId) =>
    '''
try {
  await __apply();
  const value = await __actions[${jsonEncode(action)}](Object.freeze({callId:${jsonEncode(callId)},cancelled:false}));
  await __bridge({kind:'result', value});
} catch (error) {
  await __bridge({kind:'result', error:String(error) + '\\n' + String(error.stack || ''), code:error.code});
}
''';
String pluginInvoke(String? tool, Map<String, dynamic> input, String callId) =>
    '''
try {
  await __apply();
  const value = ${tool == null ? 'null' : 'await __handlers[${jsonEncode(tool)}](${jsonEncode(input)}, Object.freeze({callId:${jsonEncode(callId)},cancelled:false}))'};
  await __bridge({kind:'result', value});
} catch (error) {
  await __bridge({kind:'result', error:String(error) + '\\n' + String(error.stack || ''), code:error.code});
}
''';
