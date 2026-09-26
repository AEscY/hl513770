import Foundation

// MARK: - 单根K线
struct Candle: Identifiable, Codable {
    var id: String { date }
    let date: String      // MM-dd
    let open: Double
    let high: Double
    let low: Double
    let close: Double
}

// MARK: - 实时行情
struct Quote: Codable, Equatable {
    let code: String
    let name: String
    let price: Double
    let preClose: Double
    let open: Double
    let high: Double
    let low: Double
    let time: String

    var change: Double { price - preClose }
    var changePct: Double { preClose > 0 ? (price - preClose) / preClose * 100 : 0 }
}

// MARK: - 信号
enum Signal: String, Codable {
    case red = "R", yellow = "Y", green = "G", none = "N"

    var title: String {
        switch self {
        case .red: return "红"
        case .yellow: return "黄"
        case .green: return "绿"
        case .none: return "—"
        }
    }
    var desc: String {
        switch self {
        case .red: return "红灯 · 下跌趋势中"
        case .yellow: return "黄灯 · 反弹未确认"
        case .green: return "绿灯 · 趋势转强"
        case .none: return "数据不足"
        }
    }
    var action: String {
        switch self {
        case .red: return "只卖不买，禁止加仓"
        case .yellow: return "观望为主，站稳3天才算数"
        case .green: return "趋势转强，可正常操作"
        case .none: return "等待数据"
        }
    }
    var swiftUIColor: String {
        switch self {
        case .red: return "red"
        case .yellow: return "yellow"
        case .green: return "green"
        case .none: return "gray"
        }
    }
}

// MARK: - 自选标的
struct WatchItem: Identifiable, Codable, Equatable {
    var id: String { code }
    let code: String      // sh513770
    var name: String
    var price: Double?
    var changePct: Double?
    var signalRaw: String?

    var signal: Signal { Signal(rawValue: signalRaw ?? "N") ?? .none }
}

// MARK: - 持仓
struct Position: Codable {
    var cost: Double = 0
    var qty: Double = 0
}
