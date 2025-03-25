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
/// Протокол, требующий выполнения методов на MainActor.
/// - Важно: Один лишь атрибут `@MainActor` на протоколе не гарантирует изоляцию реализаций.
///   Изоляция будет работать на **весь класс** только если:
///   1) класс сам помечен `@MainActor`, или
///   2) конформанс к протоколу (например, `Store: MainActorIsolated`) объявлен
///      **внутри** основной декларации класса, а не в extension.
///
/// Если объявить конформанс к `MainActorIsolated` в extension, то **лишь** методы протокола
/// будут изолированы, а остальные части класса (свойства, дополнительные методы) — нет.
/// Это может быть желанным (частичная изоляция) или потенциально опасным (случайные data races).
@MainActor
protocol MainActorIsolated {
    func performUpdate(with date: Date) async
}

// MARK: - Базовая реализация (Полная изоляция класса)
/// `Store` демонстрирует полную `MainActor`-изоляцию:
/// - Конформанс к `MainActorIsolated` объявлен **внутри** класса.
/// - Это означает, что все свойства и методы `Store` изолированы в `MainActor`.
/// - Особенно полезно для UI-ориентированных объектов (например, SwiftUI View Model),
///   где любые модификации состояния происходят на main thread.
@Observable
final class Store: MainActorIsolated {
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

// MARK: - Пример НЕполной изоляции (через extension)
/// Пояснения:
/// 1. При таком подходе изолирован на MainActor будет только метод performUpdate.
/// 2. Внутренняя логика executeInternalUpdate(with:) не обязана быть на MainActor.
/// 3. Swift 6 запретит такой вызов из-за потенциальной гонки данных, если метод
///    executeInternalUpdate не помечен @MainActor.
/// 4. Подобная “частичная изоляция” может быть целесообразна, если класс несёт
///    смешанные обязанности (UI + бекграунд-операции). Но нужно внимательно убедиться, что
///    non-isolated части не обращаются к UI-состоянию в обход главного актера.
//extension Store: MainActorIsolated {
//    func performUpdate(with date: Date) async {
//        logThread("Unsafe update started on:")
//        await executeInternalUpdate(with: date)
//    }
//}

 

// MARK: - Тестовая View
struct ContentView: View {
    @State private var store = Store()
    
    var body: some View {
        VStack(spacing: 16) {
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
/// Сценарий 1: Конформанс в основном теле класса (как сейчас в примере)
/// - performUpdate: выполняется на MainActor
/// - executeInternalUpdate: выполняется на MainActor
/// - didSet: вызывается на MainActor (безопасно для UI)
///
/// Сценарий 2: Конформанс через extension
/// - performUpdate: вызывается на MainActor (т.к. метод из протокола)
/// - executeInternalUpdate: может оказаться без изоляции, т.е. на фоне
/// - didSet: потенциально на фоне (небезопасно для UI, т.к. есть прослойка Observation которая может синхронизировать доступ)
///
/// Вывод: Если нужен полный compile-time контроль и удобство, объявляйте:
/// 1. Класс как `@MainActor`, или
/// 2. Конформанс к протоколу внутри тела класса,
/// чтобы все свойства и методы реально были под защитой главного актора.
