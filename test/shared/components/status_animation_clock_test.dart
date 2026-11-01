import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/components/reveric_spinner.dart';
import 'package:reveric/shared/components/status_animation_clock.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/ai/chat/typing_indicator.dart';

const _interval = StatusAnimationClock.interval;

bool get _hasScheduledFrame => SchedulerBinding.instance.hasScheduledFrame;

Widget _host({required bool withTyping}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 12,
            child: RevericSpinner(color: Color(0xFF8B7355)),
          ),
          if (withTyping)
            const AiTypingIndicator(colors: RevericColors.reveric),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('status animations mounted at different times share ticks', (
    tester,
  ) async {
    await tester.pumpWidget(_host(withTyping: false));
    await tester.pump();

    // Mount the second animation half an interval later. Separate timers would
    // then fire out of phase and double the frame rate.
    await tester.binding.delayed(_interval ~/ 2);
    await tester.pumpWidget(_host(withTyping: true));
    await tester.pump();
    expect(_hasScheduledFrame, isFalse);

    await tester.binding.delayed(_interval ~/ 2 + _interval ~/ 10);
    expect(_hasScheduledFrame, isTrue);
    await tester.pump();

    await tester.binding.delayed(_interval ~/ 2);
    expect(_hasScheduledFrame, isFalse);

    await tester.binding.delayed(_interval ~/ 2);
    expect(_hasScheduledFrame, isTrue);
    await tester.pump();
  });
}
