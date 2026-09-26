import Foundation

/// 行情服务。
/// 关键：这是原生 App，用 URLSession 直接发请求，
/// 不受浏览器同源策略（CORS）限制 —— 网页版拿不到的接口这里都能取。
final class QuoteService {

    static let shared = QuoteService()

    /// 腾讯行情返回 GBK 编码，需要转成 NSStringEncoding
    static let gbkEncoding: String.Encoding = {
        let cf = CFStringEncodings.GB_18030_2000
        let ns = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cf.rawValue))
        return String.Encoding(rawValue: ns)
    }()

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 12
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    // MARK: - 实时行情

    /// 批量拉取实时行情（逗号分隔代码），主线程回调
    func fetchQuotes(_ codes: [String], completion: @escaping ([String: Quote]) -> Void) {
        guard !codes.isEmpty else { completion([:]); return }
        let list = codes.joined(separator: ",")
        guard let url = URL(string: "https://qt.gtimg.cn/q=" + list) else {
            completion([:]); return
        }
        session.dataTask(with: url) { data, _, err in
            guard let data = data, err == nil else {
                DispatchQueue.main.async { completion([:]) }
                return
            }
            let text = String(data: data, encoding: QuoteService.gbkEncoding)
                ?? String(data: data, encoding: .utf8)
                ?? ""
            var out: [String: Quote] = [:]
            // 形如 v_sh513770="1~名称~513770~0.333~0.334~...";
            for line in text.components(separatedBy: ";") {
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard t.hasPrefix("v_"), let eq = t.firstIndex(of: "=") else { continue }
                let key = String(t[t.index(t.startIndex, offsetBy: 2)..<eq])
                var body = String(t[t.index(after: eq)...])
                body = body.trimmingCharacters(in: CharacterSet(charactersIn: "\"\n\r "))
                let parts = body.components(separatedBy: "~")
                guard parts.count >= 35 else { continue }
                let price = Double(parts[3]) ?? 0
                guard price > 0 else { continue }
                let q = Quote(
                    code: key,
                    name: parts[1],
                    price: price,
                    preClose: Double(parts[4]) ?? 0,
                    open: Double(parts[5]) ?? 0,
                    high: Double(parts[33]) ?? 0,
                    low: Double(parts[34]) ?? 0,
                    time: parts.count > 30 ? parts[30] : ""
                )
                out[key] = q
            }
            DispatchQueue.main.async { completion(out) }
        }.resume()
    }

    // MARK: - 历史K线

    func fetchHistory(_ code: String, days: Int = 320, completion: @escaping ([Candle]) -> Void) {
        let primary = "https://web.ifzq.gtimg.cn/appstock/app/fqkline/get?param=\(code),day,,,\(days),qfq"
        let backup  = "https://web.ifzq.gtimg.cn/appstock/app/fqkline/get?param=\(code),day,,,250,qfq"
        requestKLine(primary, code: code) { r in
            if let r = r, !r.isEmpty { DispatchQueue.main.async { completion(r) }; return }
            self.requestKLine(backup, code: code) { r2 in
                DispatchQueue.main.async { completion(r2 ?? []) }
            }
        }
    }

    private func requestKLine(_ urlStr: String, code: String, completion: @escaping ([Candle]?) -> Void) {
        guard let url = URL(string: urlStr) else { completion(nil); return }
        session.dataTask(with: url) { data, _, err in
            guard let data = data, err == nil else { completion(nil); return }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let d = obj["data"] as? [String: Any],
                  let node = d[code] as? [String: Any] else { completion(nil); return }
            let raw = (node["qfqday"] as? [[Any]]) ?? (node["day"] as? [[Any]]) ?? []
            var out: [Candle] = []
            for item in raw {
                guard item.count >= 5,
                      let dt = item[0] as? String,
                      let o = Double("\(item[1])"),
                      let c = Double("\(item[2])"),
                      let h = Double("\(item[3])"),
                      let l = Double("\(item[4])"),
                      c > 0 else { continue }
                let short = dt.count >= 10 ? String(dt.suffix(5)) : dt
                out.append(Candle(date: short, open: o, high: h, low: l, close: c))
            }
            completion(out)
        }.resume()
    }
}
