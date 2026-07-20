import Foundation
import Testing
@testable import Planner

@Suite("Header Collision Layout")
struct HeaderCollisionLayoutTests {
    /// Supported representative widths: compact split view, compact and
    /// regular iPhones, compact iPad, and full iPads.
    private static let widths: [CGFloat] = [
        320, 393, 402, 430, 507, 768, 834, 1_024, 1_366,
    ]

    // MARK: Control budget

    @Test("The budget collapses the control at narrow widths")
    func budgetCollapsesAtNarrowWidths() {
        // At iPhone widths even a moderately wide connected capsule must
        // not fit: the month keeps its minimum footprint.
        #expect(HeaderCollisionLayout.accountControlBudget(in: 320) == 68)
        #expect(HeaderCollisionLayout.accountControlBudget(in: 393) == 104.5)
        #expect(HeaderCollisionLayout.accountControlBudget(in: 402) == 109)
    }

    @Test("The budget caps the control at wide widths")
    func budgetCapsAtWideWidths() {
        #expect(HeaderCollisionLayout.accountControlBudget(in: 834) == 280)
        #expect(HeaderCollisionLayout.accountControlBudget(in: 1_366) == 280)
    }

    @Test("The budget never drops below the activation target")
    func budgetFloor() {
        #expect(HeaderCollisionLayout.accountControlBudget(in: 200) == 44)
    }

    // MARK: Visible Month cap

    @Test("The default reservation preserves the accepted month footprint")
    func monthCapDefaultReservation() {
        #expect(
            HeaderCollisionLayout.visibleMonthMaxWidth(
                in: 393,
                controlFootprint: 96
            ) == 201
        )
        #expect(
            HeaderCollisionLayout.visibleMonthMaxWidth(
                in: 402,
                controlFootprint: 96
            ) == 210
        )
    }

    @Test("A wider control shrinks the month cap symmetrically")
    func monthCapWiderControl() {
        #expect(
            HeaderCollisionLayout.visibleMonthMaxWidth(
                in: 834,
                controlFootprint: 312
            ) == 210
        )
    }

    @Test("The month cap keeps its floor")
    func monthCapFloor() {
        #expect(
            HeaderCollisionLayout.visibleMonthMaxWidth(
                in: 320,
                controlFootprint: 400
            ) == 24
        )
    }

    // MARK: The no-overlap invariant

    @Test("An in-budget control can never overlap the centered month")
    func noOverlapInvariant() {
        for width in Self.widths {
            let budget = HeaderCollisionLayout.accountControlBudget(in: width)
            var controlWidth: CGFloat = 0
            while controlWidth <= budget {
                let footprint = controlWidth + 32
                let monthCap = HeaderCollisionLayout.visibleMonthMaxWidth(
                    in: width,
                    controlFootprint: footprint
                )
                let monthTrailingEdge = width / 2 + monthCap / 2
                let controlLeadingEdge = width - 16 - controlWidth

                #expect(
                    monthTrailingEdge <= controlLeadingEdge + 0.5,
                    "Overlap at width \(width), control \(controlWidth)"
                )
                controlWidth += 1
            }
        }
    }
}
