// 职责: 使用独立协议替身验证实际 stdio 与 HTTP 的分页发现和调用。
// 关联文件:
//   lib/shared/services/mcp/client_adapter.dart
//   lib/shared/models/mcp/config.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart' as sdk;
// ignore: implementation_imports
import 'package:mcp_dart/src/types/json_rpc.dart' as meta_validation;
import 'package:reveric/shared/models/mcp/config.dart';
import 'package:reveric/shared/services/mcp/client_adapter.dart';
import 'package:reveric/shared/services/mcp/runtime.dart';
import 'package:reveric/shared/services/mcp/diagnostics.dart';
import 'package:reveric/shared/services/mcp/tool_dispatcher.dart';
import 'package:reveric/shared/models/mcp/call_result.dart';

Map<String, dynamic>? reply(
  Map<String, dynamic> request, {
  bool modern = false,
}) {
  if (!request.containsKey('id')) {
    return null;
  }
  final result = switch (request['method']) {
    'server/discover' when modern => {
      'resultType': 'complete',
      'supportedVersions': ['2026-07-28'],
      'capabilities': {'tools': {}},
      'ttlMs': 0,
      'cacheScope': 'private',
      '_meta': {
        'io.modelcontextprotocol/serverInfo': {
          'name': 'fixture',
          'version': '1',
        },
      },
    },
    'initialize' => {
      'protocolVersion': '2025-11-25',
      'capabilities': {'tools': {}},
      'serverInfo': {'name': 'fixture', 'version': '1'},
    },
    'tools/list' => {
      'tools': [
        {
          'name': request['params']?['cursor'] == null ? 'first' : 'second',
          'inputSchema': {'type': 'object', 'properties': {}},
        },
      ],
      if (request['params']?['cursor'] == null) 'nextCursor': 'page2',
    },
    'tools/call' => {
      'content': [
        {'type': 'text', 'text': 'called'},
      ],
    },
    _ => null,
  };
  return {
    'jsonrpc': '2.0',
    'id': request['id'],
    if (result != null)
      'result': {
        ...result,
        if (modern) 'resultType': 'complete',
        if (modern && request['method'] == 'tools/list') ...{
          'ttlMs': 0,
          'cacheScope': 'private',
        },
      }
    else
      'error': {'code': -32601, 'message': 'Method not found'},
  };
}

void main() {
  test(
    'Windows resolves a cmd shim from the configured PATH',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mcp cmd fixture ',
      );
      addTearDown(() => directory.delete(recursive: true));
      await File('${directory.path}/mcp-fixture.cmd').writeAsString(
        '@echo {"jsonrpc":"2.0","method":"fixture","params":{"argument":"%~1"}}\r\n',
      );
      final message = Completer<sdk.JsonRpcMessage>();
      final transport = sdk.StdioClientTransport(
        sdk.StdioServerParameters(
          command: 'mcp-fixture',
          args: ['argument with spaces'],
          environment: {'PATH': directory.path},
        ),
      );
      addTearDown(transport.close);
      transport.onmessage = message.complete;
      await transport.start();
      final result = await message.future.timeout(const Duration(seconds: 5));
      expect(result.toJson()['params'], {'argument': 'argument with spaces'});
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(seconds: 10)),
  );

  for (final variant in ['opaque_extensions', 'non_object', 'null_metadata']) {
    test('HTTP modern tool metadata stays opaque: $variant', () async {
      final meta = <String, dynamic>{
        'openai/toolInvocation/invoking': 'Searching…',
        'openai/toolInvocation/invoked': 'x' * 100,
        'vendor/extension/nested': {
          'value': [1, true, null],
        },
        'legacy key with spaces': 42,
        'traceparent': {'opaqueToolValue': true},
      };
      final schema = <String, dynamic>{
        'type': 'object',
        r'$defs': {
          'query': {'type': 'string'},
        },
        'properties': {
          'query': {r'$ref': r'#/$defs/query'},
        },
        'allOf': [
          {
            'required': ['query'],
          },
        ],
      };
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (request.method != 'POST') {
          request.response.statusCode = 405;
        } else {
          final rpc =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;
          final response = reply(rpc, modern: true);
          if (rpc['method'] == 'tools/list') {
            final result = response!['result'] as Map;
            result['tools'] = [
              for (final tool in result['tools'] as List)
                <String, dynamic>{
                  ...Map<String, dynamic>.from(tool as Map),
                  '_meta': switch (variant) {
                    'non_object' => ['invalid'],
                    'null_metadata' => null,
                    _ => meta,
                  },
                  'inputSchema': schema,
                },
            ];
          }
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(response));
        }
        await request.response.close();
      });
      final adapter = await McpClientAdapter.connect(
        McpServerConfig(
          name: 'fixture',
          enabled: true,
          connection: McpHttpConfig(url: 'http://127.0.0.1:${server.port}/mcp'),
        ),
      );
      addTearDown(adapter.close);
      expect(adapter.client.getProtocolVersion(), '2026-07-28');
      if (variant == 'opaque_extensions') {
        final tools = await adapter.listTools();
        expect(tools, hasLength(2));
        expect(tools.first['_meta'], meta);
        expect(tools.first['inputSchema'], schema);
      } else {
        await expectLater(adapter.listTools(), throwsA(isA<sdk.McpError>()));
      }
    });
  }
  test(
    'protocol metadata validation outside tool descriptors remains strict',
    () {
      expect(
        () => meta_validation.validateMetaObject({
          'vendor/extension/nested': 'outside tool',
        }),
        throwsFormatException,
      );
      expect(
        () => meta_validation.validateMetaObject({'traceparent': 'invalid'}),
        throwsFormatException,
      );
    },
  );
  for (final cwd in [false, true]) {
    test(
      'local startup reports safe ${cwd ? 'directory' : 'command'} category',
      () async {
        final runtime = McpRuntime(connect: McpClientAdapter.connect);
        addTearDown(runtime.close);
        await runtime.configure(
          McpSettings([
            McpServerConfig(
              name: 'local',
              enabled: true,
              connection: McpStdioConfig(
                command: 'reveric-mcp-no-such-executable',
                cwd: cwd ? '/reveric-mcp-no-such-directory' : null,
              ),
            ),
          ]),
        );
        await expectLater(runtime.ensureReady('local'), throwsA(anything));
        if (Platform.isWindows && !cwd) {
          // cmd.exe reports lookup failure through stderr rather than a
          // native ProcessException. Preserve that command diagnostic.
          expect(
            runtime.states['local']!.error,
            contains('reveric-mcp-no-such-executable'),
          );
        } else {
          expect(
            runtime.states['local']!.failureKind,
            cwd
                ? McpFailureKind.working_directory
                : McpFailureKind.command_not_found,
          );
        }
      },
    );
  }

  for (final modern in [false, true]) {
    test(
      'HTTP modern=$modern connects to an independent fixture and follows pages',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          if (request.method != 'POST') {
            request.response.statusCode = HttpStatus.methodNotAllowed;
          } else {
            final value = reply(
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>,
              modern: modern,
            );
            if (value == null) {
              request.response.statusCode = HttpStatus.accepted;
            } else {
              request.response.headers.contentType = ContentType.json;
              request.response.write(jsonEncode(value));
            }
          }
          await request.response.close();
        });
        final adapter = await McpClientAdapter.connect(
          McpServerConfig(
            name: 'fixture',
            enabled: true,
            connection: McpHttpConfig(
              url: 'http://127.0.0.1:${server.port}/mcp',
            ),
          ),
        );
        addTearDown(adapter.close);
        expect((await adapter.listTools()).map((t) => t['name']), [
          'first',
          'second',
        ]);
        expect((await adapter.callTool('first', {}))['content'], [
          {'type': 'text', 'text': 'called'},
        ]);
      },
    );
  }
  for (final modern in [false, true]) {
    test(
      'stdio modern=$modern uses independent command and arguments',
      () async {
        final directory = await Directory.systemTemp.createTemp('mcp-fixture-');
        addTearDown(() => directory.delete(recursive: true));
        final script = File('${directory.path}/server.py');
        await script.writeAsString(r'''
import json,sys,os
for line in sys.stdin:
 r=json.loads(line)
 if 'id' not in r: continue
 m=r['method']
 if m=='server/discover' and 'modern' in sys.argv: result={'resultType':'complete','supportedVersions':['2026-07-28'],'capabilities':{'tools':{}},'ttlMs':0,'cacheScope':'private'}
 elif m=='initialize': result={'protocolVersion':'2025-11-25','capabilities':{'tools':{}},'serverInfo':{'name':'fixture','version':'1'}}
 elif m=='tools/list': result={'tools':[{'name':'echo','inputSchema':{'type':'object','properties':{}}}]}
 elif m=='tools/call': result={'content':[{'type':'text','text':'called'}], 'structuredContent':{'inheritedShell':os.environ.get('SHELL'), 'override':os.environ.get('LANG'), 'path':os.environ.get('PATH'), 'argument':sys.argv[-1]}}
 else: result=None
 out={'jsonrpc':'2.0','id':r['id']}
 if result is None: out['error']={'code':-32601,'message':'Method not found'}
 else:
  if 'modern' in sys.argv: result.update({'resultType':'complete','ttlMs':0,'cacheScope':'private'})
  out['result']=result
 print(json.dumps(out),flush=True)
''');
        final adapter = await McpClientAdapter.connect(
          McpServerConfig(
            name: 'fixture',
            enabled: true,
            connection: McpStdioConfig(
              command: 'python3',
              args: [
                script.path,
                if (modern) 'modern',
                r'argument with spaces & $literal',
              ],
              env: {
                'LANG': 'C',
                if (modern) 'PATH': Platform.environment['PATH']!,
              },
            ),
          ),
        );
        try {
          expect((await adapter.listTools()).single['name'], 'echo');
          final result = await adapter.callTool('echo', {});
          expect(result['structuredContent'], {
            'inheritedShell': Platform.environment['SHELL'],
            'override': 'C',
            'path': modern ? Platform.environment['PATH'] : isNotEmpty,
            'argument': r'argument with spaces & $literal',
          });
          expect(result['content'], [
            {'type': 'text', 'text': 'called'},
          ]);
        } finally {
          await adapter.close();
        }
      },
      skip: Platform.isWindows
          ? 'Independent fixture requires python3 on PATH'
          : false,
    );
  }
  for (final authMode in [McpAuthMode.bearer, McpAuthMode.headers]) {
    test(
      'HTTP ${authMode.name} 401 during a call is a rejection, not lost',
      () async {
        var callsSent = 0;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          if (request.method != 'POST') {
            request.response.statusCode = HttpStatus.methodNotAllowed;
          } else {
            final rpc =
                jsonDecode(await utf8.decoder.bind(request).join())
                    as Map<String, dynamic>;
            if (rpc['method'] == 'tools/call') {
              callsSent++;
              request.response.statusCode = HttpStatus.unauthorized;
              request.response.write('credentials revoked');
            } else if (reply(rpc) case final value?) {
              request.response.headers.contentType = ContentType.json;
              request.response.write(jsonEncode(value));
            } else {
              request.response.statusCode = HttpStatus.accepted;
            }
          }
          await request.response.close();
        });
        final runtime = McpRuntime(connect: McpClientAdapter.connect);
        addTearDown(runtime.close);
        await runtime.configure(
          McpSettings([
            McpServerConfig(
              name: 'fixture',
              enabled: true,
              connection: McpHttpConfig(
                url: 'http://127.0.0.1:${server.port}/mcp',
                authMode: authMode,
                bearerToken: authMode == McpAuthMode.bearer ? 'secret' : null,
                headers: authMode == McpAuthMode.headers
                    ? {'X-Api-Key': 'secret'}
                    : {},
              ),
            ),
          ]),
        );
        await runtime.ensureReady('fixture');
        final result = await McpToolDispatcher(
          runtime,
        ).call('mcp__fixture__first', {});
        expect(callsSent, 1);
        expect(result.executionState, McpExecutionState.failed);
        expect(result.errorCode, 'mcp_unauthorized');
        expect(result.error, contains('HTTP 401'));
        expect(result.recovery, isNot(contains('Verify external state')));
      },
    );
  }
}
