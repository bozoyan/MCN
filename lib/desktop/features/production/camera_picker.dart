// 职责: 展示运镜模板并将选中的提示词作为可见文本交给视频编辑器。
// 关联文件:
//   lib/desktop/features/production/composer.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../../shared/components/reveric_dialog.dart';
import '../../../shared/components/reveric_filter_chip.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/theme/theme.dart';

const _moves = <({String id, String group, String prompt})>[
  (id: 'ct_static', group: 'basic', prompt: '固定机位，画面构图全程不变。'),
  (id: 'ct_tilt_u', group: 'basic', prompt: '镜头由下向上缓慢摇起。'),
  (id: 'ct_tilt_d', group: 'basic', prompt: '镜头由环境缓慢下摇，落到人物身上。'),
  (id: 'ct_pan_l', group: 'basic', prompt: '机位不动，镜头缓慢向左横摇。'),
  (id: 'ct_pan_r', group: 'basic', prompt: '机位不动，镜头缓慢向右横摇，引出画外。'),
  (id: 'ct_push', group: 'basic', prompt: '镜头缓慢向前推进。'),
  (id: 'ct_pull', group: 'basic', prompt: '镜头缓慢后拉，人物在画面中变小。'),
  (id: 'ct_zoom', group: 'basic', prompt: '机位不动，镜头变焦推近到人物面部。'),
  (id: 'ct_follow', group: 'follow', prompt: '镜头跟随人物移动，保持人物在画面同一位置。'),
  (id: 'ct_lead', group: 'follow', prompt: '镜头在人物前方同步后退，人物迎面走来。'),
  (id: 'ct_orbit', group: 'follow', prompt: '镜头围绕人物缓慢环绕半周。'),
  (id: 'ct_over', group: 'follow', prompt: '过肩镜头，前景是一方肩部，焦点在对面人物。'),
  (id: 'ct_door', group: 'reveal', prompt: '起幅被前景遮挡，镜头缓慢横移，逐渐揭示后方空间。'),
  (id: 'ct_rack', group: 'reveal', prompt: '焦点从前景缓慢转移到后景人物。'),
  (id: 'ct_slow', group: 'emotion', prompt: '镜头以几乎察觉不到的速度持续推进。'),
  (id: 'ct_hand', group: 'emotion', prompt: '手持拍摄，画面轻微晃动。'),
  (id: 'ct_rise', group: 'aerial', prompt: '镜头向后并向上缓慢升起，离开人物，露出全景。'),
  (id: 'ct_crane_d', group: 'aerial', prompt: '镜头从高处缓慢下降，聚焦到画面中心人物。'),
  (id: 'ct_up', group: 'basic', prompt: '镜头垂直向上移动，保持拍摄方向不变。'),
  (id: 'ct_down', group: 'basic', prompt: '镜头垂直向下移动，保持拍摄方向不变。'),
  (id: 'ct_truck_l', group: 'basic', prompt: '镜头向左横向移动，保持拍摄方向不变。'),
  (id: 'ct_truck_r', group: 'basic', prompt: '镜头向右横向移动，保持拍摄方向不变。'),
  (id: 'ct_zoom_out', group: 'basic', prompt: '机位不动，镜头变焦拉远，逐渐显露周围环境。'),
  (id: 'ct_foreground', group: 'reveal', prompt: '镜头横向移动并保持注视主体，让近处遮挡物擦过画面。'),
  (id: 'ct_fly_through', group: 'reveal', prompt: '镜头沿视线方向快速前推，穿过前景开口进入后方空间。'),
  (id: 'ct_whip', group: 'reveal', prompt: '镜头快速向右甩摇，短暂运动模糊后停在新的构图。'),
  (id: 'ct_crash_zoom', group: 'emotion', prompt: '机位不动，镜头急速变焦推近主体，突出瞬间反应。'),
  (id: 'ct_side', group: 'follow', prompt: '镜头位于人物侧方，与人物平行移动，保持人物在画面中的位置。'),
  (id: 'ct_orbit_full', group: 'follow', prompt: '镜头围绕人物平稳环绕一周，全程保持人物在画面中心。'),
  (id: 'ct_spiral_up', group: 'aerial', prompt: '镜头围绕主体盘旋并逐渐升高，持续朝向主体。'),
  (id: 'ct_spiral_down', group: 'aerial', prompt: '镜头围绕主体盘旋并逐渐降低，持续朝向主体。'),
  (id: 'ct_aerial', group: 'aerial', prompt: '镜头从高空俯视场景，保持高度与拍摄角度，平稳向前滑行。'),
  (id: 'ct_fpv', group: 'aerial', prompt: '第一视角高速向前飞行，随空间转弯起伏，穿过障碍间的开口。'),
];
Future<String?> pickProductionCamera(BuildContext context) =>
    showRevericDialog<String>(
      context: context,
      builder: (_) => const _CameraPicker(),
    );

class _CameraPicker extends HookWidget {
  const _CameraPicker();
  @override
  Widget build(BuildContext context) {
    final group = useState('all');
    final visible = _moves
        .where((m) => group.value == 'all' || m.group == group.value)
        .toList();
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return RevericDialog.panel(
      width: 700,
      title: Text(context.t(LocaleKeys.productionCameraLibrary)),
      content: SizedBox(
        height: 420,
        child: Column(
          children: [
            Wrap(
              spacing: RevericSpacing.sm,
              runSpacing: RevericSpacing.sm,
              children: [
                for (final id in [
                  'all',
                  'basic',
                  'follow',
                  'reveal',
                  'emotion',
                  'aerial',
                ])
                  RevericFilterChip(
                    label: context.t('screenplay.production.camera_group.$id'),
                    selected: group.value == id,
                    onTap: () => group.value = id,
                  ),
              ],
            ),
            const SizedBox(height: RevericSpacing.lg),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 240,
                  mainAxisExtent: 116,
                  crossAxisSpacing: RevericSpacing.sm,
                  mainAxisSpacing: RevericSpacing.sm,
                ),
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final move = visible[index];
                  return Material(
                    color: colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(RevericRadius.large),
                    child: InkWell(
                      onTap: () => Navigator.pop(context, move.prompt),
                      child: Padding(
                        padding: const EdgeInsets.all(RevericSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.t(
                                'screenplay.production.camera.${move.id}',
                              ),
                              style: typo.uiSemibold,
                            ),
                            const SizedBox(height: RevericSpacing.sm),
                            Expanded(
                              child: Text(
                                move.prompt,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: typo.uiSmall.copyWith(
                                  color: colors.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
