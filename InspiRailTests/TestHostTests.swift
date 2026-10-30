//
//  TestHostTests.swift
//  InspiRailTests
//

import Testing
@testable import InspiRail

/// The unit tests run inside the app. When it hosts them, the app shows an
/// empty scene and makes no requests (#15). `InspiRail.xctestplan` marks the
/// host by setting `INSPIRAIL_UNIT_TEST_HOST=1` in its environment.
@Suite("Unit-test host")
struct TestHostTests {
    @Test("This test run's host knows it is hosting the unit tests")
    func currentProcessIsTheTestHost() {
        #expect(AppConfiguration.isHostingUnitTests())
    }

    @Test("A normal launch, or the app a UI test launches, is not the test host")
    func normalLaunchIsNotTheTestHost() {
        #expect(!AppConfiguration.isHostingUnitTests(environment: [:]))
        // What Xcode 26 puts in the environment of the app a UI test launches.
        #expect(!AppConfiguration.isHostingUnitTests(environment: [
            "XCODE_SCHEME_NAME": "InspiRail",
            "XCODE_TEST_PLAN_NAME": "InspiRail",
        ]))
    }

    @Test("Only the value 1 marks the test host")
    func onlyOneMarksTheTestHost() {
        #expect(AppConfiguration.isHostingUnitTests(environment: ["INSPIRAIL_UNIT_TEST_HOST": "1"]))
        #expect(!AppConfiguration.isHostingUnitTests(environment: ["INSPIRAIL_UNIT_TEST_HOST": "0"]))
        #expect(!AppConfiguration.isHostingUnitTests(environment: ["INSPIRAIL_UNIT_TEST_HOST": ""]))
    }
}
