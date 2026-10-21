import Foundation
import HanSearchCore

extension ChineseSearchTests {
    func testOCRScheduling() throws {
        func decision(_ power: OCRResourceState.Power = .external, percent: Int? = nil, idle: Double = 0,
                      low: Bool = false, hot: Bool = false, battery: Bool = false, idleOnly: Bool = false) -> OCRWorkDecision {
            .evaluate(OCRResourceState(power: power, batteryPercent: percent, idleSeconds: idle, lowPower: low, thermalElevated: hot), allowBattery: battery, idleOnly: idleOnly)
        }
        precondition(decision() == .active && decision(idle: 90) == .idle)
        precondition(decision(idle: 89, idleOnly: true) == .waitingForIdle)
        precondition(decision(idle: 90, idleOnly: true) == .idle)
        precondition(decision(.battery, percent: 100, idle: 300) == .waitingForPower)
        precondition(decision(.battery, percent: 80, idle: 89, battery: true) == .waitingForIdle)
        precondition(decision(.battery, percent: 31, idle: 90, battery: true) == .batteryIdle)
        precondition(decision(.battery, percent: 30, idle: 90, battery: true) == .lowBattery)
        precondition(decision(.battery, idle: 300, battery: true) == .lowBattery)
        precondition(decision(.unknown, idle: 300, battery: true) == .unknownPower)
        precondition(decision(idle: 300, low: true) == .lowPower)
        precondition(decision(idle: 300, hot: true) == .cooling)
        precondition(decision(.battery, percent: 80, idle: 300, low: true, battery: true) == .lowPower)
        precondition(OCRWorkDecision.active.interval! > OCRWorkDecision.idle.interval!)
        precondition(OCRWorkDecision.batteryIdle.interval! > OCRWorkDecision.active.interval!)
        var working = OCRResourceState(power: .external, idleSeconds: 900,
                                       workActivity: OCRWorkActivity(protectedApp: "Logic Pro"))
        precondition(OCRWorkDecision.evaluate(working) == .protectedApp, "Opening a work app overrides idle acceleration")
        precondition(OCRWorkDecision.evaluate(working, protectWork: false) == .idle)
        for activity in [OCRWorkActivity.Audio.input, .inputAndOutput] {
            working.workActivity = OCRWorkActivity(audio: activity)
            precondition(OCRWorkDecision.evaluate(working) == .audioInput)
        }
        working.workActivity = OCRWorkActivity(audio: .output)
        precondition(OCRWorkDecision.evaluate(working) == .audioOutput)
        precondition(OCRWorkDecision.evaluate(working, protectAudio: false) == .idle)
        working.workActivity = OCRWorkActivity(audio: .unavailable)
        precondition(OCRWorkDecision.evaluate(working) == .audioUnavailable)
        working.workActivity = OCRWorkActivity()
        precondition(OCRWorkDecision.evaluate(working) == .idle, "Quiet state recovers normal scheduling")
        precondition(OCRWorkDecision.protectedApp.interval == nil && OCRWorkDecision.audioInput.interval == nil)
        let cancelled = ProcessCancellation(); cancelled.cancel()
        do { try OCRWorkScheduler { .idle }.prepare(cancellation: cancelled); preconditionFailure("Cancellation required") }
        catch is CancellationError {} catch { preconditionFailure("Wrong cancellation error") }
        let stopped = OCRWorkScheduler { .waitingForPower }
        let start = Date()
        do { try stopped.prepare(cancellation: ProcessCancellation()); preconditionFailure("Must defer") }
        catch DocumentReadReason.ocrDeferred {} catch { preconditionFailure("Wrong defer error") }
        precondition(Date().timeIntervalSince(start) < 0.5, "Waiting must release the worker, not block until power returns")
        let phase = SourceHealth(phase: .waiting, partialUpdate: Date())
        precondition(!phase.shouldRefresh(at: Date().addingTimeInterval(3600), interval: 900, force: true))
        // Read public system state without requesting permissions or changing any settings.
        let current = OCRResourceState.current()
        precondition(current.idleSeconds >= 0)
        print("PASS: OCR external power, battery opt-in, battery threshold, idle threshold, low power, thermal and unknown-state policies; cancellation and non-blocking deferral")
    }
}
