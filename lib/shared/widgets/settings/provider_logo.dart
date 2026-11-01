// 职责: 用本地品牌素材展示供应商标识，未知渠道保留文字标识。
// 关联文件:
//   lib/shared/models/provider_brand.dart
//   lib/shared/widgets/settings/ai_providers_section.dart
//   lib/shared/widgets/settings/mobile_provider_list.dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/provider_brand.dart';
import '../../theme/theme.dart';

class ProviderLogo extends StatelessWidget {
  const ProviderLogo({super.key, required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final asset = providerLogoAsset(type);
    final colors = RevericTheme.colorsOf(context);
    return ExcludeSemantics(
      child: Container(
        width: RevericSizes.iconButtonSize,
        height: RevericSizes.iconButtonSize,
        padding: const EdgeInsets.all(RevericSpacing.xxs),
        decoration: BoxDecoration(
          // Brand artwork retains its own colors on a stable light substrate.
          color: asset == null
              ? colors.surfaceContainer
              : RevericThemeData.reveric.colors.surface,
          borderRadius: BorderRadius.circular(RevericRadius.medium),
        ),
        child: asset == null
            ? Center(
                child: Text(
                  type.isEmpty ? '?' : type.characters.first.toUpperCase(),
                  style: RevericTheme.typographyOf(
                    context,
                  ).uiSemibold.copyWith(color: colors.textMuted),
                ),
              )
            : asset.endsWith('.svg')
            ? SvgPicture.asset(asset, fit: BoxFit.contain)
            : Image.asset(asset, fit: BoxFit.contain),
      ),
    );
  }
}
