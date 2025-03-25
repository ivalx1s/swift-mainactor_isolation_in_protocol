import SwiftUI

@main
struct MainActorProtocolDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - Протокол с MainActor изоляцией
/// Протокол, требующий выполнения методов на MainActor
/// - Важно: Сам по себе протокол НЕ гарантирует изоляцию реализаций,
/// если конформанс (DataStore: MainActorIsolated) добавляется через extension
@MainActor
protocol MainActorIsolated {
    func performUpdate(with date: Date) async
}

// MARK: - Базовая реализация
/// Наблюдаемый класс для демонстрации изоляции
/// - Важно: Изоляция MainActor работает только если: конформанс к протоколу объявлен в декларации класса
@Observable
final class DataStore: MainActorIsolated {
    var lastUpdate: Date = .now {
        didSet {
            logThread("DidSet triggered on:")
        }
    }
    
    func performUpdate(with date: Date) async {
        logThread("Update started on:")
        await executeInternalUpdate(with: date)
    }

    private func executeInternalUpdate(with date: Date) async {
        try? await Task.sleep(nanoseconds: 100_000_000)
        logThread("Internal update executing on:")
        lastUpdate = date
    }
    
    private func logThread(_ message: String) {
        print("\(message): \(Thread.current)")
    }
}

// MARK: - Пример НЕправильной реализации
/// Расширение добавляет конформанс к протоколу, но НЕ обеспечивает изоляцию:
/// - Метод performUpdate будет выполняться на MainActor
/// - Внутренняя логика (executeInternalUpdate) может выполняться вне MainActor
/// -  При этом не имеет значения реализация метода находится внутри экстеншена или внутри декларации класса.
/// - **ВАЖНО**:  вызвать `executeInternalUpdate(with:) невозможно при включении data-race safety Swift 6`
/// что наглядно демонстрирует красоту и важность compile-time data-race safety.
// extension DataStore: MainActorIsolated {
//        func performUpdate(with date: Date) async {
//            logThread("Unsafe update started on:")
//            await executeInternalUpdate(with: date)
//        }
// }

// MARK: - Тестовая View
struct ContentView: View {
    @State private var store = DataStore()
    
    var body: some View {
        VStack {
            Text("Last update: \(store.lastUpdate.formatted())")
            
            Button("Trigger Update") {
                Task {
                    await store.performUpdate(with: .now)
                }
            }
        }
        .padding()
    }
}

// MARK: - Результаты тестирования
/// Сценарий 1: Конформанс в основном теле класса
/// - performUpdate: MainActor
/// - executeInternalUpdate: MainActor
/// - DidSet: MainActor
///
/// Сценарий 2: Конформанс через extension
/// - performUpdate: MainActor
/// - executeInternalUpdate: Background
/// - DidSet: Background (опасно для UI)
///
/// Вывод: Для гарантированной изоляции:
/// 1. Объявляйте конформанс к протоколам, имеющим изоляцию MainActor в основном теле класса.
/// 2. Помечайте класс как @MainActor при необходимости гарантий полной изоляции

// MARK: - Наблюдения по Swift Observation
/*
 1. Макрос @Observable автоматически синхронизирует изменения свойств с MainActor
 2. Прямые изменения свойств из фонового потока будут перенаправлены в главный (но это не точно).
 3. Это НЕ отменяет необходимости правильной изоляции акторами:
 - UI-логика должна выполняться на MainActor
 - Бизнес-логика должна быть правильно изолирована
 - Состояние должно защищаться от гонок данных
 */
