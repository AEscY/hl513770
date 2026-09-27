import Foundation

// MARK: - 纯算法核心（不依赖 SwiftUI / UIKit，可在命令行独立编译运行）
// 主 App 与云端验证程序共用这一份实现，保证"验证的就是跑的"

// MARK: - 异常检测项
// level: 0 正常 / 1 注意 / 2 异动
struct HLAnomalyItem {
    var name: String = ""
    var value: String = ""
    var level: Int = 0
    var hint: String = ""
}

struct HLCore {

    // ---------- 均线 ----------
    static func maAt(_ a: [Double], _ k: Int, _ idx: Int) -> Double? {
        if k <= 0 { return nil }
        if idx < 0 || idx >= a.count { return nil }
        if idx + 1 < k { return nil }
        var s = 0.0
        var i = idx - k + 1
        while i <= idx { s += a[i]; i += 1 }
        return s / Double(k)
    }

    static func ma(_ a: [Double], _ k: Int) -> Double? {
        if a.isEmpty { return nil }
        return maAt(a, k, a.count - 1)
    }

    // ---------- RSI ----------
    static func rsiAt(_ a: [Double], _ k: Int, _ idx: Int) -> Double? {
        if idx < k || idx >= a.count || k <= 0 { return nil }
        var gain = 0.0
        var loss = 0.0
        var i = idx - k + 1
        while i <= idx {
            let d = a[i] - a[i - 1]
            if d > 0 { gain += d } else { loss += (-d) }
            i += 1
        }
        if loss <= 0 { return gain > 0 ? 100 : 50 }
        if gain <= 0 { return 0 }
        let rs = (gain / Double(k)) / (loss / Double(k))
        return 100 - 100 / (1 + rs)
    }

    static func rsi(_ a: [Double], _ k: Int) -> Double? {
        if a.isEmpty { return nil }
        return rsiAt(a, k, a.count - 1)
    }

    // ---------- ATR ----------
    static func atr(highs: [Double], lows: [Double], closes: [Double], k: Int) -> Double? {
        let n = min(highs.count, min(lows.count, closes.count))
        if n < k + 1 || k <= 0 { return nil }
        var sum = 0.0
        var i = n - k
        while i < n {
            let h = highs[i]
            let l = lows[i]
            let pc = closes[i - 1]
            let tr = max(h - l, max(abs(h - pc), abs(l - pc)))
            sum += tr
            i += 1
        }
        return sum / Double(k)
    }

    // ---------- 布林带 ----------
    static func bollAt(_ a: [Double], _ k: Int, _ idx: Int) -> (mid: Double, up: Double, low: Double)? {
        guard let mid = maAt(a, k, idx) else { return nil }
        var sum = 0.0
        var i = idx - k + 1
        while i <= idx { let d = a[i] - mid; sum += d * d; i += 1 }
        let sd = sqrt(sum / Double(k))
        return (mid, mid + 2 * sd, mid - 2 * sd)
    }

    static func bollUpAt(_ a: [Double], _ k: Int, _ idx: Int) -> Double? {
        return bollAt(a, k, idx)?.up
    }

    static func bollLowAt(_ a: [Double], _ k: Int, _ idx: Int) -> Double? {
        return bollAt(a, k, idx)?.low
    }

    // ---------- EMA ----------
    static func ema(_ a: [Double], _ k: Int) -> [Double] {
        if a.isEmpty || k <= 0 { return [] }
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

    // ---------- MACD ----------
    static func macd(_ a: [Double]) -> (dif: Double, dea: Double, bar: Double)? {
        if a.count < 26 { return nil }
        let e12 = ema(a, 12)
        let e26 = ema(a, 26)
        var difLine: [Double] = []
        var i = 0
        while i < a.count { difLine.append(e12[i] - e26[i]); i += 1 }
        let deaLine = ema(difLine, 9)
        let dif = difLine[difLine.count - 1]
        let dea = deaLine[deaLine.count - 1]
        return (dif, dea, (dif - dea) * 2)
    }

    // ---------- KDJ ----------
    static func kdj(highs: [Double], lows: [Double], closes: [Double], k: Int) -> (k: Double, d: Double, j: Double)? {
        let n = min(highs.count, min(lows.count, closes.count))
        if n < k || k <= 0 { return nil }
        var rsv: [Double] = []
        var i = k - 1
        while i < n {
            var hi = highs[i]
            var lo = lows[i]
            var t = i - k + 1
            while t <= i {
                if highs[t] > hi { hi = highs[t] }
                if lows[t] < lo { lo = lows[t] }
                t += 1
            }
            let v = (hi > lo) ? (closes[i] - lo) / (hi - lo) * 100 : 50
            rsv.append(v)
            i += 1
        }
        var kk = 50.0
        var dd = 50.0
        i = 0
        while i < rsv.count {
            kk = (2.0 / 3.0) * kk + (1.0 / 3.0) * rsv[i]
            dd = (2.0 / 3.0) * dd + (1.0 / 3.0) * kk
            i += 1
        }
        return (kk, dd, 3 * kk - 2 * dd)
    }

    // ---------- 收益率序列 ----------
    static func rets(_ a: [Double]) -> [Double] {
        if a.count < 2 { return [] }
        var out: [Double] = []
        var i = 1
        while i < a.count { out.append(a[i] / a[i - 1] - 1); i += 1 }
        return out
    }

    static func mean(_ a: [Double]) -> Double {
        if a.isEmpty { return 0 }
        var s = 0.0
        var i = 0
        while i < a.count { s += a[i]; i += 1 }
        return s / Double(a.count)
    }

    static func stdev(_ a: [Double]) -> Double {
        if a.count < 2 { return 0 }
        let m = mean(a)
        var v = 0.0
        var i = 0
        while i < a.count { let d = a[i] - m; v += d * d; i += 1 }
        return sqrt(v / Double(a.count - 1))
    }

    // ---------- VaR / CVaR ----------
    static func varHist(_ r: [Double], _ p: Double) -> Double {
        if r.isEmpty { return 0 }
        let s = r.sorted()
        var idx = Int((1 - p) * Double(s.count))
        if idx < 0 { idx = 0 }
        if idx >= s.count { idx = s.count - 1 }
        return s[idx]
    }

    static func cvarHist(_ r: [Double], _ p: Double) -> Double {
        if r.isEmpty { return 0 }
        let s = r.sorted()
        var idx = Int((1 - p) * Double(s.count))
        if idx < 1 { idx = 1 }
        if idx > s.count { idx = s.count }
        var sum = 0.0
        var i = 0
        while i < idx { sum += s[i]; i += 1 }
        return sum / Double(idx)
    }

    static func varParam(_ r: [Double], _ p: Double) -> Double {
        let z = (p >= 0.99) ? 2.3263 : 1.6449
        return mean(r) - z * stdev(r)
    }

    // ---------- 风险调整 ----------
    static func annVol(_ r: [Double]) -> Double { stdev(r) * sqrt(252.0) }

    static func annRet(_ a: [Double]) -> Double {
        if a.count < 30 || a[0] <= 0 { return 0 }
        let years = Double(a.count) / 252.0
        if years <= 0 { return 0 }
        return pow(a[a.count - 1] / a[0], 1.0 / years) - 1
    }

    static func sharpe(_ a: [Double]) -> Double {
        let v = annVol(rets(a))
        if v <= 0 { return 0 }
        return (annRet(a) - 0.02) / v
    }

    static func maxDD(_ a: [Double]) -> Double {
        if a.isEmpty { return 0 }
        var peak = a[0]
        var dd = 0.0
        var i = 0
        while i < a.count {
            if a[i] > peak { peak = a[i] }
            let d = (peak - a[i]) / peak
            if d > dd { dd = d }
            i += 1
        }
        return dd
    }

    static func maxUnderwater(_ a: [Double]) -> Int {
        if a.isEmpty { return 0 }
        var peak = a[0]
        var cur = 0
        var mx = 0
        var i = 0
        while i < a.count {
            if a[i] >= peak { peak = a[i]; cur = 0 }
            else { cur += 1; if cur > mx { mx = cur } }
            i += 1
        }
        return mx
    }

    // ---------- 波动率锥 ----------
    static func volCone(_ r: [Double], _ k: Int) -> Double? {
        if k <= 0 || r.count < k * 3 { return nil }
        var agg: [Double] = []
        var i = k
        while i + k <= r.count {
            var s = 0.0
            var j = i
            while j < i + k { s += r[j]; j += 1 }
            agg.append(s)
            i += k
        }
        if agg.count < 2 { return nil }
        let sd = stdev(agg)
        return sd * sqrt(252.0 / Double(k))
    }

    // ---------- EWMA ----------
    static func ewmaVol(_ r: [Double], _ lambda: Double) -> Double {
        if r.isEmpty { return 0 }
        var v = r[0] * r[0]
        var i = 1
        while i < r.count {
            v = lambda * v + (1 - lambda) * r[i] * r[i]
            i += 1
        }
        return sqrt(v * 252.0)
    }

    // ---------- 赫斯特指数 ----------
    static func hurst(_ a: [Double]) -> Double? {
        if a.count < 60 { return nil }
        var lx: [Double] = []
        var ly: [Double] = []
        var lag = 8
        let lim = min(60, a.count / 4)
        while lag <= lim {
            var diffs: [Double] = []
            var i = 0
            while i + lag < a.count { diffs.append(a[i + lag] - a[i]); i += 1 }
            if diffs.count >= 5 {
                let sd = stdev(diffs)
                if sd > 0 {
                    lx.append(log(Double(lag)))
                    ly.append(log(sd))
                }
            }
            lag += 1
        }
        if lx.count < 4 { return nil }
        let mx = mean(lx)
        let my = mean(ly)
        var num = 0.0
        var den = 0.0
        var t = 0
        while t < lx.count {
            num += (lx[t] - mx) * (ly[t] - my)
            den += (lx[t] - mx) * (lx[t] - mx)
            t += 1
        }
        if den <= 0 { return nil }
        return num / den
    }

    // ---------- 回测（7 种策略）----------
    // 返回 [收益倍数, 最大回撤%, 交易次数, 胜率%]
    static func backtest(_ c: [Double], _ kind: Int) -> [Double] {
        if c.count < 70 { return [1, 0, 0, 0] }
        var v = 1.0
        var pos = 0.0
        var peak = 1.0
        var dd = 0.0
        var trades = 0
        var wins = 0
        var closed = 0
        var entry = 0.0
        var gridLevel = 0.0
        var i = 1
        while i < c.count {
            let prev = c[i - 1]
            var target = pos

            if kind == 0 {
                target = 1.0
            } else if kind == 1 {
                let m20 = maAt(c, 20, i - 1)
                let m60 = maAt(c, 60, i - 1)
                if m20 != nil && m60 != nil {
                    if prev >= m60! { target = 1.0 }
                    else if prev >= m20! { target = 0.5 }
                    else { target = 0.0 }
                }
            } else if kind == 2 {
                let m5 = maAt(c, 5, i - 1)
                let m20 = maAt(c, 20, i - 1)
                if m5 != nil && m20 != nil { target = (m5! > m20!) ? 1.0 : 0.0 }
            } else if kind == 3 {
                let r = rsiAt(c, 14, i - 1)
                if r != nil {
                    if r! < 30 { target = 1.0 }
                    if r! > 70 { target = 0.0 }
                }
            } else if kind == 4 {
                let up = bollUpAt(c, 20, i - 1)
                let lo = bollLowAt(c, 20, i - 1)
                if up != nil && lo != nil {
                    if prev <= lo! { target = 1.0 }
                    if prev >= up! { target = 0.0 }
                }
            } else if kind == 5 {
                if gridLevel <= 0 { gridLevel = prev }
                if prev <= gridLevel * 0.95 {
                    target = min(1.0, pos + 0.25); gridLevel = prev
                } else if prev >= gridLevel * 1.05 {
                    target = max(0.0, pos - 0.25); gridLevel = prev
                }
            } else if kind == 6 {
                if i % 20 == 0 { target = min(1.0, pos + 0.1) }
            }

            if target > pos + 0.001 || target < pos - 0.001 {
                if pos <= 0.001 && target > 0.001 { entry = c[i] }
                else if pos > 0.001 && target <= 0.001 {
                    closed += 1
                    if c[i] > entry { wins += 1 }
                }
                trades += 1
            }

            pos = target
            let ret = c[i] / prev
            v *= (1 + pos * (ret - 1))
            if v > peak { peak = v }
            let cur = (peak - v) / peak
            if cur > dd { dd = cur }
            i += 1
        }
        var wr = 0.0
        if closed > 0 { wr = Double(wins) / Double(closed) * 100 }
        return [v, dd * 100, Double(trades), wr]
    }

    static func strategyName(_ k: Int) -> String {
        let names = ["一直持有", "红绿灯", "双均线 MA5/20", "RSI 超卖反弹",
                     "布林带回归", "网格 每5%", "定投 每20日"]
        if k >= 0 && k < names.count { return names[k] }
        return "—"
    }

    // ---------- 形态特征 ----------
    static func featureAt(_ c: [Double], _ idx: Int) -> [Double] {
        var f: [Double] = [0, 0, 0, 0]
        let m5 = maAt(c, 5, idx)
        let m20 = maAt(c, 20, idx)
        let m60 = maAt(c, 60, idx)
        if m5 != nil && m20 != nil && m20! > 0 { f[0] = (m5! - m20!) / m20! * 100 }
        if m20 != nil && m60 != nil && m60! > 0 { f[1] = (m20! - m60!) / m60! * 100 }
        if let r = rsiAt(c, 14, idx) { f[2] = r }
        let n = min(60, idx + 1)
        let st = idx - n + 1
        if st >= 0 && idx < c.count {
            var hi = c[st]
            var lo = c[st]
            var i = st
            while i <= idx {
                if c[i] > hi { hi = c[i] }
                if c[i] < lo { lo = c[i] }
                i += 1
            }
            if hi > lo { f[3] = (c[idx] - lo) / (hi - lo) * 100 }
        }
        return f
    }

    // ---------- 历史相似形态 ----------
    // 返回 [样本数, 平均涨幅%, 上涨概率%, 最好, 最差, 上涨时平均涨, 下跌时平均跌]
    static func similarStats(_ c: [Double]) -> [Double] {
        if c.count < 120 { return [0, 0, 0, 0, 0, 0, 0] }
        let cur = featureAt(c, c.count - 1)
        let horizon = 20
        var pool: [[Double]] = []
        var i = 80
        while i <= c.count - 1 - horizon {
            let f = featureAt(c, i)
            let d0 = f[0] - cur[0]
            let d1 = f[1] - cur[1]
            let d2 = (f[2] - cur[2]) * 0.3
            let d3 = (f[3] - cur[3]) * 0.3
            let d = sqrt(d0 * d0 + d1 * d1 + d2 * d2 + d3 * d3)
            let fut = (c[i + horizon] / c[i] - 1) * 100
            pool.append([d, fut])
            i += 5
        }
        if pool.isEmpty { return [0, 0, 0, 0, 0, 0, 0] }
        var sorted: [[Double]] = []
        while sorted.count < 15 && pool.isEmpty == false {
            var bi = 0
            var j = 1
            while j < pool.count { if pool[j][0] < pool[bi][0] { bi = j }; j += 1 }
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
            if r > 0 { up += 1; winSum += r } else { lossSum += (-r) }
            if r > best { best = r }
            if r < worst { worst = r }
            k += 1
        }
        let n = Double(sorted.count)
        var avgWin = 0.0
        var avgLoss = 0.0
        if up > 0 { avgWin = winSum / Double(up) }
        if up < sorted.count { avgLoss = lossSum / Double(sorted.count - up) }
        return [n, sum / n, Double(up) / n * 100, best, worst, avgWin, avgLoss]
    }

    // ---------- 蒙特卡洛（确定性 LCG，可重复验证）----------
    static func lcg(_ seed: inout UInt64) -> Double {
        seed = (seed &* 6364136223846793005) &+ 1442695040888963407
        let x = Double(seed >> 11) / Double(1 << 53)
        return x
    }

    static func gauss(_ seed: inout UInt64) -> Double {
        var u = lcg(&seed)
        if u < 0.000001 { u = 0.000001 }
        if u > 0.999999 { u = 0.999999 }
        let v = lcg(&seed)
        return sqrt(-2.0 * log(u)) * cos(2.0 * Double.pi * v)
    }

    // 返回 [5%, 25%, 50%, 75%, 95%]
    static func monteCarlo(_ c: [Double], _ days: Int, _ sims: Int, _ seed0: UInt64) -> [Double] {
        if c.count < 30 || c[c.count - 1] <= 0 { return [0, 0, 0, 0, 0] }
        let r = rets(c)
        if r.isEmpty { return [0, 0, 0, 0, 0] }
        let tail = Array(r.suffix(60))
        let mu = mean(tail)
        let sd = stdev(tail)
        let p0 = c[c.count - 1]
        var finals: [Double] = []
        var seed = seed0
        var s = 0
        while s < sims {
            var p = p0
            var d = 0
            while d < days {
                p = p * (1 + mu + sd * gauss(&seed))
                if p < 0 { p = 0 }
                d += 1
            }
            finals.append(p)
            s += 1
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

    // ---------- 参数网格 ----------
    static func fastPeriods() -> [Int] { return [5, 10, 15, 20] }
    static func slowPeriods() -> [Int] { return [30, 40, 60, 80] }

    // 返回 [fast, slow, 收益%, 回撤%, 评分]
    static func gridAt(_ c: [Double], _ row: Int) -> [Double] {
        let fp = fastPeriods()
        let sp = slowPeriods()
        let f = fp[row / 4]
        let s = sp[row % 4]
        if f >= s || c.count < s + 5 { return [Double(f), Double(s), 0, 0, -999] }
        var v = 1.0
        var pos = 0.0
        var peak = 1.0
        var dd = 0.0
        var i = s
        while i < c.count {
            let mf = maAt(c, f, i - 1)
            let ms = maAt(c, s, i - 1)
            if mf != nil && ms != nil {
                let p = c[i - 1]
                var tgt = 0.0
                if p >= ms! { tgt = 1.0 }
                else if p >= mf! { tgt = 0.5 }
                let ret = c[i] / c[i - 1]
                v *= (1 + pos * (ret - 1))
                pos = tgt
            }
            if v > peak { peak = v }
            let cur = (peak - v) / peak
            if cur > dd { dd = cur }
            i += 1
        }
        return [Double(f), Double(s), (v - 1) * 100, dd * 100, (v - 1) * 100 - dd * 50]
    }

    // ---------- 信号质量审计 ----------
    // kind: 0红 1黄 2绿；返回 [样本数, 后20日平均%, 上涨率%]
    static func signalQuality(_ c: [Double], _ kind: Int) -> [Double] {
        if c.count < 90 { return [0, 0, 0] }
        var n = 0.0
        var sum = 0.0
        var up = 0.0
        let horizon = 20
        var i = 60
        while i + horizon < c.count {
            let m20 = maAt(c, 20, i)
            let m60 = maAt(c, 60, i)
            if m20 != nil && m60 != nil {
                let p = c[i]
                var sig = 0
                if p < m20! { sig = 0 }
                else if p < m60! { sig = 1 }
                else { sig = 2 }
                if sig == kind {
                    let fut = (c[i + horizon] / c[i] - 1) * 100
                    sum += fut
                    if fut > 0 { up += 1 }
                    n += 1
                }
            }
            i += 1
        }
        if n <= 0 { return [0, 0, 0] }
        return [n, sum / n, up / n * 100]
    }

    // ---------- 红绿灯判定 ----------
    static func bandAt(_ c: [Double], _ i: Int) -> Int {
        // 0=红 1=黄 2=绿 3=无
        if i >= c.count { return 3 }
        let m20 = maAt(c, 20, i)
        let m60 = maAt(c, 60, i)
        if m20 == nil || m60 == nil { return 3 }
        let p = c[i]
        if p < m20! { return 0 }
        if p < m60! { return 1 }
        return 2
    }

    // ---------- 市场异常扫描 ----------
    // 返回全部检测项（含正常项），调用方按 level 过滤
    static func anomalyScan(_ c: [Double], _ h: [Double], _ l: [Double],
                            _ o: [Double], _ v: [Double]) -> [HLAnomalyItem] {
        var out: [HLAnomalyItem] = []
        if c.count < 70 { return out }
        let n = c.count - 1
        let today = c[n] / c[n - 1] - 1

        // 近60日收益率
        var r60: [Double] = []
        var i = n - 59
        if i < 1 { i = 1 }
        while i <= n { r60.append(c[i] / c[i - 1] - 1); i += 1 }
        let sd60 = stdev(r60)

        // 1 价格 Z-Score
        var it = HLAnomalyItem()
        it.name = "价格波动"
        let z = sd60 > 0 ? (today - mean(r60)) / sd60 : 0
        it.value = String(format: "%+.2f%% (Z %+.2f)", today * 100, z)
        if abs(z) >= 2.5 { it.level = 2; it.hint = "偏离日常波动 2.5 倍标准差，属罕见波动" }
        else if abs(z) >= 2 { it.level = 1; it.hint = "偏离日常波动 2 倍标准差" }
        else { it.level = 0; it.hint = "在正常波动范围内" }
        out.append(it)

        // 2 量比
        it = HLAnomalyItem()
        it.name = "成交量"
        var vbase: [Double] = []
        var j = n - 20
        if j < 0 { j = 0 }
        while j < n { vbase.append(v[j]); j += 1 }
        let vr = vbase.count > 0 && mean(vbase) > 0 ? v[n] / mean(vbase) : 1
        it.value = String(format: "量比 %.2f", vr)
        if vr >= 2.5 { it.level = 2; it.hint = "天量（2.5倍以上），有大资金集中动作" }
        else if vr >= 2 { it.level = 1; it.hint = "显著放量" }
        else if vr <= 0.4 { it.level = 1; it.hint = "极度缩量，几乎无人交易" }
        else { it.level = 0; it.hint = "成交正常" }
        out.append(it)

        // 3 振幅 / ATR
        it = HLAnomalyItem()
        it.name = "日内振幅"
        var atrs: [Double] = []
        var k = n - 13
        if k < 1 { k = 1 }
        while k <= n {
            let tr = max(h[k] - l[k], max(abs(h[k] - c[k - 1]), abs(l[k] - c[k - 1])))
            atrs.append(tr)
            k += 1
        }
        let atr = mean(atrs)
        let amp = (h[n] - l[n]) / c[n - 1]
        let ampr = atr > 0 ? amp / (atr / c[n - 1]) : 0
        it.value = String(format: "%.2f%% (%.2f倍ATR)", amp * 100, ampr)
        if ampr >= 2.5 { it.level = 2; it.hint = "振幅达 ATR 2.5 倍，盘中激烈争夺" }
        else if ampr >= 2 { it.level = 1; it.hint = "振幅偏大" }
        else { it.level = 0; it.hint = "振幅正常" }
        out.append(it)

        // 4 跳空
        it = HLAnomalyItem()
        it.name = "跳空缺口"
        let gap = (o[n] - c[n - 1]) / c[n - 1]
        it.value = String(format: "%+.2f%%", gap * 100)
        if abs(gap) >= 0.03 { it.level = 2; it.hint = "大幅跳空（3%以上），隔夜有重大消息" }
        else if abs(gap) >= 0.015 { it.level = 1; it.hint = "明显跳空" }
        else { it.level = 0; it.hint = "开盘平稳" }
        out.append(it)

        // 5 连续单边
        it = HLAnomalyItem()
        it.name = "连续走势"
        var streak = 0
        var m = n
        while m >= 1 {
            let r = c[m] / c[m - 1] - 1
            if (r > 0) == (today > 0) { streak += 1; m -= 1 }
            else { break }
        }
        it.value = String(format: "%d 天%@", streak, today > 0 ? "上涨" : "下跌")
        if streak >= 7 { it.level = 2; it.hint = "连续 7 天以上单边，反转概率上升" }
        else if streak >= 5 { it.level = 1; it.hint = "连续 5 天单边" }
        else { it.level = 0; it.hint = "无极端连边" }
        out.append(it)

        // 6 波动率突变
        it = HLAnomalyItem()
        it.name = "波动率突变"
        var r5: [Double] = []
        var q = n - 4
        if q < 1 { q = 1 }
        while q <= n { r5.append(c[q] / c[q - 1] - 1); q += 1 }
        let vj = stdev(r60) > 0 ? stdev(r5) / stdev(r60) : 1
        it.value = String(format: "%.2f 倍", vj)
        if vj >= 2.5 { it.level = 2; it.hint = "短期波动达常态 2.5 倍，风险显著上升" }
        else if vj >= 2 { it.level = 1; it.hint = "波动放大" }
        else { it.level = 0; it.hint = "波动平稳" }
        out.append(it)

        // 7 量价背离（最有价值的一类）
        it = HLAnomalyItem()
        it.name = "量价背离"
        var tag = "无背离"
        var lvl = 0
        if vr >= 2 {
            if today >= 0.03 { tag = "放量暴涨"; lvl = 2
                it.hint = "放量上攻，可能是趋势启动或情绪高点" }
            else if today > 0 && today < 0.01 { tag = "放量滞涨"; lvl = 2
                it.hint = "量大但价格不动，常见出货信号" }
            else if today < 0 { tag = "放量下跌"; lvl = 2
                it.hint = "放量下杀，抛压真实，勿接飞刀" }
        } else if vr <= 0.5 && today < 0 {
            tag = "缩量阴跌"; lvl = 1
            it.hint = "无人接盘式下跌，通常还没跌完"
        }
        if lvl == 0 { it.hint = "量价配合正常" }
        it.value = tag
        it.level = lvl
        out.append(it)

        return out
    }

    // 综合预警等级
    static func anomalyLevel(_ items: [HLAnomalyItem]) -> (level: Int, score: Int, count: Int) {
        var score = 0
        var count = 0
        var i = 0
        while i < items.count {
            if items[i].level >= 1 {
                count += 1
                score += items[i].level
            }
            i += 1
        }
        // 有任意 level2 → 异动；无 level2 但累计≥3 → 注意；否则平静
        var has2 = false
        var t = 0
        while t < items.count {
            if items[t].level >= 2 { has2 = true }
            t += 1
        }
        var lv = 0
        if has2 { lv = 2 }
        else if score >= 3 { lv = 1 }
        return (lv, score, count)
    }

    static func anomalyTitle(_ level: Int) -> String {
        if level >= 2 { return "异动" }
        if level == 1 { return "注意" }
        return "平静"
    }

    // 综合应对建议：取最严重那一项的提示
    static func anomalyAdvice(_ items: [HLAnomalyItem]) -> String {
        var worst = -1
        var pick = ""
        var i = 0
        while i < items.count {
            if items[i].level > worst {
                worst = items[i].level
                pick = items[i].hint
            }
            i += 1
        }
        if worst <= 0 { return "各项指标正常，无异动。按既定纪律执行即可。" }
        return pick
    }
}
