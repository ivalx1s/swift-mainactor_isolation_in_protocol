## Подходы к изоляции с помощью `MainActor` и протоколов в Swift

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-red?logo=swift)](https://swift.org/download/) [![Xcode 15+](https://img.shields.io/badge/Xcode-15+-blue?logo=xcode)](https://developer.apple.com/xcode/) [![Swift 6](https://img.shields.io/badge/Swift-6.0+-red?logo=swift)](https://swift.org/download/) [![Xcode 16+](https://img.shields.io/badge/Xcode-16+-blue?logo=xcode)](https://developer.apple.com/xcode/) [![RU](https://img.shields.io/badge/Translation-EN-green)](https://github.com/ivalx1s/swift-mainactor_isolation_in_protocol/blob/main/README.md)

При работе с кодом, привязанным к основному потоку (особенно при обновлении UI в SwiftUI или UIKit), могут возникать проблемы с конкурентностью, если ваши данные не изолированы должным образом с помощью `MainActor`. Хотя широко практикуется объявлять класс (или его методы) на главном акторе с помощью аннотации `@MainActor`, более тонкий способ — изоляция методов через протокольные расширения — освещён в меньшей степени и не так хорошо документирован в сетевых ресурсах.

В этой статье мы рассмотрим два способа изоляции на главном акторе:

1. **Весь класс помечен `@MainActor`**: простой подход, когда весь класс становится изолированным на `MainActor`, обеспечивая понятную и всеобъемлющую защиту от ошибок, связанных с многопоточностью.
2. **Изоляция на уровне протокола через extension**: более тонкая техника, при которой только свойства и методы, определённые в протоколе, становятся изолированными на `MainActor`. Это даёт более гибкое управление конкурентностью.

Мы изучим примеры кода, рассмотрим сценарии, где каждый из способов наиболее полезен, и покажем, как проверки компилятора Swift 6 помогают заранее выявлять потенциальные ошибки в области конкурентного доступа.

---

### Пример настройки

Ниже определён протокол `MainActorIsolated` с атрибутом `@MainActor`:

```swift
@MainActor
protocol MainActorIsolated {
    func performUpdate(with date: Date) async
}
```

Базовый класс со свойством, которое может использоваться в UI:

```swift
@Observable
final class Store {
    var lastUpdate: Date = .now {
        didSet {
            logThread("DidSet triggered on:")
        }
    }

    private func logThread(_ message: String) {
        print("\(message): \(Thread.current)")
    }

    func executeInternalUpdate(with date: Date) async {
        try? await Task.sleep(nanoseconds: 100_000_000)
        logThread("Internal update executing on:")
        lastUpdate = date
    }
}
```

---

### 1. Полная изоляция класса на `MainActor`

Если объявить соответствие (`conformance`) протоколу, который помечен атрибутом @MainActor, внутри тела класса, то **весь класс** становится изолированным на главном акторе. Это означает, что **каждое** свойство и метод гарантированно выполняются в главном потоке, что обеспечивает высокую безопасность для кода, связанного с UI.

```swift
// Весь класс изолирован на MainActor
@Observable
final class Store: MainActorIsolated {
    func performUpdate(with date: Date) async {
        await executeInternalUpdate(with: date)
    }
}
```

В ситуациях, когда вы привязываете экземпляр `Store` к представлению SwiftUI (или интегрируете его в UI другим образом), вам, как правило, нужны гарантии на уровне компиляции, что **все** обращения и изменения свойств происходят на главном акторе. Такой подход практически исключает риск случайных модификаций из фонового потока.

---

### 2. Соответствие в extension (частичная изоляция)

Если вы хотите, чтобы только методы из протокола были изолированы на главном акторе (при этом другие части класса могли работать на разных акторах или потоках), можно объявить соответствие протоколу в `extension`. Этот способ бывает особенно полезен, если у класса несколько обязанностей (привет **S**OLID, но ведь бывает?), и не все из них требуют выполнения на главном потоке.

```swift
// Только методы протокола MainActorIsolated изолированы на главном акторе
extension Store: MainActorIsolated {
    func performUpdate(with date: Date) async {
        // Выполняется в контексте главного актора (по требованию протокола)
        await executeInternalUpdate(with: date) // исполняется вне главного потока
    }
}
```

В таком случае **только** метод `performUpdate(with:)` (и любые другие, прямо прописанные в `MainActorIsolated`) будет гарантированно выполняться на главном акторе. Остальные части `Store` останутся без ограничений. Это удобно, если вы «расширяете» класс за счёт протокола и хотите, чтобы только определённые действия были изолированы, сохраняя при этом гибкость для остальных операций.

> **Примечание:** Такой подход требует осторожности, если вы невольно полагаетесь на доступ к свойствам или методам, которым также нужна изоляция на главном потоке, но они не входят в протокол. **Убедитесь, что вам действительно нужна частичная изоляция.**

Важно осознать, что реализуя соответствие протоколу в расширении класса, весь класс не наследует изоляцию, прописанную в протоколе. Это может быть контр-интуитивно, особенно если учесть тот факт, что в Swift принято реализовывать протоколы в расширениях к типу. Если следовать этому подходу без должного понимания механики наследованная изоляции от дефиниции протокола, можно оказаться в ситуации, когда мы ожидаем что, что класс будет изолирован, но этого не произойдет.

Это логичное поведение языка, т.к. расширение по определению не может (и не должно) изменять изоляцию сущности, которую оно расширяет. Но этот тот факт, который все же стоит держать в голове при проектировании изоляции вашего кода.

---

### Когда выгодна частичная изоляция

1. **«Затемнение» методов или множественная реализация протоколов**: допустим, класс `Store` должен соответствовать другому протоколу, который допускает или требует выполнение на фоне. Благодаря изоляции только методов `MainActorIsolated` в extension, вы сможете избежать того, чтобы остальные методы принудительно вызывались на главном потоке.  
2. **Соображения производительности**: некая логика может потребовать интенсивного использования CPU, и её лучше выполнять в фоне или на параллельном акторе. Частичная изоляция гарантирует, что только UI-критические или требующие главного потока методы будут защищены аннотацией `@MainActor`.

---

### Когда выгодна полная изоляция

1. **Данные, ориентированные на UI**: часто `Store` тесно связан с вашими представлениями. Если объявить весь класс `@MainActor` или объявить соответствие внутри тела класса, то все свойства и методы будут надёжно выполняться в главном потоке.  
2. **Безопасность на уровне компиляции**: вы получите более широкие проверки компилятора, которые следят, что **все** обращения к классу совершаются в главном потоке. В Swift 6, например, попытка изменить свойство, изолированное на `MainActor`, из фонового потока вызовет ошибку компиляции.

---

### Сравнительная таблица

| Компонент                     | Полный класс на MainActor                          | Частичное соответствие через extension                   |
|-------------------------------|----------------------------------------------------|-----------------------------------------------------------|
| Охват изоляции                | Весь класс (все свойства и методы)                | Только методы протокола `MainActorIsolated`              |
| Типичный случай использования | Данные, связанные с UI, модели SwiftUI, нужна полная безопасность | Смешанные обязанности, частичная работа с UI, выборочная изоляция |
| Помощь от компилятора         | Сильные гарантии                                   | Ограниченные гарантии (только в части протокола)          |
| Потенциальные гонки данных    | Почти исключены                                    | Возможны, если незащищённые части некорректно обращаются к данным UI |
| Идеальные сценарии            | AppState, View Models, пользовательские данные    | Общие модули, выборочная конкурентность, частичные UI-обновления |

---

### Интеграция со Swift Observation

```swift
@Observable class Store {
    // Автоматически синхронизирует изменения свойств (но Main Thread Checker не отлавливает всю конкурентность)
    var value: Date = .now
}
```

Похоже, что макрос `@Observable` в Swift отправляет уведомления об изменении свойств в главный поток. Однако это поведение основано скорее на эмпирических наблюдениях, чем на жёстком механизме безопасности потоков. Поэтому для надёжной работы с конкурентностью рекомендуется явно использовать `@MainActor` или внедрять частичную изоляцию, как описано выше.

---

### Проверки в Swift 6

Начиная со Swift 6, компилятор может помочь отследить вызовы методов и свойств, изолированных на `MainActor`, если вы по ошибке вызываете их за пределами контекста главного актора. Например:

```swift
extension Store: MainActorIsolated {
    func performUpdate(with date: Date) async {
    // Sending main actor-isolated 'self.store' to nonisolated instance method 'performUpdate(with:)'
    // risks causing data races between nonisolated and main actor-isolated uses
        await executeInternalUpdate(with: date)
    }
}
```

или, если `performUpdate(with:)` не изолирован на `MainActor` через протокол или другие средства:

```swift
Button("Trigger Update") {
    Task {
    // Sending main actor-isolated 'self.store' to nonisolated instance method 'performUpdate(with:)'
    // risks causing data races between nonisolated and main actor-isolated uses
        await store.performUpdate(with: .now)
    }
}
```

---

При работе с данными, связанными с UI в Swift, у разработчиков есть несколько эффективных способов управлять изоляцией акторов. Для классов, главным образом обрабатывающих состояние, связанное с пользовательским интерфейсом, объявление всего класса с `@MainActor` даёт наиболее надёжный подход: он обеспечивает строгую безопасность на этапе компиляции и понятную модель конкурентности. Если ваш класс решает более разнообразные задачи, частичная изоляция через расширения протоколов становится ценным приёмом, позволяя выбирать, какие методы будут выполняться на главном акторе и сохраняя при этом гибкость для остальных частей кода.

Новый компилятор Swift 6 повышает уровень защиты, благодаря расширенному статическому анализу, который ещё на этапе компиляции может выявлять потенциальные проблемы с многопоточностью. Подобные проверки позволяют ловить и устранять гонки данных до запуска приложения.

В конечном счёте, овладение этими паттернами изоляции акторов важно для написания надёжного многопоточного кода на Swift. Независимо от того, какой путь вы выберете — изоляцию всего класса или более детальную стратегию, — понимание этих механизмов даёт возможность создавать более предсказуемые и удобные в сопровождении конкурентные приложения, минимизируя риск непредвиденных сложностей с потоками.
