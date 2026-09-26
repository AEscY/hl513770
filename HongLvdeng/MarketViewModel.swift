import Foundation
import SwiftUI

final class MarketViewModel: ObservableObject {

    // 当前标的
    @Published var candles: [Candle] = []
    @Published var quote: Quote?
    @Published var isLoading = false
    @Published var loadFailed = false
    @Published var dataNote = ""

    // 简报
    @Published var globalQuotes: [String: Quote] = [:]
    @Published var adrQuotes: [String: Quote] = [:]
    @Published var holdingQuotes: [String: Quote] = [:]

    // 自选（由 Store 持有，这里只做行情刷新）
    var store: Store?

    // MARK: - 派生指标

    var closes: [Double] { candles.map { $0.close } }
    var highs: [Double] { candles.map { $0.high } }
    var lows: [Double] { candles.map { $0.low } }
    var opens: [Double] { candles.map { $0.open } }

    var lastPrice: Double { quote?.price ?? closes.last ?? 0 }
    var ma5: Double? { Indicators.ma(closes, 5) }
    var ma20: Double? { Indicators.ma(closes, 20) }
    var ma60: Double? { Indicators.ma(closes, 60) }
    var ma120: Double? { Indicators.ma(closes, 120) }

    var signal: Signal { Indicators.signal(price: lastPrice, ma20: ma20, ma60: ma60) }

    var rsi6: Double? { Indicators.rsi(closes, 6) }
    var rsi14: Double? { Indicators.rsi(closes, 14) }
    var atr: Double? { Indicators.atr(o: opens, h: highs, l: lows, c: closes, k: 14) }
    var nextYellow: Double? { Indicators.nextYellowThreshold(closes) }
    var nextGreen: Double? { Indicators.nextGreenThreshold(closes) }
    var annualVol: Double? { Indicators.annualVol(closes) }
    var avgAmp: Double? { Indicators.avgAmplitude(h: highs, l: lows, c: closes) }

    var periodHigh: Double { closes.max() ?? 0 }
    var periodLow: Double { closes.min() ?? 0 }
    var percentile: Double {
        let r = periodHigh - periodLow
        guard r > 0 else { return 0 }
        return (lastPrice - periodLow) / r * 100
    }

    /// 建议止损 = 现价 - 2×ATR
    var stopLoss: Double? {
        guard let a = atr else { return nil }
        return lastPrice - 2 * a
    }

    var bollinger: (up: Double, mid: Double, low: Double, width: Double)? {
        guard closes.count >= 20 else { return nil }
        let w = Array(closes.suffix(20))
        let mid = w.reduce(0, +) / 20
        let sd = Indicators.std(w)
        return (mid + 2 * sd, mid, mid - 2 * sd, (4 * sd) / mid * 100)
    }

    // MARK: - 加载

    func load(code: String, force: Bool = false) {
        isLoading = true
        loadFailed = false
        let group = DispatchGroup()

        group.enter()
        QuoteService.shared.fetchQuotes([code]) { [weak self] map in
            if let q = map[code] {
                self?.quote = q
                self?.store?.updatePrice(code: code, price: q.price, pct: q.changePct, signal: nil)
            }
            group.leave()
        }

        group.enter()
        QuoteService.shared.fetchHistory(code) { [weak self] list in
            self?.candles = list
            if list.isEmpty { self?.loadFailed = true }
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isLoading = false
            // 用最新收盘覆盖最后一根（实时价）
            if let q = self.quote, !self.candles.isEmpty {
                var c = self.candles[self.candles.count - 1]
                c = Candle(date: c.date, open: c.open, high: max(c.high, q.price),
                           low: min(c.low, q.price), close: q.price)
                self.candles[self.candles.count - 1] = c
            }
            if let st = self.store {
                st.updatePrice(code: code, price: self.lastPrice,
                               pct: self.quote?.changePct, signal: self.signal)
            }
            // 交易时段每分钟自动刷新
            if !self.candles.isEmpty {
                self.dataNote = "最新 \(self.candles.last?.date ?? "") · \(self.candles.count) 个交易日"
            }
        }
    }

    /// 简报：外围 + ADR + 成分股（一次批量各一个请求）
    func loadBrief() {
        let g = Presets.globalIdx.map { $0.code }
        QuoteService.shared.fetchQuotes(g) { [weak self] m in self?.globalQuotes = m }

        let a = Presets.adrs.map { $0.code }
        QuoteService.shared.fetchQuotes(a) { [weak self] m in self?.adrQuotes = m }

        let h = Presets.holdings.map { $0.code }
        QuoteService.shared.fetchQuotes(h) { [weak self] m in self?.holdingQuotes = m }
    }

    /// 刷新自选列表价格
    func refreshWatchList() {
        guard let st = store, !st.watchList.isEmpty else { return }
        let codes = st.watchList.map { $0.code }
        QuoteService.shared.fetchQuotes(codes) { [weak self] map in
            guard let self = self, let st = self.store else { return }
            for item in st.watchList {
                if let q = map[item.code] {
                    st.updatePrice(code: item.code, price: q.price, pct: q.changePct, signal: nil)
                }
            }
        }
    }

    /// ADR 加权估算（%）
    var adrEstimate: Double? {
        var sw = 0.0, se = 0.0
        for a in Presets.adrs {
            guard let q = adrQuotes[a.code] else { continue }
            sw += a.weight
            se += a.weight * q.changePct
        }
        return sw > 0 ? se / sw : nil
    }
    var adrCoverage: Double {
        Presets.adrs.reduce(0) { $0 + (adrQuotes[$1.code] != nil ? $1.weight : 0) }
    }

    /// 成分股加权方向（%）
    var holdingEstimate: Double? {
        var sw = 0.0, se = 0.0
        for h in Presets.holdings {
            guard let q = holdingQuotes[h.code] else { continue }
            sw += h.weight
            se += h.weight * q.changePct
        }
        return sw > 0 ? se / sw : nil
    }
    var holdingCoverage: Double {
        Presets.holdings.reduce(0) { $0 + (holdingQuotes[$1.code] != nil ? $1.weight : 0) }
    }
}

// MARK: - 交易时段

enum MarketClock {
    static func status() -> (text: String, isLive: Bool) {
        let cal = Calendar.current
        let now = Date()
        let wd = cal.component(.weekday, from: now)
        let h = cal.component(.hour, from: now)
        let m = cal.component(.minute, from: now)
        if wd == 1 || wd == 7 { return ("周末休市", false) }
        let t = h * 60 + m
        func left(_ end: Int) -> String {
            let d = max(0, end - t)
            return d >= 60 ? "\(d / 60) 小时 \(d % 60) 分" : "\(d) 分钟"
        }
        if t < 570 { return ("盘前准备 · 距开盘 " + left(570), false) }
        if t < 690 { return ("交易中 · 距午休 " + left(690), true) }
        if t < 780 { return ("午间休市 · 距开盘 " + left(780), false) }
        if t < 900 { return ("交易中 · 距收盘 " + left(900), true) }
        return ("今日已收盘", false)
    }
}
