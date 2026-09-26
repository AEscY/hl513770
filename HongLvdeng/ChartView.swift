import SwiftUI

/// 纯 SwiftUI Path 自绘，不依赖 Swift Charts（iOS 16+），iOS 15 可用
struct LineChart: View {
    let series: [Double]          // 主数据（收盘）
    let ma20: [Double?]
    let ma60: [Double?]
    let bands: [Signal]           // 底部信号色带

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let bandH: CGFloat = 12
            let plotH = h - bandH - 6
            let lo = series.min() ?? 0
            let hi = series.max() ?? 1
            let range = max(hi - lo, 1e-9)
            func x(_ i: Int) -> CGFloat { CGFloat(i) / CGFloat(max(series.count - 1, 1)) * w }
            func y(_ v: Double) -> CGFloat { (1 - CGFloat((v - lo) / range)) * plotH + 2 }

            ZStack {
                // 网格
                Path { p in
                    for g in 0...4 {
                        let yy = plotH * CGFloat(g) / 4 + 2
                        p.move(to: CGPoint(x: 0, y: yy))
                        p.addLine(to: CGPoint(x: w, y: yy))
                    }
                }
                .stroke(Color.line, lineWidth: 1)

                // 信号色带
                ForEach(Array(bands.indices), id: \.self) { idx in
                    Rectangle()
                        .fill(bands[idx].color.opacity(0.55))
                        .frame(width: w / CGFloat(max(bands.count, 1)) + 0.6, height: bandH)
                        .position(x: x(idx) + (w / CGFloat(max(bands.count, 1))) / 2,
                                  y: plotH + 4 + bandH / 2)
                }

                // MA20 / MA60
                maPath(ma20, plotH: plotH, w: w, lo: lo, range: range).stroke(Color.warn, lineWidth: 1.2)
                maPath(ma60, plotH: plotH, w: w, lo: lo, range: range).stroke(Color.accent, lineWidth: 1.2)

                // 收盘线
                Path { p in
                    for (i, v) in series.enumerated() {
                        if i == 0 { p.move(to: CGPoint(x: x(i), y: y(v))) }
                        else { p.addLine(to: CGPoint(x: x(i), y: y(v))) }
                    }
                }
                .stroke(Color.txt, lineWidth: 1.6)
            }
        }
    }

    private func maPath(_ arr: [Double?], plotH: CGFloat, w: CGFloat, lo: Double, range: Double) -> Path {
        Path { p in
            var started = false
            for (i, v) in arr.enumerated() {
                guard let v = v else { continue }
                let px = CGFloat(i) / CGFloat(max(arr.count - 1, 1)) * w
                let py = (1 - CGFloat((v - lo) / range)) * plotH + 2
                if !started { p.move(to: CGPoint(x: px, y: py)); started = true }
                else { p.addLine(to: CGPoint(x: px, y: py)) }
            }
        }
    }
}

/// 回测净值曲线
struct EquityChart: View {
    let holdCurve: [Double]
    let stratCurve: [Double]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let all = holdCurve + stratCurve
            let lo = all.min() ?? 0
            let hi = all.max() ?? 1
            let range = max(hi - lo, 1e-9)

            ZStack {
                Path { p in
                    let y1 = (1 - CGFloat((1 - lo) / range)) * h
                    p.move(to: CGPoint(x: 0, y: y1))
                    p.addLine(to: CGPoint(x: w, y: y1))
                }
                .stroke(Color.dim2, lineWidth: 1)

                curve(holdCurve, w: w, h: h, lo: lo, range: range).stroke(Color.down, lineWidth: 1.6)
                curve(stratCurve, w: w, h: h, lo: lo, range: range).stroke(Color.warn, lineWidth: 1.6)
            }
        }
    }

    private func curve(_ a: [Double], w: CGFloat, h: CGFloat, lo: Double, range: Double) -> Path {
        Path { p in
            for (i, v) in a.enumerated() {
                let px = CGFloat(i) / CGFloat(max(a.count - 1, 1)) * w
                let py = (1 - CGFloat((v - lo) / range)) * h
                if i == 0 { p.move(to: CGPoint(x: px, y: py)) }
                else { p.addLine(to: CGPoint(x: px, y: py)) }
            }
        }
    }
}

struct ChartView: View {
    @EnvironmentObject var vm: MarketViewModel

    var bands: [Signal] {
        vm.candles.enumerated().map { i, _ in
            let m20 = Indicators.ma(vm.closes, 20, at: i)
            let m60 = Indicators.ma(vm.closes, 60, at: i)
            return Indicators.signal(price: vm.closes[i], ma20: m20, ma60: m60)
        }
    }
    var ma20Series: [Double?] { vm.candles.indices.map { Indicators.ma(vm.closes, 20, at: $0) } }
    var ma60Series: [Double?] { vm.candles.indices.map { Indicators.ma(vm.closes, 60, at: $0) } }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Card {
                    Text("走势 · 信号色带").font(.system(size: 12, weight: .bold)).foregroundColor(.dim)
                    if vm.candles.isEmpty {
                        Text("加载中…").font(.system(size: 12)).foregroundColor(.dim)
                            .frame(height: 190)
                    } else {
                        LineChart(series: vm.closes, ma20: ma20Series, ma60: ma60Series, bands: bands)
                            .frame(height: 200)
                    }
                    HStack(spacing: 14) {
                        legend("红灯 禁止买", .down)
                        legend("黄灯 观望", .warn)
                        legend("绿灯 可操作", .up)
                    }
                    .padding(.top, 6)
                }

                Card {
                    Text("回测 · 本金 1 万").font(.system(size: 12, weight: .bold)).foregroundColor(.dim)
                    let bt = Indicators.backtest(vm.closes)
                    if vm.candles.count > 60 {
                        EquityChart(holdCurve: bt.curve, stratCurve: bt.stratCurve)
                            .frame(height: 140)
                    }
                    DataRow(label: "一直持有", value: fmtPct((bt.hold - 1) * 100, 1), color: .down)
                    DataRow(label: "红绿灯策略", value: fmtPct((bt.strat - 1) * 100, 1), color: .warn)
                    DataRow(label: "最大回撤（持有/策略）",
                            value: "\(fmt(bt.ddHold * 100, 1))% / \(fmt(bt.ddStrat * 100, 1))%")
                    Text("策略：红灯空仓、黄灯半仓、绿灯满仓，按昨日信号执行今日仓位。")
                        .font(.system(size: 10)).foregroundColor(.dim2).padding(.top, 4)
                }
            }
            .padding(10)
        }
        .background(Color.bg)
    }

    private func legend(_ t: String, _ c: Color) -> some View {
        HStack(spacing: 4) {
            Rectangle().fill(c).frame(width: 9, height: 9).cornerRadius(2)
            Text(t).font(.system(size: 10)).foregroundColor(.dim2)
        }
    }
}
