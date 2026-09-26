import SwiftUI

// MARK: - 颜色

extension Color {
    static let bg = Color(red: 0.043, green: 0.051, blue: 0.071)
    static let card = Color(red: 0.078, green: 0.094, blue: 0.125)
    static let card2 = Color(red: 0.106, green: 0.125, blue: 0.161)
    static let line = Color(red: 0.145, green: 0.169, blue: 0.212)
    static let txt = Color(red: 0.902, green: 0.914, blue: 0.933)
    static let dim = Color(red: 0.545, green: 0.576, blue: 0.639)
    static let dim2 = Color(red: 0.373, green: 0.408, blue: 0.471)
    static let up = Color(red: 0.0, green: 0.839, blue: 0.561)
    static let down = Color(red: 1.0, green: 0.302, blue: 0.369)
    static let warn = Color(red: 1.0, green: 0.69, blue: 0.125)
    static let accent = Color(red: 0.302, green: 0.624, blue: 1.0)
}

extension Signal {
    var color: Color {
        switch self {
        case .red: return .down
        case .yellow: return .warn
        case .green: return .up
        case .none: return Color(white: 0.42)
        }
    }
}

// MARK: - 卡片

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.line, lineWidth: 1)
                    )
            )
    }
}

// MARK: - 数据行

struct DataRow: View {
    let label: String
    let value: String
    var color: Color = .txt
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 12.5)).foregroundColor(.dim)
            Spacer()
            Text(value).font(.system(size: 13, weight: .semibold)).foregroundColor(color)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - 键值格

struct StatBox: View {
    let key: String
    let value: String
    var color: Color = .txt
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(key).font(.system(size: 10)).foregroundColor(.dim2)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(.system(size: 15, weight: .bold)).foregroundColor(color)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.card2))
    }
}

// MARK: - 信号灯

struct SignalLamp: View {
    let signal: Signal
    var size: CGFloat = 54
    @State private var glow = false

    var body: some View {
        ZStack {
            Circle()
                .fill(signal.color)
                .frame(width: size, height: size)
                .shadow(color: signal.color.opacity(glow ? 0.85 : 0.4),
                        radius: glow ? 16 : 8)
            Text(signal.title)
                .font(.system(size: size * 0.26, weight: .bold))
                .foregroundColor(.white)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }
}

// MARK: - 提示条

struct Banner: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.3), lineWidth: 1))
            )
    }
}

// MARK: - 格式化

func fmt(_ v: Double?, _ d: Int = 3) -> String {
    guard let v = v, v.isFinite else { return "—" }
    return String(format: "%.\(d)f", v)
}
func fmtPct(_ v: Double?, _ d: Int = 2) -> String {
    guard let v = v, v.isFinite else { return "—" }
    return (v >= 0 ? "+" : "") + String(format: "%.\(d)f%%", v)
}
func pctColor(_ v: Double?) -> Color {
    guard let v = v else { return .dim }
    return v >= 0 ? .up : .down
}
