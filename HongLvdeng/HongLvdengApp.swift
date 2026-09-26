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
    var change: Double { price - preClose }
    var changePct: Double { preClose > 0 ? (price - preClose) / preClose * 100 : 0 }
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

    // MARK: - 网络

    static func gbkEncoding() -> String.Encoding {
        let cf = CFStringEncodings.GB_18030_2000
        let raw = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cf.rawValue))
        return String.Encoding(rawValue: UInt(raw))
    }

    func loadQuotes(_ codes: [String], done: @escaping ([String: HLQuote]) -> Void) {
        if codes.isEmpty {
            DispatchQueue.main.async { done([:]) }
            return
        }
        let list = codes.joined(separator: ",")
        let urlStr = "https://qt.gtimg.cn/q=" + list
        if let url = URL(string: urlStr) {
            let task = URLSession.shared.dataTask(with: url) { data, _, err in
                if err != nil || data == nil {
                    DispatchQueue.main.async { done([:]) }
                    return
                }
                let enc = HLModel.gbkEncoding()
                let text = String(data: data!, encoding: enc)
                var out: [String: HLQuote] = [:]
                if let t = text {
                    let lines = t.components(separatedBy: ";")
                    for line in lines {
                        let tr = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if tr.hasPrefix("v_") == false { continue }
                        if let eq = tr.firstIndex(of: "=") {
                            let start = tr.index(tr.startIndex, offsetBy: 2)
                            let key = String(tr[start..<eq])
                            var body = String(tr[tr.index(after: eq)...])
                            body = body.trimmingCharacters(in: CharacterSet(charactersIn: "\"\n\r "))
                            let parts = body.components(separatedBy: "~")
                            if parts.count >= 6 {
                                let price = Double(parts[3]) ?? 0
                                let pre = Double(parts[4]) ?? 0
                                if price > 0 {
                                    out[key] = HLQuote(code: key, name: parts[1],
                                                        price: price, preClose: pre)
                                }
                            }
                        }
                    }
                }
                DispatchQueue.main.async { done(out) }
            }
            task.resume()
        } else {
            DispatchQueue.main.async { done([:]) }
        }
    }

    func loadHistory(_ code: String, done: @escaping ([HLCandle]) -> Void) {
        let urlStr = "https://web.ifzq.gtimg.cn/appstock/app/fqkline/get?param=" + code + ",day,,,320,qfq"
        if let url = URL(string: urlStr) {
            let task = URLSession.shared.dataTask(with: url) { data, _, err in
                if err != nil || data == nil {
                    DispatchQueue.main.async { done([]) }
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
                                if let dt = item[0] as? String {
                                    let o = Double("\(item[1])") ?? 0
                                    let c = Double("\(item[2])") ?? 0
                                    let h = Double("\(item[3])") ?? 0
                                    let l = Double("\(item[4])") ?? 0
                                    if c > 0 {
                                        let short = dt.count >= 10 ? String(dt.suffix(5)) : dt
                                        out.append(HLCandle(date: short, open: o, high: h, low: l, close: c))
                                    }
                                }
                            }
                        }
                    }
                }
                DispatchQueue.main.async { done(out) }
            }
            task.resume()
        } else {
            DispatchQueue.main.async { done([]) }
        }
    }

    func loadAll() {
        let code = curCode
        loadQuotes([code]) { map in
            self.quote = map[code]
            self.loadHistory(code) { list in
                self.candles = list
                if list.isEmpty {
                    self.note = "数据获取失败"
                } else {
                    self.note = "最新 " + (list.last?.date ?? "") + " · " + String(list.count) + " 个交易日"
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

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
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

                // 行情
                VStack(spacing: 6) {
                    hrow("现价", hfmt(m.lastPrice, 3), HLText)
                    hrow("涨跌幅", hfmtPct(m.quote?.changePct), hcolor(m.quote?.changePct))
                    hrow("昨收", hfmt(m.quote?.preClose, 3), HLDim)
                    hrow("MA5", hfmt(m.ma(5), 4), HLText)
                    hrow("MA20 · 短期生命线", hfmt(m.ma(20), 4), HLText)
                    hrow("MA60 · 中期生命线", hfmt(m.ma(60), 4), HLText)
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                // 门槛
                VStack(spacing: 6) {
                    hrow("🟡 变黄需到", hfmt(m.nextYellow, 4), Color(red: 1.0, green: 0.69, blue: 0.13))
                    hrow("🟢 变绿需到", hfmt(m.nextGreen, 4), Color(red: 0.0, green: 0.84, blue: 0.56))
                    hrow("🔴 止损参考", hfmt(m.stopLoss, 3), Color(red: 1.0, green: 0.30, blue: 0.37))
                    hrow("近一年低", hfmt(m.periodLow, 3), HLDim)
                    hrow("近一年高", hfmt(m.periodHigh, 3), HLDim)
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                Text("本工具仅为纪律辅助，不构成投资建议。市场有风险，本金可能亏损。")
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
                    .padding(.top, 4)
            }
            .padding(10)
        }
        .background(Color(red: 0.043, green: 0.051, blue: 0.071))
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
                                m.curCode = w.code
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

                Text("数据来自公开接口，非官方授权，可能失效。\n本工具仅为纪律辅助，不构成投资建议。")
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
        }
        .background(Color(red: 0.043, green: 0.051, blue: 0.071))
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
            HLChartView()
                .tabItem { Label("图表", systemImage: "chart.xyaxis.line") }
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
