import Foundation

// MARK: - 语言适配（中文原文即键：英文查字典，缺失回退中文）

/// 当前是否英文界面
var gIsEN: Bool {
    switch SettingsStore.shared.language {
    case "zh": return false
    case "en": return true
    default: return !(Locale.preferredLanguages.first ?? "zh").hasPrefix("zh")
    }
}

extension String {
    /// 界面文案本地化
    var loc: String { gIsEN ? (L10n.en[self] ?? self) : self }
}

/// 带参数的本地化格式串
func lf(_ key: String, _ args: CVarArg...) -> String {
    String(format: key.loc, arguments: args)
}

enum L10n {
    /// 周一起始的星期缩写（热力图/玫瑰图）
    static var weekMon: [String] {
        gIsEN ? ["M", "T", "W", "T", "F", "S", "S"] : ["一", "二", "三", "四", "五", "六", "日"]
    }
    /// 周日起始的星期名（设置选择器）
    static var weekSun: [String] {
        gIsEN ? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"] : ["日", "一", "二", "三", "四", "五", "六"]
    }

    static let en: [String: String] = [
        // ── 通用
        "今日": "Today",
        "本周": "This week",
        "少": "less",
        "多": "more",
        "暂无数据": "No data",
        "未知": "unknown",
        "取消": "Cancel",
        "重试": "Retry",
        "刷新": "Refresh",
        "连接": "Connect",
        "断开": "Disconnect",
        "恢复默认": "Reset",

        // ── 小面板
        "今日 token": "Today's tokens",
        "今日累计 · 近 7 日均值": "today · 7-day avg",
        "Token 小目标": "Token Goals",
        "自然周": "calendar week",
        "近 90 天用量": "Last 90 Days",
        "混合口径": "all tokens",
        "合计 %@": "Total %@",
        "打开 MyClaude": "Open MyClaude",
        "没有启用任何模块——去 ⚙️ 设置里勾选": "No modules enabled — pick some in ⚙️ Settings",
        "剩余%d天": "%dd left",

        // ── 统计卡
        "7天剩余": "7-Day Left",
        "重置 %@ %@": "Resets %@ %@",
        "输入 %@ · 输出 %@": "In %@ · Out %@",
        "近7天": "Last 7 Days",
        "日均 %@": "daily avg %@",
        "累计": "All Time",
        "近90天 %@": "90-day %@",

        // ── 标签页
        "今日估算": "Today",
        "用量趋势": "Trends",
        "项目排行": "Projects",
        "5h窗": "5h Window",
        "下次重置 %@ · %d 天后": "Next reset %@ · in %dd",

        // ── 左栏卡片
        "最近 90 天用量": "Last 90 Days Usage",
        "近90天合计 %@": "90-day total %@",
        "今日累计节奏": "Today's Pace",
        "较昨日 +": "vs yesterday +",
        "较昨日 ": "vs yesterday ",
        "预计全天 %@": "projected %@",
        "今日 %@": "Today %@",
        "5 小时窗口": "5-Hour Window",
        "本窗口用量": "this window",
        "窗口 %@ – %@": "Window %@ – %@",
        "剩余 %d时%d分": "%dh %dm left",
        "当前没有活跃的 5 小时窗口": "No active 5-hour window",

        // ── 模块
        "圆环总览": "Overview Ring",
        "90天热力图": "90-Day Heatmap",
        "最近 7 天": "Last 7 Days",
        "7 天合计": "7-day total",
        "下次重置": "Next Reset",
        "%@ · %d 天后": "%@ · in %d days",
        "本周期已过 %@": "%@ of cycle elapsed",
        "健康度": "Health",
        "连续活跃 %d 天": "%d-day streak",
        "预算已用": "Budget used",
        "按当前节奏，重置前约 %@（预算的 %@）": "At this pace ≈ %@ by reset (%@ of budget)",
        "模型分布": "Models",
        "今日仪表盘": "Today Gauge",
        "量程 150%": "range 150%",
        "目标 %@": "goal %@",
        "实时脉搏": "Live Pulse",
        "60 分钟前": "60 min ago",
        "近1小时 %@": "last hour %@",
        "现在": "now",
        "昼夜热环": "Day Cycle",
        "近90天分布": "90-day dist.",
        "当前时段": "current hour",
        "周节律玫瑰": "Weekday Rose",
        "里程碑计数": "Milestones",
        "历史累计": "all-time",
        "下一里程碑 %@，还差 %@": "Next milestone %@ — %@ to go",
        "缓存命中率": "Cache Hits",
        "输入侧构成": "input mix",
        "命中": "hit",
        "缓存读取": "Cache read",
        "缓存写入": "Cache write",
        "新鲜输入": "Fresh input",
        "命中率越高，重复上下文越省——这是省额度的关键指标": "Higher hit rate = more context reuse — the key quota-saving metric",
        "GitHub 仓库": "GitHub Repos",
        "未连接。在 ⚙️ 设置中粘贴 Personal Access Token，或安装并登录 gh CLI 后点右上角刷新。":
            "Not connected. Paste a Personal Access Token in ⚙️ Settings, or sign in with gh CLI and hit refresh.",
        "加载中…": "Loading…",
        "加载失败：%@": "Failed: %@",
        "%d 公开仓库": "%d public repos",
        "没有仓库": "No repositories",
        "5h窗柱状": "5h Window Bars",

        // ── 模块详细介绍（悬浮浮层）
        "周额度剩余圆环 + 今日累计曲线。圆环按『每周预算』计算本周还剩多少，中心显示剩余百分比和距重置天数；右侧是今日逐半小时累计曲线，虚线为近 7 日均值参考——一眼判断今天用得比平常快还是慢。":
            "Weekly-quota ring plus today's cumulative curve. The ring shows what's left of your weekly budget with days until reset; the curve compares today against the 7-day average — see at a glance whether today is running hot.",
        "今日 / 本周两条目标进度条。分别对照『今日目标』和『每周预算』显示已用量与完成百分比，超过 100% 时以高亮色提示。适合给自己设定节制线或冲量目标。":
            "Progress bars for daily and weekly targets vs your configured goal and budget; highlights once past 100%.",
        "GitHub 风格贡献格。近 90 天每天一格，颜色越亮当天用量越大（对数刻度），行序为周一到周日，底部附 90 天合计。长期使用习惯一目了然。":
            "GitHub-style contribution grid: one cell per day for 90 days on a log scale, Mon–Sun rows, with the 90-day total below.",
        "近 7 天（含今日）逐日用量折线与 7 天合计，观察一周内的用量起伏和趋势拐点。":
            "Daily usage line for the last 7 days (incl. today) with the weekly total.",
        "距下一次周额度重置的日期与天数，进度条显示本周期已经过的比例。重置的星期与时刻可在『目标与周期』栏修改。":
            "Date and countdown to the next weekly reset; the bar shows how much of the cycle has elapsed. Configure weekday and hour under Goals & Cycle.",
        "预算消耗体检：本周已用百分比 + 按当前节奏外推到重置日的预计总量，并显示连续活跃天数。预计值超过预算说明节奏偏快，该踩刹车了。":
            "Budget check-up: percent used plus a pace projection to reset day, and your activity streak. Projection above budget means it's time to slow down.",
        "各模型（Opus / Fable / Sonnet…）历史累计用量排行与占比条，看清额度都花在了哪个模型上。":
            "All-time usage ranking across models (Opus / Fable / Sonnet…) — see where your quota really goes.",
        "速度表风格的今日读数：240° 表盘 + 发光指针 + 刻度，量程为今日目标的 150%，指针角度直观反映目标完成度，冲破 100% 自有仪式感。":
            "A 240° speedometer with glowing needle and ticks; range is 150% of the daily goal — crossing 100% feels appropriately ceremonial.",
        "近 60 分钟逐分钟用量频谱，右上角 LIVE 呼吸灯表示实时监控，最右侧高亮柱为最近几分钟。挂着它就能感知当前会话的消耗节奏。":
            "Per-minute spectrum of the last 60 minutes with a breathing LIVE dot — feel the burn rate of your current session.",
        "24 小时钟面热力环：近 90 天用量按发生时段聚合，每格一小时，越亮代表该时段历史用量越大，白框标出当前时段。看清自己是白天型还是深夜型选手。":
            "A 24-hour clock ring aggregating 90 days of usage by hour; the white frame marks the current hour. Day person or night owl — now you'll know.",
        "极坐标玫瑰图：近 90 天用量按周一到周日聚合为七片花瓣，花瓣越大该天用得越多（面积开方校正），今天的花瓣高亮描边。":
            "A polar rose: 90 days of usage folded into seven weekday petals (area-corrected); today's petal is outlined.",
        "机械翻牌里程表：历史累计总量逐位显示，下方是距下一个里程碑（100M、200M、500M、1B…）的进度与差额。攒数字的快乐。":
            "A flip-style odometer of all-time usage, with progress toward the next milestone (100M, 200M, 500M, 1B…). Number-collecting joy.",
        "输入侧 token 构成环：缓存读取 / 缓存写入 / 新鲜输入三者占比，中心为命中率。命中率越高，提示词缓存复用越好、同样额度干更多活——Claude Code 的省额度关键指标。":
            "Input-side composition ring: cache read / cache write / fresh input, hit rate at center. Higher hit rate = better prompt-cache reuse — the key quota-saving metric.",
        "连接 GitHub 账号，显示头像、用户名和最近推送的仓库（名称 / 私有标记 / Star / 语言）。登录方式：在设置中粘贴 Personal Access Token（存入系统钥匙串），或自动复用已登录的 gh CLI。":
            "Connect your GitHub account to show your avatar and recently pushed repos (name / private / stars / language). Sign in via device flow or a pasted token, stored in the macOS Keychain.",

        // ── 设置
        "设置": "Settings",
        "外观": "Appearance",
        "语言": "Language",
        "跟随系统": "System",
        "主题色": "Accent color",
        "玻璃染色": "Glass tint",
        "染色强度 %d%%": "Tint strength %d%%",
        "强度 0% = 纯玻璃（透出壁纸原色）；调高后玻璃带上你选的颜色":
            "0% = pure glass (wallpaper shows through); increase to tint the glass with your color",
        "模块光效": "Light Effects",
        "逐模块开关动态光效（闪烁 / 彗星 / 光点 / 光带 / 声呐）。「今日累计节奏」「5h窗柱状」对应主面板左侧图表；趋势页热力图跟随「90天热力图」":
            "Per-module dynamic effects (sparkle / comets / dots / bands / sonar). \"Today's Pace\" and \"5h Window Bars\" control the dashboard's left-side charts; the Trends heatmap follows \"90-Day Heatmap\"",
        "模块显示": "Modules",
        "小面板": "Popover",
        "主面板右栏": "Dashboard right column",
        "目标与周期": "Goals & Cycle",
        "今日目标 (M)": "Daily goal (M)",
        "每周预算 (B)": "Weekly budget (B)",
        "重置星期": "Reset weekday",
        "重置时刻": "Reset hour",
        "菜单栏显示数字": "Number in menu bar",
        "已连接：%@": "Connected: %@",
        "连接中…": "Connecting…",
        "连接失败：%@": "Failed: %@",
        "未连接": "Not connected",
        "高级：手动 Token": "Advanced: manual token",
        "粘贴 Personal Access Token": "Paste Personal Access Token",
        "一键连接 GitHub": "Connect GitHub",
        "自动打开浏览器授权，无需手动创建 Token": "Opens your browser to authorize — no manual token needed",
        "正在获取授权码…": "Requesting code…",
        "授权码已复制到剪贴板——在打开的 GitHub 页面粘贴并点击授权，完成后这里会自动连上":
            "Code copied — paste it on the GitHub page that just opened and authorize; this connects automatically",
        "凭证存入系统钥匙串，不落明文；授权记录显示为 GitHub CLI，可在 GitHub → Settings → Applications 随时撤销。":
            "Credentials live in the macOS Keychain. The grant shows as \"GitHub CLI\" and can be revoked anytime in GitHub → Settings → Applications.",
        "数据来源：~/.claude/projects 会话记录\n口径：输入 + 输出 + 缓存写入 + 缓存读取（混合口径）":
            "Data: ~/.claude/projects session logs\nCounting: input + output + cache write + cache read",

        // ── 刘海遮挡提示
        "菜单栏图标被刘海挡住了": "Menu bar icon is hidden by the notch",
        "菜单栏图标太多时，MyClaude 的图标可能正好排在刘海下面。按住 ⌘ 拖走或退出一两个不常用的菜单栏图标，它就会露出来。主窗口已为你打开；双击 App 图标随时可以再次打开。":
            "With a crowded menu bar, MyClaude's icon can end up right under the notch. ⌘-drag away or quit a couple of unused menu bar icons and it will reappear. The dashboard has been opened for you; double-click the app icon to open it anytime.",
        "知道了": "Got it",

        // ── GitHub 错误
        "Token 无效或已过期": "Token invalid or expired",
        "响应解析失败": "Failed to parse response",
        "授权码已过期，请重试": "Code expired — try again",
        "你在网页上拒绝了授权": "Authorization denied on the web page",
        "等待授权超时，请重试": "Timed out waiting for authorization — try again",
    ]
}
