import SwiftUI
import Foundation

// MARK: - 数据模型

struct HLCandle {
    let date: String
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    var volume: Double = 0
}

struct HLQuote {
    let code: String
    let name: String
    let price: Double
    let preClose: Double
    let open: Double
    let high: Double
    let low: Double
    let volume: Double      // 手
    let amount: Double      // 元
    let turnover: Double    // 换手率 %
    let volRatio: Double    // 量比
    let amplitude: Double   // 振幅 %
    let timeText: String    // 数据时间
    let source: String      // 数据源

    var change: Double { price - preClose }
    var changePct: Double { preClose > 0 ? (price - preClose) / preClose * 100 : 0 }

    var amountText: String {
        if amount <= 0 { return "—" }
        if amount >= 100000000 { return String(format: "%.2f 亿", amount / 100000000) }
        if amount >= 10000 { return String(format: "%.2f 万", amount / 10000) }
        return String(format: "%.0f 元", amount)
    }
    var volumeText: String {
        if volume <= 0 { return "—" }
        if volume >= 10000 { return String(format: "%.2f 万手", volume / 10000) }
        return String(format: "%.0f 手", volume)
    }
}

// 腾讯时间字段兼容：A股 20260924161443 / 港美股 2026/09/25 16:08:36
func HLTimeText(_ raw: String) -> String {
    if raw.isEmpty { return "" }
    if raw.count == 14 {
        let all = raw.allSatisfy { $0 >= "0" && $0 <= "9" }
        if all {
            let mo = String(raw.dropFirst(4).prefix(2))
            let dy = String(raw.dropFirst(6).prefix(2))
            let hh = String(raw.dropFirst(8).prefix(2))
            let mm = String(raw.dropFirst(10).prefix(2))
            return mo + "-" + dy + " " + hh + ":" + mm
        }
    }
    // 2026/09/25 16:08:36 -> 09-25 16:08
    let parts = raw.components(separatedBy: " ")
    if parts.count >= 2 {
        let d = parts[0].components(separatedBy: "/")
        if d.count >= 3 {
            let t = parts[1].components(separatedBy: ":")
            if t.count >= 2 {
                return d[1] + "-" + d[2] + " " + t[0] + ":" + t[1]
            }
        }
    }
    return raw
}

// 数据源时间戳距今多久：解析 "09-24 16:14"
func HLDataAgeSeconds(_ t: String) -> Double {
    let parts = t.components(separatedBy: " ")
    if parts.count < 2 { return -1 }
    let dp = parts[0].components(separatedBy: "-")
    if dp.count < 2 { return -1 }
    let tp = parts[1].components(separatedBy: ":")
    if tp.count < 2 { return -1 }
    let mo = Int(dp[0]) ?? 0
    let dy = Int(dp[1]) ?? 0
    let hh = Int(tp[0]) ?? 0
    let mm = Int(tp[1]) ?? 0
    if mo <= 0 || dy <= 0 { return -1 }
    let cal = Calendar.current
    let now = Date()
    let yc = cal.dateComponents([.year], from: now)
    var target = DateComponents()
    target.year = yc.year
    target.month = mo
    target.day = dy
    target.hour = hh
    target.minute = mm
    if let d = cal.date(from: target) {
        if d.timeIntervalSince(now) > 86400 {
            target.year = (yc.year ?? 2026) - 1
            if let d2 = cal.date(from: target) {
                return now.timeIntervalSince(d2)
            }
        }
        return now.timeIntervalSince(d)
    }
    return -1
}

// 友好文案
func HLDataAgeText(_ t: String) -> String {
    let s = HLDataAgeSeconds(t)
    if s < 0 { return "时间未知" }
    if s < 300 { return "实时" }
    if s < 3600 { return "数据 " + String(Int(s / 60)) + " 分钟前" }
    if s < 86400 { return "数据 " + String(Int(s / 3600)) + " 小时前" }
    let d = Int(s / 86400)
    return "数据源停在 " + String(d) + " 天前"
}

func HLDouble(_ parts: [String], _ i: Int) -> Double {
    if i >= parts.count { return 0 }
    return Double(parts[i]) ?? 0
}

func HLStr(_ parts: [String], _ i: Int) -> String {
    if i >= parts.count { return "" }
    return parts[i]
}

enum HLSignal: String {
    case red = "R"
    case yellow = "Y"
    case green = "G"
    case none = "N"

    var title: String {
        if self == .red { return "红" }
        if self == .yellow { return "黄" }
        if self == .green { return "绿" }
        return "—"
    }
    var desc: String {
        if self == .red { return "红灯 · 下跌趋势中" }
        if self == .yellow { return "黄灯 · 反弹未确认" }
        if self == .green { return "绿灯 · 趋势转强" }
        return "数据不足"
    }
    var action: String {
        if self == .red { return "只卖不买，禁止加仓" }
        if self == .yellow { return "观望为主，站稳3天才算数" }
        if self == .green { return "趋势转强，可正常操作" }
        return "等待数据"
    }
    var color: Color {
        if self == .red { return Color(red: 1.0, green: 0.30, blue: 0.37) }
        if self == .yellow { return Color(red: 1.0, green: 0.69, blue: 0.13) }
        if self == .green { return Color(red: 0.0, green: 0.84, blue: 0.56) }
        return Color(white: 0.42)
    }
}

struct HLItem {
    let code: String
    let name: String
    var weight: Double
}

struct HLPreset {
    let code: String
    let name: String
    let note: String
    let weight: Double
}

let HLGlobalIdx = [
    HLPreset(code: "hkHSTECH", name: "恒生科技", note: "港股科技 · 直接相关", weight: 0),
    HLPreset(code: "hkHSI", name: "恒生指数", note: "港股大盘", weight: 0),
    HLPreset(code: "usIXIC", name: "纳斯达克", note: "美股科技", weight: 0),
    HLPreset(code: "usDJI", name: "道琼斯", note: "美股大盘", weight: 0),
    HLPreset(code: "usINX", name: "标普500", note: "美股大盘", weight: 0)
]

let HLAdrs = [
    HLPreset(code: "usBABA", name: "阿里巴巴", note: "", weight: 14.0),
    HLPreset(code: "usTCEHY", name: "腾讯ADR", note: "", weight: 13.5),
    HLPreset(code: "usBIDU", name: "百度", note: "", weight: 12.0),
    HLPreset(code: "usJD", name: "京东", note: "", weight: 4.0),
    HLPreset(code: "usNTES", name: "网易", note: "", weight: 6.0),
    HLPreset(code: "usPDD", name: "拼多多", note: "", weight: 3.0)
]

let HLHoldings = [
    HLPreset(code: "hk00700", name: "腾讯控股", note: "", weight: 13.5),
    HLPreset(code: "hk09988", name: "阿里巴巴", note: "", weight: 14.0),
    HLPreset(code: "hk09888", name: "百度", note: "", weight: 12.0),
    HLPreset(code: "hk01810", name: "小米", note: "", weight: 9.9),
    HLPreset(code: "hk03690", name: "美团", note: "", weight: 9.4),
    HLPreset(code: "hk09999", name: "网易", note: "", weight: 6.0),
    HLPreset(code: "hk01024", name: "快手", note: "", weight: 5.5),
    HLPreset(code: "hk09961", name: "携程", note: "", weight: 4.5),
    HLPreset(code: "hk09626", name: "B站", note: "", weight: 3.0),
    HLPreset(code: "hk00020", name: "商汤", note: "", weight: 2.0)
]

// MARK: - 状态

final class HLModel: ObservableObject {
    @Published var candles: [HLCandle] = []
    @Published var quote: HLQuote?
    @Published var note: String = "加载中…"
    @Published var watch: [HLItem] = [
        HLItem(code: "sh513770", name: "港股互联网ETF", weight: 0),
        HLItem(code: "sh510300", name: "沪深300ETF", weight: 0),
        HLItem(code: "sz159915", name: "创业板ETF", weight: 0)
    ]
    @Published var curCode: String = "sh513770"

    var closes: [Double] { candles.map { $0.close } }
    var highs: [Double] { candles.map { $0.high } }
    var lows: [Double] { candles.map { $0.low } }
    var opens: [Double] { candles.map { $0.open } }
    var volumes: [Double] { candles.map { $0.volume } }

    // 市场异常扫描（纯算法在 HLCore，可被云端验证）
    var anomalies: [HLAnomalyItem] {
        if candles.count < 70 { return [] }
        return HLCore.anomalyScan(closes, highs, lows, opens, volumes)
    }
    var anomalyAgg: (level: Int, score: Int, count: Int) {
        return HLCore.anomalyLevel(anomalies)
    }
    var lastPrice: Double { quote?.price ?? (closes.last ?? 0) }

    func ma(_ k: Int) -> Double? {
        return HLCore.ma(closes, k)
    }

    func atr() -> Double? {
        let c = closes
        let h = highs
        let l = lows
        if c.count < 15 { return nil }
        var tr: [Double] = []
        var i = 1
        while i < c.count {
            let a = h[i] - l[i]
            let b = abs(h[i] - c[i - 1])
            let d = abs(l[i] - c[i - 1])
            var m = a
            if b > m { m = b }
            if d > m { m = d }
            tr.append(m)
            i += 1
        }
        if tr.count < 14 { return nil }
        var s = 0.0
        var j = 0
        while j < 14 {
            s += tr[j]
            j += 1
        }
        var r = s / 14.0
        if tr.count > 14 {
            var k = 14
            while k < tr.count {
                r = (r * 13.0 + tr[k]) / 14.0
                k += 1
            }
        }
        return r
    }

    var signal: HLSignal {
        let m20 = ma(20)
        let m60 = ma(60)
        if m20 == nil || m60 == nil { return .none }
        let p = lastPrice
        if p < m20! { return .red }
        if p < m60! { return .yellow }
        return .green
    }

    var nextYellow: Double? {
        let c = closes
        if c.count < 19 { return nil }
        var s = 0.0
        var i = c.count - 19
        while i < c.count {
            s += c[i]
            i += 1
        }
        return s / 19.0
    }

    var nextGreen: Double? {
        let c = closes
        if c.isEmpty { return nil }
        let n = min(59, c.count)
        var s = 0.0
        var i = c.count - n
        while i < c.count {
            s += c[i]
            i += 1
        }
        return s / Double(n)
    }

    var stopLoss: Double? {
        let a = atr()
        if a == nil { return nil }
        return lastPrice - 2.0 * a!
    }

    var periodHigh: Double { closes.max() ?? 0 }
    var periodLow: Double { closes.min() ?? 0 }

    var gapToYellow: Double {
        let y = nextYellow
        if y == nil { return 0 }
        return y! - lastPrice
    }

    var maGap: Double {
        let a = ma(20)
        let b = ma(60)
        if a == nil || b == nil { return 0 }
        return a! - b!
    }

    var maGapText: String {
        if ma(20) == nil || ma(60) == nil { return "—" }
        if maGap >= 0 { return "多头排列 +" + hfmt(maGap, 4) }
        return "空头排列 " + hfmt(maGap, 4)
    }

    var maGapColor: Color {
        if ma(20) == nil || ma(60) == nil { return HLDim }
        return maGap >= 0 ? Color(red: 0.0, green: 0.84, blue: 0.56) : Color(red: 1.0, green: 0.30, blue: 0.37)
    }

    // MARK: - 网络

    static func gbkEncoding() -> String.Encoding {
        let cf = CFStringEncodings.GB_18030_2000
        let raw = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cf.rawValue))
        return String.Encoding(rawValue: UInt(raw))
    }

    // MARK: - 实时行情（腾讯主源 + 新浪备源，全部真实请求，无内嵌数据）

    func loadQuotes(_ codes: [String], done: @escaping ([String: HLQuote]) -> Void) {
        if codes.isEmpty {
            DispatchQueue.main.async { done([:]) }
            return
        }
        loadTencent(codes) { map in
            if map.isEmpty == false {
                DispatchQueue.main.async { done(map) }
                return
            }
            // 主源失败，走新浪备源
            self.loadSina(codes) { map2 in
                DispatchQueue.main.async { done(map2) }
            }
        }
    }

    func loadTencent(_ codes: [String], done: @escaping ([String: HLQuote]) -> Void) {
        let list = codes.joined(separator: ",")
        let comps = URLComponents(string: "https://qt.gtimg.cn/q=" + list)
        if comps == nil {
            done([:])
            return
        }
        guard let url = comps!.url else {
            done([:])
            return
        }
        var req = URLRequest(url: url)
        req.setValue("https://gu.qq.com/", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_6 like Mac OS X) AppleWebKit/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 12

        let task = URLSession.shared.dataTask(with: req) { data, _, err in
            if err != nil || data == nil {
                done([:])
                return
            }
            let enc = HLModel.gbkEncoding()
            guard let text = String(data: data!, encoding: enc) else {
                done([:])
                return
            }
            var out: [String: HLQuote] = [:]
            let lines = text.components(separatedBy: ";")
            for rawLine in lines {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.hasPrefix("v_") == false { continue }
                guard let eq = line.firstIndex(of: "=") else { continue }
                let startIdx = line.index(line.startIndex, offsetBy: 2)
                if startIdx >= eq { continue }
                let key = String(line[startIdx..<eq])
                var body = String(line[line.index(after: eq)...])
                body = body.trimmingCharacters(in: CharacterSet(charactersIn: "\"\n\r "))
                let parts = body.components(separatedBy: "~")
                if parts.count < 6 { continue }
                let price = HLDouble(parts, 3)
                if price <= 0 { continue }
                let pre = HLDouble(parts, 4)
                let op = HLDouble(parts, 5)
                var hi = HLDouble(parts, 33)
                var lo = HLDouble(parts, 34)
                if hi <= 0 { hi = price }
                if lo <= 0 { lo = price }
                var vol = HLDouble(parts, 36)
                if vol <= 0 { vol = HLDouble(parts, 6) }
                let amtWan = HLDouble(parts, 37)
                var amt = amtWan * 10000
                if amt <= 0 {
                    // 从组合字段 价/量/额 里取
                    let comb = HLStr(parts, 35)
                    let cp = comb.components(separatedBy: "/")
                    if cp.count >= 3 { amt = HLDouble(cp, 2) }
                }
                let turnover = HLDouble(parts, 38)
                let volRatio = HLDouble(parts, 49)
                let amplitude = HLDouble(parts, 43)
                let tText = HLTimeText(HLStr(parts, 30))
                out[key] = HLQuote(code: key, name: HLStr(parts, 1), price: price,
                                   preClose: pre, open: op, high: hi, low: lo,
                                   volume: vol, amount: amt, turnover: turnover,
                                   volRatio: volRatio, amplitude: amplitude,
                                   timeText: tText, source: "腾讯")
            }
            done(out)
        }
        task.resume()
    }

    func loadSina(_ codes: [String], done: @escaping ([String: HLQuote]) -> Void) {
        var sinaCodes: [String] = []
        var keyMap: [String: String] = [:]
        for c in codes {
            let sc = HLModel.sinaCode(c)
            sinaCodes.append(sc)
            keyMap[sc] = c
        }
        let list = sinaCodes.joined(separator: ",")
        guard let url = URL(string: "https://hq.sinajs.cn/list=" + list) else {
            done([:])
            return
        }
        var req = URLRequest(url: url)
        req.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        req.timeoutInterval = 12

        let task = URLSession.shared.dataTask(with: req) { data, _, err in
            if err != nil || data == nil {
                done([:])
                return
            }
            let enc = HLModel.gbkEncoding()
            guard let text = String(data: data!, encoding: enc) else {
                done([:])
                return
            }
            var out: [String: HLQuote] = [:]
            let lines = text.components(separatedBy: ";")
            for rawLine in lines {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.hasPrefix("var hq_str_") == false { continue }
                guard let eq = line.firstIndex(of: "=") else { continue }
                let startIdx = line.index(line.startIndex, offsetBy: 11)
                if startIdx >= eq { continue }
                let sc = String(line[startIdx..<eq])
                let origKey = keyMap[sc] ?? sc
                var body = String(line[line.index(after: eq)...])
                body = body.trimmingCharacters(in: CharacterSet(charactersIn: "\"\n\r "))
                let parts = body.components(separatedBy: ",")
                if parts.count < 6 { continue }

                var name = ""
                var price = 0.0
                var pre = 0.0
                var op = 0.0
                var hi = 0.0
                var lo = 0.0
                var vol = 0.0
                var amt = 0.0
                var tText = ""

                if sc.hasPrefix("gb_") {
                    // 美股：名称,现价,涨跌幅%,时间,涨跌额,开盘,最高,最低,52高,52低,成交量...
                    name = HLStr(parts, 0)
                    price = HLDouble(parts, 1)
                    let pct = HLDouble(parts, 2)
                    tText = HLTimeText(HLStr(parts, 3))
                    let chg = HLDouble(parts, 4)
                    pre = price - chg
                    if pre <= 0 && pct != 0 { pre = price / (1 + pct / 100) }
                    op = HLDouble(parts, 5)
                    hi = HLDouble(parts, 6)
                    lo = HLDouble(parts, 7)
                    vol = HLDouble(parts, 10)
                } else if sc.hasPrefix("rt_hk") {
                    // 港股：英文名,中文名,开盘,昨收,最高,最低,现价,涨跌额,涨跌幅,...
                    name = HLStr(parts, 1)
                    if name.isEmpty { name = HLStr(parts, 0) }
                    op = HLDouble(parts, 2)
                    pre = HLDouble(parts, 3)
                    hi = HLDouble(parts, 4)
                    lo = HLDouble(parts, 5)
                    price = HLDouble(parts, 6)
                    if parts.count > 16 { tText = HLTimeText(HLStr(parts, 17)) }
                } else {
                    // A股/指数：名称,今开,昨收,现价,最高,最低,买一,卖一,成交量,成交额,...
                    name = HLStr(parts, 0)
                    op = HLDouble(parts, 1)
                    pre = HLDouble(parts, 2)
                    price = HLDouble(parts, 3)
                    hi = HLDouble(parts, 4)
                    lo = HLDouble(parts, 5)
                    if parts.count > 9 {
                        vol = HLDouble(parts, 8) / 100.0
                        amt = HLDouble(parts, 9)
                    }
                    if parts.count > 31 { tText = HLStr(parts, 30) }
                }
                if price <= 0 { continue }
                if hi <= 0 { hi = price }
                if lo <= 0 { lo = price }
                out[origKey] = HLQuote(code: origKey, name: name, price: price,
                                       preClose: pre, open: op, high: hi, low: lo,
                                       volume: vol, amount: amt, turnover: 0,
                                       volRatio: 0, amplitude: 0,
                                       timeText: tText, source: "新浪")
            }
            done(out)
        }
        task.resume()
    }

    // 腾讯代码 -> K线接口代码（新浪K线不支持 s_ 前缀，指数必须用 sh000001 这种）
    static func klineCode(_ code: String) -> String {
        // 去掉误加的 s_ 前缀
        if code.hasPrefix("s_") { return String(code.dropFirst(2)) }
        return code
    }

    // 腾讯代码 -> 新浪实时代码
    static func sinaCode(_ code: String) -> String {
        if code.hasPrefix("hk") {
            return "rt_" + code
        }
        if code.hasPrefix("us") {
            let tail = String(code.dropFirst(2)).lowercased()
            return "gb_" + tail
        }
        if code.hasPrefix("sh") || code.hasPrefix("sz") {
            // 6 位纯数字且以 000 开头的指数用 s_ 前缀
            let num = String(code.dropFirst(2))
            if num.hasPrefix("000") { return "s_" + code }
            return code
        }
        return code
    }

    // MARK: - 历史 K 线（新浪 JSON 主源 + 腾讯备源）

    func loadHistory(_ code: String, done: @escaping ([HLCandle]) -> Void) {
        loadSinaKLine(code, scale: 240, len: 320) { list in
            if list.isEmpty == false {
                DispatchQueue.main.async { done(list) }
                return
            }
            self.loadTencentKLine(code) { list2 in
                DispatchQueue.main.async { done(list2) }
            }
        }
    }

    func loadSinaKLine(_ code: String, scale: Int, len: Int, done: @escaping ([HLCandle]) -> Void) {
        // 关键：K线必须用原始代码。s_ 前缀（指数实时用）在K线接口会返回 null。
        let sc = HLModel.klineCode(code)
        let urlStr = "https://money.finance.sina.com.cn/quotes_service/api/json_v2.php/CN_MarketData.getKLineData?symbol="
            + sc + "&scale=" + String(scale) + "&ma=no&datalen=" + String(len)
        guard let url = URL(string: urlStr) else {
            done([])
            return
        }
        var req = URLRequest(url: url)
        req.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        req.timeoutInterval = 15

        let task = URLSession.shared.dataTask(with: req) { data, _, err in
            if err != nil || data == nil {
                done([])
                return
            }
            var out: [HLCandle] = []
            if let arr = try? JSONSerialization.jsonObject(with: data!) as? [[String: Any]] {
                for item in arr {
                    let day = item["day"] as? String ?? ""
                    let o = HLModel.num(item["open"])
                    let h = HLModel.num(item["high"])
                    let l = HLModel.num(item["low"])
                    let c = HLModel.num(item["close"])
                    let vol = HLModel.num(item["volume"])
                    if c > 0 {
                        let short = day.count >= 10 ? String(day.suffix(5)) : day
                        out.append(HLCandle(date: short, open: o, high: h, low: l, close: c, volume: vol))
                    }
                }
            }
            done(out)
        }
        task.resume()
    }

    // 腾讯 K 线字段顺序：日期,开,收,高,低,量
    func loadTencentKLine(_ code: String, done: @escaping ([HLCandle]) -> Void) {
        let urlStr = "https://web.ifzq.gtimg.cn/appstock/app/fqkline/get?param=" + code + ",day,,,320,qfq"
        guard let url = URL(string: urlStr) else {
            done([])
            return
        }
        var req = URLRequest(url: url)
        req.setValue("https://gu.qq.com/", forHTTPHeaderField: "Referer")
        req.timeoutInterval = 15

        let task = URLSession.shared.dataTask(with: req) { data, _, err in
            if err != nil || data == nil {
                done([])
                return
            }
            var out: [HLCandle] = []
            if let obj = try? JSONSerialization.jsonObject(with: data!) as? [String: Any] {
                if let d = obj["data"] as? [String: Any] {
                    if let node = d[code] as? [String: Any] {
                        var raw: [[Any]] = []
                        if let q = node["qfqday"] as? [[Any]] { raw = q }
                        else if let q = node["day"] as? [[Any]] { raw = q }
                        for item in raw {
                            if item.count < 5 { continue }
                            guard let dt = item[0] as? String else { continue }
                            let o = HLModel.num(item[1])
                            let c = HLModel.num(item[2])
                            let h = HLModel.num(item[3])
                            let l = HLModel.num(item[4])
                            let vol = item.count > 5 ? HLModel.num(item[5]) : 0
                            if c > 0 {
                                let short = dt.count >= 10 ? String(dt.suffix(5)) : dt
                                out.append(HLCandle(date: short, open: o, high: h, low: l, close: c, volume: vol))
                            }
                        }
                    }
                }
            }
            done(out)
        }
        task.resume()
    }

    static func num(_ v: Any?) -> Double {
        if v == nil { return 0 }
        if let d = v as? Double { return d }
        if let n = v as? NSNumber { return n.doubleValue }
        if let str = v as? String { return Double(str) ?? 0 }
        return 0
    }

    func loadAll() {
        let code = curCode
        loadQuotes([code]) { map in
            let q = map[code]
            self.quote = q
            if q != nil {
                self.dataTime = q!.timeText
                self.dataSource = q!.source
                self.lastUpdate = Date()
            }
            self.loadHistory(code) { list in
                self.candles = list
                if list.isEmpty {
                    self.note = "K线获取失败"
                } else {
                    self.note = "最新 " + (list.last?.date ?? "") + " · " + String(list.count) + " 个交易日"
                }
                self.loadSinaKLine(code, scale: 5, len: 48) { intra in
                    self.intraday = intra
                }
            }
        }
    }

    func refreshWatch() {
        var codes: [String] = []
        for w in watch { codes.append(w.code) }
        loadQuotes(codes) { map in
            var i = 0
            while i < self.watch.count {
                let code = self.watch[i].code
                if let q = map[code] {
                    self.watch[i].weight = q.price
                }
                i += 1
            }
        }
    }

    func add(code: String) {
        var exists = false
        for w in watch {
            if w.code == code { exists = true }
        }
        if exists { return }
        loadQuotes([code]) { map in
            if let q = map[code] {
                self.watch.append(HLItem(code: code, name: q.name, weight: q.price))
                self.curCode = code
                self.loadAll()
            }
        }
    }

    // 切换标的：立即重新加载，不依赖 View 的 onChange（iOS 15 上更可靠）
    func select(_ code: String) {
        if curCode == code { return }
        curCode = code
        loadAll()
        refreshWatch()
    }

    func remove(code: String) {
        if watch.count <= 1 { return }
        var next: [HLItem] = []
        for w in watch {
            if w.code != code { next.append(w) }
        }
        watch = next
        if curCode == code { curCode = watch[0].code }
        loadAll()
    }
    // MARK: - 外围 / ADR / 成分股

    @Published var globalQuotes: [String: HLQuote] = [:]
    @Published var adrQuotes: [String: HLQuote] = [:]
    @Published var holdQuotes: [String: HLQuote] = [:]
    @Published var intraday: [HLCandle] = []
    @Published var dataTime: String = ""
    @Published var dataSource: String = ""
    @Published var lastUpdate: Date = Date()

    func loadBrief() {
        var g: [String] = []
        for p in HLGlobalIdx { g.append(p.code) }
        loadQuotes(g) { map in
            self.globalQuotes = map
        }
        var a: [String] = []
        for p in HLAdrs { a.append(p.code) }
        loadQuotes(a) { map in
            self.adrQuotes = map
        }
        var h: [String] = []
        for p in HLHoldings { h.append(p.code) }
        loadQuotes(h) { map in
            self.holdQuotes = map
        }
    }

    func weighted(list: [HLPreset], quotes: [String: HLQuote]) -> Double? {
        var sw = 0.0
        var se = 0.0
        for p in list {
            let q = quotes[p.code]
            if q != nil {
                sw += p.weight
                se += p.weight * q!.changePct
            }
        }
        if sw <= 0 { return nil }
        return se / sw
    }

    func coverage(list: [HLPreset], quotes: [String: HLQuote]) -> Double {
        var sw = 0.0
        for p in list {
            if quotes[p.code] != nil { sw += p.weight }
        }
        return sw
    }

    var adrEstimate: Double? { weighted(list: HLAdrs, quotes: adrQuotes) }
    var adrCoverage: Double { coverage(list: HLAdrs, quotes: adrQuotes) }
    var holdEstimate: Double? { weighted(list: HLHoldings, quotes: holdQuotes) }
    var holdCoverage: Double { coverage(list: HLHoldings, quotes: holdQuotes) }

    // MARK: - 技术指标

    func rsi(_ k: Int) -> Double? {
        return HLCore.rsi(closes, k)
    }

    var bollMid: Double? { ma(20) }

    var bollSD: Double? {
        let a = closes
        if a.count < 20 { return nil }
        var arr: [Double] = []
        var i = a.count - 20
        while i < a.count {
            arr.append(a[i])
            i += 1
        }
        let m = bollMid ?? 0
        var s = 0.0
        for v in arr { s += (v - m) * (v - m) }
        return sqrt(s / 20.0)
    }

    var bollUp: Double? {
        let m = bollMid
        let d = bollSD
        if m == nil || d == nil { return nil }
        return m! + 2 * d!
    }

    var bollLow: Double? {
        let m = bollMid
        let d = bollSD
        if m == nil || d == nil { return nil }
        return m! - 2 * d!
    }

    var bollWidth: Double? {
        let m = bollMid
        let u = bollUp
        let l = bollLow
        if m == nil || u == nil || l == nil || m! <= 0 { return nil }
        return (u! - l!) / m! * 100
    }

    var annualVol: Double? {
        let a = closes
        if a.count < 22 { return nil }
        var rets: [Double] = []
        var i = a.count - 20
        while i < a.count {
            if a[i - 1] > 0 { rets.append(log(a[i] / a[i - 1])) }
            i += 1
        }
        if rets.count < 2 { return nil }
        var s = 0.0
        for v in rets { s += v }
        let m = s / Double(rets.count)
        var vv = 0.0
        for v in rets { vv += (v - m) * (v - m) }
        let sd = sqrt(vv / Double(rets.count - 1))
        return sd * sqrt(244.0) * 100
    }

    var avgAmp: Double? {
        let c = closes
        let h = highs
        let l = lows
        if c.count < 21 { return nil }
        var s = 0.0
        var n = 0
        var i = c.count - 20
        while i < c.count {
            if c[i - 1] > 0 {
                s += (h[i] - l[i]) / c[i - 1]
                n += 1
            }
            i += 1
        }
        if n == 0 { return nil }
        return s / Double(n) * 100
    }

    var percentile: Double {
        let hi = periodHigh
        let lo = periodLow
        let r = hi - lo
        if r <= 0 { return 0 }
        return (lastPrice - lo) / r * 100
    }

    // MARK: - 回测（返回纯数字，不画图）

    var btHold: Double {
        let c = closes
        if c.count < 2 { return 1 }
        var v = 1.0
        var i = 1
        while i < c.count {
            v *= c[i] / c[i - 1]
            i += 1
        }
        return v
    }

    var btStrat: Double {
        let c = closes
        if c.count < 2 { return 1 }
        var v = 1.0
        var i = 1
        while i < c.count {
            let m20 = maAt(c, 20, i - 1)
            let m60 = maAt(c, 60, i - 1)
            var pos = 0.0
            if m20 != nil && m60 != nil {
                let p = c[i - 1]
                if p >= m60! { pos = 1.0 }
                else if p >= m20! { pos = 0.5 }
            }
            let ret = c[i] / c[i - 1]
            v *= (1 + pos * (ret - 1))
            i += 1
        }
        return v
    }

    func maAt(_ a: [Double], _ k: Int, _ idx: Int) -> Double? {
        return HLCore.maAt(a, k, idx)
    }

    var btDDHold: Double { maxDD(series: holdCurve) }
    var btDDStrat: Double { maxDD(series: stratCurve) }

    var holdCurve: [Double] {
        let c = closes
        if c.count < 2 { return [1] }
        var out: [Double] = [1]
        var v = 1.0
        var i = 1
        while i < c.count {
            v *= c[i] / c[i - 1]
            out.append(v)
            i += 1
        }
        return out
    }

    var stratCurve: [Double] {
        let c = closes
        if c.count < 2 { return [1] }
        var out: [Double] = [1]
        var v = 1.0
        var i = 1
        while i < c.count {
            let m20 = maAt(c, 20, i - 1)
            let m60 = maAt(c, 60, i - 1)
            var pos = 0.0
            if m20 != nil && m60 != nil {
                let p = c[i - 1]
                if p >= m60! { pos = 1.0 }
                else if p >= m20! { pos = 0.5 }
            }
            let ret = c[i] / c[i - 1]
            v *= (1 + pos * (ret - 1))
            out.append(v)
            i += 1
        }
        return out
    }

    func maxDD(series: [Double]) -> Double {
        var peak = 1.0
        var dd = 0.0
        for v in series {
            if v > peak { peak = v }
            let d = (peak - v) / peak
            if d > dd { dd = d }
        }
        return dd
    }

    func bandAt(_ i: Int) -> HLSignal {
        let c = closes
        if i >= c.count { return .none }
        let m20 = maAt(c, 20, i)
        let m60 = maAt(c, 60, i)
        if m20 == nil || m60 == nil { return .none }
        let p = c[i]
        if p < m20! { return .red }
        if p < m60! { return .yellow }
        return .green
    }
    // MARK: - 专业指标：MACD / KDJ / OBV / 威廉 / 多周期均线

    // EMA 指数移动平均
    func ema(_ k: Int, _ src: [Double]? = nil) -> [Double] {
        let a = src ?? closes
        if a.isEmpty { return [] }
        let alpha = 2.0 / (Double(k) + 1.0)
        var out: [Double] = []
        var prev = a[0]
        out.append(prev)
        var i = 1
        while i < a.count {
            prev = alpha * a[i] + (1 - alpha) * prev
            out.append(prev)
            i += 1
        }
        return out
    }

    // MACD (12,26,9)
    var macdDIF: Double? {
        if closes.count < 26 { return nil }
        let e12 = ema(12)
        let e26 = ema(26)
        if e12.isEmpty || e26.isEmpty { return nil }
        return e12[e12.count - 1] - e26[e26.count - 1]
    }

    var macdDEA: Double? {
        if closes.count < 35 { return nil }
        let e12 = ema(12)
        let e26 = ema(26)
        if e12.count != e26.count || e12.isEmpty { return nil }
        var difSeries: [Double] = []
        var i = 0
        while i < e12.count {
            difSeries.append(e12[i] - e26[i])
            i += 1
        }
        let dea = ema(9, difSeries)
        return dea.isEmpty ? nil : dea[dea.count - 1]
    }

    var macdHist: Double? {
        let d = macdDIF
        let e = macdDEA
        if d == nil || e == nil { return nil }
        return (d! - e!) * 2
    }

    var macdText: String {
        let d = macdDIF
        let e = macdDEA
        if d == nil || e == nil { return "—" }
        if d! > e! && d! > 0 { return "金叉 · 多头" }
        if d! > e! { return "金叉 · 零轴下" }
        if d! < e! && d! < 0 { return "死叉 · 空头" }
        return "死叉 · 零轴上"
    }

    var macdColor: Color {
        let d = macdDIF
        let e = macdDEA
        if d == nil || e == nil { return HLDim }
        return d! > e! ? Color(red: 0.0, green: 0.84, blue: 0.56) : Color(red: 1.0, green: 0.30, blue: 0.37)
    }

    // KDJ (9,3,3)
    var kdj: (k: Double, d: Double, j: Double)? {
        let c = closes
        let h = highs
        let l = lows
        if c.count < 9 { return nil }
        var kVal = 50.0
        var dVal = 50.0
        var i = 8
        while i < c.count {
            var hh = h[i]
            var ll = l[i]
            var j = i - 8
            while j <= i {
                if h[j] > hh { hh = h[j] }
                if l[j] < ll { ll = l[j] }
                j += 1
            }
            let rsv = hh > ll ? (c[i] - ll) / (hh - ll) * 100 : 50
            kVal = (2.0 / 3.0) * kVal + (1.0 / 3.0) * rsv
            dVal = (2.0 / 3.0) * dVal + (1.0 / 3.0) * kVal
            i += 1
        }
        return (kVal, dVal, 3 * kVal - 2 * dVal)
    }

    var kdjText: String {
        let v = kdj
        if v == nil { return "—" }
        let k = v!.k
        let d = v!.d
        if k > 80 { return "超买区" }
        if k < 20 { return "超卖区" }
        return k > d ? "金叉向上" : "死叉向下"
    }

    // 威廉指标 %R (14)
    var williamsR: Double? {
        let c = closes
        let h = highs
        let l = lows
        if c.count < 14 { return nil }
        let i = c.count - 1
        var hh = h[i]
        var ll = l[i]
        var j = i - 13
        while j <= i {
            if h[j] > hh { hh = h[j] }
            if l[j] < ll { ll = l[j] }
            j += 1
        }
        if hh <= ll { return nil }
        return (hh - c[i]) / (hh - ll) * -100
    }

    // OBV 能量潮（用成交量加权）
    var obvTrend: String {
        let c = closes
        if c.count < 21 { return "—" }
        var up = 0
        var down = 0
        var i = c.count - 20
        while i < c.count {
            if c[i] > c[i - 1] { up += 1 }
            else if c[i] < c[i - 1] { down += 1 }
            i += 1
        }
        if up > down + 3 { return "量能偏多" }
        if down > up + 3 { return "量能偏空" }
        return "量能均衡"
    }

    // 多周期均线
    func maLine(_ k: Int) -> Double? { ma(k) }

    var maArrangement: String {
        let m5 = ma(5)
        let m10 = ma(10)
        let m20 = ma(20)
        let m60 = ma(60)
        if m5 == nil || m10 == nil || m20 == nil || m60 == nil { return "—" }
        if m5! > m10! && m10! > m20! && m20! > m60! { return "完美多头排列" }
        if m5! < m10! && m10! < m20! && m20! < m60! { return "完全空头排列" }
        if m5! > m20! { return "短期偏多 · 中期待确认" }
        return "短期偏空 · 中期承压"
    }

    // 支撑压力位（近60日 pivot）
    var pivotLevels: [Double] {
        let h = highs
        let l = lows
        if h.count < 20 { return [] }
        let n = min(60, h.count)
        let start = h.count - n
        var levels: [Double] = []
        var i = start + 2
        while i < h.count - 2 {
            if h[i] >= h[i-1] && h[i] >= h[i-2] && h[i] >= h[i+1] && h[i] >= h[i+2] {
                levels.append(h[i])
            }
            if l[i] <= l[i-1] && l[i] <= l[i-2] && l[i] <= l[i+1] && l[i] <= l[i+2] {
                levels.append(l[i])
            }
            i += 1
        }
        levels.sort()
        return levels
    }

    var resistance: Double? {
        let p = pivotLevels
        if p.isEmpty { return nil }
        var i = 0
        while i < p.count {
            if p[i] > lastPrice { return p[i] }
            i += 1
        }
        return nil
    }

    var support: Double? {
        let p = pivotLevels
        if p.isEmpty { return nil }
        var i = p.count - 1
        while i >= 0 {
            if p[i] < lastPrice { return p[i] }
            i -= 1
        }
        return nil
    }

    // 回撤分析
    var currentDrawdown: Double {
        let c = closes
        if c.isEmpty { return 0 }
        let peak = c.max() ?? 0
        if peak <= 0 { return 0 }
        return (peak - lastPrice) / peak * 100
    }

    var maxDrawdown: Double { btDDHold * 100 }

    // 信号统计（近120日各灯天数）
    var signalStats: (red: Int, yellow: Int, green: Int) {
        let c = closes
        if c.isEmpty { return (0, 0, 0) }
        let n = min(120, c.count)
        let start = c.count - n
        var r = 0
        var y = 0
        var g = 0
        var i = start
        while i < c.count {
            let sig = bandAt(i)
            if sig == .red { r += 1 }
            else if sig == .yellow { y += 1 }
            else if sig == .green { g += 1 }
            i += 1
        }
        return (r, y, g)
    }

    // 布林带位置（0=下轨, 1=上轨）
    var bollPosition: Double? {
        let u = bollUp
        let l = bollLow
        if u == nil || l == nil { return nil }
        if u! <= l! { return nil }
        return (lastPrice - l!) / (u! - l!)
    }

    // 量价关系
    var volumeState: String {
        if candles.count < 21 { return "—" }
        let q = quote
        if q == nil { return "—" }
        // 用换手率近似
        if q!.turnover > 8 { return "明显放量" }
        if q!.turnover < 2 { return "明显缩量" }
        return "量能正常"
    }

    // 综合评分（技术面打分 0-100）
    var techScore: Int {
        var score = 50
        // 均线
        if ma(20) != nil && ma(60) != nil {
            if lastPrice > ma(20)! { score += 10 }
            if lastPrice > ma(60)! { score += 10 }
            if ma(20)! > ma(60)! { score += 10 }
        }
        // MACD
        if macdDIF != nil && macdDEA != nil {
            if macdDIF! > macdDEA! { score += 10 }
        }
        // KDJ
        if let kd = kdj {
            if kd.k < 20 { score += 10 }
            if kd.k > 80 { score -= 10 }
        }
        // RSI
        if let r = rsi(14) {
            if r < 30 { score += 10 }
            if r > 70 { score -= 10 }
        }
        // 威廉
        if let w = williamsR {
            if w < -80 { score += 10 }
            if w > -20 { score -= 10 }
        }
        if score < 0 { score = 0 }
        if score > 100 { score = 100 }
        return score
    }

    var scoreText: String {
        let v = techScore
        if v >= 70 { return "强势" }
        if v >= 55 { return "偏强" }
        if v >= 45 { return "中性" }
        if v >= 30 { return "偏弱" }
        return "弱势"
    }

    var kValue: Double? {
        let v = kdj
        if v == nil { return nil }
        return v!.k
    }
    var dValue: Double? {
        let v = kdj
        if v == nil { return nil }
        return v!.d
    }
    var jValue: Double? {
        let v = kdj
        if v == nil { return nil }
        return v!.j
    }

    var redDays: Int { signalStats.red }
    var yellowDays: Int { signalStats.yellow }
    var greenDays: Int { signalStats.green }

    var bollPosText: String {
        let p = bollPosition
        if p == nil { return "—" }
        let v = p!
        if v >= 0.8 { return "贴近上轨 · 超买" }
        if v >= 0.5 { return "中轨上方" }
        if v >= 0.2 { return "中轨下方" }
        return "贴近下轨 · 超卖"
    }

    var scoreColor: Color {
        let v = techScore
        if v >= 70 { return Color(red: 0.0, green: 0.84, blue: 0.56) }
        if v >= 45 { return Color(red: 1.0, green: 0.69, blue: 0.13) }
        return Color(red: 1.0, green: 0.30, blue: 0.37)
    }

    // MARK: - 智能策略引擎：多策略回测 / 历史相似 / 蒙特卡洛 / 投票 / 凯利

    // ---- 通用指标（按索引，供回测使用）----

    func rsiAt(_ a: [Double], _ k: Int, _ idx: Int) -> Double? {
        return HLCore.rsiAt(a, k, idx)
    }

    func bollUpAt(_ a: [Double], _ k: Int, _ idx: Int) -> Double? {
        return HLCore.bollUpAt(a, k, idx)
    }

    func bollLowAt(_ a: [Double], _ k: Int, _ idx: Int) -> Double? {
        return HLCore.bollLowAt(a, k, idx)
    }

    // ---- 多策略回测 ----

    func strategyName(_ k: Int) -> String {
        if k == 0 { return "一直持有" }
        if k == 1 { return "红绿灯" }
        if k == 2 { return "双均线 MA5/20" }
        if k == 3 { return "RSI 超卖反弹" }
        if k == 4 { return "布林带回归" }
        if k == 5 { return "网格 每5%" }
        if k == 6 { return "定投 每20日" }
        return "—"
    }

    // 返回 [收益率倍数, 最大回撤%, 交易次数, 胜率%]
    func backtest(_ kind: Int) -> [Double] {
        return HLCore.backtest(closes, kind)
    }

    var btRows: [[Double]] {
        var out: [[Double]] = []
        var k = 0
        while k <= 6 {
            out.append(backtest(k))
            k += 1
        }
        return out
    }

    var bestStrategyIndex: Int {
        let rows = btRows
        var best = 0
        var bv = -999.0
        var i = 0
        while i < rows.count {
            let score = (rows[i][0] - 1) * 100 - rows[i][1] * 0.5
            if score > bv { bv = score; best = i }
            i += 1
        }
        return best
    }

    var bestStrategyName: String { strategyName(bestStrategyIndex) }

    // ---- 历史相似形态 ----

    func featureAt(_ idx: Int) -> [Double] {
        return HLCore.featureAt(closes, idx)
    }

    // 返回：样本数 / 平均20日涨幅% / 上涨概率% / 最好% / 最差%
    var similarStats: [Double] {
        let c = closes
        if c.count < 120 { return [0, 0, 0, 0, 0] }
        let cur = featureAt(c.count - 1)
        var dists: [[Double]] = []
        let horizon = 20
        var i = 80
        while i <= c.count - 1 - horizon {
            let f = featureAt(i)
            let d0 = f[0] - cur[0]
            let d1 = f[1] - cur[1]
            let d2 = (f[2] - cur[2]) * 0.3
            let d3 = (f[3] - cur[3]) * 0.3
            let d = sqrt(d0 * d0 + d1 * d1 + d2 * d2 + d3 * d3)
            let fut = (c[i + horizon] / c[i] - 1) * 100
            dists.append([d, fut])
            i += 5
        }
        if dists.isEmpty { return [0, 0, 0, 0, 0] }
        // 按距离排序（简单选择排序，取前 15）
        var sorted: [[Double]] = []
        var pool = dists
        while sorted.count < 15 && pool.isEmpty == false {
            var bi = 0
            var j = 1
            while j < pool.count {
                if pool[j][0] < pool[bi][0] { bi = j }
                j += 1
            }
            sorted.append(pool[bi])
            pool.remove(at: bi)
        }
        var sum = 0.0
        var up = 0
        var best = -999.0
        var worst = 999.0
        var winSum = 0.0
        var lossSum = 0.0
        var k = 0
        while k < sorted.count {
            let r = sorted[k][1]
            sum += r
            if r > 0 {
                up += 1
                winSum += r
            } else {
                lossSum += (-r)
            }
            if r > best { best = r }
            if r < worst { worst = r }
            k += 1
        }
        let n = Double(sorted.count)
        var avgWin = 0.0
        var avgLoss = 0.0
        if up > 0 { avgWin = winSum / Double(up) }
        if up < sorted.count { avgLoss = lossSum / Double(sorted.count - up) }
        // [样本数, 平均涨幅, 上涨概率, 最好, 最差, 上涨时平均涨, 下跌时平均跌]
        return [n, sum / n, Double(up) / n * 100, best, worst, avgWin, avgLoss]
    }

    var similarCount: Int { Int(similarStats[0]) }
    var similarAvgRet: Double { similarStats[1] }
    var similarWinRate: Double { similarStats[2] }
    var similarBest: Double { similarStats[3] }
    var similarWorst: Double { similarStats[4] }
    var similarAvgWin: Double { similarStats[5] }
    var similarAvgLoss: Double { similarStats[6] }

    var similarText: String {
        if similarCount == 0 { return "样本不足" }
        let a = similarAvgRet
        if a > 3 { return "历史相似形态后 20 日偏强" }
        if a < -3 { return "历史相似形态后 20 日偏弱" }
        return "历史相似形态后 20 日无明显倾向"
    }

    var similarColor: Color {
        if similarCount == 0 { return HLDim }
        if similarAvgRet > 0 { return Color(red: 0.0, green: 0.84, blue: 0.56) }
        return Color(red: 1.0, green: 0.30, blue: 0.37)
    }

    // ---- 蒙特卡洛情景推演 ----

    func gaussRandom() -> Double {
        var u = 0.0
        var v = 0.0
        var g = 0.0
        u = Double.random(in: 0.000001...0.999999)
        v = Double.random(in: 0.0...1.0)
        g = sqrt(-2.0 * log(u)) * cos(2.0 * Double.pi * v)
        return g
    }

    // 返回未来第 N 日的价格分位 [5%, 25%, 50%, 75%, 95%]
    func monteCarlo(_ days: Int) -> [Double] {
        let c = closes
        if c.count < 30 { return [0, 0, 0, 0, 0] }
        var rets: [Double] = []
        var i = c.count - 60
        if i < 1 { i = 1 }
        while i < c.count {
            rets.append(c[i] / c[i - 1] - 1)
            i += 1
        }
        if rets.isEmpty { return [0, 0, 0, 0, 0] }
        var sum = 0.0
        var k = 0
        while k < rets.count { sum += rets[k]; k += 1 }
        let mu = sum / Double(rets.count)
        var vs = 0.0
        k = 0
        while k < rets.count {
            let d = rets[k] - mu
            vs += d * d
            k += 1
        }
        let sd = sqrt(vs / Double(rets.count))
        let p0 = lastPrice
        if p0 <= 0 { return [0, 0, 0, 0, 0] }

        var finals: [Double] = []
        var sim = 0
        while sim < 800 {
            var p = p0
            var d = 0
            while d < days {
                let r = mu + sd * gaussRandom()
                p = p * (1 + r)
                if p < 0 { p = 0 }
                d += 1
            }
            finals.append(p)
            sim += 1
        }
        finals.sort()
        let n = finals.count
        func q(_ f: Double) -> Double {
            var idx = Int(f * Double(n - 1))
            if idx < 0 { idx = 0 }
            if idx >= n { idx = n - 1 }
            return finals[idx]
        }
        return [q(0.05), q(0.25), q(0.50), q(0.75), q(0.95)]
    }

    var mc20: [Double] { monteCarlo(20) }
    var mc60: [Double] { monteCarlo(60) }

    var mc20Text: String {
        let m = mc20
        if m[2] <= 0 { return "—" }
        return hfmt(m[1], 3) + " ~ " + hfmt(m[3], 3) + "（中位 " + hfmt(m[2], 3) + "）"
    }

    var mcUpProb: Double {
        let m = mc20
        if m[2] <= 0 { return 0 }
        return 50.0
    }

    // ---- 多指标投票 ----

    // 返回 [多头票数, 空头票数, 总分(-8~8)]
    var voteResult: [Double] {
        var bull = 0
        var bear = 0

        if let m20 = ma(20), m20 > 0 {
            if lastPrice > m20 { bull += 1 } else { bear += 1 }
        }
        if let m60 = ma(60), m60 > 0 {
            if lastPrice > m60 { bull += 1 } else { bear += 1 }
        }
        if let a = ma(20), let b = ma(60) {
            if a > b { bull += 1 } else { bear += 1 }
        }
        if let d = macdDIF, let e = macdDEA {
            if d > e { bull += 1 } else { bear += 1 }
        }
        if let kd = kdj {
            if kd.k > kd.d { bull += 1 } else { bear += 1 }
        }
        if let r = rsi(14) {
            if r < 35 { bull += 1 }
            else if r > 65 { bear += 1 }
        }
        if let w = williamsR {
            if w < -75 { bull += 1 }
            else if w > -25 { bear += 1 }
        }
        if let p = bollPosition {
            if p < 0.25 { bull += 1 }
            else if p > 0.75 { bear += 1 }
        }
        return [Double(bull), Double(bear), Double(bull - bear)]
    }

    var voteBull: Int { Int(voteResult[0]) }
    var voteBear: Int { Int(voteResult[1]) }
    var voteScore: Int { Int(voteResult[2]) }

    var voteText: String {
        let v = voteScore
        if v >= 4 { return "多头共振" }
        if v >= 2 { return "偏多" }
        if v <= -4 { return "空头共振" }
        if v <= -2 { return "偏空" }
        return "多空分歧"
    }

    var voteColor: Color {
        let v = voteScore
        if v >= 2 { return Color(red: 0.0, green: 0.84, blue: 0.56) }
        if v <= -2 { return Color(red: 1.0, green: 0.30, blue: 0.37) }
        return Color(red: 1.0, green: 0.69, blue: 0.13)
    }

    // ---- 凯利公式仓位 ----

    // 用历史相似形态的胜率 + 平均盈亏比
    var kellyRaw: Double {
        if similarCount < 5 { return 0 }
        let wr = similarWinRate / 100.0
        let avgWin = similarAvgWin
        let avgLoss = similarAvgLoss
        if avgLoss <= 0 || avgWin <= 0 { return 0 }
        let b = avgWin / avgLoss
        let k = (wr * b - (1 - wr)) / b
        if k < 0 { return 0 }
        if k > 1 { return 1 }
        return k
    }

    // 凯利为 0 时的解释文字
    var kellyReason: String {
        if similarCount < 5 { return "样本不足，无法估算" }
        if kellyRaw <= 0 {
            return "按历史相似形态估算，期望为负 —— 此时不加仓才是正解"
        }
        return "胜率 " + hfmt(similarWinRate, 0) + "% · 盈亏比 " + hfmt(similarAvgWin / max(similarAvgLoss, 0.01), 2)
    }

    // 分数凯利（1/4），实战更稳
    var kellySafe: Double { kellyRaw * 0.25 }

    var kellyText: String {
        if similarCount < 5 { return "样本不足，不建议据此加仓" }
        let pct = kellySafe * 100
        if pct < 5 { return "建议仓位 <5%（几乎不值得下手）" }
        return "建议仓位约 " + hfmt(pct, 0) + "%（分数凯利 1/4）"
    }

    var adviceText: String {
        let sig = signal
        let v = voteScore
        if sig == .red {
            if v <= -4 { return "灯红 + 指标共振看空：守住不动，不接下跌的刀" }
            if v >= 2 { return "灯红但指标偏多：别急着加，等灯真正转黄再说" }
            return "灯红：规则优先，不加仓"
        }
        if sig == .yellow {
            if v >= 4 { return "灯黄 + 指标共振：可小仓试探，设好止损" }
            return "灯黄：观望为主，仓位不超过三成"
        }
        if sig == .green {
            if v >= 4 { return "灯绿 + 指标共振：可按计划分批执行" }
            if v <= -2 { return "灯绿但指标转弱：警惕假突破，减半执行" }
            return "灯绿：按计划执行，别追高"
        }
        return "数据不足，先等待"
    }


    // MARK: - 顶级风险引擎：VaR / CVaR / 风险调整收益 / 波动率锥 / EWMA

    // 日收益率序列
    var rets: [Double] {
        let c = closes
        if c.count < 2 { return [] }
        var out: [Double] = []
        var i = 1
        while i < c.count {
            out.append(c[i] / c[i - 1] - 1)
            i += 1
        }
        return out
    }

    var retMean: Double {
        let r = rets
        if r.isEmpty { return 0 }
        var s = 0.0
        var i = 0
        while i < r.count { s += r[i]; i += 1 }
        return s / Double(r.count)
    }

    var retSD: Double {
        let r = rets
        if r.count < 2 { return 0 }
        let m = retMean
        var v = 0.0
        var i = 0
        while i < r.count {
            let d = r[i] - m
            v += d * d
            i += 1
        }
        return sqrt(v / Double(r.count - 1))
    }

    // 历史模拟法 VaR（负数表示亏损）
    func varHist(_ p: Double) -> Double {
        return HLCore.varHist(rets, p)
    }

    // CVaR / 期望损失：尾部平均
    func cvarHist(_ p: Double) -> Double {
        return HLCore.cvarHist(rets, p)
    }

    // 参数法 VaR（正态假设）
    func varParam(_ p: Double) -> Double {
        return HLCore.varParam(rets, p)
    }

    var var95Text: String {
        let h = varHist(0.95)
        let pa = varParam(0.95)
        return "历史 " + hfmt(h * 100, 2) + "% · 正态 " + hfmt(pa * 100, 2) + "%"
    }

    var var99Text: String {
        let h = varHist(0.99)
        let pa = varParam(0.99)
        return "历史 " + hfmt(h * 100, 2) + "% · 正态 " + hfmt(pa * 100, 2) + "%"
    }

    var cvar95Text: String { hfmt(cvarHist(0.95) * 100, 2) + "%" }
    var cvar99Text: String { hfmt(cvarHist(0.99) * 100, 2) + "%" }

    // 换算成钱（按持仓份数）
    // 当前标的的持仓份数（从持久化读取，计算页写入）
    var qtyGlobal: Double {
        let d = UserDefaults.standard
        let q = d.double(forKey: "hl_pos_" + curCode + "_qty")
        return q > 0 ? q : 0
    }

    var costGlobal: Double {
        let d = UserDefaults.standard
        let c = d.double(forKey: "hl_pos_" + curCode + "_cost")
        return c > 0 ? c : 0
    }

    var var95Money: Double { varHist(0.95) * lastPrice * qtyGlobal }
    var cvar95Money: Double { cvarHist(0.95) * lastPrice * qtyGlobal }

    // 风险调整收益
    var annRet: Double {
        let c = closes
        if c.count < 30 || c[0] <= 0 { return 0 }
        let years = Double(c.count) / 252.0
        if years <= 0 { return 0 }
        return pow(c[c.count - 1] / c[0], 1.0 / years) - 1
    }

    var annVol: Double { retSD * sqrt(252.0) }

    var sharpe: Double {
        let v = annVol
        if v <= 0 { return 0 }
        return (annRet - 0.02) / v
    }

    var sortino: Double {
        let r = rets
        if r.isEmpty { return 0 }
        var v = 0.0
        var cnt = 0
        var i = 0
        while i < r.count {
            if r[i] < 0 { v += r[i] * r[i]; cnt += 1 }
            i += 1
        }
        if cnt == 0 { return 0 }
        let dv = sqrt(v / Double(cnt)) * sqrt(252.0)
        if dv <= 0 { return 0 }
        return (annRet - 0.02) / dv
    }

    var maxDrawdownPct: Double {
        let c = closes
        if c.isEmpty { return 0 }
        var peak = c[0]
        var dd = 0.0
        var i = 0
        while i < c.count {
            if c[i] > peak { peak = c[i] }
            let d = (peak - c[i]) / peak
            if d > dd { dd = d }
            i += 1
        }
        return dd * 100
    }

    // 最长水下天数
    var maxUnderwater: Int {
        let c = closes
        if c.isEmpty { return 0 }
        var peak = c[0]
        var cur = 0
        var mx = 0
        var i = 0
        while i < c.count {
            if c[i] >= peak { peak = c[i]; cur = 0 }
            else { cur += 1; if cur > mx { mx = cur } }
            i += 1
        }
        return mx
    }

    var calmar: Double {
        let dd = maxDrawdownPct / 100.0
        if dd <= 0 { return 0 }
        return annRet / dd
    }

    var sharpeText: String {
        let v = sharpe
        if v >= 1 { return "优秀" }
        if v >= 0.5 { return "良好" }
        if v >= 0 { return "偏弱" }
        return "亏损"
    }

    var sharpeColor: Color {
        let v = sharpe
        if v >= 0.5 { return Color(red: 0.0, green: 0.84, blue: 0.56) }
        if v >= 0 { return Color(red: 1.0, green: 0.69, blue: 0.13) }
        return Color(red: 1.0, green: 0.30, blue: 0.37)
    }

    // 波动率锥：不同持有期的年化波动
    func volCone(_ k: Int) -> Double? {
        return HLCore.volCone(rets, k)
    }

    var cone5: Double { volCone(5) ?? 0 }
    var cone10: Double { volCone(10) ?? 0 }
    var cone20: Double { volCone(20) ?? 0 }
    var cone60: Double { volCone(60) ?? 0 }

    var coneText: String {
        if cone5 <= 0 { return "—" }
        if cone5 > cone60 * 1.2 { return "短期波动高于长期 · 近期震荡加剧" }
        if cone5 < cone60 * 0.8 { return "短期波动低于长期 · 近期趋于平静" }
        return "各周期波动接近"
    }

    // EWMA 波动率预测（RiskMetrics λ=0.94）
    var ewmaVol: Double {
        let r = rets
        if r.isEmpty { return 0 }
        var v = r[0] * r[0]
        var i = 1
        while i < r.count {
            v = 0.94 * v + 0.06 * r[i] * r[i]
            i += 1
        }
        return sqrt(v * 252.0)
    }

    var volTrendText: String {
        let e = ewmaVol
        let a = annVol
        if a <= 0 { return "—" }
        if e > a * 1.15 { return "波动正在放大" }
        if e < a * 0.85 { return "波动正在收敛" }
        return "波动平稳"
    }

    var volTrendColor: Color {
        let e = ewmaVol
        let a = annVol
        if a <= 0 { return HLDim }
        if e > a * 1.15 { return Color(red: 1.0, green: 0.30, blue: 0.37) }
        if e < a * 0.85 { return Color(red: 0.0, green: 0.84, blue: 0.56) }
        return HLDim
    }

    // MARK: - 市场结构识别

    // 赫斯特指数：>0.55 趋势延续，<0.45 均值回归
    var hurst: Double? {
        let c = closes
        if c.count < 60 { return nil }
        var lx: [Double] = []
        var ly: [Double] = []
        var lag = 8
        while lag <= min(60, c.count / 4) {
            var diffs: [Double] = []
            var i = 0
            while i + lag < c.count {
                diffs.append(c[i + lag] - c[i])
                i += 1
            }
            if diffs.count < 5 { lag += 1; continue }
            var m = 0.0
            var k = 0
            while k < diffs.count { m += diffs[k]; k += 1 }
            m /= Double(diffs.count)
            var v = 0.0
            k = 0
            while k < diffs.count {
                let d = diffs[k] - m
                v += d * d
                k += 1
            }
            let sd = sqrt(v / Double(diffs.count))
            if sd > 0 {
                lx.append(log(Double(lag)))
                ly.append(log(sd))
            }
            lag += 1
        }
        if lx.count < 4 { return nil }
        var mx = 0.0
        var my = 0.0
        var t = 0
        while t < lx.count { mx += lx[t]; my += ly[t]; t += 1 }
        mx /= Double(lx.count)
        my /= Double(ly.count)
        var num = 0.0
        var den = 0.0
        t = 0
        while t < lx.count {
            num += (lx[t] - mx) * (ly[t] - my)
            den += (lx[t] - mx) * (lx[t] - mx)
            t += 1
        }
        if den <= 0 { return nil }
        return num / den
    }

    var hurstText: String {
        let v = hurst
        if v == nil { return "—" }
        let x = v!
        if x > 0.55 { return "趋势延续性强（顺势更有效）" }
        if x < 0.45 { return "均值回归倾向（高抛低吸更有效）" }
        return "接近随机游走"
    }

    var hurstColor: Color {
        let v = hurst
        if v == nil { return HLDim }
        if v! > 0.55 { return Color(red: 1.0, green: 0.69, blue: 0.13) }
        if v! < 0.45 { return Color(red: 0.30, green: 0.62, blue: 1.0) }
        return HLDim
    }

    // 波动率制度：近20日振幅 / 历史平均
    var volRegime: Double {
        let r = rets
        if r.count < 40 { return 1 }
        var recent = 0.0
        var i = r.count - 20
        if i < 0 { i = 0 }
        var cnt = 0
        while i < r.count { recent += abs(r[i]); cnt += 1; i += 1 }
        if cnt == 0 { return 1 }
        recent /= Double(cnt)
        var all = 0.0
        i = 0
        while i < r.count { all += abs(r[i]); i += 1 }
        all /= Double(r.count)
        if all <= 0 { return 1 }
        return recent / all
    }

    var volRegimeText: String {
        let v = volRegime
        if v > 1.3 { return "高波动制度（止损应放宽）" }
        if v < 0.7 { return "低波动制度（警惕变盘）" }
        return "正常波动制度"
    }

    var volRegimeColor: Color {
        let v = volRegime
        if v > 1.3 { return Color(red: 1.0, green: 0.30, blue: 0.37) }
        if v < 0.7 { return Color(red: 0.30, green: 0.62, blue: 1.0) }
        return HLDim
    }

    // 动态止损：基于近期波动的 σ 倍数
    var sdRecent: Double {
        let r = rets
        if r.count < 20 { return 0 }
        var s = 0.0
        var i = r.count - 20
        while i < r.count { s += r[i]; i += 1 }
        let m = s / 20.0
        var v = 0.0
        i = r.count - 20
        while i < r.count {
            let d = r[i] - m
            v += d * d
            i += 1
        }
        return sqrt(v / 19.0)
    }

    var stop15: Double { lastPrice * (1 - sdRecent * 1.5) }
    var stop20: Double { lastPrice * (1 - sdRecent * 2.0) }
    var stop30: Double { lastPrice * (1 - sdRecent * 3.0) }

    // 固定止损相当于几个 σ
    var stopSigma: Double {
        let sl = stopLoss
        if sl == nil { return 0 }
        if sdRecent <= 0 { return 0 }
        return abs((sl! / lastPrice - 1)) / sdRecent
    }

    var stopSigmaText: String {
        let v = stopSigma
        if v <= 0 { return "—" }
        if v < 1.5 { return "仅 " + hfmt(v, 2) + "σ · 太紧，容易被扫" }
        if v > 4 { return hfmt(v, 2) + "σ · 太宽，失去保护意义" }
        return hfmt(v, 2) + "σ · 合理区间"
    }

    var stopSigmaColor: Color {
        let v = stopSigma
        if v <= 0 { return HLDim }
        if v < 1.5 || v > 4 { return Color(red: 1.0, green: 0.30, blue: 0.37) }
        return Color(red: 0.0, green: 0.84, blue: 0.56)
    }

    // MARK: - 自适应参数寻优

    var fastPeriods: [Int] { [5, 10, 15, 20] }
    var slowPeriods: [Int] { [30, 40, 60, 80] }

    // 返回 [fast, slow, 收益%, 回撤%, 评分]
    func gridAt(_ row: Int) -> [Double] {
        return HLCore.gridAt(closes, row)
    }

    var gridBest: Int {
        var best = 0
        var bs = -9999.0
        var i = 0
        while i < 16 {
            let r = gridAt(i)
            if r[4] > bs { bs = r[4]; best = i }
            i += 1
        }
        return best
    }

    var gridBestText: String {
        let r = gridAt(gridBest)
        return "MA" + String(Int(r[0])) + "/" + String(Int(r[1]))
    }

    // 默认 MA20/60 的排名（1-based）
    var gridDefaultRank: Int {
        let d = gridAt(2 * 4 + 2)  // fast=20(index2), slow=60(index2)
        var rank = 1
        var i = 0
        while i < 16 {
            if gridAt(i)[4] > d[4] { rank += 1 }
            i += 1
        }
        return rank
    }

    var gridDefaultScore: Double { gridAt(2 * 4 + 2)[4] }
    var gridBestScore: Double { gridAt(gridBest)[4] }

    var gridAdvice: String {
        let r = gridDefaultRank
        if r <= 4 { return "默认参数表现靠前（第" + String(r) + "名），不必改" }
        if r >= 13 { return "默认参数偏弱（第" + String(r) + "名），但换参数可能是过拟合" }
        return "默认参数中等（第" + String(r) + "名）"
    }

    // MARK: - 信号质量审计（红黄绿各自历史表现）

    // 返回 [样本数, 平均涨幅%, 上涨率%]
    func signalQuality(_ kind: Int) -> [Double] {
        return HLCore.signalQuality(closes, kind)
    }

    var redQ: [Double] { signalQuality(0) }
    var yellowQ: [Double] { signalQuality(1) }
    var greenQ: [Double] { signalQuality(2) }

    var signalAuditText: String {
        let r = redQ
        let g = greenQ
        if r[0] < 5 || g[0] < 5 { return "样本不足，无法审计" }
        if g[1] < r[1] { return "⚠ 绿灯样本的历史表现反而更差 —— 说明本策略在下跌中追高" }
        if r[1] < 0 && g[1] > 0 { return "红灯避开下跌、绿灯捕捉上涨，逻辑成立" }
        return "信号区分度有限"
    }

    var signalAuditColor: Color {
        let g = greenQ
        let r = redQ
        if g[0] >= 5 && g[1] < r[1] { return Color(red: 1.0, green: 0.30, blue: 0.37) }
        return HLDim
    }

}

// MARK: - 格式化

func hfmt(_ v: Double?, _ d: Int) -> String {
    if v == nil { return "—" }
    let x = v!
    if x.isFinite == false { return "—" }
    return String(format: "%.\(d)f", x)
}

func hfmtPct(_ v: Double?) -> String {
    if v == nil { return "—" }
    let x = v!
    if x.isFinite == false { return "—" }
    if x >= 0 { return "+" + String(format: "%.2f%%", x) }
    return String(format: "%.2f%%", x)
}

func hcolor(_ v: Double?) -> Color {
    if v == nil { return Color(white: 0.55) }
    if v! >= 0 { return Color(red: 0.0, green: 0.84, blue: 0.56) }
    return Color(red: 1.0, green: 0.30, blue: 0.37)
}

let HLText = Color(red: 0.90, green: 0.91, blue: 0.93)
let HLDim = Color(white: 0.55)
let HLDim2 = Color(white: 0.40)
let HLCard = Color(red: 0.078, green: 0.094, blue: 0.125)
let HLAccent = Color(red: 0.30, green: 0.62, blue: 1.0)
let HLEditingHint = true

func hrow(_ label: String, _ value: String, _ color: Color) -> some View {
    HStack(alignment: .firstTextBaseline) {
        Text(label).font(.system(size: 12.5)).foregroundColor(HLDim)
        Spacer()
        Text(value).font(.system(size: 13, weight: .semibold)).foregroundColor(color)
    }
    .padding(.vertical, 6)
}

// MARK: - 界面

struct HLSignalView: View {
    @EnvironmentObject var m: HLModel

    var plotW: CGFloat { UIScreen.main.bounds.width - 46 }

    func pathFor(_ data: [Double], _ w: CGFloat, _ h: CGFloat) -> Path {
        Path { p in
            if data.count == 0 { return }
            let lo = data.min() ?? 0
            let hi = data.max() ?? 1
            let range = hi - lo
            if range <= 0 { return }
            var i = 0
            while i < data.count {
                let x = CGFloat(i) / CGFloat(max(data.count - 1, 1)) * w
                let y = (1 - CGFloat((data[i] - lo) / range)) * h
                if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                else { p.addLine(to: CGPoint(x: x, y: y)) }
                i += 1
            }
        }
    }

    var intraCloses: [Double] { m.intraday.map { $0.close } }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // 数据源状态条
                HLSourceBar()

                // 灯
                VStack(spacing: 9) {
                    HStack(spacing: 13) {
                        Circle()
                            .fill(m.signal.color)
                            .frame(width: 54, height: 54)
                            .overlay(
                                Text(m.signal.title)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                            )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(m.signal.title + "灯")
                                .font(.system(size: 25, weight: .bold))
                                .foregroundColor(HLText)
                            Text(m.signal.desc)
                                .font(.system(size: 12))
                                .foregroundColor(HLDim)
                        }
                        Spacer()
                    }
                    Text(m.signal.action)
                        .font(.system(size: 12))
                        .foregroundColor(m.signal.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(m.signal.color.opacity(0.12)))
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                // 实时盘口
                VStack(spacing: 6) {
                    Text("实时盘口")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    hrow("现价", hfmt(m.lastPrice, 3), HLText)
                    hrow("涨跌幅", hfmtPct(m.quote?.changePct), hcolor(m.quote?.changePct))
                    hrow("涨跌额", hfmt(m.quote?.change, 4), hcolor(m.quote?.change))
                    hrow("今开", hfmt(m.quote?.open, 3), HLText)
                    hrow("最高", hfmt(m.quote?.high, 3), Color(red: 1.0, green: 0.30, blue: 0.37))
                    hrow("最低", hfmt(m.quote?.low, 3), Color(red: 0.0, green: 0.84, blue: 0.56))
                    hrow("昨收", hfmt(m.quote?.preClose, 3), HLDim)
                    hrow("成交量", m.quote?.volumeText ?? "—", HLDim)
                    hrow("成交额", m.quote?.amountText ?? "—", HLDim)
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                // 分时
                VStack(spacing: 8) {
                    Text("分时走势 · 5分钟")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if intraCloses.count < 2 {
                        Text("非交易时段或暂无分时数据")
                            .font(.system(size: 11))
                            .foregroundColor(HLDim2)
                            .frame(height: 110)
                    } else {
                        pathFor(intraCloses, plotW, 110)
                            .stroke(m.signal.color, lineWidth: 1.6)
                            .frame(width: plotW, height: 110)
                        HStack {
                            Text(hfmt(intraCloses.min(), 3))
                                .font(.system(size: 10)).foregroundColor(HLDim2)
                            Spacer()
                            Text(String(intraCloses.count) + " 个5分钟点")
                                .font(.system(size: 10)).foregroundColor(HLDim2)
                            Spacer()
                            Text(hfmt(intraCloses.max(), 3))
                                .font(.system(size: 10)).foregroundColor(HLDim2)
                        }
                        .frame(width: plotW)
                    }
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                // 均线
                VStack(spacing: 6) {
                    Text("均线 · 由历史K线实时计算")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    hrow("MA5", hfmt(m.ma(5), 4), HLText)
                    hrow("MA10", hfmt(m.ma(10), 4), HLText)
                    hrow("MA20 · 短期生命线", hfmt(m.ma(20), 4), HLText)
                    hrow("MA60 · 中期生命线", hfmt(m.ma(60), 4), HLText)
                    hrow("MA20 vs MA60", m.maGapText, m.maGapColor)
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                // 门槛
                VStack(spacing: 6) {
                    Text("关键价位 · 随行情动态重算")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    hrow("🟡 变黄需到", hfmt(m.nextYellow, 4), Color(red: 1.0, green: 0.69, blue: 0.13))
                    hrow("🟢 变绿需到", hfmt(m.nextGreen, 4), Color(red: 0.0, green: 0.84, blue: 0.56))
                    hrow("🔴 止损参考（现价-2×ATR）", hfmt(m.stopLoss, 3), Color(red: 1.0, green: 0.30, blue: 0.37))
                    hrow("距变黄还差", hfmt(m.gapToYellow, 4), HLDim)
                    hrow("近一年低", hfmt(m.periodLow, 3), HLDim)
                    hrow("近一年高", hfmt(m.periodHigh, 3), HLDim)
                    hrow("年内分位", hfmt(m.percentile, 1) + "%", HLDim)
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                // 市场情绪
                VStack(spacing: 6) {
                    Text("市场情绪")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    hrow("换手率", m.quote == nil ? "—" : hfmt(m.quote!.turnover, 2) + "%", HLDim)
                    hrow("量比", m.quote == nil ? "—" : hfmt(m.quote!.volRatio, 2), HLDim)
                    hrow("振幅", m.quote == nil ? "—" : hfmt(m.quote!.amplitude, 2) + "%", HLDim)
                    hrow("ATR(14)", hfmt(m.atr(), 4), HLDim)
                    hrow("20日年化波动率", hfmt(m.annualVol, 1) + "%", HLDim)
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                Text("所有数据均为实时网络请求，无内嵌数据。数据来自第三方公开接口，可能延迟或失效。\n本工具仅为纪律辅助，不构成投资建议。")
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
                    .padding(.top, 4)
            }
            .padding(10)
        }
        .background(Color(red: 0.043, green: 0.051, blue: 0.071))
    }
}

struct HLSourceBar: View {
    @EnvironmentObject var m: HLModel
    @State var tick: Int = 0
    @State var justRefreshed: Bool = false

    let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var staleMinutes: Int {
        let sec = Date().timeIntervalSince(m.lastUpdate)
        return Int(sec / 60)
    }

    // 新鲜度按「数据源自己的时间戳」判断，而不是上次请求时间
    var ageSec: Double { HLDataAgeSeconds(m.dataTime) }
    var isFresh: Bool { ageSec >= 0 && ageSec < 300 }
    var ageText: String {
        if m.dataTime.isEmpty { return "未连接" }
        return HLDataAgeText(m.dataTime)
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(m.dataSource.isEmpty ? HLDim2 : (isFresh ? Color(red: 0.0, green: 0.84, blue: 0.56) : Color(red: 1.0, green: 0.69, blue: 0.13)))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.dataSource.isEmpty ? "未连接" : (m.dataSource + " · " + m.dataTime))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(HLText)
                Text(ageText)
                    .font(.system(size: 9.5))
                    .foregroundColor(isFresh ? HLDim2 : Color(red: 1.0, green: 0.69, blue: 0.13))
                    .id(tick)
            }
            Spacer()
            Button {
                m.loadAll()
                m.refreshWatch()
                m.loadBrief()
                justRefreshed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    justRefreshed = false
                }
            } label: {
                Text(justRefreshed ? "已请求" : "刷新")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(justRefreshed ? Color(red: 0.0, green: 0.84, blue: 0.56) : HLAccent))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(HLCard))
        .onReceive(timer) { _ in
            tick += 1
            if HLSourceBar.isTradingTime() {
                m.loadAll()
            }
        }
    }

    static func isTradingTime() -> Bool {
        let cal = Calendar.current
        let now = Date()
        let wd = cal.component(.weekday, from: now)
        let h = cal.component(.hour, from: now)
        let mm = cal.component(.minute, from: now)
        let t = h * 60 + mm
        if wd < 2 || wd > 6 { return false }
        if t >= 570 && t < 690 { return true }
        if t >= 780 && t < 900 { return true }
        return false
    }
}

struct HLWatchView: View {
    @EnvironmentObject var m: HLModel
    @State var input: String = ""
    @State var msg: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                VStack(spacing: 6) {
                    Text("我的自选")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(m.watch, id: \.code) { w in
                        HStack(spacing: 9) {
                            Circle().fill(w.code == m.curCode ? HLAccent : HLDim2)
                                .frame(width: 9, height: 9)
                            Button {
                                m.select(w.code)
                                m.loadAll()
                            } label: {
                                HStack {
                                    Text(w.name).font(.system(size: 13)).foregroundColor(HLText)
                                    Spacer()
                                    Text(hfmt(w.weight, 3)).font(.system(size: 13)).foregroundColor(HLText)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            Button {
                                m.remove(code: w.code)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(Color(red: 1.0, green: 0.30, blue: 0.37).opacity(0.8))
                                    .font(.system(size: 17))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.vertical, 5)
                    }
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                VStack(spacing: 8) {
                    Text("添加标的")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        TextField("6位代码，如 513770", text: $input)
                            .keyboardType(.numbersAndPunctuation)
                            .font(.system(size: 14))
                            .padding(9)
                            .background(RoundedRectangle(cornerRadius: 9).fill(HLCard))
                            .foregroundColor(HLText)
                        Button {
                            addItem()
                        } label: {
                            Text("添加")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(RoundedRectangle(cornerRadius: 9).fill(HLAccent))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    if msg.isEmpty == false {
                        Text(msg).font(.system(size: 11)).foregroundColor(HLDim)
                    }
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                VStack(spacing: 8) {
                    hrow("当前标的", m.curCode, HLDim)
                    hrow("历史天数", String(m.candles.count) + " 天", HLDim)
                    hrow("数据", m.note, HLDim)
                    Button {
                        m.loadAll()
                        m.refreshWatch()
                    } label: {
                        Text("刷新数据")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 9).fill(HLAccent))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))
                .contentShape(Rectangle())
                .onTapGesture { HLEndEditing() }
            }
            .padding(10)
            .contentShape(Rectangle())
            .onTapGesture { HLEndEditing() }
        }
        .background(Color(red: 0.043, green: 0.051, blue: 0.071))
    }

    func addItem() {
        let t = input.trimmingCharacters(in: .whitespaces)
        if t.count != 6 {
            msg = "请输入 6 位数字"
            return
        }
        var code = ""
        if let f = t.first {
            if f == "6" || f == "5" || f == "9" { code = "sh" + t }
            else if f == "4" || f == "8" { code = "bj" + t }
            else { code = "sz" + t }
        }
        m.add(code: code)
        msg = "已尝试添加 " + code
        input = ""
    }
}

// MARK: - 简报页

struct HLAnomalyCard: View {
    @EnvironmentObject var m: HLModel

    var agg: (level: Int, score: Int, count: Int) { m.anomalyAgg }
    var items: [HLAnomalyItem] { m.anomalies }

    var title: String { HLCore.anomalyTitle(agg.level) }
    var advice: String { HLCore.anomalyAdvice(items) }

    var levelColor: Color {
        if agg.level >= 2 { return Color(red: 1.0, green: 0.30, blue: 0.37) }
        if agg.level == 1 { return Color(red: 1.0, green: 0.69, blue: 0.13) }
        return Color(red: 0.0, green: 0.84, blue: 0.56)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("异动雷达")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(HLDim)
                Spacer()
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(levelColor))
            }

            if items.isEmpty {
                Text("历史数据不足，无法扫描")
                    .font(.system(size: 11))
                    .foregroundColor(HLDim2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(0..<items.count, id: \.self) { i in
                    anomalyRow(items[i])
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("应对")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(levelColor)
                    Text(advice)
                        .font(.system(size: 10.5))
                        .foregroundColor(HLText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 9).fill(levelColor.opacity(0.12)))

                Text("异动检测只识别「已经发生的不寻常」，不预测涨跌。历史回测：近60日约5%的交易日会触发。")
                    .font(.system(size: 9.5))
                    .foregroundColor(HLDim2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))
    }

    func anomalyRow(_ it: HLAnomalyItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(it.level >= 2 ? Color(red: 1.0, green: 0.30, blue: 0.37)
                      : (it.level == 1 ? Color(red: 1.0, green: 0.69, blue: 0.13)
                         : Color(red: 0.0, green: 0.84, blue: 0.56)))
                .frame(width: 6, height: 6)
                .padding(.top, 5)
            Text(it.name)
                .font(.system(size: 11))
                .foregroundColor(HLDim)
                .frame(width: 68, alignment: .leading)
            Text(it.value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(it.level >= 1 ? HLText : HLDim2)
            Spacer()
        }
    }
}

struct HLBriefView: View {
    @EnvironmentObject var m: HLModel

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HLSourceBar()

                // 异动雷达
                HLAnomalyCard()

                // 今日预案
                VStack(spacing: 6) {
                    Text("今日预案")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    hrow("🔴 若跌破 " + hfmt(m.stopLoss, 3), "无条件减仓", Color(red: 1.0, green: 0.30, blue: 0.37))
                    hrow("🟡 若涨到 " + hfmt(m.nextYellow, 4) + " 且站稳", "灯转黄，可小仓", Color(red: 1.0, green: 0.69, blue: 0.13))
                    hrow("🟢 若涨到 " + hfmt(m.nextGreen, 4), "灯转绿，可正常操作", Color(red: 0.0, green: 0.84, blue: 0.56))
                    hrow("⚪ 其余情况", "不动，等信号", HLDim)
                    Text("本页不做涨跌预测。它只把「涨到哪该做什么、跌到哪该做什么」提前定下来，避免临盘情绪化决策。")
                        .font(.system(size: 10))
                        .foregroundColor(HLDim2)
                        .padding(.top, 4)
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                // 隔夜外围
                VStack(spacing: 4) {
                    Text("隔夜外围")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(HLGlobalIdx, id: \.code) { p in
                        HLBriefRow(preset: p, quote: m.globalQuotes[p.code])
                    }
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                // ADR
                VStack(spacing: 4) {
                    Text("中概股 ADR · 隔夜")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(HLAdrs, id: \.code) { p in
                        HLBriefRow(preset: p, quote: m.adrQuotes[p.code])
                    }
                    hrow("加权估算", hfmtPct(m.adrEstimate), hcolor(m.adrEstimate))
                    hrow("覆盖权重", hfmt(m.adrCoverage, 1) + "%", HLDim)
                    Text("仅覆盖部分中概股权重，未含汇率与溢价折价。只作方向参考，不是开盘价预测。")
                        .font(.system(size: 10))
                        .foregroundColor(HLDim2)
                        .padding(.top, 4)
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                // 成分股
                VStack(spacing: 4) {
                    Text("成分股体温计 · 港股互联网")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(HLHoldings, id: \.code) { p in
                        HLBriefRow(preset: p, quote: m.holdQuotes[p.code])
                    }
                    hrow("加权方向", hfmtPct(m.holdEstimate), hcolor(m.holdEstimate))
                    hrow("覆盖权重", hfmt(m.holdCoverage, 1) + "%", HLDim)
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                // 自选一览
                VStack(spacing: 4) {
                    Text("自选状态一览")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(m.watch, id: \.code) { w in
                        HStack {
                            Text(w.name).font(.system(size: 12.5)).foregroundColor(HLText)
                            Spacer()
                            Text(hfmt(w.weight, 3)).font(.system(size: 12.5)).foregroundColor(HLText)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                Text("外围、ADR、成分股均为实时网络请求（腾讯主源 / 新浪备源）。\n标注「—」表示该项当前未取到数据，不代表为零。\n数据来自公开接口，非官方授权，可能延迟或失效。\n本工具仅为纪律辅助，不构成投资建议。")
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
            }
            .padding(10)
        }
        .background(Color(red: 0.043, green: 0.051, blue: 0.071))
        .onAppear { m.loadBrief() }
    }
}

struct HLBriefRow: View {
    let preset: HLPreset
    let quote: HLQuote?

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(preset.name).font(.system(size: 12.5)).foregroundColor(HLText)
                if preset.note.isEmpty == false {
                    Text(preset.note).font(.system(size: 9.5)).foregroundColor(HLDim2)
                }
            }
            Spacer()
            if quote == nil {
                Text("—").font(.system(size: 12)).foregroundColor(HLDim2)
            } else {
                Text(hfmt(quote!.price, quote!.price < 100 ? 3 : 2))
                    .font(.system(size: 12.5))
                    .foregroundColor(HLText)
                Text(hfmtPct(quote!.changePct))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(hcolor(quote!.changePct))
                    .frame(width: 66, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 图表页（Path 自绘，不用 GeometryReader）

struct HLChartView: View {
    @EnvironmentObject var m: HLModel

    var plotW: CGFloat { UIScreen.main.bounds.width - 46 }

    func pathFor(_ data: [Double], _ w: CGFloat, _ h: CGFloat) -> Path {
        Path { p in
            if data.count == 0 { return }
            let lo = data.min() ?? 0
            let hi = data.max() ?? 1
            let range = hi - lo
            if range <= 0 { return }
            var i = 0
            while i < data.count {
                let x = CGFloat(i) / CGFloat(max(data.count - 1, 1)) * w
                let y = (1 - CGFloat((data[i] - lo) / range)) * h
                if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                else { p.addLine(to: CGPoint(x: x, y: y)) }
                i += 1
            }
        }
    }

    func pathForOpt(_ data: [Double?], _ w: CGFloat, _ h: CGFloat) -> Path {
        Path { p in
            var vals: [Double] = []
            var idx: [Int] = []
            var i = 0
            while i < data.count {
                if data[i] != nil { vals.append(data[i]!); idx.append(i) }
                i += 1
            }
            if vals.count == 0 { return }
            let lo = vals.min() ?? 0
            let hi = vals.max() ?? 1
            let range = hi - lo
            if range <= 0 { return }
            var j = 0
            while j < vals.count {
                let x = CGFloat(idx[j]) / CGFloat(max(data.count - 1, 1)) * w
                let y = (1 - CGFloat((vals[j] - lo) / range)) * h
                if j == 0 { p.move(to: CGPoint(x: x, y: y)) }
                else { p.addLine(to: CGPoint(x: x, y: y)) }
                j += 1
            }
        }
    }

    func maSeries(_ k: Int) -> [Double?] {
        let c = m.closes
        var out: [Double?] = []
        var i = 0
        while i < c.count {
            out.append(m.maAt(c, k, i))
            i += 1
        }
        return out
    }

    var recentBands: [HLSignal] {
        let n = m.closes.count
        if n == 0 { return [] }
        let start = n > 120 ? n - 120 : 0
        var out: [HLSignal] = []
        var i = start
        while i < n {
            out.append(m.bandAt(i))
            i += 1
        }
        return out
    }

    var body: some View {
        VStack(spacing: 10) {
                // 走势
                VStack(spacing: 8) {
                    Text("走势 · 信号色带")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if m.closes.count < 2 {
                        Text("加载中…").font(.system(size: 12)).foregroundColor(HLDim)
                            .frame(height: 190)
                    } else {
                        ZStack(alignment: .topLeading) {
                            pathForOpt(maSeries(20), plotW, 190).stroke(Color(red: 1.0, green: 0.69, blue: 0.13), lineWidth: 1.2)
                            pathForOpt(maSeries(60), plotW, 190).stroke(Color(red: 0.30, green: 0.62, blue: 1.0), lineWidth: 1.2)
                            pathFor(m.closes, plotW, 190).stroke(HLText, lineWidth: 1.6)
                        }
                        .frame(width: plotW, height: 190)

                        // 色带
                        HStack(spacing: 0.6) {
                            ForEach(Array(recentBands.indices), id: \.self) { i in
                                Rectangle()
                                    .fill(recentBands[i].color.opacity(0.55))
                                    .frame(height: 12)
                            }
                        }
                        .frame(width: plotW)

                        HStack(spacing: 14) {
                            HLLegend("红灯 禁止买", Color(red: 1.0, green: 0.30, blue: 0.37))
                            HLLegend("黄灯 观望", Color(red: 1.0, green: 0.69, blue: 0.13))
                            HLLegend("绿灯 可操作", Color(red: 0.0, green: 0.84, blue: 0.56))
                        }
                    }
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                // 分时
                VStack(spacing: 8) {
                    Text("分时 · 5分钟")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if m.intraday.count < 2 {
                        Text("非交易时段或暂无分时数据")
                            .font(.system(size: 11))
                            .foregroundColor(HLDim2)
                            .frame(height: 110)
                    } else {
                        pathFor(m.intraday.map { $0.close }, plotW, 110)
                            .stroke(HLAccent, lineWidth: 1.6)
                            .frame(width: plotW, height: 110)
                    }
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                // 回测
                VStack(spacing: 8) {
                    Text("回测 · 本金 1 万")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if m.closes.count > 60 {
                        ZStack(alignment: .topLeading) {
                            pathFor(m.holdCurve, plotW, 130).stroke(Color(red: 1.0, green: 0.30, blue: 0.37), lineWidth: 1.6)
                            pathFor(m.stratCurve, plotW, 130).stroke(Color(red: 1.0, green: 0.69, blue: 0.13), lineWidth: 1.6)
                        }
                        .frame(width: plotW, height: 130)
                    }
                    hrow("一直持有", hfmtPct((m.btHold - 1) * 100), Color(red: 1.0, green: 0.30, blue: 0.37))
                    hrow("红绿灯策略", hfmtPct((m.btStrat - 1) * 100), Color(red: 1.0, green: 0.69, blue: 0.13))
                    hrow("最大回撤（持有/策略）",
                         hfmt(m.btDDHold * 100, 1) + "% / " + hfmt(m.btDDStrat * 100, 1) + "%", HLDim)
                    Text("策略：红灯空仓、黄灯半仓、绿灯满仓，按昨日信号执行今日仓位。")
                        .font(.system(size: 10))
                        .foregroundColor(HLDim2)
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))
            }
    }
}

struct HLLegend: View {
    let text: String
    let color: Color
    init(_ text: String, _ color: Color) {
        self.text = text
        self.color = color
    }
    var body: some View {
        HStack(spacing: 4) {
            Rectangle().fill(color).frame(width: 9, height: 9).cornerRadius(2)
            Text(text).font(.system(size: 10)).foregroundColor(HLDim2)
        }
    }
}

// MARK: - 计算页

struct HLCalcView: View {
    @EnvironmentObject var m: HLModel
    @State var costText: String = ""
    @State var qtyText: String = ""
    @State var lotsText: String = "1"
    @State var hiText: String = ""
    @State var loText: String = ""
    @State var feeText: String = "0.05"
    @State var planText: String = ""

    var plan: Double { Double(planText) ?? 0 }
    var batch1: Double { plan * 0.3 }
    var batch2: Double { plan * 0.3 }
    var batch3: Double { plan * 0.4 }
    var batch1Text: String { plan > 0 ? hfmt(batch1, 0) + " 元 @" + hfmt(m.lastPrice, 3) : "—" }
    var batch2Text: String { plan > 0 ? hfmt(batch2, 0) + " 元 @" + hfmt(m.lastPrice * 0.95, 3) : "—" }
    var batch3Text: String { plan > 0 ? hfmt(batch3, 0) + " 元 @" + hfmt(m.lastPrice * 0.90, 3) : "—" }
    var exposurePct: Double { plan > 0 ? (m.lastPrice * qty) / plan * 100 : 0 }
    var exposureText: String { plan > 0 ? hfmt(exposurePct, 1) + "%" : "—" }
    var exposureColor: Color {
        if plan <= 0 { return HLDim }
        if exposurePct > 80 { return Color(red: 1.0, green: 0.30, blue: 0.37) }
        if exposurePct > 50 { return Color(red: 1.0, green: 0.69, blue: 0.13) }
        return Color(red: 0.0, green: 0.84, blue: 0.56)
    }

    var cost: Double { Double(costText) ?? 0 }
    var qty: Double { Double(qtyText) ?? 0 }
    var lots: Double { Double(lotsText) ?? 0 }
    var hiP: Double { Double(hiText) ?? 0 }
    var loP: Double { Double(loText) ?? 0 }
    var fee: Double { Double(feeText) ?? 0 }

    var newQty: Double { qty + lots * 100 }
    var newCost: Double { newQty > 0 ? (cost * qty + m.lastPrice * lots * 100) / newQty : 0 }
    var pnl: Double { (m.lastPrice - cost) * qty }
    var oldBack: Double { cost > 0 ? (cost / m.lastPrice - 1) * 100 : 0 }
    var newBack: Double { newCost > 0 ? (newCost / m.lastPrice - 1) * 100 : 0 }
    var backDiff: Double { oldBack - newBack }
    var stopLevel: Double { m.stopLoss ?? m.periodLow }
    var oldLoss: Double { (stopLevel - cost) * qty }
    var newLoss: Double { (stopLevel - newCost) * newQty }
    var tNet: Double { (hiP - loP) * 100 - fee * 2 }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // 持仓
                VStack(spacing: 8) {
                    Text("我的持仓")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        HLField("成本价", $costText)
                        HLField("份数", $qtyText)
                    }
                    hrow("市值", hfmt(m.lastPrice * qty, 2) + " 元", HLText)
                    hrow("盈亏", hfmt(pnl, 2) + " 元", hcolor(pnl))
                    hrow("回本需涨", cost > 0 ? hfmt((cost / m.lastPrice - 1) * 100, 1) + "%" : "—", HLText)
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                // 加仓
                VStack(spacing: 8) {
                    Text("加仓摊薄")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HLField("加仓手数（1手=100份）", $lotsText)
                    hrow("加后成本", qty > 0 ? hfmt(newCost, 4) : "—", HLText)
                    hrow("回本线",
                         (backDiff >= 0 ? "降低 " : "提高 ") + hfmt(abs(backDiff), 1) + " 个点",
                         backDiff >= 0 ? Color(red: 0.0, green: 0.84, blue: 0.56) : Color(red: 1.0, green: 0.30, blue: 0.37))
                    hrow("跌到止损位",
                         hfmt(newLoss, 2) + " 元（" + (newLoss < oldLoss ? "多亏 " + hfmt(abs(newLoss - oldLoss), 2) : "优于现在") + "）",
                         newLoss < oldLoss ? Color(red: 1.0, green: 0.30, blue: 0.37) : Color(red: 0.0, green: 0.84, blue: 0.56))
                    Text(m.signal == .red
                         ? "当前红灯，规则禁止加仓。摊薄虽让回本线降 \(hfmt(backDiff, 1)) 个点，但风险敞口从 \(hfmt(qty, 0)) 份扩大到 \(hfmt(newQty, 0)) 份。"
                         : "当前非红灯，加仓在规则允许范围内。仍建议先确认站稳天数。")
                        .font(.system(size: 11))
                        .foregroundColor(m.signal == .red ? Color(red: 1.0, green: 0.30, blue: 0.37) : Color(red: 0.0, green: 0.84, blue: 0.56))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                // 做T
                VStack(spacing: 8) {
                    Text("做 T（先卖后买）")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        HLField("高抛价", $hiText)
                        HLField("低吸价", $loText)
                    }
                    HLField("单边佣金", $feeText)
                    hrow("净收益（100份）", hfmt(tNet, 2) + " 元", hcolor(tNet))
                    Text("当天必须买回。卖完没跌回来就认了，别追高买回。")
                        .font(.system(size: 10))
                        .foregroundColor(HLDim2)
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                // 分批建仓计划
                VStack(spacing: 8) {
                    Text("分三批建仓计划（绿灯后可参考）")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HLField("计划投入资金（元）", $planText)
                    hrow("第1批 30% · 现价", batch1Text, HLDim)
                    hrow("第2批 30% · 再跌5%", batch2Text, HLDim)
                    hrow("第3批 40% · 再跌10%", batch3Text, HLDim)
                    Text("分批的意义不是提高收益，是避免一次性买在阶段高点。每批之间建议间隔观察。")
                        .font(.system(size: 10))
                        .foregroundColor(HLDim2)
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                // 风险敞口
                VStack(spacing: 6) {
                    Text("风险敞口")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    hrow("持仓市值", hfmt(m.lastPrice * qty, 2) + " 元", HLText)
                    hrow("占总资金", exposureText, exposureColor)
                    hrow("单日波动(1×ATR)", hfmt((m.atr() ?? 0) * qty, 2) + " 元", HLDim)
                    hrow("跌到止损亏损", hfmt((stopLevel - cost) * qty, 2) + " 元", Color(red: 1.0, green: 0.30, blue: 0.37))
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                // 指标
                VStack(spacing: 6) {
                    Text("技术指标")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    hrow("RSI(6)", hfmt(m.rsi(6), 1), rsiColor(m.rsi(6)))
                    hrow("RSI(14)", hfmt(m.rsi(14), 1), rsiColor(m.rsi(14)))
                    hrow("布林上轨 · 压力", hfmt(m.bollUp, 4), Color(red: 1.0, green: 0.30, blue: 0.37))
                    hrow("布林中轨 · MA20", hfmt(m.bollMid, 4), HLText)
                    hrow("布林下轨 · 支撑", hfmt(m.bollLow, 4), Color(red: 0.0, green: 0.84, blue: 0.56))
                    hrow("带宽", hfmt(m.bollWidth, 2) + "%", HLDim)
                    hrow("ATR(14)", hfmt(m.atr(), 4), HLText)
                    hrow("20日年化波动率", hfmt(m.annualVol, 1) + "%", HLDim)
                    hrow("日均振幅", hfmt(m.avgAmp, 2) + "%", HLDim)
                    hrow("近一年分位", hfmt(m.percentile, 1) + "%", HLDim)
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                Text("本工具仅为纪律辅助，不构成投资建议。市场有风险，本金可能亏损。")
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
            }
                .padding(10)
                .contentShape(Rectangle())
                .onTapGesture { HLEndEditing() }
            }
            .background(Color(red: 0.043, green: 0.051, blue: 0.071))
            .onTapGesture { HLEndEditing() }
            .onAppear { loadPos() }
        .onChange(of: m.curCode) { _ in loadPos() }
        .onChange(of: costText) { _ in savePos() }
        .onChange(of: qtyText) { _ in savePos() }
    }

    func rsiColor(_ v: Double?) -> Color {
        if v == nil { return HLDim }
        if v! < 30 { return Color(red: 0.0, green: 0.84, blue: 0.56) }
        if v! > 70 { return Color(red: 1.0, green: 0.30, blue: 0.37) }
        return Color(red: 1.0, green: 0.69, blue: 0.13)
    }

    func posKey() -> String { "hl_pos_" + m.curCode }

    func loadPos() {
        let d = UserDefaults.standard
        let c = d.double(forKey: posKey() + "_cost")
        let q = d.double(forKey: posKey() + "_qty")
        costText = c > 0 ? String(format: "%g", c) : ""
        qtyText = q > 0 ? String(format: "%g", q) : ""
        hiText = String(format: "%.3f", m.lastPrice * 1.006)
        loText = String(format: "%.3f", m.lastPrice * 0.997)
    }

    func savePos() {
        let d = UserDefaults.standard
        d.set(cost, forKey: posKey() + "_cost")
        d.set(qty, forKey: posKey() + "_qty")
    }
}

struct HLField: View {
    let title: String
    let text: Binding<String>
    init(_ title: String, _ text: Binding<String>) {
        self.title = title
        self.text = text
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10)).foregroundColor(HLDim2)
            TextField("", text: text)
                .keyboardType(.decimalPad)
                .font(.system(size: 14))
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 9).fill(HLCard))
                .foregroundColor(HLText)
                .toolbar {
                    ToolbarItem(placement: .keyboard) {
                        HStack {
                            Spacer()
                            Button("完成") { HLEndEditing() }
                        }
                    }
                }
        }
        .frame(maxWidth: .infinity)
    }
}

func HLEndEditing() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil, from: nil, for: nil
    )
}

// MARK: - 专业分析页

struct HLProView: View {
    @EnvironmentObject var m: HLModel

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // 综合评分
                VStack(spacing: 9) {
                    Text("技术面综合评分")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 13) {
                        ZStack {
                            Circle()
                                .stroke(HLDim2, lineWidth: 5)
                                .frame(width: 72, height: 72)
                            Circle()
                                .trim(from: 0, to: CGFloat(m.techScore) / 100.0)
                                .stroke(m.scoreColor, lineWidth: 5)
                                .frame(width: 72, height: 72)
                                .rotationEffect(.degrees(-90))
                            Text(String(m.techScore))
                                .font(.system(size: 23, weight: .bold))
                                .foregroundColor(m.scoreColor)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(m.scoreText)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(m.scoreColor)
                            Text("由均线/MACD/KDJ/RSI/威廉\n多维加权得出")
                                .font(.system(size: 10))
                                .foregroundColor(HLDim2)
                        }
                        Spacer()
                    }
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                // MACD
                VStack(spacing: 6) {
                    Text("MACD (12,26,9)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    hrow("DIF", hfmt(m.macdDIF, 4), HLText)
                    hrow("DEA", hfmt(m.macdDEA, 4), HLText)
                    hrow("MACD柱", hfmt(m.macdHist, 4), hcolor(m.macdHist))
                    hrow("状态", m.macdText, m.macdColor)
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                // KDJ + 威廉 + RSI
                VStack(spacing: 6) {
                    Text("摆动指标")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    hrow("KDJ · K", hfmt(m.kValue, 1), HLText)
                    hrow("KDJ · D", hfmt(m.dValue, 1), HLText)
                    hrow("KDJ · J", hfmt(m.jValue, 1), HLText)
                    hrow("KDJ 状态", m.kdjText, HLDim)
                    hrow("威廉 %R (14)", hfmt(m.williamsR, 1), HLDim)
                    hrow("RSI(24)", hfmt(m.rsi(24), 1), HLDim)
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                // 多周期均线
                VStack(spacing: 6) {
                    Text("多周期均线")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    hrow("MA5", hfmt(m.ma(5), 4), HLText)
                    hrow("MA10", hfmt(m.ma(10), 4), HLText)
                    hrow("MA20", hfmt(m.ma(20), 4), HLText)
                    hrow("MA60", hfmt(m.ma(60), 4), HLText)
                    hrow("MA120", hfmt(m.ma(120), 4), HLText)
                    hrow("MA250", hfmt(m.ma(250), 4), HLText)
                    hrow("排列形态", m.maArrangement, HLDim)
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                // 支撑压力
                VStack(spacing: 6) {
                    Text("支撑压力（近60日枢轴点）")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    hrow("上方压力", hfmt(m.resistance, 4), Color(red: 1.0, green: 0.30, blue: 0.37))
                    hrow("现价", hfmt(m.lastPrice, 4), HLText)
                    hrow("下方支撑", hfmt(m.support, 4), Color(red: 0.0, green: 0.84, blue: 0.56))
                    hrow("布林带位置", m.bollPosText, HLDim)
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                // 回撤与信号统计
                VStack(spacing: 6) {
                    Text("回撤与信号分布")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    hrow("当前回撤", hfmt(m.currentDrawdown, 1) + "%", Color(red: 1.0, green: 0.30, blue: 0.37))
                    hrow("区间最大回撤", hfmt(m.maxDrawdown, 1) + "%", HLDim)
                    hrow("近120日 红灯", String(m.redDays) + " 天", Color(red: 1.0, green: 0.30, blue: 0.37))
                    hrow("近120日 黄灯", String(m.yellowDays) + " 天", Color(red: 1.0, green: 0.69, blue: 0.13))
                    hrow("近120日 绿灯", String(m.greenDays) + " 天", Color(red: 0.0, green: 0.84, blue: 0.56))
                    hrow("量价", m.volumeState, HLDim)
                    hrow("量能趋势", m.obvTrend, HLDim)
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                // 走势与回测（原图表页，已合并进来）
                HLChartView()

                // 策略实验室
                HLStrategyView()

                // 风险引擎
                HLRiskView()

                Text("指标基于历史K线实时计算，仅描述已发生的价格结构，不预测未来。\n本工具仅为纪律辅助，不构成投资建议。")
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
            }
            .padding(10)
        }
        .background(Color(red: 0.043, green: 0.051, blue: 0.071))
    }
}

// MARK: - 策略实验室

struct HLStrategyView: View {
    @EnvironmentObject var m: HLModel

    // 策略对比行（普通函数，不在 ViewBuilder 内声明 let）
    func btRow(_ i: Int) -> some View {
        let r = m.btRows[i]
        let name = m.strategyName(i)
        let isBest = (i == m.bestStrategyIndex)
        let retPct = (r[0] - 1) * 100
        return HStack(spacing: 8) {
            Text(name)
                .font(.system(size: 12, weight: isBest ? .bold : .regular))
                .foregroundColor(isBest ? Color(red: 0.0, green: 0.84, blue: 0.56) : HLText)
                .frame(width: 104, alignment: .leading)
            Text(hfmt(retPct, 1) + "%")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(hcolor(retPct))
                .frame(width: 58, alignment: .trailing)
            Text(hfmt(r[1], 1) + "%")
                .font(.system(size: 11))
                .foregroundColor(HLDim)
                .frame(width: 52, alignment: .trailing)
            Text(String(Int(r[2])))
                .font(.system(size: 11))
                .foregroundColor(HLDim2)
                .frame(width: 40, alignment: .trailing)
            Spacer()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isBest ? Color(red: 0.0, green: 0.84, blue: 0.56).opacity(0.10) : Color.clear)
        )
    }

    var body: some View {
        VStack(spacing: 10) {
            // 总纲
            VStack(spacing: 6) {
                Text("策略实验室")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(HLText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("下面所有内容都是对已发生数据的统计，不是对未来的预测。它的作用是帮你在下单前看清胜算和风险，而不是告诉你该买。")
                    .font(.system(size: 11))
                    .foregroundColor(HLDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(13)
            .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

            // 综合建议
            VStack(spacing: 8) {
                Text("综合行动建议")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(HLDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(m.adviceText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(m.voteColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    Text("多头 " + String(m.voteBull) + " : " + String(m.voteBear) + " 空头")
                        .font(.system(size: 11))
                        .foregroundColor(HLDim)
                    Spacer()
                    Text(m.voteText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(m.voteColor)
                }
            }
            .padding(13)
            .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

            // 七策略回测对比
            VStack(spacing: 8) {
                Text("七种策略在同一段历史上的表现")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(HLDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Text("策略").font(.system(size: 10)).foregroundColor(HLDim2)
                        .frame(width: 104, alignment: .leading)
                    Text("收益").font(.system(size: 10)).foregroundColor(HLDim2)
                        .frame(width: 58, alignment: .trailing)
                    Text("回撤").font(.system(size: 10)).foregroundColor(HLDim2)
                        .frame(width: 52, alignment: .trailing)
                    Text("交易").font(.system(size: 10)).foregroundColor(HLDim2)
                        .frame(width: 40, alignment: .trailing)
                    Spacer()
                }
                .padding(.horizontal, 8)
                ForEach(Array(m.btRows.indices), id: \.self) { i in
                    self.btRow(i)
                }
                Text("最优（收益减去半个回撤后）: " + m.bestStrategyName)
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("历史最优不等于未来最优。参数固定的策略在任何标的上都会阶段性失效。")
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(13)
            .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

            // 历史相似形态
            VStack(spacing: 6) {
                Text("历史相似形态（这不是预测）")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(HLDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("在历史中找出与当前技术形态最接近的日子，看它们之后 20 日实际发生了什么。")
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                hrow("匹配样本", String(m.similarCount) + " 个", HLDim)
                hrow("之后20日平均涨跌", hfmt(m.similarAvgRet, 2) + "%", m.similarColor)
                hrow("上涨概率", hfmt(m.similarWinRate, 0) + "%", HLDim)
                hrow("上涨时平均涨", hfmt(m.similarAvgWin, 2) + "%", Color(red: 0.0, green: 0.84, blue: 0.56))
                hrow("下跌时平均跌", hfmt(m.similarAvgLoss, 2) + "%", Color(red: 1.0, green: 0.30, blue: 0.37))
                hrow("最好情况", hfmt(m.similarBest, 2) + "%", HLDim)
                hrow("最差情况", hfmt(m.similarWorst, 2) + "%", HLDim)
                Text(m.similarText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(m.similarColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(13)
            .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

            // 蒙特卡洛
            VStack(spacing: 6) {
                Text("波动情景推演（基于真实波动率）")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(HLDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("用过去 60 个交易日的真实波动率随机推演 800 次，给出价格的统计分布区间，不是点位预测。")
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                hrow("20日后 25%~75%", m.mc20Text, HLText)
                hrow("20日后 悲观(5%)", hfmt(m.mc20[0], 3), Color(red: 1.0, green: 0.30, blue: 0.37))
                hrow("20日后 乐观(95%)", hfmt(m.mc20[4], 3), Color(red: 0.0, green: 0.84, blue: 0.56))
                hrow("60日后 中位", hfmt(m.mc60[2], 3), HLDim)
                hrow("60日后 25%~75%", hfmt(m.mc60[1], 3) + " ~ " + hfmt(m.mc60[3], 3), HLDim)
            }
            .padding(13)
            .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

            // 凯利仓位
            VStack(spacing: 6) {
                Text("仓位参考（分数凯利）")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(HLDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                hrow("原始凯利值", hfmt(m.kellyRaw * 100, 1) + "%", HLDim)
                hrow("实战建议(1/4)", m.kellyText, Color(red: 1.0, green: 0.69, blue: 0.13))
                Text(m.kellyReason)
                    .font(.system(size: 11))
                    .foregroundColor(HLDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("凯利公式对参数极其敏感，样本少时误差很大。这里取四分之一作为保守参考。")
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(13)
            .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))
        }
    }
}

// MARK: - 风险引擎页

struct HLRiskView: View {
    @EnvironmentObject var m: HLModel

    func gridRow(_ i: Int) -> some View {
        let r = m.gridAt(i)
        let isBest = (i == m.gridBest)
        let isDefault = (Int(r[0]) == 20 && Int(r[1]) == 60)
        var label = "MA" + String(Int(r[0])) + "/" + String(Int(r[1]))
        if isDefault { label += " (默认)" }
        return HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: (isBest || isDefault) ? .bold : .regular))
                .foregroundColor(isBest ? Color(red: 0.0, green: 0.84, blue: 0.56) : (isDefault ? HLAccent : HLText))
                .frame(width: 96, alignment: .leading)
            Text(hfmt(r[2], 1) + "%")
                .font(.system(size: 11))
                .foregroundColor(hcolor(r[2]))
                .frame(width: 54, alignment: .trailing)
            Text(hfmt(r[3], 1) + "%")
                .font(.system(size: 10))
                .foregroundColor(HLDim)
                .frame(width: 48, alignment: .trailing)
            Text(hfmt(r[4], 1))
                .font(.system(size: 10, weight: isBest ? .bold : .regular))
                .foregroundColor(isBest ? Color(red: 0.0, green: 0.84, blue: 0.56) : HLDim2)
                .frame(width: 44, alignment: .trailing)
            Spacer()
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isBest ? Color(red: 0.0, green: 0.84, blue: 0.56).opacity(0.10) : Color.clear)
        )
    }

    func signalRow(_ name: String, _ q: [Double], _ color: Color) -> some View {
        return HStack(spacing: 8) {
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 52, alignment: .leading)
            Text(String(Int(q[0])) + " 次")
                .font(.system(size: 11))
                .foregroundColor(HLDim)
                .frame(width: 52, alignment: .trailing)
            Text(hfmt(q[1], 2) + "%")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(hcolor(q[1]))
                .frame(width: 62, alignment: .trailing)
            Text(hfmt(q[2], 0) + "% 上涨")
                .font(.system(size: 10))
                .foregroundColor(HLDim2)
                .frame(width: 66, alignment: .trailing)
            Spacer()
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            // 在险价值
            VStack(spacing: 6) {
                Text("在险价值 VaR / 期望损失 CVaR")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(HLDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("在正常市场下，一天内你最多可能亏多少。历史法用真实分布，正态法会低估厚尾。")
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                hrow("单日 VaR 95%", m.var95Text, Color(red: 1.0, green: 0.69, blue: 0.13))
                hrow("单日 VaR 99%", m.var99Text, Color(red: 1.0, green: 0.30, blue: 0.37))
                hrow("CVaR 95%（尾部平均）", m.cvar95Text, Color(red: 1.0, green: 0.30, blue: 0.37))
                hrow("CVaR 99%", m.cvar99Text, Color(red: 1.0, green: 0.30, blue: 0.37))
                if m.qtyGlobal > 0 {
                    hrow("按持仓换算 95%", hfmt(m.var95Money, 2) + " 元", HLDim)
                    hrow("极端情况 CVaR", hfmt(m.cvar95Money, 2) + " 元", HLDim)
                }
            }
            .padding(13)
            .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

            // 风险调整收益
            VStack(spacing: 6) {
                Text("风险调整收益")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(HLDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                hrow("年化收益", hfmt(m.annRet * 100, 2) + "%", hcolor(m.annRet * 100))
                hrow("年化波动", hfmt(m.annVol * 100, 2) + "%", HLDim)
                hrow("夏普比率", hfmt(m.sharpe, 3) + " · " + m.sharpeText, m.sharpeColor)
                hrow("索提诺比率", hfmt(m.sortino, 3), HLDim)
                hrow("Calmar 比率", hfmt(m.calmar, 3), HLDim)
                hrow("最大回撤", hfmt(m.maxDrawdownPct, 1) + "%", Color(red: 1.0, green: 0.30, blue: 0.37))
                hrow("最长水下", String(m.maxUnderwater) + " 个交易日", HLDim)
                Text("最长水下天数比最大回撤更折磨人 —— 它告诉你「难受」会持续多久。")
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(13)
            .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

            // 波动率结构
            VStack(spacing: 6) {
                Text("波动率结构")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(HLDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                hrow("5日", hfmt(m.cone5 * 100, 2) + "%", HLDim)
                hrow("10日", hfmt(m.cone10 * 100, 2) + "%", HLDim)
                hrow("20日", hfmt(m.cone20 * 100, 2) + "%", HLDim)
                hrow("60日", hfmt(m.cone60 * 100, 2) + "%", HLDim)
                hrow("EWMA 预测明日", hfmt(m.ewmaVol * 100, 2) + "%", HLDim)
                Text(m.volTrendText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(m.volTrendColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(m.coneText)
                    .font(.system(size: 11))
                    .foregroundColor(HLDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(m.volRegimeText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(m.volRegimeColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(13)
            .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

            // 市场结构
            VStack(spacing: 6) {
                Text("市场结构识别")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(HLDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                hrow("赫斯特指数 H", hfmt(m.hurst, 3), m.hurstColor)
                Text(m.hurstText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(m.hurstColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("H>0.55 说明涨了还会涨、跌了还会跌，追趋势有效；H<0.45 说明涨多了会跌回来，高抛低吸有效。")
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(13)
            .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

            // 动态止损
            VStack(spacing: 6) {
                Text("动态止损（按真实波动）")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(HLDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                hrow("近20日日均波动", hfmt(m.sdRecent * 100, 2) + "%", HLDim)
                hrow("1.5σ 紧", hfmt(m.stop15, 4), HLDim)
                hrow("2.0σ 标准", hfmt(m.stop20, 4), Color(red: 1.0, green: 0.69, blue: 0.13))
                hrow("3.0σ 宽", hfmt(m.stop30, 4), HLDim)
                hrow("你的固定止损", hfmt(m.stopLoss, 4), HLText)
                Text(m.stopSigmaText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(m.stopSigmaColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(13)
            .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

            // 参数寻优
            VStack(spacing: 8) {
                Text("参数敏感性检验")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(HLDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("把 16 组均线参数都跑一遍。如果只有一组特别好，多半是过拟合，不是真规律。")
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Text("参数").font(.system(size: 9)).foregroundColor(HLDim2)
                        .frame(width: 96, alignment: .leading)
                    Text("收益").font(.system(size: 9)).foregroundColor(HLDim2)
                        .frame(width: 54, alignment: .trailing)
                    Text("回撤").font(.system(size: 9)).foregroundColor(HLDim2)
                        .frame(width: 48, alignment: .trailing)
                    Text("评分").font(.system(size: 9)).foregroundColor(HLDim2)
                        .frame(width: 44, alignment: .trailing)
                    Spacer()
                }
                .padding(.horizontal, 6)
                ForEach(Array(0..<16), id: \.self) { i in
                    self.gridRow(i)
                }
                Text("最优: " + m.gridBestText + " · 默认 MA20/60 排第 " + String(m.gridDefaultRank) + "/16")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(HLText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(m.gridAdvice)
                    .font(.system(size: 11))
                    .foregroundColor(HLDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(13)
            .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

            // 信号审计
            VStack(spacing: 8) {
                Text("信号质量审计（最重要的自检）")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(HLDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("每个灯亮起之后 20 日，实际发生了什么。这是对这个策略本身的检验。")
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Text("信号").font(.system(size: 9)).foregroundColor(HLDim2)
                        .frame(width: 52, alignment: .leading)
                    Text("样本").font(.system(size: 9)).foregroundColor(HLDim2)
                        .frame(width: 52, alignment: .trailing)
                    Text("后20日").font(.system(size: 9)).foregroundColor(HLDim2)
                        .frame(width: 62, alignment: .trailing)
                    Text("胜率").font(.system(size: 9)).foregroundColor(HLDim2)
                        .frame(width: 66, alignment: .trailing)
                    Spacer()
                }
                signalRow("红灯", m.redQ, Color(red: 1.0, green: 0.30, blue: 0.37))
                signalRow("黄灯", m.yellowQ, Color(red: 1.0, green: 0.69, blue: 0.13))
                signalRow("绿灯", m.greenQ, Color(red: 0.0, green: 0.84, blue: 0.56))
                Text(m.signalAuditText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(m.signalAuditColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(13)
            .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))
        }
    }
}

struct HLRootView: View {
    @EnvironmentObject var m: HLModel
    @State var tab: Int = 0

    var body: some View {
        TabView(selection: $tab) {
            HLBriefView()
                .tabItem { Label("简报", systemImage: "sunrise.fill") }
                .tag(0)
            HLSignalView()
                .tabItem { Label("信号", systemImage: "lightbulb.fill") }
                .tag(1)
            HLProView()
                .tabItem { Label("专业", systemImage: "chart.bar.doc.horizontal") }
                .tag(2)
            HLCalcView()
                .tabItem { Label("计算", systemImage: "number") }
                .tag(3)
            HLWatchView()
                .tabItem { Label("自选", systemImage: "list.bullet") }
                .tag(4)
        }
        .accentColor(HLAccent)
        .onAppear {
            m.loadAll()
            m.refreshWatch()
            m.loadBrief()
        }
        .onChange(of: m.curCode) { _ in
            m.loadAll()
        }
        .preferredColorScheme(.dark)
    }
}

@main
struct HongLvdengApp: App {
    @StateObject var model = HLModel()

    var body: some Scene {
        WindowGroup {
            HLRootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
    }
}
