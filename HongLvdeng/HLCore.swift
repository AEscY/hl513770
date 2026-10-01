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

// 分时逐笔成交（腾讯免费接口，3 秒粒度，带主动买卖标记）
struct HLTick {
    var t: String = ""      // 时间 HH:MM:SS
    var price: Double = 0   // 成交价
    var vol: Double = 0     // 成交量（手）
    var amt: Double = 0     // 成交额（元）
    var isBuy: Bool = true  // 主动买
}

// 资金流统计
struct HLFlowStat {
    var buyAmt: Double = 0    // 主动买总额
    var sellAmt: Double = 0   // 主动卖总额
    var netAmt: Double = 0    // 净额
    var xlNet: Double = 0     // 超大单净额 >=100万
    var lgNet: Double = 0     // 大单净额 20万~100万
    var mdNet: Double = 0     // 中单净额 4万~20万
    var smNet: Double = 0     // 小单净额 <4万
    var count: Int = 0        // 笔数
    var bigCount: Int = 0     // 超大单笔数
    var buyRatio: Double = 0  // 主动买占比 %
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
                            _ nextOpen: Bool = true,
                            _ volumes: [Double]? = nil) -> [Double] {
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
            else if kind == 14 {
                // 追涨 + 趋势止损（与 backtestCore 的 kind==14 保持一致）
                if i >= 2 {
                    let m20 = maAt(c, 20, i - 1)
                    if m20 != nil {
                        var canBuy = prev > c[i - 2]
                        if let vol = volumes, vol.count == c.count {
                            var vs: [Double] = []
                            var j = i - 20
                            while j < i { if j >= 0 { vs.append(vol[j]) }; j += 1 }
                            var sv = 0.0
                            for x in vs { sv += x }
                            let av = vs.count > 0 ? sv / Double(vs.count) : 0.0
                            if av > 0 { canBuy = canBuy && (vol[i - 1] > 1.5 * av) }
                        }
                        if pos <= 0.001 && canBuy { target = 1.0 }
                        else if pos > 0.001 && prev < m20! { target = 0.0 }
                    }
                }
            } else if kind == 15 {
                // 低买高卖（反面教材，与 backtestCore 的 kind==15 一致）
                let r = rsiAt(c, 14, i - 1)
                if r != nil {
                    if pos <= 0.001 && r! < 30 { target = 1.0 }
                    else if pos > 0.001 && r! > 70 { target = 0.0 }
                }
            } else if kind == 16 {
                // 低买 + 趋势卖出（与 backtestCore 的 kind==16 一致）
                let r = rsiAt(c, 14, i - 1)
                let m20 = maAt(c, 20, i - 1)
                if r != nil && m20 != nil {
                    if pos <= 0.001 && r! < 30 { target = 1.0 }
                    else if pos > 0.001 && prev < m20! { target = 0.0 }
                }
            } else if kind == 17 {
                // 低买 + 不卖（与 backtestCore 的 kind==17 一致）
                let r = rsiAt(c, 14, i - 1)
                if r != nil {
                    if pos <= 0.001 && r! < 30 { target = 1.0 }
                }
            } else if kind == 13 { target = 0.0 }
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
                         _ nextOpen: Bool = true,
                         _ volumes: [Double]? = nil) -> [Double] {
        return backtestCore(c, kind, opens, costBps, nextOpen, volumes)
    }

    static func backtestCore(_ c: [Double], _ kind: Int,
                             _ opens: [Double]?,
                             _ costBps: Double,
                             _ nextOpen: Bool,
                             _ volumes: [Double]? = nil) -> [Double] {
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
            } else if kind == 14 {
                // 追涨 + 趋势止损：放量(>1.5x20日均量)且上涨买入，跌破 MA20 才卖
                // 关键：卖出只认趋势破位，不因"涨多了"而卖（截断亏损、让利润奔跑）
                if i >= 2 {
                    let m20 = maAt(c, 20, i - 1)
                    if m20 != nil {
                        var canBuy = prev > c[i - 2]
                        if let vol = volumes, vol.count == c.count {
                            var vs: [Double] = []
                            var j = i - 20
                            while j < i { if j >= 0 { vs.append(vol[j]) }; j += 1 }
                            var sv = 0.0
                            for x in vs { sv += x }
                            let av = vs.count > 0 ? sv / Double(vs.count) : 0.0
                            if av > 0 { canBuy = canBuy && (vol[i - 1] > 1.5 * av) }
                        }
                        if pos <= 0.001 && canBuy { target = 1.0 }
                        else if pos > 0.001 && prev < m20! { target = 0.0 }
                    }
                }
            } else if kind == 15 {
                // 低买高卖（反面教材）：RSI(14)<30 买，RSI(14)>70 卖
                // 实测：四个窗口全为负，问题出在"涨多了就卖"
                let r = rsiAt(c, 14, i - 1)
                if r != nil {
                    if pos <= 0.001 && r! < 30 { target = 1.0 }
                    else if pos > 0.001 && r! > 70 { target = 0.0 }
                }
            } else if kind == 16 {
                // 低买 + 趋势卖出：RSI<30 买，跌破 MA20 卖（只换卖出规则，买入与 15 相同）
                let r = rsiAt(c, 14, i - 1)
                let m20 = maAt(c, 20, i - 1)
                if r != nil && m20 != nil {
                    if pos <= 0.001 && r! < 30 { target = 1.0 }
                    else if pos > 0.001 && prev < m20! { target = 0.0 }
                }
            } else if kind == 17 {
                // 低买 + 不卖：RSI<30 买后一直持有（对照基准，用于分离"卖"的贡献）
                let r = rsiAt(c, 14, i - 1)
                if r != nil {
                    if pos <= 0.001 && r! < 30 { target = 1.0 }
                }
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
    // 返回 [独立样本数, 平均收益%, 上涨率%, 最好, 最差, 平均盈利, 平均亏损, 未去重数, 重叠率%]
    // 关键修正：加入最小间隔约束。相邻样本间隔 < horizon 时，其"未来 20 日"区间高度重叠，
    // 同一段行情会被重复计数，导致样本数虚高、结论看似更可靠实则不然。
    static func similarStats(_ c: [Double]) -> [Double] {
        if c.count < 120 { return [0, 0, 0, 0, 0, 0, 0, 0, 0] }
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
            pool.append([d, fut, Double(i)])
            i += 5
        }
        if pool.isEmpty { return [0, 0, 0, 0, 0, 0, 0, 0, 0] }
        // 按距离升序，依次取；要求与已选样本的索引间隔 >= horizon（未来区间不重叠）
        var sorted: [[Double]] = []
        var rawPicked = 0
        var overlapped = 0
        var rest = pool
        while sorted.count < 15 && rest.isEmpty == false {
            var bi = 0
            var j = 1
            while j < rest.count { if rest[j][0] < rest[bi][0] { bi = j }; j += 1 }
            let cand = rest[bi]
            rest.remove(at: bi)
            rawPicked += 1
            var ok = true
            var t = 0
            while t < sorted.count {
                if abs(cand[2] - sorted[t][2]) < Double(horizon) { ok = false }
                t += 1
            }
            if ok { sorted.append(cand) } else { overlapped += 1 }
        }
        if sorted.isEmpty { return [0, 0, 0, 0, 0, 0, 0, 0, 0] }
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
        let overlapRate = rawPicked > 0 ? Double(overlapped) / Double(rawPicked) * 100.0 : 0
        return [n, sum / n, Double(up) / n * 100, best, worst, avgWin, avgLoss,
                Double(rawPicked), overlapRate]
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

    /// 信号质量 + 重叠校正
    /// 返回 [原始样本n, 有效样本nEff, 后horizon日均值%, 上涨率%, 未校正t, 校正t]
    /// 逐日滑动 horizon 日窗口 → 相邻观测重叠 horizon 次，
    /// 有效独立样本 = n / horizon；不校正会把 t 值放大约 sqrt(horizon) 倍。
    /// 实测（70标的×800日）：逐日重叠 t=11.34，每20日取样 t=1.63（不再显著）。
    static func signalQualityAdj(_ c: [Double], _ kind: Int, _ horizon: Int = 20) -> [Double] {
        if c.count < 90 { return [0, 0, 0, 0, 0, 0] }
        var vals = [Double]()
        var i = 60
        while i + horizon < c.count {
            let m20 = maAt(c, 20, i)
            let m60 = maAt(c, 60, i)
            if let a = m20, let b = m60 {
                let p = c[i]
                var sig = 0
                if p < a { sig = 0 }
                else if p < b { sig = 1 }
                else { sig = 2 }
                if sig == kind, c[i] > 0 {
                    vals.append((c[i + horizon] / c[i] - 1) * 100)
                }
            }
            i += 1
        }
        let n = Double(vals.count)
        if n < 3 { return [n, 0, 0, 0, 0, 0] }
        var s = 0.0
        for v in vals { s += v }
        let mean = s / n
        var ss = 0.0
        for v in vals { let d = v - mean; ss += d * d }
        let sd = sqrt(ss / (n - 1))
        var up = 0.0
        for v in vals { if v > 0 { up += 1 } }
        let upRate = up / n * 100.0
        let nEff = max(1.0, n / Double(horizon))
        let tRaw = sd > 0 ? mean / (sd / sqrt(n)) : 0
        let tAdj = sd > 0 ? mean / (sd / sqrt(nEff)) : 0
        return [n, nEff, mean, upRate, tRaw, tAdj]
    }

    /// 各类别「绿灯后20日超额 − 红灯后20日超额」（剔除市场beta、非重叠取样）
    /// 来源：70标的 × 800交易日 实测（2023-06 ~ 2026-09），会随时间变化，仅作历史参考
    static func clsSignalEdge(_ cls: String) -> Double {
        switch cls {
        case "海外": return 1.665
        case "个股": return 1.384
        case "宽基": return 1.028
        case "商品": return 0.680
        case "行业": return 0.611
        case "债券": return -0.274
        case "货币": return -0.058
        case "港股": return -3.242
        default: return 0
        }
    }

    /// 依据类别信号优势给出提示文案
    static func clsSignalHint(_ cls: String) -> String {
        let e = clsSignalEdge(cls)
        if e <= -1.5 {
            return "本类别历史实测：绿灯亮起后 20 日反而跑输红灯 \(String(format: "%.1f", abs(e))) 个点，绿灯不作为买入依据"
        }
        if e < 0.3 {
            return "本类别历史实测：绿灯相对红灯优势仅 \(String(format: "%.2f", e)) 个点，信号区分度弱"
        }
        if e < 1.0 {
            return "本类别历史实测：绿灯后 20 日优于红灯 \(String(format: "%.2f", e)) 个点，优势有限"
        }
        return "本类别历史实测：绿灯后 20 日优于红灯 \(String(format: "%.2f", e)) 个点，信号区分度较高"
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



    // ===== 解套方案引擎 =====
    // 针对已亏损持仓，给出四条路径及其代价。全部基于「本标的自身历史」统计，
    // 不引用任何外部标的的规律。返回 16 个数：
    //  0 浮亏额   1 浮亏%    2 回本需涨%
    //  3 等回本·250天内达标概率%   4 等回本·中位耗时(天)   5 等回本·样本数
    //  6 补仓·新成本  7 补仓·回本需涨%  8 补仓·跌到止损亏损额  9 补仓·总投入
    // 10 做T·单次净收益  11 做T·需成功次数(-1=不可行)  12 日均振幅%
    // 13 止损·实亏额  14 止损·收回资金  15 不补仓·跌到止损亏损额
    static func hlRescue(_ cIn: [Double], _ hIn: [Double], _ lIn: [Double],
                         cost: Double, shares: Double, price: Double,
                         stop: Double, addCash: Double,
                         tShares: Double, fee: Double) -> [Double] {
        var r = [Double](repeating: 0, count: 16)
        if price <= 0 || cost <= 0 || shares <= 0 { return r }
        let n = min(cIn.count, min(hIn.count, lIn.count))
        if n < 60 { return r }
        let c = Array(cIn[(cIn.count - n)..<cIn.count])
        let h = Array(hIn[(hIn.count - n)..<hIn.count])
        let l = Array(lIn[(lIn.count - n)..<lIn.count])

        // --- 现状 ---
        let pnl = (price - cost) * shares
        r[0] = pnl
        r[1] = (price - cost) / cost * 100.0
        r[2] = (cost - price) / price * 100.0
        r[13] = pnl
        r[14] = price * shares
        r[15] = (stop - cost) * shares

        // --- A 等回本：只统计「低位起点」，规避幸存者偏差 ---
        //   若把所有起点混在一起，高位起点会系统性拉低成功率，结论失真
        var curRank = 0.0
        let wRank = min(250, n)
        if wRank > 0 {
            var less = 0
            var i = n - wRank
            while i < n {
                if c[i] < price { less += 1 }
                i += 1
            }
            curRank = Double(less) / Double(wRank) * 100.0
        }
        let maxStart = n - 250
        if maxStart > 30 && r[2] > 0 {
            let target = r[2] / 100.0
            var starts = 0
            var hits = [Int]()
            var i = 0
            while i < maxStart {
                let s0 = i > 250 ? (i - 250) : 0
                let span = i - s0
                if span > 0 {
                    var less = 0
                    var j = s0
                    while j < i {
                        if c[j] < c[i] { less += 1 }
                        j += 1
                    }
                    let rank = Double(less) / Double(span) * 100.0
                    if rank <= curRank + 8.0 {
                        starts += 1
                        let lim = min(i + 250, n)
                        var k2 = i + 1
                        while k2 < lim {
                            if c[k2] >= c[i] * (1.0 + target) {
                                hits.append(k2 - i)
                                break
                            }
                            k2 += 1
                        }
                    }
                }
                i += 1
            }
            r[5] = Double(starts)
            if starts > 0 && hits.isEmpty == false {
                r[3] = Double(hits.count) / Double(starts) * 100.0
                let sortedHits = hits.sorted()
                r[4] = Double(sortedHits[sortedHits.count / 2])
            }
        }

        // --- B 补仓摊薄 ---
        if addCash > 0 {
            let addS = addCash / price
            let tot = shares + addS
            if tot > 0 {
                let nc = (cost * shares + addCash) / tot
                r[6] = nc
                r[7] = (nc - price) / price * 100.0
                r[8] = (stop - nc) * tot
                r[9] = cost * shares + addCash
            }
        } else {
            r[6] = cost
            r[7] = r[2]
            r[8] = r[15]
            r[9] = cost * shares
        }

        // --- C 做T降成本：按近20日真实振幅估算，假设能抓到一半 ---
        var ampSum = 0.0
        var ampCnt = 0
        var i2 = n - 20
        if i2 < 1 { i2 = 1 }
        while i2 < n {
            let prev = c[i2 - 1]
            if prev > 0 {
                ampSum += (h[i2] - l[i2]) / prev * 100.0
                ampCnt += 1
            }
            i2 += 1
        }
        let amp = ampCnt > 0 ? (ampSum / Double(ampCnt)) : 0.0
        r[12] = amp
        let spread = price * amp / 100.0 * 0.5
        let perT = spread * tShares - fee * 2.0
        r[10] = perT
        r[11] = perT > 0 ? (abs(pnl) / perT) : -1

        return r
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

    // ==================================================================
    // MARK: - 策略适配度（风险口径）
    //
    // 为什么改口径（57 标的 × 801 日实测）：
    //   平均仓位仅 40.2%，上涨标的中「择时/持有」收益比中位 0.553，
    //   下跌标的中 12/15 亏得更少 —— 本质是「削 beta」，不是「提高收益」。
    //   用「超额收益」评价它会系统性误导：超额与持有收益 r = -0.727，
    //   标的涨得越多超额越差，但这不代表策略有害，只说明它少赚。
    //   改用夏普改善后，相关度降到 r = -0.290，判定更接近风险本身。
    //   注意：改动后仅 3 个标的判定翻转（半导体、标普500、紫金矿业），
    //   「宽基会整体翻盘」的预期并未成立，实测宽基夏普改善为 -0.105、3/10 为正。
    // ==================================================================

    struct HLFitResult {
        var timing: Double = 0      // 择时总收益（小数）
        var hold: Double = 0        // 持有总收益（小数）
        var excess: Double = 0      // 超额 = timing - hold
        var trades: Int = 0
        var sharpeT: Double = 0     // 择时净值夏普
        var sharpeH: Double = 0     // 持有净值夏普
        var dSharpe: Double = 0     // 夏普改善（主判定）
        var ddT: Double = 0         // 择时最大回撤（正数，越大越差）
        var ddH: Double = 0         // 持有最大回撤（正数）
        var dDD: Double = 0         // ddH - ddT，正 = 回撤变小 = 改善
        var exposure: Double = 0    // 持仓天数占比
        var volH: Double = 0        // 持有年化波动
        var lowVol: Bool = false    // 低波动：夏普分母不可靠
        var fit: Bool = false
        var warnTrades: Bool = false
    }

    /// 择时/持有两条净值曲线（与界面红绿灯同规则：MA20/MA60，次日开盘成交，扣 5bps）
    static func fitEquity(_ close: [Double], _ open: [Double])
        -> (eqT: [Double], eqH: [Double], trades: Int, exposure: Double) {
        let n = close.count
        if n < 150 || open.count != n { return ([], [], 0, 0) }
        let start = 60
        let fee = 0.0005
        var cash = 1.0
        var shares = 0.0
        var trades = 0
        var prev = ""
        var pend = ""
        var held = 0
        var days = 0
        var eqT: [Double] = []
        var eqH: [Double] = []
        let base = close[start]
        if base <= 0 { return ([], [], 0, 0) }
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
            eqT.append(cash + shares * close[i])
            eqH.append(close[i] / base)
            if shares > 0 { held += 1 }
            days += 1
            i += 1
        }
        let exposure = days > 0 ? Double(held) / Double(days) : 0
        return (eqT, eqH, trades, exposure)
    }

    static func strategyFitEx(_ close: [Double], _ open: [Double]) -> HLFitResult {
        var r = HLFitResult()
        let e = fitEquity(close, open)
        if e.eqT.count < 30 { return r }
        r.trades = e.trades
        r.exposure = e.exposure
        r.timing = (e.eqT.last ?? 1.0) - 1.0
        r.hold = (e.eqH.last ?? 1.0) - 1.0
        r.excess = r.timing - r.hold
        r.sharpeT = sharpe(e.eqT)
        r.sharpeH = sharpe(e.eqH)
        r.dSharpe = r.sharpeT - r.sharpeH
        r.ddT = maxDD(e.eqT)
        r.ddH = maxDD(e.eqH)
        r.dDD = r.ddH - r.ddT
        r.volH = annVol(rets(e.eqH))

        // 低波动门禁：债券/货币等波动极低，夏普分母趋近 0 会算出天文数字
        // （此前 WFE 就因此在分母近 0 时算出 17.57），故改用回撤改善判定
        r.lowVol = r.volH < 0.05
        if r.lowVol {
            r.fit = r.dDD > 0.01
        } else {
            r.fit = r.dSharpe > 0
        }
        // 交易越多越差：实测 ≥70 笔的组平均超额 -27.26 个点（n=31），
        // <60 笔的组 +33.93 个点（n=11）
        r.warnTrades = r.trades >= 70
        return r
    }

    /// 同类参照组：用于计算「同类离散度」。
    /// 性质是「参照组」不是「基准」——不参与任何信号判定，只用于提示结论可否外推。
    static func peerGroupCodes(_ cls: Int) -> [String] {
        if cls == 0 { return ["sh510300", "sh510050", "sh510500", "sz159915", "sh588000", "sz159949", "sh510880", "sh512100"] }
        if cls == 1 { return ["sh512480", "sh512170", "sh515790", "sh512690", "sh512660", "sh515030", "sh512010", "sh512800"] }
        if cls == 2 { return ["sh513770", "sh513050", "sz159792", "sh513330", "sz159605", "sh513690"] }
        if cls == 3 { return ["sh513100", "sz159941", "sh513500", "sh513300"] }
        if cls == 4 { return ["sh518880", "sz159934", "sz159981"] }
        if cls == 5 { return ["sh511260", "sh511010", "sh511180"] }
        if cls == 6 { return ["sh511990", "sh511880", "sz159001"] }
        if cls == 7 { return ["sh600519", "sz000858", "sh601318", "sz300750", "sh688981"] }
        return ["sh510300", "sh518880", "sh511260", "sh513100"]
    }

    /// 离散度：同类标的最好与最差差多少。差得越大，单个标的的结论越不可外推。
    static func peerDispersion(_ vals: [Double])
        -> (min: Double, max: Double, spread: Double, sd: Double, n: Int) {
        let v = vals.filter { $0.isFinite }
        if v.count < 2 { return (0, 0, 0, 0, v.count) }
        var mn = v[0]; var mx = v[0]
        for x in v { if x < mn { mn = x }; if x > mx { mx = x } }
        var m = 0.0
        for x in v { m += x }
        m /= Double(v.count)
        var ss = 0.0
        for x in v { ss += (x - m) * (x - m) }
        let sd = (ss / Double(v.count - 1)).squareRoot()
        return (mn, mx, mx - mn, sd, v.count)
    }

    /// 离散度是否高到「结论不可外推」。
    /// 实测依据（57 标的 × 801 日，同类内部超额极差）：
    ///   债券 1.6 < 港股 16.4 < 商品 31.7 < 海外 44.2 < 宽基 51.5 < 行业 123.8 < 个股 204.7
    /// 除港股与债券外，其余类别内部差异都远超 20 个点 —— 结论确实不可外推。
    static func peerSpreadRisk(_ spread: Double) -> Bool { return spread > 20.0 }

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
        // 必须与界面信号灯同规则：kind=1 为红绿灯(MA20/MA60)
        // 早期误用 kind=2(双均线 MA5/20)，导致"建议择时"与界面给出的红绿灯不是一回事
        let r = backtest(sc, 1, so, 20.0, true)
        return ((r[0] - 1.0) * 100.0, (sc.last! / sc.first! - 1.0) * 100.0)
    }

    /// 分段风险口径：直接复用 fitEquity，保证与界面红绿灯、strategyFitEx 三处同规则
    static func segRisk(_ c: [Double], _ o: [Double], _ from: Int, _ to: Int)
        -> (dSharpe: Double, dDD: Double, exposure: Double,
            timing: Double, hold: Double, trades: Int) {
        if to - from < 70 || c.count != o.count || to > c.count { return (0, 0, 0, 0, 0, 0) }
        let sc = Array(c[from..<to]); let so = Array(o[from..<to])
        let e = fitEquity(sc, so)
        if e.eqT.count < 30 { return (0, 0, 0, 0, 0, 0) }
        let sT = sharpe(e.eqT); let sH = sharpe(e.eqH)
        let dT = maxDD(e.eqT); let dH = maxDD(e.eqH)
        let tim = ((e.eqT.last ?? 1.0) - 1.0) * 100.0
        let hol = ((e.eqH.last ?? 1.0) - 1.0) * 100.0
        return (sT - sH, dH - dT, e.exposure, tim, hol, e.trades)
    }

    // 自适应方案：返回 [模式, 置信度, IS择时, IS持有, OOS择时, OOS持有,
    //                  全样本择时, 全样本持有, 反转风险,
    //                  IS夏普改善, OOS夏普改善, 全样本夏普改善,
    //                  全样本回撤改善, 平均仓位, 低波动标记]
    // 模式：0=持有  1=择时  2=存疑(默认持有)
    //
    // 判定依据已由「超额收益」改为「夏普改善」：
    //   实测平均仓位 40.2%，下跌标的中 12/15 亏得更少，
    //   本策略是削 beta 工具，用收益评价会系统性误导。
    static func adaptivePlan(_ o: [Double], _ h: [Double], _ l: [Double],
                             _ c: [Double]) -> [Double] {
        let n = c.count
        if n < 200 || o.count != n || h.count != n || l.count != n {
            return [2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        }
        let sp = Int(Double(n) * 0.6)
        let isSeg = segRisk(c, o, 0, sp)
        let oosSeg = segRisk(c, o, sp, n)
        let fullSeg = segRisk(c, o, 0, n)

        // 低波动标的夏普分母趋近 0，改用回撤改善判定
        let lowVol = strategyFitEx(c, o).lowVol
        let thr: (Double, Double) -> Bool = lowVol
            ? { (_, d) in d > 0.01 }
            : { (s, _) in s > 0 }

        let isWin = thr(isSeg.dSharpe, isSeg.dDD)
        let oosWin = thr(oosSeg.dSharpe, oosSeg.dDD)

        var mode = 2.0
        var conf = 35.0
        if isWin && oosWin { mode = 1.0; conf = 90.0 }
        else if !isWin && !oosWin { mode = 0.0; conf = 90.0 }

        // 反转风险：前段涨、后段跌 —— 此类标的的历史规律最易失效
        let rev: Double = (isSeg.hold > 0 && oosSeg.hold < 0) ? 1.0 : 0.0

        return [mode, conf, isSeg.timing, isSeg.hold,
                oosSeg.timing, oosSeg.hold, fullSeg.timing, fullSeg.hold, rev,
                isSeg.dSharpe, oosSeg.dSharpe, fullSeg.dSharpe,
                fullSeg.dDD, fullSeg.exposure, lowVol ? 1.0 : 0.0]
    }

    static func adaptiveModeText(_ mode: Double) -> String {
        if mode > 0.5 { return "启用择时" }
        if mode < 0.5 { return "持有不动" }
        return "存疑 · 建议持有"
    }

    // 真·前瞻检验：只用前段(IS)下判断，用后段(OOS)验证。
    // 注意 adaptivePlan 的 mode/conf 由 IS+OOS 共同决定，
    // 若反过来用"IS判断 vs OOS结论"统计命中率会构成循环论证（必然 100%/0%），
    // 因此这里单独提供一个不依赖 OOS 的判断口径。
    // 返回 [IS判断(1=择时/0=持有), OOS实际(1=择时/0=持有), 是否命中, 前段超额, 后段超额]
    static func forwardCheck(_ o: [Double], _ h: [Double], _ l: [Double],
                             _ c: [Double]) -> [Double] {
        let n = c.count
        if n < 200 || o.count != n { return [0, 0, 0, 0, 0] }
        let sp = Int(Double(n) * 0.6)
        let isSeg = segBacktest(o, h, l, c, 0, sp)
        let oosSeg = segBacktest(o, h, l, c, sp, n)
        let isWin: Double = isSeg.timing > isSeg.hold ? 1.0 : 0.0
        let oosWin: Double = oosSeg.timing > oosSeg.hold ? 1.0 : 0.0
        let hit: Double = (isWin == oosWin) ? 1.0 : 0.0
        return [isWin, oosWin, hit, isSeg.timing - isSeg.hold, oosSeg.timing - oosSeg.hold]
    }

    static func forwardCheckText(_ f: [Double]) -> String {
        if f.count < 5 { return "数据不足" }
        let isW = f[0] > 0.5; let oosW = f[1] > 0.5
        let hit = f[2] > 0.5
        if hit {
            return String(format: "前瞻验证通过：仅用前段会判断为「%@」，后段实际也是「%@」。",
                          isW ? "择时" : "持有", oosW ? "择时" : "持有")
        }
        return String(format: "前瞻验证失败：仅用前段会判断为「%@」，但后段实际是「%@」——前段表现无法预测后段。",
                      isW ? "择时" : "持有", oosW ? "择时" : "持有")
    }


    // ---------- 前瞻信号面板 ----------
    // 依据：57 个标的 × 801 根 K 线，标的内去均值后的实证分层。
    // 全部只用 idx 及之前的数据，不含未来信息。
    //
    // 波动分层（当期20日年化波动%）→ 未来20日
    //   Q1 ≤15.0   跌超5%概率 5.9%   绝对波动 3.34%
    //   Q2 15~20.7 跌超5%概率 15.7%  绝对波动 5.70%
    //   Q3 20.7~26.2 概率 21.5%      绝对波动 6.65%
    //   Q4 26.2~35.1 概率 27.2%      绝对波动 7.14%
    //   Q5 >35.1   概率 24.9%        绝对波动 7.24%
    //
    // 偏离 MA60 分层（%）→ 未来60日（z 为标的内标准化）
    //   Q1 ≤-4.5   上涨率 51.7%  z +0.230
    //   Q2 -4.5~-0.4 上涨率 48.0% z +0.130
    //   Q3 -0.4~2.2  上涨率 46.0% z +0.025
    //   Q4 2.2~6.8   上涨率 46.3% z -0.036
    //   Q5 >6.8      上涨率 26.6% z -0.349
    //
    // 事件（触发后未来20日，已扣该标的自身平均）
    //   创60日新低 z +0.305 上涨率 53.8%
    //   RSI<20     z +0.228 上涨率 55.2%
    //   RSI>80     z +0.201 上涨率 54.4%
    //   波动骤降   z -0.109 上涨率 43.0%
    //   波动突增   z +0.076 上涨率 50.8%
    //   基准            　  上涨率 52.1%

    static let fwdDrop5 = [5.9, 15.7, 21.5, 27.2, 24.9]
    static let fwdAbsMv = [3.34, 5.70, 6.65, 7.14, 7.24]
    static let fwdUp60 = [51.7, 48.0, 46.0, 46.3, 26.6]
    static let fwdZ60 = [0.230, 0.130, 0.025, -0.036, -0.349]
    static let fwdBaseUp = 52.1

    static func volBucketOf(_ volAnn: Double) -> Double {
        if volAnn < 15.0 { return 1 }
        if volAnn < 20.7 { return 2 }
        if volAnn < 26.2 { return 3 }
        if volAnn < 35.1 { return 4 }
        return 5
    }

    static func devBucketOf(_ dev: Double) -> Double {
        if dev <= -4.5 { return 1 }
        if dev <= -0.4 { return 2 }
        if dev <= 2.2 { return 3 }
        if dev <= 6.8 { return 4 }
        return 5
    }

    static func forwardSignal(_ c: [Double], _ idx: Int) -> [Double] {
        let n = c.count
        var i = idx
        if i < 0 { i = n - 1 }
        if i >= n { i = n - 1 }
        if n < 130 || i < 80 {
            return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 52.1, 0, 0]
        }
        var r1: [Double] = []
        var j = i - 19
        while j <= i {
            if j > 0 && c[j] > 0 && c[j - 1] > 0 {
                r1.append(log(c[j] / c[j - 1]))
            }
            j = j + 1
        }
        let sd1 = HLCore.stdev(r1)
        let volAnn = sd1 * sqrt(252.0) * 100.0
        let vb = HLCore.volBucketOf(volAnn)
        var bi = Int(vb) - 1
        if bi < 0 { bi = 0 }
        if bi > 4 { bi = 4 }
        let drop5 = HLCore.fwdDrop5[bi]
        let absMv = HLCore.fwdAbsMv[bi]
        var m60 = 0.0
        if let m = HLCore.maAt(c, 60, i) { m60 = m }
        var dev = 0.0
        if m60 > 0 { dev = (c[i] / m60 - 1.0) * 100.0 }
        let db = HLCore.devBucketOf(dev)
        var di = Int(db) - 1
        if di < 0 { di = 0 }
        if di > 4 { di = 4 }
        let up60 = HLCore.fwdUp60[di]
        let z60 = HLCore.fwdZ60[di]
        var evNewLow = 0.0
        if i >= 60 {
            var mn = c[i]
            var k = i - 59
            while k <= i {
                if c[k] < mn { mn = c[k] }
                k = k + 1
            }
            if c[i] <= mn { evNewLow = 1.0 }
        }
        var evRSI20 = 0.0
        var evRSI80 = 0.0
        if let rv = HLCore.rsiAt(c, 14, i) {
            if rv < 20 { evRSI20 = 1.0 }
            if rv > 80 { evRSI80 = 1.0 }
        }
        var vDrop = 0.0
        var vSpike = 0.0
        if i >= 80 {
            var r0: [Double] = []
            var k = i - 59
            while k <= i - 20 {
                if k > 0 && c[k] > 0 && c[k - 1] > 0 {
                    r0.append(log(c[k] / c[k - 1]))
                }
                k = k + 1
            }
            let sd0 = HLCore.stdev(r0)
            if sd0 > 0 && sd1 > 0 {
                let rt = sd1 / sd0
                if rt < 0.6 { vDrop = 1.0 }
                if rt > 1.5 { vSpike = 1.0 }
            }
        }
        var evZ = 0.0
        var evUp = 52.1
        var evName = 0.0
        if vSpike > 0.5 { evZ = 0.076; evUp = 50.8; evName = 5 }
        if vDrop > 0.5 { evZ = -0.109; evUp = 43.0; evName = 4 }
        if evRSI80 > 0.5 { evZ = 0.201; evUp = 54.4; evName = 3 }
        if evRSI20 > 0.5 { evZ = 0.228; evUp = 55.2; evName = 2 }
        if evNewLow > 0.5 { evZ = 0.305; evUp = 53.8; evName = 1 }
        // 告警优先级：追高(1) > 波动骤降(2) > 极低波动(3)
        var warn = 0.0
        if volAnn < 5.0 { warn = 3.0 }
        if vDrop > 0.5 { warn = 2.0 }
        if db > 4.5 { warn = 1.0 }
        return [volAnn, vb, drop5, absMv, dev, db, up60, z60,
                evNewLow, evRSI20, vDrop, vSpike, evZ, evUp, warn, evName]
    }

    static func forwardEventName(_ k: Double) -> String {
        if k > 4.5 { return "波动突增" }
        if k > 3.5 { return "波动骤降" }
        if k > 2.5 { return "RSI 超买" }
        if k > 1.5 { return "RSI 超卖" }
        if k > 0.5 { return "创 60 日新低" }
        return "无极端事件"
    }

    static func forwardWarnText(_ w: Double) -> String {
        if w < 0.5 {
            return "无显著警示"
        }
        if w < 1.5 {
            return "偏离 MA60 过高 · 历史上涨率仅 26.6%，不宜追高"
        }
        if w < 2.5 {
            return "波动骤降 · 安静不等于安全，历史上涨率仅 43.0%"
        }
        return "极低波动 · 跨资产统计概率对本标的可能偏高"
    }

    static func forwardVerdict(_ f: [Double]) -> String {
        if f.count < 16 { return "数据不足" }
        let db = f[5]
        let warn = f[14]
        if warn > 1.5 { return "安静期 · 勿因低波动贸然加仓" }
        if db > 4.5 { return "位置偏高 · 历史上涨率显著下降" }
        if db < 1.5 { return "位置偏低 · 但下跌本身不构成买入理由" }
        return "位置中性 · 无显著前瞻信号"
    }

    static func adaptiveConfText(_ conf: Double) -> String {
        if conf >= 90 {
            return "两段一致 · 注意这是全样本口径，非前瞻验证"
        }
        return "两段矛盾 · 无法判断，默认按持有处理"
    }

    // 方案说明：把结论写成一句人话
    static func adaptiveAdvice(_ p: [Double]) -> String {
        if p.count < 15 { return "数据不足" }
        let mode = p[0]
        let isT = p[2]; let isB = p[3]
        let oosT = p[4]; let oosB = p[5]
        let rev = p[8]
        let isD = p[9]; let oosD = p[10]
        let lowVol = p[14] > 0.5

        // 低波动标的：夏普不可靠，改谈回撤
        if lowVol {
            if mode > 0.5 {
                return String(format: "此标的波动极低，夏普不具参考性。两段均显示择时能缩小最大回撤——若在意回撤可择时，但收益空间本就有限。")
            }
            if mode < 0.5 {
                return "此标的波动极低，夏普不具参考性。两段均显示择时无法改善回撤，波动空间不足以覆盖交易成本，建议持有。"
            }
            return "此标的波动极低，两段回撤结论矛盾，无法判断，默认按持有处理。"
        }

        if mode > 0.5 {
            return String(format: "前段夏普改善 %@，后段 %@——两段一致。收益上前段择时 %.1f%% vs 持有 %.1f%%，"
                + "后段 %.1f%% vs %.1f%%。注意：改善的是风险调整后的表现，不等于多赚钱。",
                fmt3(isD), fmt3(oosD), isT, isB, oosT, oosB)
        }
        if mode < 0.5 {
            if rev > 0.5 {
                return String(format: "两段夏普改善均为负（前段 %@，后段 %@）。且此标的出现过『前涨后跌』反转——"
                    + "这类标的历史规律最容易在趋势切换时失效，不宜据此频繁进出。",
                    fmt3(isD), fmt3(oosD))
            }
            return String(format: "前段夏普改善 %@，后段 %@——两段一致为负。收益上择时 %.1f%% vs 持有 %.1f%%，"
                + "少赚的部分没能换来足够的波动下降，建议少动。",
                fmt3(isD), fmt3(oosD), isT, isB)
        }
        return String(format: "前段夏普改善 %@，后段 %@——两段结论矛盾，无法判断此标的是否适合择时，默认按持有处理。",
                      fmt3(isD), fmt3(oosD))
    }

    static func fmt3(_ v: Double) -> String { return String(format: "%+.3f", v) }

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

// MARK: - 进阶分析引擎（方法来自公开研究：Bailey/López de Prado、CPCV、成本敏感性、HRP）
struct HLAdv {

    // ===== 1. A股不可成交判定 =====
    // 返回 1=一字涨停（买不进）  -1=一字跌停（卖不出）  0=正常
    static func limitState(_ h: [Double], _ l: [Double], _ c: [Double],
                           _ i: Int, _ limit: Double) -> Int {
        if i <= 0 || i >= c.count { return 0 }
        let pc = c[i - 1]
        if pc <= 0 { return 0 }
        if c[i] >= pc * (1.0 + limit) * 0.998 { return 1 }
        if c[i] <= pc * (1.0 - limit) * 1.002 { return -1 }
        return 0
    }

    // 不可成交日统计 [触及涨停, 触及跌停, 停牌, 总天数, 一字板]
    static func blockedDays(_ h: [Double], _ l: [Double], _ c: [Double],
                            _ vol: [Double], _ limit: Double) -> [Double] {
        let n = c.count
        if n == 0 { return [0, 0, 0, 0, 0] }
        var up = 0.0
        var dn = 0.0
        var halt = 0.0
        var one = 0.0
        var i = 1
        while i < n {
            let st = limitState(h, l, c, i, limit)
            if st == 1 { up = up + 1 }
            if st == -1 { dn = dn + 1 }
            if vol.count == n && vol[i] <= 0 { halt = halt + 1 }
            if i < h.count && i < l.count && h[i] - l[i] <= 1e-9 { one = one + 1 }
            i = i + 1
        }
        return [up, dn, halt, Double(n), one]
    }

    // ===== 2. 净值曲线（次日开盘成交 + 涨跌停/停牌约束 + 成本）=====
    // kind: 0=一直持有  1=MACD改良  2=红绿灯
    static func navSeries(_ o: [Double], _ h: [Double], _ l: [Double], _ c: [Double],
                          _ vol: [Double], _ kind: Int, _ p1: Int, _ p2: Int,
                          _ costBps: Double, _ limit: Double, _ respectLimit: Bool,
                          _ from: Int, _ to: Int) -> [Double] {
        let n = c.count
        let warm = 60
        if n < warm + 30 { return [] }
        if o.count != n || h.count != n || l.count != n { return [] }
        var hi = to
        if hi <= 0 || hi > n { hi = n }
        var lo = from
        if lo < warm { lo = warm }
        if lo >= hi { return [] }
        var nav: [Double] = []
        var equity = 1.0
        var pos = 0.0
        var stop = 0.0
        let cost = costBps / 10000.0
        let ms = HLCore.macdSeries(c)
        var i = warm
        while i < hi {
            let sig = i - 1
            var target = pos
            if kind == 0 {
                target = 1.0
            } else if kind == 1 {
                if let m = ms {
                    let buy = (m.bar[sig] > 0 && m.dif[sig] > 0)
                    target = buy ? 1.0 : 0.0
                }
            } else {
                let a = HLCore.maAt(c, p1, sig)
                let b = HLCore.maAt(c, p2, sig)
                if pos > 0 && stop > 0 && c[sig] < stop {
                    target = 0.0
                } else if a != nil && b != nil {
                    let mv = a!
                    let sv = b!
                    if pos <= 0 && c[sig] > mv && mv > sv { target = 1.0 }
                    else if pos > 0 && c[sig] < mv { target = 0.0 }
                }
            }
            var canTrade = true
            if respectLimit {
                let st = limitState(h, l, c, i, limit)
                if target > pos && st == 1 { canTrade = false }
                if target < pos && st == -1 { canTrade = false }
                if vol.count == n && vol[i] <= 0 { canTrade = false }
            }
            if canTrade && target != pos {
                if target > pos {
                    pos = 1.0
                    equity = equity * (1.0 - cost)
                    let av = HLCore.atrAt(h, l, c, 14, sig)
                    var sd = 0.0
                    if av != nil { sd = av! }
                    stop = o[i] - 2.0 * sd
                } else {
                    pos = 0.0
                    equity = equity * (1.0 - cost)
                }
            }
            if i + 1 < n {
                let px0 = o[i]
                let px1 = o[i + 1]
                if px0 > 0 {
                    let r = px1 / px0 - 1.0
                    equity = equity * (1.0 + pos * r)
                }
                if i >= lo { nav.append(equity) }
            }
            i = i + 1
        }
        return nav
    }

    static func navAll(_ o: [Double], _ h: [Double], _ l: [Double], _ c: [Double],
                       _ vol: [Double], _ kind: Int, _ p1: Int, _ p2: Int,
                       _ costBps: Double, _ limit: Double) -> [Double] {
        return navSeries(o, h, l, c, vol, kind, p1, p2, costBps, limit, true, -1, -1)
    }

    // ===== 3. 每笔交易收益（用于置换检验）=====
    static func tradeRets(_ o: [Double], _ h: [Double], _ l: [Double], _ c: [Double],
                          _ vol: [Double], _ kind: Int, _ p1: Int, _ p2: Int,
                          _ costBps: Double, _ limit: Double) -> [Double] {
        let n = c.count
        let warm = 60
        if n < warm + 30 { return [] }
        if o.count != n || h.count != n || l.count != n { return [] }
        var out: [Double] = []
        var pos = 0.0
        var stop = 0.0
        var entry = 0.0
        let cost = costBps / 10000.0
        let ms = HLCore.macdSeries(c)
        var i = warm
        while i < n {
            let sig = i - 1
            var target = pos
            if kind == 0 {
                target = 1.0
            } else if kind == 1 {
                if let m = ms {
                    let buy = (m.bar[sig] > 0 && m.dif[sig] > 0)
                    target = buy ? 1.0 : 0.0
                }
            } else {
                let a = HLCore.maAt(c, p1, sig)
                let b = HLCore.maAt(c, p2, sig)
                if pos > 0 && stop > 0 && c[sig] < stop {
                    target = 0.0
                } else if a != nil && b != nil {
                    let mv = a!
                    let sv = b!
                    if pos <= 0 && c[sig] > mv && mv > sv { target = 1.0 }
                    else if pos > 0 && c[sig] < mv { target = 0.0 }
                }
            }
            var canTrade = true
            let st = limitState(h, l, c, i, limit)
            if target > pos && st == 1 { canTrade = false }
            if target < pos && st == -1 { canTrade = false }
            if vol.count == n && vol[i] <= 0 { canTrade = false }
            if canTrade && target != pos {
                if target > pos {
                    pos = 1.0
                    entry = o[i] * (1.0 + cost)
                    let av = HLCore.atrAt(h, l, c, 14, sig)
                    var sd = 0.0
                    if av != nil { sd = av! }
                    stop = o[i] - 2.0 * sd
                } else {
                    let exitP = o[i] * (1.0 - cost)
                    if entry > 0 { out.append(exitP / entry - 1.0) }
                    pos = 0.0
                    entry = 0.0
                }
            }
            i = i + 1
        }
        return out
    }

    // ===== 4. 成本敏感性（5 / 15 / 30 bps）=====
    static func costSensitivity(_ o: [Double], _ h: [Double], _ l: [Double], _ c: [Double],
                                 _ vol: [Double], _ kind: Int, _ p1: Int, _ p2: Int,
                                 _ limit: Double) -> [Double] {
        var out: [Double] = []
        let bps: [Double] = [5.0, 15.0, 30.0]
        var i = 0
        while i < bps.count {
            let nav = navAll(o, h, l, c, vol, kind, p1, p2, bps[i], limit)
            if nav.count < 20 {
                out.append(0.0)
            } else {
                let last = nav[nav.count - 1]
                out.append((last - 1.0) * 100.0)
            }
            i = i + 1
        }
        return out
    }

    // ===== 5. 滚动样本外一致性（Walk-Forward，固定参数）=====
    // 返回 [有效折数, OOS中位夏普, OOS最差, OOS最好, 为正折占比%, 全样本夏普, WFE]
    static func walkForward(_ o: [Double], _ h: [Double], _ l: [Double], _ c: [Double],
                             _ vol: [Double], _ kind: Int, _ p1: Int, _ p2: Int,
                             _ costBps: Double, _ limit: Double, _ folds: Int) -> [Double] {
        let n = c.count
        if n < 300 { return [0, 0, 0, 0, 0, 0, 0] }
        var k = folds
        if k < 4 { k = 4 }
        if k > 10 { k = 10 }
        let size = n / k
        if size < 60 { return [0, 0, 0, 0, 0, 0, 0] }
        var arr: [Double] = []
        var f = 1
        while f < k {
            let from = f * size
            var to = (f + 1) * size
            if f == k - 1 { to = n }
            if to - from >= 60 {
                let nav = navSeries(o, h, l, c, vol, kind, p1, p2, costBps, limit, true, from, to)
                if nav.count >= 30 {
                    let r = HLCore.navToRets(nav)
                    let st = HLCore.retStats(r)
                    arr.append(st[0])
                }
            }
            f = f + 1
        }
        let fullNav = navAll(o, h, l, c, vol, kind, p1, p2, costBps, limit)
        var isSr = 0.0
        if fullNav.count >= 30 {
            let r = HLCore.navToRets(fullNav)
            isSr = HLCore.retStats(r)[0]
        }
        if arr.count == 0 { return [0, 0, 0, 0, 0, isSr, 0] }
        let s = arr.sorted()
        let m = s.count
        var med = s[m / 2]
        if m % 2 == 0 { med = (s[m / 2 - 1] + s[m / 2]) * 0.5 }
        var posCnt = 0
        var i = 0
        while i < m {
            if s[i] > 0 { posCnt = posCnt + 1 }
            i = i + 1
        }
        var wfe = 0.0
        if isSr > 0.05 || isSr < -0.05 { wfe = med / isSr }
        return [Double(m), med, s[0], s[m - 1],
                Double(posCnt) / Double(m) * 100.0, isSr, wfe]
    }

    // ===== 6. 组合 Purged 交叉验证（CPCV）=====
    // 返回 [路径数, 中位夏普, 最差, 最好, 为正占比%, p25, p75]
    static func cpcv(_ rets: [Double], _ groups: Int, _ embargo: Int) -> [Double] {
        let n = rets.count
        var g = groups
        if g < 4 { g = 4 }
        if g > 10 { g = 10 }
        if n < g * 40 { return [0, 0, 0, 0, 0, 0, 0] }
        let size = n / g
        var emb = embargo
        if emb < 0 { emb = 0 }
        if emb > size / 3 { emb = size / 3 }
        var arr: [Double] = []
        var a = 0
        while a < g {
            var b = a + 1
            while b < g {
                var tr: [Double] = []
                var x = a * size + emb
                let e1 = (a + 1) * size - emb
                while x < e1 && x < n {
                    tr.append(rets[x])
                    x = x + 1
                }
                x = b * size + emb
                let e2 = (b + 1) * size - emb
                while x < e2 && x < n {
                    tr.append(rets[x])
                    x = x + 1
                }
                if tr.count >= 30 {
                    let st = HLCore.retStats(tr)
                    arr.append(st[0])
                }
                b = b + 1
            }
            a = a + 1
        }
        if arr.count == 0 { return [0, 0, 0, 0, 0, 0, 0] }
        let s = arr.sorted()
        let m = s.count
        var med = s[m / 2]
        if m % 2 == 0 { med = (s[m / 2 - 1] + s[m / 2]) * 0.5 }
        var posCnt = 0
        var i = 0
        while i < m {
            if s[i] > 0 { posCnt = posCnt + 1 }
            i = i + 1
        }
        var i25 = Int(Double(m) * 0.25)
        var i75 = Int(Double(m) * 0.75)
        if i25 < 0 { i25 = 0 }
        if i75 > m - 1 { i75 = m - 1 }
        return [Double(m), med, s[0], s[m - 1],
                Double(posCnt) / Double(m) * 100.0, s[i25], s[i75]]
    }

    // ===== 7. 蒙特卡洛置换检验 =====
    // 统计量 = 交易序列的最大回撤（该量与顺序有关；收益求和在打乱后不变，不能用）
    // 返回 [实际序列最大回撤%, p值, 模拟次数, 交易笔数]
    static func seqMDD(_ rs: [Double]) -> Double {
        var eq = 1.0
        var peak = 1.0
        var mdd = 0.0
        var i = 0
        while i < rs.count {
            eq = eq * (1.0 + rs[i])
            if eq > peak { peak = eq }
            let d = (eq - peak) / peak
            if d < mdd { mdd = d }
            i = i + 1
        }
        return mdd
    }

    static func permutationTest(_ tradeRets: [Double], _ sims: Int, _ seed0: UInt64) -> [Double] {
        let m = tradeRets.count
        if m < 8 { return [0, 1, 0, Double(m)] }
        let actual = seqMDD(tradeRets)
        var seed = seed0
        var ge = 0
        var s = 0
        while s < sims {
            var arr = tradeRets
            var j = m - 1
            while j > 0 {
                let u = HLCore.lcg(&seed)
                var q = Int(u * Double(j + 1))
                if q > j { q = j }
                if q < 0 { q = 0 }
                let t = arr[j]
                arr[j] = arr[q]
                arr[q] = t
                j = j - 1
            }
            if seqMDD(arr) >= actual { ge = ge + 1 }
            s = s + 1
        }
        return [actual * 100.0, Double(ge) / Double(sims), Double(sims), Double(m)]
    }

    // ===== 8. 基准相对指标 =====
    // 返回 [年化Alpha%, Beta, 年化跟踪误差%, 信息比率, R²%, 上行捕获%, 下行捕获%]
    static func benchMetrics(_ p: [Double], _ b: [Double], _ rfAnn: Double) -> [Double] {
        let n0 = p.count < b.count ? p.count : b.count
        if n0 < 30 { return [0, 0, 0, 0, 0, 0, 0] }
        let pp = Array(p.suffix(n0))
        let bb = Array(b.suffix(n0))
        var mp = 0.0
        var mb = 0.0
        var i = 0
        while i < n0 {
            mp = mp + pp[i]
            mb = mb + bb[i]
            i = i + 1
        }
        mp = mp / Double(n0)
        mb = mb / Double(n0)
        var vp = 0.0
        var vb = 0.0
        var cov = 0.0
        i = 0
        while i < n0 {
            let dp = pp[i] - mp
            let db = bb[i] - mb
            vp = vp + dp * dp
            vb = vb + db * db
            cov = cov + dp * db
            i = i + 1
        }
        vp = vp / Double(n0 - 1)
        vb = vb / Double(n0 - 1)
        cov = cov / Double(n0 - 1)
        var beta = 0.0
        if vb > 1e-12 { beta = cov / vb }
        let rfd = rfAnn / 100.0 / 252.0
        let alphaD = mp - (rfd + beta * (mb - rfd))
        let alphaAnn = alphaD * 252.0 * 100.0
        var ma = 0.0
        i = 0
        while i < n0 {
            ma = ma + (pp[i] - bb[i])
            i = i + 1
        }
        ma = ma / Double(n0)
        var va = 0.0
        i = 0
        while i < n0 {
            let d = (pp[i] - bb[i]) - ma
            va = va + d * d
            i = i + 1
        }
        va = va / Double(n0 - 1)
        let te = sqrt(max(0.0, va)) * sqrt(252.0) * 100.0
        let teRaw = sqrt(max(0.0, va))
        var ir = 0.0
        if teRaw > 1e-12 { ir = (ma / teRaw) * sqrt(252.0) }
        var r2 = 0.0
        if vp > 1e-12 && vb > 1e-12 {
            let cr = cov / (sqrt(vp) * sqrt(vb))
            r2 = cr * cr
        }
        var upP = 0.0
        var upB = 0.0
        var dnP = 0.0
        var dnB = 0.0
        i = 0
        while i < n0 {
            if bb[i] > 0 {
                upP = upP + pp[i]
                upB = upB + bb[i]
            }
            if bb[i] < 0 {
                dnP = dnP + pp[i]
                dnB = dnB + bb[i]
            }
            i = i + 1
        }
        var upCap = 0.0
        var dnCap = 0.0
        if abs(upB) > 1e-12 { upCap = upP / upB * 100.0 }
        if abs(dnB) > 1e-12 { dnCap = dnP / dnB * 100.0 }
        return [alphaAnn, beta, te, ir, r2 * 100.0, upCap, dnCap]
    }

    // ===== 9. 相关系数矩阵 =====
    static func corrMatrix(_ cols: [[Double]]) -> [[Double]] {
        let m = cols.count
        if m == 0 { return [] }
        var out = [[Double]](repeating: [Double](repeating: 0.0, count: m), count: m)
        var i = 0
        while i < m {
            out[i][i] = 1.0
            var j = i + 1
            while j < m {
                let cv = HLCore.hlCorr(cols[i], cols[j])
                out[i][j] = cv
                out[j][i] = cv
                j = j + 1
            }
            i = i + 1
        }
        return out
    }

    // ===== 10. 层次风险平价（HRP）=====
    static func hrpWeights(_ cols: [[Double]]) -> [Double] {
        let m = cols.count
        if m == 0 { return [] }
        if m == 1 { return [1.0] }
        let corr = corrMatrix(cols)
        var vars: [Double] = []
        var i = 0
        while i < m {
            let r = HLCore.rets(cols[i])
            let v = HLCore.stdev(r)
            vars.append(v * v)
            i = i + 1
        }
        var dist = [[Double]](repeating: [Double](repeating: 0.0, count: m), count: m)
        i = 0
        while i < m {
            var j = 0
            while j < m {
                let d = sqrt(max(0.0, 0.5 * (1.0 - corr[i][j])))
                dist[i][j] = d
                j = j + 1
            }
            i = i + 1
        }
        var bestA = 0
        var bestB = 1
        var bd = 1e18
        i = 0
        while i < m {
            var j = i + 1
            while j < m {
                if dist[i][j] < bd {
                    bd = dist[i][j]
                    bestA = i
                    bestB = j
                }
                j = j + 1
            }
            i = i + 1
        }
        var used = [Bool](repeating: false, count: m)
        var order: [Int] = [bestA, bestB]
        used[bestA] = true
        used[bestB] = true
        while order.count < m {
            var pick = -1
            var pd = 1e18
            var putLeft = true
            i = 0
            while i < m {
                if !used[i] {
                    let dl = dist[i][order[0]]
                    let dr = dist[i][order[order.count - 1]]
                    if dl < pd {
                        pd = dl
                        pick = i
                        putLeft = true
                    }
                    if dr < pd {
                        pd = dr
                        pick = i
                        putLeft = false
                    }
                }
                i = i + 1
            }
            if pick < 0 { break }
            if putLeft { order.insert(pick, at: 0) } else { order.append(pick) }
            used[pick] = true
        }
        var w = [Double](repeating: 0.0, count: m)
        hrpAlloc(order, vars, corr, 0, order.count, 1.0, &w)
        return w
    }

    private static func hrpAlloc(_ order: [Int], _ vars: [Double], _ corr: [[Double]],
                                  _ from: Int, _ to: Int, _ cap: Double,
                                  _ out: inout [Double]) {
        if to - from <= 0 { return }
        if to - from == 1 {
            out[order[from]] = cap
            return
        }
        let mid = from + (to - from) / 2
        let v1 = hrpClusterVar(order, vars, corr, from, mid)
        let v2 = hrpClusterVar(order, vars, corr, mid, to)
        let s = v1 + v2
        if s <= 1e-18 {
            hrpAlloc(order, vars, corr, from, mid, cap * 0.5, &out)
            hrpAlloc(order, vars, corr, mid, to, cap * 0.5, &out)
            return
        }
        let a = v2 / s
        hrpAlloc(order, vars, corr, from, mid, cap * a, &out)
        hrpAlloc(order, vars, corr, mid, to, cap * (1.0 - a), &out)
    }

    private static func hrpClusterVar(_ order: [Int], _ vars: [Double], _ corr: [[Double]],
                                       _ from: Int, _ to: Int) -> Double {
        let k = to - from
        if k <= 0 { return 0 }
        var s = 0.0
        var i = from
        while i < to {
            var j = from
            while j < to {
                let a = order[i]
                let b = order[j]
                s = s + corr[a][b] * sqrt(vars[a]) * sqrt(vars[b])
                j = j + 1
            }
            i = i + 1
        }
        return s / Double(k * k)
    }

    // ===== 11. 集中度 [HHI, 最大权重%, 有效标的数量] =====
    static func concentration(_ w: [Double]) -> [Double] {
        let m = w.count
        if m == 0 { return [0, 0, 0] }
        var hhi = 0.0
        var mx = 0.0
        var i = 0
        while i < m {
            hhi = hhi + w[i] * w[i]
            if w[i] > mx { mx = w[i] }
            i = i + 1
        }
        var en = 0.0
        if hhi > 1e-12 { en = 1.0 / hhi }
        return [hhi, mx * 100.0, en]
    }

    // ===== 12. 相关性压力测试（相关系数统一升至 rho）=====
    static func stressVol(_ w: [Double], _ vols: [Double], _ rho: Double) -> Double {
        let m = w.count < vols.count ? w.count : vols.count
        if m == 0 { return 0 }
        var s2 = 0.0
        var i = 0
        while i < m {
            var j = 0
            while j < m {
                var r = rho
                if i == j { r = 1.0 }
                s2 = s2 + w[i] * w[j] * vols[i] * vols[j] * r
                j = j + 1
            }
            i = i + 1
        }
        return sqrt(max(0.0, s2)) * 100.0
    }

    // ===== 13. 仓位方案对比 =====
    // 返回 [固定分数%, 波动率目标%, 四分之一凯利%, 上限%]
    static func sizingModes(_ winRate: Double, _ pf: Double, _ annVolPct: Double,
                            _ stopPct: Double, _ capPct: Double) -> [Double] {
        var fixed = capPct
        if stopPct > 0.01 { fixed = 1.0 / stopPct * 100.0 }
        var vt = capPct
        if annVolPct > 0.01 { vt = 15.0 / annVolPct * 100.0 }
        var kf = 0.0
        if pf > 0.01 {
            let q = 1.0 - winRate
            kf = (pf * winRate - q) / pf
        }
        var a = fixed
        var b = vt
        var c = kf * 0.25 * 100.0
        if a > capPct { a = capPct }
        if b > capPct { b = capPct }
        if c > capPct { c = capPct }
        if a < 0 { a = 0 }
        if b < 0 { b = 0 }
        if c < 0 { c = 0 }
        return [a, b, c, capPct]
    }

    // ===== 14. 市场状态（过滤器，不是预测器）=====
    // 返回 [波动状态(1低/2高), ER, 状态码, 20日年化波动%, 波动中位数%]
    static func regimeOf(_ c: [Double]) -> [Double] {
        let n = c.count
        if n < 160 { return [0, 0, -1, 0, 0] }
        let r = HLCore.rets(c)
        var v20 = 0.0
        if let v = HLCore.volCone(r, 20) { v20 = v }
        var arr: [Double] = []
        var i = 252
        while i <= n - 20 {
            var s = 0.0
            var j = i
            while j < i + 20 {
                s = s + r[j]
                j = j + 1
            }
            let mm = s / 20.0
            var vv = 0.0
            j = i
            while j < i + 20 {
                vv = vv + (r[j] - mm) * (r[j] - mm)
                j = j + 1
            }
            vv = vv / 19.0
            arr.append(sqrt(vv) * sqrt(252.0))
            i = i + 5
        }
        var med = v20
        if arr.count > 3 {
            let s2 = arr.sorted()
            let m2 = s2.count
            med = s2[m2 / 2]
            if m2 % 2 == 0 { med = (s2[m2 / 2 - 1] + s2[m2 / 2]) * 0.5 }
        }
        var er = 0.0
        if let e = HLCore.erAt(c, n - 1, 60) { er = e }
        var vs = 1.0
        if v20 > med { vs = 2.0 }
        var code = 1.0
        if er >= 0.3 { code = 0.0 }
        if vs > 1.5 { code = code + 2.0 }
        return [vs, er, code, v20 * 100.0, med * 100.0]
    }

    static func regimeText(_ code: Double) -> String {
        if code < 0 { return "数据不足" }
        if code < 0.5 { return "低波动 · 有趋势" }
        if code < 1.5 { return "低波动 · 震荡" }
        if code < 2.5 { return "高波动 · 有趋势" }
        return "高波动 · 震荡"
    }

    static func regimeAdvice(_ code: Double) -> String {
        if code < 0 { return "样本不足，暂不判断" }
        if code < 0.5 { return "趋势类信号相对适配" }
        if code < 1.5 { return "均值回归相对适配，追突破易反复被打脸" }
        if code < 2.5 { return "波动放大，趋势可能加速，仓位宜下调" }
        return "最难做的状态：波动大且无方向，假突破最多"
    }

    // ===== 15. 稳健度分级（依据 WFE 与 CPCV 为正占比）=====
    // 返回 0=脆弱 1=一般 2=较稳
    static func robustGrade(_ wfe: Double, _ cpcvPos: Double) -> Int {
        if wfe >= 0.50 && cpcvPos >= 70 { return 2 }
        if wfe >= 0.30 && cpcvPos >= 50 { return 1 }
        return 0
    }

    static func robustGradeText(_ g: Int) -> String {
        if g == 2 { return "较稳健" }
        if g == 1 { return "一般" }
        return "脆弱"
    }

    // ===== 16. 分时逐笔资金流 =====
    // 单笔成交额分档：超大单 >=100万，大单 20万~100万，中单 4万~20万，小单 <4万
    static func tickFlow(_ ticks: [HLTick]) -> HLFlowStat {
        var st = HLFlowStat()
        st.count = ticks.count
        var i = 0
        while i < ticks.count {
            let t = ticks[i]
            let a = t.amt
            let d = t.isBuy ? a : -a
            if t.isBuy { st.buyAmt += a } else { st.sellAmt += a }
            if a >= 1000000.0 {
                st.xlNet += d
                st.bigCount += 1
            } else if a >= 200000.0 {
                st.lgNet += d
            } else if a >= 40000.0 {
                st.mdNet += d
            } else {
                st.smNet += d
            }
            i += 1
        }
        st.netAmt = st.buyAmt - st.sellAmt
        let tot = st.buyAmt + st.sellAmt
        if tot > 0 { st.buyRatio = st.buyAmt / tot * 100.0 }
        return st
    }

    // 真实 VWAP：成交额 / 成交量（股），与交易所均价的算法一致
    static func tickVwap(_ ticks: [HLTick]) -> Double {
        var tv = 0.0
        var ta = 0.0
        var i = 0
        while i < ticks.count {
            tv += ticks[i].vol
            ta += ticks[i].amt
            i += 1
        }
        if tv <= 0 { return 0 }
        return ta / tv / 100.0
    }

    // 时间 "HH:MM:SS" -> 当日分钟数
    static func tickMinute(_ t: String) -> Int {
        let p = t.components(separatedBy: ":")
        if p.count < 2 { return 0 }
        let h = Int(p[0]) ?? 0
        let mn = Int(p[1]) ?? 0
        return h * 60 + mn
    }

    // 尾盘切片：取 >=afterMin 分钟的成交
    static func tickTailFlow(_ ticks: [HLTick], _ afterMin: Int) -> HLFlowStat {
        var sub: [HLTick] = []
        var i = 0
        while i < ticks.count {
            if tickMinute(ticks[i].t) >= afterMin { sub.append(ticks[i]) }
            i += 1
        }
        return tickFlow(sub)
    }

    // 大单方向分歧：超大单与大单净额反向且都显著 -> 1（分歧），同向 -> 0
    static func flowDivergence(_ st: HLFlowStat, _ scale: Double) -> Int {
        if abs(st.xlNet) < scale || abs(st.lgNet) < scale { return 0 }
        if st.xlNet > 0 && st.lgNet < 0 { return 1 }
        if st.xlNet < 0 && st.lgNet > 0 { return 1 }
        return 0
    }

    static func flowVerdictText(_ st: HLFlowStat, _ vwap: Double, _ price: Double) -> String {
        if st.count == 0 { return "暂无逐笔数据（非交易时段或该标的不提供）" }
        if st.buyRatio > 55 {
            return "主动买占优（\(String(format: "%.0f", st.buyRatio))%），买方更急"
        }
        if st.buyRatio < 45 {
            return "主动卖占优（\(String(format: "%.0f", st.buyRatio))%），卖方更急"
        }
        if vwap > 0 && price > 0 && price > vwap {
            return "买卖均衡，现价高于均价，日内偏强"
        }
        if vwap > 0 && price > 0 && price < vwap {
            return "买卖均衡，现价低于均价，日内偏弱"
        }
        return "买卖力量均衡，无明显倾向"
    }
}

// ============================================================
// 统计修正引擎
//
// 依据（外部文献与开源社区方法）：
//   · Bailey & López de Prado (2014) 多重检验 / DSR
//   · Newey & West (1987) HAC 标准误，Bartlett 核
//   · López de Prado (2018) Purged CV / Embargo
//   · Moskowitz, Ooi & Pedersen (2012) 时序动量
//   · Qlib / alphalens 因子检验口径：IC、Rank IC、ICIR
//
// 本工具此前存在四类系统性偏差（均已实测量化）：
//   1. 重叠窗口使 t 被高估 —— 实测 2.9~4.3 倍。
//      「偏离MA60→未来60日」naive t=-5.97，NW 修正后 -1.39，
//      非重叠相位仅 -0.75；显著标的数 9 → 3 → 0。
//   2. 固定 bps 成本忽略波动率 —— 12 标的实测平均低估 2.93pp，
//      换手多的标的低估 10.4pp（黄金）、4.7pp（半导体）。
//   3. Pearson IC 受离群值影响 —— 纳指ETF 上 Pearson +0.072
//      与 Spearman -0.070 符号相反，差 0.142。
//   4. IS/OOS 朴素切分未 purge/embargo —— 标签窗口跨越边界。
//      净化后前后段超额相关由 +0.367 升至 +0.424。
// ============================================================

extension HLCore {

    // ---------- 1. Newey-West + 非重叠相位 ----------
    // x: 待检验序列（如逐日 IC 贡献）；h: 前瞻天数（决定重叠度）
    // 返回 [naiveT, nwT, nonOverlapT, lag, phases]
    static func hlNWTest(_ x: [Double], _ h: Int) -> [Double] {
        let n = x.count
        if n < 10 || h < 1 { return [0, 0, 0, 0, 0] }
        var s = 0.0
        for v in x { s += v }
        let mu = s / Double(n)
        var d = [Double]()
        d.reserveCapacity(n)
        for v in x { d.append(v - mu) }
        var g0 = 0.0
        for v in d { g0 += v * v }
        g0 /= Double(n)
        if g0 <= 0 { return [0, 0, 0, 0, 0] }

        // Bartlett 核，滞后阶 L = min(h-1, n-1)
        let L = min(h - 1, n - 1)
        var vNW = g0
        if L > 0 {
            var j = 1
            while j <= L {
                let w = 1.0 - Double(j) / Double(L + 1)
                var cj = 0.0
                var i = 0
                while i + j < n { cj += d[i] * d[i + j]; i += 1 }
                cj /= Double(n)
                vNW += 2.0 * w * cj
                j += 1
            }
        }
        if vNW <= 0 { vNW = g0 }          // 数值保护：不产生负方差
        let seN = sqrt(g0 / Double(n))
        let seW = sqrt(vNW / Double(n))
        if seN <= 0 || seW <= 0 { return [0, 0, 0, 0, 0] }

        // 非重叠相位：切成 h 个交错相位，各算普通 t 后取平均
        var ts = [Double]()
        var p = 0
        while p < h {
            var ph = [Double]()
            var k = p
            while k < n { ph.append(x[k]); k += h }
            if ph.count >= 2 {
                var ps = 0.0
                for v in ph { ps += v }
                let pm = ps / Double(ph.count)
                var pv = 0.0
                for v in ph { pv += (v - pm) * (v - pm) }
                pv /= Double(ph.count - 1)
                if pv > 0 {
                    let pse = sqrt(pv / Double(ph.count))
                    ts.append(pm / pse)
                }
            }
            p += 1
        }
        var noT = 0.0
        if !ts.isEmpty {
            for v in ts { noT += v }
            noT /= Double(ts.count)
        }
        return [mu / seN, mu / seW, noT, Double(L), Double(ts.count)]
    }

    /// 取三种口径中最保守（绝对值最小）的 t —— 文献建议：两者分歧时信较小的
    static func hlConservativeT(_ r: [Double]) -> Double {
        if r.count < 3 { return 0 }
        let a = abs(r[0]); let b = abs(r[1]); let c = abs(r[2])
        let m = min(a, min(b, c))
        if m == c { return r[2] }
        if m == b { return r[1] }
        return r[0]
    }

    static func hlNWText(_ r: [Double]) -> String {
        if r.count < 3 { return "样本不足" }
        let nv = r[0]; let nw = r[1]; let no = r[2]
        let ct = hlConservativeT(r)
        let sig = abs(ct) > 2.0
        if abs(nv) > 2.0 && !sig {
            return String(format: "未修正 t=%+.2f 看似显著，修正后仅 %+.2f —— 属重叠窗口造成的假象",
                          nv, ct)
        }
        if sig {
            return String(format: "修正后 t=%+.2f，仍显著（未修正 %+.2f）", ct, nv)
        }
        return String(format: "修正后 t=%+.2f，不显著（未修正 %+.2f，高估 %.1f 倍）",
                      ct, nv, abs(nv) / max(0.01, abs(ct)))
    }

    // ---------- 2. 波动率调整交易成本 ----------
    // cost = base × (当期20日波动 / 全样本波动中位数)，限幅 [0.5, 2.5]
    static func hlVolCostAt(_ rets: [Double], _ i: Int,
                            _ base: Double, _ win: Int = 20) -> Double {
        let n = rets.count
        if n < win + 5 || i < win || i > n { return base }
        var cur = [Double]()
        var k = i - win
        while k < i && k < n { cur.append(rets[k]); k += 1 }
        if cur.count < 2 { return base }
        let sv = stdev(cur)
        if sv <= 0 { return base }

        var all = [Double]()
        var j = win
        while j <= i && j <= n {
            var w = [Double]()
            var m = j - win
            while m < j { w.append(rets[m]); m += 1 }
            let s2 = stdev(w)
            if s2 > 0 { all.append(s2) }
            j += 1
        }
        if all.count < 5 { return base }
        all.sort()
        let mid = all[all.count / 2]
        if mid <= 1e-12 { return base }
        var ratio = sv / mid
        if ratio < 0.5 { ratio = 0.5 }
        if ratio > 2.5 { ratio = 2.5 }
        return base * ratio
    }

    // ---------- 3. Rank IC (Spearman 秩相关) ----------
    static func hlRankIC(_ a: [Double], _ b: [Double]) -> Double {
        let n = min(a.count, b.count)
        if n < 5 { return 0 }
        let ra = hlRanks(Array(a[0..<n]))
        let rb = hlRanks(Array(b[0..<n]))
        var ma = 0.0; var mb = 0.0
        for v in ra { ma += v }
        for v in rb { mb += v }
        ma /= Double(n); mb /= Double(n)
        var num = 0.0; var da = 0.0; var db = 0.0
        var i = 0
        while i < n {
            num += (ra[i] - ma) * (rb[i] - mb)
            da += (ra[i] - ma) * (ra[i] - ma)
            db += (rb[i] - mb) * (rb[i] - mb)
            i += 1
        }
        if da <= 0 || db <= 0 { return 0 }
        return num / (sqrt(da) * sqrt(db))
    }

    /// 平均秩（并列取平均），供 Spearman 使用
    static func hlRanks(_ v: [Double]) -> [Double] {
        let n = v.count
        var r = [Double](repeating: 0, count: n)
        var idx = [Int]()
        idx.reserveCapacity(n)
        var i = 0
        while i < n { idx.append(i); i += 1 }
        idx.sort { v[$0] < v[$1] }
        i = 0
        while i < n {
            var j = i
            while j + 1 < n && v[idx[j + 1]] == v[idx[i]] { j += 1 }
            let avg = (Double(i) + Double(j)) / 2.0 + 1.0
            var k = i
            while k <= j { r[idx[k]] = avg; k += 1 }
            i = j + 1
        }
        return r
    }

    // ---------- 4. Purge + Embargo 切分 ----------
    // purge: 训练段去掉末尾 (h-1) 个样本 —— 其标签窗口伸入测试段
    // embargo: 测试段之后额外留白 —— 特征可能含测试期信息
    // 返回 [trainTo, testFrom, testTo]
    static func hlPurgedSplit(_ n: Int, _ h: Int,
                              _ embargoPct: Double = 0.01) -> [Int] {
        if n < 100 { return [0, 0, n] }
        let emb = max(1, Int(Double(n) * embargoPct))
        let tf = Int(Double(n) * 0.6)
        let tr = max(1, tf - (h - 1))
        let tt = max(tr + 2, n - emb)
        return [tr, tf, tt]
    }

    // ---------- 5. 综合因子检验 ----------
    // f: 当期因子值序列；y: 对应前瞻收益序列；h: 前瞻天数
    // 返回 [pearsonIC, rankIC, icir, naiveT, nwT, nonOverlapT, consT, n]
    static func hlFactorTest(_ f: [Double], _ y: [Double], _ h: Int) -> [Double] {
        let n = min(f.count, y.count)
        if n < 60 { return [0, 0, 0, 0, 0, 0, 0, 0] }
        let ff = Array(f[0..<n]); let yy = Array(y[0..<n])
        let pe = hlCorr(ff, yy)
        let rk = hlRankIC(ff, yy)
        var mf = 0.0; var my = 0.0
        for v in ff { mf += v }
        for v in yy { my += v }
        mf /= Double(n); my /= Double(n)
        var sf = 0.0; var sy = 0.0
        var i = 0
        while i < n {
            sf += (ff[i] - mf) * (ff[i] - mf)
            sy += (yy[i] - my) * (yy[i] - my)
            i += 1
        }
        sf = sqrt(sf / Double(n)); sy = sqrt(sy / Double(n))
        if sf <= 0 || sy <= 0 { return [pe, rk, 0, 0, 0, 0, 0, Double(n)] }
        // 逐点 IC 贡献：z(f) × (y - mean(y))，其均值正比于 IC
        var contrib = [Double]()
        contrib.reserveCapacity(n)
        i = 0
        while i < n {
            contrib.append(((ff[i] - mf) / sf) * (yy[i] - my))
            i += 1
        }
        let t = hlNWTest(contrib, h)
        // IC 序列（滚动 60 窗）算 ICIR
        var ics = [Double]()
        let w = 60
        if n > w + 10 {
            var k = w
            while k < n {
                let a = Array(ff[(k - w)..<k])
                let b = Array(yy[(k - w)..<k])
                ics.append(hlCorr(a, b))
                k += 1
            }
        }
        var icir = 0.0
        if ics.count > 5 {
            var m = 0.0
            for v in ics { m += v }
            m /= Double(ics.count)
            let sd = stdev(ics)
            if sd > 1e-12 { icir = m / sd }
        }
        return [pe, rk, icir, t[0], t[1], t[2], hlConservativeT(t), Double(n)]
    }

    static func hlFactorVerdict(_ r: [Double]) -> String {
        if r.count < 8 || r[7] < 60 { return "样本不足，无法检验" }
        let pe = r[0]; let rk = r[1]; let ct = r[6]
        if pe * rk < 0 && abs(pe - rk) > 0.05 {
            return String(format: "Pearson %+.3f 与 Rank IC %+.3f 符号相反 —— 结论由少数离群值驱动，以 Rank IC 为准",
                          pe, rk)
        }
        if abs(ct) < 2.0 {
            return String(format: "修正后 t=%+.2f（<2），未通过显著性检验；IC %+.3f / Rank IC %+.3f",
                          ct, pe, rk)
        }
        return String(format: "修正后 t=%+.2f 显著；IC %+.3f / Rank IC %+.3f / ICIR %+.2f",
                      ct, pe, rk, r[2])
    }

    // ---------- 6. 波动率调整成本下的回测 ----------
    // 与界面红绿灯同规则(kind=1)，成本随当期波动率浮动。
    // 返回 [固定成本收益%, 波动调整收益%, 成本拖累pp, 换手次数]
    static func hlCostCompare(_ o: [Double], _ c: [Double],
                              _ base: Double = 20.0) -> [Double] {
        let n = min(o.count, c.count)
        if n < 120 { return [0, 0, 0, 0] }
        var rets = [Double]()
        rets.reserveCapacity(n)
        var i = 1
        while i < n { rets.append(c[i] / c[i - 1] - 1.0); i += 1 }

        func run(_ volMode: Bool) -> (nav: Double, trades: Int) {
            var nav = 1.0
            var pos = 0.0
            var tr = 0
            let warm = 60
            var i = warm + 1
            while i < n - 1 {
                let sig = hlLightPos(c, i - 1)
                let px = o[i]
                var cb = base
                if volMode {
                    let ri = min(i, rets.count - 1)
                    cb = hlVolCostAt(rets, ri, base)
                }
                if sig > 0.5 && pos <= 0.001 {
                    nav *= (1.0 - cb / 10000.0); pos = 1.0; tr += 1
                } else if sig <= 0.5 && pos > 0.001 {
                    nav *= (1.0 - cb / 10000.0); pos = 0.0; tr += 1
                }
                // 持仓收益从 o[i] 结算到 o[i+1]（防偷价）
                if pos > 0.001 && i + 1 < n { nav *= (o[i + 1] / px) }
                i += 1
            }
            return (nav, tr)
        }
        let a = run(false)
        let b = run(true)
        return [(a.nav - 1.0) * 100.0, (b.nav - 1.0) * 100.0,
                (b.nav - a.nav) * 100.0, Double(b.trades)]
    }

    /// 红绿灯仓位判定（与界面同规则）：1=持仓 0=空仓
    static func hlLightPos(_ c: [Double], _ i: Int) -> Double {
        if i < 60 || i >= c.count { return 0 }
        var m20 = 0.0; var m60 = 0.0
        var k = i + 1 - 20
        while k <= i { m20 += c[k]; k += 1 }
        k = i + 1 - 60
        while k <= i { m60 += c[k]; k += 1 }
        m20 /= 20.0; m60 /= 60.0
        if c[i] > m20 && m20 > m60 { return 1.0 }
        return 0.0
    }

    static func hlCostCompareText(_ r: [Double]) -> String {
        if r.count < 4 { return "样本不足" }
        let drag = r[2]
        let tr = Int(r[3])
        if drag < -5.0 {
            return String(format: "波动调整后收益降 %.1f 个百分点（%d 次换手）——此前结果明显高估",
                          abs(drag), tr)
        }
        if drag < -1.0 {
            return String(format: "波动调整后收益降 %.1f 个百分点（%d 次换手）——此前结果略有高估",
                          abs(drag), tr)
        }
        return String(format: "波动调整后收益降 %.1f 个百分点（%d 次换手）——成本影响有限",
                      abs(drag), tr)
    }
}

// MARK: - VIX / 波动率监测（真实数据源：新浪 znb_VIX 官方指数 + 已实现波动自算）

/// 已实现波动率（年化，百分数）。取最后 n 根收盘价的对数收益标准差。
/// 样本不足返回 0，调用方需自行判 0 为「无数据」。
static func realizedVolPct(_ c: [Double], _ n: Int) -> Double {
    if n < 2 || c.count < n + 2 { return 0 }
    let s = Array(c[(c.count - n - 1)...])
    return annVol(rets(s)) * 100.0
}

/// 滚动已实现波动率序列，用于计算历史分位。
/// 只从索引 n+2 开始（不足窗口的窗口会被算出 0，必须剔除，否则分位被拉低）。
static func rollingVolSeries(_ c: [Double], _ n: Int) -> [Double] {
    if n < 2 || c.count < n + 3 { return [] }
    var out: [Double] = []
    var i = n + 2
    while i <= c.count {
        let end = i - 1
        let s = Array(c[(i - n - 1)...end])
        out.append(annVol(rets(s)) * 100.0)
        i += 1
    }
    return out
}

/// 当前值在历史序列中的百分位（0~100）。序列为空返回 -1 表示无法计算。
static func volPercentile(_ hist: [Double], _ cur: Double) -> Double {
    if hist.isEmpty || cur <= 0 { return -1 }
    var below = 0
    for x in hist { if x < cur { below += 1 } }
    return Double(below) / Double(hist.count) * 100.0
}

/// VIX 分级：-1 无数据，0 极低，1 偏低，2 正常，3 偏高，4 警戒，5 恐慌
static func vixLevel(_ v: Double) -> Int {
    if v <= 0 { return -1 }
    if v < 12 { return 0 }
    if v < 15 { return 1 }
    if v < 20 { return 2 }
    if v < 25 { return 3 }
    if v < 30 { return 4 }
    return 5
}

static func vixLevelName(_ lv: Int) -> String {
    if lv == 0 { return "极低波动" }
    if lv == 1 { return "偏低" }
    if lv == 2 { return "正常" }
    if lv == 3 { return "偏高" }
    if lv == 4 { return "警戒" }
    if lv == 5 { return "恐慌" }
    return "无数据"
}

/// VIX 分级的行动含义。只描述风险环境，不预测涨跌。
static func vixAdvice(_ lv: Int) -> String {
    if lv == 0 { return "市场极度平静。历史上低 VIX 常伴随波动率回升，不宜因「没风险」而加杠杆。" }
    if lv == 1 { return "风险偏好较高。此环境下追涨容易在波动率回升时被套。" }
    if lv == 2 { return "正常区间。按既定纪律执行即可，无需因波动率改变仓位规则。" }
    if lv == 3 { return "市场开始定价不确定性。此时宜收紧止损、降低单笔仓位。" }
    if lv == 4 { return "风险显著上升。历史上此区间后波动往往继续放大，避免逆势加仓。" }
    if lv == 5 { return "恐慌区间。价格容易过度反应，纪律执行优先于判断方向。" }
    return "未取到 VIX 数据，不做环境判断。"
}

/// 波动率分位的状态名
static func volPctName(_ p: Double) -> String {
    if p < 0 { return "无法计算" }
    if p < 20 { return "历史低位" }
    if p < 40 { return "偏低" }
    if p < 60 { return "中位" }
    if p < 80 { return "偏高" }
    return "历史高位"
}

/// 综合环境判定：0 平静 1 正常 2 注意 3 警惕
/// 输入 (VIX分级, 纳指波动分位, 标普波动分位)
static func volRegime(_ lv: Int, _ pn: Double, _ ps: Double) -> Int {
    if lv < 0 && pn < 0 { return -1 }
    var s = 0
    if lv >= 4 { s += 2 } else if lv == 3 { s += 1 }
    if pn >= 80 { s += 2 } else if pn >= 60 { s += 1 }
    if ps >= 80 { s += 1 }
    if s >= 4 { return 3 }
    if s >= 2 { return 2 }
    if s >= 1 { return 1 }
    return 0
}

static func volRegimeName(_ r: Int) -> String {
    if r < 0 { return "数据不足" }
    if r == 0 { return "平静" }
    if r == 1 { return "正常" }
    if r == 2 { return "注意" }
    return "警惕"
}

static func volRegimeText(_ r: Int) -> String {
    if r < 0 { return "未取到足够的波动率数据，不做环境判断。" }
    if r == 0 { return "波动环境平静。维持既定纪律，不必因波动率调整仓位。" }
    if r == 1 { return "波动环境正常偏紧。可按计划执行，留意止损位。" }
    if r == 2 { return "波动率已进入偏高位区间。建议收紧止损、控制单笔仓位。" }
    return "波动率处于高位。此环境下价格易过度反应，避免逆势加仓与频繁进出。"
}


// ============================================================
// 状态画像引擎
//
// 用户思路：「它跌的时候各项参数是什么，涨的时候各项参数是什么，
//           参数都是会变的，跟涨和跌都会变。」
//
// 实测结论（12 标的 x 801 根 K 线，8400 个样本）：
//   1. 参数确实随状态迁移。偏离MA60 的效应量 d = 2.18（上涨态 +9.01%
//      vs 下跌态 -5.97%），两个分布几乎不重叠。
//   2. 但存在「状态盲」指标：MACD 柱 d = -0.01、量比 d = 0.04。
//      它们自己看不见市场在涨还是在跌，可后续含义在两态下差 2.21pp。
//      这是「红买绿卖」到处失灵的根源：用状态盲信号做依赖状态的判断。
//   3. 状态不可用于预测反转。下跌态后续 20 日超额 +0.77%、上涨态 -0.79%，
//      重叠样本 t = 6.18（极显著），但非重叠取样后 t = -0.41，效应消失。
//      该「反转规律」是滚动窗口自相关制造的幻觉。
//
// 因此本模块只做一件事：用状态去「解读」指标，不做「预测」。
// ============================================================

/// 单个指标在上涨态 / 下跌态下的画像
struct HLFeatStat {
    var name: String = ""
    var value: Double = 0      // 当前值
    var bucket: Int = 1        // 当前档位 1~4（按 20/40/60/80 分位切）
    var upMean: Double = 0     // 上涨态下的历史均值
    var dnMean: Double = 0     // 下跌态下的历史均值
    var effD: Double = 0       // 效应量 (upMean - dnMean) / pooledSD
    var fwdUp: Double = 0      // 同档位 + 上涨态 → 后续 20 日超额均值(%)
    var fwdDn: Double = 0      // 同档位 + 下跌态
    var fwdAll: Double = 0     // 同档位，不分状态
    var nUp: Int = 0
    var nDn: Int = 0
    var blind: Bool = false    // 状态盲：|effD| < 0.20
    var icUp: Double = 0       // 上涨态下 该指标值 vs 后续超额 的 IC
    var icDn: Double = 0       // 下跌态下 的 IC
    var kind: String = ""      // 构造类型：相对位置 / 标准化比值 / 动量 / 波动
    var flip: Bool = false     // IC 在两态下符号相反 → 同一数值含义翻转
}

/// 二维状态面板的单格（趋势 × 波动）
struct HLRegimeCell {
    var trend: Int = 0         // 0 跌  1 震荡  2 涨
    var volLev: Int = 0        // 0 低波  1 高波
    var n: Int = 0             // 横截面样本数
    var winRate: Double = 0    // 横截面：后续 20 日超额 > 0 的比例
    var fwdMean: Double = 0    // 横截面：后续 20 日超额均值 %
    var tsRet: Double = 0      // 时序回测：只在该象限持仓的累计收益 %
    var tsDays: Int = 0        // 时序回测实际持仓天数
    var tsTrades: Int = 0      // 时序回测进出场次数
}

/// 二维状态面板（趋势 × 波动 六象限）
struct HLRegime2D {
    var ok: Bool = false
    var curTrend: Int = 1
    var curVol: Int = 0
    var volSplit: Double = 0     // 波动中位数切分阈值（年化 %）
    var cells: [HLRegimeCell] = []
    var crossBest: Int = -1      // 横截面上涨率最高的格
    var tsBest: Int = -1         // 时序回测收益最高的格
    var conflict: Bool = false   // 两者不一致 → 高上涨率 ≠ 高收益
    var tsHold: Double = 0       // 「涨态就买」基准的时序收益 %
    var tsHoldN: Int = 0         // 有几个象限的时序收益跑赢该基准
}

/// 标的整体的状态画像
struct HLStateProfile {
    var ok: Bool = false
    var state: Int = 1         // 0 下跌态  1 震荡态  2 上涨态
    var r60: Double = 0        // 过去 60 日涨跌 %
    var days: Int = 0          // 当前状态已持续天数
    var fwdUpAll: Double = 0   // 上涨态 → 后续 20 日超额均值 %
    var fwdDnAll: Double = 0   // 下跌态 → 后续 20 日超额均值 %
    var tOverlap: Double = 0   // 重叠样本 Welch t（下跌 vs 上涨）
    var tNonOverlap: Double = 0// 非重叠取样 t
    var nSample: Int = 0
    var feats: [HLFeatStat] = []
}

extension HLCore {

    static let HL_FEAT_NAMES: [String] = [
        "RSI14", "偏离MA20%", "偏离MA60%", "20日波动%", "MACD柱/价%",
        "量比", "5日收益%", "20日收益%", "距60日高%", "距60日低%", "ATR%"
    ]

    /// 指标的构造类型。实测：相对位置类对状态极敏感，
    /// 标准化/比值类几乎状态盲（差分的差分会丢掉位置信息）。
    static let HL_FEAT_KIND: [String] = [
        "标准化比值", "相对位置", "相对位置", "波动", "标准化比值",
        "标准化比值", "动量", "动量", "相对位置", "相对位置", "波动"
    ]

    /// Pearson 相关系数。样本不足或分母为 0 返回 0。
    static func hlPear(_ a: [Double], _ b: [Double]) -> Double {
        let n = min(a.count, b.count)
        if n < 8 { return 0 }
        let ma = HLCore.mean(Array(a[0..<n]))
        let mb = HLCore.mean(Array(b[0..<n]))
        var sab = 0.0; var saa = 0.0; var sbb = 0.0
        var i = 0
        while i < n {
            let x = a[i] - ma; let y = b[i] - mb
            sab += x * y; saa += x * x; sbb += y * y
            i += 1
        }
        if saa <= 0 || sbb <= 0 { return 0 }
        return sab / sqrt(saa * sbb)
    }

    /// 第 i 根处的 MA(k)。窗口不足返回 nil。
    static func maAt(_ a: [Double], _ k: Int, _ i: Int) -> Double? {
        if k <= 0 || i + 1 < k || i >= a.count { return nil }
        var s = 0.0
        var j = i - k + 1
        while j <= i { s += a[j]; j += 1 }
        return s / Double(k)
    }

    /// Welch t（不假设等方差）。样本不足返回 0。
    static func welchT(_ a: [Double], _ b: [Double]) -> Double {
        if a.count < 3 || b.count < 3 { return 0 }
        let ma_ = HLCore.mean(a); let mb = HLCore.mean(b)
        let va = HLCore.stdev(a); let vb = HLCore.stdev(b)
        let se = sqrt(va * va / Double(a.count) + vb * vb / Double(b.count))
        if se <= 0 { return 0 }
        return (ma_ - mb) / se
    }

    /// 线性插值分位
    static func qpos(_ s: [Double], _ p: Double) -> Double {
        if s.isEmpty { return 0 }
        let pos = (Double(s.count) - 1) * p
        var lo = Int(pos)
        if lo < 0 { lo = 0 }
        if lo > s.count - 1 { lo = s.count - 1 }
        var hi = lo + 1
        if hi > s.count - 1 { hi = s.count - 1 }
        return s[lo] + (s[hi] - s[lo]) * (pos - Double(lo))
    }

    /// 第 i 根处的 11 维特征
    static func stateFeatsAt(_ c: [Double], _ h: [Double], _ l: [Double],
                             _ v: [Double], _ bar: [Double], _ i: Int) -> [Double] {
        let m20 = maAt(c, 20, i)
        let m60 = maAt(c, 60, i)
        var rr: [Double] = []
        var j = i - 19
        while j <= i {
            if j >= 1 && j < c.count { rr.append(c[j] / c[j - 1] - 1) }
            j += 1
        }
        var vs = 0.0
        var k2 = i - 19
        while k2 <= i { if k2 >= 0 && k2 < v.count { vs += v[k2] }; k2 += 1 }
        var mx = -1e18; var mn = 1e18
        var k3 = i - 59
        while k3 <= i {
            if k3 >= 0 && k3 < c.count {
                if c[k3] > mx { mx = c[k3] }
                if c[k3] < mn { mn = c[k3] }
            }
            k3 += 1
        }
        let rsi = rsiAt(c, 14, i) ?? 50.0
        let b = (i < bar.count) ? bar[i] : 0
        let vol = annVol(rr) * 100.0
        let vr = (vs > 0 && i < v.count) ? (v[i] / (vs / 20.0)) : 1.0
        let r5 = (i >= 5) ? (c[i] / c[i - 5] - 1) * 100 : 0
        let r20 = (i >= 20) ? (c[i] / c[i - 20] - 1) * 100 : 0
        let atrP = (atrAt(h, l, c, 14, i) ?? 0) / max(1e-9, c[i]) * 100
        return [rsi,
                m20 != nil ? (c[i] / m20! - 1) * 100 : 0,
                m60 != nil ? (c[i] / m60! - 1) * 100 : 0,
                vol,
                b / max(1e-9, c[i]) * 100,
                vr, r5, r20,
                (c[i] / mx - 1) * 100,
                (c[i] / mn - 1) * 100,
                atrP]
    }

    /// 状态画像主函数。样本不足返回 ok=false。
    static func stateProfile(_ c: [Double], _ h: [Double], _ l: [Double],
                             _ v: [Double]) -> HLStateProfile {
        var out = HLStateProfile()
        let n = c.count
        if n < 140 { return out }
        guard let ms = macdSeries(c) else { return out }
        let bar = ms.bar
        let i0 = 80
        let i1 = n - 21
        if i1 <= i0 { return out }

        var st: [Int] = []      // 0 下跌 1 震荡 2 上涨
        var fwd: [Double] = []
        var idx: [Int] = []
        var fv: [[Double]] = Array(repeating: [], count: HL_FEAT_NAMES.count)

        var i = i0
        while i <= i1 {
            let r60 = (c[i] / c[i - 60] - 1) * 100
            let s = r60 > 5 ? 2 : (r60 < -5 ? 0 : 1)
            let row = stateFeatsAt(c, h, l, v, bar, i)
            for f in 0..<HL_FEAT_NAMES.count { fv[f].append(row[f]) }
            st.append(s)
            fwd.append((c[i + 20] / c[i] - 1) * 100)
            idx.append(i)
            i += 1
        }
        let ns = st.count
        if ns < 120 { return out }

        let mfw = HLCore.mean(fwd)
        var adj: [Double] = []      // 标的内去均值后的后续超额
        for x in fwd { adj.append(x - mfw) }

        var au: [Double] = []; var ad: [Double] = []
        for k in 0..<ns {
            if st[k] == 2 { au.append(adj[k]) }
            else if st[k] == 0 { ad.append(adj[k]) }
        }
        let tOv = welchT(ad, au)

        // 非重叠取样：间隔 >= 20 天才取一个，避免滚动窗口自相关
        var nu: [Double] = []; var nd: [Double] = []
        var last = -9999
        for k in 0..<ns {
            if idx[k] - last >= 20 {
                last = idx[k]
                if st[k] == 2 { nu.append(adj[k]) }
                else if st[k] == 0 { nd.append(adj[k]) }
            }
        }
        let tNo = welchT(nd, nu)

        // 当前状态
        let curR60 = (c[n - 1] / c[n - 61] - 1) * 100
        let curS = curR60 > 5 ? 2 : (curR60 < -5 ? 0 : 1)
        var days = 0
        var jj = n - 1
        while jj >= 61 {
            let r = (c[jj] / c[jj - 60] - 1) * 100
            let s = r > 5 ? 2 : (r < -5 ? 0 : 1)
            if s != curS { break }
            days += 1
            jj -= 1
        }

        let curV = stateFeatsAt(c, h, l, v, bar, n - 1)
        var curB: [Int] = []
        var qs: [[Double]] = []
        for f in 0..<HL_FEAT_NAMES.count {
            let s = fv[f].sorted()
            var q: [Double] = []
            var b2 = 0
            while b2 < 4 { q.append(qpos(s, Double(b2 + 1) * 0.2)); b2 += 1 }
            qs.append(q)
            var bk = 0
            while bk < 4 && curV[f] > q[bk] { bk += 1 }
            curB.append(bk)
        }

        var feats: [HLFeatStat] = []
        for f in 0..<HL_FEAT_NAMES.count {
            var su: [Double] = []; var sd: [Double] = []
            for k in 0..<ns {
                if st[k] == 2 { su.append(fv[f][k]) }
                else if st[k] == 0 { sd.append(fv[f][k]) }
            }
            if su.isEmpty || sd.isEmpty { continue }
            let vu = HLCore.stdev(su); let vd = HLCore.stdev(sd)
            let pooled = sqrt((vu * vu + vd * vd) / 2.0)
            let d = pooled > 0 ? (HLCore.mean(su) - HLCore.mean(sd)) / pooled : 0
            var bu: [Double] = []; var bd: [Double] = []; var ba: [Double] = []
            for k in 0..<ns {
                var bk = 0
                while bk < 4 && fv[f][k] > qs[f][bk] { bk += 1 }
                if bk == curB[f] {
                    ba.append(adj[k])
                    if st[k] == 2 { bu.append(adj[k]) }
                    if st[k] == 0 { bd.append(adj[k]) }
                }
            }
            // 两态下的 IC：该指标值 vs 后续 20 日超额
            var iu: [Double] = []; var idn: [Double] = []
            var fu: [Double] = []; var fdn: [Double] = []
            for k in 0..<ns {
                if st[k] == 2 { iu.append(fv[f][k]); fu.append(adj[k]) }
                else if st[k] == 0 { idn.append(fv[f][k]); fdn.append(adj[k]) }
            }
            let icu = HLCore.hlPear(iu, fu)
            let icd = HLCore.hlPear(idn, fdn)

            var ft = HLFeatStat()
            ft.name = HL_FEAT_NAMES[f]
            ft.value = curV[f]
            ft.bucket = curB[f] + 1
            ft.upMean = HLCore.mean(su)
            ft.dnMean = HLCore.mean(sd)
            ft.effD = d
            ft.icUp = icu
            ft.icDn = icd
            ft.kind = (f < HLCore.HL_FEAT_KIND.count) ? HLCore.HL_FEAT_KIND[f] : ""
            ft.flip = (abs(icu) > 0.05 && abs(icd) > 0.05 && icu * icd < 0)
            ft.fwdUp = bu.count >= 20 ? HLCore.mean(bu) : 0
            ft.fwdDn = bd.count >= 20 ? HLCore.mean(bd) : 0
            ft.fwdAll = ba.count >= 20 ? HLCore.mean(ba) : 0
            ft.nUp = bu.count
            ft.nDn = bd.count
            ft.blind = abs(d) < 0.20
            feats.append(ft)
        }

        out.ok = true
        out.state = curS
        out.r60 = curR60
        out.days = days
        out.fwdUpAll = au.isEmpty ? 0 : HLCore.mean(au)
        out.fwdDnAll = ad.isEmpty ? 0 : HLCore.mean(ad)
        out.tOverlap = tOv
        out.tNonOverlap = tNo
        out.nSample = ns
        out.feats = feats
        return out
    }

    static func stateName(_ s: Int) -> String {
        if s == 0 { return "下跌态" }
        if s == 2 { return "上涨态" }
        return "震荡态"
    }

    /// 二维状态面板下的时序回测。无偷价：信号由 c[i-1] 收盘产生，
    /// 于 o[i] 开盘成交，收益记 o[i]→o[i+1]。volLev < 0 表示不分波动。
    static func regimeTs(_ c: [Double], _ o: [Double], _ trend: Int,
                         _ volLev: Int, _ volArr: [Double],
                         _ split: Double, _ n: Int) -> (Double, Int, Int) {
        var eq = 1.0
        var pos = 0.0
        var days = 0
        var trades = 0
        var i = 61
        while i + 1 < n {
            let r60 = (c[i - 1] / c[i - 61] - 1) * 100
            let s = r60 > 5 ? 2 : (r60 < -5 ? 0 : 1)
            let vl = volArr[i - 1] > split ? 1 : 0
            var want = 0.0
            if s == trend && (volLev < 0 || vl == volLev) { want = 1.0 }
            if want != pos {
                trades += 1
                eq *= (1.0 - 0.001)
            }
            pos = want
            if pos > 0 {
                eq *= (1.0 + pos * (o[i + 1] / o[i] - 1.0))
                days += 1
            }
            i += 1
        }
        return ((eq - 1.0) * 100.0, days, trades)
    }

    /// 二维状态面板：趋势（跌/震荡/涨）× 波动（低/高）六象限。
    /// 关键：同时给出横截面上涨率与时序回测收益 —— 二者常不一致。
    static func regime2D(_ c: [Double], _ o: [Double], _ h: [Double],
                         _ l: [Double], _ v: [Double]) -> HLRegime2D {
        var out = HLRegime2D()
        let n = c.count
        if n < 200 || o.count != n { return out }
        let i0 = 80
        let i1 = n - 21
        if i1 <= i0 { return out }

        // 逐日年化波动（%）
        var volArr = Array(repeating: 0.0, count: n)
        var i = 20
        while i < n {
            var rr: [Double] = []
            var k = i - 19
            while k <= i { rr.append(c[k] / c[k - 1] - 1); k += 1 }
            volArr[i] = annVol(rr) * 100.0
            i += 1
        }
        var vs: [Double] = []
        i = i0
        while i <= i1 { vs.append(volArr[i]); i += 1 }
        if vs.count < 60 { return out }
        let split = qpos(vs.sorted(), 0.5)

        // 横截面聚合
        var cnt = Array(repeating: 0, count: 6)
        var sum = Array(repeating: 0.0, count: 6)
        var win = Array(repeating: 0, count: 6)
        var raw: [Double] = []
        var tr: [Int] = []
        var vl2: [Int] = []
        i = i0
        while i <= i1 {
            let r60 = (c[i] / c[i - 60] - 1) * 100
            let s = r60 > 5 ? 2 : (r60 < -5 ? 0 : 1)
            let g = volArr[i] > split ? 1 : 0
            raw.append((c[i + 20] / c[i] - 1) * 100)
            tr.append(s)
            vl2.append(g)
            i += 1
        }
        let mraw = HLCore.mean(raw)
        for k in 0..<raw.count {
            let b = tr[k] * 2 + vl2[k]
            let a = raw[k] - mraw
            cnt[b] += 1
            sum[b] += a
            if a > 0 { win[b] += 1 }
        }

        var cells: [HLRegimeCell] = []
        for t in 0...2 {
            for g in 0...1 {
                let b = t * 2 + g
                var cc = HLRegimeCell()
                cc.trend = t
                cc.volLev = g
                cc.n = cnt[b]
                cc.fwdMean = cnt[b] > 0 ? sum[b] / Double(cnt[b]) : 0
                cc.winRate = cnt[b] > 0 ? Double(win[b]) / Double(cnt[b]) * 100 : 0
                let r = HLCore.regimeTs(c, o, t, g, volArr, split, n)
                cc.tsRet = r.0
                cc.tsDays = r.1
                cc.tsTrades = r.2
                cells.append(cc)
            }
        }

        // 横截面最优 vs 时序最优
        var cb = -1; var cw = -1e18
        var tb = -1; var tw = -1e18
        for k in 0..<cells.count {
            if cells[k].n >= 20 && cells[k].winRate > cw { cw = cells[k].winRate; cb = k }
            if cells[k].tsRet > tw { tw = cells[k].tsRet; tb = k }
        }
        let hold = HLCore.regimeTs(c, o, 2, -1, volArr, split, n)
        var beat = 0
        for k in 0..<cells.count { if cells[k].tsRet > hold.0 { beat += 1 } }

        let curR60 = (c[n - 1] / c[n - 61] - 1) * 100
        out.ok = true
        out.curTrend = curR60 > 5 ? 2 : (curR60 < -5 ? 0 : 1)
        out.curVol = volArr[n - 1] > split ? 1 : 0
        out.volSplit = split
        out.cells = cells
        out.crossBest = cb
        out.tsBest = tb
        out.conflict = (cb >= 0 && tb >= 0 && cb != tb)
        out.tsHold = hold.0
        out.tsHoldN = beat
        return out
    }

    static func regime2DText(_ p: HLRegime2D) -> String {
        if !p.ok { return "历史样本不足（需 200 根以上 K 线），无法建立二维状态面板。" }
        var s = String(format: "当前 %@ · %@波动（切分阈值 %.1f%%）。",
                       stateName(p.curTrend),
                       p.curVol == 1 ? "高" : "低", p.volSplit)
        if p.conflict {
            let a = p.cells[p.crossBest]
            let b = p.cells[p.tsBest]
            s += String(format: "横截面上「%@·%@」上涨率最高（%.1f%%），但时序回测收益最高的是「%@·%@」（%+.2f%% 对 %+.2f%%）。",
                        stateName(a.trend), a.volLev == 1 ? "高波" : "低波", a.winRate,
                        stateName(b.trend), b.volLev == 1 ? "高波" : "低波",
                        b.tsRet, a.tsRet)
            s += "两者不一致是常态：上涨率高只代表「常小赚」，时序复利下胜在「少赚但偶有大赚」的象限可能反超。不可直接用上涨率选象限。"
        } else if p.tsBest >= 0 {
            let b = p.cells[p.tsBest]
            s += String(format: "横截面与时序一致，最优象限为「%@·%@」，时序收益 %+.2f%%，持仓 %d 天、进出 %d 次。",
                        stateName(b.trend), b.volLev == 1 ? "高波" : "低波",
                        b.tsRet, b.tsDays, b.tsTrades)
        }
        s += String(format: "基准「涨态就买」时序收益 %+.2f%%，六象限中有 %d 个跑赢它。",
                    p.tsHold, p.tsHoldN)
        return s
    }

    /// 状态画像的总结文案。只描述「如何解读」，不做涨跌预测。
    static func stateProfileText(_ p: HLStateProfile) -> String {
        if !p.ok { return "历史样本不足（需 140 根以上 K 线），无法建立状态画像。" }
        let gap = p.fwdDnAll - p.fwdUpAll
        var s = ""
        s += String(format: "当前 %@，已持续 %d 个交易日，过去 60 日 %+.1f%%。",
                    stateName(p.state), p.days, p.r60)
        s += String(format: "历史上本标的跌态后续 20 日超额 %+.2f%%，涨态 %+.2f%%，两态差 %+.2f 个百分点。",
                    p.fwdDnAll, p.fwdUpAll, gap)
        let ct = abs(p.tNonOverlap)
        if abs(p.tOverlap) > 2.0 && ct <= 2.0 {
            s += String(format: "注意：重叠样本 t=%+.2f 看似显著，非重叠取样后仅 %+.2f —— 该规律很可能是滚动窗口自相关造成的假象，不可用于预测反转。",
                        p.tOverlap, p.tNonOverlap)
        } else if ct > 2.0 {
            s += String(format: "非重叠取样 t=%+.2f，两态差异较稳。", p.tNonOverlap)
        } else {
            s += String(format: "非重叠取样 t=%+.2f，两态差异不显著。", p.tNonOverlap)
        }
        return s
    }
}
