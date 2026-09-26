import SwiftUI

@main
struct HongLvdengApp: App {
    @StateObject private var store = Store()
    @StateObject private var vm = MarketViewModel()

    init() {
        // 深色外观
        UINavigationBar.appearance().barTintColor = UIColor(red: 0.043, green: 0.051, blue: 0.071, alpha: 1)
        UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: UIColor.white]
        UITableView.appearance().backgroundColor = UIColor(red: 0.043, green: 0.051, blue: 0.071, alpha: 1)
        UIScrollView.appearance().bounces = true
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
