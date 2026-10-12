import CoreGraphics
import Testing
@testable import OryClientExample

#if DEBUG
@Suite("Tap indicator state")
@MainActor
struct TapIndicatorStateTests {

    @Test("began tracks a touch at its point")
    func beganTracksPoint() {
        var state = TapIndicatorState<Int>()

        state.began(1, at: CGPoint(x: 10, y: 20))

        #expect(state.points == [1: CGPoint(x: 10, y: 20)])
    }

    @Test("moved updates the point of a tracked touch")
    func movedUpdatesPoint() {
        var state = TapIndicatorState<Int>()
        state.began(1, at: CGPoint(x: 10, y: 20))

        state.moved(1, to: CGPoint(x: 30, y: 40))

        #expect(state.points[1] == CGPoint(x: 30, y: 40))
    }

    @Test("moved ignores an untracked touch")
    func movedIgnoresUntracked() {
        var state = TapIndicatorState<Int>()

        state.moved(99, to: CGPoint(x: 5, y: 5))

        #expect(state.points.isEmpty)
    }

    @Test("ended stops tracking the touch")
    func endedRemovesPoint() {
        var state = TapIndicatorState<Int>()
        state.began(1, at: CGPoint(x: 10, y: 20))

        state.ended(1)

        #expect(state.points[1] == nil)
    }

    @Test("tracks multiple touches independently")
    func tracksMultipleTouches() {
        var state = TapIndicatorState<Int>()

        state.began(1, at: CGPoint(x: 1, y: 1))
        state.began(2, at: CGPoint(x: 2, y: 2))
        state.ended(1)

        #expect(state.points == [2: CGPoint(x: 2, y: 2)])
    }

    @Test("clear removes all tracked touches")
    func clearRemovesAll() {
        var state = TapIndicatorState<Int>()
        state.began(1, at: CGPoint(x: 1, y: 1))
        state.began(2, at: CGPoint(x: 2, y: 2))

        state.clear()

        #expect(state.points.isEmpty)
    }
}
#endif
