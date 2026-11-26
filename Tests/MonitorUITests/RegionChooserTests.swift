import MonitorCore
import XCTest

@testable import MonitorUI

@MainActor
final class RegionChooserTests: XCTestCase {
    /// Fastest first, then regions still measuring, then those that never answered; ties keep the catalog order.
    func testSortsFastestFirst() {
        let regions = Array(CloudRegion.regions(of: .aws).prefix(5))
        let model = RegionLatencyModel(readings: [
            regions[0].id: .noAnswer,
            regions[1].id: .milliseconds(140),
            regions[2].id: .milliseconds(30),
            regions[4].id: .milliseconds(140),
        ])
        XCTAssertEqual(
            model.sorted(regions).map(\.code), [regions[2], regions[1], regions[4], regions[3], regions[0]].map(\.code))
        XCTAssertEqual(model.reading(regions[3]), .measuring)
    }

    /// The chooser shows fixed readings without measuring anything.
    func testFixedReadingsDoNotMeasure() {
        let region = CloudRegion.defaultFirst
        let model = RegionLatencyModel(readings: [region.id: .milliseconds(34)])
        model.measure(.aws)
        XCTAssertEqual(model.reading(region), .milliseconds(34))
    }
}
