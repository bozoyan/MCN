// 职责: 将图片请求编码为 BizyAir modelzoo / webapp 两类 openapi 异步任务，轮询并解析输出图片。
// 关联文件:
//   lib/shared/services/ai/image/client.dart
//   lib/shared/models/image/channels.dart
//   lib/shared/services/ai/image.dart
//   lib/shared/localization/locale_keys.dart
// 遵循的 Rules:
//   .agents/rules/api-contract.md
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;

import '../../../localization/locale_keys.dart';
import '../../../models/ai_provider.dart';
import '../../../models/image/channels.dart';
import '../bizyair_keys.dart';
import '../image.dart';
import 'client.dart';

/// BizyAir 异步任务客户端。同一供应商类型（modelzoo / webapp）各挂一个协议，
/// 本类按渠道的 protocolOptions 分派到对应 openapi 链路。
class BizyAirImageClient extends ImageClient {
  BizyAirImageClient(
    super.config, {
    http.Client? httpClient,
    BizyAirKeyPool? keyPool,
    this.firstPollDelay = const Duration(seconds: 60),
    this.pollInterval = const Duration(seconds: 5),
  }) : _injectedClient = httpClient,
       _injectedKeyPool = keyPool;

  static const _attempts = 3;
  static const _referenceTransferUrl = 'https://b.slas.cc/api/bizyair/upload';

  /// BizyAir 图生图不接受 base64；本地/内联图片需转存为公网 URL。
  static const _referenceTransferHint =
      'BizyAir 不支持内联参考图，请改用公网图片 URL。';

  final http.Client? _injectedClient;

  /// 注入的密钥池（测试用）；为空时按供应商 Key 字段与外置 txt 解析。
  final BizyAirKeyPool? _injectedKeyPool;
  /// 首轮轮询等待（官方建议拿到任务 ID 后先等 60 秒）。
  final Duration firstPollDelay;

  /// 后续轮询间隔。
  final Duration pollInterval;

  /// 每个供应商一条任务队列：一把 key 同一时刻只跑一个任务，
  /// 多密钥时按队列串行出图，避免同 key 并发被限流。
  static final Map<String, Future<void>> _taskQueues = {};

  @override
  Future<AiImageGenerationResult> generate(ImageGenerationRequest request) =>
      _enqueue(() => _generate(request));

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final slot = config.id;
    final previous = _taskQueues[slot] ?? Future<void>.value();
    final gate = Completer<void>();
    _taskQueues[slot] = gate.future;
    // 前一个任务失败也要继续放行后续任务，不能把错误串下去。
    final ready = previous.then<void>((_) {}, onError: (_) {});
    return ready.then((_) => action()).whenComplete(() {
      gate.complete();
      if (identical(_taskQueues[slot], gate.future)) {
        _taskQueues.remove(slot);
      }
    });
  }

  Future<AiImageGenerationResult> _generate(
    ImageGenerationRequest request,
  ) async {
    final channel = validatedChannel(request);
    if (channel == null) {
      throw invalidImageParameter();
    }
    final options = channel.protocolOptions;
    if (options is! BizyAirModelZooOptions && options is! BizyAirWebAppOptions) {
      throw invalidImageParameter();
    }

    final pool =
        _injectedKeyPool ??
        await BizyAirKeyPool.resolve(config.apiKey, providerId: config.id);
    if (pool.isEmpty) {
      // 复用基类的「缺少 Key」错误，保持各供应商提示一致。
      requireApiKey();
    }
    final client = _injectedClient ?? config.createProxyClient() ?? http.Client();
    final elapsed = Stopwatch()..start();
    try {
      final String requestId;
      if (options is BizyAirWebAppOptions) {
        requestId = await _submitWebApp(client, elapsed, request, options, pool);
      } else {
        requestId = await _submitModelZoo(client, elapsed, request, pool);
      }
      try {
        await request.onSubmitted?.call(requestId);
      } catch (error) {
        throw AiImageFetchException(
          '图片结果获取失败，请稍后重试。',
          providerTaskId: requestId,
          debugMessage: 'BizyAir task $requestId record failed: $error',
        );
      }
      final result = options is BizyAirWebAppOptions
          ? await _settleWebApp(client, elapsed, requestId, pool.current!)
          : await _settleModelZoo(client, elapsed, requestId, pool.current!);
      // 任务成功后才推进游标：失败重试不会白白消耗轮转位。
      await pool.commit();
      return result;
    } finally {
      if (_injectedClient == null) {
        client.close();
      }
    }
  }

  Uri _uri(String path) =>
      Uri.parse(config.effectiveBaseUrl).replace(
        path: '${Uri.parse(config.effectiveBaseUrl).path}$path',
      );

  Future<String> _submitModelZoo(
    http.Client client,
    Stopwatch elapsed,
    ImageGenerationRequest request,
    BizyAirKeyPool pool,
  ) async {
    final body = <String, dynamic>{
      'prompt': request.prompt,
      'aspect_ratio': _aspectRatio(request),
      'resolution': _resolution(request),
    };
    if (request.images.isNotEmpty) {
      body['image_urls'] = await _prepareReferenceUrls(
        request.images,
        pool.current!,
      );
    }
    final response = await _sendForSubmit(
      client,
      elapsed,
      _uri('/v1/modelzoo/tasks/openapi/${request.model}'),
      data: body,
      pool: pool,
    );
    final id = response['data'] is Map
        ? (response['data'] as Map)['request_id']
        : response['request_id'];
    if (id is! String || id.trim().isEmpty) {
      throw _taskError(response, request.model);
    }
    return id;
  }

  Future<String> _submitWebApp(
    http.Client client,
    Stopwatch elapsed,
    ImageGenerationRequest request,
    BizyAirWebAppOptions options,
    BizyAirKeyPool pool,
  ) async {
    final dimensions = _webAppDimensions(request);
    final body = <String, dynamic>{
      'web_app_id': options.webAppId,
      'input_values': <String, dynamic>{
        options.promptInputKey: request.prompt,
        options.widthInputKey: dimensions.$1,
        options.heightInputKey: dimensions.$2,
        'batch_size': options.batchSize,
      },
    };
    final response = await _sendForSubmit(
      client,
      elapsed,
      _uri('/v1/webapp/task/openapi/create'),
      data: body,
      headers: const {'X-Bizyair-Task-Async': 'enable'},
      pool: pool,
    );
    final id = response['request_id'];
    if (id is! String || id.trim().isEmpty) {
      throw _taskError(response, 'webapp:${options.webAppId}');
    }
    return id;
  }

  Future<AiImageGenerationResult> _settleModelZoo(
    http.Client client,
    Stopwatch elapsed,
    String taskId,
    String apiKey,
  ) async {
    final uri = _uri('/v1/modelzoo/tasks/openapi/${Uri.encodeComponent(taskId)}');
    var first = true;
    while (true) {
      await _waitFirstThenPoll(first);
      first = false;
      final task = await _poll(client, elapsed, uri, taskId, apiKey);
      final data = task['data'];
      final status = data is Map ? data['status'] : task['status'];
      if (_isPending(status)) {
        continue;
      }
      if (!_isSuccess(status)) {
        throw _taskError(task, taskId);
      }
      final outputs = data is Map ? data['outputs'] : null;
      final images = outputs is Map ? outputs['images'] : null;
      if (images is! List || images.isEmpty || images.first is! String) {
        throw _taskError(task, taskId);
      }
      return parseImageResponse({
        'data': [
          {'url': images.first},
        ],
      }, emptyMessage: tr(LocaleKeys.aiImageNoResult));
    }
  }

  Future<AiImageGenerationResult> _settleWebApp(
    http.Client client,
    Stopwatch elapsed,
    String taskId,
    String apiKey,
  ) async {
    final statusUri = _uri(
      '/v1/webapp/task/openapi/${Uri.encodeComponent(taskId)}',
    );
    var first = true;
    while (true) {
      await _waitFirstThenPoll(first);
      first = false;
      final task = await _poll(client, elapsed, statusUri, taskId, apiKey);
      final data = task['data'];
      final status = data is Map ? data['status'] : task['status'];
      if (_isPending(status)) {
        continue;
      }
      if (!_isSuccess(status)) {
        throw _taskError(task, taskId);
      }
      break;
    }
    // 终态后再取输出列表：webapp 的 URL 不在状态响应里。
    final outputsUri = _uri(
      '/v1/webapp/task/openapi/${Uri.encodeComponent(taskId)}/outputs',
    );
    final outputs = await _poll(client, elapsed, outputsUri, taskId, apiKey);
    final list = outputs['data'] is Map
        ? (outputs['data'] as Map)['outputs']
        : outputs['outputs'];
    if (list is! List || list.isEmpty) {
      throw _taskError(outputs, taskId);
    }
    final firstOutput = list.first;
    final url = firstOutput is String
        ? firstOutput
        : firstOutput is Map
        ? firstOutput['object_url']?.toString()
        : null;
    if (url == null || url.isEmpty) {
      throw _taskError(outputs, taskId);
    }
    return parseImageResponse({
      'data': [
        {'url': url},
      ],
    }, emptyMessage: tr(LocaleKeys.aiImageNoResult));
  }

  Future<void> _waitFirstThenPoll(bool first) async {
    final delay = first ? firstPollDelay : pollInterval;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
  }

  bool _isPending(Object? status) =>
      status is String &&
      (status.toUpperCase() == 'PENDING' ||
          status.toUpperCase() == 'RUNNING' ||
          status.toUpperCase() == 'PROCESSING');

  bool _isSuccess(Object? status) =>
      status is String &&
      (status.toUpperCase() == 'SUCCESS' || status.toUpperCase() == 'SUCCEED');

  Future<Map<String, dynamic>> _poll(
    http.Client client,
    Stopwatch elapsed,
    Uri uri,
    String taskId,
    String apiKey,
  ) async {
    try {
      return await _send(client, elapsed, uri, apiKey: apiKey);
    } catch (error) {
      throw AiImageFetchException(
        '图片结果获取失败，请稍后重试。',
        providerTaskId: taskId,
        debugMessage:
            'BizyAir task $taskId poll failed at ${safeImageUriForLog(uri)}: '
            '${error is AiImageGenerationException ? error.debugMessage ?? error.userMessage : error}',
      );
    }
  }

  /// 把参考图归一为公网 URL：http(s) 原样放行交给服务端拉取；
  /// 本地路径 / data URI / 裸 base64 走转存接口换成公网 URL。
  Future<List<String>> _prepareReferenceUrls(
    List<String> inputs,
    String apiKey,
  ) async {
    final urls = <String>[];
    for (final input in inputs) {
      final trimmed = input.trim();
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        urls.add(trimmed);
        continue;
      }
      final bytes = await _referenceBytes(trimmed);
      if (bytes == null) {
        throw invalidImageParameter();
      }
      urls.add(await _transferReference(bytes, apiKey));
    }
    return urls;
  }

  Future<Uint8List?> _referenceBytes(String input) async {
    if (input.startsWith('data:')) {
      final comma = input.indexOf(',');
      if (comma < 0) {
        return null;
      }
      try {
        return base64Decode(input.substring(comma + 1));
      } catch (_) {
        return null;
      }
    }
    final file = File(input);
    if (await file.exists()) {
      return file.readAsBytes();
    }
    try {
      return base64Decode(input);
    } catch (_) {
      return null;
    }
  }

  Future<String> _transferReference(Uint8List bytes, String apiKey) async {
    final client = _injectedClient ?? config.createProxyClient() ?? http.Client();
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_referenceTransferUrl))
        ..headers['Authorization'] = 'Bearer $apiKey'
        ..files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: 'reference.png'),
        );
      final response = await http.Response.fromStream(
        await client.send(request),
      ).timeout(imageHttpDataTimeout);
      throwForImageHttpFailure(
        uri: Uri.parse(_referenceTransferUrl),
        statusCode: response.statusCode,
        data: response.body,
        providerId: config.id,
      );
      final decoded = jsonDecode(response.body);
      final url = decoded is Map ? decoded['url'] : null;
      if (url is! String || url.isEmpty) {
        throw const AiImageGenerationException(_referenceTransferHint);
      }
      return url;
    } on AiImageGenerationException {
      rethrow;
    } catch (_) {
      throw const AiImageGenerationException(_referenceTransferHint);
    } finally {
      if (_injectedClient == null) {
        client.close();
      }
    }
  }

  /// 提交类请求：当前 key 失败时串行切到下一把重试，全部失败才抛错。
  /// 提交成功即停在可用的那把 key 上，后续轮询沿用同一把（任务归属）。
  Future<Map<String, dynamic>> _sendForSubmit(
    http.Client client,
    Stopwatch elapsed,
    Uri uri, {
    Map<String, dynamic>? data,
    Map<String, String> headers = const {},
    required BizyAirKeyPool pool,
  }) async {
    final attempts = pool.size;
    for (var attempt = 1; ; attempt++) {
      try {
        return await _send(
          client,
          elapsed,
          uri,
          apiKey: pool.current!,
          data: data,
          headers: headers,
        );
      } catch (error) {
        final hasNext = attempt < attempts && pool.advance();
        writeImageLog(
          '[IMGDBG] bizyair_key_fail key=${pool.masked} '
          'uri=${safeImageUriForLog(uri)} attempt=$attempt rotate=$hasNext error=$error',
        );
        if (!hasNext) {
          rethrow;
        }
      }
    }
  }

  Future<Map<String, dynamic>> _send(
    http.Client client,
    Stopwatch elapsed,
    Uri uri, {
    required String apiKey,
    Map<String, dynamic>? data,
    Map<String, String> headers = const {},
  }) async {
    final remaining = imageHttpDataTimeout - elapsed.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException('BizyAir image task timed out');
    }
    http.Request build() {
      final request = http.Request(data == null ? 'GET' : 'POST', uri)
        ..followRedirects = false
        ..headers.addAll({
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          ...headers,
        });
      if (data != null) {
        request.body = jsonEncode(data);
      }
      return request;
    }

    var request = build();
    http.Response? response;
    for (var attempt = 1; response == null; attempt++) {
      try {
        response = await http.Response.fromStream(
          await client.send(request),
        ).timeout(remaining);
      } catch (error) {
        final retryable =
            error is HandshakeException ||
            (data == null &&
                (error is SocketException || error is http.ClientException));
        if (attempt >= _attempts || !retryable) {
          rethrow;
        }
        writeImageLog(
          '[IMGDBG] bizyair_retry method=${request.method} '
          'uri=${safeImageUriForLog(uri)} attempt=$attempt error=$error',
        );
        await Future<void>.delayed(Duration(seconds: attempt));
        request = build();
      }
    }
    writeImageLog(
      '[IMGDBG] bizyair_response method=${request.method} '
      'uri=${safeImageUriForLog(uri)} status=${response.statusCode}',
    );
    throwForImageHttpFailure(
      uri: uri,
      statusCode: response.statusCode,
      data: response.body,
      providerId: config.id,
    );
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw _taskError({'message': response.body}, uri.path);
    }
    // modelzoo 成功码是 20000；非成功业务码按任务失败处理。
    final code = json['code'];
    if (code != null && code is int && code != 20000) {
      throw _taskError(json, uri.path);
    }
    if (json['error'] != null) {
      throw _taskError(json, uri.path);
    }
    return json;
  }

  AiImageGenerationException _taskError(Map<String, dynamic> data, Object where) {
    final message = extractImageServerMessage(data);
    return AiImageGenerationException(
      imageUserMessageFromServerMessage(message) ??
          tr(LocaleKeys.aiImageGenerationFailed),
      debugMessage: 'BizyAir task error at $where response=${safeImageSerializeForLog(data)}',
      code: classifyAiImageError(message),
    );
  }

  /// 比例：优先用能力表登记的档位换算出 WxH，再按比例字符串回推 aspect_ratio。
  /// BizyAir 的 aspect_ratio 接受比例字符串，直接取请求的比例值。
  String _aspectRatio(ImageGenerationRequest request) {
    final ratio = request.aspectRatio;
    if (ratio != null && ratio != 'auto') {
      return ratio;
    }
    final size = request.size;
    if (size != null) {
      final match = RegExp(r'^(\d+)x(\d+)$').firstMatch(size);
      if (match != null) {
        return _ratioFromDimensions(
          int.parse(match[1]!),
          int.parse(match[2]!),
        );
      }
    }
    return '1:1';
  }

  String _ratioFromDimensions(int width, int height) {
    var a = width;
    var b = height;
    while (b != 0) {
      final t = a % b;
      a = b;
      b = t;
    }
    final simpleW = width ~/ a;
    final simpleH = height ~/ a;
    for (final candidate in const [
      '1:1',
      '16:9',
      '9:16',
      '4:3',
      '3:4',
      '3:2',
      '2:3',
      '5:4',
      '4:5',
      '21:9',
      '1:4',
      '4:1',
      '1:8',
      '8:1',
    ]) {
      final parts = candidate.split(':');
      if (int.parse(parts[0]) == simpleW && int.parse(parts[1]) == simpleH) {
        return candidate;
      }
    }
    return '$simpleW:$simpleH';
  }

  /// 分辨率档位：1K / 2K / 4K 大写转小写；未给定的按 2K（文档默认）。
  String _resolution(ImageGenerationRequest request) {
    final raw = request.resolution ?? request.size;
    if (raw != null) {
      final upper = raw.toUpperCase();
      if (upper == '1K' || upper == '2K' || upper == '4K') {
        return upper.toLowerCase();
      }
    }
    return '2k';
  }

  /// webapp 按 WIDTHxHEIGHT 提交：16 的倍数、最大边 2048（2K）或 1024（1K）。
  (int, int) _webAppDimensions(ImageGenerationRequest request) {
    final ratio = _aspectRatio(request);
    final maxEdge = _resolution(request) == '1k' ? 1024 : 2048;
    if (ratio == 'auto' || !ratio.contains(':')) {
      return (maxEdge, maxEdge);
    }
    final parts = ratio.split(':');
    final rw = int.tryParse(parts[0]) ?? 1;
    final rh = int.tryParse(parts[1]) ?? 1;
    final scale = maxEdge / (rw > rh ? rw : rh);
    var width = (_align16((rw * scale).round()));
    var height = (_align16((rh * scale).round()));
    if (width < 16) {
      width = 16;
    }
    if (height < 16) {
      height = 16;
    }
    return (width, height);
  }

  int _align16(int value) => (value ~/ 16) * 16;
}
