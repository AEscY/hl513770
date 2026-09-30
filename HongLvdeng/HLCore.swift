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

    // ---------- 研究纪律常量 ----------
    // 历史长度：默认拉取 1000 根日线。样本太短会让任何策略看起来都不错。
    static let historyDays = 1000

    // 单边交易成本（万三）
    static let costRate = 0.0003

    // 统计结论的最低交易笔数警戒线
    static let minTradesForClaim = 30

    // ---------- ATR / 唐奇安 / 吊灯 ----------
    // 真实波幅 TR = max(H-L, |H-前收|, |L-前收|)
    static func trueRange(_ h: [Double], _ l: [Double], _ c: [Double], _ i: Int) -> Double {
        if i <= 0 || i >= c.count { return 0 }
        let pdc = c[i - 1]
        return max(h[i] - l[i], max(abs(h[i] - pdc), abs(l[i] - pdc)))
    }

    // ATR（简单均值版）
    static func atrAt(_ h: [Double], _ l: [Double], _ c: [Double], _ k: Int, _ idx: Int) -> Double? {
        if idx < k || idx >= c.count || k <= 0 { return nil }
        var sum = 0.0
        var i = idx - k + 1
        while i <= idx { sum += trueRange(h, l, c, i); i += 1 }
        return sum / Double(k)
    }

    static func atr(_ h: [Double], _ l: [Double], _ c: [Double], _ k: Int) -> Double? {
        if c.isEmpty { return nil }
        return atrAt(h, l, c, k, c.count - 1)
    }

    // 唐奇安上轨：过去 k 日最高（不含当日，否则"收盘>最高"永远不成立）
    static func donchianUp(_ h: [Double], _ k: Int, _ idx: Int) -> Double? {
        if idx < k || k <= 0 || idx >= h.count { return nil }
        var mx = -1e18
        var i = idx - k
        while i <= idx - 1 { if h[i] > mx { mx = h[i] }; i += 1 }
        return mx
    }

    // 唐奇安下轨：过去 k 日最低（不含当日）
    static func donchianDown(_ l: [Double], _ k: Int, _ idx: Int) -> Double? {
        if idx < k || k <= 0 || idx >= l.count { return nil }
        var mn = 1e18
        var i = idx - k
        while i <= idx - 1 { if l[i] < mn { mn = l[i] }; i += 1 }
        return mn
    }

    // ---------- 期望值与 R 分布 ----------
    // 输入：每笔交易的收益率倍数（如 1.03 表示 +3%）
    // 返回 [笔数, 胜率%, 平均盈利%, 平均亏损%(负), 期望%, 盈亏比, 利润因子, 最大连亏, 净收益%]
    static func tradeStats(_ rets: [Double]) -> [Double] {
        let cnt = rets.count
        if cnt == 0 { return [0, 0, 0, 0, 0, 0, 0, 0, 0] }
        var pcts: [Double] = []
        var i = 0
        while i < cnt { pcts.append((rets[i] - 1) * 100); i += 1 }
        var wins: [Double] = []
        var losses: [Double] = []
        var j = 0
        while j < cnt {
            if pcts[j] > 0 { wins.append(pcts[j]) } else { losses.append(pcts[j]) }
            j += 1
        }
        let wr = Double(wins.count) / Double(cnt) * 100
        var aw = 0.0
        if !wins.isEmpty {
            var s1 = 0.0
            for x in wins { s1 += x }
            aw = s1 / Double(wins.count)
        }
        var al = 0.0
        if !losses.isEmpty {
            var s2 = 0.0
            for x in losses { s2 += x }
            al = s2 / Double(losses.count)
        }
        // 期望 E = 胜率×平均盈利 + (1-胜率)×平均亏损（亏损为负）
        let expect = (wr / 100) * aw + (1 - wr / 100) * al
        var pf = 0.0
        var gp = 0.0
        var gl = 0.0
        for x in wins { gp += x }
        for x in losses { gl += (-x) }
        if gl > 0 { pf = gp / gl } else if gp > 0 { pf = 99 }
        var pl = 0.0
        if al < 0 { pl = abs(aw / al) }
        // 最大连续亏损
        var mx = 0
        var cur = 0
        var k = 0
        while k < cnt {
            if pcts[k] <= 0 { cur += 1; if cur > mx { mx = cur } } else { cur = 0 }
            k += 1
        }
        var net = 1.0
        var q = 0
        while q < cnt { net *= rets[q]; q += 1 }
        return [Double(cnt), wr, aw, al, expect, pl, pf, Double(mx), (net - 1) * 100]
    }

    // 样本量是否足以支撑结论
    static func sampleVerdict(_ trades: Int) -> String {
        if trades < 5 { return "样本极少，仅可用于排除明显错误逻辑" }
        if trades < minTradesForClaim { return "样本不足，仅作定性诊断，不能证明有效" }
        if trades < 100 { return "样本中等，可小规模试验，仍需样本外验证" }
        return "样本较充分，可用于风险配置参考"
    }

    // ================= 回测引擎 V2 =================
    // 与旧版的关键差异：
    //  1) T+1：信号在 bar t 收盘产生，bar t+1 开盘才成交（旧版是同日收盘，存在成交幻觉）
    //  2) 计入万三单边成本
    //  3) 返回完整交易列表，用于计算期望值 E、盈亏比、利润因子、最大连亏
    //  4) 支持唐奇安突破与吊灯移动止损
    // kind: 0=买入持有 1=MACD改良版 2=唐奇安突破 3=唐奇安+吊灯止损
    // 返回 [净收益%, 最大回撤%, 交易笔数, 胜率%, 期望%, 盈亏比, 利润因子, 最大连亏, 持仓占比%]
    static func backtestV2(_ o: [Double], _ h: [Double], _ l: [Double], _ c: [Double],
                           _ kind: Int, _ p1: Int, _ p2: Int, _ p3: Double) -> [Double] {
        if c.count < 80 { return [0, 0, 0, 0, 0, 0, 0, 0, 0] }
        let n = c.count
        var pos = 0.0
        var cash = 1.0
        var entry = 0.0
        var stop = 0.0
        var hh = 0.0
        var peak = 1.0
        var dd = 0.0
        var rets: [Double] = []
        var holdDays = 0
        let warm = 60

        var ms: (dif: [Double], bar: [Double])? = nil
        if kind == 1 { ms = macdSeries(c) }

        var i = warm
        while i < n {
            let sig = i - 1          // 信号日（已知收盘）
            let px = o[i]            // T+1 次日开盘成交
            var target = pos

            if kind == 0 {
                target = 1.0
            } else if kind == 1 {
                if let m = ms {
                    target = (m.bar[sig] > 0 && m.dif[sig] > 0) ? 1.0 : 0.0
                }
            } else if kind == 2 {
                let up = donchianUp(h, p1, sig)
                let dn = donchianDown(l, p2, sig)
                if up != nil && dn != nil {
                    if pos <= 0 && c[sig] > up! { target = 1.0 }
                    else if pos > 0 && c[sig] < dn! { target = 0.0 }
                }
            } else if kind == 3 {
                let up = donchianUp(h, p1, sig)
                let at = atrAt(h, l, c, p2, sig)
                if up != nil && at != nil {
                    if pos <= 0 && c[sig] > up! { target = 1.0 }
                    else if pos > 0 {
                        // 吊灯止损：随创新高上移
                        if h[i] > hh { hh = h[i] }
                        let ns = hh - p3 * at!
                        if ns > stop { stop = ns }
                        if l[i] <= stop { target = 0.0 }
                    }
                }
            }

            // 执行
            if target > pos + 0.001 {
                if pos <= 0.001 {
                    entry = px
                    cash *= (1 - costRate)
                    hh = h[i]
                    stop = px - p3 * (atrAt(h, l, c, p2, sig) ?? 0)
                }
                pos = target
            } else if target < pos - 0.001 {
                if pos > 0.001 {
                    var exitPx = px
                    if kind == 3 && l[i] <= stop { exitPx = min(o[i], stop) }
                    rets.append(exitPx / entry)
                    cash *= (1 - costRate) * (exitPx / entry)
                }
                pos = target
                hh = 0.0
                stop = 0.0
            }

            if kind == 3 && pos > 0.001 {
                if h[i] > hh { hh = h[i] }
                let at = atrAt(h, l, c, p2, i)
                if at != nil {
                    let ns = hh - p3 * at!
                    if ns > stop { stop = ns }
                }
            }

            if pos > 0.001 { holdDays += 1 }

            // 浮动净值
            var eq = cash
            if pos > 0.001 { eq = cash * (c[i] / entry) }
            if eq > peak { peak = eq }
            let curDd = (peak - eq) / peak
            if curDd > dd { dd = curDd }

            i += 1
        }

        // 强制平仓
        if pos > 0.001 {
            rets.append(c[n - 1] / entry)
            cash *= (1 - costRate) * (c[n - 1] / entry)
        }

        let st = tradeStats(rets)
        let holdPct = Double(holdDays) / Double(n - warm) * 100
        return [(cash - 1) * 100, dd * 100, st[0], st[1], st[4], st[5], st[6], st[7], holdPct]
    }

    // ---------- 均线 ----------
    // ============ 统计 / 证据门禁 ============
    // 标准正态累积分布（用误差函数）
    static func normCdf(_ x: Double) -> Double {
        return 0.5 * (1.0 + erf(x / 1.4142135623730951))
    }

    // 标准正态逆累积分布（Acklam 有理逼近，精度约 1e-9）
    static func normInv(_ pIn: Double) -> Double {
        if pIn <= 0 { return -8.0 }
        if pIn >= 1 { return 8.0 }
        let p = pIn
        let a = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
                 1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00]
        let b = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
                 6.680131188771972e+01, -1.328068155288572e+01]
        let c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
                 -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00]
        let d = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00,
                 3.754408661907416e+00]
        let pl = 0.02425
        var q = 0.0
        var r = 0.0
        if p < pl {
            q = sqrt(-2.0 * log(p))
            let num = (((((c[0]*q+c[1])*q+c[2])*q+c[3])*q+c[4])*q+c[5])
            let den = ((((d[0]*q+d[1])*q+d[2])*q+d[3])*q+1.0)
            return num / den
        }
        if p > 1.0 - pl {
            q = sqrt(-2.0 * log(1.0 - p))
            let num = -(((((c[0]*q+c[1])*q+c[2])*q+c[3])*q+c[4])*q+c[5])
            let den = ((((d[0]*q+d[1])*q+d[2])*q+d[3])*q+1.0)
            return num / den
        }
        q = p - 0.5
        r = q * q
        let num = (((((a[0]*r+a[1])*r+a[2])*r+a[3])*r+a[4])*r+a[5])*q
        let den = (((((b[0]*r+b[1])*r+b[2])*r+b[3])*r+b[4])*r+1.0)
        return num / den
    }

    // 收益序列的夏普 / 偏度 / 超额峰度
    // 返回 [年化夏普, 偏度, 峰度, 样本数]
    static func retStats(_ rets: [Double]) -> [Double] {
        let n = rets.count
        if n < 3 { return [0, 0, 0, 0] }
        var mu = 0.0
        var i = 0
        while i < n { mu += rets[i]; i += 1 }
        mu = mu / Double(n)
        var v = 0.0
        i = 0
        while i < n { v += (rets[i] - mu) * (rets[i] - mu); i += 1 }
        v = v / Double(n - 1)
        if v <= 0 { return [0, 0, 0, Double(n)] }
        let sd = sqrt(v)
        let sr = (mu / sd) * sqrt(252.0)
        var m3 = 0.0
        var m4 = 0.0
        i = 0
        while i < n {
            let z = (rets[i] - mu) / sd
            m3 += z * z * z
            m4 += z * z * z * z
            i += 1
        }
        m3 = m3 / Double(n)
        m4 = m4 / Double(n)
        return [sr, m3, m4 - 3.0, Double(n)]
    }

    // Deflated Sharpe Ratio（Bailey & López de Prado 2014）
    // 校正"从 N 次试验里挑出最好那个"造成的选择偏差 + 非正态性
    // trials: 总共试验过的策略/参数组合数
    // 返回 [原始夏普, DSR(0~1), 所需最短样本长度MinTRL(交易日), 期望最大夏普SR0]
    static func dsr(_ rets: [Double], _ trials: Int) -> [Double] {
        let st = retStats(rets)
        let sr = st[0]
        let g3 = st[1]
        let g4 = st[2]
        let n = Int(st[3])
        if n < 12 || sr <= 0 { return [sr, 0, 0, 0] }
        let N = Double(max(2, trials))
        let e = 2.718281828459045
        // 期望最大夏普（零假设下）
        let z1 = normInv(1.0 - 1.0 / N)
        let z2 = normInv(1.0 - 1.0 / (N * e))
        let gamma = 0.5772156649015329
        let sr0 = sqrt(varianceSr(rets)) * ((1.0 - gamma) * z1 + gamma * z2)
        // DSR
        let denom = sqrt(max(1e-9, 1.0 - g3 * sr + (g4 - 1.0) / 4.0 * sr * sr))
        let dsrVal = normCdf((sr - sr0) * sqrt(Double(n - 1)) / denom)
        // MinTRL
        var minTRL = 0.0
        if sr > sr0 {
            let za = normInv(0.95)
            let den2 = max(1e-9, 1.0 - g3 * sr + (g4 - 1.0) / 4.0 * sr * sr)
            minTRL = 1.0 + den2 * (za / (sr - sr0)) * (za / (sr - sr0))
        } else {
            minTRL = 1e9
        }
        return [sr, dsrVal, minTRL, sr0]
    }

    // 夏普估计量的方差 V[SR] ≈ (1 + sr²/2) / (n-1)
    static func varianceSr(_ rets: [Double]) -> Double {
        let st = retStats(rets)
        let n = Int(st[3])
        if n < 3 { return 0 }
        let sr = st[0] / sqrt(252.0)
        return (1.0 + 0.5 * sr * sr) / Double(n - 1)
    }

    // 证据门禁结论：0=证据不足 1=弱 2=可用
    static func evidenceLevel(_ rets: [Double], _ trials: Int) -> Int {
        let r = dsr(rets, trials)
        let dv = r[1]
        let minTRL = r[2]
        let n = retStats(rets)[3]
        if dv >= 0.95 && Double(n) >= minTRL { return 2 }
        if dv >= 0.90 { return 1 }
        return 0
    }

    static func evidenceText(_ rets: [Double], _ trials: Int) -> String {
        let lv = evidenceLevel(rets, trials)
        if lv == 2 { return "证据可用" }
        if lv == 1 { return "证据较弱" }
        return "证据不足"
    }

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

    // ---------- MACD 序列（供策略回测用）----------
    // 返回 (difLine, barLine)，长度与输入相同
    // ============ 稳健度引擎 ============
    // 参数化回测：可指定 MACD 参数、RSI 阈值、是否加 MA60 过滤
    // rsiTh <= 0 表示不启用 RSI 条件；useMA60=false 表示不启用 MA60 过滤
    // 返回 [收益%, 最大回撤%, 交易次数, 胜率%, 持仓占比%, 完成交易笔数]
    static func backtestP(_ c: [Double], _ fast: Int, _ slow: Int, _ sig: Int,
                          _ rsiTh: Double, _ useMA60: Bool) -> [Double] {
        let need = slow + sig + 20
        if c.count < need { return [0, 0, 0, 0, 0, 0] }
        guard let ms = macdSeriesP(c, fast, slow, sig) else { return [0, 0, 0, 0, 0, 0] }
        var v = 1.0
        var pos = 0.0
        var peak = 1.0
        var dd = 0.0
        var trades = 0
        var wins = 0
        var closed = 0
        var entry = 0.0
        var holdDays = 0
        var i = 1
        while i < c.count {
            let prev = c[i - 1]
            let bar = ms.bar[i - 1]
            let dif = ms.dif[i - 1]
            var ok = (bar > 0 && dif > 0)
            if rsiTh > 0 {
                let r = rsiAt(c, 14, i - 1)
                if r == nil { ok = false }
                else { ok = ok && (r! > rsiTh) }
            }
            if useMA60 {
                let m60 = maAt(c, 60, i - 1)
                if m60 == nil { ok = false }
                else { ok = ok && (prev > m60!) }
            }
            let target: Double = ok ? 1.0 : 0.0

            if target > pos + 0.001 || target < pos - 0.001 {
                if pos <= 0.001 && target > 0.001 { entry = c[i] }
                else if pos > 0.001 && target <= 0.001 {
                    closed += 1
                    if c[i] > entry { wins += 1 }
                }
                trades += 1
            }
            pos = target
            if pos > 0.001 { holdDays += 1 }
            let ret = c[i] / prev
            v *= (1 + pos * (ret - 1))
            if v > peak { peak = v }
            let cur = (peak - v) / peak
            if cur > dd { dd = cur }
            i += 1
        }
        var wr = 0.0
        if closed > 0 { wr = Double(wins) / Double(closed) * 100 }
        let holdPct = Double(holdDays) / Double(c.count - 1) * 100
        return [(v - 1) * 100, dd * 100, Double(trades), wr, holdPct, Double(closed)]
    }

    // 返回某策略的净值序列（用于计算日收益、夏普、DSR）
    static func backtestNAV(_ c: [Double], _ kind: Int,
                            _ opens: [Double]? = nil,
                            _ costBps: Double = 20.0,
                            _ nextOpen: Bool = true) -> [Double] {
        if c.count < 70 { return [] }
        var nav: [Double] = [1.0]
        var pos = 0.0
        var v = 1.0
        var gridLevel = 0.0
        var lastTrade = 0
        let macdCache: (dif: [Double], bar: [Double])? =
            (kind == 7 || kind == 8 || kind == 9 || kind == 10) ? macdSeries(c) : nil
        var i = 1
        while i < c.count {
            let prev = c[i - 1]
            var target = pos

            if kind == 0 { target = 1.0 }
            else if kind == 13 { target = 0.0 }
            else if kind == 2 {
                let m5 = maAt(c, 5, i - 1)
                let m20 = maAt(c, 20, i - 1)
                if m5 != nil && m20 != nil { target = (m5! > m20!) ? 1.0 : 0.0 }
            } else if kind == 7 {
                if let ms = macdCache { target = ms.bar[i - 1] > 0 ? 1.0 : 0.0 }
            } else if kind == 8 {
                if let ms = macdCache {
                    target = (ms.bar[i - 1] > 0 && ms.dif[i - 1] > 0) ? 1.0 : 0.0
                }
            } else if kind == 9 {
                if let ms = macdCache {
                    let r = rsiAt(c, 14, i - 1)
                    if r != nil {
                        target = (ms.bar[i - 1] > 0 && ms.dif[i - 1] > 0 && r! > 50) ? 1.0 : 0.0
                    }
                }
            } else if kind == 10 {
                if let ms = macdCache {
                    let m60 = maAt(c, 60, i - 1)
                    if m60 != nil {
                        target = (ms.bar[i - 1] > 0 && ms.dif[i - 1] > 0 && prev > m60!) ? 1.0 : 0.0
                    }
                }
            } else if kind == 11 {
                let look = 120
                if i - 1 >= look {
                    target = (prev / c[i - 1 - look] - 1.0) > 0 ? 1.0 : 0.0
                } else { target = 0.0 }
                if lastTrade > 0 && (i - lastTrade) < 20 { target = pos }
            } else if kind == 12 {
                if i - 1 >= 60 {
                    var rs: [Double] = []
                    var j = i - 60
                    while j < i { rs.append(c[j] / c[j - 1] - 1.0); j += 1 }
                    var mu = 0.0
                    for x in rs { mu += x }
                    mu = mu / Double(rs.count)
                    var va = 0.0
                    for x in rs { va += (x - mu) * (x - mu) }
                    va = va / Double(rs.count - 1)
                    let rv = sqrt(va) * sqrt(252.0)
                    var wgt = 0.10 / max(0.05, rv)
                    if wgt > 1.0 { wgt = 1.0 }
                    var trendOk = true
                    if i - 1 >= 120 { trendOk = (prev / c[i - 121] - 1.0) > 0 }
                    target = trendOk ? wgt : 0.0
                } else { target = 0.0 }
            }

            var px = c[i]
            if nextOpen && opens != nil {
                let op = opens!
                if i < op.count { px = op[i] }
            }
            if target > pos + 0.001 || target < pos - 0.001 {
                let fee = abs(target - pos) * costBps / 10000.0
                v *= (1.0 - fee)
                lastTrade = i
            }
            pos = target
            // 收益从本期成交价结算到下一期开盘价（本期收益不含信号产生前的行情）
            var nxtP = c[i]
            if nextOpen && opens != nil {
                let op = opens!
                if i + 1 < op.count { nxtP = op[i + 1] }
                else { nxtP = c[c.count - 1] }
            }
            var ret = 1.0
            if px > 0 { ret = nxtP / px }
            v *= (1 + pos * (ret - 1))
            nav.append(v)
            i += 1
        }
        return nav
    }

    // 由净值序列得到日收益序列
    static func navToRets(_ nav: [Double]) -> [Double] {
        if nav.count < 3 { return [] }
        var out: [Double] = []
        var i = 1
        while i < nav.count {
            if nav[i - 1] > 0 { out.append(nav[i] / nav[i - 1] - 1.0) }
            i += 1
        }
        return out
    }

    // 稳健度评分：比"谁收益高"更重要 —— 检验策略是不是凑出来的
    // mode: 0 = 扫 MACD 参数（快/慢/信号）；1 = 扫 RSI 阈值
    // 返回 [综合等级, 参数正收益率%, 前半段收益%, 后半段收益%, 最差参数收益%, 测试组数]
    // 等级: 3=稳定 2=较稳 1=一般 0=脆弱（过拟合风险高）
    static func robustness(_ c: [Double], _ mode: Int) -> [Double] {
        if c.count < 120 { return [0, 0, 0, 0, 0, 0] }
        var params: [(Int, Int, Int, Double, Bool)] = []
        if mode == 0 {
            params = [(8, 17, 9, 0, false),
                      (12, 26, 9, 0, false),
                      (19, 39, 9, 0, false),
                      (21, 55, 9, 0, false)]
        } else {
            params = [(12, 26, 9, 45, false),
                      (12, 26, 9, 50, false),
                      (12, 26, 9, 55, false),
                      (12, 26, 9, 60, false)]
        }
        var posCount = 0
        var worst = 9999.0
        var i = 0
        while i < params.count {
            let pm = params[i]
            let r = backtestP(c, pm.0, pm.1, pm.2, pm.3, pm.4)
            if r[0] > 0 { posCount += 1 }
            if r[0] < worst { worst = r[0] }
            i += 1
        }
        let posRate = Double(posCount) / Double(params.count) * 100

        // 时间切片：前后各半段
        let half = c.count / 2
        var first: [Double] = []
        var second: [Double] = []
        var j = 0
        while j < half { first.append(c[j]); j += 1 }
        while j < c.count { second.append(c[j]); j += 1 }
        var fRet = 0.0
        var sRet = 0.0
        if first.count > 80 {
            let pm = params[1]
            fRet = backtestP(first, pm.0, pm.1, pm.2, pm.3, pm.4)[0]
        }
        if second.count > 80 {
            let pm = params[1]
            sRet = backtestP(second, pm.0, pm.1, pm.2, pm.3, pm.4)[0]
        }

        // 综合等级
        var bothPos = 0.0
        if fRet > 0 && sRet > 0 { bothPos = 1.0 }
        else if fRet > 0 || sRet > 0 { bothPos = 0.5 }

        var level = 0.0
        if posRate >= 100 && bothPos >= 1.0 { level = 3 }
        else if posRate >= 75 && bothPos >= 0.5 { level = 2 }
        else if posRate >= 50 { level = 1 }
        else { level = 0 }

        return [level, posRate, fRet, sRet, worst, Double(params.count)]
    }

    // 稳健度等级文案
    static func robustText(_ level: Double) -> String {
        if level >= 3 { return "稳定" }
        if level >= 2 { return "较稳" }
        if level >= 1 { return "一般" }
        return "脆弱"
    }

    // 参数化版本：可指定快慢线与信号周期，供稳健度（参数敏感性）测试
    static func macdSeriesP(_ a: [Double], _ fast: Int, _ slow: Int, _ sig: Int)
        -> (dif: [Double], bar: [Double])? {
        if a.count < slow + sig { return nil }
        if fast >= slow { return nil }
        let ef = ema(a, fast)
        let es = ema(a, slow)
        var difLine: [Double] = []
        var i = 0
        while i < a.count { difLine.append(ef[i] - es[i]); i += 1 }
        let deaLine = ema(difLine, sig)
        var barLine: [Double] = []
        var j = 0
        while j < a.count { barLine.append((difLine[j] - deaLine[j]) * 2); j += 1 }
        return (difLine, barLine)
    }

    static func macdSeries(_ a: [Double]) -> (dif: [Double], bar: [Double])? {
        if a.count < 26 { return nil }
        let e12 = ema(a, 12)
        let e26 = ema(a, 26)
        var difLine: [Double] = []
        var i = 0
        while i < a.count { difLine.append(e12[i] - e26[i]); i += 1 }
        let deaLine = ema(difLine, 9)
        var barLine: [Double] = []
        var j = 0
        while j < a.count { barLine.append((difLine[j] - deaLine[j]) * 2); j += 1 }
        return (difLine, barLine)
    }

    // ---------- MACD 当前状态（供界面判断）----------
    // 返回 [dif, dea, bar, 原版信号(1买入/0空仓), 改良信号(1买入/0空仓), 距零轴]
    static func macdState(_ a: [Double]) -> [Double] {
        guard let ms = macdSeries(a) else { return [0, 0, 0, 0, 0, 0] }
        let n = ms.dif.count
        if n < 1 { return [0, 0, 0, 0, 0, 0] }
        let dif = ms.dif[n - 1]
        let bar = ms.bar[n - 1]
        let dea = dif - bar / 2
        let raw = bar > 0 ? 1.0 : 0.0
        let improved = (bar > 0 && dif > 0) ? 1.0 : 0.0
        return [dif, dea, bar, raw, improved, -dif]
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

    // ---------- 回测（9 种策略）----------
    // 返回 [收益倍数, 最大回撤%, 交易次数, 胜率%]
    // 回测（默认：扣 20bps 往返成本，信号次日开盘执行）
    // opens 为空时退化为收盘价执行；costBps 为单次往返成本(bps)
    static func backtest(_ c: [Double], _ kind: Int,
                         _ opens: [Double]? = nil,
                         _ costBps: Double = 20.0,
                         _ nextOpen: Bool = true) -> [Double] {
        return backtestCore(c, kind, opens, costBps, nextOpen)
    }

    static func backtestCore(_ c: [Double], _ kind: Int,
                             _ opens: [Double]?,
                             _ costBps: Double,
                             _ nextOpen: Bool) -> [Double] {
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
        var lastTrade = 0
        var macdCache: (dif: [Double], bar: [Double])? = nil
        if kind == 7 || kind == 8 || kind == 9 || kind == 10 { macdCache = macdSeries(c) }
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
            } else if kind == 7 {
                // MACD 红买绿卖（原版）：只看柱
                if let ms = macdCache {
                    let bar = ms.bar[i - 1]
                    target = bar > 0 ? 1.0 : 0.0
                }
            } else if kind == 8 {
                // MACD 改良版：柱>0 且 DIF>0（只认零轴上方红柱）
                if let ms = macdCache {
                    let bar = ms.bar[i - 1]
                    let dif = ms.dif[i - 1]
                    target = (bar > 0 && dif > 0) ? 1.0 : 0.0
                }
            } else if kind == 9 {
                // 三指标共振：MACD柱>0 且 DIF>0 且 RSI(14)>50
                // 注意：样本极少，仅作观察，不作为推荐
                if let ms = macdCache {
                    let bar = ms.bar[i - 1]
                    let dif = ms.dif[i - 1]
                    let r = rsiAt(c, 14, i - 1)
                    if r != nil {
                        target = (bar > 0 && dif > 0 && r! > 50) ? 1.0 : 0.0
                    }
                }
            } else if kind == 10 {
                // 改良版 + MA60 趋势过滤：再加一道大趋势确认
                if let ms = macdCache {
                    let bar = ms.bar[i - 1]
                    let dif = ms.dif[i - 1]
                    let m60 = maAt(c, 60, i - 1)
                    if m60 != nil {
                        target = (bar > 0 && dif > 0 && prev > m60!) ? 1.0 : 0.0
                    }
                }
            } else if kind == 11 {
                // 低频时序动量（Moskowitz-Ooi-Pedersen 思路的不可做空版本）
                // 过去 120 日累计收益为正才持有，否则空仓；最小持有 20 日
                let look = 120
                if i - 1 >= look {
                    let mom = prev / c[i - 1 - look] - 1.0
                    target = mom > 0 ? 1.0 : 0.0
                } else {
                    target = 0.0
                }
                if lastTrade > 0 && (i - lastTrade) < 20 { target = pos }
            } else if kind == 13 {
                // 始终空仓：现金基准。报告指出"及时减仓的理论上限约为空仓"
                target = 0.0
            } else if kind == 12 {
                // 波动率目标风险预算（Barroso-Santa-Clara 思路）
                // w = targetVol / max(floor, realizedVol)，并叠加 120 日趋势过滤
                let tv = 0.10
                let floorV = 0.05
                if i - 1 >= 60 {
                    var rs: [Double] = []
                    var j = i - 60
                    while j < i { rs.append(c[j] / c[j - 1] - 1.0); j += 1 }
                    var mu = 0.0
                    for x in rs { mu += x }
                    mu = mu / Double(rs.count)
                    var va = 0.0
                    for x in rs { va += (x - mu) * (x - mu) }
                    va = va / Double(rs.count - 1)
                    let rv = sqrt(va) * sqrt(252.0)
                    var wgt = tv / max(floorV, rv)
                    if wgt > 1.0 { wgt = 1.0 }
                    var trendOk = true
                    if i - 1 >= 120 { trendOk = (prev / c[i - 121] - 1.0) > 0 }
                    target = trendOk ? wgt : 0.0
                } else {
                    target = 0.0
                }
            }

            // 执行价：次日开盘（避免用当日收盘价成交的未来函数）
            var px = c[i]
            if nextOpen && opens != nil {
                let op = opens!
                if i < op.count { px = op[i] }
            }
            if target > pos + 0.001 || target < pos - 0.001 {
                // 交易成本：按仓位变动比例扣
                let fee = abs(target - pos) * costBps / 10000.0
                v *= (1.0 - fee)
                if pos <= 0.001 && target > 0.001 { entry = px }
                else if pos > 0.001 && target <= 0.001 {
                    closed += 1
                    if px > entry { wins += 1 }
                }
                trades += 1
                lastTrade = i
            }

            pos = target
            // 收益从本期成交价结算到下一期开盘价（消除"用信号日之前行情计收益"的偷价）
            var nxtP = c[i]
            if nextOpen && opens != nil {
                let op = opens!
                if i + 1 < op.count { nxtP = op[i + 1] }
                else { nxtP = c[c.count - 1] }
            }
            var ret = 1.0
            if px > 0 { ret = nxtP / px }
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
                     "布林带回归", "网格 每5%", "定投 每20日",
                     "MACD 红买绿卖", "MACD 改良版"]
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
    // ===== 跨资产配置：相关系数 =====
    // 取两者较短长度对齐尾部，计算日收益的皮尔逊相关系数
    static func hlCorr(_ a: [Double], _ b: [Double]) -> Double {
        var n = a.count
        if b.count < n { n = b.count }
        if n < 30 { return 0 }
        let ao = Array(a[(a.count - n)...])
        let bo = Array(b[(b.count - n)...])
        var ra: [Double] = []
        var rb: [Double] = []
        var i = 1
        while i < n {
            if ao[i - 1] > 0 { ra.append(ao[i] / ao[i - 1] - 1) } else { ra.append(0) }
            if bo[i - 1] > 0 { rb.append(bo[i] / bo[i - 1] - 1) } else { rb.append(0) }
            i += 1
        }
        let m = ra.count
        if m < 30 { return 0 }
        var sa = 0.0
        var sb = 0.0
        var j = 0
        while j < m {
            sa += ra[j]
            sb += rb[j]
            j += 1
        }
        let ma = sa / Double(m)
        let mb = sb / Double(m)
        var num = 0.0
        var da = 0.0
        var db = 0.0
        var k = 0
        while k < m {
            let x = ra[k] - ma
            let y = rb[k] - mb
            num += x * y
            da += x * x
            db += y * y
            k += 1
        }
        if da <= 0 || db <= 0 { return 0 }
        return num / (sqrt(da) * sqrt(db))
    }

    // ===== 跨资产配置：过去 lb 期动量收益 =====
    static func hlMom(_ c: [Double], _ lb: Int) -> Double {
        if lb <= 0 { return 0 }
        if c.count <= lb { return 0 }
        let last = c[c.count - 1]
        let prev = c[c.count - 1 - lb]
        if prev <= 0 { return 0 }
        return last / prev - 1
    }

    // ===== 跨资产配置：区间总收益与最大回撤（用于展示"同期谁更好"）=====
    static func hlRangeRet(_ c: [Double]) -> Double {
        if c.count < 2 { return 0 }
        let f = c[0]
        if f <= 0 { return 0 }
        return c[c.count - 1] / f - 1
    }

    static func hlMaxDD(_ c: [Double]) -> Double {
        if c.count < 2 { return 0 }
        var peak = c[0]
        var dd = 0.0
        var i = 0
        while i < c.count {
            if c[i] > peak { peak = c[i] }
            let d = c[i] / peak - 1
            if d < dd { dd = d }
            i += 1
        }
        return dd
    }


    // ===== 策略适配度：本标的上「择时」是否跑赢「一直持有」=====
    // 用次日开盘成交 + 万五手续费，避免用当日收盘价成交的未来函数
    // 返回 (择时收益, 持有收益, 超额, 交易次数, 是否适配)
    static func strategyFit(_ close: [Double], _ open: [Double])
        -> (timing: Double, hold: Double, excess: Double, trades: Int, fit: Bool) {
        let n = close.count
        if n < 150 || open.count != n { return (0, 0, 0, 0, false) }
        let start = 60
        let fee = 0.0005
        var cash = 1.0
        var shares = 0.0
        var trades = 0
        var prev = ""
        var pend = ""
        var i = start
        while i < n {
            let px = open[i]
            if pend == "buy" && shares == 0 && px > 0 {
                shares = cash * (1.0 - fee) / px
                cash = 0.0
                trades += 1
                pend = ""
            } else if pend == "sell" && shares > 0 {
                cash = shares * px * (1.0 - fee)
                shares = 0.0
                trades += 1
                pend = ""
            }
            let m20 = maAt(close, 20, i)
            let m60 = maAt(close, 60, i)
            if m20 != nil && m60 != nil {
                let p = close[i]
                var s = "yellow"
                if p < m20! { s = "red" }
                else if p < m60! { s = "yellow" }
                else { s = "green" }
                if s == "green" && prev != "green" && shares == 0 { pend = "buy" }
                else if s != "green" && prev == "green" && shares > 0 { pend = "sell" }
                prev = s
            }
            i += 1
        }
        let last = close[n - 1]
        let eq = cash + shares * last
        let base = close[start]
        if base <= 0 { return (0, 0, 0, 0, false) }
        let hold = last / base - 1.0
        let timing = eq - 1.0
        let excess = timing - hold
        return (timing, hold, excess, trades, excess > 0)
    }

    // 标的档案：年化波动率(%)、趋势效率 ER(0~1)、最大回撤(%)
    static func profileStats(_ close: [Double]) -> (vol: Double, er: Double, dd: Double) {
        let n = close.count
        if n < 30 { return (0, 0, 0) }
        var rets: [Double] = []
        var i = n - 60
        if i < 1 { i = 1 }
        while i < n {
            let a = close[i - 1]
            let b = close[i]
            if a > 0 && b > 0 { rets.append((b / a) - 1.0) }
            i += 1
        }
        var vol = 0.0
        if rets.count > 2 {
            var m = 0.0
            for r in rets { m += r }
            m /= Double(rets.count)
            var ss = 0.0
            for r in rets { ss += (r - m) * (r - m) }
            let sd = (ss / Double(rets.count - 1)).squareRoot()
            vol = sd * (252.0).squareRoot() * 100.0
        }
        // ER = |净变化| / Σ|日变化|
        let lb = 60
        var er = 0.0
        if n > lb {
            var tot = 0.0
            var k = n - lb
            while k < n {
                tot += (close[k] - close[k - 1]).magnitude
                k += 1
            }
            let net = (close[n - 1] - close[n - 1 - lb]).magnitude
            if tot > 0 { er = net / tot }
        }
        let dd = maxDD(close) * 100.0
        return (vol, er, dd)
    }



    // ==================================================================
    // MARK: - 自适应方案引擎（两段一致性检验）
    //
    // 实证基础（12 个标的 × 800 日，前 60% 判断 / 后 40% 验证）：
    //   · 参数自适应无效：IS 选最优参数，OOS 胜率仅 41.7%（不如抛硬币）
    //   · 稳健选参略有改善：47.9%，仍不可用
    //   · 两段一致性选模式：OOS 平均 +15.65%，优于始终持有 +11.22%
    //     与始终择时 +5.74%；选对比例 83.3%
    //   · 置信度确实能预测准确率：高置信 7/7=100%，低置信 3/5=60%
    //
    // 因此本引擎【不调参数】，只判断"该不该择时"，并诚实给出置信度。
    // ==================================================================

    // 分段回测：对 closes[from..<to] 做双均线择时 / 持有
    // kind=2 为双均线(5,20)，与工具内其他回测同口径（扣成本、次日开盘）
    static func segBacktest(_ o: [Double], _ h: [Double], _ l: [Double],
                            _ c: [Double], _ from: Int, _ to: Int) -> (timing: Double, hold: Double) {
        if to - from < 70 { return (0, 0) }
        let so = Array(o[from..<to]); let sh = Array(h[from..<to])
        let sc = Array(c[from..<to])
        // backtest 返回 [净值, 回撤%, 交易数, 胜率]，收益需 (净值-1)*100
        let r = backtest(sc, 2, so, 20.0, true)
        return ((r[0] - 1.0) * 100.0, (sc.last! / sc.first! - 1.0) * 100.0)
    }

    // 自适应方案：返回 [模式, 置信度, IS择时, IS持有, OOS择时, OOS持有,
    //                  全样本择时, 全样本持有, 反转风险]
    // 模式：0=持有  1=择时  2=存疑(默认持有)
    static func adaptivePlan(_ o: [Double], _ h: [Double], _ l: [Double],
                             _ c: [Double]) -> [Double] {
        let n = c.count
        if n < 200 || o.count != n || h.count != n || l.count != n {
            return [2, 0, 0, 0, 0, 0, 0, 0, 0]
        }
        let sp = Int(Double(n) * 0.6)
        let isSeg = segBacktest(o, h, l, c, 0, sp)
        let oosSeg = segBacktest(o, h, l, c, sp, n)
        let fullSeg = segBacktest(o, h, l, c, 0, n)

        let isWin = isSeg.timing > isSeg.hold
        let oosWin = oosSeg.timing > oosSeg.hold

        var mode = 2.0
        var conf = 35.0
        if isWin && oosWin { mode = 1.0; conf = 90.0 }
        else if !isWin && !oosWin { mode = 0.0; conf = 90.0 }

        // 反转风险：前段涨、后段跌 —— 此类标的的历史规律最易失效
        let rev: Double = (isSeg.hold > 0 && oosSeg.hold < 0) ? 1.0 : 0.0

        return [mode, conf, isSeg.timing, isSeg.hold,
                oosSeg.timing, oosSeg.hold, fullSeg.timing, fullSeg.hold, rev]
    }

    static func adaptiveModeText(_ mode: Double) -> String {
        if mode > 0.5 { return "启用择时" }
        if mode < 0.5 { return "持有不动" }
        return "存疑 · 建议持有"
    }

    static func adaptiveConfText(_ conf: Double) -> String {
        if conf >= 90 { return "高置信（历史同类判断准确率 100%）" }
        return "低置信（历史同类判断准确率 60%，仅供参考）"
    }

    // 方案说明：把结论写成一句人话
    static func adaptiveAdvice(_ p: [Double]) -> String {
        if p.count < 9 { return "数据不足" }
        let mode = p[0]
        let isT = p[2]; let isB = p[3]
        let oosT = p[4]; let oosB = p[5]
        let rev = p[8]
        if mode > 0.5 {
            return String(format: "前段择时 %.1f%% 优于持有 %.1f%%，后段 %.1f%% 优于 %.1f%%——两段一致，此标的上择时有效。",
                          isT, isB, oosT, oosB)
        }
        if mode < 0.5 {
            if rev > 0.5 {
                return "两段均显示持有更优，但此标的出现过『前涨后跌』反转——这类标的历史规律最容易在趋势切换时失效，不宜据此频繁进出。"
            }
            return String(format: "前段持有 %.1f%% 优于择时 %.1f%%，后段 %.1f%% 优于 %.1f%%——此标的上择时会拖累收益，建议少动。",
                          isB, isT, oosB, oosT)
        }
        return String(format: "前段择时%@，后段择时%@——两段结论矛盾，无法判断此标的是否适合择时，默认按持有处理。",
                      isT > isB ? "占优" : "落后", oosT > oosB ? "占优" : "落后")
    }

    // ==================================================================
    // MARK: - 自适应引擎（按标的特征自动选策略与参数）
    //
    // 设计原则：不做"全局最优策略"，只做"这个标的上、这组历史里，
    // 哪套规则经得起参数扰动和时间切片"。所有结论都带置信度。
    // ==================================================================

    // 策略编号：0持有 1红绿灯 2MACD改良 3双均线 4RSI反弹 5布林回归 6自适应均线
    static func autoCount() -> Int { return 7 }

    static func autoName(_ k: Int) -> String {
        if k == 0 { return "一直持有" }
        if k == 1 { return "红绿灯" }
        if k == 2 { return "MACD改良版" }
        if k == 3 { return "双均线" }
        if k == 4 { return "RSI超卖反弹" }
        if k == 5 { return "布林带回归" }
        return "自适应均线"
    }

    // 策略族：0=基准 1=趋势跟随 2=均值回归
    static func autoFamily(_ k: Int) -> Int {
        if k == 0 { return 0 }
        if k == 1 || k == 2 || k == 3 || k == 6 { return 1 }
        return 2
    }

    // ---------- 信号生成：1=持仓 0=空仓 ----------
    // 信号在 i 处产生，实际在 i+1 执行（避免未来函数）
    static func autoSignal(_ c: [Double], _ h: [Double], _ l: [Double],
                           _ kind: Int, _ p1: Int, _ p2: Int) -> [Int] {
        let n = c.count
        var out: [Int] = []
        var i = 0
        while i < n {
            var s = 0
            if kind == 0 {
                s = 1
            } else if kind == 1 {
                let b = bandAt(c, i)
                if b == 2 { s = 1 }
            } else if kind == 2 {
                if let st = macdStateAt(c, i) {
                    if st.0 > 0 && st.1 > 0 { s = 1 }
                }
            } else if kind == 3 {
                let f = maAt(c, p1, i)
                let w = maAt(c, p2, i)
                if f != nil && w != nil && f! > w! { s = 1 }
            } else if kind == 4 {
                let r = rsiAt(c, p1, i)
                if r != nil {
                    if r! < Double(p2) { s = 1 }
                    else if r! > 70 { s = 0 }
                    else { s = i > 0 ? out[i - 1] : 0 }
                }
            } else if kind == 5 {
                let b = bollAt(c, p1, i)
                if b != nil {
                    if c[i] <= b!.low { s = 1 }
                    else if c[i] >= b!.up { s = 0 }
                    else { s = i > 0 ? out[i - 1] : 0 }
                }
            } else if kind == 6 {
                // 自适应均线：趋势强用慢线，震荡用快线
                let erNow = erAt(c, i, 60)
                var per = p2
                if erNow != nil {
                    if erNow! >= 0.30 { per = p2 }
                    else { per = p1 }
                }
                let m = maAt(c, per, i)
                if m != nil && c[i] > m! { s = 1 }
            }
            out.append(s)
            i += 1
        }
        return out
    }

    // 单点 MACD 状态（避免每点重算整条序列）
    static func macdStateAt(_ a: [Double], _ idx: Int) -> (Double, Double)? {
        if idx < 35 { return nil }
        var e12 = [Double]()
        var e26 = [Double]()
        var i = 0
        let k12 = 2.0 / 13.0
        let k26 = 2.0 / 27.0
        var v12 = a[0]
        var v26 = a[0]
        while i <= idx {
            v12 = v12 + k12 * (a[i] - v12)
            v26 = v26 + k26 * (a[i] - v26)
            e12.append(v12)
            e26.append(v26)
            i += 1
        }
        var difs: [Double] = []
        var j = 0
        while j < e12.count {
            difs.append(e12[j] - e26[j])
            j += 1
        }
        let k9 = 2.0 / 10.0
        var dea = difs[0]
        j = 0
        while j < difs.count {
            dea = dea + k9 * (difs[j] - dea)
            j += 1
        }
        let dif = difs[difs.count - 1]
        return (dif, dif - dea)
    }

    // 单点效率系数 ER
    static func erAt(_ c: [Double], _ idx: Int, _ lb: Int) -> Double? {
        if idx < lb + 1 { return nil }
        var tot = 0.0
        var k = idx - lb + 1
        while k <= idx {
            tot += (c[k] - c[k - 1]).magnitude
            k += 1
        }
        let net = (c[idx] - c[idx - lb]).magnitude
        if tot <= 0 { return nil }
        return net / tot
    }

    // ---------- 回测：信号次日成交，扣成本 ----------
    // 返回 [收益%, 回撤%, 交易次数, 胜率%, 持仓占比%]
    static func autoBacktest(_ c: [Double], _ sig: [Int], _ costBps: Double) -> [Double] {
        let n = c.count
        if n < 60 || sig.count != n { return [0, 0, 0, 0, 0] }
        var nav: [Double] = []
        nav.append(1.0)
        var pos = 0
        var entry = 0.0
        var trades = 0
        var wins = 0
        var holdDays = 0
        var v = 1.0
        var i = 1
        while i < n {
            let want = sig[i - 1]
            var r = 0.0
            if want == 1 && pos == 0 {
                pos = 1
                entry = c[i]
                trades += 1
                v = v * (1.0 - costBps / 10000.0)
            } else if want == 0 && pos == 1 {
                let pnl = c[i] / entry - 1.0
                if pnl > 0 { wins += 1 }
                v = v * (1.0 + pnl) * (1.0 - costBps / 10000.0)
                pos = 0
                trades += 1
            }
            if pos == 1 {
                r = c[i] / c[i - 1] - 1.0
                v = v * (1.0 + r)
                holdDays += 1
            }
            nav.append(v)
            i += 1
        }
        if pos == 1 { trades += 1 }
        let ret = (v - 1.0) * 100.0
        let dd = maxDD(nav) * 100.0
        let wr = trades > 0 ? Double(wins) / Double(trades) * 100.0 : 0
        let holdPct = Double(holdDays) / Double(n - 1) * 100.0
        return [ret, dd, Double(trades), wr, holdPct]
    }

    // ---------- 参数网格（按策略给候选） ----------
    static func autoParams(_ k: Int) -> [[Int]] {
        if k == 3 {
            return [[3, 20], [5, 20], [5, 30], [8, 30], [10, 40], [5, 60], [10, 60]]
        }
        if k == 4 {
            return [[14, 25], [14, 30], [14, 35], [7, 30], [21, 30]]
        }
        if k == 5 {
            return [[20, 0], [14, 0], [26, 0]]
        }
        if k == 6 {
            return [[10, 60], [20, 60], [10, 40], [20, 40]]
        }
        return [[12, 26]]
    }

    // ---------- 主入口：自适应分析 ----------
    // 返回每项 8 个数：[编号, 收益, 回撤, 交易, 胜率, 持仓%, 邻域稳健%, 切片稳健%]
    static func autoAnalyze(_ c: [Double], _ h: [Double], _ l: [Double]) -> [[Double]] {
        var out: [[Double]] = []
        if c.count < 120 { return out }
        let cost = 20.0

        // 标的档案
        let vol = annVol(rets(c)) * 100.0
        let erNow = erAt(c, c.count - 1, 60) ?? 0
        let hx: Double? = hurst(c)
        let hu = hx ?? 0.5

        // 按档案决定搜索偏好：趋势强→偏趋势族；震荡→偏均值回归族
        var prefFamily = 1
        if erNow < 0.20 || hu < 0.45 { prefFamily = 2 }

        var k = 0
        while k < autoCount() {
            let fam = autoFamily(k)
            // 基准永远测；非偏好族也测，但后面排序时降权
            let ps = autoParams(k)
            var best: [Double]? = nil
            var bestP: [Int] = [0, 0]
            var pi = 0
            while pi < ps.count {
                let sig = autoSignal(c, h, l, k, ps[pi][0], ps[pi][1])
                let r = autoBacktest(c, sig, cost)
                if best == nil || r[0] > best![0] {
                    best = r
                    bestP = ps[pi]
                }
                pi += 1
            }
            if best != nil {
                let nb = autoNeighbor(c, h, l, k, bestP)
                let sp = autoSplit(c, h, l, k, bestP)
                var row: [Double] = []
                row.append(Double(k))
                row.append(best![0])
                row.append(best![1])
                row.append(best![2])
                row.append(best![3])
                row.append(best![4])
                row.append(nb)
                row.append(sp)
                row.append(Double(bestP[0]))
                row.append(Double(bestP[1]))
                row.append(Double(fam))
                row.append(Double(prefFamily))
                row.append(vol)
                row.append(erNow * 100.0)
                row.append(hu)
                out.append(row)
            }
            k += 1
        }
        return out
    }

    // 邻域稳健度：最优参数附近挪一格，看还正不正
    // 返回 0~100
    static func autoNeighbor(_ c: [Double], _ h: [Double], _ l: [Double],
                             _ k: Int, _ p: [Int]) -> Double {
        if k == 0 { return 100.0 }
        var deltas: [[Int]] = []
        if k == 3 {
            deltas = [[-2, 0], [2, 0], [0, -10], [0, 10], [-2, -10], [2, 10]]
        } else if k == 4 {
            deltas = [[-7, 0], [7, 0], [0, -5], [0, 5]]
        } else if k == 5 {
            deltas = [[-6, 0], [6, 0]]
        } else if k == 6 {
            deltas = [[-10, 0], [10, 0], [0, -20], [0, 20]]
        } else {
            deltas = []
        }
        if deltas.count == 0 { return 50.0 }
        var ok = 0
        var tested = 0
        var d = 0
        while d < deltas.count {
            var np = p
            np[0] = p[0] + deltas[d][0]
            np[1] = p[1] + deltas[d][1]
            if np[0] >= 2 && np[1] >= 3 && np[0] < np[1] {
                let sig = autoSignal(c, h, l, k, np[0], np[1])
                let r = autoBacktest(c, sig, 20.0)
                if r[0] > 0 { ok += 1 }
                tested += 1
            }
            d += 1
        }
        if tested == 0 { return 50.0 }
        return Double(ok) / Double(tested) * 100.0
    }

    // 时间切片稳健度：前后两段是否都为正
    static func autoSplit(_ c: [Double], _ h: [Double], _ l: [Double],
                          _ k: Int, _ p: [Int]) -> Double {
        let n = c.count
        if n < 200 || k == 0 { return 50.0 }
        let half = n / 2
        var c1: [Double] = []
        var h1: [Double] = []
        var l1: [Double] = []
        var c2: [Double] = []
        var h2: [Double] = []
        var l2: [Double] = []
        var i = 0
        while i < n {
            if i < half {
                c1.append(c[i]); h1.append(h[i]); l1.append(l[i])
            } else {
                c2.append(c[i]); h2.append(h[i]); l2.append(l[i])
            }
            i += 1
        }
        let s1 = autoSignal(c1, h1, l1, k, p[0], p[1])
        let r1 = autoBacktest(c1, s1, 20.0)
        let s2 = autoSignal(c2, h2, l2, k, p[0], p[1])
        let r2 = autoBacktest(c2, s2, 20.0)
        var ok = 0.0
        if r1[0] > 0 { ok += 1 }
        if r2[0] > 0 { ok += 1 }
        return ok / 2.0 * 100.0
    }

    // ---------- 综合评分与推荐 ----------
    // 评分 = 收益 为主，稳健度为门槛；不稳健的直接降权
    static func autoScore(_ row: [Double]) -> Double {
        if row.count < 8 { return -999 }
        let ret = row[1]
        let dd = row[2]
        let nb = row[6]
        let sp = row[7]
        // 稳健度门槛：邻域 <40% 或 切片 <50% → 大幅降权
        var gate = 1.0
        if nb < 40 { gate = 0.40 }
        if sp < 50 { gate = gate * 0.70 }
        // 回撤惩罚
        var sc = ret - dd * 0.30
        sc = sc * gate
        return sc
    }

    // 推荐结论：返回 [编号, 收益, 回撤, 交易, 胜率, 持仓%, 邻域, 切片, p1, p2, 置信度]
    static func autoPick(_ rows: [[Double]]) -> [Double] {
        if rows.isEmpty { return [] }
        var best = rows[0]
        var bs = autoScore(rows[0])
        var i = 1
        while i < rows.count {
            let s = autoScore(rows[i])
            if s > bs { bs = s; best = rows[i] }
            i += 1
        }
        // 基准（持有）收益
        var baseRet = 0.0
        i = 0
        while i < rows.count {
            if rows[i][0] < 0.5 { baseRet = rows[i][1] }
            i += 1
        }
        // 置信度：综合稳健度、超额、样本交易数
        var conf = 0.0
        conf += best[6] * 0.45
        conf += best[7] * 0.35
        let excess = best[1] - baseRet
        if excess > 5 { conf += 20 }
        else if excess > 0 { conf += 10 }
        if best[3] >= 10 { conf += 10 }
        else if best[3] >= 5 { conf += 5 }
        if conf > 95 { conf = 95 }
        if conf < 0 { conf = 0 }
        var out = best
        out.append(conf)
        out.append(baseRet)
        return out
    }

    static func autoConfText(_ c: Double) -> String {
        if c >= 75 { return "较高" }
        if c >= 55 { return "中等" }
        if c >= 35 { return "偏低" }
        return "不足"
    }

    // 自适应建议文案
    static func autoAdvice(_ pick: [Double], _ rows: [[Double]]) -> String {
        if pick.count < 12 { return "样本不足，无法给出建议" }
        let k = Int(pick[0])
        let ret = pick[1]
        let base = pick[13]
        let conf = pick[12]
        let nb = pick[6]
        let sp = pick[7]
        let name = autoName(k)
        var s = ""
        if k == 0 {
            s = "本标的历史上「一直持有」得分最高（" + fmt1(base) + "%）。"
            s = s + "任何择时规则都会因频繁进出拖累收益，建议直接持有或减少操作频率。"
            return s
        }
        s = "本标的自适应选出「" + name + "」，历史收益 " + fmt1(ret) + "%，"
        s = s + "同期持有 " + fmt1(base) + "%，超额 " + fmt1(ret - base) + " 个百分点。"
        if conf < 35 {
            s = s + " 但邻域稳健度仅 " + fmt0(nb) + "%、时间切片 " + fmt0(sp) + "%，"
            s = s + "证据不足——这个结果很可能来自参数碰巧，不建议照搬。"
        } else if conf < 55 {
            s = s + " 稳健度中等，可作参考，但请先小仓位验证，别一次上满。"
        } else {
            s = s + " 稳健度较好，可优先考虑。"
        }
        return s
    }

    static func fmt1(_ x: Double) -> String { return String(format: "%.1f", x) }
    static func fmt0(_ x: Double) -> String { return String(format: "%.0f", x) }


    // ============================================================
    // 资产类别识别 —— 标的中性框架核心
    // 工具不绑定任何单一标的：关联池 / 外围池 / 成分池
    // 全部按当前标的的类别动态选择
    // ============================================================
    // 类别：0=A股宽基 1=A股行业主题 2=港股/中概 3=海外市场
    //       4=商品 5=债券 6=货币 7=A股个股 8=其他

    static func prefixIn(_ code6: String, _ list: [String]) -> Bool {
        var i = 0
        while i < list.count {
            if code6.hasPrefix(list[i]) { return true }
            i += 1
        }
        return false
    }

    static func digits6(_ codeIn: String) -> String {
        let c = codeIn.lowercased()
        var num = ""
        for ch in c {
            let s = String(ch)
            if s >= "0" && s <= "9" { num = num + s }
        }
        return num
    }

    static func assetClass(_ codeIn: String) -> Int {
        let c = codeIn.lowercased()
        if c.hasPrefix("hk") { return 2 }
        if c.hasPrefix("us") { return 3 }
        let num = digits6(codeIn)
        if num.count < 6 { return 8 }
        let p6 = String(num.prefix(6))
        if p6.hasPrefix("60") || p6.hasPrefix("68") { return 7 }
        if p6.hasPrefix("00") || p6.hasPrefix("30") { return 7 }
        if p6.hasPrefix("43") || p6.hasPrefix("83") || p6.hasPrefix("87") || p6.hasPrefix("88") { return 7 }
        if prefixIn(p6, ["5119", "5116", "5118", "1590"]) { return 6 }
        if prefixIn(p6, ["5112", "5110", "5113", "5111", "1596", "1598"]) { return 5 }
        if prefixIn(p6, ["5188", "159934", "159937", "159981", "159980", "159985", "161226", "162411"]) { return 4 }
        if prefixIn(p6, ["513100", "159941", "513500", "159612", "513300", "513520", "513080", "513030", "159632", "513850", "513390"]) { return 3 }
        if prefixIn(p6, ["513770", "513050", "159792", "513330", "159605", "513690", "159636", "159892", "513970", "513120", "159561"]) { return 2 }
        if prefixIn(p6, ["510300", "510310", "510050", "510500", "512500", "159915", "588000", "159901", "510880", "515080", "512100", "159949", "510180", "159919", "515800", "510210", "159629", "512550"]) { return 0 }
        if p6.hasPrefix("51") || p6.hasPrefix("15") || p6.hasPrefix("16") || p6.hasPrefix("56") || p6.hasPrefix("58") { return 1 }
        return 8
    }

    static func assetClassName(_ cls: Int) -> String {
        if cls == 0 { return "A股宽基" }
        if cls == 1 { return "行业/主题" }
        if cls == 2 { return "港股/中概" }
        if cls == 3 { return "海外市场" }
        if cls == 4 { return "商品" }
        if cls == 5 { return "债券" }
        if cls == 6 { return "货币" }
        if cls == 7 { return "个股" }
        return "其他"
    }

    /// 关联指数/同类标的：与当前标的直接相关的市场参照
    static func contextCodes(_ cls: Int) -> [String] {
        if cls == 2 { return ["hkHSI", "hkHSTECH", "usIXIC", "sh000001"] }
        if cls == 3 { return ["usIXIC", "usINX", "usDJI", "hkHSI"] }
        if cls == 4 { return ["sh518880", "usIXIC", "sh000001"] }
        if cls == 5 { return ["sh511260", "sh511010", "sh000001"] }
        if cls == 6 { return ["sh511990", "sh511880", "sh000001"] }
        if cls == 7 { return ["sh000001", "sz399001", "sz399006", "sh000300"] }
        return ["sh000001", "sz399001", "sz399006", "sh000300"]
    }

    /// 隔夜外围：按标的市场归属选择，不再固定为港股视角
    static func overnightCodes(_ cls: Int) -> [String] {
        if cls == 2 { return ["hkHSI", "hkHSTECH", "usIXIC", "usINX"] }
        if cls == 3 { return ["usIXIC", "usINX", "usDJI", "hkHSI"] }
        if cls == 4 { return ["usIXIC", "usINX", "hkHSI", "sh000001"] }
        if cls == 5 { return ["usIXIC", "hkHSI", "sh000001"] }
        if cls == 6 { return ["sh000001", "sz399001"] }
        if cls == 7 { return ["hkHSI", "usIXIC", "usINX", "sh000001"] }
        return ["hkHSI", "usIXIC", "usINX", "usDJI"]
    }

    /// 仅当标的有已知持仓明细时才展示成分模块：避免把 A 的成分套到 B 上
    static func hasHoldings(_ codeIn: String) -> Bool {
        let num = digits6(codeIn)
        if num.count < 6 { return false }
        let p6 = String(num.prefix(6))
        return prefixIn(p6, ["513770", "513050", "159792", "159605"])
    }

    /// ADR 参照仅对港股/中概标的有意义
    static func showAdr(_ cls: Int) -> Bool { return cls == 2 }

}
