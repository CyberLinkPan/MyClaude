import Foundation
import Combine

/// 快照模式：ImageRenderer 离屏渲染不支持 ScrollView 内容，
/// 置 true 时视图用普通布局替代滚动容器（仅 --snapshot 自检用）
var gSnapshotMode = false

// MARK: - 数据模型

struct UsageEvent {
    let time: Date
    let input: Int
    let output: Int
    let cacheCreate: Int
    let cacheRead: Int
    let model: String
    let project: String
    var total: Int { input + output + cacheCreate + cacheRead }
}

struct BlockInfo {
    let start: Date
    let end: Date
    let tokens: Double
    let halfHourBars: [Double]   // 10 段，每段 30 分钟
}

struct Metrics {
    var today: Double = 0
    var yesterday: Double = 0
    var todayInput: Double = 0
    var todayOutput: Double = 0
    var todayCum: [Double] = Array(repeating: 0, count: 48)   // 今日累计（半小时粒度）
    var avg7Cum: [Double] = Array(repeating: 0, count: 48)    // 近7日均值累计曲线
    var last7Daily: [Double] = Array(repeating: 0, count: 7)  // 含今日
    var last7Sum: Double = 0
    var heat: [(date: Date, value: Double)] = []              // 近90天
    var total90: Double = 0
    var lifetime: Double = 0
    var week: Double = 0                                      // 自上次重置以来
    var lastReset: Date = .distantPast
    var nextReset: Date = .distantFuture
    var daysLeft: Int = 0
    var projects: [(name: String, tokens: Double)] = []
    var models: [(name: String, tokens: Double)] = []
    var streak: Int = 0
    var block: BlockInfo? = nil
    var hourDist: [Double] = Array(repeating: 0, count: 24)    // 近90天按小时分布
    var weekdayDist: [Double] = Array(repeating: 0, count: 7)  // 近90天按周几分布（周一=0）
    var minute60: [Double] = Array(repeating: 0, count: 60)    // 近60分钟逐分钟
    var min60Sum: Double = 0
    var totInput: Double = 0
    var totOutput: Double = 0
    var totCacheRead: Double = 0
    var totCacheWrite: Double = 0
    var generatedAt: Date = .distantPast
}

// MARK: - 设置

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    private let d = UserDefaults.standard

    @Published var dailyGoalM: Double {      // 单位：百万 token
        didSet { d.set(dailyGoalM, forKey: "dailyGoalM"); UsageStore.shared.recomputeOnly() }
    }
    @Published var weeklyBudgetB: Double {   // 单位：十亿 token
        didSet { d.set(weeklyBudgetB, forKey: "weeklyBudgetB"); UsageStore.shared.recomputeOnly() }
    }
    @Published var resetWeekday: Int {       // Calendar weekday: 1=周日 2=周一 ...
        didSet { d.set(resetWeekday, forKey: "resetWeekday"); UsageStore.shared.recomputeOnly() }
    }
    @Published var resetHour: Int {
        didSet { d.set(resetHour, forKey: "resetHour"); UsageStore.shared.recomputeOnly() }
    }
    @Published var showMenuNumber: Bool {   // 菜单栏是否显示今日数字（占宽，满菜单栏易被刘海挤掉）
        didSet { d.set(showMenuNumber, forKey: "showMenuNumber"); UsageStore.shared.recomputeOnly() }
    }
    @Published var accentRGB: [Double] {    // 主题色（强调色，派生出渐变/热力图梯度）
        didSet { d.set(accentRGB, forKey: "accentRGB") }
    }
    @Published var tintRGB: [Double] {      // 玻璃染色颜色
        didSet { d.set(tintRGB, forKey: "tintRGB") }
    }
    @Published var tintStrength: Double {   // 玻璃染色强度 0=纯玻璃
        didSet { d.set(tintStrength, forKey: "tintStrength") }
    }
    @Published var popoverModules: [String] {    // 小面板启用的模块
        didSet { d.set(popoverModules, forKey: "popoverModules") }
    }
    @Published var dashboardModules: [String] {  // 主面板右栏启用的模块
        didSet { d.set(dashboardModules, forKey: "dashboardModules") }
    }
    @Published var effectsOff: [String] {        // 关闭光效的模块（默认空=全开）
        didSet { d.set(effectsOff, forKey: "effectsOff") }
    }

    var dailyGoal: Double { dailyGoalM * 1_000_000 }
    var weeklyBudget: Double { weeklyBudgetB * 1_000_000_000 }

    private init() {
        dailyGoalM = d.object(forKey: "dailyGoalM") as? Double ?? 300
        weeklyBudgetB = d.object(forKey: "weeklyBudgetB") as? Double ?? 3.0
        resetWeekday = d.object(forKey: "resetWeekday") as? Int ?? 2
        resetHour = d.object(forKey: "resetHour") as? Int ?? 0
        showMenuNumber = d.object(forKey: "showMenuNumber") as? Bool ?? false
        accentRGB = Self.loadRGB(d.object(forKey: "accentRGB")) ?? [1.00, 0.18, 0.45]
        tintRGB = Self.loadRGB(d.object(forKey: "tintRGB")) ?? [1.00, 0.18, 0.45]
        tintStrength = d.object(forKey: "tintStrength") as? Double ?? 0
        popoverModules = d.object(forKey: "popoverModules") as? [String] ?? Self.defaultPopoverModules
        dashboardModules = d.object(forKey: "dashboardModules") as? [String] ?? Self.defaultDashboardModules
        effectsOff = d.object(forKey: "effectsOff") as? [String] ?? []
    }

    static let defaultPopoverModules = ["ring", "goals", "heatmap"]
    static let defaultDashboardModules = ["last7", "reset", "health", "models"]

    /// 容错读取 RGB 数组（兼容 defaults 命令行写入的字符串元素）
    private static func loadRGB(_ any: Any?) -> [Double]? {
        guard let a = any as? [Any], a.count == 3 else { return nil }
        let v = a.compactMap { ($0 as? NSNumber)?.doubleValue ?? Double("\($0)") }
        return v.count == 3 ? v : nil
    }
}

// MARK: - 用量仓库

final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    @Published var metrics = Metrics()

    private struct FileCache { var mtime: Date; var size: Int; var events: [UsageEvent] }
    private var cache: [String: FileCache] = [:]
    private let queue = DispatchQueue(label: "myclaude.usage", qos: .userInitiated)

    private let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private var root: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    }

    /// 扫描目录，重新解析有变化的文件，然后重算指标
    func refresh() {
        queue.async { [self] in
            let fm = FileManager.default
            var files: [URL] = []
            if let en = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) {
                for case let u as URL in en where u.pathExtension == "jsonl" { files.append(u) }
            }
            var alive = Set<String>()
            for u in files {
                let path = u.path
                alive.insert(path)
                let attr = try? u.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let mtime = attr?.contentModificationDate ?? .distantPast
                let size = attr?.fileSize ?? 0
                if let c = cache[path], c.mtime == mtime, c.size == size { continue }
                cache[path] = FileCache(mtime: mtime, size: size, events: parse(file: u))
            }
            for k in cache.keys where !alive.contains(k) { cache.removeValue(forKey: k) }
            publish()
        }
    }

    /// 只重算（设置变化时用），不重新读文件
    func recomputeOnly() {
        queue.async { [self] in publish() }
    }

    /// 同步刷新（离屏渲染自检用）
    func refreshSync() {
        let fm = FileManager.default
        var events: [UsageEvent] = []
        if let en = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let u as URL in en where u.pathExtension == "jsonl" {
                events.append(contentsOf: parse(file: u))
            }
        }
        metrics = compute(events: events)
    }

    private func publish() {
        let all = cache.values.flatMap(\.events)
        let m = compute(events: all)
        DispatchQueue.main.async { self.metrics = m }
    }

    // MARK: 解析单个 jsonl

    private func parse(file: URL) -> [UsageEvent] {
        guard let data = try? Data(contentsOf: file),
              let text = String(data: data, encoding: .utf8) else { return [] }
        var events: [UsageEvent] = []
        var seen = Set<String>()
        for line in text.split(separator: "\n") {
            guard line.contains("\"type\":\"assistant\""), line.contains("\"usage\"") else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let msg = obj["message"] as? [String: Any],
                  let usage = msg["usage"] as? [String: Any],
                  let ts = obj["timestamp"] as? String,
                  let date = isoFrac.date(from: ts) ?? isoPlain.date(from: ts)
            else { continue }
            // 去重：同一 message.id + requestId 只算一次（流式输出会重复写行）
            let key = "\(msg["id"] as? String ?? ""):\(obj["requestId"] as? String ?? "")"
            if !key.hasPrefix(":") || !key.hasSuffix(":") {
                if seen.contains(key) { continue }
                seen.insert(key)
            }
            let cwd = obj["cwd"] as? String ?? ""
            let project = cwd.isEmpty ? "未知" : (cwd as NSString).lastPathComponent
            events.append(UsageEvent(
                time: date,
                input: usage["input_tokens"] as? Int ?? 0,
                output: usage["output_tokens"] as? Int ?? 0,
                cacheCreate: usage["cache_creation_input_tokens"] as? Int ?? 0,
                cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0,
                model: msg["model"] as? String ?? "unknown",
                project: project))
        }
        return events
    }

    // MARK: 指标计算

    private func compute(events: [UsageEvent]) -> Metrics {
        var m = Metrics()
        let cal = Calendar.current
        let now = Date()
        let startToday = cal.startOfDay(for: now)
        let s = SettingsStore.shared

        // 重置周期
        var comp = DateComponents(); comp.hour = s.resetHour; comp.minute = 0; comp.weekday = s.resetWeekday
        let next = cal.nextDate(after: now, matching: comp, matchingPolicy: .nextTime) ?? now.addingTimeInterval(7 * 86400)
        m.nextReset = next
        m.lastReset = next.addingTimeInterval(-7 * 86400)
        m.daysLeft = max(0, Int(ceil(next.timeIntervalSince(now) / 86400)))

        var todayHalf = [Double](repeating: 0, count: 48)
        var prevHalf = [Double](repeating: 0, count: 48)
        var dayTotals: [Date: Double] = [:]
        var projects: [String: Double] = [:]
        var models: [String: Double] = [:]

        let heat0 = cal.date(byAdding: .day, value: -89, to: startToday)!
        let last70 = cal.date(byAdding: .day, value: -6, to: startToday)!
        let prev70 = cal.date(byAdding: .day, value: -7, to: startToday)!
        let yest0 = cal.date(byAdding: .day, value: -1, to: startToday)!

        for e in events {
            let t = Double(e.total)
            m.lifetime += t
            m.totInput += Double(e.input)
            m.totOutput += Double(e.output)
            m.totCacheRead += Double(e.cacheRead)
            m.totCacheWrite += Double(e.cacheCreate)
            projects[e.project, default: 0] += t
            models[e.model, default: 0] += t
            let d0 = cal.startOfDay(for: e.time)
            if d0 >= heat0 {
                dayTotals[d0, default: 0] += t
                m.hourDist[cal.component(.hour, from: e.time)] += t
                m.weekdayDist[(cal.component(.weekday, from: e.time) + 5) % 7] += t
            }
            let ago = now.timeIntervalSince(e.time)
            if ago >= 0 && ago < 3600 {
                m.minute60[min(59, max(0, 59 - Int(ago / 60)))] += t
                m.min60Sum += t
            }
            if e.time >= startToday {
                m.today += t
                m.todayInput += Double(e.input)
                m.todayOutput += Double(e.output)
                let idx = min(47, max(0, Int(e.time.timeIntervalSince(startToday) / 1800)))
                todayHalf[idx] += t
            } else if e.time >= yest0 {
                m.yesterday += t
            }
            if e.time >= prev70 && e.time < startToday {
                let idx = min(47, max(0, Int(e.time.timeIntervalSince(cal.startOfDay(for: e.time)) / 1800)))
                prevHalf[idx] += t
            }
            if e.time >= m.lastReset { m.week += t }
        }

        // 累计曲线
        var acc = 0.0
        let nowIdx = min(47, Int(now.timeIntervalSince(startToday) / 1800))
        for i in 0..<48 {
            acc += todayHalf[i]
            m.todayCum[i] = i <= nowIdx ? acc : -1   // -1 表示未来（不画）
        }
        acc = 0
        for i in 0..<48 { acc += prevHalf[i] / 7.0; m.avg7Cum[i] = acc }

        // 近7天（含今日）
        for i in 0..<7 {
            let d = cal.date(byAdding: .day, value: i, to: last70)!
            m.last7Daily[i] = dayTotals[d] ?? 0
        }
        m.last7Sum = m.last7Daily.reduce(0, +)

        // 近90天热力图
        for i in 0..<90 {
            let d = cal.date(byAdding: .day, value: i, to: heat0)!
            let v = dayTotals[d] ?? 0
            m.heat.append((d, v))
            m.total90 += v
        }

        // 连续活跃天数
        var streak = 0
        for i in stride(from: 89, through: 0, by: -1) {
            if m.heat[i].value > 0 { streak += 1 }
            else if i == 89 { continue }   // 今天还没用不打断连击
            else { break }
        }
        m.streak = streak

        m.projects = projects.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
        m.models = models.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }

        // 5 小时窗口（对齐整点，间隔 >5h 则开新窗）
        let sorted = events.sorted { $0.time < $1.time }
        var blockStart: Date? = nil
        var blockEvents: [UsageEvent] = []
        var lastTime: Date = .distantPast
        for e in sorted {
            if let bs = blockStart,
               e.time < bs.addingTimeInterval(5 * 3600),
               e.time.timeIntervalSince(lastTime) < 5 * 3600 {
                blockEvents.append(e)
            } else {
                var c = cal.dateComponents([.year, .month, .day, .hour], from: e.time)
                c.minute = 0; c.second = 0
                blockStart = cal.date(from: c)
                blockEvents = [e]
            }
            lastTime = e.time
        }
        if let bs = blockStart, now < bs.addingTimeInterval(5 * 3600) {
            var bars = [Double](repeating: 0, count: 10)
            var tok = 0.0
            for e in blockEvents {
                tok += Double(e.total)
                let idx = min(9, max(0, Int(e.time.timeIntervalSince(bs) / 1800)))
                bars[idx] += Double(e.total)
            }
            m.block = BlockInfo(start: bs, end: bs.addingTimeInterval(5 * 3600), tokens: tok, halfHourBars: bars)
        }

        m.generatedAt = now
        return m
    }
}

// MARK: - 格式化

enum Fmt {
    static func tokens(_ n: Double) -> String {
        let a = abs(n)
        if a >= 1e9 { return String(format: "%.1fB", n / 1e9) }
        if a >= 1e6 { return String(format: "%.1fM", n / 1e6) }
        if a >= 1e3 { return String(format: "%.1fK", n / 1e3) }
        return String(format: "%.0f", n)
    }
    static func pct(_ x: Double) -> String { String(format: "%.0f%%", x * 100) }
    static func day(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M月d日"; return f.string(from: d)
    }
    static func hm(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }
    static func month(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M月"; return f.string(from: d)
    }
}
