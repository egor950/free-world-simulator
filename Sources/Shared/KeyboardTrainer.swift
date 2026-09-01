import Combine
import CryptoKit
import Foundation
import SwiftData

@MainActor
final class KeyboardTrainerStore: ObservableObject {
    let container: ModelContainer

    @Published private(set) var currentUser: KeyboardTrainerUser?
    @Published private(set) var completedLessonIDs: Set<Int> = []

    init() {
        let schema = Schema([
            KeyboardTrainerUser.self,
            KeyboardTrainerResult.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                container = try ModelContainer(for: schema, configurations: [fallback])
            } catch {
                fatalError("Не удалось создать локальную базу клавиатурного тренажёра: \(error)")
            }
        }
    }

    var isLoggedIn: Bool {
        currentUser != nil
    }

    func register(username rawUsername: String, password: String, confirmation: String) -> String? {
        let username = rawUsername.trimmingCharacters(in: .whitespacesAndNewlines)

        guard username.count >= 3 else {
            return "Имя пользователя должно содержать не менее 3 символов."
        }
        guard password.count >= 4 else {
            return "Пароль должен содержать не менее 4 символов."
        }
        guard password == confirmation else {
            return "Пароли не совпадают."
        }

        let descriptor = FetchDescriptor<KeyboardTrainerUser>(
            predicate: #Predicate { $0.username == username }
        )

        do {
            guard try container.mainContext.fetch(descriptor).isEmpty else {
                return "Такой пользователь уже существует."
            }

            let user = KeyboardTrainerUser(
                username: username,
                passwordHash: Self.hash(password)
            )
            container.mainContext.insert(user)
            try container.mainContext.save()
            currentUser = user
            refreshProgress()
            return nil
        } catch {
            return "Не удалось сохранить профиль."
        }
    }

    func login(username rawUsername: String, password: String) -> String? {
        let username = rawUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptor = FetchDescriptor<KeyboardTrainerUser>(
            predicate: #Predicate { $0.username == username }
        )

        do {
            guard let user = try container.mainContext.fetch(descriptor).first,
                  user.passwordHash == Self.hash(password) else {
                return "Неверное имя пользователя или пароль."
            }

            currentUser = user
            refreshProgress()
            return nil
        } catch {
            return "Не удалось открыть профиль."
        }
    }

    func logout() {
        currentUser = nil
        completedLessonIDs = []
    }

    func recordResult(
        lesson: KeyboardTrainerLesson,
        duration: TimeInterval,
        correct: Int,
        errors: Int,
        characters: Int
    ) {
        guard let currentUser else { return }

        let result = KeyboardTrainerResult(
            userID: currentUser.id,
            lessonID: lesson.id,
            duration: duration,
            correct: correct,
            errors: errors,
            characters: characters
        )
        container.mainContext.insert(result)
        currentUser.lastLessonID = lesson.id

        do {
            try container.mainContext.save()
            refreshProgress()
        } catch {
            // Следующая тренировка всё равно остаётся доступной в рамках текущей сессии.
            completedLessonIDs.insert(lesson.id)
        }
    }

    func refreshProgress() {
        guard let currentUser else {
            completedLessonIDs = []
            return
        }

        let userID = currentUser.id
        let descriptor = FetchDescriptor<KeyboardTrainerResult>(
            predicate: #Predicate { $0.userID == userID }
        )

        do {
            let results = try container.mainContext.fetch(descriptor)
            completedLessonIDs = Set(results.map(\.lessonID))
        } catch {
            completedLessonIDs = []
        }
    }

    func averageSpeed() -> Double {
        guard let currentUser else { return 0 }
        let userID = currentUser.id
        let descriptor = FetchDescriptor<KeyboardTrainerResult>(
            predicate: #Predicate { $0.userID == userID }
        )

        do {
            let results = try container.mainContext.fetch(descriptor)
            let timed = results.filter { $0.duration > 0 && $0.characters > 0 }
            guard !timed.isEmpty else { return 0 }
            return timed.reduce(0) { partial, result in
                partial + Double(result.characters) / result.duration * 60
            } / Double(timed.count)
        } catch {
            return 0
        }
    }

    private static func hash(_ password: String) -> String {
        SHA256.hash(data: Data(password.utf8))
            .map { String(format: "%02hhx", $0) }
            .joined()
    }
}

@Model
final class KeyboardTrainerUser {
    var id: UUID
    var username: String
    var passwordHash: String
    var createdAt: Date
    var lastLessonID: Int

    init(username: String, passwordHash: String) {
        self.id = UUID()
        self.username = username
        self.passwordHash = passwordHash
        self.createdAt = Date()
        self.lastLessonID = 0
    }
}

@Model
final class KeyboardTrainerResult {
    var id: UUID
    var userID: UUID
    var lessonID: Int
    var createdAt: Date
    var duration: TimeInterval
    var correct: Int
    var errors: Int
    var characters: Int

    init(
        userID: UUID,
        lessonID: Int,
        duration: TimeInterval,
        correct: Int,
        errors: Int,
        characters: Int
    ) {
        self.id = UUID()
        self.userID = userID
        self.lessonID = lessonID
        self.createdAt = Date()
        self.duration = duration
        self.correct = correct
        self.errors = errors
        self.characters = characters
    }
}

struct KeyboardTrainerLesson: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case key
        case sequence
        case word
        case sentence
        case text
        case speed
    }

    let id: Int
    let title: String
    let description: String
    let kind: Kind
    let tasks: [String]

    var isTimed: Bool {
        kind == .speed
    }

    var totalCharacters: Int {
        tasks.reduce(0) { $0 + $1.count }
    }

    static let all: [KeyboardTrainerLesson] = [
        KeyboardTrainerLesson(
            id: 1,
            title: "Знакомство с клавиатурой",
            description: "Находим отдельные клавиши и учимся уверенно их нажимать.",
            kind: .key,
            tasks: ["ф", "а", "ы", "в", "о", "л", "д", "ж", "к", "п"]
        ),
        KeyboardTrainerLesson(
            id: 2,
            title: "Первые клавиши",
            description: "Повторяем базовые буквы и закрепляем их расположение.",
            kind: .key,
            tasks: ["ф", "а", "о", "л", "д", "ж", "ы", "в", "п", "р", "н", "г", "к", "е"]
        ),
        KeyboardTrainerLesson(
            id: 3,
            title: "Сочетания клавиш",
            description: "Печатаем короткие последовательности без пауз между буквами.",
            kind: .sequence,
            tasks: ["аф", "ол", "вы", "ды", "аж", "пл", "рв", "ок", "фыа", "лдп"]
        ),
        KeyboardTrainerLesson(
            id: 4,
            title: "Простые слова",
            description: "Переходим от отдельных букв к настоящим словам.",
            kind: .word,
            tasks: ["дом", "кот", "лес", "мама", "папа", "окно", "рука", "книга"]
        ),
        KeyboardTrainerLesson(
            id: 5,
            title: "Предложения",
            description: "Тренируем пробелы, слова и знаки препинания.",
            kind: .sentence,
            tasks: [
                "сегодня хорошая погода.",
                "я учусь печатать.",
                "клавиатура теперь понятнее."
            ]
        ),
        KeyboardTrainerLesson(
            id: 6,
            title: "Небольшой текст",
            description: "Печатаем несколько предложений подряд и следим за точностью.",
            kind: .text,
            tasks: [
                "я печатаю спокойно и внимательно. моя цель — писать правильно и постепенно увеличивать скорость."
            ]
        ),
        KeyboardTrainerLesson(
            id: 7,
            title: "Скорость",
            description: "За 60 секунд набираем как можно больше текста с минимальным числом ошибок.",
            kind: .speed,
            tasks: [
                "печатайте ровно и без лишней спешки. правильная техника важнее рекорда."
            ]
        )
    ]

    static func lesson(for id: Int) -> KeyboardTrainerLesson? {
        all.first { $0.id == id }
    }
}

struct KeyboardTrainerKeyboard {
    static let rows = [
        ["ё", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "⌫"],
        ["й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з", "х", "ъ"],
        ["ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э"],
        ["я", "ч", "с", "м", "и", "т", "ь", "б", "ю", "."]
    ]

    static let fingerHints: [String: String] = [
        "ё": "мизинец левой руки",
        "й": "мизинец левой руки",
        "ц": "безымянный палец левой руки",
        "у": "средний палец левой руки",
        "к": "указательный палец левой руки",
        "е": "средний палец левой руки",
        "н": "указательный палец правой руки",
        "г": "указательный палец левой руки",
        "ш": "безымянный палец левой руки",
        "щ": "мизинец левой руки",
        "з": "безымянный палец левой руки",
        "х": "мизинец левой руки",
        "ф": "мизинец левой руки",
        "ы": "безымянный палец левой руки",
        "в": "средний палец левой руки",
        "а": "мизинец левой руки",
        "п": "указательный палец правой руки",
        "р": "указательный палец правой руки",
        "о": "безымянный палец правой руки",
        "л": "средний палец правой руки",
        "д": "указательный палец правой руки",
        "ж": "мизинец правой руки",
        "э": "мизинец правой руки",
        "я": "мизинец левой руки",
        "ч": "безымянный палец левой руки",
        "с": "средний палец левой руки",
        "м": "указательный палец правой руки",
        "и": "средний палец правой руки",
        "т": "указательный палец левой руки",
        "ь": "указательный палец правой руки",
        "б": "указательный палец правой руки",
        "ю": "мизинец правой руки",
        ".": "мизинец правой руки"
    ]

    static func finger(for character: String) -> String {
        let normalized = character.lowercased()
        return fingerHints[normalized] ?? "по стандартной постановке пальцев"
    }
}
