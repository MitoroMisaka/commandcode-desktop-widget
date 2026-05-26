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
    private var fetchTask: Task<Void, Never>?
    
    /// Quick-connect URLSession: 15s request timeout, 30s total, 10s connect.
    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 30
        c.waitsForConnectivity = false
        c.httpMaximumConnectionsPerHost = 3
        return URLSession(configuration: c)
    }()
    
    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30*60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // Debounced: avoid stacking refreshes on rapid focus switches
        var pending: Task<Void, Never>?
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            pending?.cancel()
            pending = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
                self?.refresh()
            }
        }
    }
    func stop() { timer?.invalidate(); fetchTask?.cancel() }
    func refresh() {
        fetchTask?.cancel()
        fetchTask = Task { await fetch() }
    }
    
    private func fetch() async {
        guard !loading else { return }
        loading = true; error = nil
        
        guard let tok = await TokenExtractor.extract() else {
            error = "请登录 Firefox → Command Code"; loading = false; return
        }
        
        // Wrap fetchData in a timeout to avoid 3+ minute hangs on flaky networks.
        let result = await withTimeout(25) { [tok] in
            await self.fetchData(tok)
        }
        
        if Task.isCancelled { loading = false; return }
        
        switch result {
        case .timeout:
            error = "网络超时"
        case .success(let (h, s, c)):
            if let h = h { hourly = h }
            if let s = s { summary = s }
            if let c = c { credits = c }
        }
        
        try? await Task.sleep(nanoseconds: 600_000_000)
        if Task.isCancelled { return }
        loading = false
    }
    
    /// Network fetches off the main actor.
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
            let (d, resp) = try await DataFetcher.session.data(for: r)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(T.self, from: d)
        } catch { return nil }
    }
}

// MARK: - Task timeout

enum TimeoutResult<T> { case success(T), timeout }

private func withTimeout<T>(_ seconds: Double, _ op: @escaping () async -> T) async -> TimeoutResult<T> {
    do {
        let value = try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { await op() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CancellationError()
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
        return .success(value)
    } catch {
        return .timeout
    }
}
