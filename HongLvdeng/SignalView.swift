import SwiftUI

struct SignalView: View {
    @EnvironmentObject var vm: MarketViewModel
    @EnvironmentObject var store: Store

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // 灯
                Card {
                    HStack(spacing: 13) {
                        SignalLamp(signal: vm.signal)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(vm.signal.title + "灯")
                                .font(.system(size: 25, weight: .bold))
                            Text(vm.signal.desc).font(.system(size: 12)).foregroundColor(.dim)
                            if let q = vm.quote {
                                Text("\(fmt(q.change))  \(fmtPct(q.changePct))")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(pctColor(q.changePct))
                            }
                        }
                        Spacer()
                    }
                    Banner(text: actionText(), color: bannerColor())
                        .padding(.top, 9)
                }

                // 实时行情
                Card {
                    HStack {
                        Text("实时行情").font(.system(size: 12, weight: .bold)).foregroundColor(.dim)
                        Spacer()
                        Text(vm.quote == nil ? "离线" : "实时")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(vm.quote == nil ? .dim : .up)
                    }
                    HStack(spacing: 8) {
                        StatBox(key: "现价", value: fmt(vm.lastPrice), color: .txt)
                        StatBox(key: "涨跌幅", value: fmtPct(vm.quote?.changePct),
                                color: pctColor(vm.quote?.changePct))
                        StatBox(key: "昨收", value: fmt(vm.quote?.preClose), color: .dim)
                    }
                    .padding(.top, 7)
                    HStack(spacing: 8) {
                        StatBox(key: "今开", value: fmt(vm.quote?.open))
                        StatBox(key: "最高", value: fmt(vm.quote?.high))
                        StatBox(key: "最低", value: fmt(vm.quote?.low))
                    }
                    if let q = vm.quote, !q.time.isEmpty {
                        Text("数据时间 \(q.time)")
                            .font(.system(size: 10)).foregroundColor(.dim2)
                            .padding(.top, 6)
                    }
                }

                // 均线
                Card {
                    HStack {
                        Text("均线系统").font(.system(size: 12, weight: .bold)).foregroundColor(.dim)
                        Spacer()
                        Text(arrangeText()).font(.system(size: 10)).foregroundColor(.dim2)
                    }
                    DataRow(label: "MA5", value: fmt(vm.ma5, 4), color: maColor(vm.ma5))
                    DataRow(label: "MA20 · 短期生命线", value: fmt(vm.ma20, 4), color: maColor(vm.ma20))
                    DataRow(label: "MA60 · 中期生命线", value: fmt(vm.ma60, 4), color: maColor(vm.ma60))
                    DataRow(label: "MA120 · 长期趋势", value: fmt(vm.ma120, 4), color: maColor(vm.ma120))
                }

                // 变灯门槛
                Card {
                    Text("变灯门槛").font(.system(size: 12, weight: .bold)).foregroundColor(.dim)
                    HStack {
                        Text("时间").font(.system(size: 10)).foregroundColor(.dim2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("变黄需到").font(.system(size: 10)).foregroundColor(.dim2)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text("变绿需到").font(.system(size: 10)).foregroundColor(.dim2)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                    DataRow(label: "明日", value: "\(fmt(vm.nextYellow, 4))  →  \(fmt(vm.nextGreen, 4))",
                            color: .warn)
                    Text("明日 MA20 =（前19日收盘 + 明日价）/20。旧高价滚出窗口，门槛会自动下降——横着不动也可能被动变灯。")
                        .font(.system(size: 10)).foregroundColor(.dim2)
                        .padding(.top, 5)
                }

                // 关键价位
                Card {
                    Text("关键价位").font(.system(size: 12, weight: .bold)).foregroundColor(.dim)
                    DataRow(label: "🔴 止损参考（现价−2ATR）", value: fmt(vm.stopLoss), color: .down)
                    DataRow(label: "🟡 变黄位", value: fmt(vm.nextYellow, 4), color: .warn)
                    DataRow(label: "🟢 变绿位", value: fmt(vm.nextGreen, 4), color: .up)
                    let pos = store.position(for: store.currentCode)
                    DataRow(label: "⚪ 你的成本",
                            value: pos.cost > 0 ? fmt(pos.cost) : "未设置")
                    // 区间分位条
                    VStack(alignment: .leading, spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.card2).frame(height: 6)
                                Capsule().fill(LinearGradient(
                                    colors: [.down, .warn, .up],
                                    startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(0, geo.size.width * CGFloat(vm.percentile / 100)), height: 6)
                            }
                        }
                        .frame(height: 6)
                        Text("近一年区间 \(fmt(vm.percentile, 1))% 分位（低 \(fmt(vm.periodLow)) ~ 高 \(fmt(vm.periodHigh))）")
                            .font(.system(size: 10)).foregroundColor(.dim2)
                    }
                    .padding(.top, 6)
                }
            }
            .padding(10)
        }
        .background(Color.bg)
    }

    private func maColor(_ v: Double?) -> Color {
        guard let v = v else { return .dim }
        return vm.lastPrice >= v ? .up : .down
    }
    private func arrangeText() -> String {
        var parts: [String] = []
        if let a = vm.ma5, let b = vm.ma20 { parts.append(a > b ? "MA5>MA20" : "MA5<MA20") }
        if let a = vm.ma20, let b = vm.ma60 { parts.append(a > b ? "MA20>MA60" : "MA20<MA60") }
        return parts.joined(separator: " · ")
    }
    private func actionText() -> String {
        switch vm.signal {
        case .red:
            let gap = (vm.ma20 ?? 0) - vm.lastPrice
            return "只卖不买，禁止加仓。距 MA20 还差 \(fmt(gap * 1000, 1)) 厘。今天最该做的事是什么都不做。"
        case .yellow:
            return "反弹未确认，观望为主。站稳 3 天才算数，可小仓试探。"
        case .green:
            return "趋势转强，可正常操作。止损位 \(fmt(vm.stopLoss)) 别忘。"
        case .none:
            return "等待数据加载。"
        }
    }
    private func bannerColor() -> Color {
        switch vm.signal {
        case .red: return .down
        case .yellow: return .warn
        case .green: return .up
        case .none: return .dim
        }
    }
}
