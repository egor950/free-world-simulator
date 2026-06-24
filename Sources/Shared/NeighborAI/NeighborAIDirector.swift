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
    var isPlayerMovementLocked: Bool { get set }
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
    private var streetChaseRuntime: NeighborStreetChaseRuntime?
    private let stunnedMovementMultiplier: TimeInterval = 2.0
    private let streetPushSecondHitChancePercent = 12

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
        delegate?.movementSpeedMultiplier = 1.0
        delegate?.isPlayerMovementLocked = false
        debug.reset()
        doorMachine.reset()
        searchMachine.reset()
        hidingSystem.reset()
        attackMachine.reset()
        distractionSystem.reset()
        chaseMachine.reset()
        escapeSystem.reset()
        streetChaseRuntime = nil
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

            self.streetChaseRuntime = NeighborStreetChaseRuntime(
                playerRoomID: self.delegate?.playerRoomID ?? .street,
                playerPosition: self.delegate?.playerPosition ?? StreetRoom.spawnPosition
            )

            // Chase loop — neighbor has a real position and catches by distance.
            let tickInterval: TimeInterval = 0.25
            while self.shouldContinueNeighborSequence && self.chaseMachine.isChasing {
                await self.sleep(seconds: tickInterval)
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

                guard let playerRoom = self.delegate?.playerRoomID,
                      let playerPosition = self.delegate?.playerPosition,
                      let room = self.delegate?.rooms[playerRoom] else {
                    continue
                }

                if self.streetChaseRuntime == nil {
                    self.streetChaseRuntime = NeighborStreetChaseRuntime(
                        playerRoomID: playerRoom,
                        playerPosition: playerPosition
                    )
                }

                guard var runtime = self.streetChaseRuntime else { continue }
                let snapshot = runtime.tick(
                    deltaTime: tickInterval,
                    playerRoomID: playerRoom,
                    playerPosition: playerPosition,
                    roomSize: (room.width, room.height)
                )

                if runtime.shouldPlayFootstep() {
                    self.delegate?.audioCoordinator.playEffect(.neighborStepClose, volumeMultiplier: snapshot.footstepVolume)
                }
                self.streetChaseRuntime = runtime

                if runtime.hasLostPlayer() {
                    self.chaseMachine.playerLost()
                    self.chaseMachine.giveUpChase()
                    let giveUpLine = "Сосед отстал. Его шаги быстро растворились за спиной."
                    self.delegate?.addLog(giveUpLine)
                    self.delegate?.announce(giveUpLine, delay: 0.2)
                    self.cancelNeighborTasks()
                    self.doorMachine.reset()
                    self.debug.doorHitsTarget = 0
                    _ = self.machine.enter(CalmState.self)
                    return
                }

                if runtime.hasCaughtPlayer(distance: snapshot.distance) {
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
            for _ in 0..<2 {
                await self.sleep(seconds: 0.4)
                guard self.shouldContinueNeighborSequence else { return }
                self.delegate?.audioCoordinator.playEffect(.neighborFootstepsBuilding)
            }

            await self.sleep(seconds: 0.4)
            guard self.shouldContinueNeighborSequence else { return }

            // "Listening" phase — neighbor pauses in hallway, listening for noise
            let listenLine = "Сосед стоит в прихожей и слушает."
            self.delegate?.addLog(listenLine)
            self.delegate?.announce(listenLine, delay: 0.3)
            await self.sleep(seconds: 1.5)
            guard self.shouldContinueNeighborSequence else { return }

            // Pursuit-based search: neighbor goes directly to player's room
            var neighborRoom: RoomID = .hallway
            var hasEnteredCurrentRoom = true

            // Main pursuit loop — check every 0.5s (slower, more deliberate)
            while self.shouldContinueNeighborSequence {
                // Distraction check
                if self.distractionSystem.isDistracted {
                    let distractLine = "Сосед остановился. Кажется, его отвлёк брошенный предмет."
                    self.delegate?.addLog(distractLine)
                    self.delegate?.announce(distractLine, delay: 0.3)

                    while self.distractionSystem.isDistracted && self.shouldContinueNeighborSequence {
                        self.distractionSystem.update()
                        await self.sleep(seconds: 0.5)
                    }

                    let resumeLine = "Сосед вернулся к преследованию."
                    self.delegate?.addLog(resumeLine)
                    self.delegate?.announce(resumeLine, delay: 0.2)
                }

                guard self.shouldContinueNeighborSequence else { return }

                // Get player's current room — this is where the noise comes from
                let playerRoom = self.delegate?.playerRoomID ?? .hallway

                // Player on street → switch to street chase
                if playerRoom == .street || playerRoom == .mainStreet {
                    self.searchMachine.reset()
                    self.startChasePhase(chaseText: "Сосед тебя заметил на улице и бежит за тобой!")
                    return
                }

                // Neighbor is in the same room as player
                if neighborRoom == playerRoom && hasEnteredCurrentRoom {
                    let onBed = self.delegate?.isPlayerOnBed ?? false
                    let detectable = self.hidingSystem.isPlayerDetectable() && !onBed

                    if detectable {
                        // FOUND — immediate attack
                        self.searchMachine.playerDetected()
                        self.resolveNeighborAttack(
                            text: "Сосед нашёл тебя и нанёс удар.",
                            logLine: "Сосед нашёл игрока в квартире"
                        )
                        return
                    } else {
                        // Player hiding or on bed — continue pursuit, they might move
                        await self.sleep(seconds: 0.5)
                        continue
                    }
                }

                // Neighbor needs to move to player's room — deliberate pursuit
                if neighborRoom != playerRoom || !hasEnteredCurrentRoom {
                    let roomName = self.roomDisplayName(playerRoom)

                    // Announce pursuit direction
                    let moveLine = neighborRoom == playerRoom
                        ? "Сосед осматривает \(roomName)..."
                        : "Сосед слышит шум и идёт к \(roomName)..."
                    self.delegate?.addLog(moveLine)
                    self.delegate?.announce(moveLine, delay: 0.2)

                    // Play door open sound (hallway has no door)
                    if let openSound = Self.doorOpenSound(for: playerRoom) {
                        self.delegate?.audioCoordinator.playEffect(openSound)
                    }

                    // Update search machine state
                    self.searchMachine.reset()
                    self.searchMachine.beginSearch(from: playerRoom, availableRooms: [playerRoom])
                    self.searchMachine.enterRoomComplete()
                    neighborRoom = playerRoom

                    // Transition wait — walking to room
                    await self.sleep(seconds: 0.5)
                    guard self.shouldContinueNeighborSequence else { return }

                    // Footstep into room
                    self.delegate?.audioCoordinator.playEffect(.neighborFootstepsBuilding)
                    self.delegate?.audioCoordinator.playStep(surfaceOverride: .carpet)

                    // Play door close sound
                    if let closeSound = Self.doorCloseSound(for: playerRoom) {
                        self.delegate?.audioCoordinator.playEffect(closeSound)
                    }

                    hasEnteredCurrentRoom = true
                }

                // Pause before next check — deliberate pacing
                await self.sleep(seconds: 0.5)
            }

            // Safety: neighbor gives up if pursuit loop exits
            guard self.shouldContinueNeighborSequence else { return }
            self.delegate?.audioCoordinator.playEffect(.neighborExitsBuilding)

            let giveUpLine = "Сосед потерял след и ушёл."
            self.delegate?.addLog(giveUpLine)
            self.delegate?.announce(giveUpLine, delay: 0.2)
            self.delegate?.refreshScreenState()

            self.cancelNeighborTasks()
            self.searchMachine.reset()
            self.doorMachine.reset()
            self.debug.doorHitsTarget = 0
            _ = self.machine.enter(CalmState.self)
        }
    }

    // MARK: - Noise Notification

    /// Called when the player moves to a new room or makes a loud noise.
    /// The pursuit loop picks up delegate.playerRoomID every 0.2s naturally,
    /// but this method provides explicit notification for immediate reactions.
    func notifyPlayerMoved(to roomID: RoomID) {
        guard !isResolved, !isCalm else { return }
        // The pursuit loop checks delegate?.playerRoomID every 0.2s
        // and redirects automatically. This API exists for explicit
        // GameViewModel integration when a direct call is needed.
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
        delegate?.movementSpeedMultiplier = stunnedMovementMultiplier
        delegate?.isPlayerMovementLocked = true
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
            await self.delegate?.audioCoordinator.applyStunEffect()

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

                // At 3s and 6s — small chance of second hit → game over.
                // Most of the time the player should wake up on the bed.
                if i == 6 || i == 12 {
                    if Int.random(in: 1...100) <= self.streetPushSecondHitChancePercent {
                        let hitText = "Сосед нанёс ещё один удар, пока ты лежал."
                        self.delegate?.addLog(hitText)
                        self.delegate?.audioCoordinator.playEffect(.neighborPunch)
                        await self.delegate?.audioCoordinator.applyStunEffect()
                        self.delegate?.movementSpeedMultiplier = self.stunnedMovementMultiplier
                        self.delegate?.isPlayerMovementLocked = true

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

            // Survived — recover right where the player fell.
            self.recoverFromStreetPush()
        }
    }

    private func recoverFromStreetPush() {
        guard shouldContinueNeighborSequence else { return }

        cancelNeighborTasks()
        chaseMachine.endPush()

        // Hard stun: movement is locked, and any later movement is half speed.
        delegate?.movementSpeedMultiplier = stunnedMovementMultiplier
        delegate?.isPlayerMovementLocked = true

        // Cinematic stun sequence
        Task { @MainActor [weak self] in
            guard let self else { return }

            // === PHASE 1: Stun fade-in on the street (4.5 seconds) ===
            await self.delegate?.audioCoordinator.applyStunEffect()

            // === PHASE 2: Drift into silence ===
            let silenceText = "Темнота. Тишина. Только стук сердца в ушах."
            self.delegate?.addLog(silenceText)
            self.delegate?.announce(silenceText, delay: 0.5)
            try? await Task.sleep(nanoseconds: 4_000_000_000) // 4s of silence

            // === PHASE 3: Wake up on bed, with control returned ===
            self.delegate?.movePlayerTo(roomID: .bedroom, position: GridPosition(x: 3, y: 2))
            self.delegate?.setPlayerPose(.lying)
            self.delegate?.isPlayerMovementLocked = false
            self.delegate?.refreshScreenState()

            let wakeText = "Ты очнулся в своей кровати. Голова всё ещё гудит, но теперь ты можешь двигаться по кровати и нажать E, чтобы встать."
            self.delegate?.addLog(wakeText)
            self.delegate?.announce(wakeText, delay: 0.4)

            // === PHASE 4: Recovery — 24 seconds, movement stays slow ===
            await self.delegate?.audioCoordinator.recoverFromStun(fastRecovery: true)
            self.delegate?.movementSpeedMultiplier = 1.0
            self.delegate?.refreshScreenState()
            _ = self.machine.enter(CalmState.self)
        }
    }

    func resolveNeighborAttack(text: String, logLine: String) {
        cancelNeighborTasks()
        chaseMachine.reset()
        _ = machine.enter(ResolvedState.self)
        delegate?.setInventoryOpen(false)
        delegate?.audioCoordinator.playEffect(.punchHit)

        // Hard stun: movement is locked, and any later movement is half speed.
        delegate?.movementSpeedMultiplier = stunnedMovementMultiplier
        delegate?.isPlayerMovementLocked = true

        // Cinematic stun sequence — everything happens in this Task
        Task { @MainActor [weak self] in
            guard let self else { return }

            // === PHASE 1: Stun fade-in (4.5 seconds) — player frozen ===
            self.delegate?.setPlayerPose(.lying)
            self.delegate?.refreshScreenState()
            await self.delegate?.audioCoordinator.applyStunEffect()

            // === PHASE 2: Neighbor leaves while player is stunned ===
            let leavingText = "Сосед развернулся и ушёл. Слышно, как его шаги затихают в подъезде."
            self.delegate?.addLog(leavingText)
            self.delegate?.announce(leavingText, delay: 0.3)

            // Neighbor footsteps fading with distance
            for i in 0..<6 {
                try? await Task.sleep(nanoseconds: 700_000_000)
                self.delegate?.audioCoordinator.playEffect(.neighborFootstepsBuilding)
                if let lastEffect = self.delegate?.audioCoordinator.activeEffects.last {
                    lastEffect.volume = max(0.1, Float(1.0 - Double(i) * 0.15) * lastEffect.volume)
                }
            }

            // === PHASE 3: Silence — player drifts into darkness ===
            let silenceText = "Темнота. Тишина. Только стук сердца в ушах."
            self.delegate?.addLog(silenceText)
            self.delegate?.announce(silenceText, delay: 0.5)
            try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5s of silence

            // === PHASE 4: Wake up on bed, with control returned ===
            self.delegate?.movePlayerTo(roomID: .bedroom, position: GridPosition(x: 3, y: 2))
            self.delegate?.setPlayerPose(.lying)
            self.delegate?.isPlayerMovementLocked = false
            self.delegate?.refreshScreenState()

            let wakeText = "Ты очнулся в своей кровати. Голова всё ещё гудит, но теперь ты можешь двигаться по кровати и нажать E, чтобы встать."
            self.delegate?.addLog(wakeText)
            self.delegate?.announce(wakeText, delay: 0.3)

            // === PHASE 5: Recovery — 75 seconds back to normal ===
            await self.delegate?.audioCoordinator.recoverFromStun(fastRecovery: false)

            // Restore movement
            self.delegate?.movementSpeedMultiplier = 1.0
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
        streetChaseRuntime = nil
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
