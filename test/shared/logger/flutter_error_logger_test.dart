import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/logger/flutter_error_logger.dart';

void main() {
  test('forwards Flutter framework errors to presenter and log sink', () {
    final previousHandler = FlutterError.onError;
    addTearDown(() {
      FlutterError.onError = previousHandler;
    });

    FlutterErrorDetails? presentedDetails;
    String? loggedMessage;
    Object? loggedError;
    StackTrace? loggedStackTrace;

    installFlutterErrorLogger(
      presentErrorOverride: (details) {
        presentedDetails = details;
      },
      logErrorOverride: (message, {error, stackTrace}) {
        loggedMessage = message;
        loggedError = error;
        loggedStackTrace = stackTrace;
      },
    );

    final stackTrace = StackTrace.current;
    final exception = FlutterError('A RenderFlex overflowed by 10 pixels.');
    final details = FlutterErrorDetails(
      exception: exception,
      stack: stackTrace,
      library: 'rendering library',
      context: ErrorDescription('during layout'),
    );

    FlutterError.reportError(details);

    expect(presentedDetails, same(details));
    expect(loggedMessage, contains('A RenderFlex overflowed by 10 pixels.'));
    expect(loggedError, same(exception));
    expect(loggedStackTrace, same(stackTrace));
  });
}
