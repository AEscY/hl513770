import SwiftUI

struct WatchView: View {
    @EnvironmentObject var vm: MarketViewModel
    @EnvironmentObject var store: Store

    @State private var input: String = ""
    @State private var message: String = ""
    @State private var msgColor: Color = .dim
    @State private var isAdding = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // 自选列表
                Card {
                    HStack {
                        Text("我的自选").font(.system(size: 12, weight: .bold)).foregroundColor(.dim)
                        Spacer()
                        Text("\(store.watchList.count) 个").font(.system(size: 10)).foregroundColor(.dim2)
                    }
                    ForEach(store.watchList) { w in
                        HStack(spacing: 9) {
                            Button {
                                store.currentCode = w.code
                            } label: {
                                HStack(spacing: 9) {
                                    Circle().fill(w.signal.color).frame(width: 9, height: 9)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(w.name).font(.system(size: 13))
                                            .foregroundColor(store.currentCode == w.code ? .accent : .txt)
                                        Text(w.code).font(.system(size: 9.5)).foregroundColor(.dim2)
                                    }
                                    Spacer()
                                    Text(fmt(w.price)).font(.system(size: 13))
                                    Text(fmtPct(w.changePct))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(pctColor(w.changePct))
                                        .frame(width: 62, alignment: .trailing)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            if store.watchList.count > 1 {
                                Button {
                                    store.remove(code: w.code)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.down.opacity(0.8)).font(.system(size: 17))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }

                // 添加
                Card {
                    Text("添加标的").font(.system(size: 12, weight: .bold)).foregroundColor(.dim)
                    HStack(spacing: 8) {
                        TextField("输入 6 位代码，如 513770", text: $input)
                            .keyboardType(.numbersAndPunctuation)
                            .font(.system(size: 14))
                            .padding(9)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Color.card2))
                            .foregroundColor(.txt)
                        Button {
                            addByCode()
                        } label: {
                            Text(isAdding ? "…" : "添加")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(RoundedRectangle(cornerRadius: 9).fill(Color.accent))
                        }
                        .disabled(isAdding)
                    }
                    if !message.isEmpty {
                        Text(message).font(.system(size: 11)).foregroundColor(msgColor)
                            .padding(.top, 5)
                    }
                    Text("输入 6 位代码会联网验证并自动获取真实名称。原生 App 不受跨域限制，比网页版能取到更多数据源。")
                        .font(.system(size: 10)).foregroundColor(.dim2).padding(.top, 4)
                }

                // 快捷
                Card {
                    Text("快捷添加").font(.system(size: 12, weight: .bold)).foregroundColor(.dim)
                    let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                    LazyVGrid(columns: cols, spacing: 8) {
                        ForEach(Presets.quick, id: \.code) { item in
                            Button {
                                store.add(code: item.code, name: item.name)
                                store.currentCode = item.code
                            } label: {
                                Text(item.name)
                                    .font(.system(size: 11))
                                    .foregroundColor(.txt)
                                    .lineLimit(1).minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.card2))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.top, 5)
                }

                // 数据信息
                Card {
                    Text("数据").font(.system(size: 12, weight: .bold)).foregroundColor(.dim)
                    DataRow(label: "当前标的", value: store.currentCode)
                    DataRow(label: "历史天数", value: "\(vm.candles.count) 天")
                    DataRow(label: "最后交易日", value: vm.candles.last?.date ?? "—")
                    Button {
                        vm.load(code: store.currentCode, force: true)
                        vm.refreshWatchList()
                        vm.loadBrief()
                    } label: {
                        Text("刷新全部数据")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Color.accent))
                    }
                    .padding(.top, 6)
                    Text("行情来自公开接口，仅供个人参考。\n本工具仅为纪律辅助，不构成投资建议。市场有风险，本金可能亏损。")
                        .font(.system(size: 10)).foregroundColor(.dim2).padding(.top, 6)
                }
            }
            .padding(10)
        }
        .background(Color.bg)
    }

    private func addByCode() {
        guard let code = CodeUtil.fromSix(input) else {
            message = "请输入 6 位数字代码"; msgColor = .down; return
        }
        if store.watchList.contains(where: { $0.code == code }) {
            message = "已在自选中"; msgColor = .warn
            store.currentCode = code
            return
        }
        isAdding = true
        message = "正在验证 \(code)…"; msgColor = .dim
        QuoteService.shared.fetchQuotes([code]) { map in
            isAdding = false
            if let q = map[code] {
                store.add(code: code, name: q.name)
                store.currentCode = code
                message = "已添加：\(q.name)"; msgColor = .up
                input = ""
            } else {
                message = "未找到该代码，请检查"; msgColor = .down
            }
        }
    }
}
