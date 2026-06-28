import Cocoa

enum St { case sleep, idle, walk, digging, away, falling, zoomies, hunt
    var label: String {
        switch self {
        case .sleep:   return "sleeping"
        case .idle:    return "idle"
        case .walk:    return "walking"
        case .digging: return "digging"
        case .away:    return "away (out)"
        case .falling: return "falling"
        case .zoomies: return "zoomies"
        case .hunt:    return "hunting"
        }
    }
}

enum Mood: String, CaseIterable {
    case playful, lazy, curious, hungry, normal
    var label: String {
        switch self {
        case .playful: return "Playful"; case .lazy: return "Lazy"
        case .curious: return "Curious"; case .hungry: return "Hungry"; case .normal: return "Normal"
        }
    }
}

// Движок поведения: решает «мозг + позу» за тик. Переключается в дебаге.
// Физика корма, перетаскивание и падение — общие (в tick), движков не касаются.
protocol CatEngine: AnyObject {
    var label: String { get }
    func step(_ app: AppDelegate)
}
// Текущее поведение — рефлексный агент: условие→действие, флаги + взвешенный рандом. Эталон.
final class ReflexEngine: CatEngine {
    let label = "reflex"
    func step(_ app: AppDelegate) { app.reflexStep() }
}
// Новый движок — utility-агент: нужды через response-кривые + взвешенный выбор с инерцией.
// Тело (исполнение состояний) общее с Reflex; отличается только «мозг» (решение что дальше).
final class UtilityEngine: CatEngine {
    let label = "utility"
    func step(_ app: AppDelegate) { app.utilityStep() }
}
func makeEngine(_ name: String) -> CatEngine {
    name == "utility" ? UtilityEngine() : ReflexEngine()
}
