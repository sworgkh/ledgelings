import CoreGraphics
import Testing
@testable import LedgelingsCore

/// Every window the app opens can be dragged, and a dragged one reopens where it was let go.
@Suite struct WindowPlacesTests {
    let laptop = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let monitor = CGRect(x: 1440, y: 0, width: 1920, height: 1055)

    @Test func everyWindowMovesButTheOverlaysOverTheScreen() {
        let fixed: Set<WindowPlaces.Window> = [.overlay, .shotScreens, .shotToolbar, .clipToast, .clipGhost]
        for window in WindowPlaces.Window.allCases {
            #expect(window.movable == !fixed.contains(window), "\(window)")
            #expect(window.remembered == window.movable, "\(window)")
        }
        let movable: Set<WindowPlaces.Window> = [.settings, .relationships, .snippets, .actions, .reminder,
                                                 .tools, .translate, .readAloud, .clipPicker]
        #expect(Set(WindowPlaces.Window.allCases.filter(\.movable)) == movable)
    }

    @Test func aSavedPlaceOnAScreenIsWhereItReopens() {
        let size = CGSize(width: 600, height: 400)
        let frame = WindowPlaces.frame(topLeft: CGPoint(x: 1600, y: 900), size: size, screens: [laptop, monitor])
        #expect(frame == CGRect(x: 1600, y: 500, width: 600, height: 400))
    }

    @Test func aPlaceOnAMonitorThatIsGoneIsForgotten() {
        let size = CGSize(width: 600, height: 400)
        #expect(WindowPlaces.frame(topLeft: CGPoint(x: 1600, y: 900), size: size, screens: [laptop]) == nil)
        #expect(WindowPlaces.frame(topLeft: CGPoint(x: -900, y: 500), size: size, screens: [laptop, monitor]) == nil)
    }

    @Test func aWindowHangingOffItsScreenIsPulledBackIn() {
        let size = CGSize(width: 600, height: 400)
        // Its title strip is on the laptop, the rest past its right edge and bottom.
        let frame = WindowPlaces.frame(topLeft: CGPoint(x: 1300, y: 200), size: size, screens: [laptop])
        #expect(frame == CGRect(x: 840, y: 0, width: 600, height: 400))
    }

    @Test func aPaperStaysInsideItsPanel() {
        let room = CGSize(width: 1440, height: 875)
        let paper = CGRect(x: -40, y: 700, width: 560, height: 400)
        #expect(WindowPlaces.paper(paper, inside: room) == CGRect(x: 0, y: 475, width: 560, height: 400))
        #expect(WindowPlaces.paper(CGRect(x: 100.4, y: 60.6, width: 560, height: 400), inside: room).origin == CGPoint(x: 100, y: 61))
    }
}
