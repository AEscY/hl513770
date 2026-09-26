import Foundation

struct Indicators {
    /// 简单移动平均，取第 i 根（默认最后一根）
    static func ma(_ arr: [Double], _ k: Int, at i: Int? = nil) -> Double? {
        let idx = i ?? arr.count - 1
        guard idx + 1 >= k, k > 0 else { return nil }
        var s = 0.0
        for j in (idx - k + 1)...idx { s += arr[j] }
        return s / Double(k)
    }

    /// RSI（Wilder 平滑）
    static func rsi(_ arr: [Double], _ k: Int) -> Double? {
        guard arr.count > k else { return nil }
        var gain = 0.0, loss = 0.0
        for i in 1...k {
            let ch = arr[i] - arr[i - 1]
            if ch > 0 { gain += ch } else { loss -= ch }
        }
        var ag = gain / Double(k), al = loss / Double(k)
        if arr.count > k + 1 {
            for i in (k + 1)..<arr.count {
                let ch = arr[i] - arr[i - 1]
                ag = (ag * Double(k - 1) + (ch > 0 ? ch : 0)) / Double(k)
                al = (al * Double(k - 1) + (ch < 0 ? -ch : 0)) / Double(k)
            }
        }
        if al <= 0 { return 100 }
        return 100 - 100 / (1 + ag / al)
    }

    /// 标准差
    static func std(_ w: [Double]) -> Double {
        guard !w.isEmpty else { return 0 }
        let m = w.reduce(0, +) / Double(w.count)
        let v = w.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(w.count)
        return sqrt(v)
    }

    /// ATR（Wilder 平滑）
    static func atr(o: [Double], h: [Double], l: [Double], c: [Double], k: Int) -> Double? {
        var tr: [Double] = []
        for i in 1..<c.count {
            tr.append(max(h[i] - l[i], abs(h[i] - c[i - 1]), abs(l[i] - c[i - 1])))
        }
        guard tr.count >= k else { return nil }
        var a = tr[0..<k].reduce(0, +) / Double(k)
        if tr.count > k {
            for i in k..<tr.count { a = (a * Double(k - 1) + tr[i]) / Double(k) }
        }
        return a
    }

    /// 信号判定：价 < MA20 红；MA20 ≤ 价 < MA60 黄；价 ≥ MA60 绿
    static func signal(price: Double, ma20: Double?, ma60: Double?) -> Signal {
        guard let m20 = ma20, let m60 = ma60 else { return .none }
        let p = (price * 1000).rounded() / 1000
        let a = (m20 * 1000).rounded() / 1000
        let b = (m60 * 1000).rounded() / 1000
        if p < a { return .red }
        if p < b { return .yellow }
        return .green
    }

    /// 明日变黄门槛：价 > 前19日均值
    static func nextYellowThreshold(_ c: [Double]) -> Double? {
        guard c.count >= 19 else { return nil }
        let w = Array(c.suffix(19))
        return w.reduce(0, +) / Double(w.count)
    }

    /// 明日变绿门槛：价 > 最近（最多59日）均值
    static func nextGreenThreshold(_ c: [Double]) -> Double? {
        guard !c.isEmpty else { return nil }
        let w = Array(c.suffix(min(59, c.count)))
        return w.reduce(0, +) / Double(w.count)
    }

    /// 20日年化波动率（%）
    static func annualVol(_ c: [Double], window: Int = 20) -> Double? {
        guard c.count > window else { return nil }
        var rets: [Double] = []
        let start = c.count - window
        for i in start..<c.count { rets.append(log(c[i] / c[i - 1])) }
        let m = rets.reduce(0, +) / Double(rets.count)
        let v = rets.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(rets.count - 1)
        return sqrt(v) * sqrt(244) * 100
    }

    /// 近N日日均振幅（%）
    static func avgAmplitude(h: [Double], l: [Double], c: [Double], n: Int = 20) -> Double? {
        guard c.count > n else { return nil }
        var s = 0.0, cnt = 0
        let start = c.count - n
        for i in start..<c.count {
            s += (h[i] - l[i]) / c[i - 1]
            cnt += 1
        }
        return cnt > 0 ? s / Double(cnt) * 100 : nil
    }

    /// 回测：红灯空仓、黄灯半仓、绿灯满仓
    static func backtest(_ c: [Double]) -> (hold: Double, strat: Double, ddHold: Double, ddStrat: Double, curve: [Double], stratCurve: [Double]) {
        var hold = 1.0, strat = 1.0
        var hc = [1.0], sc = [1.0]
        for i in 1..<c.count {
            let ret = c[i] / c[i - 1]
            hold *= ret
            hc.append(hold)
            // 用 i-1 的信号决定 i 的仓位（无未来函数）
            let m20 = ma(c, 20, at: i - 1)
            let m60 = ma(c, 60, at: i - 1)
            let sg = signal(price: c[i - 1], ma20: m20, ma60: m60)
            let pos: Double = sg == .green ? 1.0 : (sg == .yellow ? 0.5 : 0.0)
            strat *= (1 + pos * (ret - 1))
            sc.append(strat)
        }
        func maxDD(_ a: [Double]) -> Double {
            var peak = 1.0, dd = 0.0
            for v in a { if v > peak { peak = v }; dd = max(dd, (peak - v) / peak) }
            return dd
        }
        return (hold, strat, maxDD(hc), maxDD(sc), hc, sc)
    }
}
