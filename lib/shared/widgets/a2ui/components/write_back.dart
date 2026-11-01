// 职责: 把输入组件的值写回绑定的页面数据路径，写入失败时上报为界面运行时错误。
// 关联文件:
//   lib/shared/widgets/a2ui/components/text_field.dart
//   lib/shared/widgets/a2ui/components/choice_picker.dart
//   lib/shared/widgets/a2ui/components/toggle.dart

import 'dart:async';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:flutter/widgets.dart';

import '../component.dart';
import '../surface_view.dart';

/// 属性 [key] 绑定了数据路径时返回写入函数，否则返回 null（组件按只读显示）。
/// 写入函数返回是否成功。
bool Function(Object? value)? a2uiWriterFor(
  BuildContext context,
  A2uiProps props,
  String key,
) {
  final binding = props.writable(key);
  if (binding == null) {
    return null;
  }
  final surface = A2uiSurfaceScope.maybeOf(context)?.surface;
  return (value) {
    try {
      binding.set(value);
      return true;
    } on A2uiDataError catch (error) {
      if (surface != null) {
        unawaited(
          surface.dispatchError(
            A2uiRendererError(
              code: error.code,
              surfaceId: surface.id,
              message: error.message,
              path: error.path,
            ),
          ),
        );
      }
      return false;
    }
  };
}
