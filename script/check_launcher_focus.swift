import Foundation

@main struct LauncherFocusChecks {
    static func main() {
        var session = LauncherFocusSession<Int>()
        let han = 10, line = 20, other = 30
        session.capture(line, owner: han)
        // Calling show twice, or reopening during a closing fade, must not
        // replace LINE with Han itself.
        session.capture(han, owner: han)
        precondition(session.takeReturnTarget(frontmost: han, owner: han, hasOtherKeyWindow: false) == line)
        precondition(session.takeReturnTarget(frontmost: han, owner: han, hasOtherKeyWindow: false) == nil)
        session.capture(line, owner: han)
        precondition(session.takeReturnTarget(frontmost: other, owner: han, hasOtherKeyWindow: false) == nil, "Never steal focus after user switches apps")
        session.capture(line, owner: han)
        precondition(session.takeReturnTarget(frontmost: han, owner: han, hasOtherKeyWindow: true) == nil, "Keep settings, dialogs and other Han windows active")
        session.capture(line, owner: han); session.discard()
        precondition(session.takeReturnTarget(frontmost: han, owner: han, hasOtherKeyWindow: false) == nil, "Opening a result/internal flow must discard return activation")
        session.capture(line, owner: han); session.capture(other, owner: han)
        precondition(session.takeReturnTarget(frontmost: han, owner: han, hasOtherKeyWindow: false) == other, "A new external invocation replaces the origin")
        session.capture(nil, owner: han)
        precondition(session.takeReturnTarget(frontmost: han, owner: han, hasOtherKeyWindow: false) == nil)
        print("PASS: launcher focus return, repeated opening, interrupted fade session, one-time restore, external switch, other Han window, internal/result flow and next-origin boundaries")
    }
}
