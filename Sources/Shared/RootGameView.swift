import SwiftUI

struct RootGameView: View {
    @ObservedObject var viewModel: GameViewModel

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    titleBlock

                    switch viewModel.stage {
                    case .welcome:
                        welcomeBlock
                    case .characterCreation:
                        characterCreationBlock
                    case .exploration:
                        explorationBlock
                    case .finished:
                        finishedBlock
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            #if os(macOS)
            if viewModel.stage == .exploration {
                MacKeyboardCapture { command in
                    viewModel.handle(command)
                }
                .frame(width: 1, height: 1)
                .opacity(0.01)
            }
            #endif
        }
        .frame(minWidth: 720, minHeight: 680)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Симулятор свободного мира")
                .font(.largeTitle.bold())
            Text("Комнатная аудиоигра с короткими фразами, дверями, предметами и разным управлением на Mac и iPhone.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var welcomeBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(viewModel.statusText)
                .font(.title3)

            Text("Что уже есть")
                .font(.headline)

            Text("В этой версии мы идем по комнате шаг за шагом, доходим до дверей и предметов, а длинные описания слушаем только по запросу.")

            Button("ОК, продолжить") {
                viewModel.continueFromWelcome()
            }
            .buttonStyle(.borderedProminent)
        }
        .cardStyle()
    }

    private var characterCreationBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Создание персонажа")
                .font(.title2.bold())

            Picker("Тип персонажа", selection: $viewModel.selectedCharacterKind) {
                ForEach(CharacterKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                Text("Имя персонажа")
                    .font(.headline)
                TextField("Например, Егор", text: $viewModel.characterName)
                    .textFieldStyle(.roundedBorder)
            }

            Text("Сейчас выбран герой: \(viewModel.currentCharacterSummary)")
                .foregroundStyle(.secondary)

            Button("Завершить") {
                viewModel.finishCharacterCreation()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canFinishCharacterCreation)
        }
        .cardStyle()
    }

    private var explorationBlock: some View {
            VStack(alignment: .leading, spacing: 18) {
                if viewModel.isInventoryOpen {
                    inventoryBlock
                }

                if viewModel.isTutorialVisible {
                    VStack(alignment: .leading, spacing: 12) {
                    Text("Обучение")
                        .font(.title3.bold())
                    Text(viewModel.tutorialText)
                    Button("Понял") {
                        viewModel.dismissTutorial()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .cardStyle()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(viewModel.statusText)
                    .font(.title3)
                Text("Персонаж: \(viewModel.currentCharacterSummary)")
                    .font(.headline)
                Text(viewModel.holdText)
                    .foregroundStyle(.secondary)
            }
            .cardStyle()

            VStack(alignment: .leading, spacing: 10) {
                Text(viewModel.roomTitle)
                    .font(.title2.bold())
                Text("Сейчас рядом: \(viewModel.focusTitle)")
                Text(viewModel.focusShortText)
            }
            .cardStyle()

            #if os(macOS)
            macControlsBlock
            #else
            iphoneControlsBlock
            #endif

            if !viewModel.eventLog.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Последние события")
                        .font(.title3.bold())

                    ForEach(Array(viewModel.eventLog.enumerated()), id: \.offset) { _, line in
                        Text(line)
                    }
                }
                .cardStyle()
            }
        }
    }

    private var finishedBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(viewModel.statusText)
                .font(.title2.bold())
            Text("Ты дошел до конца игры.")
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var macControlsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Управление на Mac")
                .font(.title3.bold())
            if viewModel.isInventoryOpen {
                Text("Инвентарь открыт. E делает главное действие предмета. F делает силовое действие. C кладет предмет рядом. R читает описание предмета. Escape или I закрывают инвентарь.")
            } else {
                Text("Стрелки ведут тебя по комнате шагами. Q читает полное описание. E делает главное действие. F бьет или ломает. Пробел сбрасывает. Удержание E кладет предмет обратно. I открывает инвентарь.")
            }
            commandRow(viewModel.movementButtons, usesMacKeyTitle: true)
            commandRow(viewModel.actionButtons, usesMacKeyTitle: true)
        }
        .cardStyle()
    }

    private var iphoneControlsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Управление на iPhone")
                .font(.title3.bold())
            Text("Используй крупные кнопки. Игра будет говорить только про предмет, дверь и результат действия.")
            commandRow(viewModel.movementButtons, usesMacKeyTitle: false)
            commandRow(viewModel.actionButtons, usesMacKeyTitle: false)
        }
        .cardStyle()
    }

    private var inventoryBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.inventoryTitle)
                .font(.title3.bold())
            Text(viewModel.inventoryText)
            commandRow(viewModel.inventoryButtons, usesMacKeyTitle: true)
        }
        .cardStyle()
    }

    private func commandRow(_ commands: [PlatformButtonDefinition], usesMacKeyTitle: Bool) -> some View {
        HStack(spacing: 10) {
            ForEach(commands) { button in
                Button {
                    viewModel.handle(button.command)
                } label: {
                    VStack(spacing: 4) {
                        Text(usesMacKeyTitle ? button.command.macKeyTitle : button.title)
                            .font(.headline)
                        Text(button.hint)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
