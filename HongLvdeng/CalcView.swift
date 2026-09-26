import SwiftUI

struct CalcView: View {
    @EnvironmentObject var vm: MarketViewModel
    @EnvironmentObject var store: Store

    @State private var costText: String = ""
    @State private var qtyText: String = ""
    @State private var addLots: String = "1"
    @State private var feeText: String = "0.05"
    @State private var sellHi: String = ""
    @State private var buyLo: String = ""
    @State private var tQty: String = "100"

    private var cost: Double { Double(costText) ?? 0 }
    private var qty: Double { Double(qtyText) ?? 0 }
    private var lots: Double { Double(addLots) ?? 0 }
    private var fee: Double { Double(feeText) ?? 0 }
    private var hiP: Double { Double(sellHi) ?? 0 }
    private var loP: Double { Double(buyLo) ?? 0 }
    private var tQ: Double { Double(tQty) ?? 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // 持仓
                Card {
                    Text("我的持仓").font(.system(size: 12, weight: .bold)).foregroundColor(.dim)
                    HStack(spacing: 8) {
                        field("成本价", $costText)
                        field("份数", $qtyText)
                    }
                    let mv = vm.lastPrice * qty
                    let pnl = (vm.lastPrice - cost) * qty
                    DataRow(label: "市值", value: fmt(mv, 2) + " 元")
                    DataRow(label: "盈亏", value: fmt(pnl, 2) + " 元",
                            color: pnl >= 0 ? .up : .down)
                    DataRow(label: "回本需涨",
                            value: cost > 0 ? fmt((cost / vm.lastPrice - 1) * 100, 1) + "%" : "—")
                }

                // 加仓摊薄
                Card {
                    Text("加仓摊薄").font(.system(size: 12, weight: .bold)).foregroundColor(.dim)
                    field("加仓手数（1手=100份）", $addLots)
                    let nq = qty + lots * 100
                    let nc = nq > 0 ? (cost * qty + vm.lastPrice * lots * 100) / nq : 0
                    DataRow(label: "加后成本", value: qty > 0 ? fmt(nc, 4) : "—")
                    let ob = cost > 0 ? (cost / vm.lastPrice - 1) * 100 : 0
                    let nb = nc > 0 ? (nc / vm.lastPrice - 1) * 100 : 0
                    let df = ob - nb
                    DataRow(label: "回本线",
                            value: (df >= 0 ? "降低 " : "提高 ") + fmt(abs(df), 1) + " 个点",
                            color: df >= 0 ? .up : .down)
                    let sl = vm.stopLoss ?? vm.periodLow
                    let ol = (sl - cost) * qty
                    let nl = (sl - nc) * nq
                    DataRow(label: "跌到止损位",
                            value: fmt(nl, 2) + " 元（" + (nl < ol ? "多亏 " + fmt(abs(nl - ol), 2) : "优于现在") + "）",
                            color: nl < ol ? .down : .up)
                    if vm.signal == .red {
                        Banner(text: "当前红灯，规则禁止加仓。摊薄虽让回本线降 \(fmt(df, 1)) 个点，但风险敞口从 \(fmt(qty, 0)) 份扩大到 \(fmt(nq, 0)) 份。",
                               color: .down)
                            .padding(.top, 6)
                    } else {
                        Banner(text: "当前非红灯，加仓在规则允许范围内。仍建议先确认站稳天数。", color: .up)
                            .padding(.top, 6)
                    }
                }

                // 做T
                Card {
                    Text("做 T（先卖后买）").font(.system(size: 12, weight: .bold)).foregroundColor(.dim)
                    HStack(spacing: 8) {
                        field("高抛价", $sellHi)
                        field("低吸价", $buyLo)
                    }
                    HStack(spacing: 8) {
                        field("份数", $tQty)
                        field("单边佣金", $feeText)
                    }
                    let net = (hiP - loP) * tQ - fee * 2
                    DataRow(label: "净收益", value: fmt(net, 2) + " 元",
                            color: net >= 0 ? .up : .down)
                    Text("当天必须买回。卖完没跌回来就认了，别追高买回。")
                        .font(.system(size: 10)).foregroundColor(.dim2).padding(.top, 4)
                }

                // 指标
                Card {
                    Text("技术指标").font(.system(size: 12, weight: .bold)).foregroundColor(.dim)
                    HStack(spacing: 8) {
                        StatBox(key: "RSI(6)", value: fmt(vm.rsi6, 1), color: rsiColor(vm.rsi14))
                        StatBox(key: "RSI(14)", value: fmt(vm.rsi14, 1), color: rsiColor(vm.rsi14))
                    }
                    if let b = vm.bollinger {
                        DataRow(label: "布林上轨 · 压力", value: fmt(b.up, 4), color: .down)
                        DataRow(label: "布林中轨 · MA20", value: fmt(b.mid, 4))
                        DataRow(label: "布林下轨 · 支撑", value: fmt(b.low, 4), color: .up)
                        DataRow(label: "带宽", value: fmt(b.width, 2) + "%")
                    }
                    DataRow(label: "ATR(14)", value: fmt(vm.atr, 4))
                    DataRow(label: "ATR 占现价",
                            value: (vm.atr != nil && vm.lastPrice > 0)
                                ? fmt(vm.atr! / vm.lastPrice * 100, 2) + "%" : "—")
                    DataRow(label: "20日年化波动率", value: fmt(vm.annualVol, 1) + "%")
                    DataRow(label: "日均振幅", value: fmt(vm.avgAmp, 2) + "%")
                }
            }
            .padding(10)
        }
        .background(Color.bg)
        .onAppear(perform: loadFromStore)
        .onChange(of: store.currentCode) { _ in loadFromStore() }
        .onChange(of: costText) { _ in saveToStore() }
        .onChange(of: qtyText) { _ in saveToStore() }
    }

    private func field(_ title: String, _ binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10)).foregroundColor(.dim2)
            TextField("", text: binding)
                .keyboardType(.decimalPad)
                .font(.system(size: 14))
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.card2))
                .foregroundColor(.txt)
        }
        .frame(maxWidth: .infinity)
    }

    private func rsiColor(_ v: Double?) -> Color {
        guard let v = v else { return .dim }
        return v < 30 ? .up : (v > 70 ? .down : .warn)
    }

    private func loadFromStore() {
        let p = store.position(for: store.currentCode)
        costText = p.cost > 0 ? String(format: "%g", p.cost) : ""
        qtyText = p.qty > 0 ? String(format: "%g", p.qty) : ""
        sellHi = String(format: "%.*f", 3, vm.lastPrice * 1.006)
        buyLo = String(format: "%.*f", 3, vm.lastPrice * 0.997)
    }

    private func saveToStore() {
        var p = Position()
        p.cost = cost
        p.qty = qty
        store.savePosition(p, for: store.currentCode)
    }
}
