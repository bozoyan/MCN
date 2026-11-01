import Cocoa
import FlutterMacOS
import XCTest
@testable import Reveric

class RunnerTests: XCTestCase {

  func testMainViewIsReattachedAfterEnablingMultiView() {
    let flutterViewController = FlutterViewController()

    MainFlutterWindow.prepareEngineForMultiView(flutterViewController)

    XCTAssertTrue(flutterViewController.engine.viewController === flutterViewController)

    // The windowing API calls this selector again when creating its first
    // native window. It must be an idempotent no-op instead of throwing the
    // late-enable NSInternalInconsistencyException.
    let enableMultiView = NSSelectorFromString("enableMultiView")
    XCTAssertTrue(flutterViewController.engine.responds(to: enableMultiView))
    _ = flutterViewController.engine.perform(enableMultiView)
  }

  func testRestoredWindowPositionIsKeptInsideVisibleScreen() {
    let visibleFrame = NSRect(x: 0, y: 24, width: 1440, height: 876)

    let origin = MainFlutterWindow.clampedWindowOrigin(
      NSPoint(x: 2400, y: -500),
      windowSize: NSSize(width: 640, height: 640),
      visibleFrames: [visibleFrame],
      fallbackVisibleFrame: visibleFrame
    )

    XCTAssertEqual(origin.x, 800, accuracy: 0.001)
    XCTAssertEqual(origin.y, 24, accuracy: 0.001)
  }

  func testRestoredWindowPositionPreservesNegativeDisplayCoordinates() {
    let leftDisplay = NSRect(x: -1920, y: 0, width: 1920, height: 1080)
    let primaryDisplay = NSRect(x: 0, y: 0, width: 1440, height: 900)

    let origin = MainFlutterWindow.clampedWindowOrigin(
      NSPoint(x: -1500, y: 120),
      windowSize: NSSize(width: 640, height: 640),
      visibleFrames: [leftDisplay, primaryDisplay],
      fallbackVisibleFrame: primaryDisplay
    )

    XCTAssertEqual(origin.x, -1500, accuracy: 0.001)
    XCTAssertEqual(origin.y, 120, accuracy: 0.001)
  }

}
