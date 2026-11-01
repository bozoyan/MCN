import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/components/status_animation_clock.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/ai/chat/typing_indicator.dart';

const _interval = StatusAnimationClock.interval;

bool get _hasScheduledFrame => SchedulerBinding.instance.hasScheduledFrame;

Widget _host({bool tickerEnabled = true}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: TickerMode(
        enabled: tickerEnabled,
        child: const AiTypingIndicator(colors: RevericColors.reveric),
      ),
    ),
  );
}

void main() {
  testWidgets('keeps the three-dot footprint and its own repaint layer', (
    tester,
  ) async {
    await tester.pumpWidget(_host());

    final indicator = find.byType(AiTypingIndicator);
    expect(
      tester.getSize(indicator),
      const Size(10 * 3 + RevericSpacing.xs * 2, 10),
    );
    expect(
      find.descendant(of: indicator, matching: find.byType(RepaintBoundary)),
      findsOneWidget,
    );
  });

  testWidgets('animates on the shared clock instead of vsync', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();
    expect(_hasScheduledFrame, isFalse);

    await tester.binding.delayed(_interval ~/ 2);
    expect(_hasScheduledFrame, isFalse);

    await tester.binding.delayed(_interval);
    expect(_hasScheduledFrame, isTrue);
    await tester.pump();
  });

  testWidgets('stays idle while tickers are muted', (tester) async {
    await tester.pumpWidget(_host(tickerEnabled: false));
    await tester.pump();

    await tester.binding.delayed(_interval * 3);
    expect(_hasScheduledFrame, isFalse);
  });
}
