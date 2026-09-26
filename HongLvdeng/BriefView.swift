import SwiftUI

struct BriefView: View {
    @EnvironmentObject var vm: MarketViewModel
    @EnvironmentObject var store: Store

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // 今日预案
                Card {
                    HStack {
                        Text("今日预案").font(.system(size: 12, weight: .bold)).foregroundColor(.dim)
                        Spacer()
                        Text(vm.candles.last?.date ?? "—")
                            .font(.system(size: 10)).foregroundColor(.dim2)
                    }
                    DataRow(label: "🔴 若跌破 \(fmt(vm.stopLoss))", value: "无条件减仓", color: .down)
                    DataRow(label: "🟡 若涨到 \(fmt(vm.nextYellow, 4)) 且站稳", value: "灯转黄，可小仓", color: .warn)
                    DataRow(label: "🟢 若涨到 \(fmt(vm.nextGreen, 4))", value: "灯转绿，可正常操作", color: .up)
                    DataRow(label: "⚪ 其余情况", value: "不动，等信号", color: .dim)
                    let pos = store.position(for: store.currentCode)
                    if pos.cost > 0, pos.qty > 0, let sl = vm.stopLoss {
                        DataRow(label: "📉 跌到止损，你的持仓将",
                                value: fmt((sl - vm.lastPrice) * pos.qty, 2) + " 元", color: .down)
                    }
                    Text("本页不做涨跌预测。它只把「涨到哪该做什么、跌到哪该做什么」提前定下来，避免临盘情绪化决策。")
                        .font(.system(size: 10)).foregroundColor(.dim2)
                        .padding(.top, 5)
                }

                // 隔夜外围
                Card {
                    Text("隔夜外围").font(.system(size: 12, weight: .bold)).foregroundColor(.dim)
                    ForEach(Presets.globalIdx, id: \.code) { item in
                        if let q = vm.globalQuotes[item.code] {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.name).font(.system(size: 12.5))
                                    Text(item.note).font(.system(size: 9.5)).foregroundColor(.dim2)
                                }
                                Spacer()
                                Text(fmt(q.price, q.price < 100 ? 3 : 2)).font(.system(size: 13, weight: .semibold))
                                Text(fmtPct(q.changePct))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(pctColor(q.changePct))
                                    .frame(width: 66, alignment: .trailing)
                            }
                            .padding(.vertical, 5)
                        }
                    }
                    if let hk = vm.globalQuotes["hkHSTECH"] {
                        Text("恒生科技隔夜 \(fmtPct(hk.changePct)) —— 与港股互联网 ETF 底层资产高度重合，参考价值最高。")
                            .font(.system(size: 10)).foregroundColor(.dim2).padding(.top, 4)
                    }
                }

                // 中概股 ADR
                Card {
                    Text("中概股 ADR · 隔夜").font(.system(size: 12, weight: .bold)).foregroundColor(.dim)
                    ForEach(Presets.adrs, id: \.code) { item in
                        if let q = vm.adrQuotes[item.code] {
                            HStack {
                                Text(item.name).font(.system(size: 12.5))
                                Spacer()
                                Text(fmt(q.price, 2)).font(.system(size: 12.5))
                                Text(fmtPct(q.changePct))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(pctColor(q.changePct))
                                    .frame(width: 66, alignment: .trailing)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    HStack(spacing: 8) {
                        StatBox(key: "加权估算", value: fmtPct(vm.adrEstimate),
                                color: pctColor(vm.adrEstimate))
                        StatBox(key: "覆盖权重", value: fmt(vm.adrCoverage, 1) + "%", color: .dim)
                    }
                    .padding(.top, 6)
                    Text("仅覆盖部分中概股权重，未含汇率、溢价折价及全部成分股。只作方向参考，不是开盘价预测。")
                        .font(.system(size: 10)).foregroundColor(.dim2).padding(.top, 4)
                }

                // 成分股体温计
                Card {
                    Text("成分股体温计 · 港股互联网").font(.system(size: 12, weight: .bold)).foregroundColor(.dim)
                    ForEach(Presets.holdings, id: \.code) { item in
                        if let q = vm.holdingQuotes[item.code] {
                            HStack {
                                Text(item.name).font(.system(size: 12.5))
                                Spacer()
                                Text(fmt(q.price, 2)).font(.system(size: 12.5))
                                Text(fmtPct(q.changePct))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(pctColor(q.changePct))
                                    .frame(width: 66, alignment: .trailing)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    if let e = vm.holdingEstimate {
                        Text("前十大成分股约 \(fmt(vm.holdingCoverage, 1))% 权重，加权方向 \(fmtPct(e))。")
                            .font(.system(size: 10.5)).foregroundColor(.dim).padding(.top, 5)
                    }
                }

                // 自选一览
                Card {
                    Text("自选状态一览").font(.system(size: 12, weight: .bold)).foregroundColor(.dim)
                    ForEach(store.watchList) { w in
                        HStack(spacing: 8) {
                            Circle().fill(w.signal.color).frame(width: 8, height: 8)
                            Text(w.name).font(.system(size: 12.5))
                                .lineLimit(1)
                            Spacer()
                            Text(fmt(w.price)).font(.system(size: 12.5))
                            Text(fmtPct(w.changePct))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(pctColor(w.changePct))
                                .frame(width: 62, alignment: .trailing)
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
            .padding(10)
        }
        .background(Color.bg)
        .onAppear { vm.loadBrief() }
    }
}
