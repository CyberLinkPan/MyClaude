import Foundation
import AppKit
import Security
import Combine

// MARK: - 钥匙串（Token 不落明文）

enum Keychain {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "MyClaude",
         kSecAttrAccount as String: key]
    }
    static func set(_ value: String, key: String) {
        delete(key)
        var q = query(key)
        q[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }
    static func get(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func delete(_ key: String) { SecItemDelete(query(key) as CFDictionary) }
}

// MARK: - GitHub 数据

final class GitHubStore: ObservableObject {
    static let shared = GitHubStore()

    struct Repo: Identifiable {
        let id: Int
        let name: String
        let isPrivate: Bool
        let stars: Int
        let language: String?
    }
    struct GHUser {
        let login: String
        let avatarURL: String
        let publicRepos: Int
    }
    enum LoadState {
        case notConfigured
        case loading
        case loaded(GHUser, [Repo])
        case failed(String)
    }

    enum DeviceFlowState {
        case idle
        case requesting
        case waiting(code: String)
        case failed(String)
    }

    @Published var state: LoadState = .notConfigured
    @Published var avatar: NSImage? = nil
    @Published var deviceFlow: DeviceFlowState = .idle

    var isConnected: Bool {
        if case .loaded = state { return true }
        return false
    }

    private var flowCancelled = false
    private var timer: Timer?

    private init() {
        DispatchQueue.global(qos: .utility).async { [weak self] in self?.refreshBlocking() }
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .utility).async { self?.refreshBlocking() }
        }
    }

    var hasStoredToken: Bool { Keychain.get("github_token") != nil }

    func setToken(_ t: String) {
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Keychain.set(trimmed, key: "github_token")
        refresh()
    }

    func disconnect() {
        Keychain.delete("github_token")
        DispatchQueue.main.async { self.state = .notConfigured; self.avatar = nil }
    }

    func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in self?.refreshBlocking() }
    }

    // MARK: 设备授权流（一键连接，无需手动创建 Token）

    /// GitHub CLI 的公开 client id（设备流无密钥；授权记录会显示为 "GitHub CLI"，
    /// 可随时在 GitHub → Settings → Applications 撤销）
    private static let clientID = "178c6fc778ccc68e1d6a"

    func startDeviceFlow() {
        flowCancelled = false
        DispatchQueue.main.async { self.deviceFlow = .requesting }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.deviceFlowBlocking() }
    }

    func cancelDeviceFlow() {
        flowCancelled = true
        DispatchQueue.main.async { self.deviceFlow = .idle }
    }

    private func deviceFlowBlocking() {
        do {
            guard let obj = try post("https://github.com/login/device/code",
                                     body: "client_id=\(Self.clientID)&scope=repo%20read%3Auser") as? [String: Any],
                  let userCode = obj["user_code"] as? String,
                  let deviceCode = obj["device_code"] as? String,
                  let uri = obj["verification_uri"] as? String
            else { throw Err.parse }
            let expires = obj["expires_in"] as? Int ?? 900
            var step = obj["interval"] as? Int ?? 5

            DispatchQueue.main.async {
                self.deviceFlow = .waiting(code: userCode)
                // 授权码进剪贴板 + 打开授权页，用户只需 ⌘V 并点授权
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(userCode, forType: .string)
                if let u = URL(string: uri) { NSWorkspace.shared.open(u) }
            }

            var waited = 0
            while waited < expires && !flowCancelled {
                Thread.sleep(forTimeInterval: Double(step + 1))
                waited += step + 1
                guard let r = try? post("https://github.com/login/oauth/access_token",
                    body: "client_id=\(Self.clientID)&device_code=\(deviceCode)&grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code") as? [String: Any]
                else { continue }
                if let token = r["access_token"] as? String {
                    Keychain.set(token, key: "github_token")
                    DispatchQueue.main.async { self.deviceFlow = .idle }
                    refreshBlocking()
                    return
                }
                switch r["error"] as? String {
                case "slow_down": step += 5
                case "expired_token": throw Err.flow("授权码已过期，请重试")
                case "access_denied": throw Err.flow("你在网页上拒绝了授权")
                default: break   // authorization_pending → 继续轮询
                }
            }
            if flowCancelled { return }
            throw Err.flow("等待授权超时，请重试")
        } catch {
            let msg = (error as? Err)?.text ?? error.localizedDescription
            DispatchQueue.main.async { self.deviceFlow = .failed(msg) }
        }
    }

    private func post(_ urlStr: String, body: String) throws -> Any {
        var req = URLRequest(url: URL(string: urlStr)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(body.utf8)
        req.timeoutInterval = 15
        var result: Result<Any, Error> = .failure(Err.parse)
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            defer { sem.signal() }
            if let err { result = .failure(err); return }
            guard let data, let obj = try? JSONSerialization.jsonObject(with: data) else {
                result = .failure(Err.parse); return
            }
            result = .success(obj)
        }.resume()
        sem.wait()
        return try result.get()
    }

    // MARK: 内部

    /// Token 来源：① 钥匙串（设置里粘贴） ② 已登录的 gh CLI
    private func currentToken() -> String? {
        if let t = Keychain.get("github_token") { return t }
        return ghCLIToken()
    }

    private func ghCLIToken() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "command -v gh >/dev/null && gh auth token 2>/dev/null"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return out.isEmpty ? nil : out
    }

    private func refreshBlocking() {
        guard let token = currentToken() else {
            DispatchQueue.main.async { self.state = .notConfigured }
            return
        }
        DispatchQueue.main.async { self.state = .loading }
        do {
            guard let userObj = try request("https://api.github.com/user", token: token) as? [String: Any],
                  let login = userObj["login"] as? String else { throw Err.parse }
            let user = GHUser(login: login,
                              avatarURL: userObj["avatar_url"] as? String ?? "",
                              publicRepos: userObj["public_repos"] as? Int ?? 0)
            let repoArr = try request(
                "https://api.github.com/user/repos?sort=pushed&per_page=30&affiliation=owner",
                token: token) as? [[String: Any]] ?? []
            let repos = repoArr.map {
                Repo(id: $0["id"] as? Int ?? 0,
                     name: $0["name"] as? String ?? "?",
                     isPrivate: $0["private"] as? Bool ?? false,
                     stars: $0["stargazers_count"] as? Int ?? 0,
                     language: $0["language"] as? String)
            }
            DispatchQueue.main.async { self.state = .loaded(user, repos) }
            if !user.avatarURL.isEmpty, let url = URL(string: user.avatarURL),
               let d = try? Data(contentsOf: url), let img = NSImage(data: d) {
                DispatchQueue.main.async { self.avatar = img }
            }
        } catch {
            let msg = (error as? Err)?.text ?? error.localizedDescription
            DispatchQueue.main.async { self.state = .failed(msg) }
        }
    }

    private enum Err: Error {
        case http(Int), parse, flow(String)
        var text: String {
            switch self {
            case .http(let c): return c == 401 ? "Token 无效或已过期" : "HTTP \(c)"
            case .parse: return "响应解析失败"
            case .flow(let s): return s
            }
        }
    }

    /// 同步请求（仅在后台队列调用）
    private func request(_ urlStr: String, token: String) throws -> Any {
        var req = URLRequest(url: URL(string: urlStr)!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        var result: Result<Any, Error> = .failure(Err.parse)
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            defer { sem.signal() }
            if let err { result = .failure(err); return }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else { result = .failure(Err.http(code)); return }
            guard let data, let obj = try? JSONSerialization.jsonObject(with: data) else {
                result = .failure(Err.parse); return
            }
            result = .success(obj)
        }.resume()
        sem.wait()
        return try result.get()
    }
}
