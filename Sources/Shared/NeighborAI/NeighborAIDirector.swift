import Foundation
import GameplayKit

// MARK: - NeighborAIDelegate

@MainActor
protocol NeighborAIDelegate: AnyObject {
    var audioCoordinator: AudioCoordinator { get }
    var currentStage: GameStage { get }
    var playerRoomID: RoomID { get }
    var availableRoomIDs: [RoomID] { get }
    var isPlayerOnBed: Bool { get }
    var playerPosition: GridPosition { get }
    var isPlayerOnStreet: Bool { get }
    var canPlayerEscapeToCar: Bool { get }
    var movementSpeedMultiplier: TimeInterval { get set }
    var rooms: [RoomID: RoomDefinition] { get }

    func addLog(_ line: String)
    func throwHeldItemToPosition(_ position: GridPosition)
    func announce(_ text: String, delay: TimeInterval)
    func refreshScreenState()
    func setInventoryOpen(_ isOpen: Bool)
    func performCarEscape() -> Bool
    func setPlayerPose(_ pose: PlayerPose)
    func movePlayerTo(roomID: RoomID, position: GridPosition)
    func finishGame(
        roomTitle: String,
        focusTitle: String,
        text: String,
        logLine: String,
        ambientCue: AudioCueID?,
        announcementDelay: TimeInterval
    )
}

// MARK: - NeighborAIDirector

@MainActor
final class NeighborAIDirector {
    // Sub-systems
    let doorMachine = NeighborDoorMachine()
    let searchMachine = NeighborSearchMachine()
    let hidingSystem = NeighborHidingSystem()
    let attackMachine = NeighborAttackMachine()
    let distractionSystem = NeighborDistractionSystem()
    let chaseMachine = NeighborChaseMachine()
    let escapeSystem = NeighborEscapeSystem()
    let debug = NeighborDebugConfig()

    weak var delegate: NeighborAIDelegate?

    // Main escalation machine
    private let machine: GKStateMachine
    private var neighborResponseTask: Task<Void, Never>?
    private var neighborBreakInTask: Task<Void, Never>?
    private var neighborSearchTask: Task<Void, Never>?
    private var neighborChaseTask: Task<Void, Never>?
    private var stunRecoveryTask: Task<Void, Never>?
    private var chaseDuration: TimeInterval = 0

    init() {
        machine = GKStateMachine(states: [
            CalmState(),
            WarnedState(),
            ActiveState(),
            ResolvedState()
        ])
        machine.enter(CalmState.self)
    }

    // MARK: - State queries

    var isCalm: Bool { machine.currentState is CalmState }
    var isWarned: Bool { machine.currentState is WarnedState }
    var isActive: Bool { machine.currentState is ActiveState }
    var isResolved: Bool { machine.currentState is ResolvedState }

    // MARK: - Same API as old NeighborSystem (drop-in replacement)

    func reactToLoudActionIfNeeded(for action: ItemAction) -> String? {
        guard isNeighborNoiseAction(action) else { return nil }

        if isCalm {
            _ = machine.enter(WarnedState.self)
            return "Где-то за стеной сразу рявкнули: Эй, ты там что творишь вообще?"
        }

        if isWarned {
            _ = machine.enter(ActiveState.self)
            doorMachine.beginKnocking()
            delegate?.audioCoordinator.playEffect(.doorbellMain)
            scheduleNeighborResponse()
            return "Снаружи раздался злой звонок в дверь. Похоже, кто-то пришел разбираться. Иди в прихожую к самому началу."
        }

        return nil
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

    func resetNeighborEncounterState() {
        cancelNeighborTasks()
        delegate?.audioCoordinator.cancelStunEffect()
        debug.reset()
        doorMachine.reset()
        searchMachine.reset()
        hidingSystem.reset()
        attackMachine.reset()
        distractionSystem.reset()
        chaseMachine.reset()
        escapeSystem.reset()
        _ = machine.enter(CalmState.self)
    }

    // MARK: - Debug simulation

    func simulateDoorbell() {
        _ = machine.enter(WarnedState.self)
        _ = machine.enter(ActiveState.self)
        doorMachine.beginKnocking()
        delegate?.audioCoordinator.playEffect(.doorbellMain)
    }

    /// Полный запуск штурма из отладки (с async-задачей, по ударам, поиском).
    func triggerBreakInFromDebug(
        introText: String = "Снаружи сорвались: Всё, ломаем дверь.",
        finalText: String = "Отладка: соседский штурм запущен."
    ) {
        _ = machine.enter(ActiveState.self)
        startNeighborBreakIn(introText: introText, finalText: finalText)
    }

    // MARK: - Noise detection

    func isNeighborNoiseAction(_ action: ItemAction) -> Bool {
        guard !isResolved else { return false }
        return action.sound == .glassBreakSmall || action.sound == .cabinetSmash
    }

    // MARK: - Response scheduling

    private func scheduleNeighborResponse() {
        neighborResponseTask?.cancel()
        let attempts = Int.random(in: 1...2)
        let pauseRange = debug.responsePauseRange ?? (1.8...3.0)

        neighborResponseTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for attempt in 1...attempts {
                let pause = Double.random(in: pauseRange)
                await self.sleep(seconds: pause)
                guard self.shouldContinueNeighborSequence else { return }
                guard !self.doorMachine.isBreaking else { return }

                let shouldRing = Bool.random()
                if shouldRing {
                    self.delegate?.audioCoordinator.playEffect(.doorbellMain)
                } else {
                    self.delegate?.audioCoordinator.playEffect(.doorBangingHard)
                }

                let line = self.neighborPressureLine(isDoorbell: shouldRing, attempt: attempt, totalAttempts: attempts)
                self.delegate?.addLog(line)
                self.delegate?.announce(line, delay: 0.2)
            }

            guard self.shouldContinueNeighborSequence else { return }
            guard !self.doorMachine.isBreaking else { return }

            self.startNeighborBreakIn(
                introText: "За дверью зло процедили: Всё, хорош ждать. Сейчас вынесем.",
                finalText: "Похоже, они решили больше не церемониться."
            )
        }
    }

    private func startNeighborBreakIn(introText: String, finalText: String) {
        guard shouldContinueNeighborSequence else { return }
        guard neighborBreakInTask == nil else { return }

        doorMachine.beginBreaking()
        neighborResponseTask?.cancel()
        neighborResponseTask = nil
        debug.doorHitsTarget = debug.doorHitsTargetOverride ?? ([3, 5, 8].randomElement() ?? 5)
        delegate?.addLog(finalText)
        delegate?.announce(introText, delay: 0.15)
        let breakInPauseRange = debug.breakInPauseRange ?? (0.6...0.9)
        let footstepCount = debug.footstepCountOverride ?? 3
        let footstepPause = debug.footstepPauseOverride ?? 0.45

        neighborBreakInTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for hit in 1...self.debug.doorHitsTarget {
                await self.sleep(seconds: Double.random(in: breakInPauseRange))
                guard self.shouldContinueNeighborSequence else { return }
                self.delegate?.audioCoordinator.playEffect(.doorBreakHeavy)

                if hit == 1 {
                    let line = "Снаружи уже не стучат. Дверь начали вышибать тяжелыми ударами."
                    self.delegate?.addLog(line)
                    self.delegate?.announce(line, delay: 0.2)
                } else if hit == self.debug.doorHitsTarget {
                    let line = "Дверь треснула. Кажется, замок уже не держит."
                    self.delegate?.addLog(line)
                    self.delegate?.announce(line, delay: 0.2)
                } else {
                    self.delegate?.addLog("Входная дверь снова тяжело дрогнула от удара.")
                }
            }

            guard self.shouldContinueNeighborSequence else { return }
            self.doorMachine.doorDestroyed()
            let breachLine = "Замок не выдержал. Слышно, как один сосед уже влетел в квартиру и тяжело идет прямо к тебе."
            self.delegate?.addLog(breachLine)
            self.delegate?.announce(breachLine, delay: 0.25)

            for _ in 0..<footstepCount {
                await self.sleep(seconds: footstepPause)
                guard self.shouldContinueNeighborSequence else { return }
                self.delegate?.audioCoordinator.playStep(surfaceOverride: .carpet)
            }

            await self.sleep(seconds: 0.35)
            guard self.shouldContinueNeighborSequence else { return }
            self.startSearchPhase()
        }
    }

    private func startChasePhase(chaseText: String? = nil) {
        guard shouldContinueNeighborSequence else { return }

        neighborChaseTask = Task { @MainActor [weak self] in
            guard let self else { return }

            chaseMachine.beginChase()
            let chaseStart = chaseText ?? "Сосед тебя заметил и бежит за тобой!"
            self.delegate?.addLog(chaseStart)
            self.delegate?.announce(chaseStart, delay: 0.15)

            // Chase loop — check every 0.5s
            while self.shouldContinueNeighborSequence && self.chaseMachine.isChasing {
                await self.sleep(seconds: 0.5)
                guard self.shouldContinueNeighborSequence else { return }

                // Check if player escaped to car
                if self.delegate?.canPlayerEscapeToCar ?? false {
                    self.chaseMachine.giveUpChase()
                    let escapeLine = "Ты вбежал в машину и сорвался с места. Сосед остался позади."
                    self.delegate?.addLog(escapeLine)
                    self.delegate?.announce(escapeLine, delay: 0.15)
                    _ = self.delegate?.performCarEscape()
                    // Reset neighbor after escape
                    self.cancelNeighborTasks()
                    self.doorMachine.reset()
                    self.debug.doorHitsTarget = 0
                    _ = self.machine.enter(CalmState.self)
                    return
                }

                // Check if player is still on street and not hiding
                let playerOnStreet = self.delegate?.isPlayerOnStreet ?? false
                if !playerOnStreet {
                    // Player went back inside — stop chase
                    self.chaseMachine.playerLost()
                    await self.sleep(seconds: 3.0)
                    if self.chaseMachine.isLost {
                        self.chaseMachine.giveUpChase()
                        await self.sleep(seconds: 1.0)
                        self.chaseMachine.returnedHome()
                        let giveUpLine = "Сосед потерял тебя из виду и вернулся."
                        self.delegate?.addLog(giveUpLine)
                        self.delegate?.announce(giveUpLine, delay: 0.2)
                        self.cancelNeighborTasks()
                        self.doorMachine.reset()
                        self.debug.doorHitsTarget = 0
                        _ = self.machine.enter(CalmState.self)
                    }
                    return
                }

                // Player still on street — neighbor catches up
                // Simulate: after 5 seconds of chase, neighbor pushes player
                self.chaseDuration += 0.5
                if self.chaseDuration >= 5.0 {
                    self.streetPushPlayer()
                    return
                }
            }
        }
    }

    private func startSearchPhase() {
        guard shouldContinueNeighborSequence else { return }

        neighborSearchTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Neighbor enters the building
            self.delegate?.audioCoordinator.playEffect(.neighborEntersBuilding)

            // Walk into hallway with carpet footsteps
            let entryStepCount = 2
            for _ in 0..<entryStepCount {
                await self.sleep(seconds: 0.45)
                guard self.shouldContinueNeighborSequence else { return }
                self.delegate?.audioCoordinator.playEffect(.neighborFootstepsBuilding)
            }

            await self.sleep(seconds: 0.3)
            guard self.shouldContinueNeighborSequence else { return }

            // Start BFS search from hallway (street excluded — handled separately)
            let availableRooms = (self.delegate?.availableRoomIDs ?? []).filter { $0 != .street }
            self.searchMachine.beginSearch(from: .hallway, availableRooms: availableRooms)

            // Main search loop — driven by NeighborSearchMachine BFS
            while self.shouldContinueNeighborSequence && self.searchMachine.isSearching {
                // Distraction check before each room entry
                if self.distractionSystem.isDistracted {
                    let distractLine = "Сосед остановился. Кажется, его отвлёк брошенный предмет. Он идёт проверять."
                    self.delegate?.addLog(distractLine)
                    self.delegate?.announce(distractLine, delay: 0.2)

                    while self.distractionSystem.isDistracted && self.shouldContinueNeighborSequence {
                        self.distractionSystem.update()
                        await self.sleep(seconds: 0.5)
                    }

                    let resumeLine = "Сосед вернулся к поиску."
                    self.delegate?.addLog(resumeLine)
                    self.delegate?.announce(resumeLine, delay: 0.15)
                }

                guard self.shouldContinueNeighborSequence else { return }
                guard let currentRoom = self.searchMachine.currentRoom else { return }

                // Announce entering
                let roomName = self.roomDisplayName(currentRoom)
                let enterLine = "Сосед входит в \(roomName)..."
                self.delegate?.addLog(enterLine)
                self.delegate?.announce(enterLine, delay: 0.15)

                // Play door open sound (hallway has no door)
                if let openSound = Self.doorOpenSound(for: currentRoom) {
                    self.delegate?.audioCoordinator.playEffect(openSound)
                }

                // Wait for door animation + footstep into room
                await self.sleep(seconds: 0.5)
                guard self.shouldContinueNeighborSequence else { return }
                self.delegate?.audioCoordinator.playEffect(.neighborFootstepsBuilding)
                self.delegate?.audioCoordinator.playStep(surfaceOverride: .carpet)

                // Mark entry complete → enters SearchingRoomState
                self.searchMachine.enterRoomComplete()

                // --- Cell-by-cell walk through the room ---
                let roomDef = self.delegate?.rooms[currentRoom]
                if let roomDef {
                    // Collect door positions to skip them during the walk
                    var doorPositions: [(Int, Int)] = []
                    for node in roomDef.nodes {
                        if case .door = node.target {
                            doorPositions.append((node.position.x, node.position.y))
                        }
                    }

                    // Walk every cell in the room grid, row by row
                    for y in 0..<roomDef.height {
                        for x in 0..<roomDef.width {
                            guard self.shouldContinueNeighborSequence else { return }

                            // Skip door positions — the neighbor entered through one
                            if doorPositions.contains(where: { $0.0 == x && $0.1 == y }) {
                                continue
                            }

                            // Footstep for this cell
                            self.delegate?.audioCoordinator.playStep(surfaceOverride: roomDef.stepSurface)

                            // Walking speed wait
                            await self.sleep(seconds: Double.random(in: 0.3...0.5))
                            guard self.shouldContinueNeighborSequence else { return }

                            // Check if player is at this exact cell
                            let playerRoom = self.delegate?.playerRoomID
                            if let playerPos = self.delegate?.playerPosition {
                                let playerAtCell = playerRoom == currentRoom && playerPos.x == x && playerPos.y == y
                                let onBed = self.delegate?.isPlayerOnBed ?? false
                                let detectable = self.hidingSystem.isPlayerDetectable() && !onBed

                                if playerAtCell && detectable {
                                    self.searchMachine.playerDetected()
                                    self.resolveNeighborAttack(
                                        text: "Сосед нашёл тебя и нанёс удар.",
                                        logLine: "Сосед нашёл игрока в квартире"
                                    )
                                    return
                                }

                                // Player at this cell but hiding — announce and continue
                                if playerAtCell && !detectable {
                                    let hideLine = "Сосед прошёл мимо, но ты в последний момент спрятался."
                                    self.delegate?.addLog(hideLine)
                                    self.delegate?.announce(hideLine, delay: 0.15)
                                }
                            }
                        }
                    }
                }

                // Room result announcement — all cells checked, player not found
                let emptyLine: String
                let playerRoomNow = self.delegate?.playerRoomID
                if playerRoomNow == currentRoom && self.hidingSystem.isInBed {
                    emptyLine = "Сосед осмотрел \(roomName). Ты спрятался в кровати — сосед не заметил тебя."
                } else {
                    emptyLine = "Сосед осмотрел \(roomName). Здесь пусто."
                }
                self.delegate?.addLog(emptyLine)
                self.delegate?.announce(emptyLine, delay: 0.15)

                // Play door close sound
                if let closeSound = Self.doorCloseSound(for: currentRoom) {
                    self.delegate?.audioCoordinator.playEffect(closeSound)
                }

                // After hallway, check if player is on street → chase instead of searching
                if currentRoom == .hallway {
                    let isOnStreet = self.delegate?.isPlayerOnStreet ?? false
                    if isOnStreet {
                        self.searchMachine.reset()
                        self.startChasePhase(chaseText: "Сосед тебя заметил на улице и бежит за тобой!")
                        return
                    }
                }

                // Room clear → next room (BFS) or LostPlayerState if queue empty
                self.searchMachine.roomClear()
            }

            // All rooms searched — neighbor gives up
            guard self.shouldContinueNeighborSequence else { return }
            await self.sleep(seconds: 0.5)
            guard self.shouldContinueNeighborSequence else { return }

            // Neighbor exits the building
            self.delegate?.audioCoordinator.playEffect(.neighborExitsBuilding)

            let giveUpLine = "Сосед обошёл все комнаты. Похоже, ушёл."
            self.delegate?.addLog(giveUpLine)
            self.delegate?.announce(giveUpLine, delay: 0.2)
            self.delegate?.refreshScreenState()

            // Reset to calm
            self.cancelNeighborTasks()
            self.searchMachine.reset()
            self.doorMachine.reset()
            self.debug.doorHitsTarget = 0
            _ = self.machine.enter(CalmState.self)
        }
    }

    // MARK: - Door Sound Mapping

    private static func doorOpenSound(for roomID: RoomID) -> AudioCueID? {
        switch roomID {
        case .bedroom: return .doorOpenBedroom
        case .kitchen: return .doorOpenKitchen
        case .bathroom: return .doorOpenBathroom
        case .livingRoom: return .doorOpenLivingRoom
        case .teaRoom: return .doorOpenTeaRoom
        case .groceryStore: return .doorOpenHallway
        case .hallway, .street, .mainStreet: return nil
        }
    }

    private static func doorCloseSound(for roomID: RoomID) -> AudioCueID? {
        switch roomID {
        case .bedroom: return .doorCloseBedroom
        case .kitchen: return .doorCloseKitchen
        case .bathroom: return .doorCloseBathroom
        case .livingRoom: return .doorCloseLivingRoom
        case .teaRoom: return .doorCloseTeaRoom
        case .groceryStore: return .doorCloseHallway
        case .hallway, .street, .mainStreet: return nil
        }
    }

    private func roomDisplayName(_ roomID: RoomID) -> String {
        switch roomID {
        case .hallway: return "прихожую"
        case .bedroom: return "спальню"
        case .kitchen: return "кухню"
        case .bathroom: return "ванную"
        case .livingRoom: return "гостиную"
        case .street: return "улицу"
        case .mainStreet: return "главную улицу"
        case .groceryStore: return "магазин"
        case .teaRoom: return "чайную"
        }
    }

    private var shouldContinueNeighborSequence: Bool {
        delegate?.currentStage == .exploration && !isResolved
    }

    var isNeighborSequenceActive: Bool {
        shouldContinueNeighborSequence
    }

    private func neighborPressureLine(isDoorbell: Bool, attempt: Int, totalAttempts: Int) -> String {
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

    private func neighborsGiveUpAndLeave() {
        guard shouldContinueNeighborSequence else { return }
        cancelNeighborTasks()
        doorMachine.reset()
        debug.doorHitsTarget = 0
        let text = "За дверью еще немного потоптались, кто-то буркнул: Да ну его. Потом шаги стихли. Кажется, ушли."
        delegate?.addLog(text)
        delegate?.refreshScreenState()
        delegate?.announce(text, delay: 0.25)
        _ = machine.enter(CalmState.self)
    }

    // MARK: - Street Push

    private func streetPushPlayer() {
        guard shouldContinueNeighborSequence else { return }

        chaseMachine.beginPush()
        chaseDuration = 0

        let pushText = "Сосед догнал тебя и с размаху толкнул в грудь."
        delegate?.addLog(pushText)
        delegate?.announce(pushText, delay: 0.15)

        // Punch + fall sound sequence
        delegate?.audioCoordinator.playEffect(.punchLight)
        delegate?.setInventoryOpen(false)

        stunRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }

            await self.sleep(seconds: 0.2)
            guard self.shouldContinueNeighborSequence else { return }

            self.delegate?.audioCoordinator.playEffect(.humanFall1)

            await self.sleep(seconds: 0.3)
            guard self.shouldContinueNeighborSequence else { return }

            // Player lies on the street
            self.delegate?.setPlayerPose(.lying)

            let fallText = "Ты шлёпнулся на асфальт. Голова раскалывается. Стоять не получается."
            self.delegate?.addLog(fallText)
            self.delegate?.announce(fallText, delay: 0.3)

            await self.sleep(seconds: 0.5)
            guard self.shouldContinueNeighborSequence else { return }

            // 10-second stun loop — every 0.5s, 20 iterations
            for i in 0 ..< 20 {
                guard self.shouldContinueNeighborSequence else { return }
                guard self.chaseMachine.isPushing else { return }

                await self.sleep(seconds: 0.5)
                guard self.shouldContinueNeighborSequence else { return }

                // At 3s and 6s — chance of second hit → game over
                if i == 6 || i == 12 {
                    let hitChance = Bool.random()
                    if hitChance {
                        let hitText = "Сосед нанёс ещё один удар, пока ты лежал."
                        self.delegate?.addLog(hitText)
                        self.delegate?.audioCoordinator.playEffect(.neighborPunch)
                        self.delegate?.audioCoordinator.applyStunEffect()
                        self.delegate?.movementSpeedMultiplier = 5.0

                        self.cancelNeighborTasks()
                        self.chaseMachine.reset()
                        _ = self.machine.enter(ResolvedState.self)

                        self.delegate?.finishGame(
                            roomTitle: "Улица",
                            focusTitle: "Тебя избили",
                            text: "Сосед бил тебя, пока ты не потерял сознание.",
                            logLine: "Сосед избил игрока на улице",
                            ambientCue: .heartbeatFast,
                            announcementDelay: 0.6
                        )
                        return
                    }
                }
            }

            // Survived — wake up and teleport to bed
            self.recoverFromStreetPush()
        }
    }

    private func recoverFromStreetPush() {
        guard shouldContinueNeighborSequence else { return }

        cancelNeighborTasks()
        chaseMachine.endPush()

        delegate?.movePlayerTo(roomID: .bedroom, position: GridPosition(x: 3, y: 2))
        delegate?.setPlayerPose(.lying)
        delegate?.refreshScreenState()

        let wakeText = "Ты очнулся в своей кровати. Голова всё ещё гудит, но ты дома. Кажется, сосед оттащил тебя."
        delegate?.addLog(wakeText)
        delegate?.announce(wakeText, delay: 0.4)
        _ = machine.enter(CalmState.self)
    }

    func resolveNeighborAttack(text: String, logLine: String) {
        cancelNeighborTasks()
        chaseMachine.reset()
        _ = machine.enter(ResolvedState.self)
        delegate?.setInventoryOpen(false)
        delegate?.audioCoordinator.playEffect(.punchHit)

        // Apply stun effect
        delegate?.audioCoordinator.applyStunEffect()
        delegate?.movementSpeedMultiplier = 5.0

        // Neighbor physically leaves with footsteps
        let leavingText = "Сосед развернулся и ушёл. Слышно, как его шаги затихают в подъезде."
        delegate?.addLog(leavingText)
        delegate?.announce(leavingText, delay: 0.3)

        // Play neighbor leaving footsteps (fading with distance)
        Task { @MainActor [weak self] in
            guard let self else { return }
            for i in 0..<6 {
                try? await Task.sleep(nanoseconds: 700_000_000)
                let volume = Float(1.0 - Double(i) * 0.15)
                self.delegate?.audioCoordinator.playEffect(.neighborFootstepsBuilding)
                // Fade out each subsequent footstep
                if let lastEffect = self.delegate?.audioCoordinator.activeEngineEffects.last {
                    lastEffect.volume = max(0.1, volume * lastEffect.volume)
                }
            }
        }

        // Schedule stun recovery → return to normal (NOT game over)
        let onBed = delegate?.isPlayerOnBed ?? false
        stunRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Recover from stun (60 seconds, or 10 if on bed)
            await self.delegate?.audioCoordinator.recoverFromStun(fastRecovery: onBed)

            // Restore movement speed
            self.delegate?.movementSpeedMultiplier = 1.0

            // Return to calm state — game continues
            _ = self.machine.enter(CalmState.self)
            let recoverText = "Сознание прояснилось. Ты снова можешь двигаться."
            self.delegate?.addLog(recoverText)
            self.delegate?.announce(recoverText, delay: 0.3)
            self.delegate?.refreshScreenState()
        }
    }

    func cancelNeighborTasks() {
        distractionSystem.clearDistraction()
        neighborResponseTask?.cancel()
        neighborResponseTask = nil
        neighborBreakInTask?.cancel()
        neighborBreakInTask = nil
        neighborSearchTask?.cancel()
        neighborSearchTask = nil
        neighborChaseTask?.cancel()
        neighborChaseTask = nil
        stunRecoveryTask?.cancel()
        stunRecoveryTask = nil
        chaseDuration = 0
    }

    /// Called when player throws an item to distract the neighbor
    func performThrowDistraction() {
        guard !isResolved else { return }
        guard delegate?.playerRoomID != nil else { return }

        let throwPosition = delegate?.playerPosition ?? GridPosition(x: 0, y: 0)
        distractionSystem.distract(to: throwPosition, duration: 5.0)
        delegate?.addLog("Ты бросил предмет. Сосед может отвлечься.")
    }

    private func sleep(seconds: TimeInterval) async {
        let nanoseconds = UInt64(seconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
}

// MARK: - Escalation States

private final class CalmState: GKState {
    override func isValidNextState(_ stateClass: AnyClass) -> Bool {
        stateClass == WarnedState.self || stateClass == ResolvedState.self
    }
}

private final class WarnedState: GKState {
    override func isValidNextState(_ stateClass: AnyClass) -> Bool {
        stateClass == ActiveState.self || stateClass == CalmState.self || stateClass == ResolvedState.self
    }
}

private final class ActiveState: GKState {
    override func isValidNextState(_ stateClass: AnyClass) -> Bool {
        stateClass == CalmState.self || stateClass == ResolvedState.self
    }
}

private final class ResolvedState: GKState {
    override func isValidNextState(_ stateClass: AnyClass) -> Bool {
        stateClass == CalmState.self
    }
}
