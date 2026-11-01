import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/components/reveric_spinner.dart';
import 'package:reveric/shared/components/status_animation_clock.dart';

const _color = Color(0xFF8B7355);

const _interval = StatusAnimationClock.interval;

Widget _host(Widget child) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: child),
  );
}

Widget _spinners({int count = 2, bool tickerEnabled = true, double? value}) {
  return _host(
    TickerMode(
      enabled: tickerEnabled,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            SizedBox.square(
              dimension: 12,
              child: RevericSpinner(color: _color, value: value),
            ),
        ],
      ),
    ),
  );
}

bool get _hasScheduledFrame => SchedulerBinding.instance.hasScheduledFrame;

void main() {
  testWidgets('does not request vsync frames between clock ticks', (
    tester,
  ) async {
    await tester.pumpWidget(_spinners());
    await tester.pump();

    expect(_hasScheduledFrame, isFalse);

    await tester.binding.delayed(_interval ~/ 2);
    expect(_hasScheduledFrame, isFalse);

    await tester.binding.delayed(_interval);
    expect(_hasScheduledFrame, isTrue);

    await tester.pump();
    expect(_hasScheduledFrame, isFalse);
  });

  testWidgets('stays idle when tickers are muted or the value is fixed', (
    tester,
  ) async {
    await tester.pumpWidget(_spinners(tickerEnabled: false));
    await tester.pump();
    await tester.binding.delayed(_interval * 3);
    expect(_hasScheduledFrame, isFalse);

    await tester.pumpWidget(_spinners(value: 0.5));
    await tester.pump();
    await tester.binding.delayed(_interval * 3);
    expect(_hasScheduledFrame, isFalse);
  });

  testWidgets('resumes after tickers are re-enabled', (tester) async {
    await tester.pumpWidget(_spinners(tickerEnabled: false));
    await tester.pump();

    await tester.pumpWidget(_spinners());
    await tester.pump();
    await tester.binding.delayed(_interval * 2);
    expect(_hasScheduledFrame, isTrue);
  });

  testWidgets('releases the shared clock when the last spinner unmounts', (
    tester,
  ) async {
    await tester.pumpWidget(_spinners(count: 3));
    await tester.pump();

    await tester.pumpWidget(_host(const SizedBox()));
    await tester.pump();
    await tester.binding.delayed(_interval * 3);
    expect(_hasScheduledFrame, isFalse);
  });

  testWidgets('fills tight constraints and repaints in its own layer', (
    tester,
  ) async {
    await tester.pumpWidget(_spinners(count: 1));

    final spinner = find.byType(RevericSpinner);
    expect(tester.getSize(spinner), const Size.square(12));
    expect(
      find.descendant(of: spinner, matching: find.byType(RepaintBoundary)),
      findsOneWidget,
    );
  });

  test('both arc ends only move clockwise', () {
    // Signed shortest step between two angles, in (-pi, pi].
    double step(double from, double to) {
      final d = (to - from) % (math.pi * 2);
      return d > math.pi ? d - math.pi * 2 : d;
    }

    const dt = 1 / 240;
    var previous = spinnerArcAt(0);
    for (var i = 1; i <= 240 * 6; i++) {
      final arc = spinnerArcAt(i * dt);
      expect(step(previous.start, arc.start), greaterThanOrEqualTo(0));
      expect(
        step(previous.start + previous.sweep, arc.start + arc.sweep),
        greaterThanOrEqualTo(0),
      );
      expect(arc.sweep, greaterThan(0));
      previous = arc;
    }
  });
}
