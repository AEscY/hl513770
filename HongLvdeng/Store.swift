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

enum Presets {
    /// 常用标的，添加页可直接点
    static let quick: [(code: String, name: String)] = [
        ("sh513770", "港股互联网ETF"),
        ("sh510300", "沪深300ETF"),
        ("sz159915", "创业板ETF"),
        ("sh588000", "科创50ETF"),
        ("sh512880", "证券ETF"),
        ("sh513180", "恒生科技ETF"),
        ("sz159941", "纳指ETF"),
        ("sh518880", "黄金ETF"),
        ("sh000001", "上证指数"),
        ("sh000300", "沪深300"),
        ("sz399006", "创业板指"),
        ("sh000688", "科创50")
    ]

    /// 隔夜外围
    static let globalIdx: [(code: String, name: String, note: String)] = [
        ("hkHSTECH", "恒生科技", "港股科技 · 直接相关"),
        ("hkHSI", "恒生指数", "港股大盘"),
        ("usIXIC", "纳斯达克", "美股科技"),
        ("usDJI", "道琼斯", "美股大盘"),
        ("usINX", "标普500", "美股大盘")
    ]

    /// 中概股 ADR（权重 %）
    static let adrs: [(code: String, name: String, weight: Double)] = [
        ("usBABA", "阿里巴巴", 14.0),
        ("usTCEHY", "腾讯ADR", 13.5),
        ("usBIDU", "百度", 12.0),
        ("usJD", "京东", 4.0),
        ("usNTES", "网易", 6.0),
        ("usPDD", "拼多多", 3.0)
    ]

    /// 港股互联网前十大成分股（权重 %）
    static let holdings: [(code: String, name: String, weight: Double)] = [
        ("hk00700", "腾讯控股", 13.5),
        ("hk09988", "阿里巴巴", 14.0),
        ("hk09888", "百度", 12.0),
        ("hk01810", "小米", 9.9),
        ("hk03690", "美团", 9.4),
        ("hk09999", "网易", 6.0),
        ("hk01024", "快手", 5.5),
        ("hk09961", "携程", 4.5),
        ("hk09626", "B站", 3.0),
        ("hk00020", "商汤", 2.0)
    ]
}

// MARK: - 代码规范化

enum CodeUtil {
    /// 6 位数字自动补市场前缀
    static func normalize(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        if t.count == 6, let _ = Int(t) { return t }        // 已带前缀的按原样处理见下
        if t.hasPrefix("sh") || t.hasPrefix("sz") || t.hasPrefix("bj") || t.hasPrefix("hk") || t.hasPrefix("us") { return t }
        return nil
    }

    /// 纯 6 位数字判断市场
    static func fromSix(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count == 6, let _ = Int(t) else { return nil }
        switch t.first {
        case "6", "5", "9": return "sh" + t
        case "0", "2", "3", "1": return "sz" + t
        case "4", "8": return "bj" + t
        default: return "sh" + t
        }
    }
}
