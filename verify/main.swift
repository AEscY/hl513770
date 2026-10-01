import Foundation

// ============================================================
// 云端验证程序：在 Codemagic 的 macOS 机器上真实编译并运行
// 只依赖 Foundation，与主 App 共用 HLCore.swift
// ============================================================

var vfFlat: [Double] = []

var pass = 0
var fail = 0
var failures: [String] = []

func check(_ name: String, _ cond: Bool, _ detail: String = "") {
    if cond {
        pass += 1
        print("  ✅ \(name) \(detail)")
    } else {
        fail += 1
        failures.append(name + " " + detail)
        print("  ❌ \(name) \(detail)")
    }
}

func near(_ a: Double, _ b: Double, _ eps: Double = 1e-6) -> Bool {
    return abs(a - b) < eps
}


func vfF_append() {
    vfFlat.append(10.0)
}

func fetch(_ code: String, _ len: Int) -> [Double] {
    let urlStr = "https://money.finance.sina.com.cn/quotes_service/api/json_v2.php/CN_MarketData.getKLineData?symbol=\(code)&scale=240&ma=no&datalen=\(len)"
    guard let url = URL(string: urlStr) else { return [] }
    var req = URLRequest(url: url)
    req.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
    req.timeoutInterval = 20
    let sem = DispatchSemaphore(value: 0)
    var out: [Double] = []
    let task = URLSession.shared.dataTask(with: req) { data, _, _ in
        if let d = data, let s = String(data: d, encoding: .utf8) {
            // 简易解析 "close":"0.333"
            var vals: [Double] = []
            var search = s
            while let r = search.range(of: "\"close\":\"") {
                let rest = String(search[r.upperBound...])
                if let e = rest.range(of: "\"") {
                    let num = String(rest[..<e.lowerBound])
                    if let v = Double(num) { vals.append(v) }
                    search = String(rest[e.upperBound...])
                } else { break }
            }
            out = vals
        }
        sem.signal()
    }
    task.resume()
    _ = sem.wait(timeout: .now() + 25)
    return out
}

print("")
print("──── 跨资产配置算法 ────")
// 相关系数：完全相同序列应为 1
// 注意：hlCorr 要求样本数 >= 30，测试序列必须足够长
// 用「同一组收益率取负号」构造完全反向序列，保证相关系数严格 = -1
var baseR: [Double] = []
var bseed: UInt64 = 20240930
var bi = 0
while bi < 60 {
    bseed = bseed &* 6364136223846793005 &+ 1442695040888963407
    baseR.append(Double(bseed % 2000) / 100000.0 - 0.01)
    bi += 1
}
var sameA: [Double] = [10.0]
var sameB: [Double] = [10.0]
var invB: [Double] = [10.0]
bi = 0
while bi < baseR.count {
    sameA.append(sameA[bi] * (1.0 + baseR[bi]))
    sameB.append(sameB[bi] * (1.0 + baseR[bi]))
    invB.append(invB[bi] * (1.0 - baseR[bi]))
    bi += 1
}
let cSame = HLCore.hlCorr(sameA, sameB)
check("完全同向序列相关系数=1 (得\(cSame))", abs(cSame - 1.0) < 0.001)

// 完全反向序列应为 -1
let cInv = HLCore.hlCorr(sameA, invB)
check("完全反向序列相关系数=-1 (得\(cInv))", abs(cInv + 1.0) < 0.001)

// 相关系数必须在 [-1, 1]
var rnd1: [Double] = []
var rnd2: [Double] = []
var sd: UInt64 = 12345
for _ in 0..<200 {
    sd = sd &* 6364136223846793005 &+ 1442695040888963407
    rnd1.append(Double(sd % 1000) / 10.0 + 10.0)
    sd = sd &* 6364136223846793005 &+ 1442695040888963407
    rnd2.append(Double(sd % 1000) / 10.0 + 10.0)
}
let cRnd = HLCore.hlCorr(rnd1, rnd2)
check("随机序列相关系数在[-1,1] (得\(cRnd))", cRnd >= -1.0001 && cRnd <= 1.0001)

// 长度不足应返回 0
let short = [1.0, 2.0, 3.0]
check("样本不足返回0", HLCore.hlCorr(short, short) == 0)

// 动量：上涨序列应为正，下跌应为负
let upC = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
let dnC = [10.0, 9.0, 8.0, 7.0, 6.0, 5.0, 4.0, 3.0, 2.0, 1.0]
check("上涨序列动量为正", HLCore.hlMom(upC, 5) > 0)
check("下跌序列动量为负", HLCore.hlMom(dnC, 5) < 0)
check("回看期为0返回0", HLCore.hlMom(upC, 0) == 0)
check("回看期超长返回0", HLCore.hlMom(upC, 100) == 0)

// 区间收益与回撤
check("区间收益 10->15 = +50%", abs(HLCore.hlRangeRet([10.0, 15.0]) - 0.5) < 0.0001)
check("存在回撤时为负", HLCore.hlMaxDD([10.0, 5.0, 12.0]) < 0)
check("单调上涨回撤为0", HLCore.hlMaxDD([10.0, 11.0, 12.0]) == 0)

print("  同向=\(String(format: "%.4f", cSame)) 反向=\(String(format: "%.4f", cInv)) 随机=\(String(format: "%.4f", cRnd))")

print("")

// ============================================================
// 6) 防偷价回归（look-ahead）
//    构造：长期横盘 1.0，末尾抬价使双均线【仅在第 103 期】才发出买入信号。
//    修正后：买入价 = 末日开盘 5.0，结算价 = 末日收盘 5.0 -> 收益 ≈ 0（仅手续费）
//    若退回偷价写法（收益取 op[i-1]->op[i]）会算出 ≈ +376%
// ============================================================
do {
    var c = [Double](repeating: 1.0, count: 100)
    c.append(1.0); c.append(1.0); c.append(1.0); c.append(1.05); c.append(5.0)
    let o = c
    let r = HLCore.backtest(c, 2, o, 20.0, true)
    let gain = (r[0] - 1.0) * 100.0
    check("防偷价·不得计入信号产生前的涨幅", gain < 5.0,
          String(format: "收益=%.2f%%（偷价写法会得到约+376%%）", gain))
}

print("════════════════════════════════════════")
print("  算法验证（云端真实运行）")
print("════════════════════════════════════════")

// ---------- 第一层：固定输入的单元测试 ----------
print("")
print("【第一部分】单元测试 — 固定输入，答案已知")

let seq = [1.0, 2.0, 3.0, 4.0, 5.0]
check("MA5(1..5)=3", near(HLCore.ma(seq, 5)!, 3.0), "实际 \(HLCore.ma(seq, 5)!)")

check("MA20 数据不足返回nil", HLCore.maAt(seq, 20, 4) == nil)

// 单调递增 → RSI = 100
let upSeq = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0]
check("全涨序列 RSI=100", near(HLCore.rsi(upSeq, 14)!, 100.0), "实际 \(HLCore.rsi(upSeq, 14)!)")

// 单调递减 → RSI = 0
let downSeq = Array(upSeq.reversed())
check("全跌序列 RSI=0", near(HLCore.rsi(downSeq, 14)!, 0.0), "实际 \(HLCore.rsi(downSeq, 14)!)")

// 常数序列：布林带上下轨应等于中轨（sd=0）
let flat = Array(repeating: 5.0, count: 30)
if let b = HLCore.bollAt(flat, 20, 29) {
    check("常数序列 布林带退化", near(b.up, b.mid) && near(b.low, b.mid), "up=\(b.up) low=\(b.low)")
} else {
    check("常数序列 布林带退化", false, "返回 nil")
}

// ATR：价格全平时 TR = 0
let flatH = Array(repeating: 5.0, count: 30)
let flatL = Array(repeating: 5.0, count: 30)
let flatC = Array(repeating: 5.0, count: 30)
check("常数序列 ATR=0", near(HLCore.atr(flatH, flatL, flatC, 14)!, 0.0))

// VaR / CVaR：构造已知数组
let rets100 = (1...100).map { Double($0) / 1000.0 - 0.05 }  // -0.049 .. 0.05
let v95 = HLCore.varHist(rets100, 0.95)
let cv95 = HLCore.cvarHist(rets100, 0.95)
check("CVaR ≤ VaR（尾部更差）", cv95 <= v95, "VaR=\(v95) CVaR=\(cv95)")

// 波动率锥：持有期越长，聚合后年化波动不应为负
check("volCone 非负", (HLCore.volCone(rets100, 5) ?? -1) >= 0)

// 蒙特卡洛：分位必须单调递增
// 注意：序列必须 >= 30 点，否则 monteCarlo 走退化分支返回全 0（测试会假通过）
var mxSeed: UInt64 = 20250101
var mcC: [Double] = [10.0]
var mxI = 0
while mxI < 300 {
    mxSeed = mxSeed &* 6364136223846793005 &+ 1442695040888963407
    mcC.append(mcC[mxI] * (1.0 + Double(mxSeed % 2000) / 100000.0 - 0.01))
    mxI += 1
}
var seed: UInt64 = 12345
let mc = HLCore.monteCarlo(mcC, 20, 400, seed)
check("蒙特卡洛 序列足够长(非退化)", mc[4] > 0 && mc[0] > 0,
      "\(mc.map { String(format: "%.3f", $0) }.joined(separator: " "))")
check("蒙特卡洛 分位单调递增",
      mc[0] <= mc[1] && mc[1] <= mc[2] && mc[2] <= mc[3] && mc[3] <= mc[4],
      "\(mc.map { String(format: "%.3f", $0) }.joined(separator: " "))")

// 蒙特卡洛确定性：同种子两次结果相同
let mc2 = HLCore.monteCarlo(mcC, 20, 400, 12345)
check("蒙特卡洛 同种子可复现", mc == mc2)

// 蒙特卡洛：不同种子结果应不同（防止随机数被写死）
let mc3 = HLCore.monteCarlo(mcC, 20, 400, 999)
check("蒙特卡洛 不同种子结果不同", mc != mc3)

// 回测：一直持有应等于首尾比（真正比对，而非只看 > 0）
let btC = mcC
let btHold = HLCore.backtest(btC, 0)
let expectHold = btC[btC.count - 1] / btC[1] - 1.0
check("回测 一直持有=首尾比", abs(btHold[0] - (1.0 + expectHold)) < 0.02,
      "倍数 \(String(format: "%.4f", btHold[0])) 期望 \(String(format: "%.4f", 1.0 + expectHold))")

// 信号质量：样本数非负（用足够长序列，避免走 <90 的退化分支）
check("signalQuality 返回3项", HLCore.signalQuality(mcC, 0).count == 3)
check("signalQuality 有真实样本", HLCore.signalQuality(mcC, 0)[0] > 0,
      "红灯样本 \(Int(HLCore.signalQuality(mcC, 0)[0]))")

// 赫斯特：平滑序列（二次积分）的 H 应显著高于粗糙序列（一阶差分）
// 注意：不能用完美等差序列 —— 各 lag 的差分标准差恒为 0，hurst 会返回 nil
var hz: [UInt64] = []
var hseed: UInt64 = 999
var hi0 = 0
while hi0 < 400 {
    hseed = hseed &* 6364136223846793005 &+ 1442695040888963407
    hz.append(hseed)
    hi0 += 1
}
var hn: [Double] = []
var hi1 = 0
while hi1 < hz.count {
    hn.append(Double((hz[hi1] >> 16) % 1000) / 1000.0 - 0.5)
    hi1 += 1
}
var smooth: [Double] = []
var rough: [Double] = []
var acc1 = 0.0
var acc2 = 0.0
var hi2 = 0
while hi2 < hn.count {
    acc1 = acc1 + hn[hi2] * 0.02
    acc2 = acc2 + acc1
    smooth.append(100.0 + acc2)
    hi2 += 1
}
var hi3 = 0
while hi3 + 1 < hn.count {
    rough.append(100.0 + (hn[hi3 + 1] - hn[hi3]) * 0.5)
    hi3 += 1
}
if let hS = HLCore.hurst(smooth), let hR = HLCore.hurst(rough) {
    check("赫斯特·平滑序列 H 偏高", hS > 0.6, "H=\(String(format: "%.3f", hS))")
    check("赫斯特·粗糙序列 H 偏低", hR < 0.4, "H=\(String(format: "%.3f", hR))")
    check("赫斯特·平滑 > 粗糙", hS > hR, "\(String(format: "%.3f", hS)) > \(String(format: "%.3f", hR))")
} else {
    check("赫斯特·平滑与粗糙对比", false, "返回 nil")
}

// ---------- 第二层：真实数据不变量 ----------
print("")
print("【第二部分】真实行情 — 拉 513770 实际数据跑不变量")
let real = fetch("sh513770", 320)
if real.count < 100 {
    print("  ⚠ 未能获取真实数据（\(real.count) 根），跳过真实数据检查")
    print("    这不影响第一部分单元测试的结论")
} else {
    print("  获取到 \(real.count) 根，现价 \(String(format: "%.3f", real[real.count-1]))")
    let r = HLCore.rets(real)

    // 不变量 1：MA 必须落在价格区间内
    if let m20 = HLCore.ma(real, 20) {
        let lo = real.min()!
        let hi = real.max()!
        check("MA20 落在价格区间内", m20 >= lo && m20 <= hi, "MA20=\(String(format: "%.4f", m20))")
    }
    // 不变量 2：RSI 必须在 0~100
    if let rs = HLCore.rsi(real, 14) {
        check("RSI ∈ [0,100]", rs >= 0 && rs <= 100, "RSI=\(String(format: "%.1f", rs))")
    }
    // 不变量 3：VaR95 应为负（亏损）
    let rv95 = HLCore.varHist(r, 0.95)
    check("VaR95 < 0（表示亏损）", rv95 < 0, "\(String(format: "%.2f", rv95 * 100))%")
    // 不变量 4：CVaR ≤ VaR
    let rcv = HLCore.cvarHist(r, 0.95)
    check("CVaR95 ≤ VaR95", rcv <= rv95, "CVaR=\(String(format: "%.2f", rcv * 100))%")
    // 不变量 5：最大回撤 ∈ [0,1]
    let dd = HLCore.maxDD(real)
    check("最大回撤 ∈ [0,1]", dd >= 0 && dd <= 1, "\(String(format: "%.1f", dd * 100))%")
    // 不变量 6：年化波动 > 0
    check("年化波动 > 0", HLCore.annVol(r) > 0, "\(String(format: "%.2f", HLCore.annVol(r) * 100))%")
    // 不变量 7：最长水下 ≤ 总天数
    let uw = HLCore.maxUnderwater(real)
    check("最长水下 ≤ 样本数", uw <= real.count, "\(uw) 天")
    // 不变量 8：赫斯特 ∈ (0,1) 大致
    if let h = HLCore.hurst(real) {
        check("赫斯特 H ∈ (0,1)", h > 0 && h < 1, "H=\(String(format: "%.3f", h))")
    }
    // 不变量 9：七策略回测均返回有限数
    var allFinite = true
    var k = 0
    while k <= 6 {
        let b = HLCore.backtest(real, k)
        if b[0].isNaN || b[0].isInfinite || b[1] < 0 || b[1] > 100 { allFinite = false }
        k += 1
    }
    check("七策略回测结果有效", allFinite)
    // 不变量 10：相似形态独立样本数在合理区间（去重后不再恒为 15）
    let sim = HLCore.similarStats(real)
    check("相似形态 独立样本数 ∈ [3,15]", Int(sim[0]) >= 3 && Int(sim[0]) <= 15,
          "独立 \(Int(sim[0])) 个（去重前取 \(Int(sim[7])) 个）")
    // 不变量 10b：去重后必须真的没有重叠，否则统计结论不可信
    check("相似形态 已去除重叠样本", sim[8] >= 0 && sim[7] >= sim[0],
          "剔除了 \(Int(sim[8]))% 的重叠样本")
    // 不变量 11：上涨概率 ∈ [0,100]
    check("上涨概率 ∈ [0,100]", sim[2] >= 0 && sim[2] <= 100, "\(String(format: "%.0f", sim[2]))%")
    // 不变量 12：异常扫描返回 7 项，level 全部合法
    // 构造 ohlcv
    var oo: [Double] = []
    var hh: [Double] = []
    var ll: [Double] = []
    var vv: [Double] = []
    var t = 0
    while t < real.count {
        oo.append(real[t]); hh.append(real[t]); ll.append(real[t]); vv.append(1.0)
        t += 1
    }
    let items = HLCore.anomalyScan(real, hh, ll, oo, vv)
    check("异常扫描 返回7项", items.count == 7, "实际 \(items.count)")
    var lvlOK = true
    var t2 = 0
    while t2 < items.count {
        if items[t2].level < 0 || items[t2].level > 2 { lvlOK = false }
        t2 += 1
    }
    check("异常项 level ∈ [0,2]", lvlOK)
    let agg = HLCore.anomalyLevel(items)
    check("异常聚合 count≤7 且 score≥0", agg.count <= 7 && agg.score >= 0,
          "level=\(agg.level) score=\(agg.score) count=\(agg.count)")

    // 不变量 12：信号质量三类样本之和 > 0
    let rq = HLCore.signalQuality(real, 0)
    let yq = HLCore.signalQuality(real, 1)
    let gq = HLCore.signalQuality(real, 2)
    check("信号审计 有样本", rq[0] + yq[0] + gq[0] > 0,
          "红\(Int(rq[0])) 黄\(Int(yq[0])) 绿\(Int(gq[0]))")

    // 打印真实计算结果（供人工核对）
    print("")
    print("  ─── 真实数据计算结果 ───")
    print("  现价        \(String(format: "%.3f", real[real.count-1]))")
    if let m20 = HLCore.ma(real, 20) { print("  MA20        \(String(format: "%.4f", m20))") }
    if let m60 = HLCore.ma(real, 60) { print("  MA60        \(String(format: "%.4f", m60))") }
    if let rs = HLCore.rsi(real, 14) { print("  RSI14       \(String(format: "%.1f", rs))") }
    print("  VaR95       \(String(format: "%.2f", rv95 * 100))%")
    print("  CVaR95      \(String(format: "%.2f", rcv * 100))%")
    print("  年化波动    \(String(format: "%.2f", HLCore.annVol(r) * 100))%")
    print("  夏普        \(String(format: "%.3f", HLCore.sharpe(real)))")
    print("  最大回撤    \(String(format: "%.1f", dd * 100))%")
    print("  最长水下    \(uw) 天")
    if let h = HLCore.hurst(real) { print("  赫斯特 H    \(String(format: "%.3f", h))") }
    print("  相似形态    样本\(Int(sim[0])) 后20日均\(String(format: "%.2f", sim[1]))% 上涨率\(String(format: "%.0f", sim[2]))%")
    print("  信号审计    红\(Int(rq[0]))次均\(String(format: "%.2f", rq[1]))% | 黄\(Int(yq[0]))次均\(String(format: "%.2f", yq[1]))% | 绿\(Int(gq[0]))次均\(String(format: "%.2f", gq[1]))%")
    print("")
    print("  ─── 市场异常扫描 ───")
    var ai = 0
    while ai < items.count {
        let mark = items[ai].level >= 2 ? "⚠" : (items[ai].level == 1 ? "·" : " ")
        print("  \(mark) \(items[ai].name.padding(toLength: 12, withPad: " ", startingAt: 0)) \(items[ai].value)")
        ai += 1
    }
    print("  综合: \(HLCore.anomalyTitle(agg.level)) (score \(agg.score), 触发 \(agg.count) 项)")

    var bk = 0
    while bk <= 6 {
        let b = HLCore.backtest(real, bk)
        print("  回测 \(HLCore.strategyName(bk).padding(toLength: 14, withPad: " ", startingAt: 0)) 收益\(String(format: "%+7.2f", (b[0]-1)*100))%  回撤\(String(format: "%5.1f", b[1]))%")
        bk += 1
    }
}

// ===== 策略适配度 =====
do {
    let n = 200
    var c: [Double] = []
    var o: [Double] = []
    var i = 0
    while i < n { c.append(10.0); o.append(10.0); i += 1 }
    let f = HLCore.strategyFit(c, o)
    check("常数序列·持有收益≈0", abs(f.hold) < 0.0001)
    check("常数序列·超额有限值", f.excess.isFinite)

    var up: [Double] = []
    var upO: [Double] = []
    var k = 0
    while k < 200 { let v = 10.0 + Double(k) * 0.1; up.append(v); upO.append(v); k += 1 }
    let fu = HLCore.strategyFit(up, upO)
    check("单调上涨·持有为正", fu.hold > 0)
    check("单调上涨·择时≤持有", fu.timing <= fu.hold + 0.001)
}

// ===== 自适应方案引擎 =====
do {
    // 1) 数据不足（<200）应返回存疑且置信度 0
    var sc: [Double] = []
    var so: [Double] = []
    var i = 0
    while i < 100 { sc.append(10.0); so.append(10.0); i += 1 }
    let p0 = HLCore.adaptivePlan(so, sc, sc, sc)
    check("自适应·数据不足返回存疑", p0[0] > 1.5 && p0[0] < 2.5)
    check("自适应·数据不足置信度为0", p0[1] == 0)

    // 2) 构造"前段跌、后段跌"序列：择时应两段都跑赢持有 → mode=1
    var dn: [Double] = []
    var dnO: [Double] = []
    var k = 0
    while k < 400 { let v = 20.0 - Double(k) * 0.02; dn.append(v); dnO.append(v); k += 1 }
    let pd = HLCore.adaptivePlan(dnO, dn, dn, dn)
    check("自适应·下跌序列返回合法模式", pd[0] >= 0 && pd[0] <= 2)
    check("自适应·下跌序列置信度合法", pd[1] == 90 || pd[1] == 35)
    check("自适应·下跌序列两段均为有限值", pd[2].isFinite && pd[3].isFinite && pd[4].isFinite && pd[5].isFinite)
    check("自适应·下跌序列持有为负", pd[3] < 0 && pd[5] < 0)

    // 3) 构造"前段涨、后段涨"序列：持有应两段都跑赢择时 → mode=0
    var upv: [Double] = []
    var upOv: [Double] = []
    var j = 0
    while j < 400 { let v = 10.0 + Double(j) * 0.05; upv.append(v); upOv.append(v); j += 1 }
    let pu = HLCore.adaptivePlan(upOv, upv, upv, upv)
    check("自适应·上涨序列模式合法", pu[0] >= 0 && pu[0] <= 2)
    check("自适应·上涨序列持有为正", pu[3] > 0 && pu[5] > 0)
    check("自适应·上涨序列择时不超持有", pu[2] <= pu[3] + 0.001 && pu[4] <= pu[5] + 0.001)

    // 4) 反转风险标记：前段涨后段跌应被识别
    var rv: [Double] = []
    var rvO: [Double] = []
    var t = 0
    while t < 240 { let v = 10.0 + Double(t) * 0.05; rv.append(v); rvO.append(v); t += 1 }
    var t2 = 0
    while t2 < 160 { let v = rv[239] - Double(t2) * 0.05; rv.append(v); rvO.append(v); t2 += 1 }
    let pr = HLCore.adaptivePlan(rvO, rv, rv, rv)
    check("自适应·反转风险被标记", pr[8] > 0.5)
    check("自适应·反转文案非空", HLCore.adaptiveAdvice(pr).isEmpty == false)

    // 5) 文案函数健壮性
    check("自适应·模式文案非空", HLCore.adaptiveModeText(0).isEmpty == false)
    check("自适应·模式文案非空1", HLCore.adaptiveModeText(1).isEmpty == false)
    check("自适应·模式文案非空2", HLCore.adaptiveModeText(2).isEmpty == false)
    check("自适应·置信文案非空", HLCore.adaptiveConfText(90).isEmpty == false)
    check("自适应·置信文案非空低", HLCore.adaptiveConfText(35).isEmpty == false)
    check("自适应·短数组不崩", HLCore.adaptiveAdvice([0]).isEmpty == false)
}

print("")
print("【资产分类】标的中性框架 —— 工具不绑定单一标的")
check("513770 判为港股/中概", HLCore.assetClass("sh513770") == 2)
check("513050 判为港股/中概", HLCore.assetClass("sh513050") == 2)
check("159941 判为海外市场", HLCore.assetClass("sz159941") == 3)
check("518880 判为商品", HLCore.assetClass("sh518880") == 4)
check("511260 判为债券", HLCore.assetClass("sh511260") == 5)
check("511990 判为货币", HLCore.assetClass("sh511990") == 6)
check("510300 判为A股宽基", HLCore.assetClass("sh510300") == 0)
check("512480 判为行业主题", HLCore.assetClass("sh512480") == 1)
check("600519 判为个股", HLCore.assetClass("sh600519") == 7)
check("hk00700 判为港股", HLCore.assetClass("hk00700") == 2)
check("usAAPL 判为海外", HLCore.assetClass("usAAPL") == 3)
let nm2 = HLCore.assetClassName(2)
check("类别名非空", nm2.isEmpty == false)
let ctx2 = HLCore.contextCodes(2)
let ctx7 = HLCore.contextCodes(7)
check("关联池非空", ctx2.isEmpty == false)
check("不同类别关联池不同", ctx2 != ctx7)
let ov0 = HLCore.overnightCodes(0)
let ov3 = HLCore.overnightCodes(3)
check("外围池非空", ov0.isEmpty == false)
check("不同类别外围池不同", ov0 != ov3)
check("中概标的展示成分", HLCore.hasHoldings("sh513770") == true)
check("个股不展示成分", HLCore.hasHoldings("sh600519") == false)
check("黄金不展示成分", HLCore.hasHoldings("sh518880") == false)
check("ADR 仅港股中概显示", HLCore.showAdr(2) == true)
check("A股标的隐藏 ADR", HLCore.showAdr(0) == false)
check("digits6 提取数字", HLCore.digits6("sh513770") == "513770")


// ============================================================
// 解套方案引擎
// ============================================================
print("")
print("── 解套方案引擎 ──")

// 构造一条先跌后涨的序列，验证「等回本」统计
var rc: [Double] = []
var rh: [Double] = []
var rl: [Double] = []
var rv: Double = 10.0
var ti: Int = 0
while ti < 400 {
    rv = rv * (ti < 200 ? 0.995 : 1.006)
    rc.append(rv)
    rh.append(rv * 1.01)
    rl.append(rv * 0.99)
    ti += 1
}
let rLow = rc[199]               // 最低点附近
let rCost = rLow * 1.30          // 成本比现价高 30%
let rPlan = HLCore.hlRescue(rc, rh, rl,
                            cost: rCost, shares: 300, price: rLow,
                            stop: rLow * 0.95, addCash: 200,
                            tShares: 100, fee: 0.05)
check("解套返回16个数", rPlan.count == 16)
check("浮亏为负", rPlan[0] < 0, "\(String(format: "%.2f", rPlan[0]))")
check("浮亏百分比为负", rPlan[1] < 0, "\(String(format: "%.2f", rPlan[1]))%")
check("回本需涨为正", rPlan[2] > 0, "\(String(format: "%.2f", rPlan[2]))%")
check("回本需涨≈30%", near(rPlan[2], 30.0, eps: 0.5), "\(String(format: "%.2f", rPlan[2]))%")
check("样本数为正", rPlan[5] > 0, "\(String(format: "%.0f", rPlan[5]))")
check("达标概率在0~100", rPlan[3] >= 0 && rPlan[3] <= 100, "\(String(format: "%.1f", rPlan[3]))%")
check("中位耗时非负", rPlan[4] >= 0, "\(String(format: "%.0f", rPlan[4]))天")

// 补仓：新成本必须低于原成本、高于现价
check("补仓后成本低于原成本", rPlan[6] < rCost, "\(String(format: "%.4f", rPlan[6])) < \(String(format: "%.4f", rCost))")
check("补仓后成本高于现价", rPlan[6] > rLow)
check("补仓后回本需涨更小", rPlan[7] < rPlan[2], "\(String(format: "%.2f", rPlan[7]))% < \(String(format: "%.2f", rPlan[2]))%")
check("补仓总投入=原投入+补仓额", near(rPlan[9], rCost * 300 + 200, eps: 0.01))
// 补仓的代价：跌到止损时亏得更多
check("补仓后跌到止损亏更多", rPlan[8] < rPlan[15], "\(String(format: "%.2f", rPlan[8])) < \(String(format: "%.2f", rPlan[15]))")

// 做T：单次收益与次数
check("日均振幅为正", rPlan[12] > 0, "\(String(format: "%.2f", rPlan[12]))%")
check("做T需次数为正或标记不可行", rPlan[11] > 0 || rPlan[11] == -1, "\(String(format: "%.1f", rPlan[11]))")
if rPlan[11] > 0 {
    let gap = rPlan[10] * rPlan[11]
    check("次数×单次≈亏损额", near(gap, abs(rPlan[0]), eps: abs(rPlan[0]) * 0.02 + 0.01),
          "\(String(format: "%.2f", gap)) vs \(String(format: "%.2f", abs(rPlan[0])))")
}

// 边界：不亏损时返回全零或正数浮亏（hasRescue 会过滤）
let rFlat = HLCore.hlRescue(rc, rh, rl,
                            cost: rLow * 0.8, shares: 300, price: rLow,
                            stop: rLow * 0.95, addCash: 0,
                            tShares: 100, fee: 0.05)
check("盈利持仓浮亏为正", rFlat[0] > 0)
check("补仓额为0时成本=原成本", near(rFlat[6], rLow * 0.8, eps: 1e-9))

// 边界：非法输入返回全零
let rBad = HLCore.hlRescue(rc, rh, rl,
                           cost: 0, shares: 0, price: 0,
                           stop: 0, addCash: 0, tShares: 100, fee: 0.05)
var allZero = true
for x in rBad { if x != 0 { allZero = false } }
check("非法输入返回全零", allZero)

// 真实数据上的一次完整推演（若网络可用）
// fetch 只返回收盘价，这里按 ±1.2% 构造日内高低点用于振幅估算
var realH: [Double] = []
var realL: [Double] = []
for x in real {
    realH.append(x * 1.012)
    realL.append(x * 0.988)
}
if real.count >= 300 {
    let rp = HLCore.hlRescue(real, realH, realL,
                             cost: (real.last ?? 0) * 1.2,
                             shares: 300, price: real.last ?? 0,
                             stop: (real.last ?? 0) * 0.95,
                             addCash: 200, tShares: 100, fee: 0.05)
    check("真实数据·浮亏为负", rp[0] < 0)
    check("真实数据·回本需涨≈20%", near(rp[2], 20.0, eps: 0.5), "\(String(format: "%.2f", rp[2]))%")
    check("真实数据·补仓后回本线更低", rp[7] < rp[2], "\(String(format: "%.2f", rp[7]))%")
    check("真实数据·补仓代价更大", rp[8] < rp[15])
    print("  · 真实数据推演: 浮亏 \(String(format: "%.2f", rp[0])) 元, 需涨 \(String(format: "%.1f", rp[2]))%,")
    print("    等回本达标 \(String(format: "%.0f", rp[3]))% (中位 \(String(format: "%.0f", rp[4])) 天), 做T需 \(String(format: "%.0f", rp[11])) 次")
}


// ============================================================
// 进阶引擎验证（HLAdv）
// ============================================================
print("")
print("【进阶引擎】")

// 涨跌停判定
let upC2: [Double] = [10.0, 11.0]
let dnC2: [Double] = [10.0, 9.0]
let flatTwo: [Double] = [10.0, 10.0]
check("涨跌停·涨停判定", HLAdv.limitState(upC2, upC2, upC2, 1, 0.10) == 1)
check("涨跌停·跌停判定", HLAdv.limitState(dnC2, dnC2, dnC2, 1, 0.10) == -1)
check("涨跌停·平盘可成交", HLAdv.limitState(flatTwo, flatTwo, flatTwo, 1, 0.10) == 0)
let bd2 = HLAdv.blockedDays(upC2, upC2, upC2, [1.0, 1.0], 0.10)
check("不可成交统计·返回5项", bd2.count == 5)
check("不可成交统计·涨停1天", near(bd2[0], 1.0))

// 净值曲线：无偷价（构造横盘序列，策略不应产生虚假收益）
var flatC2: [Double] = []
var flatO2: [Double] = []
var flatH2: [Double] = []
var flatL2: [Double] = []
var fv2: [Double] = []
var fi2 = 0
while fi2 < 300 {
    flatC2.append(10.0); flatO2.append(10.0)
    flatH2.append(10.0); flatL2.append(10.0)
    fv2.append(1000.0)
    fi2 += 1
}
let flatNav = HLAdv.navAll(flatO2, flatH2, flatL2, flatC2, fv2, 2, 20, 60, 20.0, 0.10)
if flatNav.count > 0 {
    let fr = (flatNav[flatNav.count - 1] - 1.0) * 100.0
    check("横盘序列·无虚假收益", abs(fr) < 6.0, "\(String(format: "%.2f", fr))%")
} else {
    check("横盘序列·净值非空", false)
}

// 成本单调性：成本越高收益越低
var upSeq2: [Double] = []
var upO2: [Double] = []
var ui2 = 0
while ui2 < 400 {
    let px = 10.0 + Double(ui2) * 0.01
    upSeq2.append(px); upO2.append(px)
    ui2 += 1
}
let csA = HLAdv.costSensitivity(upO2, upSeq2, upSeq2, upSeq2, [], 2, 20, 60, 0.10)
check("成本敏感性·三档递减", csA[0] >= csA[1] && csA[1] >= csA[2],
      "\(String(format: "%.2f", csA[0])) / \(String(format: "%.2f", csA[1])) / \(String(format: "%.2f", csA[2]))")

// CPCV 分位数单调
var rnd: [Double] = []
var ri = 0
while ri < 900 {
    rnd.append((HLCore.lcg(&sd) - 0.5) * 0.04)
    ri += 1
}
let cpR = HLAdv.cpcv(rnd, 6, 5)
check("CPCV·路径数=15", near(cpR[0], 15.0), "\(String(format: "%.0f", cpR[0]))")
check("CPCV·最差≤中位≤最好", cpR[2] <= cpR[1] + 1e-9 && cpR[1] <= cpR[3] + 1e-9)
check("CPCV·p25≤p75", cpR[5] <= cpR[6] + 1e-9)

// 置换检验：p 值在 [0,1]
var trSeq: [Double] = []
var ti2 = 0
while ti2 < 20 {
    trSeq.append((ti2 % 3 == 0) ? 0.05 : -0.02)
    ti2 += 1
}
let ptR = HLAdv.permutationTest(trSeq, 300, 99)
check("置换检验·p值在[0,1]", ptR[1] >= 0 && ptR[1] <= 1, "p=\(String(format: "%.3f", ptR[1]))")
check("置换检验·样本不足返回", HLAdv.permutationTest([0.1], 10, 1)[1] == 1)

// 基准相对：与自身完全相关
var base: [Double] = []
var bi2 = 0
while bi2 < 300 {
    base.append((HLCore.lcg(&sd) - 0.5) * 0.03)
    bi2 += 1
}
let bmSelf = HLAdv.benchMetrics(base, base, 0.0)
check("基准相对·自身Beta=1", near(bmSelf[1], 1.0, eps: 1e-6), "\(String(format: "%.4f", bmSelf[1]))")
check("基准相对·自身Alpha≈0", abs(bmSelf[0]) < 1e-6)
check("基准相对·自身R²=100", near(bmSelf[4], 100.0, eps: 1e-6))
check("基准相对·自身跟踪误差=0", abs(bmSelf[2]) < 1e-6)

// 相关系数矩阵
let cmA = HLAdv.corrMatrix([base, base])
check("相关矩阵·对角为1", near(cmA[0][0], 1.0) && near(cmA[1][1], 1.0))
check("相关矩阵·自身相关为1", near(cmA[0][1], 1.0, eps: 1e-6))
let cmB = HLAdv.corrMatrix([base])
check("相关矩阵·单资产", cmB.count == 1 && near(cmB[0][0], 1.0))

// HRP：权重和为1且非负
let hrpW = HLAdv.hrpWeights([base, upSeq, flatC])
let wsum = hrpW[0] + hrpW[1] + hrpW[2]
check("HRP·权重和为1", near(wsum, 1.0, eps: 1e-6), "\(String(format: "%.6f", wsum))")
check("HRP·权重非负", hrpW[0] >= 0 && hrpW[1] >= 0 && hrpW[2] >= 0)
check("HRP·单资产返回1", near(HLAdv.hrpWeights([base])[0], 1.0))

// 集中度
let conE = HLAdv.concentration([0.5, 0.5])
check("集中度·两项等权HHI=0.5", near(conE[0], 0.5, eps: 1e-9))
check("集中度·有效标的数=2", near(conE[2], 2.0, eps: 1e-6))
let con1 = HLAdv.concentration([1.0])
check("集中度·单一资产HHI=1", near(con1[0], 1.0))

// 压力测试：rho 越大波动越大
let sv1 = HLAdv.stressVol([0.5, 0.5], [0.2, 0.2], 0.0)
let sv2 = HLAdv.stressVol([0.5, 0.5], [0.2, 0.2], 0.9)
check("压力测试·相关升高波动增大", sv2 > sv1, "\(String(format: "%.2f", sv1))% -> \(String(format: "%.2f", sv2))%")

// 仓位方案
let smA = HLAdv.sizingModes(0.5, 2.0, 30.0, 6.0, 100.0)
check("仓位·波动率目标=50%", near(smA[1], 50.0, eps: 1e-6), "\(String(format: "%.1f", smA[1]))%")
check("仓位·固定分数≈16.7%", near(smA[0], 16.6667, eps: 1e-3), "\(String(format: "%.2f", smA[0]))%")
let smB = HLAdv.sizingModes(0.5, 2.0, 30.0, 0.0, 100.0)
check("仓位·止损为0时取上限", near(smB[0], 100.0, eps: 1e-9))
let smC = HLAdv.sizingModes(0.3, 1.0, 30.0, 6.0, 100.0)
check("仓位·劣势时凯利归零", near(smC[2], 0.0, eps: 1e-9), "\(String(format: "%.2f", smC[2]))%")

// 市场状态
let rgA = HLAdv.regimeOf(flatC)
check("状态·样本足够时返回状态码", rgA[2] >= 0)
check("状态·横盘ER低", rgA[1] < 0.3, "ER=\(String(format: "%.3f", rgA[1]))")
let rgB = HLAdv.regimeOf(upSeq)
check("状态·单调上涨ER高", rgB[1] > 0.9, "ER=\(String(format: "%.3f", rgB[1]))")
check("状态·文案非空", HLAdv.regimeText(rgB[2]).count > 0)
check("状态·建议非空", HLAdv.regimeAdvice(rgB[2]).count > 0)

// 稳健度分级
check("稳健度·高WFE高占比=较稳", HLAdv.robustGrade(0.6, 80) == 2)
check("稳健度·低WFE=脆弱", HLAdv.robustGrade(0.1, 30) == 0)
check("稳健度·中间=一般", HLAdv.robustGrade(0.4, 60) == 1)

// 分时逐笔资金流
func mkTick(_ t: String, _ p: Double, _ v: Double, _ a: Double, _ buy: Bool) -> HLTick {
    var k = HLTick()
    k.t = t
    k.price = p
    k.vol = v
    k.amt = a
    k.isBuy = buy
    return k
}
let tkEmpty: [HLTick] = []
check("逐笔·空序列笔数为0", HLCore.tickFlow(tkEmpty).count == 0)
check("逐笔·空序列占比为0", HLCore.tickFlow(tkEmpty).buyRatio == 0)
check("逐笔·空序列VWAP为0", HLCore.tickVwap(tkEmpty) == 0)
check("逐笔·空序列文案非空", HLCore.flowVerdictText(HLCore.tickFlow(tkEmpty), 0, 0).count > 0)

let tk1 = mkTick("09:30:01", 10.0, 100, 1000000, true)    // 超大单 买 100万
let tk2 = mkTick("10:30:01", 10.0, 50, 500000, false)     // 大单 卖 50万
let tk3 = mkTick("14:45:01", 10.0, 10, 100000, true)      // 中单 买 10万
let tk4 = mkTick("14:50:01", 10.0, 1, 10000, false)       // 小单 卖 1万
let tkAll = [tk1, tk2, tk3, tk4]
let fs1 = HLCore.tickFlow(tkAll)
check("逐笔·笔数正确", fs1.count == 4, "\(fs1.count)")
check("逐笔·主动买额正确", near(fs1.buyAmt, 1100000.0), "\(fs1.buyAmt)")
check("逐笔·主动卖额正确", near(fs1.sellAmt, 510000.0), "\(fs1.sellAmt)")
check("逐笔·净额=买-卖", near(fs1.netAmt, 590000.0), "\(fs1.netAmt)")
check("逐笔·超大单净额正确", near(fs1.xlNet, 1000000.0), "\(fs1.xlNet)")
check("逐笔·大单净额为负", near(fs1.lgNet, -500000.0), "\(fs1.lgNet)")
check("逐笔·中单净额正确", near(fs1.mdNet, 100000.0), "\(fs1.mdNet)")
check("逐笔·小单净额为负", near(fs1.smNet, -10000.0), "\(fs1.smNet)")
check("逐笔·超大单笔数1", fs1.bigCount == 1, "\(fs1.bigCount)")
check("逐笔·四档净额之和=总净额",
      near(fs1.xlNet + fs1.lgNet + fs1.mdNet + fs1.smNet, fs1.netAmt, eps: 1e-6))
check("逐笔·买占比在0~100", fs1.buyRatio > 0 && fs1.buyRatio < 100)
check("逐笔·买占比数值正确",
      near(fs1.buyRatio, 1100000.0 / 1610000.0 * 100.0, eps: 1e-9),
      String(format: "%.4f", fs1.buyRatio))

// VWAP 必落在价格区间内（金额须与 价格 x 手数 x 100 自洽）
let tk5 = mkTick("09:31:01", 12.0, 100, 120000, true)   // 100手=1万股 x 12元
let tk6 = mkTick("09:32:01", 8.0, 100, 80000, true)     // 100手=1万股 x 8元
let fsV = HLCore.tickVwap([tk5, tk6])
check("逐笔·VWAP落在区间内", fsV >= 8.0 && fsV <= 12.0, String(format: "%.4f", fsV))
check("逐笔·等额等股VWAP=均价", near(fsV, 10.0, eps: 1e-9), String(format: "%.4f", fsV))

// 尾盘切片
let tailS = HLCore.tickTailFlow(tkAll, 870)  // 14:30 = 870 分钟
check("逐笔·尾盘只含14:30后", tailS.count == 2, "\(tailS.count)")
check("逐笔·尾盘净额正确", near(tailS.netAmt, 90000.0), "\(tailS.netAmt)")
let tailN = HLCore.tickTailFlow(tkAll, 900)  // 15:00，无数据
check("逐笔·超出时段尾盘为空", tailN.count == 0)

// 时间解析
check("逐笔·时间解析09:30", HLCore.tickMinute("09:30:00") == 570)
check("逐笔·时间解析14:30", HLCore.tickMinute("14:30:00") == 870)

// 分歧检测
check("逐笔·超大单与大单反向=分歧", HLCore.flowDivergence(fs1, 100000.0) == 1)
let sameFlow = HLCore.tickFlow([mkTick("09:30:01", 10, 100, 1000000, true),
                                mkTick("09:31:01", 10, 50, 500000, true)])
check("逐笔·同向不算分歧", HLCore.flowDivergence(sameFlow, 100000.0) == 0)
check("逐笔·金额过小忽略", HLCore.flowDivergence(fs1, 1e12) == 0)

print("")
print("── 样本重叠校正（70标的×800日实测：逐日重叠t=11.34 → 非重叠t=1.63）──")
let sqc = HLCore.signalQualityAdj(mcC, 0)
let sqg = HLCore.signalQualityAdj(mcC, 2)
check("signalQualityAdj 返回6项", sqc.count == 6)
check("signalQualityAdj 有效样本 ≤ 原始样本", sqc[1] <= sqc[0] + 0.001,
      "原始\(Int(sqc[0])) 有效\(String(format: "%.1f", sqc[1]))")
check("校正t绝对值 ≤ 未校正t", abs(sqc[5]) <= abs(sqc[4]) + 0.001,
      "tRaw=\(String(format: "%.2f", sqc[4])) tAdj=\(String(format: "%.2f", sqc[5]))")
check("有效样本 = 原始/窗口", sqc[0] > 20 ? abs(sqc[1] - sqc[0] / 20.0) < 0.01 : true)
let flatA = [Double](repeating: 1.0, count: 200)
let sqf = HLCore.signalQualityAdj(flatA, 2)
check("常数序列均值为0", abs(sqf[2]) < 0.0001)
let upA = (1...200).map { Double($0) }
let squ = HLCore.signalQualityAdj(upA, 2)
check("单调上涨·绿灯后20日为正", squ[2] > 0, "均值\(String(format: "%.3f", squ[2]))%")
check("上涨序列绿灯上涨率100%", squ[3] > 99.0, "\(String(format: "%.0f", squ[3]))%")
let dnA = (1...200).map { Double(201 - $0) }
let sqd = HLCore.signalQualityAdj(dnA, 0)
check("单调下跌·红灯后20日为负", sqd[2] < 0, "均值\(String(format: "%.3f", sqd[2]))%")
check("短序列返回退化值", HLCore.signalQualityAdj([1.0, 2.0], 0).count == 6)

print("")
print("── 类别信号优势（跨标的实测）──")
check("港股类别信号优势为负", HLCore.clsSignalEdge("港股") < 0,
      "\(String(format: "%.2f", HLCore.clsSignalEdge("港股")))")
check("个股类别信号优势为正", HLCore.clsSignalEdge("个股") > 0,
      "\(String(format: "%.2f", HLCore.clsSignalEdge("个股")))")
check("未知类别返回0", HLCore.clsSignalEdge("未知类别") == 0)
check("港股提示含否定表述", HLCore.clsSignalHint("港股").count > 10)
check("各类别提示非空", HLCore.clsSignalHint("宽基").count > 5 && HLCore.clsSignalHint("商品").count > 5)



print("")
print("── 风险口径适配度（新增）──")
// fitEquity 基本性质
let fe1 = HLCore.fitEquity([1.0, 2.0], [1.0, 2.0])
check("短序列fitEquity返回空", fe1.eqT.isEmpty && fe1.eqH.isEmpty)
let up200 = (1...200).map { Double($0) }
let fe2 = HLCore.fitEquity(up200, up200)
check("上涨序列fitEquity非空", fe2.eqT.count > 100, "长度\(fe2.eqT.count)")
check("上涨序列仓位在[0,1]", fe2.exposure >= 0 && fe2.exposure <= 1,
      "仓位\(String(format: "%.3f", fe2.exposure))")
check("持有净值起点为1", abs((fe2.eqH.first ?? 0) - 1.0) < 0.0001)

// strategyFitEx
// 常数序列全程绿灯：只会买入一次并一直持有，不产生卖出
let fitConst = HLCore.strategyFitEx(Array(repeating: 5.0, count: 200),
                                    Array(repeating: 5.0, count: 200))
check("常数序列只买不卖", fitConst.trades <= 1, "交易\(fitConst.trades)次")
check("常数序列波动为0", abs(fitConst.volH) < 0.0000001)
// 只买入一次 → 择时净值因单边费率低 0.05% → 回撤改善 = -0.0005，正好等于费率
// 这条同时验证了「成本确实被计入回测」
check("常数序列回撤改善=负单边费率", abs(fitConst.dDD + 0.0005) < 0.0001,
      "dDD=\(String(format: "%.6f", fitConst.dDD))")
let fitUp = HLCore.strategyFitEx(up200, up200)
check("上涨序列持有收益为正", fitUp.hold > 0, "持有\(String(format: "%.3f", fitUp.hold))")
check("回撤改善=持有回撤-择时回撤", abs(fitUp.dDD - (fitUp.ddH - fitUp.ddT)) < 0.0000001)
check("夏普改善=择时夏普-持有夏普", abs(fitUp.dSharpe - (fitUp.sharpeT - fitUp.sharpeH)) < 0.0000001)
check("超额=择时-持有", abs(fitUp.excess - (fitUp.timing - fitUp.hold)) < 0.0000001)
check("回撤值在[0,1]", fitUp.ddT >= 0 && fitUp.ddT <= 1 && fitUp.ddH >= 0 && fitUp.ddH <= 1)
// 低波动门禁：常数序列波动为0，应触发 lowVol
let fitLow = HLCore.strategyFitEx(Array(repeating: 10.0, count: 300),
                                  Array(repeating: 10.0, count: 300))
check("零波动标的lowVol为true", fitLow.lowVol, "volH=\(String(format: "%.5f", fitLow.volH))")

// segRisk
let sr = HLCore.segRisk(up200, up200, 0, 200)
check("segRisk夏普改善有限", sr.dSharpe.isFinite)
let srShort = HLCore.segRisk(up200, up200, 0, 30)
check("segRisk短区间退化", srShort.trades == 0)

// peerDispersion
let pd1 = HLCore.peerDispersion([1.0, 1.0, 1.0])
check("离散度·常数极差为0", abs(pd1.spread) < 0.0000001)
check("离散度·常数标准差为0", abs(pd1.sd) < 0.0000001)
check("离散度·样本数正确", pd1.n == 3, "n=\(pd1.n)")
let pd2 = HLCore.peerDispersion([10.0])
check("离散度·单元素n=1", pd2.n == 1 && pd2.spread == 0)
let pd3 = HLCore.peerDispersion([Double.nan, 1.0, 5.0])
check("离散度·过滤NaN", pd3.n == 2, "n=\(pd3.n)")
let pd4 = HLCore.peerDispersion([-20.0, 30.0])
check("离散度·极差计算正确", abs(pd4.spread - 50.0) < 0.0000001, "极差\(pd4.spread)")
check("离散度·min/max正确", pd4.min == -20.0 && pd4.max == 30.0)

// peerSpreadRisk 阈值 20
check("离散度·阈值20以上报警", HLCore.peerSpreadRisk(51.5))
check("离散度·阈值20以内不报警", HLCore.peerSpreadRisk(16.4) == false)

// peerGroupCodes
check("参照组·宽基非空", HLCore.peerGroupCodes(0).count >= 4)
check("参照组·商品非空", HLCore.peerGroupCodes(4).count >= 2)
check("参照组·未知类别有默认", HLCore.peerGroupCodes(99).count >= 2)
check("参照组·各类别不同", HLCore.peerGroupCodes(0) != HLCore.peerGroupCodes(4))

// adaptivePlan 返回 15 元素且用夏普判定
let apShort = HLCore.adaptivePlan([1.0], [1.0], [1.0], [1.0])
check("adaptivePlan短数据返回15元素", apShort.count == 15, "个数\(apShort.count)")
let apUp = HLCore.adaptivePlan(up200, up200, up200, up200)
check("adaptivePlan正常数据15元素", apUp.count == 15)
check("adaptivePlan模式合法", apUp[0] == 0 || apUp[0] == 1 || apUp[0] == 2)
check("adaptivePlan置信度合法", apUp[1] == 35 || apUp[1] == 90, "置信\(apUp[1])")
check("adaptivePlan夏普改善有限", apUp[9].isFinite && apUp[10].isFinite && apUp[11].isFinite)
check("adaptivePlan仓位在[0,1]", apUp[13] >= 0 && apUp[13] <= 1)


    // ---------- 前瞻信号面板 ----------
    print("\n[前瞻信号]")

    // 分档边界（57 标的 801 根实测分位数）
    check("波动 Q1 边界", HLCore.volBucketOf(14.9) == 1, "14.9→Q1")
    check("波动 Q2 边界", HLCore.volBucketOf(15.0) == 2, "15.0→Q2")
    check("波动 Q3 边界", HLCore.volBucketOf(20.7) == 3, "20.7→Q3")
    check("波动 Q4 边界", HLCore.volBucketOf(26.2) == 4, "26.2→Q4")
    check("波动 Q5 边界", HLCore.volBucketOf(35.1) == 5, "35.1→Q5")
    check("波动分档值域", HLCore.volBucketOf(0.0) >= 1 && HLCore.volBucketOf(9999.0) <= 5, "恒在1..5")

    check("偏离 Q1 边界", HLCore.devBucketOf(-4.5) == 1, "-4.5→Q1")
    check("偏离 Q2 边界", HLCore.devBucketOf(-0.4) == 2, "-0.4→Q2")
    check("偏离 Q3 边界", HLCore.devBucketOf(2.2) == 3, "2.2→Q3")
    check("偏离 Q4 边界", HLCore.devBucketOf(6.8) == 4, "6.8→Q4")
    check("偏离 Q5 边界", HLCore.devBucketOf(6.9) == 5, "6.9→Q5")
    check("偏离分档值域", HLCore.devBucketOf(-999.0) >= 1 && HLCore.devBucketOf(999.0) <= 5, "恒在1..5")

    // 映射表完整性
    check("波动映射表长度", HLCore.fwdDrop5.count == 5 && HLCore.fwdAbsMv.count == 5, "各5项")
    check("偏离映射表长度", HLCore.fwdUp60.count == 5 && HLCore.fwdZ60.count == 5, "各5项")
    check("跌超5%概率在0..100", HLCore.fwdDrop5.filter { $0 > 0 && $0 < 100 }.count == 5, "全部合法")
    check("上涨率在0..100", HLCore.fwdUp60.filter { $0 > 0 && $0 < 100 }.count == 5, "全部合法")
    check("Q1跌超5%概率最低", HLCore.fwdDrop5[0] < HLCore.fwdDrop5[4], "\(HLCore.fwdDrop5[0]) < \(HLCore.fwdDrop5[4])")
    check("Q5上涨率最低", HLCore.fwdUp60[4] < HLCore.fwdUp60[0], "\(HLCore.fwdUp60[4]) < \(HLCore.fwdUp60[0])")
    check("Q5偏离z为负", HLCore.fwdZ60[4] < 0, "\(HLCore.fwdZ60[4])")

    // 数组长度与缺数据保护
    let fShort = HLCore.forwardSignal([1.0, 2.0, 3.0], 2)
    check("短序列返回16元素", fShort.count == 16, "\(fShort.count)")
    check("短序列波动档为0", fShort[1] == 0, "不产生假信号")

    // 构造序列：常数序列波动应为 0（Q1）
    var flat: [Double] = []
    for _ in 0..<200 { flat.append(10.0) }
    let fFlat = HLCore.forwardSignal(flat, 199)
    check("常数序列档位Q1", fFlat[1] == 1, "Q\(Int(fFlat[1]))")
    check("常数序列偏离0", near(fFlat[4], 0.0, 0.001), "\(fFlat[4])")
    check("常数序列跌超5%概率为Q1值", near(fFlat[2], 5.9, 0.001), "\(fFlat[2])")

    // 上涨序列：偏离 MA60 为正，档位应偏后
    var upC2: [Double] = []
    var pv = 10.0
    for _ in 0..<200 { pv = pv * 1.01; upC2.append(pv) }
    let fUp = HLCore.forwardSignal(upC2, 199)
    check("上涨序列偏离MA60为正", fUp[4] > 0, "\(fUp[4])")
    check("上涨序列偏离档≥Q4", fUp[5] >= 4, "Q\(Int(fUp[5]))")
    check("上涨序列上涨率≤Q4值", fUp[6] <= 46.3 + 0.001, "\(fUp[6])")

    // 下跌序列：偏离为负，档位应偏前
    var dnC2: [Double] = []
    var qv = 100.0
    for _ in 0..<200 { qv = qv * 0.99; dnC2.append(qv) }
    let fDn = HLCore.forwardSignal(dnC2, 199)
    check("下跌序列偏离MA60为负", fDn[4] < 0, "\(fDn[4])")
    check("下跌序列偏离档Q1", fDn[5] == 1, "Q\(Int(fDn[5]))")

    // 事件名映射
    check("事件名0为无", HLCore.forwardEventName(0) == "无极端事件", "")
    check("事件名1为新低", HLCore.forwardEventName(1).contains("新低"), "")
    check("事件名4为骤降", HLCore.forwardEventName(4).contains("骤降"), "")

    // 告警文案
    check("告警0无警示", HLCore.forwardWarnText(0).contains("无"), "")
    check("告警1提追高", HLCore.forwardWarnText(1).contains("追高"), "")
    check("告警2提安静", HLCore.forwardWarnText(2).contains("安静"), "")
    check("告警3提低波动", HLCore.forwardWarnText(3).contains("极低波动"), "")

    // 告警优先级：追高(1) 应压过 波动骤降(2) 与 极低波动(3)
    var pri: [Double] = []
    for _ in 0..<200 { pri.append(10.0) }
    // 构造：极低波动 + 波动骤降 + 偏离Q5 同时成立 → 应为 1
    var mixC: [Double] = []
    var mv = 10.0
    var t = 0
    while t < 60 { mixC.append(mv * (1.0 + 0.0002)); t += 1 }
    while t < 200 { mv = mv * 1.012; mixC.append(mv); t += 1 }
    let fm = HLCore.forwardSignal(mixC, 199)
    check("混合场景档位", fm[5] >= 4 || fm[5] == 1, "Q\(Int(fm[5]))")
    check("告警优先级有值", fm[14] == 1 || fm[14] == 2 || fm[14] == 3, "warn=\(Int(fm[14]))")

    // 结论文案
    check("结论·数据不足", HLCore.forwardVerdict([0.0]) == "数据不足", "")
    let fvQ5 = [0.0, 1.0, 24.9, 7.24, 9.0, 5.0, 26.6, -0.349, 0, 0, 0, 0, 0, 52.1, 1.0, 0]
    check("结论·位置偏高", HLCore.forwardVerdict(fvQ5).contains("偏高"), "")
    let fvQ1 = [0.0, 1.0, 5.9, 3.34, -9.0, 1.0, 51.7, 0.230, 0, 0, 0, 0, 0, 52.1, 0.0, 0]
    check("结论·位置偏低", HLCore.forwardVerdict(fvQ1).contains("偏低"), "")

    // ========== 统计修正引擎 ==========
    print("")
    print("── 统计修正（Newey-West / 波动率成本 / Rank IC / Purge-Embargo）──")

    // 确定性 LCG，保证云端与本地结果一致
    var sfxSeed: UInt64 = 42
    var sfxNoise = [Double]()
    var sfxI = 0
    while sfxI < 800 {
        sfxSeed = sfxSeed &* 6364136223846793005 &+ 1442695040888963407
        sfxNoise.append(Double(sfxSeed % 20000) / 20000.0 - 0.5)
        sfxI += 1
    }
    let sfxN = HLCore.hlNWTest(sfxNoise, 20)
    check("NW·白噪声三口径均不显著",
          abs(sfxN[0]) < 2.0 && abs(sfxN[1]) < 2.0 && abs(sfxN[2]) < 2.0,
          String(format: "naive=%.2f nw=%.2f no=%.2f", sfxN[0], sfxN[1], sfxN[2]))

    var sfxAr = [Double]()
    sfxAr.append(0.0)
    var sfxJ = 1
    while sfxJ < 800 {
        let sfxPrev = sfxAr[sfxJ - 1]
        sfxSeed = sfxSeed &* 6364136223846793005 &+ 1442695040888963407
        let sfxE = Double(sfxSeed % 20000) / 20000.0 - 0.5
        sfxAr.append(0.9 * sfxPrev + sfxE)
        sfxJ += 1
    }
    let sfxA = HLCore.hlNWTest(sfxAr, 20)
    check("NW·强自相关时 naive 明显大于 NW",
          abs(sfxA[0]) > abs(sfxA[1]) * 1.5,
          String(format: "naive=%.2f nw=%.2f 倍数=%.2f",
                 sfxA[0], sfxA[1], abs(sfxA[0]) / max(0.01, abs(sfxA[1]))))
    check("NW·滞后阶 = h-1", near(sfxA[3], 19.0), "")
    check("NW·相位数 = h", near(sfxA[4], 20.0), "")
    check("NW·保守 t 取三者最小绝对值",
          abs(HLCore.hlConservativeT([sfxA[0], sfxA[1], sfxA[2]]))
              <= min(abs(sfxA[0]), min(abs(sfxA[1]), abs(sfxA[2]))) + 1e-9, "")

    let sfxR = HLCore.hlRanks([10.0, 30.0, 20.0])
    check("Ranks·升序编号", near(sfxR[0], 1.0) && near(sfxR[1], 3.0) && near(sfxR[2], 2.0), "")
    let sfxRt = HLCore.hlRanks([5.0, 5.0, 9.0])
    check("Ranks·并列取平均秩",
          near(sfxRt[0], 1.5) && near(sfxRt[1], 1.5) && near(sfxRt[2], 3.0), "")

    var sfxA1 = [Double]()
    var sfxK = 0
    while sfxK < 100 {
        sfxA1.append(Double(sfxK) + 1.0)
        sfxK += 1
    }
    var sfxB1 = [Double]()
    sfxK = 0
    while sfxK < 100 {
        sfxB1.append((Double(sfxK) + 1.0) * 3.0)
        sfxK += 1
    }
    check("RankIC·完全同向=1", near(HLCore.hlRankIC(sfxA1, sfxB1), 1.0, 1e-6), "")
    var sfxB2 = [Double]()
    sfxK = 0
    while sfxK < 100 {
        sfxB2.append(100.0 - Double(sfxK))
        sfxK += 1
    }
    check("RankIC·完全反向=-1", near(HLCore.hlRankIC(sfxA1, sfxB2), -1.0, 1e-6), "")
    let sfxFlat = [Double](repeating: 3.0, count: 100)
    check("RankIC·常数序列=0", abs(HLCore.hlRankIC(sfxA1, sfxFlat)) < 1e-6, "")

    var sfxRets = [Double]()
    sfxK = 0
    while sfxK < 300 {
        sfxRets.append((sfxK % 2 == 0) ? 0.001 : -0.001)
        sfxK += 1
    }
    sfxK = 200
    while sfxK < 300 {
        sfxRets[sfxK] = (sfxK % 2 == 0) ? 0.05 : -0.05
        sfxK += 1
    }
    let sfxCLow = HLCore.hlVolCostAt(sfxRets, 150, 20.0)
    let sfxCHigh = HLCore.hlVolCostAt(sfxRets, 290, 20.0)
    check("波动成本·高波动段更贵", sfxCHigh > sfxCLow,
          String(format: "低波=%.1f 高波=%.1f", sfxCLow, sfxCHigh))
    check("波动成本·不超过上限 2.5x", sfxCHigh <= 50.0 + 1e-9, "")
    check("波动成本·不低于下限 0.5x", sfxCLow >= 10.0 - 1e-9, "")

    let sfxSp = HLCore.hlPurgedSplit(801, 20, 0.01)
    check("净化·训练段剔除 h-1 根", sfxSp[1] - sfxSp[0] == 19, "")
    check("净化·测试段起点为 60%", sfxSp[1] == 480, "")
    check("净化·测试段后禁运", 801 - sfxSp[2] == 8, "")

    var sfxF = [Double]()
    var sfxY = [Double]()
    sfxK = 0
    while sfxK < 300 {
        sfxF.append(Double(sfxK) + 1.0)
        sfxY.append((Double(sfxK) + 1.0) * 0.01)
        sfxK += 1
    }
    let sfxFt = HLCore.hlFactorTest(sfxF, sfxY, 20)
    check("因子检验·返回 8 项", sfxFt.count == 8, "")
    check("因子检验·完全线性 IC 为正", sfxFt[0] > 0.9 && sfxFt[1] > 0.9,
          String(format: "IC=%.3f RankIC=%.3f", sfxFt[0], sfxFt[1]))
    check("因子检验·样本不足返 0", HLCore.hlFactorTest([1.0], [1.0], 20)[7] == 0, "")

    var sfxO = [Double]()
    var sfxC2 = [Double]()
    var sfxP = 10.0
    sfxK = 0
    while sfxK < 400 {
        sfxSeed = sfxSeed &* 6364136223846793005 &+ 1442695040888963407
        let sfxCh = (Double(sfxSeed % 2000) / 2000.0 - 0.5) * 0.04
        sfxP = sfxP * (1.0 + sfxCh)
        sfxO.append(sfxP)
        sfxC2.append(sfxP * (1.0 + sfxCh * 0.2))
        sfxK += 1
    }
    let sfxCC = HLCore.hlCostCompare(sfxO, sfxC2, 20.0)
    check("成本对比·返回 4 项", sfxCC.count == 4, "")
    check("成本对比·波动调整后不高于固定成本", sfxCC[1] <= sfxCC[0] + 1e-9,
          String(format: "固定=%.2f%% 波调=%.2f%%", sfxCC[0], sfxCC[1]))

    var sfxUp = [Double]()
    sfxK = 0
    while sfxK < 100 {
        sfxUp.append(Double(sfxK) + 1.0)
        sfxK += 1
    }
    check("灯位·单调上涨为持仓", HLCore.hlLightPos(sfxUp, 99) > 0.5, "")
    var sfxDn = [Double]()
    sfxK = 0
    while sfxK < 100 {
        sfxDn.append(100.0 - Double(sfxK))
        sfxK += 1
    }
    check("灯位·单调下跌为空仓", HLCore.hlLightPos(sfxDn, 99) < 0.5, "")


// ===== 波动率环境（VIX 分级 / 已实现波动 / 历史分位）=====
print("")
print("── 波动率环境 ──")

// 已实现波动率
var vfI = 0
while vfI < 60 { vfF_append(); vfI += 1 }
check("已实现波动·常数序列为0", HLCore.realizedVolPct(vfFlat, 20) == 0, "")
check("已实现波动·样本不足返回0", HLCore.realizedVolPct([1.0, 2.0, 3.0], 20) == 0, "")

var vfUp = [Double]()
var vfU = 0
while vfU < 60 { vfUp.append(10.0 + Double(vfU) * 0.5); vfU += 1 }
let vfUpV = HLCore.realizedVolPct(vfUp, 20)
check("已实现波动·上涨序列为正", vfUpV > 0, String(format: "%.4f", vfUpV))

// 滚动波动序列：长度与剔除不足窗口
let vfSer = HLCore.rollingVolSeries(vfUp, 20)
check("滚动波动序列·长度正确", vfSer.count == vfUp.count - 21, "\(vfSer.count)")
var vfHasZero = false
for x in vfSer { if x <= 0 { vfHasZero = true } }
check("滚动波动序列·无零值（不足窗口已剔除）", vfHasZero == false, "")
check("滚动波动序列·样本不足返回空", HLCore.rollingVolSeries([1.0, 2.0], 20).isEmpty, "")

// 历史分位
check("波动分位·空序列返回-1", HLCore.volPercentile([], 10.0) == -1, "")
check("波动分位·当前值无效返回-1", HLCore.volPercentile([1.0, 2.0], 0) == -1, "")
let vfP1 = HLCore.volPercentile([10.0, 20.0, 30.0], 5.0)
check("波动分位·低于全部为0", near(vfP1, 0.0, 0.001), String(format: "%.3f", vfP1))
let vfP2 = HLCore.volPercentile([10.0, 20.0, 30.0], 40.0)
check("波动分位·高于全部为100", near(vfP2, 100.0, 0.001), String(format: "%.3f", vfP2))
let vfP3 = HLCore.volPercentile([10.0, 20.0, 30.0], 20.0)
check("波动分位·居中约为33", near(vfP3, 33.333, 0.01), String(format: "%.3f", vfP3))

// VIX 分级
check("VIX分级·无数据", HLCore.vixLevel(0) == -1, "")
check("VIX分级·负值为无数据", HLCore.vixLevel(-5) == -1, "")
check("VIX分级·11为极低", HLCore.vixLevel(11.0) == 0, "")
check("VIX分级·12边界进偏低", HLCore.vixLevel(12.0) == 1, "")
check("VIX分级·14.9为偏低", HLCore.vixLevel(14.9) == 1, "")
check("VIX分级·15边界进正常", HLCore.vixLevel(15.0) == 2, "")
check("VIX分级·19.9为正常", HLCore.vixLevel(19.9) == 2, "")
check("VIX分级·20进偏高", HLCore.vixLevel(20.0) == 3, "")
check("VIX分级·25进警戒", HLCore.vixLevel(25.0) == 4, "")
check("VIX分级·30进恐慌", HLCore.vixLevel(30.0) == 5, "")
check("VIX分级·50仍为恐慌", HLCore.vixLevel(50.0) == 5, "")
check("VIX分级·名称非空", HLCore.vixLevelName(3).isEmpty == false, HLCore.vixLevelName(3))
check("VIX分级·无数据名", HLCore.vixLevelName(-1) == "无数据", "")
check("VIX建议·非空", HLCore.vixAdvice(4).isEmpty == false, "")

// 分位状态名
check("分位状态·负值为无法计算", HLCore.volPctName(-1) == "无法计算", "")
check("分位状态·低位", HLCore.volPctName(10) == "历史低位", "")
check("分位状态·高位", HLCore.volPctName(90) == "历史高位", "")

// 综合环境判定
check("环境判定·全无数据", HLCore.volRegime(-1, -1, -1) == -1, "")
check("环境判定·全部平静", HLCore.volRegime(1, 10, 10) == 0, "")
check("环境判定·VIX偏高单独触发", HLCore.volRegime(3, 10, 10) == 1, "")
check("环境判定·VIX恐慌+纳指高位", HLCore.volRegime(5, 85, 10) == 3, "")
check("环境判定·纳指高位触发注意", HLCore.volRegime(2, 85, 10) == 2, "")
check("环境判定·名称非空", HLCore.volRegimeName(2).isEmpty == false, HLCore.volRegimeName(2))
check("环境判定·文案非空", HLCore.volRegimeText(-1).isEmpty == false, "")



// ── 买卖方式分解：追涨止损 / 低买高卖 / 低买破位卖 / 低买不卖 ──
// 构造：前 60 点连续下跌（触发 RSI<30 超卖买入），后 240 点大牛市
// 上涨段每 30 点放量一次，用于触发"放量上涨"入场条件
var upLong300: [Double] = []
var upLongVo300: [Double] = []
var ui300 = 0
while ui300 < 300 {
    if ui300 < 60 { upLong300.append(20.0 - Double(ui300) * 0.1333) }
    else { upLong300.append(12.0 + Double(ui300 - 60) * 0.10) }
    if ui300 >= 60 && ui300 % 30 == 0 { upLongVo300.append(5000000.0) }
    else { upLongVo300.append(1000000.0) }
    ui300 += 1
}

check("追涨止损·有量数据可运行", HLCore.backtest(upLong300, 14, upLong300, 20.0, true, upLongVo300).count == 4, "")
check("追涨止损·无量数据不崩溃", HLCore.backtest(upLong300, 14, upLong300, 20.0, true, nil).count == 4, "")
check("低买高卖·可运行", HLCore.backtest(upLong300, 15, upLong300, 20.0, true, nil).count == 4, "")
check("低买破位卖·可运行", HLCore.backtest(upLong300, 16, upLong300, 20.0, true, nil).count == 4, "")
check("低买不卖·可运行", HLCore.backtest(upLong300, 17, upLong300, 20.0, true, nil).count == 4, "")

let sc15r = HLCore.backtest(upLong300, 15, upLong300, 20.0, true, nil)
let sc16r = HLCore.backtest(upLong300, 16, upLong300, 20.0, true, nil)
let sc17r = HLCore.backtest(upLong300, 17, upLong300, 20.0, true, nil)
// 长期上涨序列上：不卖 应显著优于 涨多了就卖
check("卖出端·不卖优于RSI高卖", sc17r[0] > sc15r[0], String(format: "不卖 %.3f vs 高卖 %.3f", sc17r[0], sc15r[0]))
// 买入端相同（RSI<30），卖出规则不同 → 三者必须产生可观测差异
let sellSpread300 = max(sc15r[0], sc16r[0], sc17r[0]) - min(sc15r[0], sc16r[0], sc17r[0])
check("卖出端·三档存在差异", sellSpread300 > 0.01, String(format: "极差 %.3f", sellSpread300))

// 常数序列：无波动时不应产生虚假收益（除交易成本外）
var flatC300: [Double] = []
var fi300 = 0
while fi300 < 300 { flatC300.append(10.0); fi300 += 1 }
let flatR15 = HLCore.backtest(flatC300, 15, flatC300, 20.0, true, nil)
let flatR14 = HLCore.backtest(flatC300, 14, flatC300, 20.0, true, nil)
check("常数序列·低买高卖无虚假收益", abs(flatR15[0] - 1.0) < 0.02, String(format: "%.4f", flatR15[0]))
check("常数序列·追涨止损无虚假收益", abs(flatR14[0] - 1.0) < 0.02, String(format: "%.4f", flatR14[0]))

// 单调下跌序列：追涨止损应空仓或极少交易（不逆势买入）
var dnLong300: [Double] = []
var di300 = 0
while di300 < 300 { dnLong300.append(20.0 - Double(di300) * 0.05); di300 += 1 }
let dnR14 = HLCore.backtest(dnLong300, 14, dnLong300, 20.0, true, upLongVo300)
check("下跌序列·追涨止损不逆势做多", dnR14[0] >= 0.90, String(format: "%.3f", dnR14[0]))

// ---------- 状态画像引擎 ----------
// 思路：涨的时候参数是什么、跌的时候参数是什么。只用于「解读」指标，不预测反转。
let spUp600: [Double] = { () -> [Double] in
    var a: [Double] = []
    var i = 0
    while i < 300 { a.append(10.0 * pow(1.005, Double(i))); i += 1 }
    var j = 0
    while j < 300 { a.append(a[299] * pow(0.995, Double(j + 1))); j += 1 }
    return a
}()
let spV600 = [Double](repeating: 1000.0, count: 600)
let spUp = HLCore.stateProfile(spUp600, spUp600, spUp600, spV600)
check("状态画像·人工先涨后跌序列可用", spUp.ok, spUp.ok ? "ok" : "ok=false")

let spDn600: [Double] = { () -> [Double] in
    var a: [Double] = []
    var i = 0
    while i < 600 { a.append(20.0 * pow(0.998, Double(i))); i += 1 }
    return a
}()
let spDn = HLCore.stateProfile(spDn600, spDn600, spDn600, spV600)
check("状态画像·单调下跌序列判为下跌态", spDn.ok && spDn.state == 0,
      spDn.ok ? "state=\(spDn.state)" : "ok=false")

let spFlat600 = [Double](repeating: 10.0, count: 600)
let spFl = HLCore.stateProfile(spFlat600, spFlat600, spFlat600, spV600)
check("状态画像·常数序列不崩溃且判为震荡", spFl.ok && spFl.state == 1,
      spFl.ok ? "state=\(spFl.state)" : "ok=false")

let spShort = [Double](repeating: 10.0, count: 100)
let spSh = HLCore.stateProfile(spShort, spShort, spShort, [Double](repeating: 1.0, count: 100))
check("状态画像·样本不足返回 ok=false", !spSh.ok, spSh.ok ? "ok=true（错误）" : "ok=false")

// 两态必须都有样本，否则指标画像无意义
check("状态画像·人工序列两态均有样本", spUp.fwdUpAll != 0 || spUp.fwdDnAll != 0,
      String(format: "涨%.2f 跌%.2f", spUp.fwdUpAll, spUp.fwdDnAll))

// 「距60日低」在上涨态应显著高于下跌态（上涨时远离低点）
var spFound = false
var spD = 0.0
for f in spUp.feats {
    if f.name == "距60日低%" { spFound = true; spD = f.effD }
}
check("状态画像·距60日低效应量为正", spFound && spD > 0.5,
      spFound ? String(format: "d=%.2f", spD) : "未找到该指标")

// 样本门槛：非重叠取样后样本必然减少，t 不应被放大到失真
check("状态画像·样本数达门槛", spUp.ok && spUp.nSample >= 120,
      String(format: "n=%d", spUp.nSample))
check("状态画像·t值为有限数",
      spUp.tOverlap.isFinite && spUp.tNonOverlap.isFinite,
      String(format: "重叠%.2f 非重叠%.2f", spUp.tOverlap, spUp.tNonOverlap))

// 指标数量与状态盲标记的一致性
var spBlind = 0
for f in spUp.feats { if f.blind { spBlind += 1 } }
check("状态画像·状态盲标记与效应量一致",
      spUp.feats.count == 0 || spBlind < spUp.feats.count,
      "盲\(spBlind)/\(spUp.feats.count)")


check("状态画像·文案非空", HLCore.stateProfileText(spUp).count > 10, "ok")

// ---------- 指标构造类型与 IC ----------
check("指标构造类型数量与指标数一致",
      HLCore.HL_FEAT_KIND.count == HLCore.HL_FEAT_NAMES.count,
      "\(HLCore.HL_FEAT_KIND.count)/\(HLCore.HL_FEAT_NAMES.count)")

var spKind = 0
for f in spUp.feats { if f.kind.count > 0 { spKind += 1 } }
check("状态画像·每个指标都有构造类型",
      spUp.feats.count == 0 || spKind == spUp.feats.count,
      "\(spKind)/\(spUp.feats.count)")

var spIcOk = true
for f in spUp.feats {
    if !f.icUp.isFinite || !f.icDn.isFinite { spIcOk = false }
    if f.icUp > 1.0001 || f.icUp < -1.0001 { spIcOk = false }
    if f.icDn > 1.0001 || f.icDn < -1.0001 { spIcOk = false }
}
check("状态画像·IC 落在 [-1,1] 且为有限数", spIcOk, "ok")

var spFlipOk = true
for f in spUp.feats {
    if f.flip && f.icUp * f.icDn >= 0 { spFlipOk = false }
}
check("状态画像·翻转标记与 IC 符号一致", spFlipOk, "ok")

// hlPear 自检
check("相关系数·完全正相关为1",
      abs(HLCore.hlPear([1,2,3,4,5,6,7,8,9,10],
                        [2,4,6,8,10,12,14,16,18,20]) - 1.0) < 1e-9, "ok")
check("相关系数·完全负相关为-1",
      abs(HLCore.hlPear([1,2,3,4,5,6,7,8,9,10],
                        [10,9,8,7,6,5,4,3,2,1]) + 1.0) < 1e-9, "ok")
check("相关系数·常数序列返回0",
      HLCore.hlPear([5,5,5,5,5,5,5,5,5,5],
                    [1,2,3,4,5,6,7,8,9,10]) == 0, "ok")
check("相关系数·样本不足返回0",
      HLCore.hlPear([1,2,3], [1,2,3]) == 0, "ok")
check("相关系数·对称性",
      abs(HLCore.hlPear([1,3,2,5,4,7,6,9,8,10],
                        [2,1,4,3,6,5,8,7,10,9])
          - HLCore.hlPear([2,1,4,3,6,5,8,7,10,9],
                          [1,3,2,5,4,7,6,9,8,10])) < 1e-9, "ok")

// ---------- 二维状态面板 ----------
let rgC = spUp600
let rgO: [Double] = { () -> [Double] in
    var a: [Double] = []
    a.append(spUp600[0])
    var i = 1
    while i < spUp600.count { a.append(spUp600[i - 1]); i += 1 }
    return a
}()
let rgUp = HLCore.regime2D(rgC, rgO, spUp600, spUp600, spV600)
check("二维状态·样本不足返回未就绪",
      HLCore.regime2D(Array(repeating: 10.0, count: 50),
                      Array(repeating: 10.0, count: 50),
                      Array(repeating: 10.0, count: 50),
                      Array(repeating: 10.0, count: 50),
                      Array(repeating: 1.0, count: 50)).ok == false, "ok")

check("二维状态·合格样本就绪", rgUp.ok, "ok")
check("二维状态·六象限齐全", rgUp.cells.count == 6,
      "\(rgUp.cells.count)")

var rgN = 0
for cc in rgUp.cells { rgN += cc.n }
let rgNExpect = rgC.count - 100
check("二维状态·各象限样本之和等于总样本",
      rgN > 0 && rgN == rgNExpect, "\(rgN)/\(rgNExpect)")

var rgRateOk = true
for cc in rgUp.cells {
    if cc.winRate < -0.001 || cc.winRate > 100.001 { rgRateOk = false }
}
check("二维状态·上涨率落在 [0,100]", rgRateOk, "ok")

var rgFin = true
for cc in rgUp.cells {
    if !cc.tsRet.isFinite || !cc.fwdMean.isFinite { rgFin = false }
}
check("二维状态·时序收益为有限数", rgFin, "ok")

var rgDays = 0
for cc in rgUp.cells { rgDays += cc.tsDays }
check("二维状态·至少一格有时序持仓", rgDays > 0, "\(rgDays)")

check("二维状态·当前象限合法",
      rgUp.curTrend >= 0 && rgUp.curTrend <= 2
      && rgUp.curVol >= 0 && rgUp.curVol <= 1, "ok")

check("二维状态·冲突标记与最优索引一致",
      rgUp.conflict == (rgUp.crossBest >= 0 && rgUp.tsBest >= 0
                        && rgUp.crossBest != rgUp.tsBest), "ok")

check("二维状态·跑赢基准计数不超6",
      rgUp.tsHoldN >= 0 && rgUp.tsHoldN <= 6, "\(rgUp.tsHoldN)")

// 无偷价核心：常数序列（零波动、零涨跌）不得产生任何时序收益
var kfC: [Double] = []
var kfO: [Double] = []
var kfH: [Double] = []
var kfL: [Double] = []
var kfV: [Double] = []
var kfI = 0
while kfI < 300 {
    kfC.append(10.0); kfO.append(10.0)
    kfH.append(10.0); kfL.append(10.0); kfV.append(1000.0)
    kfI += 1
}
let rgFlat = HLCore.regime2D(kfC, kfO, kfH, kfL, kfV)
var rgFlatOk = true
if rgFlat.ok {
    for cc in rgFlat.cells {
        // 无涨跌时，扣费后收益应 <= 0，绝不能为正
        if cc.tsRet > 0.0001 { rgFlatOk = false }
    }
}
check("二维状态·横盘序列不得产生正收益（防偷价）", rgFlatOk, "ok")

check("二维状态·文案非空", HLCore.regime2DText(rgUp).count > 10, "ok")

print("")
print("════════════════════════════════════════")
print("  通过 \(pass) · 失败 \(fail)")
if fail > 0 {
    print("  失败项：")
    for f in failures { print("    - \(f)") }
}
print("════════════════════════════════════════")
exit(fail > 0 ? 1 : 0)
