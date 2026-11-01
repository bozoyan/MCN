// 职责: 验证 AI 模式错误提示会根据结构化失败展示本地化原因。
// 关联文件:
//   lib/shared/widgets/ai/ai_mode_error_notice.dart
//   lib/shared/models/ai_run_failure.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/ai_run_failure.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/ai/ai_mode_error_notice.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => rootBundle.clear());

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('shows original provider message at mobile and desktop widths', (
    tester,
  ) async {
    const message =
        'Upstream returned an unexpected response. api_key=example-secret';
    for (final width in [375.0, 1280.0]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpWidget(
        _wrap(
          const AiModeErrorNotice(
            title: 'Generation failed',
            failure: AiRunFailure.http(
              statusCode: 400,
              providerMessage: message,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('maps provider failures safely within mobile and desktop widths', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const SizedBox(
          width: 375,
          child: Padding(
            padding: EdgeInsets.all(RevericSpacing.lg),
            child: Column(
              children: [
                AiModeErrorNotice(
                  title: 'Interrupted',
                  failure: AiRunFailure.requestFailed(),
                ),
                SizedBox(height: RevericSpacing.md),
                AiModeErrorNotice(
                  title: 'Generation interrupted',
                  failure: AiRunFailure.http(
                    statusCode: 402,
                    providerId: 'custom',
                  ),
                ),
                SizedBox(height: RevericSpacing.md),
                AiModeErrorNotice(
                  title: 'Generation interrupted',
                  failure: AiRunFailure.http(
                    statusCode: 401,
                    providerId: 'custom',
                  ),
                ),
                SizedBox(height: RevericSpacing.md),
                AiModeErrorNotice(
                  title: 'Generation interrupted',
                  failure: AiRunFailure.http(
                    statusCode: 402,
                    providerId: 'openai',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Interrupted'), findsOneWidget);
    expect(find.text('Request failed, please try again later'), findsOneWidget);
    expect(
      find.text(
        'The current model service has insufficient balance or requires '
        'payment. Check your account balance and billing with the provider.',
      ),
      findsNWidgets(2),
    );
    expect(
      find.text(
        'The API key is invalid. Check it and configure the provider again.',
      ),
      findsOneWidget,
    );
    expect(find.byType(RevericIcon), findsNWidgets(4));
    expect(tester.takeException(), isNull);
    for (final width in [375.0, 1000.0]) {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: width,
            child: const AiModeErrorNotice(
              title: 'Interrupted',
              failure: AiRunFailure.http(
                statusCode: 402,
                providerId: 'custom',
                providerMessage:
                    'Provider says the account balance is insufficient.',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Provider says the account balance is insufficient.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'The current model service has insufficient balance or requires '
          'payment. Check your account balance and billing with the provider.',
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(
      _wrap(
        const AiModeErrorNotice(
          title: 'Interrupted',
          failure: AiRunFailure.http(statusCode: 410),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'The requested resource has been retired or removed. Check your provider configuration or choose another model.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _wrap(Widget child) {
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    child: Builder(
      builder: (context) {
        return MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: RevericThemeData.reveric.toThemeData(),
          home: RevericTheme(
            data: RevericThemeData.reveric,
            child: Scaffold(body: SingleChildScrollView(child: child)),
          ),
        );
      },
    ),
  );
}
