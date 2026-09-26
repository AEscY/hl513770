import SwiftUI
import Foundation

// MARK: - 数据模型

struct HLCandle {
    let date: String
    let open: Double
    let high: Double
    let low: Double
    let close: Double
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
    var lastPrice: Double { quote?.price ?? (closes.last ?? 0) }

    func ma(_ k: Int) -> Double? {
        let a = closes
        if a.count < k || k <= 0 { return nil }
        var s = 0.0
        var i = a.count - k
        while i < a.count {
            s += a[i]
            i += 1
        }
        return s / Double(k)
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
        var comps = URLComponents(string: "https://qt.gtimg.cn/q=" + list)
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
                var amtWan = HLDouble(parts, 37)
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
                    if c > 0 {
                        let short = day.count >= 10 ? String(day.suffix(5)) : day
                        out.append(HLCandle(date: short, open: o, high: h, low: l, close: c))
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
                            if c > 0 {
                                let short = dt.count >= 10 ? String(dt.suffix(5)) : dt
                                out.append(HLCandle(date: short, open: o, high: h, low: l, close: c))
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
        let a = closes
        if a.count <= k { return nil }
        var gain = 0.0
        var loss = 0.0
        var i = 1
        while i <= k {
            let ch = a[i] - a[i - 1]
            if ch > 0 { gain += ch } else { loss -= ch }
            i += 1
        }
        var ag = gain / Double(k)
        var al = loss / Double(k)
        if a.count > k + 1 {
            var j = k + 1
            while j < a.count {
                let ch = a[j] - a[j - 1]
                let g = ch > 0 ? ch : 0.0
                let l = ch < 0 ? -ch : 0.0
                ag = (ag * Double(k - 1) + g) / Double(k)
                al = (al * Double(k - 1) + l) / Double(k)
                j += 1
            }
        }
        if al <= 0 { return 100 }
        return 100 - 100 / (1 + ag / al)
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
        if idx + 1 < k { return nil }
        var s = 0.0
        var i = idx - k + 1
        while i <= idx {
            s += a[i]
            i += 1
        }
        return s / Double(k)
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

    let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var staleMinutes: Int {
        let sec = Date().timeIntervalSince(m.lastUpdate)
        return Int(sec / 60)
    }

    var isStale: Bool { staleMinutes >= 5 }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(m.dataSource.isEmpty ? HLDim2 : (isStale ? Color(red: 1.0, green: 0.69, blue: 0.13) : Color(red: 0.0, green: 0.84, blue: 0.56)))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.dataSource.isEmpty ? "未连接" : (m.dataSource + " · " + m.dataTime))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(HLText)
                Text(isStale ? ("数据已 " + String(staleMinutes) + " 分钟未更新") : "实时")
                    .font(.system(size: 9.5))
                    .foregroundColor(HLDim2)
            }
            Spacer()
            Button {
                m.loadAll()
                m.refreshWatch()
                m.loadBrief()
            } label: {
                Text("刷新")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(HLAccent))
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
            }
            .padding(10)
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

struct HLBriefView: View {
    @EnvironmentObject var m: HLModel

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HLSourceBar()

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
        ScrollView {
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
                // 持仓与加仓计算（原计算页，已合并进来）
                HLCalcView()
            }
            .padding(10)
        }
        .background(Color(red: 0.043, green: 0.051, blue: 0.071))
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
        }
        .frame(maxWidth: .infinity)
    }
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

                Text("指标基于历史K线实时计算，仅描述已发生的价格结构，不预测未来。\n本工具仅为纪律辅助，不构成投资建议。")
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
            }
            .padding(10)
        }
        .background(Color(red: 0.043, green: 0.051, blue: 0.071))
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
            HLChartView()
                .tabItem { Label("图表", systemImage: "chart.xyaxis.line") }
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
