// 职责: 共享远程桥接设置区 — WeChat QR 登录、桥接开关、状态指示
// 关联文件:
//   lib/shared/services/remote/remote_bridge_service.dart
//   lib/shared/providers/remote_bridge_providers.dart
//   lib/shared/localization/locale_keys.dart
//   lib/shared/theme/theme.dart
//   lib/shared/widgets/settings/settings_section_widgets.dart
//   assets/translations/en/remote.json
//   assets/translations/zh-CN/remote.json
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../components/reveric_button.dart';
import '../../components/reveric_switch.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../providers/remote_bridge_providers.dart';
import '../../services/remote/remote_bridge_service.dart';
import '../../theme/theme.dart';
import 'settings_section_widgets.dart';

/// 远程桥接设置 section。
///
/// 桌面端与移动端共用：按登录态展示 WeChat 登录二维码（未登录）或远程控制开关（已登录）。
class RemoteBridgeSettingsSection extends HookConsumerWidget {
  const RemoteBridgeSettingsSection({super.key});

  /// 「查看套餐」动作（桌面端切设置导航，移动端 push 套餐页）。

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(remoteBridgeServiceProvider);
    // 触发 coordinator 实例化，确保 inbound handler 已注册到 bridge。
    ref.watch(assistantCoordinatorProvider);
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    // 订阅 service 状态变化（ChangeNotifier），用 revision 触发重建
    final revision = useState(0);
    useEffect(() {
      void onChanged() {
        revision.value += 1;
      }

      service.addListener(onChanged);
      return () => service.removeListener(onChanged);
    }, [service]);

    // section 销毁时取消进行中的登录流（showingQr/scanned/expired），
    // 避免 dialog 关闭后 QR 轮询仍在后台空跑。
    useEffect(() {
      return () {
        if (service.isLoginInProgress) {
          unawaited(service.cancelLogin());
        }
      };
    }, [service]);

    // 开关先落到服务再落库：start 抛错（未登录）时不会留下与实际状态不符的持久化值。
    Future<void> setBridgeEnabled(bool value) async {
      if (value) {
        await service.start();
      } else {
        await service.stop();
      }
      await ref.read(remoteBridgeEnabledWriterProvider)(value);
    }

    final loginPhase = service.loginPhase;
    final isLoggedIn = service.isLoggedIn;
    final isRunning = service.isRunning;
    final qrImageUrl = service.qrImageUrl;
    final loginError = service.loginError;
    final lastError = service.lastError;
    // 已登录且无进行中的登录流（idle/confirmed）→ 显示连接卡；
    // 否则（未登录，或正在切换账号的扫码流）→ 显示登录卡以渲染二维码。
    final showConnected =
        isLoggedIn &&
        (loginPhase == BridgeLoginPhase.idle ||
            loginPhase == BridgeLoginPhase.confirmed);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(RevericSpacing.x4l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(context, locked: false),
          const SizedBox(height: RevericSpacing.x3l),
          if (showConnected)
            _buildConnectedCard(
              context: context,
              colors: colors,
              typo: typo,
              service: service,
              isRunning: isRunning,
              lastError: lastError,
              onToggle: setBridgeEnabled,
            )
          else
            _buildLoginCard(
              context: context,
              colors: colors,
              typo: typo,
              service: service,
              loginPhase: loginPhase,
              qrImageUrl: qrImageUrl,
              loginError: loginError,
              lastError: lastError,
              onStartLogin: () => service.startLogin(),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, {required bool locked}) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              context.t(LocaleKeys.settingsRemote),
              style: typo.uiSemibold.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: RevericSpacing.xs),
        Text(
          context.t(LocaleKeys.remoteSettingsDescription),
          style: typo.ui.copyWith(color: colors.textMuted),
        ),
      ],
    );
  }

  Widget _buildLoginCard({
    required BuildContext context,
    required RevericColors colors,
    required RevericTypography typo,
    required RemoteBridgeService service,
    required BridgeLoginPhase loginPhase,
    required String? qrImageUrl,
    required String? loginError,
    required String? lastError,
    required VoidCallback onStartLogin,
  }) {
    return switch (loginPhase) {
      BridgeLoginPhase.idle => _buildFeatureCard(
        context: context,
        colors: colors,
        typo: typo,
        service: service,
        lastError: lastError,
        onStartLogin: onStartLogin,
      ),
      BridgeLoginPhase.showingQr => _buildQrLoginCard(
        context: context,
        colors: colors,
        typo: typo,
        qrImageUrl: qrImageUrl,
        service: service,
      ),
      BridgeLoginPhase.scanned => _buildScannedCard(
        context: context,
        colors: colors,
        typo: typo,
        service: service,
      ),
      BridgeLoginPhase.expired => _buildExpiredCard(
        context: context,
        colors: colors,
        typo: typo,
      ),
      BridgeLoginPhase.confirmed => _buildConfirmedCard(
        context: context,
        colors: colors,
        typo: typo,
      ),
      BridgeLoginPhase.error => _buildErrorCard(
        context: context,
        colors: colors,
        typo: typo,
        loginError: loginError,
        service: service,
        onStartLogin: onStartLogin,
      ),
    };
  }

  Widget _buildFeatureCard({
    required BuildContext context,
    required RevericColors colors,
    required RevericTypography typo,
    required RemoteBridgeService service,
    required String? lastError,
    required VoidCallback onStartLogin,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(RevericRadius.xl),
        border: Border.all(color: colors.borderInput),
      ),
      child: Column(
        children: [
          _FeatureCardHero(colors: colors),
          _FeatureCardBody(
            context: context,
            colors: colors,
            typo: typo,
            service: service,
            lastError: lastError,
            onStartLogin: onStartLogin,
          ),
        ],
      ),
    );
  }

  Widget _buildQrLoginCard({
    required BuildContext context,
    required RevericColors colors,
    required RevericTypography typo,
    required String? qrImageUrl,
    required RemoteBridgeService service,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.borderInput),
      ),
      padding: const EdgeInsets.all(RevericSpacing.x2l),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _QrImage(qrImageUrl: qrImageUrl, size: 120, colors: colors),
          const SizedBox(width: RevericSpacing.x2l),
          Expanded(
            child: _QrLoginInfo(
              context: context,
              colors: colors,
              typo: typo,
              service: service,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannedCard({
    required BuildContext context,
    required RevericColors colors,
    required RevericTypography typo,
    required RemoteBridgeService service,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.borderInput),
      ),
      padding: const EdgeInsets.all(RevericSpacing.x2l),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.accent,
            ),
          ),
          const SizedBox(width: RevericSpacing.sm),
          Expanded(
            child: Text(
              context.t(LocaleKeys.remoteLoginScanned),
              style: typo.ui.copyWith(color: colors.textPrimary),
            ),
          ),
          TextButton(
            onPressed: () => service.cancelLogin(),
            child: Text(context.t(LocaleKeys.remoteLoginCancel)),
          ),
        ],
      ),
    );
  }

  Widget _buildExpiredCard({
    required BuildContext context,
    required RevericColors colors,
    required RevericTypography typo,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.borderInput),
      ),
      padding: const EdgeInsets.all(RevericSpacing.x2l),
      child: Row(
        children: [
          RevericIcon(
            RevericIcons.arrow_clockwise,
            size: 16,
            color: colors.textSecondary,
          ),
          const SizedBox(width: RevericSpacing.sm),
          Expanded(
            child: Text(
              context.t(LocaleKeys.remoteLoginExpired),
              style: typo.ui.copyWith(color: colors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmedCard({
    required BuildContext context,
    required RevericColors colors,
    required RevericTypography typo,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.borderInput),
      ),
      padding: const EdgeInsets.all(RevericSpacing.x2l),
      child: Row(
        children: [
          RevericIcon(
            RevericIcons.check_circle,
            size: 16,
            color: colors.success,
          ),
          const SizedBox(width: RevericSpacing.sm),
          Expanded(
            child: Text(
              context.t(LocaleKeys.remoteConnected),
              style: typo.ui.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard({
    required BuildContext context,
    required RevericColors colors,
    required RevericTypography typo,
    required String? loginError,
    required RemoteBridgeService service,
    required VoidCallback onStartLogin,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.borderInput),
      ),
      padding: const EdgeInsets.all(RevericSpacing.x2l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RevericIcon(
                RevericIcons.error_outline,
                size: 16,
                color: colors.error,
              ),
              const SizedBox(width: RevericSpacing.sm),
              Expanded(
                child: Text(
                  context.t(LocaleKeys.remoteLoginFailed),
                  style: typo.ui.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
          if (loginError != null) ...[
            const SizedBox(height: RevericSpacing.xs),
            Text(
              loginError,
              style: typo.uiSmall.copyWith(color: colors.textMuted),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: RevericSpacing.md),
          RevericButton.primary(
            onPressed: onStartLogin,
            icon: RevericIcons.arrow_clockwise,
            label: context.t(LocaleKeys.remoteLoginWechat),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedCard({
    required BuildContext context,
    required RevericColors colors,
    required RevericTypography typo,
    required RemoteBridgeService service,
    required bool isRunning,
    required String? lastError,
    required Future<void> Function(bool value) onToggle,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.borderInput),
      ),
      child: Column(
        children: [
          _ConnectedStatusRow(
            context: context,
            colors: colors,
            typo: typo,
            isRunning: isRunning,
            onToggle: onToggle,
          ),
          if (lastError != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RevericSpacing.x2l,
              ),
              child: Text(
                context.t(
                  LocaleKeys.remoteLastError,
                  namedArgs: {'error': lastError},
                ),
                style: typo.uiSmall.copyWith(color: colors.textMuted),
              ),
            ),
          const SizedBox(height: RevericSpacing.md),
          const SettingsRowDivider(),
          const SizedBox(height: RevericSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.x2l),
            child: Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => service.logout(),
                  child: Text(
                    context.t(LocaleKeys.remoteLogout),
                    style: typo.uiSmall.copyWith(color: colors.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 功能卡片 Hero 区域 — 设备图标 + 连接线 + 微信图标
class _FeatureCardHero extends StatelessWidget {
  const _FeatureCardHero({required this.colors});

  final RevericColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.accent.withValues(alpha: 0.08),
            colors.accent.withValues(alpha: 0.02),
          ],
        ),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DeviceIcon(colors: colors),
            const SizedBox(width: RevericSpacing.xl),
            _ConnectionLine(color: colors.accent),
            const SizedBox(width: RevericSpacing.xl),
            _WechatIcon(),
          ],
        ),
      ),
    );
  }
}

/// 设备图标
class _DeviceIcon extends StatelessWidget {
  const _DeviceIcon({required this.colors});

  final RevericColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 80,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.borderInput, width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 48,
            decoration: BoxDecoration(
              color: colors.surfaceDim,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Center(
              child: RevericIcon(
                RevericIcons.terminal_rounded,
                size: 16,
                color: colors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 连接线（虚线 + 两端圆点）
class _ConnectionLine extends StatelessWidget {
  const _ConnectionLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(40, 4),
      painter: _ConnectionLinePainter(color: color),
    );
  }
}

class _ConnectionLinePainter extends CustomPainter {
  _ConnectionLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Draw dashed line
    const dashWidth = 4.0;
    const dashSpace = 4.0;
    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, size.height / 2),
        Offset(startX + dashWidth, size.height / 2),
        paint,
      );
      startX += dashWidth + dashSpace;
    }

    // Draw dots at ends
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(0, size.height / 2), 3, dotPaint);
    canvas.drawCircle(Offset(size.width, size.height / 2), 3, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 微信图标
class _WechatIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFF07C160),
        borderRadius: BorderRadius.circular(RevericRadius.large),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF07C160).withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: RevericIcon(RevericIcons.qr_code, size: 28, color: Colors.white),
      ),
    );
  }
}

/// 功能卡片 Body 区域
class _FeatureCardBody extends StatelessWidget {
  const _FeatureCardBody({
    required this.context,
    required this.colors,
    required this.typo,
    required this.service,
    required this.lastError,
    required this.onStartLogin,
  });

  final BuildContext context;
  final RevericColors colors;
  final RevericTypography typo;
  final RemoteBridgeService service;
  final VoidCallback onStartLogin;

  /// 桥接最近错误。被 -14 踢下线后登录阶段回到 idle 落到本卡片，
  /// 这里显示原因，否则用户只看到「未登录」，不知道是被动掉线。
  final String? lastError;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RevericSpacing.x2l,
        RevericSpacing.x2l,
        RevericSpacing.x2l,
        RevericSpacing.x3l,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t(LocaleKeys.remoteLoginFeatureTitle),
            style: typo.uiSemibold.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: RevericSpacing.xs),
          Text(
            context.t(LocaleKeys.remoteLoginFeatureDescription),
            style: typo.uiSmall.copyWith(color: colors.textMuted),
          ),
          if (lastError != null) ...[
            const SizedBox(height: RevericSpacing.sm),
            Text(
              context.t(
                LocaleKeys.remoteLastError,
                namedArgs: {'error': lastError!},
              ),
              style: typo.uiSmall.copyWith(color: colors.error),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: RevericSpacing.x2l),
          RevericButton.primary(
            onPressed: onStartLogin,
            icon: RevericIcons.qr_code,
            label: context.t(LocaleKeys.remoteLoginWechat),
          ),
        ],
      ),
    );
  }
}

/// QR 登录卡片信息区域（步骤说明）
class _QrLoginInfo extends StatelessWidget {
  const _QrLoginInfo({
    required this.context,
    required this.colors,
    required this.typo,
    required this.service,
  });

  final BuildContext context;
  final RevericColors colors;
  final RevericTypography typo;
  final RemoteBridgeService service;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              context.t(LocaleKeys.remoteLoginQrPrompt),
              style: typo.uiSemibold.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(width: RevericSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: RevericSpacing.xs,
                vertical: RevericSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF07C160).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(RevericRadius.pill),
              ),
              child: Text(
                context.t(LocaleKeys.remoteLoginBadge),
                style: typo.uiSmall.copyWith(
                  color: const Color(0xFF07C160),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: RevericSpacing.lg),
        _LoginStep(
          number: '1',
          text: context.t(LocaleKeys.remoteLoginStep1),
          colors: colors,
          typo: typo,
        ),
        const SizedBox(height: RevericSpacing.sm),
        _LoginStep(
          number: '2',
          text: context.t(LocaleKeys.remoteLoginStep2),
          colors: colors,
          typo: typo,
        ),
        const SizedBox(height: RevericSpacing.sm),
        _LoginStep(
          number: '3',
          text: context.t(LocaleKeys.remoteLoginStep3),
          colors: colors,
          typo: typo,
        ),
      ],
    );
  }
}

/// 登录步骤
class _LoginStep extends StatelessWidget {
  const _LoginStep({
    required this.number,
    required this.text,
    required this.colors,
    required this.typo,
  });

  final String number;
  final String text;
  final RevericColors colors;
  final RevericTypography typo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: colors.surfaceDim,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.borderSubtle),
          ),
          child: Center(
            child: Text(
              number,
              style: typo.uiSmall.copyWith(
                color: colors.textMuted,
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
          ),
        ),
        const SizedBox(width: RevericSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: typo.uiSmall.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// 已连接状态行
class _ConnectedStatusRow extends StatefulWidget {
  const _ConnectedStatusRow({
    required this.context,
    required this.colors,
    required this.typo,
    required this.isRunning,
    required this.onToggle,
  });

  final BuildContext context;
  final RevericColors colors;
  final RevericTypography typo;
  final bool isRunning;

  /// 开关回调 — 启停桥接并把用户意图持久化到 AppSettings。
  final Future<void> Function(bool value) onToggle;

  @override
  State<_ConnectedStatusRow> createState() => _ConnectedStatusRowState();
}

class _ConnectedStatusRowState extends State<_ConnectedStatusRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _pulseAnimation = Tween<double>(begin: 3, end: 6).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.x2l,
        vertical: RevericSpacing.x2l,
      ),
      decoration: BoxDecoration(
        color: widget.colors.success.withValues(alpha: 0.04),
        border: Border(bottom: BorderSide(color: widget.colors.borderSubtle)),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              final color = widget.isRunning
                  ? widget.colors.success
                  : widget.colors.textMuted;
              final shadowAlpha = widget.isRunning ? 0.15 : 0.0;
              final shadowRadius = widget.isRunning
                  ? _pulseAnimation.value
                  : 0.0;
              return Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: shadowAlpha),
                      blurRadius: shadowRadius,
                      spreadRadius: shadowRadius - 3,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: RevericSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t(LocaleKeys.remoteConnectedStatus),
                  style: widget.typo.uiSemibold.copyWith(
                    color: widget.colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  widget.isRunning
                      ? context.t(LocaleKeys.remoteConnectedSubtitle)
                      : context.t(LocaleKeys.remoteBridgeStopped),
                  style: widget.typo.uiSmall.copyWith(
                    color: widget.colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          RevericSwitch(
            value: widget.isRunning,
            onChanged: (value) => widget.onToggle(value),
          ),
        ],
      ),
    );
  }
}

/// 二维码图片渲染：支持 URL 与 base64 两种形式。
class _QrImage extends StatelessWidget {
  const _QrImage({
    required this.qrImageUrl,
    required this.size,
    required this.colors,
  });

  final String? qrImageUrl;
  final double size;
  final RevericColors colors;

  @override
  Widget build(BuildContext context) {
    if (qrImageUrl == null || qrImageUrl!.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(RevericRadius.medium),
          border: Border.all(color: colors.borderInput),
        ),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.accent,
            ),
          ),
        ),
      );
    }

    if (_isWechatMiniAppUrl(qrImageUrl!)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        child: Container(
          width: size,
          height: size,
          color: colors.surface,
          child: Center(
            child: QrImageView(
              data: qrImageUrl!,
              size: size - 20,
              eyeStyle: QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: colors.textPrimary,
              ),
              dataModuleStyle: QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: colors.textPrimary,
              ),
              backgroundColor: colors.surface,
              padding: EdgeInsets.zero,
            ),
          ),
        ),
      );
    }

    final provider = _resolveImageProvider(qrImageUrl!);
    if (provider == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        child: Container(
          width: size,
          height: size,
          color: colors.surface,
          child: Center(
            child: RevericIcon(
              RevericIcons.broken_image_outlined,
              size: 32,
              color: colors.textMuted,
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(RevericRadius.medium),
      child: Image(
        image: provider,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stack) => Container(
          width: size,
          height: size,
          color: colors.surface,
          child: Center(
            child: RevericIcon(
              RevericIcons.broken_image_outlined,
              size: 32,
              color: colors.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  bool _isWechatMiniAppUrl(String url) {
    return url.startsWith('https://liteapp.weixin.qq.com/') ||
        url.startsWith('https://weixin.qq.com/x/');
  }

  ImageProvider? _resolveImageProvider(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return NetworkImage(url);
    }
    final pure = url.startsWith('data:')
        ? url.substring(url.indexOf(',') + 1)
        : url;
    try {
      final bytes = base64Decode(pure);
      return MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }
}
