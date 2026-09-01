import SwiftUI

@MainActor
struct KeyboardTrainerView: View {
    private enum Screen {
        case auth
        case dashboard
        case lesson
        case settings
    }

    @StateObject private var store = KeyboardTrainerStore()
    @State private var screen: Screen = .auth
    @State private var selectedLesson: KeyboardTrainerLesson?

    @State private var username = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var registrationMode = false
    @State private var authMessage = ""

    @AppStorage("keyboardTrainer.voiceEnabled") private var voiceEnabled = true
    @AppStorage("keyboardTrainer.promptVoiceEnabled") private var promptVoiceEnabled = true
    @AppStorage("keyboardTrainer.visualHintsEnabled") private var visualHintsEnabled = true
    @AppStorage("keyboardTrainer.fingerHintsEnabled") private var fingerHintsEnabled = true
    @AppStorage("keyboardTrainer.largeTextEnabled") private var largeTextEnabled = false

    var body: some View {
        NavigationStack {
            Group {
                switch screen {
                case .auth:
                    authenticationView
                case .dashboard:
                    dashboardView
                case .lesson:
                    lessonView
                case .settings:
                    settingsView
                }
            }
            .navigationTitle("Клавиатурный тренажёр")
            .toolbar {
                if store.isLoggedIn, screen != .auth {
                    ToolbarItem(placement: .automatic) {
                        Button("Выйти") {
                            store.logout()
                            selectedLesson = nil
                            screen = .auth
                        }
                        .accessibilityLabel("Выйти из профиля")
                    }
                }
            }
        }
        .font(largeTextEnabled ? .title3 : .body)
        .onAppear {
            if store.isLoggedIn {
                screen = .dashboard
            }
        }
    }

    private var authenticationView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Учимся печатать постепенно")
                        .font(.largeTitle.bold())
                    Text("Сначала отдельные клавиши, затем слова, предложения и скорость. Всё сопровождается понятными подсказками и озвучкой.")
                        .foregroundStyle(.secondary)
                }

                Picker("Режим входа", selection: $registrationMode) {
                    Text("Вход").tag(false)
                    Text("Регистрация").tag(true)
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 12) {
                    TextField("Имя пользователя", text: $username)
                        .textContentType(.username)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Имя пользователя")

                    SecureField("Пароль", text: $password)
                        .textContentType(registrationMode ? .newPassword : .password)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Пароль")

                    if registrationMode {
                        SecureField("Повторите пароль", text: $passwordConfirmation)
                            .textContentType(.newPassword)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Повторите пароль")
                    }
                }

                if !authMessage.isEmpty {
                    Text(authMessage)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Сообщение: \(authMessage)")
                }

                Button(registrationMode ? "Зарегистрироваться" : "Войти") {
                    authenticate()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityLabel(registrationMode ? "Зарегистрироваться" : "Войти")

                Text("Профиль хранится локально на этом устройстве. Пароль в открытом виде не сохраняется.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private var dashboardView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let user = store.currentUser {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Добро пожаловать, \(user.username)!")
                            .font(.title.bold())
                        Text("Пройдено уроков: \(store.completedLessonIDs.count) из \(KeyboardTrainerLesson.all.count)")
                        ProgressView(value: Double(store.completedLessonIDs.count), total: Double(KeyboardTrainerLesson.all.count))
                            .accessibilityLabel("Прогресс обучения")
                            .accessibilityValue("\(store.completedLessonIDs.count) из \(KeyboardTrainerLesson.all.count) уроков")
                        Text(String(format: "Средняя скорость: %.0f знаков в минуту", store.averageSpeed()))
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                HStack {
                    Text("Уроки")
                        .font(.title2.bold())
                    Spacer()
                    Button("Настройки") {
                        screen = .settings
                    }
                    .accessibilityLabel("Настройки доступности")
                }

                ForEach(KeyboardTrainerLesson.all) { lesson in
                    lessonCard(lesson)
                }
            }
            .padding()
            .frame(maxWidth: 820, alignment: .leading)
        }
    }

    private func lessonCard(_ lesson: KeyboardTrainerLesson) -> some View {
        let isCompleted = store.completedLessonIDs.contains(lesson.id)
        let isUnlocked = lesson.id == 1 || store.completedLessonIDs.contains(lesson.id - 1)

        return Button {
            selectedLesson = lesson
            screen = .lesson
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : (isUnlocked ? "play.circle.fill" : "lock.fill"))
                    .font(.title2)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Урок \(lesson.id). \(lesson.title)")
                        .font(.headline)
                    Text(lesson.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .disabled(!isUnlocked)
        .accessibilityLabel("Урок \(lesson.id): \(lesson.title)")
        .accessibilityValue(isCompleted ? "Пройден" : (isUnlocked ? "Доступен" : "Заблокирован"))
    }

    private var lessonView: some View {
        Group {
            if let selectedLesson {
                KeyboardTrainerLessonView(
                    lesson: selectedLesson,
                    store: store,
                    voiceEnabled: $voiceEnabled,
                    promptVoiceEnabled: $promptVoiceEnabled,
                    visualHintsEnabled: $visualHintsEnabled,
                    fingerHintsEnabled: $fingerHintsEnabled,
                    onFinish: { screen = .dashboard },
                    onSettings: { screen = .settings }
                )
            } else {
                ContentUnavailableView("Урок не выбран", systemImage: "keyboard")
            }
        }
    }

    private var settingsView: some View {
        Form {
            Section("Звук") {
                Toggle("Озвучивать нажатые клавиши", isOn: $voiceEnabled)
                Toggle("Озвучивать задания", isOn: $promptVoiceEnabled)
            }

            Section("Визуальные подсказки") {
                Toggle("Показывать виртуальную клавиатуру", isOn: $visualHintsEnabled)
                Toggle("Показывать рекомендуемый палец", isOn: $fingerHintsEnabled)
                Toggle("Крупный текст", isOn: $largeTextEnabled)
            }

            Section {
                Button("Назад к урокам") {
                    screen = .dashboard
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal)
    }

    private func authenticate() {
        authMessage = ""

        let result: String?
        if registrationMode {
            result = store.register(
                username: username,
                password: password,
                confirmation: passwordConfirmation
            )
        } else {
            result = store.login(username: username, password: password)
        }

        if let result {
            authMessage = result
            return
        }

        password = ""
        passwordConfirmation = ""
        registrationMode = false
        screen = .dashboard
    }
}

@MainActor
private struct KeyboardTrainerLessonView: View {
    let lesson: KeyboardTrainerLesson
    let store: KeyboardTrainerStore
    @Binding var voiceEnabled: Bool
    @Binding var promptVoiceEnabled: Bool
    @Binding var visualHintsEnabled: Bool
    @Binding var fingerHintsEnabled: Bool
    let onFinish: () -> Void
    let onSettings: () -> Void

    @State private var lessonIndex = 0
    @State private var inputBuffer = ""
    @State private var correct = 0
    @State private var errors = 0
    @State private var startedAt = Date()
    @State private var timeRemaining = 60
    @State private var completedPasses = 0
    @State private var resultPresented = false
    @State private var speech = SpeechCoordinator()
    @State private var timer: Timer?
    @FocusState private var inputIsFocused: Bool

    private var task: String {
        lesson.tasks[min(lessonIndex, lesson.tasks.count - 1)]
    }

    private var nextCharacter: String {
        guard !lesson.tasks.isEmpty else { return "" }
        let offset = min(inputBuffer.count, task.count)
        return String(task.dropFirst(offset).prefix(1))
    }

    private var accuracy: Double {
        let total = correct + errors
        guard total > 0 else { return 100 }
        return Double(correct) / Double(total) * 100
    }

    private var speed: Double {
        let elapsed = max(Date().timeIntervalSince(startedAt), 0.001)
        return Double(correct) / elapsed * 60
    }

    private var progressText: String {
        if lesson.isTimed {
            return "Осталось: \(timeRemaining) сек."
        }
        return "Задание \(lessonIndex + 1) из \(lesson.tasks.count)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button("Уроки") {
                        stopTimer()
                        onFinish()
                    }
                    .accessibilityLabel("Вернуться к урокам")
                    Spacer()
                    Button("Настройки") {
                        onSettings()
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Урок \(lesson.id). \(lesson.title)")
                        .font(.title.bold())
                    Text(progressText)
                        .foregroundStyle(.secondary)
                    ProgressView(value: progressValue)
                        .accessibilityLabel("Прогресс урока")
                        .accessibilityValue(progressAccessibilityValue)
                }

                VStack(alignment: .center, spacing: 14) {
                    Text(lesson.isTimed ? "Печатайте текст" : "Введите")
                        .font(.headline)
                    Text(task)
                        .font(.system(size: lesson.isTimed ? 30 : 38, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Задание: \(task)")

                    if !nextCharacter.isEmpty {
                        Text("Следующая клавиша: \(spokenName(for: nextCharacter))")
                            .font(.title2.bold())
                            .accessibilityLabel("Следующая клавиша: \(spokenName(for: nextCharacter))")
                    }

                    if fingerHintsEnabled, !nextCharacter.isEmpty {
                        Text("Нажимайте: \(KeyboardTrainerKeyboard.finger(for: nextCharacter))")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Рекомендуемый палец: \(KeyboardTrainerKeyboard.finger(for: nextCharacter))")
                    }

                    TextField("Поле ввода", text: $inputBuffer)
                        .textFieldStyle(.roundedBorder)
                        .focused($inputIsFocused)
                        .frame(maxWidth: 560)
                        .accessibilityLabel("Поле ввода тренажёра")
                        .accessibilityHint("Введите показанный текст или нажмите показанную клавишу")
                        .onChange(of: inputBuffer) { _, newValue in
                            consumeInput(newValue)
                        }

                    if visualHintsEnabled {
                        TrainerKeyboardView(highlight: nextCharacter)
                            .accessibilityLabel("Виртуальная русская клавиатура")
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                HStack(spacing: 18) {
                    StatView(title: "Ошибки", value: "\(errors)")
                    StatView(title: "Точность", value: String(format: "%.0f%%", accuracy))
                    StatView(title: "Скорость", value: String(format: "%.0f зн/мин", speed))
                }

                if lesson.isTimed {
                    Button("Завершить раньше") {
                        finishLesson()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Завершить тренировку раньше времени")
                }
            }
            .padding()
            .frame(maxWidth: 1000, alignment: .leading)
        }
        .onAppear {
            startLesson()
        }
        .onDisappear {
            stopTimer()
        }
        .sheet(isPresented: $resultPresented) {
            resultView
        }
    }

    private var progressValue: Double {
        if lesson.isTimed {
            return Double(60 - timeRemaining) / 60
        }
        return Double(lessonIndex) / Double(max(lesson.tasks.count, 1))
    }

    private var progressAccessibilityValue: String {
        if lesson.isTimed {
            return "\(60 - timeRemaining) из 60 секунд"
        }
        return "\(min(lessonIndex, lesson.tasks.count)) из \(lesson.tasks.count) заданий"
    }

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Урок завершён!")
                .font(.title.bold())
            Text("Время: \(formattedDuration)")
            Text("Правильных нажатий: \(correct)")
            Text("Ошибок: \(errors)")
            Text(String(format: "Точность: %.0f%%", accuracy))
            Text(String(format: "Скорость: %.0f знаков/мин", speed))

            HStack {
                Button("Повторить") {
                    resultPresented = false
                    startLesson()
                }
                .buttonStyle(.bordered)

                Button("К урокам") {
                    resultPresented = false
                    onFinish()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 360, alignment: .leading)
        .presentationDetents([.medium])
        .accessibilityElement(children: .contain)
    }

    private var formattedDuration: String {
        let seconds = Int(Date().timeIntervalSince(startedAt))
        let minutes = seconds / 60
        let remainder = seconds % 60
        return minutes > 0 ? "\(minutes) мин \(remainder) сек" : "\(remainder) сек"
    }

    private func startLesson() {
        stopTimer()
        lessonIndex = 0
        inputBuffer = ""
        correct = 0
        errors = 0
        completedPasses = 0
        timeRemaining = 60
        startedAt = Date()
        resultPresented = false
        inputIsFocused = true

        if promptVoiceEnabled {
            speech.speak(promptText)
        }

        guard lesson.isTimed else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                guard timeRemaining > 0 else { return }
                timeRemaining -= 1
                if timeRemaining == 0 {
                    finishLesson()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func consumeInput(_ newValue: String) {
        guard let character = newValue.last else { return }
        inputBuffer = ""
        processCharacter(String(character))
    }

    private func processCharacter(_ character: String) {
        let normalized = character.lowercased()
        let expected = nextCharacter.lowercased()

        if voiceEnabled {
            speech.speak(spokenName(for: character))
        }

        guard !expected.isEmpty else { return }

        if normalized == expected {
            correct += 1
            inputBuffer = ""
            advanceAfterCorrectCharacter()
        } else {
            errors += 1
            if promptVoiceEnabled {
                speech.speak("Ошибка. Нужно \(spokenName(for: expected))")
            }
        }
    }

    private func advanceAfterCorrectCharacter() {
        let typedLength = inputBuffer.count
        if typedLength == 0 {
            // The input field is cleared immediately, so compare completed work against the task length.
            let expectedLength = task.count
            if correctForCurrentTask >= expectedLength {
                finishCurrentTask()
            }
        }
    }

    @State private var correctForCurrentTask = 0

    private func finishCurrentTask() {
        correctForCurrentTask = 0

        if lesson.isTimed {
            completedPasses += 1
            lessonIndex = 0
            if promptVoiceEnabled {
                speech.speak("Продолжайте")
            }
            return
        }

        if lessonIndex + 1 >= lesson.tasks.count {
            finishLesson()
        } else {
            lessonIndex += 1
            if promptVoiceEnabled {
                speech.speak(promptText)
            }
        }
    }

    private var promptText: String {
        if lesson.kind == .key {
            return "Нажмите клавишу \(spokenName(for: nextCharacter))"
        }
        return "Введите: \(task)"
    }

    private func finishLesson() {
        guard !resultPresented else { return }
        stopTimer()
        let duration = max(Date().timeIntervalSince(startedAt), 0.1)
        store.recordResult(
            lesson: lesson,
            duration: duration,
            correct: correct,
            errors: errors,
            characters: correct
        )
        speech.speak("Урок завершён")
        resultPresented = true
    }

    private func spokenName(for character: String) -> String {
        switch character {
        case " ": return "Пробел"
        case ".": return "Точка"
        case ",": return "Запятая"
        case "-": return "Дефис"
        default: return character.uppercased()
        }
    }
}

private struct TrainerKeyboardView: View {
    let highlight: String

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(KeyboardTrainerKeyboard.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 5) {
                    ForEach(row, id: \.self) { key in
                        Text(key.uppercased())
                            .font(.system(.caption, design: .monospaced).bold())
                            .frame(minWidth: 32, minHeight: 34)
                            .padding(.horizontal, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(key.lowercased() == highlight.lowercased() ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                            )
                            .accessibilityLabel("Клавиша \(key.uppercased())")
                    }
                }
            }

            Text("ПРОБЕЛ")
                .font(.caption.bold())
                .frame(maxWidth: 300, minHeight: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(highlight == " " ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
                .accessibilityLabel("Клавиша Пробел")
        }
        .padding(.top, 6)
    }
}

private struct StatView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
