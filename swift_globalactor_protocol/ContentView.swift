import SwiftUI

@main
struct swift_globalactor_protocolApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// цель: получить изоляцию мейн актора через конформанс к протоколу
// для того что бы иметь гарантии, что сущности реализующие протокол,
// будут изолированы мейн актором.
//
// по итогу, строгой изоляции получить на можем, тк. передача изоляции через протокол работает
// только для случае, когда конформанс к протоколу происходит в декларации класса

@MainActor // Протокол помечен атрибутом Main Actor
protocol IUpdate {
    func update(date: Date) async
}

extension LS  {
    func update(date: Date) async {
        print("update: ", Thread.current)
        await internalUpdate(date: date)
    }
}

// вызов апдейт на главном (очевидное поведение) но не подходит для случая когда объект в вью не закрыт протоколом IUpdate
//extension IUpdate {
//    func update(date: Date) async {
//        print("update: ", Thread.current)
//    }
//}


// Конформанс к протоколу в экстеншене класса - исполнение метода update на главном потоке
// internalUpdate на не главном потоке (по итогу, мутация LS из не мейна, изоляция не обеспечена, не интуитивное поведение), didSet не из мейн
//extension LS: IUpdate {
//    func update(date: Date) async {
//        print("update: ", Thread.current)
//        await internalUpdate(date: date)
//    }
//}


// Конформанс к протоколу в декларации класса - исполнение метода update на главном потоке
// internalUpdate на главном потоке мутация LS не мейна, didSet мейн
// не имеет значения, реализация update в декларации класса или в экстеншене класса
@Observable
final class LS: IUpdate {
    var date: Date = .now {
        didSet {
            print("didset: ", Thread.current)
        }
    }

//    func update(date: Date) async {
//        print("update: ", Thread.current)
//        await internalUpdate(date: date)
//    }
}

extension LS {
    private func internalUpdate(date: Date) async {
        print("internalUpdate: ", Thread.current)
        self.date = date
    }
}

struct ContentView: View {
    @State private var ls: LS = .init()

    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, Global Actors!")
            Text("date \(ls.date)")

            Button(action: riseUpdate) { Text("Rise") }
        }
        .padding()
    }

    private func riseUpdate() {
        Task.detached {
            await ls.update(date: .now)
        }
    }
}

