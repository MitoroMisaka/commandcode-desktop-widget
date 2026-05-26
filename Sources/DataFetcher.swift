import Foundation
import AppKit

@MainActor
class DataFetcher: ObservableObject {
    @Published var hourly: [HourBucket] = []
    @Published var summary: SummaryResp?
    @Published var credits: CreditsResp.C2?
    @Published var loading = false
    @Published var error: String?
    private var timer: Timer?
    
    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30*60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    func stop() { timer?.invalidate() }
    func refresh() { Task { await fetch() } }
    
    private func fetch() async {
        guard !loading else { return }
        loading = true; error = nil
        guard let tok = await TokenExtractor.extract() else {
            error = "请登录 Firefox → Command Code"; loading = false; return
        }
        
        // Run network requests off the main actor, then apply results on it
        let result = await fetchData(tok)
        if let h = result.0 { hourly = h }
        if let s = result.1 { summary = s }
        if let b = result.2 { credits = b }
        
        try? await Task.sleep(nanoseconds: 600_000_000)
        loading = false
    }
    
    /// Network fetches on URLSession's delegate queue so all three run in
    /// parallel without hopping back to the main actor mid-flight.
    private nonisolated func fetchData(_ tok: String) async -> ([HourBucket]?, SummaryResp?, CreditsResp.C2?) {
        struct CR: Codable { let data: [ChartBucket] }
        async let c: CR? = get("https://api.commandcode.ai/internal/usage/charts", tok)
        async let s: SummaryResp? = get("https://api.commandcode.ai/internal/usage/summary", tok)
        async let b: CreditsResp? = get("https://api.commandcode.ai/internal/billing/credits", tok)
        let (cc, ss, bb) = await (c, s, b)
        return (cc.map { aggregateHourly($0.data) }, ss, bb?.credits)
    }
    
    private nonisolated func get<T: Codable>(_ u: String, _ tok: String) async -> T? {
        guard let url = URL(string: u) else { return nil }
        var r = URLRequest(url: url)
        r.setValue("\(TokenExtractor.name)=\(tok)", forHTTPHeaderField: "Cookie")
        r.timeoutInterval = 15
        do {
            let (d, resp) = try await URLSession.shared.data(for: r)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(T.self, from: d)
        } catch { return nil }
    }
}
