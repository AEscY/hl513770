import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: MarketViewModel
    @EnvironmentObject var store: Store
    @State private var tab: Int = 0
    @State private var clock = MarketClock.status()

    let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider().background(Color.line)
            TabView(selection: $tab) {
            BriefView()
                .tabItem { Label("简报", systemImage: "sunrise.fill") }
                .tag(0)
            SignalView()
                .tabItem { Label("信号", systemImage: "lightbulb.fill") }
                .tag(1)
            ChartView()
                .tabItem { Label("图表", systemImage: "chart.xyaxis.line") }
                .tag(2)
            CalcView()
                .tabItem { Label("计算", systemImage: "number") }
                .tag(3)
            WatchView()
                .tabItem { Label("自选", systemImage: "list.bullet") }
                .tag(4)
        }
        }
        .accentColor(.accent)
        .background(Color.bg.ignoresSafeArea())
        .onAppear {
            vm.store = store
            vm.load(code: store.currentCode)
            vm.loadBrief()
            vm.refreshWatchList()
        }
        .onChange(of: store.currentCode) { code in
            vm.load(code: code)
        }
        .onReceive(timer) { _ in
            clock = MarketClock.status()
            // 交易时段自动刷新
            let cal = Calendar.current
            let wd = cal.component(.weekday, from: Date())
            let h = cal.component(.hour, from: Date())
            let m = cal.component(.minute, from: Date())
            let t = h * 60 + m
            if wd >= 2 && wd <= 6 && ((t >= 570 && t < 690) || (t >= 780 && t < 900)) {
                vm.load(code: store.currentCode)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(clock.isLive ? Color.up : Color.dim)
                .frame(width: 7, height: 7)
            Text(clock.text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(clock.isLive ? .up : .dim)
            Spacer()
            if vm.isLoading {
                ProgressView().scaleEffect(0.7)
            } else {
                Text(store.watchList.first(where: { $0.code == store.currentCode })?.name ?? "")
                    .font(.system(size: 11)).foregroundColor(.dim)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Color.card)
    }
}
