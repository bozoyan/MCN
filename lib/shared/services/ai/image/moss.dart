// 职责: 将图片请求编码为 MOSS 平台的同步文生图接口调用并解析返回图片。
// 关联文件:
//   lib/shared/services/ai/image/client.dart
//   lib/shared/models/image/channels.dart
//   lib/shared/models/image/extras.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/zh-CN/ai.json
import 'dart:math';

import 'package:easy_localization/easy_localization.dart';

import '../../../localization/locale_keys.dart';
import '../../../models/ai_provider.dart';
import '../image.dart';
import 'client.dart';

/// MOSS 尺寸硬约束(官方文档):每边 256-2048、16 的倍数、总像素 ≤ 2097152。
const mossMinEdge = 256;
const mossMaxEdge = 2048;
const mossMaxPixels = 2097152;

/// 将不满足 MOSS 约束的尺寸等比收敛到合规(向 16 对齐);
/// 已合规或非像素格式时原样返回。封面等入口按通用档位算出的尺寸
/// (如 3:4 + 2K = 1536x2048,总像素超限)在此统一收敛,日志留痕。
String? clampMossSize(String? size) {
  if (size == null) {
    return null;
  }
  final match = RegExp(r'^(\d+)x(\d+)$').firstMatch(size);
  if (match == null) {
    return size;
  }
  var width = int.parse(match[1]!);
  var height = int.parse(match[2]!);
  // 每边不足下限时等比放大到下限(向上取 16 对齐)。
  if (width < mossMinEdge || height < mossMinEdge) {
    final scale = max(mossMinEdge / width, mossMinEdge / height);
    width = _align16Up((width * scale).ceil());
    height = _align16Up((height * scale).ceil());
  }
  final scale = min(
    1.0,
    min(mossMaxEdge / width, mossMaxEdge / height),
  );
  final pixelScale = sqrt(mossMaxPixels / (width * height));
  final finalScale = min(scale, pixelScale);
  if (finalScale >= 1) {
    // 缩放因子为 1:每边与总像素都已合规(含放大到下限的场景),直接放行。
    if (width <= mossMaxEdge &&
        height <= mossMaxEdge &&
        width * height <= mossMaxPixels) {
      return '${width}x$height';
    }
  }
  var nextWidth = _align16Down((width * finalScale).floor());
  var nextHeight = _align16Down((height * finalScale).floor());
  // 向下对齐只会更小,总像素必然达标;防御性兜底循环,正常不触发。
  while (nextWidth * nextHeight > mossMaxPixels &&
      nextWidth > mossMinEdge &&
      nextHeight > mossMinEdge) {
    nextWidth = _align16Down(nextWidth * 15 ~/ 16);
    nextHeight = _align16Down(nextHeight * 15 ~/ 16);
  }
  return '${max(nextWidth, mossMinEdge)}x${max(nextHeight, mossMinEdge)}';
}

int _align16Down(int value) => max(16, value ~/ 16 * 16);

int _align16Up(int value) => max(16, (value + 15) ~/ 16 * 16);

/// MOSS 只提供同步文生图;响应为 OpenAI images 格式,仅返回 url。
class MossImageClient extends ImageClient {
  MossImageClient(super.config);

  @override
  bool get supportsEdit => false;

  @override
  Future<AiImageGenerationResult> generate(
    ImageGenerationRequest request,
  ) async {
    validatedChannel(request);
    final extras = request.extras;
    final body = <String, dynamic>{
      'model': request.model,
      'prompt': request.prompt,
      // 服务端仅支持单张与 url 返回。
      'n': 1,
      'response_format': 'url',
      // 按官方默认值显式发送,行为与界面显示一致:增强开、水印关。
      'prompt_enhance': extras?.promptEnhance ?? true,
      'output_watermark': {'enabled': extras?.outputWatermark ?? false},
    };
    final size = clampMossSize(request.size ?? channelSize(request));
    if (size != null) {
      body['size'] = size;
    }
    final negative = extras?.negativePrompt;
    if (negative != null && negative.trim().isNotEmpty) {
      body['negative_prompt'] = negative;
    }
    final base = Uri.parse(config.effectiveBaseUrl);
    final uri = base.replace(path: '${base.path}/images/generations');
    final response = await postImageJson(uri, body);
    return parseImageResponse(
      response,
      emptyMessage: tr(LocaleKeys.aiImageNoResult),
    );
  }

  String? channelSize(ImageGenerationRequest request) {
    final channel = channelFor(request.model);
    final caps = channel?.capabilities;
    if (caps == null || caps.sizes.isEmpty) {
      return request.size;
    }
    if (request.aspectRatio != null || request.resolution != null) {
      return caps.size(
        request.aspectRatio ?? '1:1',
        request.resolution ?? caps.resolutions.first,
      );
    }
    return channel!.requestDefaults.size;
  }
}
