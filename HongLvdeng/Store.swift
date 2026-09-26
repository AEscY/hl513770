import Foundation

/// 自选、持仓的本地持久化（UserDefaults）
final class Store: ObservableObject {

    @Published var watchList: [WatchItem] {
        didSet { save() }
    }
    @Published var currentCode: String {
        didSet { UserDefaults.standard.set(currentCode, forKey: Store.kCurrent) }
    }

    private static let kWatch = "hl_watch_v1"
    private static let kCurrent = "hl_cur_v1"
    private static let kPosPrefix = "hl_pos_"

    static let defaultWatch = [
        WatchItem(code: "sh513770", name: "港股互联网ETF")
    ]

    init() {
        if let data = UserDefaults.standard.data(forKey: Store.kWatch),
           let list = try? JSONDecoder().decode([WatchItem].self, from: data),
           !list.isEmpty {
            watchList = list
        } else {
            watchList = Store.defaultWatch
        }
        let saved = UserDefaults.standard.string(forKey: Store.kCurrent)
        currentCode = (saved != nil && watchList.contains { $0.code == saved })
            ? saved! : watchList[0].code
    }

    private func save() {
        if let data = try? JSONEncoder().encode(watchList) {
            UserDefaults.standard.set(data, forKey: Store.kWatch)
        }
    }

    func add(code: String, name: String) {
        guard !watchList.contains(where: { $0.code == code }) else { return }
        watchList.append(WatchItem(code: code, name: name))
    }

    func remove(code: String) {
        guard watchList.count > 1 else { return }
        watchList.removeAll { $0.code == code }
        if currentCode == code { currentCode = watchList[0].code }
    }

    func updatePrice(code: String, price: Double?, pct: Double?, signal: Signal?) {
        guard let i = watchList.firstIndex(where: { $0.code == code }) else { return }
        if let p = price { watchList[i].price = p }
        if let c = pct { watchList[i].changePct = c }
        watchList[i].signalRaw = signal?.rawValue
    }

    // MARK: - 持仓（按标的独立保存）

    func position(for code: String) -> Position {
        let key = Store.kPosPrefix + code
        guard let data = UserDefaults.standard.data(forKey: key),
              let p = try? JSONDecoder().decode(Position.self, from: data) else {
            return Position()
        }
        return p
    }

    func savePosition(_ p: Position, for code: String) {
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: Store.kPosPrefix + code)
        }
    }
}

// MARK: - 预设清单

/// 预设项。必须用 struct 而不是 tuple —— Swift 的 KeyPath 不支持 tuple，
/// ForEach(id:\.code) 对 tuple 数组会编译失败。
struct PresetItem: Identifiable {
    var id: String { code }
    let code: String
    let name: String
    let note: String
    let weight: Double

    init(code: String, name: String, note: String = "", weight: Double = 0) {
        self.code = code
        self.name = name
        self.note = note
        self.weight = weight
    }
}

enum Presets {
    /// 常用标的，添加页可直接点
    static let quick: [PresetItem] = [
        PresetItem(code: "sh513770", name: "港股互联网ETF"),
        PresetItem(code: "sh510300", name: "沪深300ETF"),
        PresetItem(code: "sz159915", name: "创业板ETF"),
        PresetItem(code: "sh588000", name: "科创50ETF"),
        PresetItem(code: "sh512880", name: "证券ETF"),
        PresetItem(code: "sh513180", name: "恒生科技ETF"),
        PresetItem(code: "sz159941", name: "纳指ETF"),
        PresetItem(code: "sh518880", name: "黄金ETF"),
        PresetItem(code: "sh000001", name: "上证指数"),
        PresetItem(code: "sh000300", name: "沪深300"),
        PresetItem(code: "sz399006", name: "创业板指"),
        PresetItem(code: "sh000688", name: "科创50")
    ]

    /// 隔夜外围
    static let globalIdx: [PresetItem] = [
        PresetItem(code: "hkHSTECH", name: "恒生科技", note: "港股科技 · 直接相关"),
        PresetItem(code: "hkHSI", name: "恒生指数", note: "港股大盘"),
        PresetItem(code: "usIXIC", name: "纳斯达克", note: "美股科技"),
        PresetItem(code: "usDJI", name: "道琼斯", note: "美股大盘"),
        PresetItem(code: "usINX", name: "标普500", note: "美股大盘")
    ]

    /// 中概股 ADR（权重 %）
    static let adrs: [PresetItem] = [
        PresetItem(code: "usBABA", name: "阿里巴巴", weight: 14.0),
        PresetItem(code: "usTCEHY", name: "腾讯ADR", weight: 13.5),
        PresetItem(code: "usBIDU", name: "百度", weight: 12.0),
        PresetItem(code: "usJD", name: "京东", weight: 4.0),
        PresetItem(code: "usNTES", name: "网易", weight: 6.0),
        PresetItem(code: "usPDD", name: "拼多多", weight: 3.0)
    ]

    /// 港股互联网前十大成分股（权重 %）
    static let holdings: [PresetItem] = [
        PresetItem(code: "hk00700", name: "腾讯控股", weight: 13.5),
        PresetItem(code: "hk09988", name: "阿里巴巴", weight: 14.0),
        PresetItem(code: "hk09888", name: "百度", weight: 12.0),
        PresetItem(code: "hk01810", name: "小米", weight: 9.9),
        PresetItem(code: "hk03690", name: "美团", weight: 9.4),
        PresetItem(code: "hk09999", name: "网易", weight: 6.0),
        PresetItem(code: "hk01024", name: "快手", weight: 5.5),
        PresetItem(code: "hk09961", name: "携程", weight: 4.5),
        PresetItem(code: "hk09626", name: "B站", weight: 3.0),
        PresetItem(code: "hk00020", name: "商汤", weight: 2.0)
    ]
}

// MARK: - 代码规范化

enum CodeUtil {
    /// 6 位数字自动补市场前缀
    static func normalize(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        if t.count == 6, Int(t) != nil { return t }        // 已带前缀的按原样处理见下
        if t.hasPrefix("sh") || t.hasPrefix("sz") || t.hasPrefix("bj") || t.hasPrefix("hk") || t.hasPrefix("us") { return t }
        return nil
    }

    /// 纯 6 位数字判断市场
    static func fromSix(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count == 6, Int(t) != nil else { return nil }
        switch t.first {
        case "6", "5", "9": return "sh" + t
        case "0", "2", "3", "1": return "sz" + t
        case "4", "8": return "bj" + t
        default: return "sh" + t
        }
    }
}
