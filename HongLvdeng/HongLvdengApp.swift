import SwiftUI
import Foundation
import UIKit

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

    // ===== 券商 App 同款参数（腾讯接口补充字段）=====
    var avgPrice: Double = 0      // 均价 [51]
    var outerVol: Double = 0      // 外盘 主动买 [7]
    var innerVol: Double = 0      // 内盘 主动卖 [8]
    var weicha: Double = 0        // 委差 [50]
    var limitUp: Double = 0       // 涨停 [47]
    var limitDown: Double = 0     // 跌停 [48]
    var iopv: Double = 0          // 基金实时估值净值 [78]
    var premium: Double = 0       // 溢价率 % [77]
    var totalShare: Double = 0    // 总份额 [72]
    var bidPrices: [Double] = []  // 买一到买五价
    var bidVols: [Double] = []    // 买一到买五量
    var askPrices: [Double] = []  // 卖一到卖五价
    var askVols: [Double] = []    // 卖一到卖五量

    var hasDepth: Bool { bidPrices.count == 5 && askPrices.count == 5 }
    var isFund: Bool { iopv > 0 }

    // 外盘占比：>50% 主动买更积极
    var activeBuyPct: Double {
        let tot = outerVol + innerVol
        if tot <= 0 { return 0 }
        return outerVol / tot * 100
    }

    var avgPriceText: String { avgPrice > 0 ? String(format: "%.3f", avgPrice) : "—" }
    var weichaText: String {
        if weicha == 0 { return "—" }
        let sign = weicha > 0 ? "+" : ""
        if abs(weicha) >= 10000 { return sign + String(format: "%.2f 万手", weicha / 10000) }
        return sign + String(format: "%.0f 手", weicha)
    }
    var outerText: String {
        if outerVol <= 0 { return "—" }
        if outerVol >= 10000 { return String(format: "%.2f 万手", outerVol / 10000) }
        return String(format: "%.0f 手", outerVol)
    }
    var innerText: String {
        if innerVol <= 0 { return "—" }
        if innerVol >= 10000 { return String(format: "%.2f 万手", innerVol / 10000) }
        return String(format: "%.0f 手", innerVol)
    }
    var premiumText: String {
        if !isFund { return "—" }
        let sign = premium > 0 ? "+" : ""
        return sign + String(format: "%.2f%%", premium)
    }
    var iopvText: String { isFund ? String(format: "%.4f", iopv) : "—" }
    var shareText: String {
        if totalShare <= 0 { return "—" }
        return String(format: "%.2f 亿份", totalShare / 100000000)
    }

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

/// 波动率环境快照
/// vix 为 CBOE 官方 VIX 指数（新浪 znb_VIX，实时）；
/// ndxVol / spxVol 为基于 QQQ / SPY 收盘价自算的 20 日已实现波动率（年化 %）。
/// 注意：VXN（纳指100隐含波动率）暂无免费公开源，故以已实现波动作为代理，
/// 二者口径不同（隐含 vs 已实现），界面必须明确标注，不能当作官方 VXN 展示。
struct HLVixSnap {
    var vix: Double = 0
    var vixChg: Double = 0
    var vixPctChg: Double = 0
    var vixOpen: Double = 0
    var vixPrev: Double = 0
    var vixHigh: Double = 0
    var vixLow: Double = 0
    var vixDate: String = ""
    var vixTime: String = ""
    var vixOK: Bool = false

    var ndxVol: Double = 0
    var spxVol: Double = 0
    var ndxPctl: Double = -1
    var spxPctl: Double = -1
    var ndxOK: Bool = false
    var spxOK: Bool = false
    var bars: Int = 0

    var loading: Bool = false
    var note: String = "未获取"

    var level: Int { return HLCore.vixLevel(vix) }
    var levelName: String { return HLCore.vixLevelName(level) }
    var advice: String { return HLCore.vixAdvice(level) }
    var regime: Int { return HLCore.volRegime(level, ndxPctl, spxPctl) }
    var regimeName: String { return HLCore.volRegimeName(regime) }
    var regimeText: String { return HLCore.volRegimeText(regime) }
    var ndxPctlName: String { return HLCore.volPctName(ndxPctl) }
    var spxPctlName: String { return HLCore.volPctName(spxPctl) }
    var ready: Bool { return vixOK || ndxOK || spxOK }
}

/// 代码 -> 资产类别名（供列表展示，避免在 View 内嵌套调用）
func HLClassNameOf(_ code: String) -> String {
    return HLCore.assetClassName(HLCore.assetClass(code))
}

/// 通用标的代码 -> 名称映射（与具体标的类型无关）
func HLNameOf(_ code: String) -> String {
    let c = code.lowercased()
    if c == "hkhsi" { return "恒生指数" }
    if c == "hkhstech" { return "恒生科技" }
    if c == "usixic" { return "纳斯达克" }
    if c == "usdji" { return "道琼斯" }
    if c == "usinx" { return "标普500" }
    if c == "sh000001" { return "上证指数" }
    if c == "sz399001" { return "深证成指" }
    if c == "sz399006" { return "创业板指" }
    if c == "sh000300" { return "沪深300" }
    if c == "sh000905" { return "中证500" }
    let n = HLCore.digits6(code)
    if n == "518880" { return "黄金ETF" }
    if n == "159934" { return "黄金ETF" }
    if n == "511260" { return "十年国债" }
    if n == "511010" { return "国债ETF" }
    if n == "511990" { return "货币ETF" }
    if n == "511880" { return "货币ETF" }
    if n == "510300" { return "沪深300ETF" }
    if n == "513100" { return "纳指ETF" }
    if n == "159941" { return "纳指ETF" }
    if n == "513050" { return "中概互联" }
    if n == "510500" { return "中证500ETF" }
    if n == "159915" { return "创业板ETF" }
    if n == "588000" { return "科创50ETF" }
    return code
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
    // 自选默认留空：由使用者自行添加，不预设任何标的
    @Published var watch: [HLItem] = []
    @Published var curCode: String = ""

    var closes: [Double] { candles.map { $0.close } }
    // ===== 跨资产候选池（用于"不该只持有单一标的"的对照）=====
    // 覆盖四类：跨境权益 / A股宽基 / 利率债 / 商品
    // 跨资产对照的基准池（固定四类资产，用于"不该只持有单一标的"的横向比较）
    // 你自己的标的会自动并入，但基准池不随自选清空而消失
    var poolCodes: [String] {
        // 四类资产代表：A股宽基 / 利率债 / 商品 / 海外权益
        // 不含任何特定标的，当前自选自动并入
        var out: [String] = ["sh510300", "sh511260", "sh518880", "sh513100"]
        var i = 0
        while i < watch.count {
            let c = watch[i].code
            var has = false
            var j = 0
            while j < out.count {
                if out[j] == c { has = true }
                j += 1
            }
            if !has { out.append(c) }
            i += 1
        }
        return out
    }
    func poolName(_ code: String) -> String {
        var i = 0
        while i < watch.count {
            if watch[i].code == code { return watch[i].name }
            i += 1
        }
        return HLNameOf(code)
    }
    @Published var poolCloses: [String: [Double]] = [:]

    // 各标的在同一窗口内的动量与区间表现
    func poolMom(_ lb: Int) -> [(String, Double)] {
        var out: [(String, Double)] = []
        var i = 0
        let cs = poolCodes
        while i < cs.count {
            let c = cs[i]
            if let arr = poolCloses[c] {
                out.append((c, HLCore.hlMom(arr, lb)))
            }
            i += 1
        }
        var a = 0
        while a < out.count {
            var b = a + 1
            while b < out.count {
                if out[b].1 > out[a].1 {
                    let t = out[a]
                    out[a] = out[b]
                    out[b] = t
                }
                b += 1
            }
            a += 1
        }
        return out
    }
    func poolRange(_ code: String) -> Double? {
        if let arr = poolCloses[code] { return HLCore.hlRangeRet(arr) }
        return nil
    }
    func poolDD(_ code: String) -> Double? {
        if let arr = poolCloses[code] { return HLCore.hlMaxDD(arr) }
        return nil
    }
    func poolCorr(_ a: String, _ b: String) -> Double? {
        if a == b { return 1 }
        guard let x = poolCloses[a], let y = poolCloses[b] else { return nil }
        return HLCore.hlCorr(x, y)
    }
    // 双动量结论：胜者须跑赢现金（年化1.5%折算）才持有
    var allocPickCode: String { return allocPick.0 }
    var allocPickText: String { return allocPick.1 }
    var allocPick: (String, String) {
        let lb126 = poolMom(126)
        if lb126.count == 0 { return ("", "数据加载中") }
        let win = lb126[0]
        let cashBar = 0.015 * 126.0 / 252.0
        if win.1 <= cashBar {
            return ("CASH", "所有候选过去6个月均未跑赢现金 —— 应持币")
        }
        return (win.0, "过去6个月最强：" + poolName(win.0))
    }

    func loadPool() {
        let cs = poolCodes
        var i = 0
        while i < cs.count {
            let code = cs[i]
            loadHistory(code) { arr in
                var out: [Double] = []
                var j = 0
                while j < arr.count {
                    out.append(arr[j].close)
                    j += 1
                }
                if out.count > 0 {
                    DispatchQueue.main.async {
                        self.poolCloses[code] = out
                    }
                }
            }
            i += 1
        }
    }

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

    // 前瞻信号面板（纯算法在 HLCore，可被云端验证）
    var forwardSig: [Double] {
        if candles.count < 130 { return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 52.1, 0, 0] }
        return HLCore.forwardSignal(closes, closes.count - 1)
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
                var q = HLQuote(code: key, name: HLStr(parts, 1), price: price,
                                preClose: pre, open: op, high: hi, low: lo,
                                volume: vol, amount: amt, turnover: turnover,
                                volRatio: volRatio, amplitude: amplitude,
                                timeText: tText, source: "腾讯")
                // 券商 App 同款参数
                q.avgPrice = HLDouble(parts, 51)
                q.outerVol = HLDouble(parts, 7)
                q.innerVol = HLDouble(parts, 8)
                q.weicha = HLDouble(parts, 50)
                q.limitUp = HLDouble(parts, 47)
                q.limitDown = HLDouble(parts, 48)
                q.iopv = HLDouble(parts, 78)
                q.premium = HLDouble(parts, 77)
                q.totalShare = HLDouble(parts, 72)
                var bp: [Double] = []
                var bv: [Double] = []
                var ap: [Double] = []
                var av: [Double] = []
                var k = 0
                while k < 5 {
                    bp.append(HLDouble(parts, 9 + k * 2))
                    bv.append(HLDouble(parts, 10 + k * 2))
                    ap.append(HLDouble(parts, 19 + k * 2))
                    av.append(HLDouble(parts, 20 + k * 2))
                    k = k + 1
                }
                q.bidPrices = bp
                q.bidVols = bv
                q.askPrices = ap
                q.askVols = av
                out[key] = q
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
        loadSinaKLine(code, scale: 240, len: HLCore.historyDays) { list in
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
        let urlStr = "https://web.ifzq.gtimg.cn/appstock/app/fqkline/get?param=" + code + ",day,,," + String(HLCore.historyDays) + ",qfq"
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

    // ===== 分时逐笔成交（腾讯免费接口，3 秒粒度，带主动买卖标记）=====
    // 返回形如: v_detail_data_sh513770=[0,"0/09:25:01/0.327/-0.001/64768/2117914/S|1/..."]
    static func parseTicks(_ text: String) -> [HLTick] {
        var out: [HLTick] = []
        guard let a = text.range(of: ",\"") else { return out }
        let rest = String(text[a.upperBound...])
        guard let b = rest.range(of: "\"]") else { return out }
        let body = String(rest[rest.startIndex..<b.lowerBound])
        for item in body.components(separatedBy: "|") {
            let f = item.components(separatedBy: "/")
            if f.count < 7 { continue }
            guard let p = Double(f[2]) else { continue }
            guard let v = Double(f[4]) else { continue }
            guard let am = Double(f[5]) else { continue }
            if p <= 0 || am <= 0 { continue }
            let side = f[6].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            var tk = HLTick()
            tk.t = f[1]
            tk.price = p
            tk.vol = v
            tk.amt = am
            tk.isBuy = side.hasPrefix("B")
            out.append(tk)
        }
        return out
    }

    func loadTickPage(_ code: String, _ page: Int, done: @escaping ([HLTick]) -> Void) {
        let urlStr = "https://stock.gtimg.cn/data/index.php?appn=detail&action=data&c="
            + code + "&p=" + String(page)
        guard let url = URL(string: urlStr) else {
            done([])
            return
        }
        var req = URLRequest(url: url)
        req.setValue("https://gu.qq.com/", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_6 like Mac OS X) AppleWebKit/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        let task = URLSession.shared.dataTask(with: req) { data, _, err in
            if err != nil || data == nil {
                done([])
                return
            }
            var text = String(data: data!, encoding: .utf8)
            if text == nil || text!.isEmpty {
                text = String(data: data!, encoding: .isoLatin1)
            }
            guard let tx = text else {
                done([])
                return
            }
            done(HLModel.parseTicks(tx))
        }
        task.resume()
    }

    func loadTicks(_ code: String, done: @escaping ([HLTick]) -> Void) {
        let maxPage = 40
        var box: [Int: [HLTick]] = [:]
        let lock = NSLock()
        let group = DispatchGroup()
        var i = 0
        while i < maxPage {
            let pg = i
            group.enter()
            loadTickPage(code, pg) { tk in
                lock.lock()
                if tk.isEmpty == false { box[pg] = tk }
                lock.unlock()
                group.leave()
            }
            i += 1
        }
        group.notify(queue: .main) {
            var all: [HLTick] = []
            var j = 0
            while j < maxPage {
                if let t = box[j] { all.append(contentsOf: t) }
                j += 1
            }
            all.sort { $0.t < $1.t }
            done(all)
        }
    }

    func loadAll() {
        let code = curCode
        if code.isEmpty {
            self.quote = nil
            self.candles = []
            self.intraday = []
            self.note = "尚未添加标的"
            return
        }
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
                    let dTxt = list.last?.date ?? ""
                    let nTxt = String(list.count)
                    self.note = "最新 " + dTxt + " · " + nTxt + " 个交易日"
                }
                self.loadSinaKLine(code, scale: 5, len: 48) { intra in
                    self.intraday = intra
                }
                self.loadTicks(code) { tk in
                    self.ticks = tk
                }
            }
        }
        loadPool()
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

    @Published var addNote: String = ""

    func add(code: String) {
        var exists = false
        for w in watch {
            if w.code == code { exists = true }
        }
        if exists { addNote = "该标的已在自选中"; return }
        addNote = "正在校验 " + code + " …"
        loadQuotes([code]) { map in
            if let q = map[code] {
                self.watch.append(HLItem(code: code, name: q.name, weight: q.price))
                self.curCode = code
                self.saveWatch()
                self.addNote = "已添加 " + q.name
                self.loadAll()
                self.refreshWatch()
            } else {
                self.addNote = code + " 查无此标的，请核对代码"
            }
        }
    }

    // 切换标的：立即重新加载，不依赖 View 的 onChange（iOS 15 上更可靠）
    func select(_ code: String) {
        if curCode == code { return }
        curCode = code
        saveWatch()
        loadAll()
        refreshWatch()
    }

    func remove(code: String) {
        var next: [HLItem] = []
        for w in watch {
            if w.code != code { next.append(w) }
        }
        watch = next
        saveWatch()
        if curCode == code { curCode = next.isEmpty ? "" : next[0].code }
        loadAll()
        refreshWatch()
    }

    // MARK: - 自选持久化（自己添加的标的，下次打开还在）

    func saveWatch() {
        let d = UserDefaults.standard
        var codes: [String] = []
        var names: [String] = []
        for w in watch {
            codes.append(w.code)
            names.append(w.name)
        }
        d.set(codes, forKey: "hl_watch_codes")
        d.set(names, forKey: "hl_watch_names")
        d.set(curCode, forKey: "hl_cur_code")
    }

    func loadWatch() {
        let d = UserDefaults.standard
        let codes = d.stringArray(forKey: "hl_watch_codes") ?? []
        let names = d.stringArray(forKey: "hl_watch_names") ?? []
        var list: [HLItem] = []
        var i = 0
        while i < codes.count {
            let nm = i < names.count ? names[i] : codes[i]
            list.append(HLItem(code: codes[i], name: nm, weight: 0))
            i += 1
        }
        watch = list
        let saved = d.string(forKey: "hl_cur_code") ?? ""
        if saved.isEmpty == false {
            var hit = false
            for w in list { if w.code == saved { hit = true } }
            if hit { curCode = saved }
            else if list.isEmpty == false { curCode = list[0].code }
        } else if list.isEmpty == false {
            curCode = list[0].code
        }
    }
    // MARK: - 外围 / ADR / 成分股

    @Published var globalQuotes: [String: HLQuote] = [:]
    @Published var contextQuotes: [String: HLQuote] = [:]
    @Published var adrQuotes: [String: HLQuote] = [:]
    @Published var holdQuotes: [String: HLQuote] = [:]

    /// 当前标的的资产类别 —— 决定关联池/外围池/成分池的选择
    var assetCls: Int { return HLCore.assetClass(curCode) }
    var assetClsName: String { return HLCore.assetClassName(assetCls) }

    /// 隔夜外围清单（按标的市场归属动态生成）
    var overnightList: [HLPreset] {
        var out: [HLPreset] = []
        for c in HLCore.overnightCodes(assetCls) {
            out.append(HLPreset(code: c, name: HLNameOf(c), note: "", weight: 0))
        }
        return out
    }
    /// 关联指数/同类标的清单
    var contextList: [HLPreset] {
        var out: [HLPreset] = []
        for c in HLCore.contextCodes(assetCls) {
            out.append(HLPreset(code: c, name: HLNameOf(c), note: "", weight: 0))
        }
        return out
    }
    /// 是否展示 ADR（仅港股/中概有意义）
    var showAdrBlock: Bool { return HLCore.showAdr(assetCls) }
    /// 隔夜外围标题
    var overnightTitle: String { return "隔夜外围 · " + assetClsName }
    /// 关联指数标题
    var contextTitle: String { return "关联指数 · " + assetClsName }
    /// 成分模块标题：取不到名称时退回类别名
    var holdTitle: String {
        let nm = quote?.name ?? ""
        if nm.isEmpty { return "成分股体温计 · " + assetClsName }
        return "成分股体温计 · " + nm
    }
    /// 是否展示成分模块（仅已知持仓明细的标的）
    var showHoldBlock: Bool { return HLCore.hasHoldings(curCode) }
    @Published var intraday: [HLCandle] = []
    @Published var ticks: [HLTick] = []
    @Published var dataTime: String = ""
    @Published var dataSource: String = ""
    @Published var lastUpdate: Date = Date()
    /// 波动率环境快照（VIX 官方 + QQQ/SPY 已实现波动代理）
    @Published var vix: HLVixSnap = HLVixSnap()

    func loadBrief() {
        let cls = assetCls
        var g: [String] = HLCore.overnightCodes(cls)
        loadQuotes(g) { map in
            self.globalQuotes = map
        }
        var cx: [String] = HLCore.contextCodes(cls)
        loadQuotes(cx) { map in
            self.contextQuotes = map
        }
        if HLCore.showAdr(cls) {
            var a: [String] = []
            for p in HLAdrs { a.append(p.code) }
            loadQuotes(a) { map in
                self.adrQuotes = map
            }
        } else {
            self.adrQuotes = [:]
        }
        if HLCore.hasHoldings(curCode) {
            var h: [String] = []
            for p in HLHoldings { h.append(p.code) }
            loadQuotes(h) { map in
                self.holdQuotes = map
            }
        } else {
            self.holdQuotes = [:]
        }
        self.loadVixEnv()
    }

    // MARK: - VIX / 波动率环境

    /// 拉取官方 VIX（新浪 znb_VIX，GBK 编码）
    /// 字段：0名称 1现价 2涨跌 3涨跌幅 4-5空 6日期 7时间 8开 9昨收 10高 11低
    func loadVixIndex(done: @escaping (Double, Double, Double, Double, Double, Double, Double, String, String, Bool) -> Void) {
        let urlStr = "https://hq.sinajs.cn/list=znb_VIX"
        guard let url = URL(string: urlStr) else {
            done(0, 0, 0, 0, 0, 0, 0, "", "", false)
            return
        }
        var req = URLRequest(url: url)
        req.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_6 like Mac OS X) AppleWebKit/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 12
        let task = URLSession.shared.dataTask(with: req) { data, _, err in
            if err != nil || data == nil {
                DispatchQueue.main.async { done(0, 0, 0, 0, 0, 0, 0, "", "", false) }
                return
            }
            let enc = HLModel.gbkEncoding()
            guard let text = String(data: data!, encoding: enc) else {
                DispatchQueue.main.async { done(0, 0, 0, 0, 0, 0, 0, "", "", false) }
                return
            }
            guard let q1 = text.firstIndex(of: "\""),
                  let q2 = text.lastIndex(of: "\"") else {
                DispatchQueue.main.async { done(0, 0, 0, 0, 0, 0, 0, "", "", false) }
                return
            }
            let body = String(text[text.index(after: q1)..<q2])
            let f = body.components(separatedBy: ",")
            if f.count < 12 {
                DispatchQueue.main.async { done(0, 0, 0, 0, 0, 0, 0, "", "", false) }
                return
            }
            let cur = Double(f[1]) ?? 0
            if cur <= 0 {
                DispatchQueue.main.async { done(0, 0, 0, 0, 0, 0, 0, "", "", false) }
                return
            }
            let chg = Double(f[2]) ?? 0
            let pct = Double(f[3]) ?? 0
            let op = Double(f[8]) ?? 0
            let prev = Double(f[9]) ?? 0
            let hi = Double(f[10]) ?? 0
            let lo = Double(f[11]) ?? 0
            let d = f[6]
            let t = f[7]
            DispatchQueue.main.async { done(cur, chg, pct, op, prev, hi, lo, d, t, true) }
        }
        task.resume()
    }

    /// 美股 ETF 历史收盘价（腾讯，需带交易所后缀：QQQ.OQ / SPY.AM）
    func loadUsCloses(_ sym: String, done: @escaping ([Double]) -> Void) {
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let end = fmt.string(from: now)
        let start = fmt.string(from: cal.date(byAdding: .day, value: -600, to: now) ?? now)
        let param = sym + ",day," + start + "," + end + ",400,qfq"
        guard let enc = param.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://web.ifzq.gtimg.cn/appstock/app/usfqkline/get?param=" + enc) else {
            DispatchQueue.main.async { done([]) }
            return
        }
        var req = URLRequest(url: url)
        req.setValue("https://gu.qq.com/", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_6 like Mac OS X) AppleWebKit/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        let task = URLSession.shared.dataTask(with: req) { data, _, err in
            if err != nil || data == nil {
                DispatchQueue.main.async { done([]) }
                return
            }
            guard let obj = try? JSONSerialization.jsonObject(with: data!) as? [String: Any],
                  let dd = obj["data"] as? [String: Any] else {
                DispatchQueue.main.async { done([]) }
                return
            }
            var node: [String: Any]? = nil
            for (_, v) in dd {
                if let vv = v as? [String: Any] { node = vv; break }
            }
            guard let nd = node else {
                DispatchQueue.main.async { done([]) }
                return
            }
            var arr: [[Any]]? = nil
            if let a = nd["qfqday"] as? [[Any]] { arr = a }
            else if let a = nd["day"] as? [[Any]] { arr = a }
            guard let rows = arr else {
                DispatchQueue.main.async { done([]) }
                return
            }
            var out: [Double] = []
            for r in rows {
                if r.count < 5 { continue }
                let sv = "\(r[2])"
                let c = Double(sv) ?? 0
                if c > 0 { out.append(c) }
            }
            DispatchQueue.main.async { done(out) }
        }
        task.resume()
    }

    /// 汇总波动率环境：VIX 官方指数 + QQQ/SPY 已实现波动率与历史分位
    func loadVixEnv() {
        DispatchQueue.main.async { self.vix.loading = true }
        loadVixIndex { cur, chg, pct, op, prev, hi, lo, d, t, ok in
            self.vix.vix = cur
            self.vix.vixChg = chg
            self.vix.vixPctChg = pct
            self.vix.vixOpen = op
            self.vix.vixPrev = prev
            self.vix.vixHigh = hi
            self.vix.vixLow = lo
            self.vix.vixDate = d
            self.vix.vixTime = t
            self.vix.vixOK = ok
            self.finishVixNote()
        }
        loadUsCloses("usQQQ.OQ") { c in
            if c.count < 30 {
                self.vix.ndxOK = false
                self.finishVixNote()
                return
            }
            let v = HLCore.realizedVolPct(c, 20)
            let s = HLCore.rollingVolSeries(c, 20)
            self.vix.ndxVol = v
            self.vix.ndxPctl = HLCore.volPercentile(s, v)
            self.vix.ndxOK = v > 0
            if self.vix.bars == 0 { self.vix.bars = c.count }
            self.finishVixNote()
        }
        loadUsCloses("usSPY.AM") { c in
            if c.count < 30 {
                self.vix.spxOK = false
                self.finishVixNote()
                return
            }
            let v = HLCore.realizedVolPct(c, 20)
            let s = HLCore.rollingVolSeries(c, 20)
            self.vix.spxVol = v
            self.vix.spxPctl = HLCore.volPercentile(s, v)
            self.vix.spxOK = v > 0
            self.finishVixNote()
        }
    }

    func finishVixNote() {
        self.vix.loading = false
        var miss: [String] = []
        if self.vix.vixOK == false { miss.append("VIX") }
        if self.vix.ndxOK == false { miss.append("纳指波动") }
        if self.vix.spxOK == false { miss.append("标普波动") }
        if miss.isEmpty {
            self.vix.note = "VIX 官方指数 + 已实现波动（自算）"
        } else if miss.count == 3 {
            self.vix.note = "三项均未取到，请检查网络"
        } else {
            self.vix.note = "缺失：" + miss.joined(separator: "、")
        }
    }

    // MARK: - 日报生成

    func hlDateText(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }

    /// 生成当日决策日报（纯文本，便于复制 / 分享 / 存档）
    var dailyReport: String {
        var L: [String] = []
        let bar = "────────────────────────"

        L.append("红绿灯 · 每日决策日报")
        L.append("生成时间  " + hlDateText(Date()))
        let nm = quote?.name ?? "—"
        let cd = curCode.isEmpty ? "未选择" : curCode
        L.append("标的      " + nm + " (" + cd + ")")
        let srcTxt = dataSource.isEmpty ? "未取到" : dataSource
        let tmTxt = dataTime.isEmpty ? "未取到" : dataTime
        L.append("数据源    " + srcTxt + " · " + tmTxt)
        L.append("")

        // 一、行情快照
        L.append("【一】行情快照")
        if let q = quote {
            let sgn = q.change >= 0 ? "+" : ""
            L.append("现价 " + hfmt(q.price, 3) + "   涨跌 " + sgn + hfmt(q.change, 3)
                     + " (" + sgn + hfmt(q.changePct, 2) + "%)")
            L.append("开 " + hfmt(q.open, 3) + "  高 " + hfmt(q.high, 3)
                     + "  低 " + hfmt(q.low, 3) + "  昨收 " + hfmt(q.preClose, 3))
            var extra: [String] = []
            if q.amount > 0 { extra.append("成交额 " + hfmt(q.amount / 100000000.0, 2) + "亿") }
            if q.turnover > 0 { extra.append("换手 " + hfmt(q.turnover, 2) + "%") }
            if q.volRatio > 0 { extra.append("量比 " + hfmt(q.volRatio, 2)) }
            if q.amplitude > 0 { extra.append("振幅 " + hfmt(q.amplitude, 2) + "%") }
            if extra.isEmpty == false { L.append(extra.joined(separator: "  ")) }
            if q.isFund {
                var f2: [String] = []
                f2.append("IOPV " + hfmt(q.iopv, 4))
                f2.append("溢价 " + hfmt(q.premium, 2) + "%")
                L.append(f2.joined(separator: "  "))
            }
            if q.activeBuyPct > 0 {
                L.append("主动买占比 " + hfmt(q.activeBuyPct, 1) + "%"
                         + "   外盘 " + hfmt(q.outerVol / 10000.0, 2) + "万手"
                         + "  内盘 " + hfmt(q.innerVol / 10000.0, 2) + "万手")
            }
        } else {
            L.append("未取到行情")
        }
        L.append("")

        // 二、信号灯
        L.append("【二】信号灯与纪律")
        let sg = signal
        var sgName = "无信号（数据不足）"
        if sg == .red { sgName = "🔴 红灯" }
        else if sg == .yellow { sgName = "🟡 黄灯" }
        else if sg == .green { sgName = "🟢 绿灯" }
        L.append("当前灯色  " + sgName)
        if let y = nextYellow { L.append("变黄需到  " + hfmt(y, 4) + "（距现价 " + hfmt(gapToYellow, 3) + "）") }
        if let g = nextGreen { L.append("变绿需到  " + hfmt(g, 4)) }
        if let s = stopLoss { L.append("止损参考  " + hfmt(s, 3) + "（距现价 " + hfmt(s - lastPrice, 3) + "）") }
        L.append("规则：红灯只卖不买、禁止加仓；黄灯可小仓；绿灯可正常操作。")
        L.append("")

        // 三、波动率环境
        L.append("【三】波动率环境")
        let v = vix
        if v.vixOK {
            let s2 = v.vixChg >= 0 ? "+" : ""
            L.append("VIX " + hfmt(v.vix, 2) + "  " + s2 + hfmt(v.vixChg, 2)
                     + " (" + s2 + hfmt(v.vixPctChg, 2) + "%)  状态 " + v.levelName)
            L.append("VIX 区间  开 " + hfmt(v.vixOpen, 2) + "  高 " + hfmt(v.vixHigh, 2)
                     + "  低 " + hfmt(v.vixLow, 2) + "  昨收 " + hfmt(v.vixPrev, 2))
            L.append("VIX 数据时间  " + v.vixDate + " " + v.vixTime)
        } else {
            L.append("VIX 未取到")
        }
        if v.ndxOK {
            L.append("纳指波动(QQQ自算) " + hfmt(v.ndxVol, 2) + "%  " + v.ndxPctlName
                     + " " + hfmt(v.ndxPctl, 0) + "%分位")
        } else {
            L.append("纳指波动 未取到")
        }
        if v.spxOK {
            L.append("标普波动(SPY自算) " + hfmt(v.spxVol, 2) + "%  " + v.spxPctlName
                     + " " + hfmt(v.spxPctl, 0) + "%分位")
        } else {
            L.append("标普波动 未取到")
        }
        L.append("综合判定  " + v.regimeName)
        L.append(v.regimeText)
        L.append("注：纳指波动为已实现波动率自算代理，非官方 VXN（免费源无 VXN）。")
        L.append("")

        // 四、前瞻信号
        L.append("【四】前瞻信号")
        let f = forwardSig
        if f[1] > 0.5 {
            L.append("20日年化波动 " + hfmt(f[0], 1) + "% (Q" + String(Int(f[1])) + ")")
            L.append("未来20日跌超5%概率 " + hfmt(f[2], 1) + "%")
            L.append("未来20日平均绝对波动 " + hfmt(f[3], 2) + "%")
            L.append("偏离MA60 " + hfmt(f[4], 2) + "% (Q" + String(Int(f[5])) + ")")
            L.append("未来60日上涨概率 " + hfmt(f[6], 1) + "%")
            L.append("极端事件 " + HLCore.forwardEventName(f[15]))
            L.append("判定 " + HLCore.forwardVerdict(f))
            L.append(HLCore.forwardWarnText(f[14]))
        } else {
            L.append("历史数据不足（需 130 根以上 K 线）")
        }
        L.append("")

        // 五、异动雷达
        L.append("【五】异动扫描")
        let ag = anomalyAgg
        L.append("综合 " + HLCore.anomalyTitle(ag.level))
        if anomalies.isEmpty {
            L.append("历史数据不足（需 70 根以上 K 线）")
        } else {
            for it in anomalies {
                L.append("· " + it.name + " " + it.value + "  " + it.hint)
            }
            L.append(HLCore.anomalyAdvice(anomalies))
        }
        L.append("")

        // 六、自选
        if watch.isEmpty == false {
            L.append("【六】自选一览")
            for w in watch {
                L.append("· " + w.name + " (" + w.code + ") " + hfmt(w.weight, 3)
                         + "  " + HLClassNameOf(w.code))
            }
            L.append("")
        }

        L.append(bar)
        L.append("本日报由工具按实时数据自动生成，所有数字来自公开接口（腾讯 / 新浪）。")
        L.append("波动率与前瞻信号衡量的是风险大小与位置高低，不预测涨跌方向。")
        L.append("策略收益类结论样本有限、前瞻命中率低，不可作为买卖依据。")
        L.append("本工具仅为纪律辅助，不构成投资建议。")
        return L.joined(separator: "\n")
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

    /// 等权重平均：不依赖静态权重快照，避免权重过期造成的偏差
    func equalWeight(list: [HLPreset], quotes: [String: HLQuote]) -> Double? {
        var se = 0.0
        var n = 0.0
        for p in list {
            if let q = quotes[p.code] {
                se += q.changePct
                n += 1
            }
        }
        if n <= 0 { return nil }
        return se / n
    }

    var adrEqual: Double? { equalWeight(list: HLAdrs, quotes: adrQuotes) }
    var holdEqual: Double? { equalWeight(list: HLHoldings, quotes: holdQuotes) }
    var holdDivergence: Double? {
        if let a = holdEstimate, let b = holdEqual { return a - b }
        return nil
    }

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
    // MARK: - 策略适配度（标的中性：本标的上择时是否跑赢持有）

    func strategyFit() -> (timing: Double, hold: Double, excess: Double, trades: Int, fit: Bool) {
        return HLCore.strategyFit(closes, opens)
    }

    // 风险口径适配度（主判定）：夏普改善 + 回撤改善
    func strategyFitEx() -> HLCore.HLFitResult {
        return HLCore.strategyFitEx(closes, opens)
    }

    func profileStats() -> (vol: Double, er: Double, dd: Double) {
        return HLCore.profileStats(closes)
    }

    // 适配度结论文案（风险口径）
    func fitVerdict() -> String {
        let f = strategyFitEx()
        if f.trades == 0 { return "历史数据不足，无法判断" }
        let ddTxt = hfmt(f.dDD * 100, 1)
        if f.lowVol {
            // 低波动标的：夏普分母不可靠，只谈回撤
            if f.fit {
                return "此标的波动极低（年化 " + hfmt(f.volH * 100, 1)
                    + "%），夏普不具参考性；择时使最大回撤缩小 " + ddTxt + " 个点"
            }
            return "此标的波动极低（年化 " + hfmt(f.volH * 100, 1)
                + "%），波动空间不足以覆盖交易成本，择时只会损耗"
        }
        if f.fit {
            return "风险调整后有效：夏普改善 " + hfmt(f.dSharpe, 3)
                + "，最大回撤缩小 " + ddTxt + " 个点。它不保证多赚，但显著降低了波动"
        }
        return "风险调整后仍为负：夏普改善 " + hfmt(f.dSharpe, 3)
            + "，说明少赚的收益不足以补偿承担的波动，不宜据此频繁进出"
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

    // ===== MACD 两种用法对比 =====
    // 下拉刷新统一入口
    func refreshAll() {
        loadAll()
        refreshWatch()
        loadBrief()
    }

    var macdStateVec: [Double] { HLCore.macdState(closes) }

    // 原版：柱>0 即买入
    var macdRawSignal: Int { Int(macdStateVec[3]) }
    // 改良版：柱>0 且 DIF>0 才买
    var macdImprovedSignal: Int { Int(macdStateVec[4]) }
    // DIF 距零轴还差多少
    var macdGapToZero: Double { macdStateVec[5] }

    var macdRawText: String { macdRawSignal == 1 ? "买入" : "空仓" }
    var macdImprovedText: String { macdImprovedSignal == 1 ? "买入" : "空仓" }

    var macdRawColor: Color {
        macdRawSignal == 1 ? Color(red: 1.0, green: 0.30, blue: 0.37) : HLDim
    }
    var macdImprovedColor: Color {
        macdImprovedSignal == 1 ? Color(red: 1.0, green: 0.30, blue: 0.37) : Color(red: 0.0, green: 0.84, blue: 0.56)
    }

    var macdAdvice: String {
        if macdImprovedSignal == 1 { return "两种用法一致：可考虑" }
        if macdRawSignal == 1 {
            return "红柱已现，但 DIF 仍在零轴下 —— 属下跌中的反弹，历史上这类信号胜率低，建议只看不动"
        }
        return "两种用法一致：保持空仓"
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
        if k == 7 { return "MACD 红买绿卖" }
        if k == 8 { return "MACD 改良版" }
        if k == 9 { return "三指标共振" }
        if k == 10 { return "改良+MA60" }
        if k == 11 { return "低频时序动量" }
        if k == 12 { return "波动率目标" }
        if k == 13 { return "始终空仓(现金)" }
        if k == 14 { return "追涨+趋势止损" }
        if k == 15 { return "低买+RSI>70卖" }
        if k == 16 { return "低买+破MA20卖" }
        if k == 17 { return "低买+不卖" }
        return "—"
    }

    // 策略总数
    var strategyCount: Int { 18 }

    // 回测：扣交易成本 + 次日开盘执行（不再用当日收盘价成交）
    func backtest(_ kind: Int) -> [Double] {
        return HLCore.backtest(closes, kind, opens, 20.0, true, volumes)
    }

    // ============ 自适应方案引擎（两段一致性 + 置信度）============
    // 实证：参数自适应在样本外胜率仅 41.7%（无效）；
    // 两段一致性选模式胜率 83.3%，且置信度能预测准确率（高置信 100% / 低置信 60%）
    var adaptive: [Double] {
        if opens.count != closes.count || closes.count < 200 {
            return [2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        }
        return HLCore.adaptivePlan(opens, highs, lows, closes)
    }

    // 风险口径分项（索引 9~14）
    var isDSharpe: Double { adaptive.count >= 15 ? adaptive[9] : 0 }
    var oosDSharpe: Double { adaptive.count >= 15 ? adaptive[10] : 0 }
    var fullDSharpe: Double { adaptive.count >= 15 ? adaptive[11] : 0 }
    var fullDDD: Double { adaptive.count >= 15 ? adaptive[12] : 0 }
    var fullExposure: Double { adaptive.count >= 15 ? adaptive[13] : 0 }
    var isLowVol: Bool { adaptive.count >= 15 && adaptive[14] > 0.5 }

    // ============ 同类离散度 ============
    // 同为港股中概、同期同跌的三只标的，超额相差 53.5 个点。
    // 若同类内部都无法互相印证，单个标的的结论就更不可外推。
    @Published var peerSharpe: [Double] = []
    @Published var peerExcess: [Double] = []
    @Published var peerLoading: Bool = false
    @Published var peerDone: Bool = false

    // 离散度用「超额百分点」口径：与实测港股中概同类相差 53.5 个点同一量纲
    var peerStat: (min: Double, max: Double, spread: Double, sd: Double, n: Int) {
        HLCore.peerDispersion(peerExcess)
    }
    var peerHighSpread: Bool { HLCore.peerSpreadRisk(peerStat.spread) }

    func loadPeers() {
        let codes = HLCore.peerGroupCodes(HLCore.assetClass(curCode))
        if codes.isEmpty { return }
        peerLoading = true
        peerDone = false
        peerSharpe = []
        peerExcess = []
        let grp = DispatchGroup()
        let lock = NSLock()
        var acc: [Double] = []
        var accE: [Double] = []
        for c in codes {
            grp.enter()
            loadTencentKLine(c) { ks in
                let cl = ks.map { $0.close }
                let op = ks.map { $0.open }
                if cl.count >= 150 {
                    let f = HLCore.strategyFitEx(cl, op)
                    if f.trades > 0 {
                        lock.lock()
                        acc.append(f.dSharpe * 100)
                        accE.append(f.excess * 100)
                        lock.unlock()
                    }
                }
                grp.leave()
            }
        }
        grp.notify(queue: .main) {
            self.peerSharpe = acc
            self.peerExcess = accE
            self.peerLoading = false
            self.peerDone = true
        }
    }

    var adaptiveMode: String { HLCore.adaptiveModeText(adaptive[0]) }
    var adaptiveConf: Double { adaptive[1] }
    var adaptiveConfText: String { HLCore.adaptiveConfText(adaptive[1]) }
    var forward: [Double] {
        if closes.count < 200 || opens.count != closes.count { return [0,0,0,0,0] }
        return HLCore.forwardCheck(opens, highs, lows, closes)
    }
    var forwardText: String { HLCore.forwardCheckText(forward) }
    var forwardHit: Bool { forward.count >= 5 && forward[2] > 0.5 }
    var adaptiveAdvice: String { HLCore.adaptiveAdvice(adaptive) }
    var adaptiveReverseRisk: Bool { adaptive[8] > 0.5 }

    func adaptiveColor(_ v: Double) -> Color { hcolor(v) }

    // 证据门禁：DSR 及相关统计
    // trials = 试验过的策略与参数组合总数（保守估计）
    var trialsCount: Int { 30 }

    // ---------- 统计修正引擎 ----------
    // 20日已实现波动 → 未来20日收益 的因子检验
    // 只取最近 520 根，避免主线程长时间计算
    var statFixFactor: [Double] {
        let c = closes
        let n = c.count
        if n < 200 { return [0, 0, 0, 0, 0, 0, 0, 0] }
        let start = max(20, n - 520)
        var f = [Double]()
        var y = [Double]()
        var i = start
        while i + 20 < n {
            var w = [Double]()
            var k = i - 19
            while k <= i { w.append(c[k] / c[k - 1] - 1.0); k += 1 }
            f.append(HLCore.stdev(w) * sqrt(252.0) * 100.0)
            y.append(c[i + 20] / c[i] - 1.0)
            i += 1
        }
        return HLCore.hlFactorTest(f, y, 20)
    }

    // 固定成本 vs 波动率调整成本下的红绿灯回测
    var statFixCost: [Double] { HLCore.hlCostCompare(opens, closes, 20.0) }

    // Purge + Embargo 后的 IS/OOS 边界
    var statFixSplit: [Int] { HLCore.hlPurgedSplit(closes.count, 20, 0.01) }

    var closesCount: Int { closes.count }

    // 未修正 t：|t|>2 反而是危险信号（多半是重叠窗口造的假象）
    var statFixFactorNaiveColor: Color {
        return abs(statFixFactor[3]) > 2.0 ? HLUp : HLDim
    }
    var statFixFactorNWColor: Color {
        return abs(statFixFactor[4]) > 2.0 ? HLWarn : HLDim
    }
    var statFixFactorNoColor: Color {
        return abs(statFixFactor[5]) > 2.0 ? HLWarn : HLDim
    }
    var statFixFactorVerdictColor: Color {
        let r = statFixFactor
        if r.count < 8 || r[7] < 60 { return HLDim2 }
        if r[0] * r[1] < 0 && abs(r[0] - r[1]) > 0.05 { return HLWarn }
        return abs(HLCore.hlConservativeT([r[3], r[4], r[5]])) > 2.0 ? HLWarn : HLDim2
    }
    var statFixCostColor: Color {
        return statFixCost[2] < -1.0 ? HLWarn : HLDim
    }

    // ---------- 状态画像引擎 ----------
    // 用户思路：涨的时候参数是什么，跌的时候参数是什么。
    // 按 K 线数量缓存，避免 SwiftUI 重绘时反复计算。
    private var _spCache: HLStateProfile? = nil
    private var _spKey: String = ""
    private var _spKey2: String = ""

    var stateProf: HLStateProfile {
        // 缓存键同时含 K 线根数与最后两根收盘价：
        // 同一天内刷新时根数不变，仅靠 count 会导致画像不更新
        let k1 = String(candles.count)
        let lc = candles.last?.close ?? 0
        let pc = candles.count > 2 ? candles[candles.count - 2].close : 0
        let k2 = String(format: "%.6f_%.6f", lc, pc)
        if let c = _spCache, _spKey == k1, _spKey2 == k2 { return c }
        let p = HLCore.stateProfile(closes, highs, lows, volumes)
        _spCache = p
        _spKey = k1
        _spKey2 = k2
        return p
    }

    var stateProfName: String { HLCore.stateName(stateProf.state) }

    var stateProfColor: Color {
        if !stateProf.ok { return HLDim2 }
        if stateProf.state == 0 { return HLDown }
        if stateProf.state == 2 { return HLUp }
        return HLWarn
    }

    var stateProfText: String { HLCore.stateProfileText(stateProf) }

    // ---------- 二维状态面板（趋势 × 波动） ----------
    private var _rgCache: HLRegime2D? = nil
    private var _rgKey: String = ""

    var regime2D: HLRegime2D {
        let k = String(candles.count) + "_"
            + String(format: "%.6f", candles.last?.close ?? 0)
        if let c = _rgCache, _rgKey == k { return c }
        let p = HLCore.regime2D(closes, opens, highs, lows, volumes)
        _rgCache = p
        _rgKey = k
        return p
    }

    var regime2DText: String { HLCore.regime2DText(regime2D) }

    var regimeCrossName: String {
        let b = regime2D.crossBest
        if b < 0 || b >= regime2D.cells.count { return "—" }
        return HLCore.stateName(regime2D.cells[b].trend) + "·"
            + (regime2D.cells[b].volLev == 1 ? "高波" : "低波")
    }

    func regimeIsCur(_ k: Int) -> Bool {
        if k < 0 || k >= regime2D.cells.count { return false }
        let cc = regime2D.cells[k]
        return cc.trend == regime2D.curTrend && cc.volLev == regime2D.curVol
    }

    var regimeTsName: String {
        let b = regime2D.tsBest
        if b < 0 || b >= regime2D.cells.count { return "—" }
        return HLCore.stateName(regime2D.cells[b].trend) + "·"
            + (regime2D.cells[b].volLev == 1 ? "高波" : "低波")
    }

    /// IC 符号翻转的指标个数
    var stateFlipCount: Int {
        var n = 0
        for f in stateProf.feats { if f.flip { n += 1 } }
        return n
    }

    // 状态盲指标个数（|效应量| < 0.20，即该指标自己看不见市场在涨还是在跌）
    var stateBlindCount: Int {
        var n = 0
        for f in stateProf.feats { if f.blind { n += 1 } }
        return n
    }

    // 两态后续差（跌态 − 涨态），正 = 历史上本标的「跌透易反弹」
    var stateFwdGap: Double { stateProf.fwdDnAll - stateProf.fwdUpAll }

    var stateFwdGapColor: Color {
        if !stateProf.ok { return HLDim2 }
        return stateFwdGap > 0 ? HLDown : HLUp
    }

    // 非重叠 t 是否推翻了重叠 t 的「显著性」
    var stateNonOverlapWarn: Bool {
        return abs(stateProf.tOverlap) > 2.0 && abs(stateProf.tNonOverlap) <= 2.0
    }

    func dsrOf(_ kind: Int) -> [Double] {
        let nav = HLCore.backtestNAV(closes, kind, opens, 20.0, true, volumes)
        let rets = HLCore.navToRets(nav)
        return HLCore.dsr(rets, trialsCount)
    }

    func evidenceText(_ kind: Int) -> String {
        let nav = HLCore.backtestNAV(closes, kind, opens, 20.0, true, volumes)
        let rets = HLCore.navToRets(nav)
        return HLCore.evidenceText(rets, trialsCount)
    }

    func evidenceColor(_ kind: Int) -> Color {
        let nav = HLCore.backtestNAV(closes, kind, opens, 20.0, true, volumes)
        let rets = HLCore.navToRets(nav)
        let lv = HLCore.evidenceLevel(rets, trialsCount)
        if lv == 2 { return HLUp }
        if lv == 1 { return HLWarn }
        return HLDim2
    }

    // 需要多少交易日的样本才能证明该策略有效
    func minTRLText(_ kind: Int) -> String {
        let r = dsrOf(kind)
        let t = r[2]
        if r[0] <= 0 { return "—" }
        if t > 1e8 { return "无法达到" }
        if t > 100000 { return String(format: "%.0f 万年", t / 244.0 / 10000.0) }
        return String(format: "%.0f 个交易日", t)
    }

    // 噪声门槛：反复试 N 次，纯噪声下期望看到的最大夏普（Bailey & Lopez de Prado）
    func noiseFloorText() -> String {
        var best = 0.0
        var bestSr0 = 0.0
        for i in [0, 7, 8, 9, 11, 12] {
            let r = dsrOf(i)
            if r[0] > best {
                best = r[0]
                bestSr0 = r[3]
            }
        }
        if bestSr0 <= 0 { return "—" }
        let b = String(format: "%.2f", best)
        let s = String(format: "%.2f", bestSr0)
        if best < bestSr0 {
            return "最佳策略夏普 " + b + " < 噪声门槛 " + s
                + "（试 " + String(trialsCount) + " 次）—— 连纯碰运气的期望水平都没到"
        }
        return "最佳策略夏普 " + b + " > 噪声门槛 " + s
            + "（试 " + String(trialsCount) + " 次）—— 超过运气水平"
    }

    // ============ 回测引擎 V2（T+1 + 成本 + 期望值）============
    // kind: 0=买入持有 1=MACD改良版 2=唐奇安突破 3=唐奇安+吊灯止损
    func backtestV2(_ kind: Int, _ p1: Int, _ p2: Int, _ p3: Double) -> [Double] {
        HLCore.backtestV2(opens, highs, lows, closes, kind, p1, p2, p3)
    }

    // V2 策略表：[[名称, kind, p1, p2, p3]]
    var v2Specs: [[Any]] {
        return [
            ["买入持有", 0, 0, 0, 0.0],
            ["MACD 改良版", 1, 0, 0, 0.0],
            ["唐奇安 20/10", 2, 20, 10, 0.0],
            ["唐奇安 55/20", 2, 55, 20, 0.0],
            ["唐奇安20+吊灯2ATR", 3, 20, 22, 2.0],
            ["唐奇安20+吊灯3ATR", 3, 20, 22, 3.0],
            ["唐奇安55+吊灯3ATR", 3, 55, 22, 3.0]
        ]
    }

    func v2Name(_ i: Int) -> String {
        let sp = v2Specs[i]
        return sp[0] as? String ?? "—"
    }

    func v2Row(_ i: Int) -> [Double] {
        let sp = v2Specs[i]
        let k = sp[1] as? Int ?? 0
        let a = sp[2] as? Int ?? 0
        let b = sp[3] as? Int ?? 0
        let c = sp[4] as? Double ?? 0
        return backtestV2(k, a, b, c)
    }

    var v2Count: Int { v2Specs.count }

    // V2 最优：以"回撤调整后收益"排序，且要求期望为正优先
    var v2BestIndex: Int {
        var best = 0
        var bv = -9999.0
        var i = 0
        while i < v2Count {
            let r = v2Row(i)
            // 回撤惩罚权重更高：回撤是散户最难承受的
            let score = r[0] - r[1] * 0.8 + r[4] * 5
            if score > bv { bv = score; best = i }
            i += 1
        }
        return best
    }

    func v2BestName(_ i: Int) -> String { v2Name(i) }

    // 样本量结论
    func sampleVerdict(_ trades: Int) -> String { HLCore.sampleVerdict(trades) }

    // 数据是否够长（用于提示）
    var historyLengthText: String {
        return String(closes.count) + " 根日线"
    }

    var isHistoryEnough: Bool { closes.count >= 500 }

    // 稳健度：mode 0=扫MACD参数 1=扫RSI阈值
    func robust(_ mode: Int) -> [Double] { HLCore.robustness(closes, mode) }

    func robustText(_ mode: Int) -> String { HLCore.robustText(robust(mode)[0]) }

    func robustColor(_ mode: Int) -> Color {
        let lv = robust(mode)[0]
        if lv >= 3 { return HLDown }
        if lv >= 2 { return HLInfo }
        if lv >= 1 { return HLWarn }
        return HLUp
    }

    // 卖出方式对比：固定"RSI<30 买入"，只换卖出规则（15/16/17）
    // 用于分离"卖"的贡献——实测问题主要出在卖出端，不是买入端
    var sellCompareRows: [[Double]] {
        var out: [[Double]] = []
        var k = 15
        while k <= 17 {
            out.append(backtest(k))
            k += 1
        }
        return out
    }

    var sellCompareSpread: Double {
        let r = sellCompareRows
        if r.count < 3 { return 0 }
        var mx = -999.0
        var mn = 999.0
        for x in r {
            let v = (x[0] - 1) * 100
            if v > mx { mx = v }
            if v < mn { mn = v }
        }
        return mx - mn
    }

    var btRows: [[Double]] {
        var out: [[Double]] = []
        var k = 0
        while k <= 17 {
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
    // 委托给 HLCore：避免与云端验证程序出现两份实现（此前两份会算出不同结果）
    // 返回 [独立样本数, 平均%, 上涨率%, 最好, 最差, 平均盈利, 平均亏损, 去重前条数, 重叠率%]
    var similarStats: [Double] {
        return HLCore.similarStats(closes)
    }

    var similarCount: Int { Int(similarStats[0]) }
    var similarAvgRet: Double { similarStats[1] }
    var similarWinRate: Double { similarStats[2] }
    var similarBest: Double { similarStats[3] }
    var similarWorst: Double { similarStats[4] }
    var similarAvgWin: Double { similarStats[5] }
    var similarAvgLoss: Double { similarStats[6] }
    // [7]=去重前取的条数  [8]=被判为重叠而剔除的比例%
    var similarRawCount: Int { similarStats.count > 7 ? Int(similarStats[7]) : 0 }
    var similarOverlapPct: Double { similarStats.count > 8 ? similarStats[8] : 0 }

    // 诚实标注：显示的是去重后的「独立」样本，不是原始条数
    var similarSampleText: String {
        if similarCount == 0 { return "样本不足" }
        let dropped = similarRawCount - similarCount
        if dropped > 0 {
            return "\(similarCount) 个独立样本（剔除 \(dropped) 个重叠）"
        }
        return "\(similarCount) 个独立样本"
    }

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
        let mLo = hfmt(m[1], 3)
        let mMid = hfmt(m[2], 3)
        let mHi = hfmt(m[3], 3)
        return mLo + " ~ " + mHi + "（中位 " + mMid + "）"
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
    var voteBullBearText: String {
        let a = "多头 " + String(voteBull)
        let b = " : " + String(voteBear)
        return a + b + " 空头"
    }
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
    var gridSummaryText: String {
        let a = "最优: " + gridBestText
        let b = " · 默认 MA20/60 排第 " + String(gridDefaultRank)
        return a + b + "/16"
    }
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

    // 重叠校正版：[n, nEff, 均值%, 上涨率%, tRaw, tAdj]
    var redQAdj: [Double] { HLCore.signalQualityAdj(closes, 0) }
    var greenQAdj: [Double] { HLCore.signalQualityAdj(closes, 2) }

    var overlapWarnText: String {
        let r = redQAdj
        let g = greenQAdj
        if r[0] < 5 || g[0] < 5 { return "样本不足" }
        let tR = r[4]; let tG = g[4]; let aR = r[5]; let aG = g[5]
        let rawSig = abs(tG) > 1.96 || abs(tR) > 1.96
        let adjSig = abs(aG) > 1.96 || abs(aR) > 1.96
        if rawSig && !adjSig {
            return "⚠ 未校正时 t=\(hfmt(tG, 2))／\(hfmt(tR, 2)) 看似显著，按有效样本 \(Int(g[1])) 校正后 t=\(hfmt(aG, 2))／\(hfmt(aR, 2))，不再显著 —— 结论不可靠"
        }
        if !rawSig && !adjSig {
            return "校正后 t=\(hfmt(aG, 2))／\(hfmt(aR, 2))，均未达显著线 1.96 —— 本标的信号无统计证据"
        }
        return "校正后 t=\(hfmt(aG, 2))／\(hfmt(aR, 2))，达到显著线"
    }

    var clsHintText: String {
        return HLCore.clsSignalHint(assetClsName)
    }

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

// ===== 设计系统 · 统一色板 =====
func HLColor(_ r: Double, _ g: Double, _ b: Double) -> Color {
    Color(red: r, green: g, blue: b)
}
let HLUp    = HLColor(1.0, 0.30, 0.37)   // 涨·红（A股习惯）
let HLDown  = HLColor(0.0, 0.84, 0.56)   // 跌·绿
let HLWarn  = HLColor(1.0, 0.69, 0.13)   // 警示·黄
let HLInfo  = HLColor(0.30, 0.62, 1.0)   // 信息·蓝
let HLCard2 = HLColor(0.105, 0.122, 0.155)  // 次级卡/内嵌块
let HLLine  = Color.white.opacity(0.07)     // 分隔线

// ===== 设计系统 · 基础组件 =====

// 统一卡片容器
struct HLCardBox<Content: View>: View {
    var title: String = ""
    var subtitle: String = ""
    var content: () -> Content

    init(title: String = "", subtitle: String = "", @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title.isEmpty == false {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(HLText)
                    if subtitle.isEmpty == false {
                        Text(subtitle)
                            .font(.system(size: 9.5))
                            .foregroundColor(HLDim2)
                    }
                    Spacer()
                }
            }
            content()
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(HLCard)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(HLLine, lineWidth: 1))
        )
    }
}

// 分区标题（卡片外）
struct HLSection: View {
    var title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(HLDim2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
            .padding(.top, 2)
    }
}

// 数据行：标签 + 值 + 可选进度可视化
struct HLRow: View {
    var label: String
    var value: String
    var color: Color = HLText
    var ratio: Double? = nil      // 0~1，给值时画底部条
    var barColor: Color = HLInfo

    var body: some View {
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 12.5))
                    .foregroundColor(HLDim)
                Spacer()
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
            }
            if ratio != nil {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(barColor)
                            .frame(width: max(2, geo.size.width * CGFloat(min(max(ratio ?? 0, 0), 1))))
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(.vertical, 4)
    }
}

// 水平指标条（用于 RSI / KDJ / 威廉 等 0~100 指标）
struct HLMeter: View {
    var label: String
    var value: Double
    var text: String
    var lo: Double = 0
    var hi: Double = 100
    var lowZone: Double = 20      // <= 此值 → 超卖色
    var highZone: Double = 80     // >= 此值 → 超买色
    var zones: [(Double, Color)] = []   // 降序分界点 + 颜色，命中即停

    var ratio: Double {
        if hi <= lo { return 0 }
        return (value - lo) / (hi - lo)
    }
    // 若调用方未给 zones，用 lowZone/highZone 自动生成（降序）
    var useZones: [(Double, Color)] {
        if zones.isEmpty == false { return zones }
        return [(highZone, HLWarn), (lowZone, HLInfo), (-9999, HLDown)]
    }
    // 按传入阈值降序，命中第一个即停（避免后面的兜底覆盖前面的判断）
    var color: Color {
        var c = HLInfo
        var i = 0
        while i < useZones.count {
            if value >= useZones[i].0 { c = useZones[i].1; break }
            i += 1
        }
        return c
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.system(size: 11.5))
                    .foregroundColor(HLDim)
                Spacer()
                Text(text)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(color)
                        .frame(width: max(3, geo.size.width * CGFloat(min(max(ratio, 0), 1))))
                    // 中线标记
                    Rectangle().fill(Color.white.opacity(0.25))
                        .frame(width: 1, height: 8)
                        .position(x: geo.size.width * 0.5, y: 3)
                }
            }
            .frame(height: 5)
        }
        .padding(.vertical, 3)
    }
}

// 大数字格
/// 状态画像的单指标行：显示当前值、档位、两态均值与效应量
struct stateFeatRow: View {
    var f: HLFeatStat
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(f.name)
                    .font(.system(size: 10.5))
                    .foregroundColor(HLDim)
                if f.blind {
                    Text("状态盲")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(HLWarn)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(HLWarn.opacity(0.18)))
                }
                Spacer()
                Text(hfmt(f.value, 2))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(HLDim)
            }
            HStack(spacing: 10) {
                Text("涨态 " + hfmt(f.upMean, 2))
                    .font(.system(size: 9))
                    .foregroundColor(HLUp)
                Text("跌态 " + hfmt(f.dnMean, 2))
                    .font(.system(size: 9))
                    .foregroundColor(HLDown)
                Text("d=" + hfmt(f.effD, 2))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(f.blind ? HLWarn : HLDim2)
                Spacer()
            }
            HStack(spacing: 8) {
                Text(f.kind)
                    .font(.system(size: 8.5))
                    .foregroundColor(HLDim2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3).fill(HLCard2))
                Spacer()
                Text("IC 涨 " + hfmt(f.icUp, 2))
                    .font(.system(size: 9))
                    .foregroundColor(HLUp)
                Text("跌 " + hfmt(f.icDn, 2))
                    .font(.system(size: 9))
                    .foregroundColor(HLDown)
                if f.flip {
                    Text("翻转")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(HLWarn)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(HLWarn.opacity(0.18)))
                }
            }
            if f.nUp >= 20 || f.nDn >= 20 {
                HStack(spacing: 10) {
                    Text("同档后续 涨 " + (f.nUp >= 20 ? hfmt(f.fwdUp, 2) : "样本少"))
                        .font(.system(size: 9))
                        .foregroundColor(HLDim2)
                    Text("跌 " + (f.nDn >= 20 ? hfmt(f.fwdDn, 2) : "样本少"))
                        .font(.system(size: 9))
                        .foregroundColor(HLDim2)
                    Spacer()
                }
            }
        }
        .padding(.vertical, 3)
    }
}

/// 二维状态面板的单格：象限名 + 横截面上涨率 + 时序回测收益
struct regimeCellRow: View {
    var f: HLRegimeCell
    var isCur: Bool = false
    var isCross: Bool = false
    var isTs: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(HLCore.stateName(f.trend) + "·" + (f.volLev == 1 ? "高波" : "低波"))
                    .font(.system(size: 10.5, weight: isCur ? .bold : .regular))
                    .foregroundColor(isCur ? HLDim : HLDim2)
                if isCur {
                    Text("当前")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(HLInfo)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(HLInfo.opacity(0.18)))
                }
                if isCross {
                    Text("上涨率最高")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(HLWarn)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(HLWarn.opacity(0.18)))
                }
                if isTs {
                    Text("收益最高")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(HLUp)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(HLUp.opacity(0.18)))
                }
                Spacer()
            }
            HStack(spacing: 10) {
                Text("样本 " + String(f.n) + " 天")
                    .font(.system(size: 9))
                    .foregroundColor(HLDim2)
                Text("上涨率 " + hfmt(f.winRate, 1) + "%")
                    .font(.system(size: 9))
                    .foregroundColor(f.winRate > 55 ? HLUp : HLDim2)
                Text("横截面超额 " + hfmt(f.fwdMean, 2) + "%")
                    .font(.system(size: 9))
                    .foregroundColor(HLDim2)
                Spacer()
            }
            HStack(spacing: 10) {
                Text("时序收益 " + hfmt(f.tsRet, 2) + "%")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(f.tsRet > 0 ? HLUp : HLDown)
                Text("持仓 " + String(f.tsDays) + " 天")
                    .font(.system(size: 9))
                    .foregroundColor(HLDim2)
                Text("进出 " + String(f.tsTrades) + " 次")
                    .font(.system(size: 9))
                    .foregroundColor(HLDim2)
                Spacer()
            }
        }
        .padding(.vertical, 3)
    }
}

struct HLStatCell: View {
    var label: String
    var value: String
    var sub: String = ""
    var color: Color = HLText

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(HLDim2)
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if sub.isEmpty == false {
                Text(sub)
                    .font(.system(size: 9.5))
                    .foregroundColor(HLDim2)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 9).fill(HLCard2))
    }
}

// 状态徽章
struct HLBadge: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(Capsule().fill(color.opacity(0.15)))
            .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 0.8))
    }
}

// 空状态
struct HLEmpty: View {
    var text: String
    var height: CGFloat = 80
    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(HLDim2)
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }
}

// 统一标的头部（简报/信号/专业/计算共用）
struct HLQuoteHeader: View {
    @EnvironmentObject var m: HLModel

    var name: String { m.quote?.name ?? m.curCode }
    var price: String { hfmt(m.lastPrice, HLPrec(m.curCode)) }
    var pct: Double { m.quote?.changePct ?? 0 }
    var chg: Double { m.quote?.change ?? 0 }
    var empty: Bool { m.curCode.isEmpty || m.watch.isEmpty }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(empty ? "未选择标的" : name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(HLText)
                    .lineLimit(1)
                Text(empty ? "去「自选」添加" : m.curCode.uppercased())
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
            }
            Spacer()
            if empty {
                Text("—")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(HLDim2)
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(price)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(hcolor(pct))
                    HStack(spacing: 5) {
                        Text((chg >= 0 ? "+" : "") + hfmt(chg, 4))
                            .font(.system(size: 11.5))
                        Text((pct >= 0 ? "+" : "") + String(format: "%.2f%%", pct))
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundColor(hcolor(pct))
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(HLCard)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(HLLine, lineWidth: 1))
        )
    }
}

func hrow(_ label: String, _ value: String, _ color: Color) -> some View {
    HStack(alignment: .firstTextBaseline) {
        Text(label).font(.system(size: 12.5)).foregroundColor(HLDim)
        Spacer()
        Text(value).font(.system(size: 13, weight: .semibold)).foregroundColor(color)
    }
    .padding(.vertical, 6)
}

// MARK: - 界面

struct HLDepthCard: View {
    @EnvironmentObject var m: HLModel

    var q: HLQuote? { m.quote }
    var hasDepth: Bool { q?.hasDepth ?? false }
    var isFund: Bool { q?.isFund ?? false }

    var buyPct: Double { q?.activeBuyPct ?? 0 }
    var buyColor: Color {
        if buyPct > 55 { return Color(red: 1.0, green: 0.30, blue: 0.37) }
        if buyPct < 45 { return Color(red: 0.0, green: 0.84, blue: 0.56) }
        return HLDim
    }

    func depthRow(_ tag: String, _ p: Double, _ v: Double, _ isAsk: Bool) -> some View {
        HStack(spacing: 8) {
            Text(tag)
                .font(.system(size: 11))
                .foregroundColor(HLDim)
                .frame(width: 34, alignment: .leading)
            Text(p > 0 ? String(format: "%.3f", p) : "—")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isAsk ? Color(red: 1.0, green: 0.30, blue: 0.37)
                                 : Color(red: 0.0, green: 0.84, blue: 0.56))
                .frame(width: 52, alignment: .leading)
            Text(v > 0 ? String(format: "%.0f", v) : "—")
                .font(.system(size: 11))
                .foregroundColor(HLDim2)
            Spacer()
        }
        .padding(.vertical, 1.5)
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("盘口深度 · 券商同款")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(HLDim)
                .frame(maxWidth: .infinity, alignment: .leading)

            if hasDepth == false {
                Text("当前数据源未提供五档（新浪备源无盘口，切回腾讯主源即可）")
                    .font(.system(size: 11))
                    .foregroundColor(HLDim2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 0) {
                        depthRow("卖五", q?.askPrices[4] ?? 0, q?.askVols[4] ?? 0, true)
                        depthRow("卖四", q?.askPrices[3] ?? 0, q?.askVols[3] ?? 0, true)
                        depthRow("卖三", q?.askPrices[2] ?? 0, q?.askVols[2] ?? 0, true)
                        depthRow("卖二", q?.askPrices[1] ?? 0, q?.askVols[1] ?? 0, true)
                        depthRow("卖一", q?.askPrices[0] ?? 0, q?.askVols[0] ?? 0, true)
                    }
                    VStack(spacing: 0) {
                        depthRow("买一", q?.bidPrices[0] ?? 0, q?.bidVols[0] ?? 0, false)
                        depthRow("买二", q?.bidPrices[1] ?? 0, q?.bidVols[1] ?? 0, false)
                        depthRow("买三", q?.bidPrices[2] ?? 0, q?.bidVols[2] ?? 0, false)
                        depthRow("买四", q?.bidPrices[3] ?? 0, q?.bidVols[3] ?? 0, false)
                        depthRow("买五", q?.bidPrices[4] ?? 0, q?.bidVols[4] ?? 0, false)
                    }
                }

                VStack(spacing: 5) {
                    hrow("委差", q?.weichaText ?? "—",
                         (q?.weicha ?? 0) > 0 ? Color(red: 1.0, green: 0.30, blue: 0.37) : Color(red: 0.0, green: 0.84, blue: 0.56))
                    hrow("外盘 主动买", q?.outerText ?? "—", Color(red: 1.0, green: 0.30, blue: 0.37))
                    hrow("内盘 主动卖", q?.innerText ?? "—", Color(red: 0.0, green: 0.84, blue: 0.56))
                    HStack {
                        Text("主动买占比")
                            .font(.system(size: 12.5))
                            .foregroundColor(HLDim)
                        Spacer()
                        Text(String(format: "%.1f%%", buyPct))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(buyColor)
                    }
                    .padding(.vertical, 6)
                }

                if isFund {
                    VStack(spacing: 5) {
                        hrow("IOPV 净值", q?.iopvText ?? "—", HLText)
                        hrow("溢价率", q?.premiumText ?? "—",
                             (q?.premium ?? 0) > 0.5 ? Color(red: 1.0, green: 0.69, blue: 0.13) : HLDim)
                        hrow("总份额", q?.shareText ?? "—", HLDim)
                    }
                    .padding(.top, 4)
                }

                Text("溢价率为正＝买贵了；为负＝折价。ETF 可申赎，溢价高时追入会先亏一道。")
                    .font(.system(size: 9.5))
                    .foregroundColor(HLDim2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))
    }
}

struct HLFlowCard: View {
    @EnvironmentObject var m: HLModel

    var st: HLFlowStat { HLCore.tickFlow(m.ticks) }
    var vwap: Double { HLCore.tickVwap(m.ticks) }
    var price: Double { m.quote?.price ?? 0 }
    var tail: HLFlowStat { HLCore.tickTailFlow(m.ticks, 870) }
    var diverged: Bool { HLCore.flowDivergence(st, 500000.0) == 1 }
    var verdict: String { HLCore.flowVerdictText(st, vwap, price) }

    var buyColor: Color {
        if st.buyRatio > 55 { return HLUp }
        if st.buyRatio < 45 { return HLDown }
        return HLDim
    }
    var barRatio: Double {
        let r = st.buyRatio / 100.0
        if r < 0 { return 0 }
        if r > 1 { return 1 }
        return r
    }
    var buyRatioText: String { String(format: "%.1f%%", st.buyRatio) }
    var vwapText: String { String(format: "%.4f", vwap) }
    var countText: String { String(st.count) + " 笔" }
    var bigText: String { String(st.bigCount) + " 笔" }
    var buyAmtText: String { "主动买 " + amtText(st.buyAmt) }
    var sellAmtText: String { "主动卖 " + amtText(st.sellAmt) }
    var netAmtText: String { netText(st.netAmt) }
    var tailRowText: String { netText(tail.netAmt) + " · " + String(tail.count) + " 笔" }
    var vwapColor: Color { price > vwap ? HLUp : HLDown }

    func amtText(_ v: Double) -> String {
        let a = abs(v)
        if a >= 100000000.0 { return String(format: "%.2f亿", v / 100000000.0) }
        if a >= 10000.0 { return String(format: "%.0f万", v / 10000.0) }
        return String(format: "%.0f", v)
    }

    func netText(_ v: Double) -> String {
        if v > 0 { return "+" + amtText(v) }
        return amtText(v)
    }

    func netColor(_ v: Double) -> Color {
        if v > 0 { return HLUp }
        if v < 0 { return HLDown }
        return HLDim
    }

    func netRow(_ tag: String, _ v: Double, _ hint: String) -> some View {
        HStack(spacing: 8) {
            Text(tag)
                .font(.system(size: 11))
                .foregroundColor(HLDim)
                .frame(width: 50, alignment: .leading)
            Text(netText(v))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(netColor(v))
            Spacer()
            Text(hint)
                .font(.system(size: 9.5))
                .foregroundColor(HLDim2)
        }
        .padding(.vertical, 2)
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("分时逐笔资金流 · 逐笔还原")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(HLDim)
                .frame(maxWidth: .infinity, alignment: .leading)

            if st.count == 0 {
                Text("暂无逐笔数据。非交易时段或该标的无分时明细时可为空，盘中刷新即可获取。")
                    .font(.system(size: 11))
                    .foregroundColor(HLDim2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(buyAmtText)
                            .font(.system(size: 11.5))
                            .foregroundColor(HLUp)
                        Text(sellAmtText)
                            .font(.system(size: 11.5))
                            .foregroundColor(HLDown)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(netAmtText)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(netColor(st.netAmt))
                        Text("净额")
                            .font(.system(size: 9.5))
                            .foregroundColor(HLDim2)
                    }
                }

                VStack(spacing: 5) {
                    HStack {
                        Text("主动买占比")
                            .font(.system(size: 12))
                            .foregroundColor(HLDim)
                        Spacer()
                        Text(buyRatioText)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(buyColor)
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(HLCard2).frame(height: 6)
                            Rectangle().fill(buyColor)
                                .frame(width: barRatio * g.size.width, height: 6)
                        }
                        .cornerRadius(3)
                    }
                    .frame(height: 6)
                }

                VStack(spacing: 2) {
                    netRow("超大单", st.xlNet, "≥100万")
                    netRow("大单", st.lgNet, "20~100万")
                    netRow("中单", st.mdNet, "4~20万")
                    netRow("小单", st.smNet, "<4万")
                }
                .padding(.top, 2)

                VStack(spacing: 0) {
                    hrow("笔数", countText, HLDim)
                    hrow("超大单笔数", bigText, HLDim)
                    if vwap > 0 {
                        hrow("真实 VWAP", vwapText, vwapColor)
                    }
                    if tail.count > 0 {
                        hrow("尾盘 14:30 后", tailRowText, netColor(tail.netAmt))
                    }
                }

                if diverged {
                    Text("⚠ 超大单与大单方向相反，机构内部有分歧，勿单边解读")
                        .font(.system(size: 10))
                        .foregroundColor(HLWarn)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(verdict)
                    .font(.system(size: 10))
                    .foregroundColor(HLDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("与盘口「内外盘」不同：此处按逐笔成交额还原。ETF 上主要反映申赎与套利盘，个股上才近似主力资金。")
                    .font(.system(size: 9.5))
                    .foregroundColor(HLDim2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))
    }
}

struct HLMacdCompareCard: View {
    @EnvironmentObject var m: HLModel

    var body: some View {
        VStack(spacing: 10) {
            Text("MACD 两种用法 · 实测对比")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(HLDim)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("原版 红买绿卖")
                        .font(.system(size: 10.5))
                        .foregroundColor(HLDim2)
                    Text("柱>0 就买")
                        .font(.system(size: 9.5))
                        .foregroundColor(HLDim2)
                    Text(m.macdRawText)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(m.macdRawColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.04)))

                VStack(alignment: .leading, spacing: 4) {
                    Text("改良版")
                        .font(.system(size: 10.5))
                        .foregroundColor(HLDim2)
                    Text("柱>0 且 DIF>0")
                        .font(.system(size: 9.5))
                        .foregroundColor(HLDim2)
                    Text(m.macdImprovedText)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(m.macdImprovedColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.04)))
            }

            hrow("DIF 距零轴", hfmt(m.macdGapToZero > 0 ? m.macdGapToZero : nil, 4), HLDim)

            Text(m.macdAdvice)
                .font(.system(size: 11))
                .foregroundColor(HLText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color(red: 1.0, green: 0.69, blue: 0.13).opacity(0.12)))

            Text("改良版只多了一个条件：红柱出现时，DIF 必须已在零轴上方。它的价值在于压缩回撤与交易频率，把大部分下跌期挡在场外。具体数字见下方「策略实验室」，以实时回测为准——不同历史长度会得出不同结论。")
                .font(.system(size: 9.5))
                .foregroundColor(HLDim2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))
    }
}

// 价格显示精度：ETF/基金 3 位小数，个股 2 位
// 换标的时若沿用固定 3 位，个股会出现 1400.330 这种错误显示
func HLPrec(_ full: String) -> Int {
    let c = full.replacingOccurrences(of: "sh", with: "")
                 .replacingOccurrences(of: "sz", with: "")
                 .replacingOccurrences(of: "bj", with: "")
    if c.hasPrefix("5") { return 3 }   // 沪市 ETF/LOF
    if c.hasPrefix("1") { return 3 }   // 深市 ETF/LOF
    if c.hasPrefix("6") { return 2 }   // 沪市个股
    if c.hasPrefix("688") { return 2 } // 科创板
    if c.hasPrefix("0") { return 2 }   // 深市主板/中小板
    if c.hasPrefix("3") { return 2 }   // 创业板
    if c.hasPrefix("8") { return 2 }   // 北交所
    if c.hasPrefix("4") { return 2 }
    return 3
}

// 涨跌停幅度：创业板/科创板 ±20%，其余 ±10%（ST 为 ±5%，接口已直接返回涨跌停价）
func HLLimitPct(_ full: String) -> Double {
    let c = full.replacingOccurrences(of: "sh", with: "")
                 .replacingOccurrences(of: "sz", with: "")
                 .replacingOccurrences(of: "bj", with: "")
    if c.hasPrefix("3") { return 20.0 }
    if c.hasPrefix("688") { return 20.0 }
    if c.hasPrefix("689") { return 20.0 }
    return 10.0
}

// Optional<Double> → Double 便捷解包（普通函数，不在 ViewBuilder 内声明 let）
func HLV(_ v: Double?) -> Double { v ?? 0 }

// 灯副标题文案（普通函数，避免在 ViewBuilder 内声明 let）
func HLSignalSubText(_ m: HLModel) -> String {
    let p = m.lastPrice
    if p <= 0 { return "等待数据" }
    if m.nextYellow != nil && m.nextGreen != nil {
        return "变黄需到 " + hfmt(m.nextYellow, 4) + " · 变绿需到 " + hfmt(m.nextGreen, 4)
    }
    return "等待历史数据计算门槛" 
}

// 灯的操作文案：结合「本标的上择时是否有效」给出不同建议
// 同样一个红灯，在适配的标的上是纪律，在不适配的标的上可能只是踏空
func HLAdaptiveAction(_ m: HLModel) -> String {
    let base = m.signal.action
    let f = m.strategyFitEx()
    if f.trades == 0 { return base }
    if m.signal == .green { return base }
    if f.fit {
        return base + "（本标的择时风险调整后有效：夏普改善 " + hfmt(f.dSharpe, 3) + "，纪律可执行）"
    }
    return base + "（本标的择时风险调整后为负：夏普改善 " + hfmt(f.dSharpe, 3) + "，信号仅供参考，勿据此频繁进出）"
}

// 关键价位四宫格
struct HLKeyLevels: View {
    @EnvironmentObject var m: HLModel

    var p: Double { m.lastPrice }

    var body: some View {
        HLCardBox(title: "关键价位", subtitle: "每日自动重算") {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    HLStatCell(label: "现价", value: hfmt(p, 3),
                               sub: "涨跌 " + hfmtPct(m.quote?.changePct),
                               color: hcolor(m.quote?.changePct))
                    HLStatCell(label: "变黄需到", value: hfmt(m.nextYellow, 4),
                               sub: gapText(m.nextYellow), color: HLWarn)
                }
                HStack(spacing: 8) {
                    HLStatCell(label: "变绿需到", value: hfmt(m.nextGreen, 4),
                               sub: gapText(m.nextGreen), color: HLDown)
                    HLStatCell(label: "止损参考", value: hfmt(m.stopLoss, 4),
                               sub: gapText(m.stopLoss), color: HLUp)
                }
            }
        }
    }

    func gapText(_ target: Double?) -> String {
        if p <= 0 { return "—" }
        if target == nil { return "—" }
        if target! <= 0 { return "—" }
        let d = (target! - p) / p * 100
        let sign = d >= 0 ? "+" : ""
        return "距现价 " + sign + String(format: "%.2f%%", d)
    }
}

// MARK: - 自适应方案卡（两段一致性 + 置信度 + 反转风险）
struct HLAdaptiveCard: View {
    @EnvironmentObject var m: HLModel

    var a: [Double] { m.adaptive }
    var enough: Bool { m.closes.count >= 200 }

    var modeColor: Color {
        if a[0] > 0.5 { return HLUp }
        if a[0] < 0.5 { return HLInfo }
        return HLWarn
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text("自适应方案 · 本标的")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(HLDim)
                Spacer()
                HLBadge(text: enough ? m.adaptiveMode : "数据不足",
                        color: enough ? modeColor : HLDim)
            }

            if enough == false {
                Text("需要至少 200 个交易日才能做前后段检验")
                    .font(.system(size: 11.5))
                    .foregroundColor(HLDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // 置信度条
                HStack(spacing: 7) {
                    Text("置信度")
                        .font(.system(size: 11))
                        .foregroundColor(HLDim)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(HLLine).frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(a[1] >= 90 ? HLUp : HLWarn)
                            .frame(width: max(2, CGFloat(a[1] / 100.0) * 150), height: 6)
                    }
                    .frame(width: 150)
                    Text(String(format: "%.0f%%", a[1]))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(a[1] >= 90 ? HLUp : HLWarn)
                    Spacer()
                }

                // 前后段对照
                VStack(spacing: 4) {
                    segRow("前 60%（判断段）", a[2], a[3])
                    segRow("后 40%（验证段）", a[4], a[5])
                    Divider().background(HLLine)
                    segRow("全样本", a[6], a[7])
                }
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 9).fill(HLCard2))

                Text(m.isLowVol ? "判定依据 · 回撤改善（波动过低，夏普不可用）" : "判定依据 · 夏普改善")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(HLInfo)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 4) {
                    hrow("前段夏普改善", hfmt(m.isDSharpe, 3), hcolor(m.isDSharpe))
                    hrow("后段夏普改善", hfmt(m.oosDSharpe, 3), hcolor(m.oosDSharpe))
                    Divider().background(HLLine)
                    hrow("全样本夏普改善", hfmt(m.fullDSharpe, 3), hcolor(m.fullDSharpe))
                    hrow("全样本回撤改善", hfmt(m.fullDDD * 100, 1) + " 个点", hcolor(m.fullDDD * 100))
                    hrow("平均持仓比例", hfmt(m.fullExposure * 100, 1) + "%", HLDim)
                }
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 9).fill(HLCard2))

                Text(m.adaptiveAdvice)
                    .font(.system(size: 11.5))
                    .foregroundColor(modeColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
                    .background(RoundedRectangle(cornerRadius: 9).fill(modeColor.opacity(0.11)))

                Text(m.adaptiveConfText)
                    .font(.system(size: 10.5))
                    .foregroundColor(HLDim2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HLCardBox(title: "前瞻检验（只用前段判断，后段验证）", subtitle: "仅用前段下判断，后段检验是否成立") {
                    Text(m.forwardText)
                        .font(.system(size: 11))
                        .foregroundColor(m.forwardHit ? HLUp : HLWarn)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("57 个标的实测：仅用前段判断，后段能验证的只有 52.6%；前段超额与后段超额相关性 r = 0.068（约等于无关）。换成夏普口径命中率 47.4%，更低。历史表现不能预测未来表现。")
                        .font(.system(size: 10.5))
                        .foregroundColor(HLDim2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 5)
                }

                if m.adaptiveReverseRisk {
                    Text("⚠ 反转风险：此标的出现过『前段涨、后段跌』。这类标的历史规律最容易在趋势切换时失效，不要把上面的结论当保证。")
                        .font(.system(size: 11))
                        .foregroundColor(HLWarn)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9)
                        .background(RoundedRectangle(cornerRadius: 9).fill(HLWarn.opacity(0.10)))
                }

                Text("做法说明：不调参数。实证显示『按历史挑最优参数』在未见数据上胜率仅 41.7%（不如抛硬币），所以本引擎只判断该不该择时，并诚实标注置信度。")
                    .font(.system(size: 10.5))
                    .foregroundColor(HLDim2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(HLCard)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(HLLine, lineWidth: 1))
        )
    }

    func segRow(_ title: String, _ t: Double, _ b: Double) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(HLDim)
                .frame(width: 108, alignment: .leading)
            Text("择时 " + hfmtPct(t))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(hcolor(t))
            Spacer()
            Text("持有 " + hfmtPct(b))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(hcolor(b))
            Spacer()
            Text(t > b ? "择时优" : "持有优")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(t > b ? HLUp : HLDim)
        }
    }
}

// MARK: - 同类离散度卡片（结论可否外推）
// 实测（57 标的 × 801 日）同类内部超额极差：
//   债券 1.6 < 港股 16.4 < 商品 31.7 < 海外 44.2 < 宽基 51.5 < 行业 123.8 < 个股 204.7
// 除港股与债券外，同类内部差异都很大 —— 单个标的的历史结论不可外推。
struct HLPeerCard: View {
    @EnvironmentObject var m: HLModel

    var peerOK: Bool { m.peerDone && m.peerStat.n >= 2 }

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text("同类离散度 · 可否外推")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(HLDim)
                Spacer()
                if m.peerLoading {
                    ProgressView().scaleEffect(0.8)
                } else if m.peerDone && m.peerStat.n >= 2 {
                    HLBadge(text: m.peerHighSpread ? "不可外推" : "可参考",
                            color: m.peerHighSpread ? HLWarn : HLUp)
                }
            }

            Button(action: { m.loadPeers() }) {
                Text(m.peerLoading ? "正在拉取同类…" : (m.peerDone ? "重新计算" : "计算同类离散度"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(m.peerLoading ? HLDim2 : HLInfo)
                    )
            }
            .disabled(m.peerLoading)

            if m.peerDone && peerOK {
                hrow("同类标的数", String(m.peerStat.n) + " 个", HLDim)
                hrow("最好（超额）", hfmtPct(m.peerStat.max), hcolor(m.peerStat.max))
                hrow("最差（超额）", hfmtPct(m.peerStat.min), hcolor(m.peerStat.min))
                hrow("极差", hfmt(m.peerStat.spread, 1) + " 个点",
                     m.peerHighSpread ? HLWarn : HLDim)
                hrow("标准差", hfmt(m.peerStat.sd, 1) + " 个点", HLDim)

                if m.peerHighSpread {
                    Text("⚠ 同为「" + HLCore.assetClassName(HLCore.assetClass(m.curCode))
                         + "」的 " + String(m.peerStat.n) + " 个标的，超额最多相差 " + hfmt(m.peerStat.spread, 1)
                         + " 个点（最好 " + hfmtPct(m.peerStat.max) + "，最差 " + hfmtPct(m.peerStat.min)
                         + "）。连同类内部都不能互相印证，本标的的结论只适用于它自己，不要套用到别的标的。")
                        .font(.system(size: 11))
                        .foregroundColor(HLWarn)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9)
                        .background(RoundedRectangle(cornerRadius: 9).fill(HLWarn.opacity(0.10)))
                }
            } else if m.peerDone {
                Text("同类数据不足，无法计算。请确认网络后重试。")
                    .font(.system(size: 11))
                    .foregroundColor(HLDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("拉取同类参照标的后计算。性质是「参照组」不是「基准」——不参与任何信号判定，只用于提示结论可否外推。")
                    .font(.system(size: 10.5))
                    .foregroundColor(HLDim2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(HLCard)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(HLLine, lineWidth: 1))
        )
    }
}

// MARK: - 策略适配度卡片（风险口径：平均仓位仅 40.2%，本策略本质是削 beta 而非提高收益）
struct HLFitnessCard: View {
    @EnvironmentObject var m: HLModel

    var f: HLCore.HLFitResult { m.strategyFitEx() }

    var p: (vol: Double, er: Double, dd: Double) { m.profileStats() }

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text("策略适配度 · 风险口径")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(HLDim)
                Spacer()
                HLBadge(text: badgeText, color: badgeColor)
            }

            Text("主判定")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(HLInfo)
                .frame(maxWidth: .infinity, alignment: .leading)

            hrow("夏普改善（择时−持有）", hfmt(f.dSharpe, 3), hcolor(f.dSharpe))
            hrow("最大回撤改善", hfmt(f.dDD * 100, 1) + " 个点", hcolor(f.dDD * 100))
            hrow("平均持仓比例", hfmt(f.exposure * 100, 1) + "%", HLDim)

            if f.lowVol {
                Text("⚠ 年化波动仅 " + hfmt(f.volH * 100, 1)
                     + "%，夏普分母趋近 0 不可靠，已改用回撤改善判定")
                    .font(.system(size: 11))
                    .foregroundColor(HLWarn)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
                    .background(RoundedRectangle(cornerRadius: 9).fill(HLWarn.opacity(0.10)))
            }

            Text(m.fitVerdict())
                .font(.system(size: 11.5))
                .foregroundColor(f.fit ? HLUp : HLWarn)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill((f.fit ? HLUp : HLWarn).opacity(0.11))
                )

            Divider().background(HLLine)

            Text("参考项 · 收益口径（不用于判定）")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(HLDim)
                .frame(maxWidth: .infinity, alignment: .leading)

            hrow("择时策略收益", hfmtPct(f.timing * 100), hcolor(f.timing * 100))
            hrow("一直持有收益", hfmtPct(f.hold * 100), hcolor(f.hold * 100))
            hrow("超额（择时−持有）", hfmtPct(f.excess * 100), hcolor(f.excess * 100))
            hrow("回测交易次数", String(f.trades) + " 次", HLDim)

            if f.warnTrades {
                Text("⚠ 交易 " + String(f.trades)
                     + " 次。实测 ≥70 笔的标的平均超额 −27.3 个点，<60 笔的 +33.9 个点，交易越频繁越差")
                    .font(.system(size: 11))
                    .foregroundColor(HLWarn)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
                    .background(RoundedRectangle(cornerRadius: 9).fill(HLWarn.opacity(0.10)))
            }

            Divider().background(HLLine)

            Text("标的档案")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(HLDim)
                .frame(maxWidth: .infinity, alignment: .leading)

            hrow("年化波动率", hfmt(p.vol, 1) + "%", HLDim)
            hrow("趋势效率 ER", hfmt(p.er, 2), HLDim)
            hrow("历史最大回撤", hfmt(p.dd, 1) + "%", HLDown)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(HLCard)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(HLLine, lineWidth: 1))
        )
    }

    var badgeText: String {
        if f.trades == 0 { return "数据不足" }
        if f.lowVol { return f.fit ? "回撤改善" : "回撤未改善" }
        return f.fit ? "风险调整有效" : "风险未改善"
    }

    var badgeColor: Color {
        if f.trades == 0 { return HLDim }
        return f.fit ? HLUp : HLWarn
    }
}

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

                // 统一标的头部
                HLQuoteHeader()

                // 灯
                VStack(spacing: 11) {
                    HStack(spacing: 13) {
                        ZStack {
                            Circle()
                                .fill(m.signal.color.opacity(0.18))
                                .frame(width: 66, height: 66)
                            Circle()
                                .stroke(m.signal.color.opacity(0.45), lineWidth: 2)
                                .frame(width: 66, height: 66)
                            Circle()
                                .fill(m.signal.color)
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Text(m.signal.title)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                )
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(m.signal.title + "灯")
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundColor(HLText)
                                HLBadge(text: m.signal.desc, color: m.signal.color)
                            }
                            Text(HLSignalSubText(m))
                                .font(.system(size: 11))
                                .foregroundColor(HLDim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    Text(HLAdaptiveAction(m))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(m.signal.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(11)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(m.signal.color.opacity(0.13))
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .stroke(m.signal.color.opacity(0.3), lineWidth: 0.8))
                        )
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(HLCard)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(HLLine, lineWidth: 1))
                )

                // 策略适配度（先看这套逻辑在本标的上有没有效）
                HLFitnessCard()

                // 自适应方案（两段一致性检验 + 置信度）
                HLAdaptiveCard()

                // 同类离散度：单个标的的结论能否外推
                HLPeerCard()

                // 关键价位四宫格
                HLKeyLevels()

                // 实时盘口
                VStack(spacing: 6) {
                    Text("实时盘口")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    hrow("现价", hfmt(m.lastPrice, HLPrec(m.curCode)), HLText)
                    hrow("涨跌幅", hfmtPct(m.quote?.changePct), hcolor(m.quote?.changePct))
                    hrow("涨跌额", hfmt(m.quote?.change, 4), hcolor(m.quote?.change))
                    hrow("今开", hfmt(m.quote?.open, HLPrec(m.curCode)), HLText)
                    hrow("最高", hfmt(m.quote?.high, HLPrec(m.curCode)), Color(red: 1.0, green: 0.30, blue: 0.37))
                    hrow("最低", hfmt(m.quote?.low, HLPrec(m.curCode)), Color(red: 0.0, green: 0.84, blue: 0.56))
                    hrow("昨收", hfmt(m.quote?.preClose, HLPrec(m.curCode)), HLDim)
                    hrow("成交量", m.quote?.volumeText ?? "—", HLDim)
                    hrow("成交额", m.quote?.amountText ?? "—", HLDim)
                    hrow("均价", m.quote?.avgPriceText ?? "—", HLDim)
                    hrow("涨停价", hfmt(m.quote?.limitUp, HLPrec(m.curCode)), Color(red: 1.0, green: 0.30, blue: 0.37))
                    hrow("跌停价", hfmt(m.quote?.limitDown, HLPrec(m.curCode)), Color(red: 0.0, green: 0.84, blue: 0.56))
                    hrow("换手率", hfmtPct(m.quote?.turnover), HLDim)
                    hrow("量比", hfmt(m.quote?.volRatio, 2), HLDim)
                    hrow("振幅", hfmtPct(m.quote?.amplitude), HLDim)
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                // 券商 App 同款：盘口深度
                HLDepthCard()
                HLFlowCard()

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
        .refreshable { m.refreshAll() }
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

struct HLAllocCard: View {
    @EnvironmentObject var m: HLModel

    var body: some View {
        VStack(spacing: 9) {
            Text("跨资产对照")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(HLDim)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("同一窗口内各类资产的真实表现。用途是检验「是否不该只持有当前标的」——若其他资产持续更强，问题不在择时，在选品。")
                .font(.system(size: 10))
                .foregroundColor(HLDim2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if m.poolMom(126).count > 0 {
                VStack(spacing: 4) {
                    Text("近6个月动量排名")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(HLText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(0..<m.poolMom(126).count, id: \.self) { i in
                        HStack(spacing: 8) {
                            Text(m.poolName(m.poolMom(126)[i].0))
                                .font(.system(size: 12))
                                .foregroundColor(m.poolMom(126)[i].0 == m.curCode ? HLAccent : HLText)
                            Spacer()
                            Text(hfmtPct(m.poolMom(126)[i].1))
                                .font(.system(size: 12))
                                .foregroundColor(m.poolMom(126)[i].1 >= 0 ? HLUp : HLDown)
                        }
                    }
                }
            }

            if m.poolCodes.count > 1 {
                VStack(spacing: 4) {
                    Text("与当前标的的相关性（越低越分散）")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(HLText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(0..<m.poolCodes.count, id: \.self) { i in
                        HStack(spacing: 8) {
                            Text(m.poolName(m.poolCodes[i]))
                                .font(.system(size: 12))
                                .foregroundColor(HLText)
                            Spacer()
                            Text(hfmt(m.poolCorr(m.curCode, m.poolCodes[i]), 2))
                                .font(.system(size: 12))
                                .foregroundColor(HLDim)
                        }
                    }
                }
            }

            VStack(spacing: 4) {
                Text("双动量结论（须跑赢现金才持有）")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(HLText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(m.allocPickText)
                    .font(.system(size: 12))
                    .foregroundColor(m.allocPickCode == "CASH" ? HLWarn : HLText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("对照仅为历史事实陈述，不构成调仓建议。债券与货币ETF的价格序列未含分红，其收益被低估。")
                .font(.system(size: 10))
                .foregroundColor(HLDim2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))
    }
}

struct HLWatchView: View {
    @EnvironmentObject var m: HLModel
    @State var input: String = ""
    @State var msg: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HLQuoteHeader()

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
                    if m.watch.isEmpty {
                        VStack(spacing: 7) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 26))
                                .foregroundColor(HLAccent.opacity(0.8))
                            Text("还没有添加任何标的")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(HLText)
                            Text("在下方输入 6 位代码添加，例如 510300、518880、600519\n添加后会自动保存，下次打开还在")
                                .font(.system(size: 11.5))
                                .foregroundColor(HLDim)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                if m.watch.isEmpty == false {
                    HLAllocCard()

                    HLPortfolioCard()
                }

                VStack(spacing: 8) {
                    Text("添加标的")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        TextField("6位代码，如 510300", text: $input)
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
                        Text(msg).font(.system(size: 11)).foregroundColor(HLWarn)
                    }
                    if m.addNote.isEmpty == false {
                        Text(m.addNote)
                            .font(.system(size: 11))
                            .foregroundColor(HLText)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("支持 ETF / 个股 / 指数。沪市 6 位以 5、6、9 开头，深市以 0、3 开头，北交所以 4、8 开头")
                        .font(.system(size: 10.5))
                        .foregroundColor(HLDim2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                VStack(spacing: 8) {
                    hrow("当前标的", m.curCode.isEmpty ? "未选择" : m.curCode, HLDim)
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
        .refreshable { m.refreshAll() }
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
        msg = ""
        input = ""
    }
}

// MARK: - 前瞻信号面板（57 标的 × 801 根 K 线实证分层）

struct HLForwardCard: View {
    @EnvironmentObject var m: HLModel

    var f: [Double] { m.forwardSig }
    var ok: Bool { f[1] > 0.5 }

    var verdictColor: Color {
        let w = f[14]
        if w < 0.5 { return Color(red: 0.0, green: 0.84, blue: 0.56) }
        if w < 1.5 { return Color(red: 1.0, green: 0.30, blue: 0.37) }
        if w < 2.5 { return Color(red: 0.60, green: 0.60, blue: 0.70) }
        return Color(red: 1.0, green: 0.69, blue: 0.13)
    }

    var dropColor: Color {
        let p = f[2]
        if p >= 20 { return Color(red: 1.0, green: 0.30, blue: 0.37) }
        if p >= 15 { return Color(red: 1.0, green: 0.69, blue: 0.13) }
        return HLDim
    }

    var upColor: Color {
        let p = f[6]
        if p < 35 { return Color(red: 1.0, green: 0.30, blue: 0.37) }
        if p < 45 { return Color(red: 1.0, green: 0.69, blue: 0.13) }
        return HLText
    }

    var volText: String {
        return hfmt(f[0], 1) + "% · Q" + String(Int(f[1]))
    }

    var dropText: String {
        return hfmt(f[2], 1) + "%"
    }

    var absText: String {
        return hfmt(f[3], 2) + "%"
    }

    var devText: String {
        return hfmt(f[4], 2) + "% · Q" + String(Int(f[5]))
    }

    var upText: String {
        return hfmt(f[6], 1) + "%"
    }

    var eventText: String {
        let nm = HLCore.forwardEventName(f[15])
        if f[15] < 0.5 { return nm }
        return nm + " · 上涨率 " + hfmt(f[13], 1) + "%"
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("前瞻信号")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(HLDim)
                Spacer()
                Text(HLCore.forwardVerdict(f))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(verdictColor))
            }

            if ok == false {
                Text("历史数据不足（需 130 根以上 K 线）")
                    .font(.system(size: 11))
                    .foregroundColor(HLDim2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                hrow("当期 20 日年化波动", volText, HLText)
                hrow("未来 20 日跌超 5% 概率", dropText, dropColor)
                hrow("未来 20 日平均绝对波动", absText, HLDim)
                hrow("当前价格偏离 MA60", devText, HLText)
                hrow("未来 60 日上涨概率", upText, upColor)
                hrow("极端事件", eventText, HLText)

                VStack(alignment: .leading, spacing: 3) {
                    Text("提示")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(verdictColor)
                    Text(HLCore.forwardWarnText(f[14]))
                        .font(.system(size: 10.5))
                        .foregroundColor(HLText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 9).fill(verdictColor.opacity(0.12)))

                Text("分层依据 57 个标的 × 801 根 K 线、标的内去均值后的历史统计。它能预判的是「风险大小」和「位置是否偏高」，不是涨跌方向。")
                    .font(.system(size: 9.5))
                    .foregroundColor(HLDim2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))
    }
}

// MARK: - 日报（生成 / 复制 / 分享）

struct HLShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct HLReportSheet: View {
    @EnvironmentObject var m: HLModel
    @Environment(\.presentationMode) var pm
    @State private var copied: Bool = false
    @State private var showShare: Bool = false

    var text: String { m.dailyReport }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(text)
                        .font(.system(size: 11))
                        .foregroundColor(HLText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(HLCard))

                    HStack(spacing: 10) {
                        Button(action: {
                            UIPasteboard.general.string = text
                            copied = true
                        }) {
                            Text(copied ? "已复制到剪贴板" : "复制全文")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: 10)
                                    .fill(copied ? Color(red: 0.0, green: 0.84, blue: 0.56) : Color(red: 0.20, green: 0.50, blue: 0.95)))
                        }
                        Button(action: { showShare = true }) {
                            Text("分享 / 导出")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(red: 0.30, green: 0.33, blue: 0.40)))
                        }
                    }

                    Text("日报内容由实时数据生成，每次打开重新计算。可粘贴到备忘录、微信或邮件归档，形成你自己的决策轨迹。")
                        .font(.system(size: 10))
                        .foregroundColor(HLDim2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
            }
            .background(Color(red: 0.043, green: 0.051, blue: 0.071))
            .navigationTitle("每日决策日报")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { pm.wrappedValue.dismiss() }
                }
            }
            .sheet(isPresented: $showShare) {
                HLShareSheet(items: [text])
            }
        }
    }
}

// MARK: - 波动率环境（VIX 官方 + 纳指/标普已实现波动代理）

struct HLVixCard: View {
    @EnvironmentObject var m: HLModel

    var v: HLVixSnap { m.vix }

    var regimeColor: Color {
        let r = v.regime
        if r < 0 { return HLDim }
        if r == 0 { return Color(red: 0.0, green: 0.84, blue: 0.56) }
        if r == 1 { return HLText }
        if r == 2 { return Color(red: 1.0, green: 0.69, blue: 0.13) }
        return Color(red: 1.0, green: 0.30, blue: 0.37)
    }

    var vixChgText: String {
        if v.vixOK == false { return "—" }
        let sgn = v.vixChg >= 0 ? "+" : ""
        return hfmt(v.vix, 2) + "  " + sgn + hfmt(v.vixChg, 2) + " (" + hfmt(v.vixPctChg, 2) + "%)"
    }

    var ndxText: String {
        if v.ndxOK == false { return "—" }
        return hfmt(v.ndxVol, 2) + "% · " + v.ndxPctlName + " " + hfmt(v.ndxPctl, 0) + "%"
    }

    var spxText: String {
        if v.spxOK == false { return "—" }
        return hfmt(v.spxVol, 2) + "% · " + v.spxPctlName + " " + hfmt(v.spxPctl, 0) + "%"
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("波动率环境")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(HLDim)
                Spacer()
                Text(v.regimeName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(regimeColor))
            }

            if v.ready == false {
                Text(v.loading ? "正在获取波动率数据…" : v.note)
                    .font(.system(size: 11))
                    .foregroundColor(HLDim2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                hrow("VIX 恐慌指数", vixChgText, v.vixChg >= 0 ? HLUp : HLDown)
                if v.vixOK {
                    hrow("VIX 区间", "开 " + hfmt(v.vixOpen, 2) + " · 高 " + hfmt(v.vixHigh, 2) + " · 低 " + hfmt(v.vixLow, 2) + " · 昨收 " + hfmt(v.vixPrev, 2), HLDim)
                    hrow("VIX 状态", v.levelName, regimeColor)
                }
                hrow("纳指波动（QQQ 自算）", ndxText, HLDim)
                hrow("标普波动（SPY 自算）", spxText, HLDim)

                VStack(alignment: .leading, spacing: 3) {
                    Text("环境含义")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(regimeColor)
                    Text(v.regimeText)
                        .font(.system(size: 10.5))
                        .foregroundColor(HLText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 9).fill(regimeColor.opacity(0.12)))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("⚠ 关于 VXN：免费公开源无 VXN（纳指100隐含波动率）。此处「纳指波动」为基于 QQQ 收盘价自算的 20 日已实现波动率，与官方 VXN 口径不同（已实现 vs 隐含），仅作代理参考，不是官方 VXN。")
                    .font(.system(size: 9.5))
                    .foregroundColor(HLWarn)
                    .fixedSize(horizontal: false, vertical: true)
                Text("VIX 为新浪官方指数实时值（美股盘中更新，收盘后停在收盘值）。已实现波动基于近 " + String(v.bars) + " 根日 K 自算，分位为其在同期滚动序列中的位置。波动率衡量的是风险大小，不预测涨跌方向。")
                    .font(.system(size: 9.5))
                    .foregroundColor(HLDim2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))
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

                Text("异动检测只识别「已经发生的不寻常」，不预测涨跌。触发时说明出现了统计上少见的量价组合，值得留意，但不等于要买卖。")
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
    @State private var showReport: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HLQuoteHeader()

                HLSourceBar()

                // 日报入口
                Button(action: { showReport = true }) {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("生成每日决策日报")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 11)
                        .fill(Color(red: 0.20, green: 0.50, blue: 0.95)))
                }
                .sheet(isPresented: $showReport) {
                    HLReportSheet()
                }

                // 前瞻信号面板
                HLForwardCard()

                // 波动率环境（VIX 官方 + 纳指/标普已实现波动代理）
                HLVixCard()

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

                // 隔夜外围（按标的市场归属自动选择）
                VStack(spacing: 4) {
                    Text(m.overnightTitle)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(m.overnightList, id: \.code) { p in
                        HLBriefRow(preset: p, quote: m.globalQuotes[p.code])
                    }
                    Text("外围清单按当前标的市场归属自动切换（A股/港股/美股/商品各不同）。")
                        .font(.system(size: 10))
                        .foregroundColor(HLDim2)
                        .padding(.top, 2)
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                // 关联指数/同类标的（新增：标的中性的横向参照）
                VStack(spacing: 4) {
                    Text(m.contextTitle)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(m.contextList, id: \.code) { p in
                        HLBriefRow(preset: p, quote: m.contextQuotes[p.code])
                    }
                    Text("与本标的直接相关的市场参照，用于判断是个股/行业问题还是大盘问题。")
                        .font(.system(size: 10))
                        .foregroundColor(HLDim2)
                        .padding(.top, 2)
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                // ADR（仅港股/中概标的显示）
                if m.showAdrBlock {
                VStack(spacing: 4) {
                    Text("中概股 ADR · 隔夜")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(HLAdrs, id: \.code) { p in
                        HLBriefRow(preset: p, quote: m.adrQuotes[p.code])
                    }
                    hrow("加权估算（静态权重快照）", hfmtPct(m.adrEstimate), hcolor(m.adrEstimate))
                    hrow("等权平均（不依赖权重）", hfmtPct(m.adrEqual), hcolor(m.adrEqual))
                    hrow("覆盖权重", hfmt(m.adrCoverage, 1) + "%", HLDim)
                    Text("仅覆盖部分中概股权重，未含汇率与溢价折价。只作方向参考，不是开盘价预测。")
                        .font(.system(size: 10))
                        .foregroundColor(HLDim2)
                        .padding(.top, 4)
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))
                }

                // 成分股/持仓快照（仅当该标的持仓明细已知时展示）
                if m.showHoldBlock {
                VStack(spacing: 4) {
                    Text(m.holdTitle)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(HLHoldings, id: \.code) { p in
                        HLBriefRow(preset: p, quote: m.holdQuotes[p.code])
                    }
                    hrow("加权方向（静态权重快照）", hfmtPct(m.holdEstimate), hcolor(m.holdEstimate))
                    hrow("等权平均（不依赖权重）", hfmtPct(m.holdEqual), hcolor(m.holdEqual))
                    hrow("两者差异", hfmtPct(m.holdDivergence), hcolor(m.holdDivergence))
                    hrow("覆盖权重", hfmt(m.holdCoverage, 1) + "%", HLDim)
                    Text("权重为前十大持仓的静态快照，会随基金调仓变化；差异大时以「等权平均」为准")
                        .font(.system(size: 10))
                        .foregroundColor(HLWarn)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))
                }

                // 自选一览
                VStack(spacing: 4) {
                    Text("自选状态一览")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(m.watch, id: \.code) { w in
                        HStack {
                            Text(w.name).font(.system(size: 12.5)).foregroundColor(HLText)
                            Text(HLClassNameOf(w.code))
                                .font(.system(size: 10))
                                .foregroundColor(HLDim2)
                            Spacer()
                            Text(hfmt(w.weight, 3)).font(.system(size: 12.5)).foregroundColor(HLText)
                        }
                        .padding(.vertical, 4)
                    }
                    Text("类别由代码规则自动判定，决定该标的的外围参照与关联指数。")
                        .font(.system(size: 10))
                        .foregroundColor(HLDim2)
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

                Text("外围、关联指数、ADR、成分股均按当前标的类别动态选取，且为实时网络请求（腾讯主源 / 新浪备源）。\n标注「—」表示该项当前未取到数据，不代表为零。\n数据来自公开接口，非官方授权，可能延迟或失效。\n本工具仅为纪律辅助，不构成投资建议。")
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
            }
            .padding(10)
        }
        .refreshable { m.refreshAll() }
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


// MARK: - 决策档案 · 前瞻验证
// 回测可以反复挑选到好看为止，前瞻记录不能。
// 记下此刻的判断，日后用真实价格回填 —— 这是唯一无法自欺的检验。

struct HLDecision: Codable, Identifiable {
    var id: String = ""
    var date: String = ""
    var code: String = ""
    var name: String = ""
    var price: Double = 0
    var light: String = "—"
    var action: String = "观望"
    var note: String = ""
    var chkPrice: Double = 0
    var chkRet: Double = 0
    var chkDate: String = ""
}

final class HLJournal: ObservableObject {
    @Published var items: [HLDecision] = []
    private let key = "hl_journal_v1"

    init() { load() }

    func load() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: key) {
            if let arr = try? JSONDecoder().decode([HLDecision].self, from: data) {
                items = arr
            }
        }
    }

    func save() {
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(items) {
            d.set(data, forKey: key)
        }
    }

    func add(_ it: HLDecision) {
        items.insert(it, at: 0)
        save()
    }

    func remove(id: String) {
        items.removeAll { $0.id == id }
        save()
    }

    // 用最新价回填到期记录（当日记录不回填，保证是前瞻验证）
    func verify(code: String, price: Double, today: String) {
        if price <= 0 { return }
        var changed = false
        var i = 0
        while i < items.count {
            if items[i].code == code && items[i].price > 0
                && items[i].chkPrice <= 0 && items[i].date != today {
                items[i].chkPrice = price
                items[i].chkRet = (price / items[i].price - 1.0) * 100.0
                items[i].chkDate = today
                changed = true
            }
            i += 1
        }
        if changed { save() }
    }

    var verified: [HLDecision] { items.filter { $0.chkPrice > 0 } }
    var pending: Int { items.filter { $0.chkPrice <= 0 }.count }
}

struct HLJournalCard: View {
    @EnvironmentObject var m: HLModel
    @StateObject var j = HLJournal()
    @State var action: String = "观望"
    @State var note: String = ""
    @State var showAll: Bool = false

    let actions = ["观望", "买入", "加仓", "卖出", "减仓"]

    var today: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    // 判断对错：买入/加仓 涨了算对；卖出/减仓/观望 跌了算对
    func isRight(_ it: HLDecision) -> Bool? {
        if it.chkPrice <= 0 { return nil }
        let up = it.chkRet > 0
        if it.action == "买入" || it.action == "加仓" { return up }
        return !up
    }

    var rightCount: Int {
        var c = 0
        for it in j.verified { if isRight(it) == true { c += 1 } }
        return c
    }

    var wrongCount: Int {
        var c = 0
        for it in j.verified { if isRight(it) == false { c += 1 } }
        return c
    }

    var hitRate: Double {
        let t = rightCount + wrongCount
        if t == 0 { return 0 }
        return Double(rightCount) / Double(t) * 100.0
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("决策档案 · 前瞻验证")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(HLDim)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("记下此刻的判断，日后用真实价格回填。回测可以反复挑到好看为止，前瞻记录不能 —— 这是唯一无法自欺的检验。")
                .font(.system(size: 10))
                .foregroundColor(HLDim2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                ForEach(actions, id: \.self) { a in
                    Button(action: { action = a }) {
                        Text(a)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(action == a ? HLText : HLDim)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 7)
                                .fill(action == a ? HLInfo.opacity(0.30) : HLCard2))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                TextField("备注（可选）", text: $note)
                    .font(.system(size: 12))
                    .foregroundColor(HLText)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(HLCard2))
                Button(action: { addRecord() }) {
                    Text("记录")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(HLInfo))
                }
                .buttonStyle(PlainButtonStyle())
            }

            hrow("累计记录", String(j.items.count), HLDim)
            hrow("已验证", String(j.verified.count), HLDim)
            if rightCount + wrongCount > 0 {
                hrow("前瞻命中率", hfmt(hitRate, 0) + "%（对 " + String(rightCount)
                     + " / 错 " + String(wrongCount) + "）",
                     hitRate >= 50 ? HLDown : HLUp)
            }
            if j.pending > 0 {
                Text("待验证 " + String(j.pending) + " 条 · 下次打开或刷新时自动回填")
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if showAll && !j.items.isEmpty {
                VStack(spacing: 4) {
                    ForEach(j.items.prefix(30)) { it in
                        HLJournalRow(it: it, right: isRight(it))
                    }
                }
            }

            Button(action: { showAll.toggle() }) {
                Text(showAll ? "收起记录" : "查看记录（" + String(j.items.count) + "）")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(HLInfo)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))
        .onAppear {
            j.verify(code: m.curCode, price: m.lastPrice, today: today)
        }
        .onChange(of: m.lastPrice) { _ in
            j.verify(code: m.curCode, price: m.lastPrice, today: today)
        }
    }

    func addRecord() {
        var it = HLDecision()
        it.id = UUID().uuidString
        it.date = today
        it.code = m.curCode
        it.name = m.quote?.name ?? ""
        it.price = m.lastPrice
        it.light = m.signal.title
        it.action = action
        it.note = note
        j.add(it)
        note = ""
    }
}

struct HLJournalRow: View {
    var it: HLDecision
    var right: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(it.date)
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
                Text(it.light + "灯")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(HLDim)
                Text(it.action)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(HLInfo)
                Spacer()
                if it.chkPrice > 0 {
                    Text((it.chkRet >= 0 ? "+" : "") + hfmt(it.chkRet, 2) + "%")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(it.chkRet >= 0 ? HLUp : HLDown)
                    if let r = right {
                        Text(r ? "对" : "错")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(r ? HLDown : HLUp)
                    }
                } else {
                    Text("待验证")
                        .font(.system(size: 10))
                        .foregroundColor(HLDim2)
                }
            }
            HStack(spacing: 6) {
                Text("@" + hfmt(it.price, 3))
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
                if !it.note.isEmpty {
                    Text(it.note)
                        .font(.system(size: 10))
                        .foregroundColor(HLDim)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct HLCalcView: View {
    @EnvironmentObject var m: HLModel
    @State var costText: String = ""
    @State var qtyText: String = ""
    @State var lotsText: String = "1"
    @State var hiText: String = ""
    @State var loText: String = ""
    @State var feeText: String = "0.05"
    @State var planText: String = ""
    @State var addCashText: String = "200"

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
    var newLossText: String {
        let head = hfmt(newLoss, 2) + " 元（"
        let tail: String = newLoss < oldLoss ? ("多亏 " + hfmt(abs(newLoss - oldLoss), 2)) : "优于现在"
        return head + tail + "）"
    }
    var tNet: Double { (hiP - loP) * 100 - fee * 2 }

    // ---- 解套方案（仅亏损时给出）----
    var addCash: Double { Double(addCashText) ?? 0 }
    var rescue: [Double] {
        let cc = m.closes
        if cc.count < 60 || cost <= 0 || qty <= 0 || m.lastPrice <= 0 { return [] }
        return HLCore.hlRescue(cc, m.highs, m.lows,
                               cost: cost, shares: qty, price: m.lastPrice,
                               stop: stopLevel, addCash: addCash,
                               tShares: 100, fee: fee)
    }
    var hasRescue: Bool { rescue.count == 16 && rescue[0] < 0 }
    var rPnl: Double { hasRescue ? rescue[0] : 0 }
    var rPnlPct: Double { hasRescue ? rescue[1] : 0 }
    var rNeedUp: Double { hasRescue ? rescue[2] : 0 }
    var rProb: Double { hasRescue ? rescue[3] : 0 }
    var rDays: Double { hasRescue ? rescue[4] : 0 }
    var rSamples: Double { hasRescue ? rescue[5] : 0 }
    var rNewCost: Double { hasRescue ? rescue[6] : 0 }
    var rNewNeedUp: Double { hasRescue ? rescue[7] : 0 }
    var rNewLoss: Double { hasRescue ? rescue[8] : 0 }
    var rTotalIn: Double { hasRescue ? rescue[9] : 0 }
    var rPerT: Double { hasRescue ? rescue[10] : 0 }
    var rTimes: Double { hasRescue ? rescue[11] : 0 }
    var rAmp: Double { hasRescue ? rescue[12] : 0 }
    var rOldLoss: Double { hasRescue ? rescue[15] : 0 }

    var rPnlValue: String { hfmt(rPnl, 2) + " 元" }
    var rPnlSub: String { hfmt(rPnlPct, 1) + "%" }
    var rNeedValue: String { hfmt(rNeedUp, 1) + "%" }
    var rNeedSub: String { "到 " + hfmt(cost, 3) }

    var rHoldKey: String {
        if rSamples <= 0 { return "历史样本不足，无法估算" }
        let a = "250 天内达标 " + hfmt(rProb, 0) + "%"
        let b = "中位 " + hfmt(rDays, 0) + " 天"
        return a + " · " + b
    }
    var rHoldCost: String {
        if rDays <= 0 { return "需继续持有，期间可能继续下跌" }
        let a = "约 " + hfmt(rDays / 21.0, 1) + " 个月"
        return "时间成本 " + a + "，期间可能继续跌"
    }
    var rAddTitle: String {
        let a = "补仓摊薄（"
        let b = hfmt(addCash, 0)
        return a + b + " 元）"
    }
    var rAddKey: String {
        let a = "新成本 " + hfmt(rNewCost, 4)
        let b = "回本需涨 " + hfmt(rNewNeedUp, 1) + "%"
        return a + " · " + b
    }
    var rAddCost: String {
        var parts: [String] = []
        parts.append("总投入 " + hfmt(rTotalIn, 0) + " 元")
        parts.append("跌到止损亏 " + hfmt(rNewLoss, 2) + " 元")
        parts.append("比不补多亏 " + hfmt(abs(rNewLoss - rOldLoss), 2) + " 元")
        return parts.joined(separator: "，")
    }
    var rTKey: String {
        if rTimes < 0 { return "单次净收益为负，不可行" }
        let a = "每次约 " + hfmt(rPerT, 2) + " 元"
        let b = "需成功 " + hfmt(rTimes, 0) + " 次"
        return a + "，" + b
    }
    var rTCost: String {
        var parts: [String] = []
        parts.append("日均振幅 " + hfmt(rAmp, 2) + "%")
        parts.append("按抓到一半 · 100 份 · 佣金 " + hfmt(fee, 2) + " 元估算")
        return parts.joined(separator: "，")
    }
    var rCutKey: String {
        let a = "实亏 " + hfmt(rPnl, 2) + " 元"
        let b = "收回 " + hfmt(m.lastPrice * qty, 2) + " 元"
        return a + "，" + b
    }
    var rSummary: String {
        if rSamples <= 0 { return "历史样本不足，以下仅为算术推演，不构成建议。" }
        var parts: [String] = []
        let sProb = hfmt(rProb, 0)
        let sDays = hfmt(rDays, 0)
        parts.append("等回本成功率 " + sProb + "%、中位 " + sDays + " 天")
        let sOld = hfmt(rNeedUp, 1)
        let sNew = hfmt(rNewNeedUp, 1)
        parts.append("补仓把回本线从 " + sOld + "% 降到 " + sNew + "%")
        parts.append("但跌到止损多亏 " + hfmt(abs(rNewLoss - rOldLoss), 2) + " 元")
        parts.append("做 T 需成功 " + hfmt(rTimes, 0) + " 次")
        let head = "四条路都有代价："
        return head + parts.joined(separator: "；") + "。工具只负责把代价算出来，不替你选。"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HLQuoteHeader()

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

                // 解套方案（仅在持仓亏损时给出）
                if hasRescue {
                    HLCardBox(title: "解套方案", subtitle: "基于本标的自身历史统计") {
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                HLStatCell(label: "当前浮亏", value: rPnlValue,
                                           sub: rPnlSub,
                                           color: Color(red: 1.0, green: 0.30, blue: 0.37))
                                HLStatCell(label: "回本需涨", value: rNeedValue,
                                           sub: rNeedSub,
                                           color: Color(red: 1.0, green: 0.69, blue: 0.13))
                            }
                            HLPlanRow(idx: "1", title: "持有等回本",
                                      key: rHoldKey, cost: rHoldCost,
                                      color: Color(red: 0.0, green: 0.84, blue: 0.56))
                            HLPlanRow(idx: "2", title: rAddTitle,
                                      key: rAddKey, cost: rAddCost,
                                      color: Color(red: 1.0, green: 0.69, blue: 0.13))
                            HLField("补仓金额（元）", $addCashText)
                            HLPlanRow(idx: "3", title: "做 T 降成本",
                                      key: rTKey, cost: rTCost,
                                      color: Color(red: 1.0, green: 0.30, blue: 0.37))
                            HLPlanRow(idx: "4", title: "止损离场",
                                      key: rCutKey, cost: "亏损兑现，但释放资金与注意力",
                                      color: HLDim)
                            Text(rSummary)
                                .font(.system(size: 10.5))
                                .foregroundColor(HLDim2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

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
                    hrow("跌到止损位", newLossText,
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

                HLSizeCard()

                HLJournalCard()

                Text("本工具仅为纪律辅助，不构成投资建议。市场有风险，本金可能亏损。")
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
            }
                .padding(10)
                .contentShape(Rectangle())
                .onTapGesture { HLEndEditing() }
            }
        .refreshable { m.refreshAll() }
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

// 解套方案条目：序号 + 标题 + 关键数字 + 代价
struct HLPlanRow: View {
    var idx: String = ""
    var title: String = ""
    var key: String = ""
    var cost: String = ""
    var color: Color = HLText

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(idx)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(color)
                    .frame(width: 17, height: 17)
                    .background(Circle().fill(color.opacity(0.16)))
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(HLText)
                Spacer()
            }
            Text(key)
                .font(.system(size: 11.5))
                .foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
            Text(cost)
                .font(.system(size: 10))
                .foregroundColor(HLDim2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(HLCard2))
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

// MARK: - 进阶：可信度 / 基准相对 / 组合体检 / 仓位方案

struct HLKV: Identifiable {
    let k: String
    let v: String
    let lv: Int
    var id: UUID = UUID()
}

func advColor(_ lv: Int) -> Color {
    if lv == 1 { return Color(red: 0.0, green: 0.84, blue: 0.56) }
    if lv == 2 { return Color(red: 1.0, green: 0.69, blue: 0.13) }
    if lv == 3 { return Color(red: 1.0, green: 0.30, blue: 0.37) }
    if lv == 4 { return HLInfo }
    return HLText
}

struct HLTrustCard: View {
    @EnvironmentObject var m: HLModel
    var body: some View {
        VStack(spacing: 6) {
            Text("回测可信度实验室")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(HLDim)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("按公开研究方法检验：成本敏感性、滚动样本外、组合Purged交叉验证、置换检验。")
                .font(.system(size: 10))
                .foregroundColor(HLDim2)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(m.advTrustRows) { r in
                hrow(r.k, r.v, advColor(r.lv))
            }
            Text(m.advTrustVerdict)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(m.advTrustColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))
    }
}

struct HLBenchCard: View {
    @EnvironmentObject var m: HLModel
    var body: some View {
        VStack(spacing: 6) {
            Text("基准相对表现")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(HLDim)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(m.advBenchNote)
                .font(.system(size: 10))
                .foregroundColor(HLDim2)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(m.advBenchRows) { r in
                hrow(r.k, r.v, advColor(r.lv))
            }
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))
    }
}

struct HLRegimeCard: View {
    @EnvironmentObject var m: HLModel
    var body: some View {
        VStack(spacing: 6) {
            Text("市场状态识别")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(HLDim)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("用已实现波动率与其自身中位数、以及趋势效率（ER）划分状态。这是过滤器，不是预测器。")
                .font(.system(size: 10))
                .foregroundColor(HLDim2)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(m.advRegimeRows) { r in
                hrow(r.k, r.v, advColor(r.lv))
            }
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))
    }
}

struct HLPortfolioCard: View {
    @EnvironmentObject var m: HLModel
    var body: some View {
        VStack(spacing: 6) {
            Text("组合体检")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(HLDim)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("相关系数在危机时会一起冲向 1，届时分散失效。以下用最近真实数据估算。")
                .font(.system(size: 10))
                .foregroundColor(HLDim2)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(m.advPortRows) { r in
                hrow(r.k, r.v, advColor(r.lv))
            }
            Text("层次风险平价（HRP）建议权重")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(HLDim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            ForEach(m.advHrpRows) { r in
                hrow(r.k, r.v, advColor(r.lv))
            }
            Text("等权重对照")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(HLDim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
            ForEach(m.advEqRows) { r in
                hrow(r.k, r.v, advColor(r.lv))
            }
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))
    }
}

struct HLSizeCard: View {
    @EnvironmentObject var m: HLModel
    var body: some View {
        VStack(spacing: 6) {
            Text("仓位方案对比")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(HLDim)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("四种主流仓位法则给出的建议权重。凯利只作上限参考，实践中普遍用 1/4 凯利。")
                .font(.system(size: 10))
                .foregroundColor(HLDim2)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(m.advSizeRows) { r in
                hrow(r.k, r.v, advColor(r.lv))
            }
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))
    }
}

extension HLModel {
    var advOpen: [Double] { candles.map { $0.open } }
    var advHigh: [Double] { candles.map { $0.high } }
    var advLow: [Double] { candles.map { $0.low } }
    var advClose: [Double] { candles.map { $0.close } }
    var advVol: [Double] { candles.map { $0.volume } }

    var advLimit: Double {
        if curCode.hasPrefix("sz30") { return 0.20 }
        if curCode.hasPrefix("sh688") { return 0.20 }
        return 0.10
    }

    var advNav: [Double] {
        return HLAdv.navAll(advOpen, advHigh, advLow, advClose, advVol,
                            2, 20, 60, 20.0, advLimit)
    }

    // MARK: 可信度实验室
    var advTrustRows: [HLKV] {
        var out: [HLKV] = []
        let c = advClose
        let cnt = c.count
        if cnt < 200 {
            out.append(HLKV(k: "样本长度", v: String(cnt) + " 根（需≥200）", lv: 3))
            return out
        }
        let o = advOpen
        let h = advHigh
        let l = advLow
        let v = advVol
        let lim = advLimit

        let b = HLAdv.blockedDays(h, l, c, v, lim)
        let bsum = b[0] + b[1] + b[2]
        out.append(HLKV(k: "触及涨跌停 / 停牌", v: String(Int(bsum)) + " 天",
                        lv: bsum > 0 ? 2 : 1))

        let cs = HLAdv.costSensitivity(o, h, l, c, v, 2, 20, 60, lim)
        let c0 = hfmt(cs[0], 2) + "%"
        let c1 = hfmt(cs[1], 2) + "%"
        let c2 = hfmt(cs[2], 2) + "%"
        out.append(HLKV(k: "收益 @5bps（乐观成本）", v: c0, lv: cs[0] > 0 ? 1 : 3))
        out.append(HLKV(k: "收益 @15bps（常规）", v: c1, lv: cs[1] > 0 ? 1 : 3))
        out.append(HLKV(k: "收益 @30bps（保守）", v: c2, lv: cs[2] > 0 ? 1 : 3))

        let wf = HLAdv.walkForward(o, h, l, c, v, 2, 20, 60, 20.0, lim, 8)
        let v0 = String(Int(wf[0])) + " 折"
        let v1 = hfmt(wf[1], 2)
        let v4 = hfmt(wf[4], 0) + "%"
        let v5 = hfmt(wf[5], 2)
        var v6 = "不适用"
        var lv6 = 0
        if wf[6] != 0 {
            v6 = hfmt(wf[6], 2)
            lv6 = wf[6] >= 0.5 ? 1 : 3
        }
        out.append(HLKV(k: "滚动样本外折数", v: v0, lv: 0))
        out.append(HLKV(k: "样本外中位夏普", v: v1, lv: wf[1] > 0 ? 1 : 3))
        out.append(HLKV(k: "为正样本外折占比", v: v4, lv: wf[4] >= 60 ? 1 : 3))
        out.append(HLKV(k: "全样本夏普", v: v5, lv: wf[5] > 0 ? 1 : 3))
        out.append(HLKV(k: "WFE（样本外/样本内）", v: v6, lv: lv6))

        let nav = advNav
        if nav.count >= 60 {
            let rr = HLCore.navToRets(nav)
            let cp = HLAdv.cpcv(rr, 6, 5)
            let p0 = String(Int(cp[0]))
            let p1 = hfmt(cp[1], 2)
            let p2 = hfmt(cp[2], 2) + " / " + hfmt(cp[3], 2)
            let p4 = hfmt(cp[4], 0) + "%"
            out.append(HLKV(k: "CPCV 路径数", v: p0, lv: 0))
            out.append(HLKV(k: "CPCV 中位夏普", v: p1, lv: cp[1] > 0 ? 1 : 3))
            out.append(HLKV(k: "CPCV 最差 / 最好", v: p2, lv: 0))
            out.append(HLKV(k: "CPCV 为正占比", v: p4, lv: cp[4] >= 70 ? 1 : 3))
        }

        let tr = HLAdv.tradeRets(o, h, l, c, v, 2, 20, 60, 20.0, lim)
        let pt = HLAdv.permutationTest(tr, 500, 20240930)
        if pt[3] >= 8 {
            let t0 = String(Int(pt[3]))
            let t1 = hfmt(pt[0], 1) + "%"
            let t2 = hfmt(pt[1], 3)
            out.append(HLKV(k: "交易笔数", v: t0, lv: 0))
            out.append(HLKV(k: "交易序列最大回撤", v: t1, lv: 3))
            out.append(HLKV(k: "置换检验 p 值", v: t2, lv: pt[1] < 0.05 ? 1 : 3))
        } else {
            out.append(HLKV(k: "置换检验", v: "交易不足 8 笔，不适用", lv: 0))
        }
        return out
    }

    var advTrustColor: Color {
        let c = advClose
        if c.count < 200 { return HLText }
        let wf = HLAdv.walkForward(advOpen, advHigh, advLow, c, advVol,
                                   2, 20, 60, 20.0, advLimit, 8)
        let nav = advNav
        var cpPos = 0.0
        if nav.count >= 60 {
            let rr = HLCore.navToRets(nav)
            cpPos = HLAdv.cpcv(rr, 6, 5)[4]
        }
        let g = HLAdv.robustGrade(wf[6], cpPos)
        if g == 2 { return Color(red: 0.0, green: 0.84, blue: 0.56) }
        if g == 1 { return Color(red: 1.0, green: 0.69, blue: 0.13) }
        return Color(red: 1.0, green: 0.30, blue: 0.37)
    }

    var advTrustVerdict: String {
        let c = advClose
        if c.count < 200 { return "样本不足，先积累数据" }
        let wf = HLAdv.walkForward(advOpen, advHigh, advLow, c, advVol,
                                   2, 20, 60, 20.0, advLimit, 8)
        let nav = advNav
        var cpPos = 0.0
        if nav.count >= 60 {
            let rr = HLCore.navToRets(nav)
            cpPos = HLAdv.cpcv(rr, 6, 5)[4]
        }
        let g = HLAdv.robustGrade(wf[6], cpPos)
        let gt = HLAdv.robustGradeText(g)
        let cs = HLAdv.costSensitivity(advOpen, advHigh, advLow, c, advVol,
                                       2, 20, 60, advLimit)
        var frag = "不受成本假设左右"
        if cs[0] > 0 && cs[2] <= 0 { frag = "成本从 5bps 提到 30bps 就转亏，属成本敏感" }
        let s1 = "稳健度：" + gt
        let s2 = "（WFE " + hfmt(wf[6], 2) + "，样本外为正占比 " + hfmt(cpPos, 0) + "%）"
        let s3 = "。" + frag + "。"
        return s1 + s2 + s3
    }

    // MARK: 基准相对
    var advBenchNote: String {
        return "基准：沪深300ETF（510300）。未取到时退回本标的买入持有。按最近重叠交易日尾部对齐。"
    }

    var advBenchRows: [HLKV] {
        var out: [HLKV] = []
        let nav = advNav
        if nav.count < 60 {
            out.append(HLKV(k: "基准对比", v: "策略样本不足", lv: 3))
            return out
        }
        let pr = HLCore.navToRets(nav)
        var bsrc = poolCloses["sh510300"]
        if bsrc == nil { bsrc = advClose }
        var bm = bsrc!
        if bm.count < 62 {
            out.append(HLKV(k: "基准对比", v: "基准数据未取到", lv: 3))
            return out
        }
        let br = HLCore.rets(bm)
        let n = pr.count < br.count ? pr.count : br.count
        if n < 30 {
            out.append(HLKV(k: "基准对比", v: "重叠样本不足", lv: 3))
            return out
        }
        let pp = Array(pr.suffix(n))
        let bb = Array(br.suffix(n))
        let bm2 = HLAdv.benchMetrics(pp, bb, 1.5)
        out.append(HLKV(k: "年化 Alpha", v: hfmt(bm2[0], 2) + "%",
                        lv: bm2[0] > 0 ? 1 : 3))
        out.append(HLKV(k: "Beta（对基准敏感度）", v: hfmt(bm2[1], 2), lv: 0))
        out.append(HLKV(k: "年化跟踪误差", v: hfmt(bm2[2], 2) + "%", lv: 0))
        out.append(HLKV(k: "信息比率", v: hfmt(bm2[3], 2),
                        lv: bm2[3] > 0.5 ? 1 : (bm2[3] > 0 ? 2 : 3)))
        out.append(HLKV(k: "R²（可被基准解释）", v: hfmt(bm2[4], 0) + "%", lv: 0))
        out.append(HLKV(k: "上行捕获", v: hfmt(bm2[5], 0) + "%", lv: 2))
        out.append(HLKV(k: "下行捕获（越低越好）", v: hfmt(bm2[6], 0) + "%", lv: 1))
        return out
    }

    // MARK: 市场状态
    var advRegimeRows: [HLKV] {
        var out: [HLKV] = []
        let c = advClose
        if c.count < 160 {
            out.append(HLKV(k: "市场状态", v: "样本不足", lv: 3))
            return out
        }
        let rg = HLAdv.regimeOf(c)
        out.append(HLKV(k: "当前状态", v: HLAdv.regimeText(rg[2]), lv: 4))
        out.append(HLKV(k: "趋势效率 ER(60)", v: hfmt(rg[1], 2), lv: rg[1] >= 0.3 ? 1 : 0))
        out.append(HLKV(k: "20日年化波动", v: hfmt(rg[3], 1) + "%", lv: 0))
        out.append(HLKV(k: "波动中位数（近一年）", v: hfmt(rg[4], 1) + "%", lv: 0))
        out.append(HLKV(k: "适配提示", v: HLAdv.regimeAdvice(rg[2]), lv: 2))
        return out
    }

    // MARK: 组合体检
    var advPortRows: [HLKV] {
        var out: [HLKV] = []
        let cs = poolCodes
        var cols: [[Double]] = []
        var names: [String] = []
        var i = 0
        while i < cs.count {
            if let arr = poolCloses[cs[i]] {
                if arr.count >= 120 {
                    cols.append(arr)
                    names.append(poolName(cs[i]))
                }
            }
            i = i + 1
        }
        if cols.count < 2 {
            out.append(HLKV(k: "组合体检", v: "需至少 2 个标的的历史数据", lv: 3))
            return out
        }
        let cm = HLAdv.corrMatrix(cols)
        var maxPair = 0.0
        var maxA = 0
        var maxB = 1
        var a2 = 0
        while a2 < cols.count {
            var b2 = a2 + 1
            while b2 < cols.count {
                let cv = cm[a2][b2]
                if cv > maxPair {
                    maxPair = cv
                    maxA = a2
                    maxB = b2
                }
                b2 = b2 + 1
            }
            a2 = a2 + 1
        }
        let pn = names[maxA] + " × " + names[maxB]
        out.append(HLKV(k: "最高相关的一对", v: pn, lv: maxPair > 0.7 ? 3 : 0))
        out.append(HLKV(k: "该对相关系数", v: hfmt(maxPair, 2),
                        lv: maxPair > 0.7 ? 3 : (maxPair > 0.4 ? 2 : 1)))
        return out
    }

    var advHrpRows: [HLKV] {
        var out: [HLKV] = []
        let cs = poolCodes
        var cols: [[Double]] = []
        var names: [String] = []
        var i = 0
        while i < cs.count {
            if let arr = poolCloses[cs[i]] {
                if arr.count >= 120 {
                    cols.append(arr)
                    names.append(poolName(cs[i]))
                }
            }
            i = i + 1
        }
        if cols.count < 2 { return out }
        let w = HLAdv.hrpWeights(cols)
        var vols: [Double] = []
        i = 0
        while i < cols.count {
            let r = HLCore.rets(cols[i])
            vols.append(HLCore.stdev(r) * sqrt(252.0))
            i = i + 1
        }
        let con = HLAdv.concentration(w)
        let pv = HLAdv.stressVol(w, vols, 0.0)
        let st = HLAdv.stressVol(w, vols, 0.9)
        i = 0
        while i < cols.count {
            let pv2 = hfmt(w[i] * 100.0, 1) + "%"
            out.append(HLKV(k: names[i], v: pv2, lv: w[i] > 0.4 ? 2 : 0))
            i = i + 1
        }
        out.append(HLKV(k: "集中度 HHI", v: hfmt(con[0], 2), lv: con[0] > 0.4 ? 3 : 0))
        out.append(HLKV(k: "有效标的数", v: hfmt(con[2], 1), lv: con[2] < 2 ? 3 : 0))
        out.append(HLKV(k: "组合波动（当前相关）", v: hfmt(pv, 1) + "%", lv: 0))
        out.append(HLKV(k: "ρ=0.9 压力下波动", v: hfmt(st, 1) + "%", lv: 3))
        return out
    }

    var advEqRows: [HLKV] {
        var out: [HLKV] = []
        let cs = poolCodes
        var cols: [[Double]] = []
        var names: [String] = []
        var i = 0
        while i < cs.count {
            if let arr = poolCloses[cs[i]] {
                if arr.count >= 120 {
                    cols.append(arr)
                    names.append(poolName(cs[i]))
                }
            }
            i = i + 1
        }
        if cols.count < 2 { return out }
        let m = cols.count
        var w: [Double] = []
        i = 0
        while i < m {
            w.append(1.0 / Double(m))
            i = i + 1
        }
        var vols: [Double] = []
        i = 0
        while i < m {
            let r = HLCore.rets(cols[i])
            vols.append(HLCore.stdev(r) * sqrt(252.0))
            i = i + 1
        }
        let con = HLAdv.concentration(w)
        i = 0
        while i < m {
            let pv2 = hfmt(w[i] * 100.0, 1) + "%"
            out.append(HLKV(k: names[i], v: pv2, lv: 0))
            i = i + 1
        }
        let cm = HLAdv.corrMatrix(cols)
        var pv = 0.0
        i = 0
        while i < m {
            var j = 0
            while j < m {
                pv = pv + w[i] * w[j] * vols[i] * vols[j] * cm[i][j]
                j = j + 1
            }
            i = i + 1
        }
        let pvPct = sqrt(max(0.0, pv)) * 100.0
        let st = HLAdv.stressVol(w, vols, 0.9)
        out.append(HLKV(k: "集中度 HHI", v: hfmt(con[0], 2), lv: 0))
        out.append(HLKV(k: "有效标的数", v: hfmt(con[2], 1), lv: 0))
        out.append(HLKV(k: "组合波动（当前相关）", v: hfmt(pvPct, 1) + "%", lv: 0))
        out.append(HLKV(k: "ρ=0.9 压力下波动", v: hfmt(st, 1) + "%", lv: 3))
        return out
    }

    // MARK: 仓位方案
    var advSizeRows: [HLKV] {
        var out: [HLKV] = []
        let c = advClose
        if c.count < 160 {
            out.append(HLKV(k: "仓位方案", v: "样本不足", lv: 3))
            return out
        }
        let tr = HLAdv.tradeRets(advOpen, advHigh, advLow, c, advVol,
                                 2, 20, 60, 20.0, advLimit)
        var wr = 0.0
        var pf = 0.0
        if tr.count >= 5 {
            var winSum = 0.0
            var lossSum = 0.0
            var wn = 0
            var ln = 0
            var i = 0
            while i < tr.count {
                if tr[i] > 0 {
                    winSum = winSum + tr[i]
                    wn = wn + 1
                } else {
                    lossSum = lossSum + tr[i]
                    ln = ln + 1
                }
                i = i + 1
            }
            wr = Double(wn) / Double(tr.count)
            var aw = 0.0
            var al = 0.0
            if wn > 0 { aw = winSum / Double(wn) }
            if ln > 0 { al = lossSum / Double(ln) }
            if al < 0 { pf = aw / (-al) }
        }
        let av = (annualVol ?? 0) * 100.0
        var stopPct = 0.0
        let px = lastPrice
        if px > 0 {
            if let sp = stopLoss {
                stopPct = (px - sp) / px * 100.0
            }
        }
        let sm = HLAdv.sizingModes(wr, pf, av, stopPct, 100.0)
        out.append(HLKV(k: "实测胜率", v: hfmt(wr * 100.0, 0) + "%", lv: 0))
        out.append(HLKV(k: "实测盈亏比", v: hfmt(pf, 2), lv: pf >= 1.5 ? 1 : 0))
        out.append(HLKV(k: "年化波动率", v: hfmt(av, 1) + "%", lv: 0))
        out.append(HLKV(k: "当前止损幅度", v: hfmt(stopPct, 1) + "%", lv: 0))
        out.append(HLKV(k: "固定分数（单笔风险1%）", v: hfmt(sm[0], 0) + "%", lv: 4))
        out.append(HLKV(k: "波动率目标（年化15%）", v: hfmt(sm[1], 0) + "%", lv: 4))
        out.append(HLKV(k: "1/4 凯利", v: hfmt(sm[2], 0) + "%", lv: 4))
        out.append(HLKV(k: "三者取最小（建议上限）", v: hfmt(min(sm[0], min(sm[1], sm[2])), 0) + "%", lv: 1))
        return out
    }
}

struct HLProView: View {
    @EnvironmentObject var m: HLModel

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HLQuoteHeader()

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

                // MACD 两种用法对比
                HLMacdCompareCard()

                // KDJ + 威廉 + RSI
                VStack(spacing: 6) {
                    Text("摆动指标")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HLMeter(label: "RSI (14)", value: HLV(m.rsi(14)),
                            text: hfmt(m.rsi(14), 1),
                            lowZone: 30, highZone: 70)
                    HLMeter(label: "RSI (24) 长周期", value: HLV(m.rsi(24)),
                            text: hfmt(m.rsi(24), 1),
                            lowZone: 30, highZone: 70)
                    HLMeter(label: "KDJ · K", value: HLV(m.kValue),
                            text: hfmt(m.kValue, 1),
                            lowZone: 20, highZone: 80)
                    HLMeter(label: "KDJ · D", value: HLV(m.dValue),
                            text: hfmt(m.dValue, 1),
                            lowZone: 20, highZone: 80)
                    HLMeter(label: "KDJ · J", value: HLV(m.jValue),
                            text: hfmt(m.jValue, 1), lo: -20, hi: 120,
                            lowZone: 0, highZone: 100)
                    HLMeter(label: "威廉 %R (14) 绝对值", value: -HLV(m.williamsR),
                            text: hfmt(m.williamsR, 1),
                            lowZone: 20, highZone: 80)
                    hrow("KDJ 状态", m.kdjText, HLDim)
                    Text("RSI/KDJ：>80 超买区，<20 超卖区。威廉 %R 已取绝对值，>80 超买、<20 超卖。")
                        .font(.system(size: 9.5))
                        .foregroundColor(HLDim2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
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

                // 回测可信度实验室
                HLTrustCard()

                // 基准相对
                HLBenchCard()

                // 市场状态
                HLRegimeCard()

                Text("指标基于历史K线实时计算，仅描述已发生的价格结构，不预测未来。\n本工具仅为纪律辅助，不构成投资建议。")
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
            }
            .padding(10)
        }
        .refreshable { m.refreshAll() }
        .background(Color(red: 0.043, green: 0.051, blue: 0.071))
    }
}

// MARK: - 策略实验室

struct HLStrategyView: View {
    @EnvironmentObject var m: HLModel

    // 策略对比行（普通函数，不在 ViewBuilder 内声明 let）
    // V2 最优详情卡（普通函数，避免在 ViewBuilder 内声明 let）
    func v2BestCard() -> some View {
        let bi = m.v2BestIndex
        let br = m.v2Row(bi)
        let name = m.v2Name(bi)
        let cnt = Int(br[2])
        let dSeg1 = "净值 " + hfmt(br[0], 2) + "% · 回撤 " + hfmt(br[1], 1)
        let dSeg2 = "% · " + String(cnt) + " 笔 · 胜率 " + hfmt(br[3], 1)
        let dSeg3 = "% · 最大连亏 " + String(Int(br[7])) + " 次"
        let detailText = dSeg1 + dSeg2 + dSeg3
        return VStack(alignment: .leading, spacing: 4) {
            Text("综合最优：" + name)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(HLDown)
            Text(detailText)
                .font(.system(size: 9.5))
                .foregroundColor(HLDim)
            Text("样本判定：" + m.sampleVerdict(cnt))
                .font(.system(size: 9.5))
                .foregroundColor(HLWarn)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 9).fill(HLCard2))
    }

    // V2 回测行（T+1 + 成本 + 期望值）
    func v2RowView(_ i: Int) -> some View {
        let r = m.v2Row(i)
        let name = m.v2Name(i)
        let isBest = (i == m.v2BestIndex)
        let net = r[0]
        let dd = r[1]
        let cnt = Int(r[2])
        let exp = r[4]
        let pf = r[6]
        return HStack(spacing: 5) {
            Text(name)
                .font(.system(size: 10, weight: isBest ? .bold : .regular))
                .foregroundColor(isBest ? HLDown : HLText)
                .frame(width: 96, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(hfmt(net, 1) + "%")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(hcolor(net))
                .frame(width: 50, alignment: .trailing)
            Text(hfmt(dd, 1) + "%")
                .font(.system(size: 9.5))
                .foregroundColor(HLDim)
                .frame(width: 42, alignment: .trailing)
            Text(String(cnt))
                .font(.system(size: 9.5))
                .foregroundColor(HLDim2)
                .frame(width: 28, alignment: .trailing)
            Text(hfmt(exp, 2) + "%")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(hcolor(exp))
                .frame(width: 46, alignment: .trailing)
            Text(hfmt(pf, 2))
                .font(.system(size: 9.5))
                .foregroundColor(pf >= 1 ? HLDown : HLUp)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isBest ? HLDown.opacity(0.10) : Color.clear)
        )
    }

    // 稳健度小卡（普通函数）
    func robustCell(title: String, mode: Int) -> some View {
        let r = m.robust(mode)
        let lv = r[0]
        let posRate = r[1]
        let fRet = r[2]
        let sRet = r[3]
        let worst = r[4]
        let txt = HLCore.robustText(lv)
        var col = HLUp
        if lv >= 3 { col = HLDown }
        else if lv >= 2 { col = HLInfo }
        else if lv >= 1 { col = HLWarn }
        return VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundColor(HLDim)
            HLBadge(text: txt, color: col)
            Text("参数正收益 " + String(Int(posRate)) + "%")
                .font(.system(size: 9.5))
                .foregroundColor(HLDim2)
            Text("前半 " + hfmt(fRet, 1) + "%")
                .font(.system(size: 9.5))
                .foregroundColor(hcolor(fRet))
            Text("后半 " + hfmt(sRet, 1) + "%")
                .font(.system(size: 9.5))
                .foregroundColor(hcolor(sRet))
            Text("最差参数 " + hfmt(worst, 1) + "%")
                .font(.system(size: 9.5))
                .foregroundColor(hcolor(worst))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 9).fill(HLCard2))
    }

    // 证据门禁行（DSR）
    func evidenceRow(_ i: Int) -> some View {
        let r = m.dsrOf(i)
        let sr = r[0]
        let dv = r[1]
        let txt = m.evidenceText(i)
        let col = m.evidenceColor(i)
        return HStack(spacing: 8) {
            Text(m.strategyName(i))
                .font(.system(size: 11))
                .foregroundColor(HLText)
                .frame(width: 104, alignment: .leading)
            Text(hfmt(sr, 2))
                .font(.system(size: 11))
                .foregroundColor(hcolor(sr))
                .frame(width: 46, alignment: .trailing)
            Text(hfmt(dv * 100, 1) + "%")
                .font(.system(size: 11))
                .foregroundColor(HLDim)
                .frame(width: 52, alignment: .trailing)
            Text(txt)
                .font(.system(size: 10))
                .foregroundColor(col)
                .frame(width: 62, alignment: .trailing)
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    func btRow(_ i: Int) -> some View {
        let r = m.btRows[i]
        let rawName = m.strategyName(i)
        let name = (i == 15) ? (rawName + " ⚠") : rawName
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

    // 卖出端对比：三档卖出规则，买入端完全相同（RSI<30 买）
    func sellCompareRowView(_ kind: Int, _ label: String, _ warn: Bool) -> some View {
        let r = m.backtest(kind)
        let retPct = (r[0] - 1) * 100
        let tail = warn ? "  ← 涨多了就卖" : ""
        let leftText = label + tail
        let rightText = hfmt(retPct, 1) + "%"
        return HStack(spacing: 8) {
            Text(leftText)
                .font(.system(size: 11.5, weight: warn ? .bold : .regular))
                .foregroundColor(warn ? HLWarn : HLText)
            Spacer()
            Text(rightText)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(hcolor(retPct))
        }
        .padding(.vertical, 3)
    }

    var sellCompareSpreadText: String {
        return hfmt(m.sellCompareSpread, 1)
    }

    var sellCompareCard: some View {
        let names = ["RSI>70 卖", "跌破 MA20 卖", "一直不卖"]
        let kinds = [15, 16, 17]
        let warns = [true, false, false]
        return VStack(spacing: 8) {
            Text("卖出方式决定成败")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(HLText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("三者的买入规则完全相同（RSI<30 买），只换卖出规则。差距全部来自「卖」。")
                .font(.system(size: 10))
                .foregroundColor(HLDim2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(0..<3, id: \.self) { j in
                self.sellCompareRowView(kinds[j], names[j], warns[j])
            }
            Text("极差 " + sellCompareSpreadText + " 个百分点")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(HLWarn)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("涨多了就卖会在上涨行情里持续失血。若坚持左侧买入，卖出应改用趋势破位，而不是 RSI 高位。")
                .font(.system(size: 10))
                .foregroundColor(HLDim2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text("窗口限定：卖出极差随持有期拉长而放大（6个月约10个点、3年约56个点）。短窗口内结论可能相反——样本越短，越看不出卖出方式的影响。")
                .font(.system(size: 10))
                .foregroundColor(HLWarn)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))
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
                Text("排序口径：收益 − 0.8×最大回撤（风险调整），不是单纯比收益。它与上方「策略适配度」卡片的夏普改善同属风险口径，但算法不等价，两处数字请勿直接比较。")
                    .font(.system(size: 10.5))
                    .foregroundColor(HLDim2)
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
                    Text(m.voteBullBearText)
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
                Text("各策略在同一段历史上的表现（已扣 20bps 往返成本，信号次日开盘执行）")
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

            // 卖出方式对比：固定买入规则，只换卖出
            sellCompareCard

            // V2 回测引擎：T+1 + 成本 + 期望值
            VStack(spacing: 8) {
                Text("回测引擎 V2 · 更接近真实交易")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(HLDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("旧引擎默认「当天信号当天收盘成交」，实际做不到。V2 改为：信号日收盘产生 → 次日开盘成交（T+1），并计入万三单边成本。下面每个数字都扣了成本。")
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 5) {
                    Text("策略").font(.system(size: 9)).foregroundColor(HLDim2).frame(width: 96, alignment: .leading)
                    Text("净值").font(.system(size: 9)).foregroundColor(HLDim2).frame(width: 50, alignment: .trailing)
                    Text("回撤").font(.system(size: 9)).foregroundColor(HLDim2).frame(width: 42, alignment: .trailing)
                    Text("笔").font(.system(size: 9)).foregroundColor(HLDim2).frame(width: 28, alignment: .trailing)
                    Text("期望").font(.system(size: 9)).foregroundColor(HLDim2).frame(width: 46, alignment: .trailing)
                    Text("PF").font(.system(size: 9)).foregroundColor(HLDim2).frame(width: 34, alignment: .trailing)
                }
                .padding(.horizontal, 6)

                ForEach(Array(0..<m.v2Count), id: \.self) { i in
                    self.v2RowView(i)
                }

                Text("期望 = 胜率×平均盈利 + (1−胜率)×平均亏损，是每笔交易的平均期望收益。PF（利润因子）= 总盈利÷总亏损，小于 1 意味着长期必亏。这两个比胜率重要得多。")
                    .font(.system(size: 9.5))
                    .foregroundColor(HLDim2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                self.v2BestCard()
            }
            .padding(13)
            .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

            // 稳健度检验：比"谁收益高"更重要
            VStack(spacing: 9) {
                Text("稳健度检验 · 是不是凑出来的")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(HLDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("收益高不等于策略好。这里做两件事：换几组参数看是否还赚钱、把历史切两段看是否都为正。任一不过关，就说明结果可能是数据凑出来的。")
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    robustCell(title: "MACD 改良版", mode: 0)
                    robustCell(title: "三指标共振", mode: 1)
                }

                Text("等级说明：稳定 = 换参数都赚且两段都为正；较稳 = 多数参数赚；一般 = 一半参数赚；脆弱 = 多数参数亏，收益很可能来自过拟合。")
                    .font(.system(size: 9.5))
                    .foregroundColor(HLDim2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)
            .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

            // 证据门禁：DSR
            VStack(spacing: 9) {
                Text("证据门禁 · 这个结果能不能信")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(HLDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("夏普衡量收益稳定性；DSR 是扣除「从多组参数里挑最好的」这一偏差后的可信度。DSR 越接近 100% 越可信，低于 90% 基本可视为运气。")
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text("策略").font(.system(size: 9.5)).foregroundColor(HLDim2)
                        .frame(width: 104, alignment: .leading)
                    Text("夏普").font(.system(size: 9.5)).foregroundColor(HLDim2)
                        .frame(width: 46, alignment: .trailing)
                    Text("DSR").font(.system(size: 9.5)).foregroundColor(HLDim2)
                        .frame(width: 52, alignment: .trailing)
                    Text("结论").font(.system(size: 9.5)).foregroundColor(HLDim2)
                        .frame(width: 62, alignment: .trailing)
                    Spacer()
                }
                .padding(.horizontal, 8)
                ForEach([0, 7, 8, 9, 11, 12], id: \.self) { i in
                    self.evidenceRow(i)
                }

                Text("达到可信所需样本长度（三指标共振）: " + m.minTRLText(9))
                    .font(.system(size: 9.5))
                    .foregroundColor(HLUp)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("噪声门槛: " + m.noiseFloorText())
                    .font(.system(size: 9.5))
                    .foregroundColor(HLUp)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text("若所需样本长达数万年，说明现有几百根K线根本不足以证明它有效 —— 这类结果应视为运气，而不是策略。")
                    .font(.system(size: 9.5))
                    .foregroundColor(HLDim2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)
            .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

            // 统计修正：Newey-West / 波动率成本 / Rank IC / Purge-Embargo
            VStack(spacing: 9) {
                Text("统计修正 · 此前结果高估了多少")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(HLDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("逐日滚动的前瞻窗口互相重叠，会把 t 值放大约 √持有期 倍；固定买卖价差则忽略高波动时成本更贵。这里按学术口径逐项修正。")
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text("① t 值修正（20日波动 → 未来20日收益）")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(HLDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                hrow("Pearson IC", hfmt(m.statFixFactor[0], 3), HLDim)
                hrow("Rank IC（更抗离群值）", hfmt(m.statFixFactor[1], 3), HLDim)
                hrow("ICIR", hfmt(m.statFixFactor[2], 2), HLDim)
                hrow("未修正 t", hfmt(m.statFixFactor[3], 2), m.statFixFactorNaiveColor)
                hrow("Newey-West t", hfmt(m.statFixFactor[4], 2), m.statFixFactorNWColor)
                hrow("非重叠相位 t", hfmt(m.statFixFactor[5], 2), m.statFixFactorNoColor)
                Text(HLCore.hlFactorVerdict(m.statFixFactor))
                    .font(.system(size: 9.5))
                    .foregroundColor(m.statFixFactorVerdictColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text("② 成本修正（固定价差 → 波动率调整）")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(HLDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                hrow("固定 20bps 收益", hfmt(m.statFixCost[0], 2) + "%", HLDim)
                hrow("波动率调整后收益", hfmt(m.statFixCost[1], 2) + "%", HLDim)
                hrow("成本拖累", hfmt(m.statFixCost[2], 2) + " 个百分点", m.statFixCostColor)
                hrow("换手次数", String(Int(m.statFixCost[3])), HLDim)
                Text(HLCore.hlCostCompareText(m.statFixCost))
                    .font(.system(size: 9.5))
                    .foregroundColor(HLDim2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text("③ 切分净化（Purge + Embargo）")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(HLDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                hrow("训练段剔除", String(m.statFixSplit[1] - m.statFixSplit[0]) + " 根", HLDim)
                hrow("测试段后禁运", String(m.closesCount - m.statFixSplit[2]) + " 根", HLDim)
                Text("训练段末尾样本的前瞻标签会伸进测试段，必须剔除；测试段之后还要留白，否则特征含测试期信息。")
                    .font(.system(size: 9.5))
                    .foregroundColor(HLDim2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)
            .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

            // 状态画像：涨的时候参数是什么 / 跌的时候参数是什么
            VStack(spacing: 9) {
                Text("状态画像 · 同一个指标在两种状态下含义不同")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(HLDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("把历史切成上涨态与下跌态，分别统计各指标的取值与后续表现。同一档位的 RSI 在跌势里与涨势里，含义可能完全相反 —— 这里只用于「解读」指标，不用于预测反转。")
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                if m.stateProf.ok {
                    HStack(spacing: 8) {
                        Text("当前状态")
                            .font(.system(size: 11))
                            .foregroundColor(HLDim2)
                        Spacer()
                        Text(m.stateProfName)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(m.stateProfColor)
                    }
                    hrow("过去60日涨跌", hfmt(m.stateProf.r60, 1) + "%", m.stateProfColor)
                    hrow("已持续", String(m.stateProf.days) + " 个交易日", HLDim)
                    hrow("历史样本", String(m.stateProf.nSample) + " 天", HLDim)

                    Text("两态后续表现（标的内去均值，前瞻 20 日）")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                    hrow("下跌态后续超额", hfmt(m.stateProf.fwdDnAll, 2) + "%", HLDim)
                    hrow("上涨态后续超额", hfmt(m.stateProf.fwdUpAll, 2) + "%", HLDim)
                    hrow("两态差（跌−涨）", hfmt(m.stateFwdGap, 2) + " 个百分点", m.stateFwdGapColor)
                    hrow("t 值（重叠样本）", hfmt(m.stateProf.tOverlap, 2), HLDim)
                    hrow("t 值（非重叠取样）", hfmt(m.stateProf.tNonOverlap, 2),
                         abs(m.stateProf.tNonOverlap) > 2.0 ? HLWarn : HLDim)
                    hrow("状态盲指标", String(m.stateBlindCount) + " / "
                         + String(m.stateProf.feats.count), m.stateBlindCount > 0 ? HLWarn : HLDim)
                    hrow("IC 符号翻转", String(m.stateFlipCount) + " / "
                         + String(m.stateProf.feats.count), m.stateFlipCount > 0 ? HLWarn : HLDim)

                    if m.stateNonOverlapWarn {
                        Text("⚠ 重叠样本 t=" + hfmt(m.stateProf.tOverlap, 2) +
                             " 看似显著，非重叠取样后仅 " + hfmt(m.stateProf.tNonOverlap, 2) +
                             " —— 该反转规律很可能是滚动窗口自相关造出的假象，不可据此抄底。")
                            .font(.system(size: 9.5))
                            .foregroundColor(HLUp)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("各指标：当前档位下的两态差异")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)

                    ForEach(0..<m.stateProf.feats.count, id: \.self) { k in
                        stateFeatRow(m.stateProf.feats[k])
                    }

                    Text("效应量 d =（上涨态均值 − 下跌态均值）/ 合并标准差。|d| < 0.20 标为「状态盲」—— 该指标自己看不见市场在涨还是在跌，用它做依赖状态的判断必然失灵（MACD 柱、量比实测即属此类）。构造类型解释了成因：相对位置类对状态极敏感，而 MACD 柱是「差分的差分」，构造上就丢掉了位置信息。IC 为该指标值与后续 20 日超额的相关系数，两态符号相反标为「翻转」—— 同一数值在涨势与跌势里说的是相反的话，必须结合状态解读。")
                        .font(.system(size: 9.5))
                        .foregroundColor(HLDim2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(m.stateProfText)
                        .font(.system(size: 10))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("历史样本不足（需 140 根以上 K 线），无法建立状态画像。")
                        .font(.system(size: 10.5))
                        .foregroundColor(HLDim2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(13)
            .background(RoundedRectangle(cornerRadius: 14).fill(HLCard))

            // 二维状态面板：趋势 × 波动 六象限
            VStack(spacing: 9) {
                Text("二维状态面板 · 上涨率高 ≠ 收益高")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(HLDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("状态不止一维：趋势方向之外，波动高低也独立起作用。六象限同时给出「横截面上涨率」与「时序回测收益」—— 实测二者常不一致，只看上涨率会选错象限。")
                    .font(.system(size: 10))
                    .foregroundColor(HLDim2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                if m.regime2D.ok {
                    hrow("当前象限",
                         HLCore.stateName(m.regime2D.curTrend) + " · "
                         + (m.regime2D.curVol == 1 ? "高波动" : "低波动"), HLDim)
                    hrow("波动切分阈值", hfmt(m.regime2D.volSplit, 1) + "%", HLDim)
                    hrow("横截面最优", m.regimeCrossName, HLDim)
                    hrow("时序最优", m.regimeTsName, HLDim)
                    hrow("两者是否一致", m.regime2D.conflict ? "不一致 ⚠" : "一致",
                         m.regime2D.conflict ? HLWarn : HLDim)
                    hrow("「涨态就买」基准", hfmt(m.regime2D.tsHold, 2) + "%", HLDim)
                    hrow("跑赢基准的象限", String(m.regime2D.tsHoldN) + " / 6", HLDim)

                    ForEach(0..<m.regime2D.cells.count, id: \.self) { k in
                        regimeCellRow(m.regime2D.cells[k],
                                      isCur: m.regimeIsCur(k),
                                      isCross: k == m.regime2D.crossBest,
                                      isTs: k == m.regime2D.tsBest)
                    }

                    if m.regime2D.conflict {
                        Text("⚠ 横截面与时序不一致：上涨率最高的象限，时序收益并非最高。上涨率高只说明「常小赚」，连续持仓复利下，「少赚但偶有大赚」的象限可能反超。不要直接用上涨率挑象限。")
                            .font(.system(size: 9.5))
                            .foregroundColor(HLUp)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("时序回测为无偷价口径：信号由前一日收盘产生，次日开盘成交，收益记开盘到开盘，每次进出扣 10bps。")
                        .font(.system(size: 9.5))
                        .foregroundColor(HLDim2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(m.regime2DText)
                        .font(.system(size: 10))
                        .foregroundColor(HLDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("历史样本不足（需 200 根以上 K 线），无法建立二维状态面板。")
                        .font(.system(size: 10.5))
                        .foregroundColor(HLDim2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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
                hrow("匹配样本", m.similarSampleText, HLDim)
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
                Text(m.gridSummaryText)
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

                VStack(alignment: .leading, spacing: 5) {
                    Text("样本重叠校正")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(HLDim)
                    Text("原始样本 绿 \(Int(m.greenQAdj[0]))／红 \(Int(m.redQAdj[0])) → 20日窗口逐日滑动，有效独立样本仅 \(Int(m.greenQAdj[1]))／\(Int(m.redQAdj[1]))")
                        .font(.system(size: 9))
                        .foregroundColor(HLDim2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(m.overlapWarnText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(HLWarn)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 9).fill(HLCard2))

                VStack(alignment: .leading, spacing: 5) {
                    Text("跨标的实测参考 · " + m.assetClsName)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(HLDim)
                    Text(m.clsHintText)
                        .font(.system(size: 10))
                        .foregroundColor(HLDim2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("来源：70 标的 × 800 交易日实测，剔市场beta、非重叠取样（2023-06 ~ 2026-09）")
                        .font(.system(size: 8))
                        .foregroundColor(HLDim2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 9).fill(HLCard2))

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
    @State var didInit: Bool = false

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
            m.loadWatch()
            if didInit == false {
                didInit = true
                if m.watch.isEmpty { tab = 4 }
            }
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
