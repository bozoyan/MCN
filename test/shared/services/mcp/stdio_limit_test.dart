// 职责: 验证 stdio 传输超限中断保持执行未知，并且不重放已发请求。
// 关联文件:
//   lib/shared/services/mcp/client_adapter.dart
//   lib/shared/services/mcp/tool_dispatcher.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/mcp/config.dart';
import 'package:reveric/shared/models/mcp/call_result.dart';
import 'package:reveric/shared/services/mcp/client_adapter.dart';
import 'package:reveric/shared/services/mcp/runtime.dart';
import 'package:reveric/shared/services/mcp/tool_dispatcher.dart';

void main() {
  test(
    'oversized stdio response is unknown with one external write',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mcp-stdio-limit-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final counter = File('${directory.path}/calls');
      final script = File('${directory.path}/server.py');
      await script.writeAsString(r'''
import json,sys
for line in sys.stdin:
 r=json.loads(line)
 if 'id' not in r: continue
 m=r['method']
 if m=='initialize': result={'protocolVersion':'2025-11-25','capabilities':{'tools':{}},'serverInfo':{'name':'limit-fixture','version':'1'}}
 elif m=='tools/list': result={'tools':[{'name':'large','inputSchema':{'type':'object','properties':{}}}]}
 elif m=='tools/call':
  with open(sys.argv[1],'a') as counter: counter.write('call\n')
  result={'content':[{'type':'text','text':'x'*11534336}]}
 else: result=None
 out={'jsonrpc':'2.0','id':r['id']}
 if result is None: out['error']={'code':-32601,'message':'Method not found'}
 else: out['result']=result
 print(json.dumps(out),flush=True)
''');
      final runtime = McpRuntime(connect: McpClientAdapter.connect);
      addTearDown(runtime.close);
      await runtime.configure(
        McpSettings([
          McpServerConfig(
            name: 'fixture',
            enabled: true,
            connection: McpStdioConfig(
              command: 'python3',
              args: [script.path, counter.path],
            ),
          ),
        ]),
      );
      await runtime.ensureReady('fixture');
      final result = await McpToolDispatcher(
        runtime,
      ).call('mcp__fixture__large', {});
      expect(result.executionState, McpExecutionState.unknown);
      expect(result.errorCode, 'mcp_result_unavailable');
      expect(result.error, isNotEmpty);
      expect(result.recovery, contains('Do not automatically replay'));
      expect(await counter.readAsString(), 'call\n');
    },
    timeout: const Timeout(Duration(seconds: 30)),
    skip: Platform.isWindows ? 'Requires python3 fixture runtime' : false,
  );
}
