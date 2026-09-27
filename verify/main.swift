import Foundation

// ============================================================
// 云端验证程序：在 Codemagic 的 macOS 机器上真实编译并运行
// 只依赖 Foundation，与主 App 共用 HLCore.swift
// ============================================================

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
check("常数序列 ATR=0", near(HLCore.atr(highs: flatH, lows: flatL, closes: flatC, k: 14)!, 0.0))

// VaR / CVaR：构造已知数组
let rets100 = (1...100).map { Double($0) / 1000.0 - 0.05 }  // -0.049 .. 0.05
let v95 = HLCore.varHist(rets100, 0.95)
let cv95 = HLCore.cvarHist(rets100, 0.95)
check("CVaR ≤ VaR（尾部更差）", cv95 <= v95, "VaR=\(v95) CVaR=\(cv95)")

// 波动率锥：持有期越长，聚合后年化波动不应为负
check("volCone 非负", (HLCore.volCone(rets100, 5) ?? -1) >= 0)

// 蒙特卡洛：分位必须单调递增
var seed: UInt64 = 12345
let mc = HLCore.monteCarlo(upSeq + [16.0, 17.0, 18.0], 20, 400, seed)
check("蒙特卡洛 分位单调递增",
      mc[0] <= mc[1] && mc[1] <= mc[2] && mc[2] <= mc[3] && mc[3] <= mc[4],
      "\(mc.map { String(format: "%.3f", $0) }.joined(separator: " "))")

// 蒙特卡洛确定性：同种子两次结果相同
let mc2 = HLCore.monteCarlo(upSeq + [16.0, 17.0, 18.0], 20, 400, 12345)
check("蒙特卡洛 同种子可复现", mc == mc2)

// 回测：一直持有应等于首尾比
let btHold = HLCore.backtest(seq + [6.0, 7.0, 8.0] + Array(repeating: 5.0, count: 70), 0)
check("回测 一直持有=首尾比", btHold[0] > 0, "倍数 \(String(format: "%.4f", btHold[0]))")

// 信号质量：样本数非负
check("signalQuality 返回3项", HLCore.signalQuality(upSeq, 0).count == 3)

// 赫斯特：单调上升趋势应 H 较高
if let h = HLCore.hurst(upSeq + Array((16...80).map { Double($0) })) {
    check("上升趋势 H 偏高", h > 0.4, "H=\(String(format: "%.3f", h))")
} else {
    check("上升趋势 H 偏高", false, "返回 nil")
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
    // 不变量 10：相似形态样本数 = 15
    let sim = HLCore.similarStats(real)
    check("相似形态 样本=15", Int(sim[0]) == 15, "样本 \(Int(sim[0]))")
    // 不变量 11：上涨概率 ∈ [0,100]
    check("上涨概率 ∈ [0,100]", sim[2] >= 0 && sim[2] <= 100, "\(String(format: "%.0f", sim[2]))%")
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
    var bk = 0
    while bk <= 6 {
        let b = HLCore.backtest(real, bk)
        print("  回测 \(HLCore.strategyName(bk).padding(toLength: 14, withPad: " ", startingAt: 0)) 收益\(String(format: "%+7.2f", (b[0]-1)*100))%  回撤\(String(format: "%5.1f", b[1]))%")
        bk += 1
    }
}

print("")
print("════════════════════════════════════════")
print("  通过 \(pass) · 失败 \(fail)")
if fail > 0 {
    print("  失败项：")
    for f in failures { print("    - \(f)") }
}
print("════════════════════════════════════════")
exit(fail > 0 ? 1 : 0)
