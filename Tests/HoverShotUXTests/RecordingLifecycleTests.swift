import Foundation
import XCTest
@testable import Capture

final class RecordingLifecycleTests: XCTestCase {
    func testNewStartIsReservedThroughPreparationAndActiveSession() throws {
        var lifecycle = RecordingLifecycle<String>()
        let startID = try XCTUnwrap(lifecycle.reserveNewStart())

        XCTAssertNil(lifecycle.reserveNewStart())
        XCTAssertNil(lifecycle.reserveResume())

        let session = NSObject()
        XCTAssertTrue(lifecycle.install(session, context: "Area Recording", for: startID))
        XCTAssertNotNil(lifecycle.pendingStart)
        XCTAssertFalse(lifecycle.finishStart(startID, session: NSObject()))
        XCTAssertTrue(lifecycle.finishStart(startID, session: session))

        XCTAssertNil(lifecycle.reserveNewStart())
        XCTAssertTrue(lifecycle.activeSession === session)
    }

    func testFailedCaptureStartReleasesSessionAndAllowsRetry() throws {
        var lifecycle = RecordingLifecycle<String>()
        let startID = try XCTUnwrap(lifecycle.reserveNewStart())
        let failedSession = NSObject()
        XCTAssertTrue(lifecycle.install(failedSession, context: "Area Recording", for: startID))

        XCTAssertTrue(lifecycle.failStart(startID, session: failedSession, restoring: nil))
        XCTAssertNil(lifecycle.pendingStart)
        XCTAssertNil(lifecycle.activeSession)
        XCTAssertNil(lifecycle.resumeContext)

        let retryID = try XCTUnwrap(lifecycle.reserveNewStart())
        let retrySession = NSObject()
        XCTAssertTrue(lifecycle.install(retrySession, context: "Retry", for: retryID))
        XCTAssertFalse(lifecycle.complete(failedSession))
        XCTAssertTrue(lifecycle.activeSession === retrySession)
        XCTAssertEqual(lifecycle.resumeContext, "Retry")
    }

    func testFailedResumeRestoresPausedSegmentAndAllowsResumeRetry() throws {
        var lifecycle = RecordingLifecycle<String>()
        let firstID = try XCTUnwrap(lifecycle.reserveNewStart())
        let firstSession = NSObject()
        XCTAssertTrue(lifecycle.install(firstSession, context: "Part 1", for: firstID))
        XCTAssertTrue(lifecycle.finishStart(firstID, session: firstSession))
        XCTAssertTrue(lifecycle.complete(firstSession))

        let resumeID = try XCTUnwrap(lifecycle.reserveResume())
        XCTAssertNil(lifecycle.reserveResume())
        let failedSession = NSObject()
        XCTAssertTrue(lifecycle.install(failedSession, context: "Part 2", for: resumeID))
        XCTAssertTrue(lifecycle.failStart(resumeID, session: failedSession, restoring: "Part 1"))

        XCTAssertNil(lifecycle.activeSession)
        XCTAssertEqual(lifecycle.resumeContext, "Part 1")
        XCTAssertNotNil(lifecycle.reserveResume())
    }

    func testEarlyCompletionAndLateStartCallbacksCannotAffectNextSession() throws {
        var lifecycle = RecordingLifecycle<String>()
        let firstID = try XCTUnwrap(lifecycle.reserveNewStart())
        let firstSession = NSObject()
        XCTAssertTrue(lifecycle.install(firstSession, context: "First", for: firstID))
        XCTAssertTrue(lifecycle.complete(firstSession))
        XCTAssertNil(lifecycle.pendingStart)

        lifecycle.clearResumeContext()
        let nextID = try XCTUnwrap(lifecycle.reserveNewStart())
        let nextSession = NSObject()
        XCTAssertTrue(lifecycle.install(nextSession, context: "Next", for: nextID))
        XCTAssertFalse(lifecycle.finishStart(firstID, session: firstSession))
        XCTAssertFalse(lifecycle.complete(firstSession))
        XCTAssertTrue(lifecycle.activeSession === nextSession)
        XCTAssertEqual(lifecycle.pendingStart, nextID)
    }

    func testDidStartCallbackOnlyAdvancesItsOwnStartingSession() throws {
        var lifecycle = RecordingLifecycle<String>()
        let startID = try XCTUnwrap(lifecycle.reserveNewStart())
        let session = NSObject()
        let outputURL = URL(fileURLWithPath: "/tmp/recording.mp4")
        XCTAssertTrue(lifecycle.install(session, context: "Recording", for: startID))
        XCTAssertTrue(lifecycle.acceptsDidStart(from: session, outputURL: outputURL, state: .starting(outputURL)))
        XCTAssertFalse(lifecycle.acceptsDidStart(from: session, outputURL: outputURL, state: .stopping(outputURL)))
        XCTAssertFalse(lifecycle.acceptsDidStart(from: NSObject(), outputURL: outputURL, state: .starting(outputURL)))
    }
}
