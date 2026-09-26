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
    @State var costText: String = ""
    @State var qtyText: String = ""
    @State var lotsText: String = "1"

    var cost: Double { Double(costText) ?? 0 }
    var qty: Double { Double(qtyText) ?? 0 }
    var lots: Double { Double(lotsText) ?? 0 }
    var newQty: Double { qty + lots * 100 }
    var newCost: Double { newQty > 0 ? (cost * qty + m.lastPrice * lots * 100) / newQty : 0 }
    var pnl: Double { (m.lastPrice - cost) * qty }

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

                // 持仓
                VStack(spacing: 8) {
                    Text("我的持仓")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("成本价").font(.system(size: 10)).foregroundColor(HLDim2)
                            TextField("", text: $costText)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 14))
                                .padding(9)
                                .background(RoundedRectangle(cornerRadius: 9).fill(HLCard))
                                .foregroundColor(HLText)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("份数").font(.system(size: 10)).foregroundColor(HLDim2)
                            TextField("", text: $qtyText)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 14))
                                .padding(9)
                                .background(RoundedRectangle(cornerRadius: 9).fill(HLCard))
                                .foregroundColor(HLText)
                        }
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
                    VStack(alignment: .leading, spacing: 3) {
                        Text("加仓手数（1手=100份）").font(.system(size: 10)).foregroundColor(HLDim2)
                        TextField("", text: $lotsText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 14))
                            .padding(9)
                            .background(RoundedRectangle(cornerRadius: 9).fill(HLCard))
                            .foregroundColor(HLText)
                    }
                    hrow("加后成本", qty > 0 ? hfmt(newCost, 4) : "—", HLText)
                    Text(m.signal == .red
                         ? "当前红灯，规则禁止加仓。摊薄降低回本线，但风险敞口扩大。"
                         : "当前非红灯，加仓在规则允许范围内。")
                        .font(.system(size: 11))
                        .foregroundColor(m.signal == .red ? Color(red: 1.0, green: 0.30, blue: 0.37) : Color(red: 0.0, green: 0.84, blue: 0.56))
                        .frame(maxWidth: .infinity, alignment: .leading)
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

struct HLRootView: View {
    @EnvironmentObject var m: HLModel
    @State var tab: Int = 0

    var body: some View {
        TabView(selection: $tab) {
            HLSignalView()
                .tabItem { Label("信号", systemImage: "lightbulb.fill") }
                .tag(0)
            HLWatchView()
                .tabItem { Label("自选", systemImage: "list.bullet") }
                .tag(1)
        }
        .accentColor(HLAccent)
        .onAppear {
            m.loadAll()
            m.refreshWatch()
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
