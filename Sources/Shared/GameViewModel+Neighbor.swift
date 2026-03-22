import Foundation
import GameplayKit

extension GameViewModel {
    func resetNeighborEncounterState() {
        cancelNeighborTasks()
        neighborDoorHitsTarget = 0
        neighborDoorHitsDone = 0
        state.setFlag(itemID: NeighborNoise.worldID, key: NeighborNoise.warnedFlag, value: false)
        state.setFlag(itemID: NeighborNoise.worldID, key: NeighborNoise.doorbellFlag, value: false)
        state.setFlag(itemID: NeighborNoise.worldID, key: NeighborNoise.bangingFlag, value: false)
        state.setFlag(itemID: NeighborNoise.worldID, key: NeighborNoise.resolvedFlag, value: false)
        neighborEncounterMachine.markCalmAfterGiveUp()
    }

    func reactToLoudActionIfNeeded(for action: ItemAction) -> String? {
        guard isNeighborNoiseAction(action) else {
            return nil
        }

        syncNeighborEncounterMachine()

        switch neighborEncounterMachine.resolveLoudAction() {
        case .warn:
            state.setFlag(itemID: NeighborNoise.worldID, key: NeighborNoise.warnedFlag, value: true)
            return "Где-то за стеной сразу рявкнули: Эй, ты там что творишь вообще?"
        case .ringDoorbell:
            state.setFlag(itemID: NeighborNoise.worldID, key: NeighborNoise.doorbellFlag, value: true)
            audioCoordinator.playEffect(.doorbellMain)
            scheduleNeighborResponse()
            return "Снаружи раздался злой звонок в дверь. Похоже, кто-то пришел разбираться. Иди в прихожую к самому началу."
        case .startBreakIn:
            startNeighborBreakIn(
                introText: "Снаружи сразу взбесились: А, он еще и дальше крушит. Ломай дверь.",
                finalText: "Они уже не ждут. Дверь начали высаживать всерьез."
            )
            return "Снаружи сразу взбесились: А, он еще и дальше крушит. Ломай дверь."
        case .intensifyBreakIn:
            audioCoordinator.playEffect(.doorBreakHeavy)
            return "Ты снова устроил грохот, и за дверью сразу начали бить еще ожесточеннее."
        case .ignore:
            return nil
        }
    }

    func isNeighborNoiseAction(_ action: ItemAction) -> Bool {
        guard !state.flag(itemID: NeighborNoise.worldID, key: NeighborNoise.resolvedFlag) else {
            return false
        }

        if action.sound == .glassBreakSmall || action.sound == .cabinetSmash {
            return true
        }

        return action.trigger == .force && action.sound != nil
    }

    func handleNeighborDoor() {
        let text: String
        if neighborBreakInTask != nil {
            text = "Ты дернул дверь как раз в тот момент, когда ее уже почти вынесли. Снаружи только и успели рявкнуть: Поздно. Сразу прилетел тяжелый удар, в ушах загудело, а мир провалился в темноту."
        } else {
            text = "Ты открыл входную дверь. Снаружи только и успели бросить: Ну что, попался? Сразу прилетел тяжелый удар, в ушах загудело, а мир провалился в темноту."
        }
        resolveNeighborAttack(text: text, logLine: "Соседи вырубили тебя у двери")
    }

    func scheduleNeighborResponse() {
        neighborResponseTask?.cancel()
        let attempts = Int.random(in: 3...5)

        neighborResponseTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for attempt in 1...attempts {
                let pause = Double.random(in: 1.8...3.0)
                await self.sleep(seconds: pause)
                guard self.shouldContinueNeighborSequence else { return }
                guard !self.neighborEncounterMachine.isBreakInActive else { return }

                let shouldRing = Bool.random()
                if shouldRing {
                    self.audioCoordinator.playEffect(.doorbellMain)
                } else {
                    self.audioCoordinator.playEffect(.doorBangingHard)
                }

                let line = self.neighborPressureLine(isDoorbell: shouldRing, attempt: attempt, totalAttempts: attempts)
                self.addLog(line)
                self.announce(line, delay: 0.2)
            }

            guard self.shouldContinueNeighborSequence else { return }
            guard !self.neighborEncounterMachine.isBreakInActive else { return }

            if Bool.random() {
                self.neighborsGiveUpAndLeave()
            } else {
                self.startNeighborBreakIn(
                    introText: "За дверью зло процедили: Всё, хорош ждать. Сейчас вынесем.",
                    finalText: "Похоже, они решили больше не церемониться."
                )
            }
        }
    }

    func startNeighborBreakIn(introText: String, finalText: String) {
        syncNeighborEncounterMachine()
        guard shouldContinueNeighborSequence else { return }
        guard neighborBreakInTask == nil else { return }
        guard !neighborEncounterMachine.isBreakInActive else { return }

        neighborEncounterMachine.markBreakInStarted()
        neighborResponseTask?.cancel()
        neighborResponseTask = nil
        state.setFlag(itemID: NeighborNoise.worldID, key: NeighborNoise.bangingFlag, value: true)
        neighborDoorHitsTarget = [3, 5, 8].randomElement() ?? 5
        neighborDoorHitsDone = 0
        addLog(finalText)
        announce(introText, delay: 0.15)

        neighborBreakInTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for hit in 1...self.neighborDoorHitsTarget {
                await self.sleep(seconds: Double.random(in: 0.6...0.9))
                guard self.shouldContinueNeighborSequence else { return }
                self.neighborDoorHitsDone = hit
                self.audioCoordinator.playEffect(.doorBreakHeavy)

                if hit == 1 {
                    let line = "Снаружи уже не стучат. Дверь начали вышибать тяжелыми ударами."
                    self.addLog(line)
                    self.announce(line, delay: 0.2)
                } else if hit == self.neighborDoorHitsTarget {
                    let line = "Дверь треснула. Кажется, замок уже не держит."
                    self.addLog(line)
                    self.announce(line, delay: 0.2)
                } else {
                    self.addLog("Входная дверь снова тяжело дрогнула от удара.")
                }
            }

            guard self.shouldContinueNeighborSequence else { return }
            let breachLine = "Замок не выдержал. Слышно, как один сосед уже влетел в квартиру и тяжело идет прямо к тебе."
            self.addLog(breachLine)
            self.announce(breachLine, delay: 0.25)

            for _ in 0..<3 {
                await self.sleep(seconds: 0.45)
                guard self.shouldContinueNeighborSequence else { return }
                self.audioCoordinator.playStep(surfaceOverride: .carpet)
            }

            await self.sleep(seconds: 0.35)
            guard self.shouldContinueNeighborSequence else { return }
            self.resolveNeighborAttack(
                text: "Дверь с треском вынесли. Один сосед тяжело ворвался внутрь, быстро нашел тебя по звукам и без разговоров вырубил.",
                logLine: "Соседи ворвались в квартиру и вырубили тебя"
            )
        }
    }

    var shouldContinueNeighborSequence: Bool {
        stage == .exploration &&
        !state.flag(itemID: NeighborNoise.worldID, key: NeighborNoise.resolvedFlag)
    }

    func neighborPressureLine(isDoorbell: Bool, attempt: Int, totalAttempts: Int) -> String {
        if attempt == totalAttempts {
            return isDoorbell
                ? "Звонок снова взвыл уже совсем зло, будто снаружи теряют терпение."
                : "В дверь опять врезали так, что по квартире пошел гул."
        }

        if isDoorbell {
            return [
                "Снаружи снова настойчиво жмут на звонок.",
                "Звонок опять коротко и зло резанул по тишине.",
                "У двери опять звонят, уже заметно нервнее."
            ].randomElement() ?? "Снаружи снова звонят в дверь."
        }

        return [
            "В дверь снова резко постучали.",
            "Снаружи опять ударили в дверь кулаком.",
            "Кто-то у входа опять со злостью долбанул в дверь."
        ].randomElement() ?? "Снаружи снова лупят в дверь."
    }

    func neighborsGiveUpAndLeave() {
        guard shouldContinueNeighborSequence else { return }
        cancelNeighborTasks()
        neighborEncounterMachine.markCalmAfterGiveUp()
        neighborDoorHitsTarget = 0
        neighborDoorHitsDone = 0
        state.setFlag(itemID: NeighborNoise.worldID, key: NeighborNoise.warnedFlag, value: false)
        state.setFlag(itemID: NeighborNoise.worldID, key: NeighborNoise.doorbellFlag, value: false)
        state.setFlag(itemID: NeighborNoise.worldID, key: NeighborNoise.bangingFlag, value: false)
        let text = "За дверью еще немного потоптались, кто-то буркнул: Да ну его. Потом шаги стихли. Кажется, ушли."
        addLog(text)
        refreshScreenState()
        announce(text, delay: 0.25)
    }

    func resolveNeighborAttack(text: String, logLine: String) {
        cancelNeighborTasks()
        state.setFlag(itemID: NeighborNoise.worldID, key: NeighborNoise.resolvedFlag, value: true)
        neighborEncounterMachine.markResolved()
        setInventoryOpen(false)
        audioCoordinator.playEffect(.punchHit)
        finishGame(
            roomTitle: "Прихожая",
            focusTitle: "Тебя вырубили",
            text: text,
            logLine: logLine,
            ambientCue: .heartbeatFast,
            announcementDelay: 0.6
        )
    }

    func cancelNeighborTasks() {
        neighborResponseTask?.cancel()
        neighborResponseTask = nil
        neighborBreakInTask?.cancel()
        neighborBreakInTask = nil
    }

    func syncNeighborEncounterMachine() {
        neighborEncounterMachine.syncFromRuntime(
            resolved: state.flag(itemID: NeighborNoise.worldID, key: NeighborNoise.resolvedFlag),
            warned: state.flag(itemID: NeighborNoise.worldID, key: NeighborNoise.warnedFlag),
            doorbellRaised: state.flag(itemID: NeighborNoise.worldID, key: NeighborNoise.doorbellFlag),
            breakInActive: state.flag(itemID: NeighborNoise.worldID, key: NeighborNoise.bangingFlag) || neighborBreakInTask != nil
        )
    }

    func sleep(seconds: TimeInterval) async {
        let nanoseconds = UInt64(seconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
}

enum NeighborLoudReactionStep {
    case warn
    case ringDoorbell
    case startBreakIn
    case intensifyBreakIn
    case ignore
}

final class NeighborEncounterMachine {
    private final class CalmState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == WarnedState.self || stateClass == ResolvedState.self
        }
    }

    private final class WarnedState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == DoorbellState.self || stateClass == CalmState.self || stateClass == ResolvedState.self
        }
    }

    private final class DoorbellState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == BreakInState.self || stateClass == CalmState.self || stateClass == ResolvedState.self
        }
    }

    private final class BreakInState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == CalmState.self || stateClass == ResolvedState.self
        }
    }

    private final class ResolvedState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == CalmState.self
        }
    }

    private let stateMachine: GKStateMachine

    init() {
        stateMachine = GKStateMachine(states: [
            CalmState(),
            WarnedState(),
            DoorbellState(),
            BreakInState(),
            ResolvedState()
        ])
        stateMachine.enter(CalmState.self)
    }

    var isBreakInActive: Bool {
        stateMachine.currentState is BreakInState
    }

    func syncFromRuntime(resolved: Bool, warned: Bool, doorbellRaised: Bool, breakInActive: Bool) {
        if resolved {
            _ = stateMachine.enter(ResolvedState.self)
            return
        }

        if breakInActive {
            _ = stateMachine.enter(BreakInState.self)
            return
        }

        if doorbellRaised {
            _ = stateMachine.enter(DoorbellState.self)
            return
        }

        if warned {
            _ = stateMachine.enter(WarnedState.self)
            return
        }

        _ = stateMachine.enter(CalmState.self)
    }

    func resolveLoudAction() -> NeighborLoudReactionStep {
        if stateMachine.currentState is ResolvedState {
            return .ignore
        }

        if stateMachine.currentState is CalmState {
            _ = stateMachine.enter(WarnedState.self)
            return .warn
        }

        if stateMachine.currentState is WarnedState {
            _ = stateMachine.enter(DoorbellState.self)
            return .ringDoorbell
        }

        if stateMachine.currentState is DoorbellState {
            _ = stateMachine.enter(BreakInState.self)
            return .startBreakIn
        }

        if stateMachine.currentState is BreakInState {
            return .intensifyBreakIn
        }

        return .ignore
    }

    func markBreakInStarted() {
        _ = stateMachine.enter(BreakInState.self)
    }

    func markCalmAfterGiveUp() {
        _ = stateMachine.enter(CalmState.self)
    }

    func markResolved() {
        _ = stateMachine.enter(ResolvedState.self)
    }
}
