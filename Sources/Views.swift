import SwiftUI
import AppKit

// MARK: - 调色板（由用户主题色动态推导，默认粉红霓虹）

enum P {
    /// 主题色的 HSB 分量
    private static var base: (h: Double, s: Double, b: Double) {
        let c = SettingsStore.shared.accentRGB
        guard let ns = NSColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: 1)
            .usingColorSpace(.deviceRGB) else { return (0.93, 0.82, 1.0) }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (Double(h), Double(s), Double(b))
    }
    private static func hsb(_ h: Double, _ s: Double, _ b: Double) -> Color {
        Color(hue: h, saturation: min(max(s, 0), 1), brightness: min(max(b, 0), 1))
    }

    static var accent: Color {
        let c = SettingsStore.shared.accentRGB
        return Color(red: c[0], green: c[1], blue: c[2])
    }
    static var accent2: Color { let x = base; return hsb(x.h, x.s * 0.70, min(1, x.b * 1.18)) }
    static var hot: Color { let x = base; return hsb(x.h, x.s * 0.35, 1.0) }
    static var tint: Color {
        let c = SettingsStore.shared.tintRGB
        return Color(red: c[0], green: c[1], blue: c[2])
    }

    static let text = Color.white.opacity(0.92)
    static let sub = Color.white.opacity(0.55)
    static let faint = Color.white.opacity(0.30)
    static let cardStroke = Color.white.opacity(0.10)
    static let track = Color.white.opacity(0.09)

    static var barGrad: LinearGradient {
        LinearGradient(colors: [accent, accent2], startPoint: .leading, endPoint: .trailing)
    }
    static var ringGrad: AngularGradient {
        AngularGradient(colors: [accent, accent2, hot, accent],
                        center: .center, startAngle: .degrees(-90), endAngle: .degrees(270))
    }

    /// 热力图颜色：0 → 几乎透明；随强度从暗色 → 主题色 → 亮白
    static func heat(_ t: Double) -> Color {
        if t <= 0 { return Color.white.opacity(0.06) }
        let x = base
        let tt = min(1, max(0, t))
        return hsb(x.h, x.s * (0.95 - 0.55 * tt), 0.38 + 0.62 * tt)
    }
}

// MARK: - 光效开关（每个模块独立，经环境变量传给内部组件）

private struct FXEnabledKey: EnvironmentKey {
    static let defaultValue = true
}
extension EnvironmentValues {
    var fxEnabled: Bool {
        get { self[FXEnabledKey.self] }
        set { self[FXEnabledKey.self] = newValue }
    }
}

/// 按 key 查询光效开关（模块 + 主面板左栏固定图表）
func fxKey(_ id: String) -> Bool {
    !SettingsStore.shared.effectsOff.contains(id)
}

/// 某模块的光效是否开启
func fxOf(_ m: Module) -> Bool {
    fxKey(m.rawValue)
}

/// 主面板左栏固定图表的独立光效项
let extraFXItems: [(id: String, name: String)] = [
    ("rhythm", "今日累计节奏"),
    ("blockbars", "5h窗柱状"),
]

// MARK: - 滚动容器（快照模式下退化为普通布局，因 ImageRenderer 不渲染 ScrollView 内容）

struct MaybeScroll<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        if gSnapshotMode {
            content
        } else {
            ScrollView(.vertical, showsIndicators: false) { content }
        }
    }
}

// MARK: - 玻璃卡片

struct Card<Content: View>: View {
    var pad: CGFloat = 14
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(pad)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                // 液态玻璃卡片：极低不透明度填充 + 镜面高光描边（上亮下暗）+ 落影分层
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [.white.opacity(0.30),
                                                    .white.opacity(0.06),
                                                    .white.opacity(0.14)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1))
                    .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
            )
    }
}

struct Tag: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(P.sub)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}

// MARK: - 圆环

struct RingView: View {
    // 订阅设置：主题色变化时强制重绘（否则存储属性不变会被 SwiftUI 跳过）
    @ObservedObject private var theme = SettingsStore.shared
    let fraction: Double       // 0~1 剩余比例
    let title: String          // 中心大字
    let subtitle: String       // 中心小字
    var size: CGFloat = 92
    var body: some View {
        ZStack {
            Circle().stroke(P.track, lineWidth: size * 0.10)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(P.ringGrad, style: StrokeStyle(lineWidth: size * 0.10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: P.accent.opacity(0.55), radius: 6)
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: size * 0.26, weight: .bold, design: .rounded))
                    .foregroundStyle(P.text)
                Text(subtitle)
                    .font(.system(size: size * 0.11, weight: .medium))
                    .foregroundStyle(P.sub)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 折线图

struct LineChart: View {
    @ObservedObject private var theme = SettingsStore.shared
    let series: [Double]            // 主曲线（-1 表示未来，不画）
    var ref: [Double]? = nil        // 参考曲线（虚淡）
    var xLabels: [String] = []
    var height: CGFloat = 60

    private func norm(_ arr: [Double], maxV: Double) -> [Double?] {
        arr.map { $0 < 0 ? nil : (maxV > 0 ? $0 / maxV : 0) }
    }

    var comet: Bool = true          // 彗星光点沿曲线巡游
    // 每条曲线独立的随机相位与速度：多条曲线的彗星互不同步
    @State private var cometPhase = Double.random(in: 0..<8.0)
    @State private var cometRate = Double.random(in: 0.85...1.20)
    @Environment(\.fxEnabled) private var fx
    @ObservedObject private var ui = UIActivity.shared

    var body: some View {
        let maxV = max(series.filter { $0 >= 0 }.max() ?? 0, ref?.max() ?? 0, 1)
        VStack(spacing: 3) {
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let main = norm(series, maxV: maxV)
                ZStack {
                    // 静态底图（路径/阴影/渐变只画一次，不随动画重绘）
                    staticChart(main, w: w, h: h)
                    // 动画层只有彗星
                    if comet {
                        if fx && ui.animsActive && !gSnapshotMode {
                            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { ctx in
                                // 必须套 ZStack：多个 .position 子视图直接放进 TimelineView
                                // 会丢失图表坐标系，光点会飘出图外
                                ZStack {
                                    cometView(main, w: w, h: h,
                                              time: ctx.date.timeIntervalSinceReferenceDate)
                                }
                            }
                        } else if gSnapshotMode {
                            cometView(main, w: w, h: h, time: 3.5)
                        }
                    }
                }
            }
            .frame(height: height)
            if !xLabels.isEmpty {
                HStack {
                    ForEach(Array(xLabels.enumerated()), id: \.offset) { i, l in
                        Text(l).font(.system(size: 8)).foregroundStyle(P.faint)
                        if i < xLabels.count - 1 { Spacer() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func staticChart(_ main: [Double?], w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            if let r = ref {
                chartPath(norm(r, maxV: max(series.filter { $0 >= 0 }.max() ?? 0, r.max() ?? 0, 1)), w: w, h: h)
                    .stroke(Color.white.opacity(0.22),
                            style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
            }
            // 渐变填充
            chartArea(main, w: w, h: h)
                .fill(LinearGradient(colors: [P.accent.opacity(0.30), .clear],
                                     startPoint: .top, endPoint: .bottom))
            chartPath(main, w: w, h: h)
                .stroke(P.barGrad, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .shadow(color: P.accent.opacity(0.7), radius: 4)
            // 末端亮点
            if let last = lastPoint(main, w: w, h: h) {
                Circle().fill(P.hot).frame(width: 5, height: 5)
                    .shadow(color: P.accent, radius: 4)
                    .position(last)
            }
        }
    }

    /// 彗星：白色高亮核心 + 泛光晕圈 + 7 节渐隐拖尾，沿曲线循环巡游（周期 8 秒）。
    /// 性能注意：光晕与柔边全部用径向渐变实现（blur 每帧需要离屏渲染，代价高一个量级）
    @ViewBuilder
    private func cometView(_ vals: [Double?], w: CGFloat, h: CGFloat, time: Double) -> some View {
        let p = pts(vals, w: w, h: h)
        if p.count > 1 {
            let f = (time * cometRate + cometPhase).truncatingRemainder(dividingBy: 8.0) / 8.0
            let head = pointAt(p, f)
            // 外层泛光晕圈（径向渐变柔光，无 blur）
            Circle()
                .fill(RadialGradient(colors: [P.accent.opacity(0.55), P.accent.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: 13))
                .frame(width: 26, height: 26)
                .position(head)
            // 拖尾（亮色，逐节缩小渐隐；无阴影）
            ForEach(1..<8, id: \.self) { k in
                let fk = max(0, f - Double(k) * 0.014)
                let size: CGFloat = max(2, 6.0 - CGFloat(k) * 0.6)
                Circle()
                    .fill(P.hot)
                    .frame(width: size, height: size)
                    .opacity(max(0, 0.85 - Double(k) * 0.11))
                    .position(pointAt(p, fk))
            }
            // 白色高亮核心（径向渐变柔边 + 单层光晕）
            Circle()
                .fill(RadialGradient(colors: [.white, .white.opacity(0)],
                                     center: .center, startRadius: 1.5, endRadius: 5.5))
                .frame(width: 11, height: 11)
                .shadow(color: P.hot, radius: 5)
                .position(head)
        }
    }

    private func pointAt(_ p: [CGPoint], _ f: Double) -> CGPoint {
        let x = f * Double(p.count - 1)
        let i = min(p.count - 2, max(0, Int(x)))
        let frac = CGFloat(x - Double(i))
        let a = p[i], b = p[i + 1]
        return CGPoint(x: a.x + (b.x - a.x) * frac, y: a.y + (b.y - a.y) * frac)
    }

    private func pts(_ vals: [Double?], w: CGFloat, h: CGFloat) -> [CGPoint] {
        let n = vals.count
        guard n > 1 else { return [] }
        var out: [CGPoint] = []
        for (i, v) in vals.enumerated() {
            guard let v else { continue }
            out.append(CGPoint(x: w * CGFloat(i) / CGFloat(n - 1),
                               y: h - h * CGFloat(v) * 0.92 - h * 0.04))
        }
        return out
    }
    private func chartPath(_ vals: [Double?], w: CGFloat, h: CGFloat) -> Path {
        let p = pts(vals, w: w, h: h)
        var path = Path()
        guard let f = p.first else { return path }
        path.move(to: f)
        for pt in p.dropFirst() { path.addLine(to: pt) }
        return path
    }
    private func chartArea(_ vals: [Double?], w: CGFloat, h: CGFloat) -> Path {
        let p = pts(vals, w: w, h: h)
        var path = Path()
        guard let f = p.first, let l = p.last else { return path }
        path.move(to: CGPoint(x: f.x, y: h))
        path.addLine(to: f)
        for pt in p.dropFirst() { path.addLine(to: pt) }
        path.addLine(to: CGPoint(x: l.x, y: h))
        path.closeSubpath()
        return path
    }
    private func lastPoint(_ vals: [Double?], w: CGFloat, h: CGFloat) -> CGPoint? {
        pts(vals, w: w, h: h).last
    }
}

// MARK: - 进度条

struct Bar: View {
    @ObservedObject private var theme = SettingsStore.shared
    let fraction: Double
    var height: CGFloat = 5
    // 每个实例独立的随机相位与速度：光点彼此错开，不会同起同落
    @State private var phase = Double.random(in: 0..<6.0)
    @State private var rate = Double.random(in: 0.80...1.30)
    @Environment(\.fxEnabled) private var fx
    @ObservedObject private var ui = UIActivity.shared

    var body: some View {
        GeometryReader { geo in
            let fillW = max(height, geo.size.width * CGFloat(min(1, max(0, fraction))))
            ZStack(alignment: .leading) {
                // 静态底层：轨道 + 填充（不随动画重绘）
                Capsule().fill(P.track)
                Capsule().fill(P.barGrad)
                    .frame(width: fillW)
                    .shadow(color: P.accent.opacity(0.6), radius: 3)
                // 动画层只有巡游光点
                if fraction > 0.02 {
                    if gSnapshotMode {
                        lightLayer(fillW: fillW, time: 2.45)
                    } else if fx && ui.animsActive {
                        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { ctx in
                            // 套 ZStack 保持与外层一致的 leading 坐标系（见 LineChart 同注）
                            ZStack(alignment: .leading) {
                                lightLayer(fillW: fillW, time: ctx.date.timeIntervalSinceReferenceDate)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .frame(height: height)
    }

    /// 巡游光点层（周期随长度缩放，恒定像素速度 ≈ 30px/s：长条慢悠悠，短条轻快）
    @ViewBuilder
    private func lightLayer(fillW: CGFloat, time: Double) -> some View {
        let period = Double(max(3.0, min(14.0, fillW / 30.0)))
        let prog = CGFloat((time * rate + phase).truncatingRemainder(dividingBy: period) / period)
        let x = fillW * prog
        // 光尾（裁剪在进度条形状内）
        Rectangle()
            .fill(LinearGradient(colors: [.clear, .white.opacity(0.75)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(width: 18, height: height)
            .offset(x: x - 18)
            .frame(width: fillW, alignment: .leading)
            .clipShape(Capsule())
        // 柔边白光核心（径向渐变代替 blur，单层光晕）
        Circle()
            .fill(RadialGradient(colors: [.white, .white.opacity(0)],
                                 center: .center,
                                 startRadius: height * 0.25, endRadius: height * 0.75))
            .frame(width: height + 4, height: height + 4)
            .shadow(color: P.hot, radius: 4)
            .offset(x: x - (height + 4) / 2)
    }
}

// MARK: - 热力图（GitHub 风格，周一在顶行）

struct HeatGrid: View {
    @ObservedObject private var theme = SettingsStore.shared
    let days: [(date: Date, value: Double)]
    var cell: CGFloat = 11
    var gap: CGFloat = 3
    var showMonths: Bool = false

    private var maxV: Double { max(days.map(\.value).max() ?? 1, 1) }

    /// 列 = 周；每列 7 行（周一→周日），空位为 nil
    private var columns: [[(Date, Double)?]] {
        var cols: [[(Date, Double)?]] = []
        var col: [(Date, Double)?] = []
        let cal = Calendar.current
        if let first = days.first {
            let wd = (cal.component(.weekday, from: first.date) + 5) % 7  // 周一=0
            col = Array(repeating: nil, count: wd)
        }
        for d in days {
            col.append((d.date, d.value))
            if col.count == 7 { cols.append(col); col = [] }
        }
        if !col.isEmpty { col.append(contentsOf: Array(repeating: nil, count: 7 - col.count)); cols.append(col) }
        return cols
    }

    @Environment(\.fxEnabled) private var fx
    @ObservedObject private var ui = UIActivity.shared

    private let labelW: CGFloat = 12   // 星期标签列固定宽度（保证闪光层坐标可计算）

    var body: some View {
        if gSnapshotMode || !fx || !ui.animsActive {
            gridBase
        } else {
            // 静态格子 + Canvas 单层闪光：每帧只画正在闪的几个格子，不重建 90 个视图
            gridBase.overlay(alignment: .topLeading) {
                TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { ctx in
                    flashCanvas(time: ctx.date.timeIntervalSinceReferenceDate)
                }
                .allowsHitTesting(false)
            }
        }
    }

    /// 静态底图（不随动画重绘）
    private var gridBase: some View {
        let cols = columns
        return HStack(alignment: .top, spacing: gap) {
            // 星期标签
            VStack(alignment: .trailing, spacing: gap) {
                if showMonths { Text(" ").font(.system(size: 8)).frame(height: 10) }
                ForEach(0..<7, id: \.self) { r in
                    Text(["一", "二", "三", "四", "五", "六", "日"][r])
                        .font(.system(size: 8))
                        .foregroundStyle(r % 2 == 0 ? P.faint : .clear)
                        .frame(width: labelW, height: cell, alignment: .trailing)
                }
            }
            ForEach(Array(cols.enumerated()), id: \.offset) { _, col in
                VStack(spacing: gap) {
                    if showMonths {
                        Text(monthLabel(col))
                            .font(.system(size: 8)).foregroundStyle(P.faint)
                            .frame(height: 10)
                    }
                    ForEach(0..<7, id: \.self) { r in
                        RoundedRectangle(cornerRadius: cell * 0.28)
                            .fill(color(col[r]))
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
    }

    /// 闪光层：只绘制强度过阈值且当前正在闪亮的格子
    private func flashCanvas(time: Double) -> some View {
        let cols = columns
        let x0 = labelW + gap
        let y0: CGFloat = showMonths ? 10 + gap : 0
        let step = cell + gap
        return Canvas { g, _ in
            for (ci, col) in cols.enumerated() {
                for r in 0..<7 {
                    let f = flash(col[r], time)
                    guard f > 0.03 else { continue }
                    let rect = CGRect(x: x0 + CGFloat(ci) * step,
                                      y: y0 + CGFloat(r) * step,
                                      width: cell, height: cell)
                    let path = Path(roundedRect: rect, cornerRadius: cell * 0.28)
                    g.drawLayer { layer in
                        layer.addFilter(.shadow(color: .white.opacity(f * 0.9),
                                                radius: cell * 0.45))
                        layer.fill(path, with: .color(.white.opacity(f * 0.85)))
                    }
                }
            }
        }
    }

    /// 高用量格子的爆闪强度（0 = 不闪）：过阈值后振幅随用量递增，冷格保持静止。
    /// 返回值驱动白色高光叠加和光晕，峰值时格子接近亮白。
    /// 速度/相位由日期种子决定，稳定且各不相同。
    private func flash(_ item: (Date, Double)?, _ t: Double) -> Double {
        guard let item, item.1 > 0, t > 0 else { return 0 }
        // 与热力图配色相同的对数强度（0~1）
        let intensity = log10(1 + item.1) / log10(1 + maxV)
        let threshold = 0.55
        guard intensity > threshold else { return 0 }        // 用量不高 → 不闪
        // 振幅随强度线性增长：最热的格子峰值最亮
        let amp = 0.95 * (intensity - threshold) / (1 - threshold)
        let seed = Int(item.0.timeIntervalSince1970 / 86400)
        let speed = 1.2 + Double(seed % 7) * 0.35            // 1.2 ~ 3.3 rad/s
        let phase = Double(seed % 628) / 100.0               // 0 ~ 2π
        // 用 sin 的偶次幂让波形更"尖"：大部分时间较暗，瞬间打亮
        let wave = 0.5 + 0.5 * sin(t * speed + phase)
        return amp * pow(wave, 3)
    }

    private func color(_ item: (Date, Double)?) -> Color {
        guard let item else { return .clear }
        let t = item.1 > 0 ? 0.15 + 0.85 * (log10(1 + item.1) / log10(1 + maxV)) : 0
        return P.heat(t)
    }
    private func monthLabel(_ col: [(Date, Double)?]) -> String {
        for c in col {
            if let c, Calendar.current.component(.day, from: c.0) == 1 { return Fmt.month(c.0) }
        }
        return " "
    }
}

struct HeatLegend: View {
    @ObservedObject private var theme = SettingsStore.shared
    var body: some View {
        HStack(spacing: 3) {
            Text("少").font(.system(size: 8)).foregroundStyle(P.faint)
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(P.heat(Double(i) / 4 * 0.9 + (i == 0 ? 0 : 0.1)))
                    .frame(width: 8, height: 8)
            }
            Text("多").font(.system(size: 8)).foregroundStyle(P.faint)
        }
    }
}

// MARK: - 液态玻璃滑块（分段控件的选中指示器）

struct LiquidGlassPill: View {
    @ObservedObject private var theme = SettingsStore.shared
    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.10))
            .overlay(
                // 主题色玻璃体：上浓下淡
                Capsule().fill(
                    LinearGradient(colors: [P.accent.opacity(0.42), P.accent.opacity(0.16)],
                                   startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                // 镜面描边：左上强高光 → 右下弱反光
                Capsule().strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05), .white.opacity(0.22)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
            )
            .overlay(alignment: .top) {
                // 顶部内反光条（液态玻璃的"湿润"高光）
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.32), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: 7)
                    .padding(.horizontal, 6)
                    .padding(.top, 1.5)
            }
            .shadow(color: P.accent.opacity(0.45), radius: 7, y: 1)   // 主题色泛光
            .shadow(color: .black.opacity(0.25), radius: 3, y: 2)     // 落影分层
    }
}

// MARK: - Clawd 像素吉祥物（Claude Code 官方形象，按参考图逐格复刻）

struct ClawdSprite: View {
    /// 28×14 像素网格（高精度）：
    /// X=珊瑚基色 L=受光高亮 D=暗部阴影 E=眼睛 G=眼睛高光 .=透明
    /// 特征：宽方身体、两条竖线眼、右手高左手低、四条小短腿
    static let grid: [String] = [
        ".......LLLLLLLLLLLLLL.......",
        "......LXXXXXXXXXXXXXXD......",
        "......LXXGEXXXXXXGEXXD......",
        "......LXXEEXXXXXXEEXXXXXXX..",
        "......LXXEEXXXXXXEEXXXXXXX..",
        "......LXXEEXXXXXXEEXXXDDDD..",
        "..XXXXXXXXXXXXXXXXXXXD......",
        "..XXXXXXXXXXXXXXXXXXXD......",
        "......LXXXXXXXXXXXXXXD......",
        "......DDDDDDDDDDDDDDDD......",
        "........XX..XX..XX..XX......",
        "........XX..XX..XX..XX......",
        "........XX..XX..XX..XX......",
        "........DD..DD..DD..DD......",
    ]

    static func color(_ ch: Character) -> Color {
        switch ch {
        case "X": return Color(red: 0.85, green: 0.47, blue: 0.34)   // 珊瑚基色 (Anthropic Crail)
        case "L": return Color(red: 0.92, green: 0.57, blue: 0.42)   // 受光
        case "D": return Color(red: 0.70, green: 0.36, blue: 0.25)   // 暗部
        case "E": return Color(red: 0.12, green: 0.10, blue: 0.09)   // 眼睛
        case "G": return Color(red: 0.32, green: 0.27, blue: 0.24)   // 眼睛高光
        default: return .clear
        }
    }

    var body: some View {
        GeometryReader { geo in
            let rows = Self.grid
            let cols = rows[0].count
            let s = min(geo.size.width / CGFloat(cols), geo.size.height / CGFloat(rows.count))
            let ox = (geo.size.width - s * CGFloat(cols)) / 2
            let oy = (geo.size.height - s * CGFloat(rows.count)) / 2
            ZStack(alignment: .topLeading) {
                ForEach(0..<rows.count, id: \.self) { r in
                    let chars = Array(rows[r])
                    ForEach(0..<cols, id: \.self) { c in
                        if chars[c] != "." {
                            Rectangle()
                                .fill(Self.color(chars[c]))
                                .frame(width: s + 0.5, height: s + 0.5)   // +0.5 防像素缝
                                .offset(x: ox + s * CGFloat(c), y: oy + s * CGFloat(r))
                        }
                    }
                }
            }
        }
        .aspectRatio(2.0, contentMode: .fit)
    }
}

/// App 图标：深色圆角方块 + 微微歪头的 Clawd
struct IconView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.235, green: 0.231, blue: 0.212),
                                              Color(red: 0.157, green: 0.153, blue: 0.137)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
            ClawdSprite()
                .frame(width: 600)
                .rotationEffect(.degrees(-4))
                .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
        }
        .frame(width: 1024, height: 1024)
    }
}

// MARK: - 模块系统（小面板 / 主面板右栏均可自选组合）

enum Module: String, CaseIterable, Identifiable {
    case ring, goals, heatmap, last7, reset, health, models
    case gauge, pulse, clock, rose, odometer, cache, github
    var id: String { rawValue }
    var name: String {
        switch self {
        case .ring: return "圆环总览"
        case .goals: return "Token 小目标"
        case .heatmap: return "90天热力图"
        case .last7: return "最近7天"
        case .reset: return "下次重置"
        case .health: return "健康度"
        case .models: return "模型分布"
        case .gauge: return "今日仪表盘"
        case .pulse: return "实时脉搏"
        case .clock: return "昼夜热环"
        case .rose: return "周节律玫瑰"
        case .odometer: return "里程碑计数"
        case .cache: return "缓存命中率"
        case .github: return "GitHub 仓库"
        }
    }

    var icon: String {
        switch self {
        case .ring: return "chart.pie"
        case .goals: return "target"
        case .heatmap: return "calendar"
        case .last7: return "chart.xyaxis.line"
        case .reset: return "arrow.counterclockwise.circle"
        case .health: return "heart.text.square"
        case .models: return "cpu"
        case .gauge: return "gauge.with.needle"
        case .pulse: return "waveform.path"
        case .clock: return "clock"
        case .rose: return "camera.macro"
        case .odometer: return "flag.checkered"
        case .cache: return "memorychip"
        case .github: return "arrow.triangle.branch"
        }
    }

    /// 悬浮二级浮层里的详细介绍
    var detail: String {
        switch self {
        case .ring:
            return "周额度剩余圆环 + 今日累计曲线。圆环按『每周预算』计算本周还剩多少，中心显示剩余百分比和距重置天数；右侧是今日逐半小时累计曲线，虚线为近 7 日均值参考——一眼判断今天用得比平常快还是慢。"
        case .goals:
            return "今日 / 本周两条目标进度条。分别对照『今日目标』和『每周预算』显示已用量与完成百分比，超过 100% 时以高亮色提示。适合给自己设定节制线或冲量目标。"
        case .heatmap:
            return "GitHub 风格贡献格。近 90 天每天一格，颜色越亮当天用量越大（对数刻度），行序为周一到周日，底部附 90 天合计。长期使用习惯一目了然。"
        case .last7:
            return "近 7 天（含今日）逐日用量折线与 7 天合计，观察一周内的用量起伏和趋势拐点。"
        case .reset:
            return "距下一次周额度重置的日期与天数，进度条显示本周期已经过的比例。重置的星期与时刻可在『目标与周期』栏修改。"
        case .health:
            return "预算消耗体检：本周已用百分比 + 按当前节奏外推到重置日的预计总量，并显示连续活跃天数。预计值超过预算说明节奏偏快，该踩刹车了。"
        case .models:
            return "各模型（Opus / Fable / Sonnet…）历史累计用量排行与占比条，看清额度都花在了哪个模型上。"
        case .gauge:
            return "速度表风格的今日读数：240° 表盘 + 发光指针 + 刻度，量程为今日目标的 150%，指针角度直观反映目标完成度，冲破 100% 自有仪式感。"
        case .pulse:
            return "近 60 分钟逐分钟用量频谱，右上角 LIVE 呼吸灯表示实时监控，最右侧高亮柱为最近几分钟。挂着它就能感知当前会话的消耗节奏。"
        case .clock:
            return "24 小时钟面热力环：近 90 天用量按发生时段聚合，每格一小时，越亮代表该时段历史用量越大，白框标出当前时段。看清自己是白天型还是深夜型选手。"
        case .rose:
            return "极坐标玫瑰图：近 90 天用量按周一到周日聚合为七片花瓣，花瓣越大该天用得越多（面积开方校正），今天的花瓣高亮描边。"
        case .odometer:
            return "机械翻牌里程表：历史累计总量逐位显示，下方是距下一个里程碑（100M、200M、500M、1B…）的进度与差额。攒数字的快乐。"
        case .cache:
            return "输入侧 token 构成环：缓存读取 / 缓存写入 / 新鲜输入三者占比，中心为命中率。命中率越高，提示词缓存复用越好、同样额度干更多活——Claude Code 的省额度关键指标。"
        case .github:
            return "连接 GitHub 账号，显示头像、用户名和最近推送的仓库（名称 / 私有标记 / Star / 语言）。登录方式：在设置中粘贴 Personal Access Token（存入系统钥匙串），或自动复用已登录的 gh CLI。"
        }
    }
}

/// 模块通用小标题
struct ModHeader: View {
    let icon: String
    let title: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(P.accent2)
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(P.text)
        }
    }
}

/// 按 ID 分发模块视图（并注入该模块的光效开关）
struct ModuleCard: View {
    @ObservedObject private var theme = SettingsStore.shared
    let module: Module
    let m: Metrics
    var body: some View {
        content.environment(\.fxEnabled, fxOf(module))
    }
    @ViewBuilder
    private var content: some View {
        switch module {
        case .ring: RingModule(m: m)
        case .goals: GoalsModule(m: m)
        case .heatmap: HeatmapModule(m: m)
        case .last7: Last7Module(m: m)
        case .reset: ResetModule(m: m)
        case .health: HealthModule(m: m)
        case .models: ModelsModule(m: m)
        case .gauge: GaugeModule(m: m)
        case .pulse: PulseModule(m: m)
        case .clock: ClockModule(m: m)
        case .rose: RoseModule(m: m)
        case .odometer: OdometerModule(m: m)
        case .cache: CacheModule(m: m)
        case .github: GitHubModule()
        }
    }
}

// ── GitHub 仓库
struct GitHubModule: View {
    @ObservedObject private var gh = GitHubStore.shared
    @ObservedObject private var theme = SettingsStore.shared

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ModHeader(icon: "arrow.triangle.branch", title: "GitHub 仓库")
                    Spacer()
                    Button { gh.refresh() } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(P.sub)
                    }
                    .buttonStyle(.plain)
                }
                switch gh.state {
                case .notConfigured:
                    Text("未连接。在 ⚙️ 设置中粘贴 Personal Access Token，或安装并登录 gh CLI 后点右上角刷新。")
                        .font(.system(size: 9.5)).foregroundStyle(P.faint)
                        .fixedSize(horizontal: false, vertical: true)
                case .loading:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("加载中…").font(.system(size: 10)).foregroundStyle(P.sub)
                    }
                case .failed(let e):
                    Text("加载失败：\(e)")
                        .font(.system(size: 9.5)).foregroundStyle(P.hot)
                        .fixedSize(horizontal: false, vertical: true)
                case .loaded(let user, let repos):
                    HStack(spacing: 7) {
                        if let a = gh.avatar {
                            Image(nsImage: a)
                                .resizable().scaledToFill()
                                .frame(width: 20, height: 20)
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(P.accent.opacity(0.6), lineWidth: 1))
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 16)).foregroundStyle(P.sub)
                        }
                        Text(user.login)
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(P.text)
                        Spacer()
                        Tag(text: "\(user.publicRepos) 公开仓库")
                    }
                    ForEach(repos.prefix(6)) { r in
                        HStack(spacing: 5) {
                            Image(systemName: r.isPrivate ? "lock.fill" : "book.closed")
                                .font(.system(size: 8)).foregroundStyle(P.accent2)
                            Text(r.name)
                                .font(.system(size: 10.5)).foregroundStyle(P.text)
                                .lineLimit(1)
                            Spacer()
                            if let lang = r.language {
                                Text(lang).font(.system(size: 8.5)).foregroundStyle(P.faint)
                            }
                            if r.stars > 0 {
                                Text("★ \(r.stars)")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(P.accent2)
                            }
                        }
                    }
                    if repos.isEmpty {
                        Text("没有仓库").font(.system(size: 10)).foregroundStyle(P.faint)
                    }
                }
            }
        }
    }
}

// ── 圆环总览（周剩余圆环 + 今日曲线）
struct RingModule: View {
    @ObservedObject private var settings = SettingsStore.shared
    let m: Metrics
    var body: some View {
        let remain = max(0, 1 - m.week / max(settings.weeklyBudget, 1))
        Card {
            HStack(spacing: 14) {
                RingView(fraction: remain,
                         title: Fmt.pct(remain),
                         subtitle: "剩余\(m.daysLeft)天")
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Circle().fill(P.accent).frame(width: 6, height: 6)
                            .shadow(color: P.accent, radius: 3)
                        Text("今日 token")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(P.text)
                    }
                    Text("今日累计 · 近 7 日均值")
                        .font(.system(size: 8)).foregroundStyle(P.faint)
                    LineChart(series: m.todayCum, ref: m.avg7Cum,
                              xLabels: ["00", "12", "23"], height: 46)
                }
            }
        }
    }
}

// ── Token 小目标
struct GoalsModule: View {
    @ObservedObject private var settings = SettingsStore.shared
    let m: Metrics
    var body: some View {
        Card {
            VStack(spacing: 9) {
                HStack {
                    ModHeader(icon: "target", title: "Token 小目标")
                    Spacer()
                    Tag(text: "自然周")
                }
                goalRow(label: "今日", used: m.today, goal: settings.dailyGoal)
                goalRow(label: "本周", used: m.week, goal: settings.weeklyBudget)
            }
        }
    }
    private func goalRow(label: String, used: Double, goal: Double) -> some View {
        let f = used / max(goal, 1)
        return VStack(spacing: 4) {
            HStack {
                Text(label).font(.system(size: 11)).foregroundStyle(P.sub)
                Text("\(Fmt.tokens(used)) / \(Fmt.tokens(goal))")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(P.text)
                Spacer()
                Text(Fmt.pct(f))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(f > 1 ? P.hot : P.accent2)
            }
            Bar(fraction: f)
        }
    }
}

// ── 90 天热力图
struct HeatmapModule: View {
    let m: Metrics
    var body: some View {
        Card {
            VStack(spacing: 8) {
                HStack {
                    ModHeader(icon: "calendar", title: "近 90 天用量")
                    Spacer()
                    Tag(text: "混合口径")
                }
                HeatGrid(days: m.heat, cell: 12, gap: 3)
                HStack {
                    Text("合计 \(Fmt.tokens(m.total90))")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(P.sub)
                    Spacer()
                    HeatLegend()
                }
            }
        }
    }
}

// ── 最近 7 天
struct Last7Module: View {
    let m: Metrics
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                ModHeader(icon: "chart.xyaxis.line", title: "最近 7 天")
                LineChart(series: m.last7Daily, height: 64)
                HStack(alignment: .firstTextBaseline) {
                    Text(Fmt.tokens(m.last7Sum))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(P.text)
                    Text("7 天合计").font(.system(size: 9)).foregroundStyle(P.faint)
                }
            }
        }
    }
}

// ── 下次重置
struct ResetModule: View {
    let m: Metrics
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                ModHeader(icon: "arrow.counterclockwise.circle", title: "下次重置")
                Text("\(Fmt.day(m.nextReset)) · \(m.daysLeft) 天后")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(P.text)
                let elapsed = min(1, max(0, Date().timeIntervalSince(m.lastReset) / (7 * 86400)))
                Bar(fraction: elapsed, height: 4)
                Text("本周期已过 \(Fmt.pct(elapsed))")
                    .font(.system(size: 9)).foregroundStyle(P.faint)
            }
        }
    }
}

// ── 健康度
struct HealthModule: View {
    @ObservedObject private var settings = SettingsStore.shared
    let m: Metrics
    var body: some View {
        let used = m.week / max(settings.weeklyBudget, 1)
        let elapsed = max(0.02, Date().timeIntervalSince(m.lastReset) / (7 * 86400))
        let projected = m.week / elapsed
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    ModHeader(icon: "heart.text.square", title: "健康度")
                    Spacer()
                    Tag(text: "连续活跃 \(m.streak) 天")
                }
                HStack {
                    Text("预算已用").font(.system(size: 10)).foregroundStyle(P.sub)
                    Spacer()
                    Text(Fmt.pct(used))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(used > 1 ? P.hot : P.accent2)
                }
                Bar(fraction: used)
                Text("按当前节奏，重置前约 \(Fmt.tokens(projected))（预算的 \(Fmt.pct(projected / max(settings.weeklyBudget, 1)))）")
                    .font(.system(size: 9)).foregroundStyle(P.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// ── 模型分布
struct ModelsModule: View {
    let m: Metrics
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                ModHeader(icon: "cpu", title: "模型分布")
                let top = Array(m.models.prefix(4))
                let sum = max(m.lifetime, 1)
                ForEach(Array(top.enumerated()), id: \.offset) { _, mo in
                    VStack(spacing: 3) {
                        HStack {
                            Text(mo.name.replacingOccurrences(of: "claude-", with: ""))
                                .font(.system(size: 10)).foregroundStyle(P.text)
                            Spacer()
                            Text(Fmt.tokens(mo.tokens))
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(P.accent2)
                        }
                        Bar(fraction: mo.tokens / sum, height: 3)
                    }
                }
                if top.isEmpty {
                    Text("暂无数据").font(.system(size: 11)).foregroundStyle(P.faint)
                }
            }
        }
    }
}

// ── 今日仪表盘（240° 速度表 + 指针）
struct GaugeModule: View {
    @ObservedObject private var settings = SettingsStore.shared
    let m: Metrics
    var body: some View {
        let goal = max(settings.dailyGoal, 1)
        let frac = m.today / goal                        // 1.0 = 达成目标
        let capped = min(frac, 1.5)                      // 量程 0~150%
        let needleDeg = -120 + 240 * capped / 1.5
        Card {
            VStack(spacing: 2) {
                HStack {
                    ModHeader(icon: "gauge.with.needle", title: "今日仪表盘")
                    Spacer()
                    Tag(text: "量程 150%")
                }
                ZStack {
                    // 背景弧
                    Circle().trim(from: 0, to: 2.0 / 3)
                        .stroke(P.track, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                        .rotationEffect(.degrees(150))
                    // 进度弧
                    Circle().trim(from: 0, to: 2.0 / 3 * capped / 1.5)
                        .stroke(P.ringGrad, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                        .rotationEffect(.degrees(150))
                        .shadow(color: P.accent.opacity(0.6), radius: 5)
                    // 刻度
                    ForEach(0..<9, id: \.self) { i in
                        Capsule().fill(Color.white.opacity(0.25))
                            .frame(width: 2, height: 6)
                            .offset(y: -46)
                            .rotationEffect(.degrees(-120 + Double(i) * 30))
                    }
                    // 指针
                    Capsule().fill(P.hot)
                        .frame(width: 3, height: 38)
                        .offset(y: -19)
                        .rotationEffect(.degrees(needleDeg))
                        .shadow(color: P.accent, radius: 4)
                    Circle().fill(P.hot).frame(width: 8, height: 8)
                        .shadow(color: P.accent, radius: 3)
                    // 读数
                    VStack(spacing: 0) {
                        Text(Fmt.tokens(m.today))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(P.text)
                        Text("目标 \(Fmt.pct(frac))")
                            .font(.system(size: 9)).foregroundStyle(frac > 1 ? P.hot : P.sub)
                    }
                    .offset(y: 34)
                }
                .frame(width: 120, height: 116)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// ── 实时脉搏（近 60 分钟逐分钟 + 呼吸灯）
struct PulseModule: View {
    @ObservedObject private var theme = SettingsStore.shared
    let m: Metrics
    @State private var breathe = false
    @Environment(\.fxEnabled) private var fx
    @ObservedObject private var ui = UIActivity.shared
    var body: some View {
        let maxV = max(m.minute60.max() ?? 1, 1)
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ModHeader(icon: "waveform.path", title: "实时脉搏")
                    Spacer()
                    Circle().fill(P.accent).frame(width: 6, height: 6)
                        .scaleEffect(breathe ? 1.3 : 0.75)
                        .opacity(breathe ? 1 : 0.5)
                        .shadow(color: P.accent, radius: breathe ? 5 : 2)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                                   value: breathe)
                        .onAppear { breathe = true }
                    Text("LIVE").font(.system(size: 8, weight: .bold)).foregroundStyle(P.accent2)
                }
                Group {
                    if gSnapshotMode {
                        pulseBars(maxV, time: 2.45)
                    } else if !fx || !ui.animsActive {
                        pulseBars(maxV, time: -1)
                    } else {
                        TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { ctx in
                            pulseBars(maxV, time: ctx.date.timeIntervalSinceReferenceDate)
                        }
                    }
                }
                .frame(height: 42, alignment: .bottom)
                HStack {
                    Text("60 分钟前").font(.system(size: 8)).foregroundStyle(P.faint)
                    Spacer()
                    Text("近1小时 \(Fmt.tokens(m.min60Sum))")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(P.accent2)
                    Spacer()
                    Text("现在").font(.system(size: 8)).foregroundStyle(P.faint)
                }
            }
        }
    }

    /// 频谱柱 + 自下而上的能量传输光带（相邻柱相位递增形成波浪）
    private func pulseBars(_ maxV: Double, time: Double) -> some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(0..<60, id: \.self) { i in
                let v = m.minute60[i]
                let hb = max(3, 40 * v / maxV)
                let band: CGFloat = 9
                let prog = (time * 0.40 + Double(i) * 0.045).truncatingRemainder(dividingBy: 1)
                RoundedRectangle(cornerRadius: 1)
                    .fill(i >= 57 ? AnyShapeStyle(P.hot) : AnyShapeStyle(P.accent.opacity(0.35 + 0.65 * v / maxV)))
                    .frame(height: hb)
                    .overlay(alignment: .bottom) {
                        if v > 0 && time >= 0 {
                            Rectangle()
                                .fill(LinearGradient(colors: [.clear, .white.opacity(0.85), .clear],
                                                     startPoint: .bottom, endPoint: .top))
                                .frame(height: band)
                                .offset(y: band - (hb + 2 * band) * prog)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 1))
                    .frame(maxWidth: .infinity, alignment: .bottom)
            }
        }
    }
}

// ── 昼夜热环（24 小时用量分布钟面）
struct ClockModule: View {
    @ObservedObject private var theme = SettingsStore.shared
    let m: Metrics
    var body: some View {
        let maxV = max(m.hourDist.max() ?? 1, 1)
        let nowHour = Calendar.current.component(.hour, from: Date())
        Card {
            VStack(spacing: 6) {
                HStack {
                    ModHeader(icon: "clock", title: "昼夜热环")
                    Spacer()
                    Tag(text: "近90天分布")
                }
                ZStack {
                    ForEach(0..<24, id: \.self) { h in
                        let v = m.hourDist[h]
                        let t = v > 0 ? 0.15 + 0.85 * (log10(1 + v) / log10(1 + maxV)) : 0
                        Circle()
                            .trim(from: CGFloat(h) / 24 + 0.005, to: CGFloat(h + 1) / 24 - 0.005)
                            .stroke(P.heat(t), style: StrokeStyle(lineWidth: 13, lineCap: .butt))
                            .rotationEffect(.degrees(-90))
                    }
                    // 当前小时白框高亮
                    Circle()
                        .trim(from: CGFloat(nowHour) / 24 + 0.004, to: CGFloat(nowHour + 1) / 24 - 0.004)
                        .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 2))
                        .rotationEffect(.degrees(-90))
                        .padding(-8)
                    VStack(spacing: 1) {
                        Text(String(format: "%02d:00", nowHour))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(P.text)
                        Text("当前时段")
                            .font(.system(size: 8)).foregroundStyle(P.faint)
                    }
                    // 方位小时标
                    Text("0").font(.system(size: 8)).foregroundStyle(P.faint).offset(y: -76)
                    Text("6").font(.system(size: 8)).foregroundStyle(P.faint).offset(x: 76)
                    Text("12").font(.system(size: 8)).foregroundStyle(P.faint).offset(y: 76)
                    Text("18").font(.system(size: 8)).foregroundStyle(P.faint).offset(x: -76)
                }
                .frame(width: 130, height: 130)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// ── 周节律玫瑰（周一~周日极坐标玫瑰图）
struct RoseWedge: Shape {
    let start: Angle
    let end: Angle
    let frac: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2 * frac
        p.move(to: c)
        p.addArc(center: c, radius: r, startAngle: start, endAngle: end, clockwise: false)
        p.closeSubpath()
        return p
    }
}

struct RoseModule: View {
    @ObservedObject private var theme = SettingsStore.shared
    let m: Metrics
    @Environment(\.fxEnabled) private var fx
    @ObservedObject private var ui = UIActivity.shared
    private static let names = ["一", "二", "三", "四", "五", "六", "日"]

    private var maxV: Double { max(m.weekdayDist.max() ?? 1, 1) }
    private var today: Int { (Calendar.current.component(.weekday, from: Date()) + 5) % 7 }

    private func frac(_ i: Int) -> CGFloat {
        max(0.10, CGFloat(sqrt(m.weekdayDist[i] / maxV)))   // 开方让面积感知更准
    }
    private func angles(_ i: Int) -> (Angle, Angle) {
        let a0: Double = Double(i) / 7.0 * 360.0 - 90.0 + 3.0
        let a1: Double = Double(i + 1) / 7.0 * 360.0 - 90.0 - 3.0
        return (Angle.degrees(a0), Angle.degrees(a1))
    }

    @ViewBuilder
    private func wedge(_ i: Int) -> some View {
        let (a0, a1) = angles(i)
        let f = frac(i)
        RoseWedge(start: a0, end: a1, frac: f)
            .fill(P.accent.opacity(0.16 + 0.5 * Double(f)))
            .overlay(
                RoseWedge(start: a0, end: a1, frac: f)
                    .stroke(i == today ? P.hot : P.accent2.opacity(0.55),
                            lineWidth: i == today ? 1.6 : 0.8))
    }

    @ViewBuilder
    private func label(_ i: Int) -> some View {
        let mid: Double = (Double(i) + 0.5) / 7.0 * 2.0 * Double.pi - Double.pi / 2.0
        Text(Self.names[i])
            .font(.system(size: 8, weight: i == today ? .bold : .regular))
            .foregroundStyle(i == today ? P.hot : P.faint)
            .offset(x: CGFloat(cos(mid)) * 72, y: CGFloat(sin(mid)) * 72)
    }

    var body: some View {
        Card {
            VStack(spacing: 6) {
                HStack {
                    ModHeader(icon: "camera.macro", title: "周节律玫瑰")
                    Spacer()
                    Tag(text: "近90天分布")
                }
                ZStack {
                    // 参考圈
                    Circle().stroke(Color.white.opacity(0.07), lineWidth: 1).frame(width: 116, height: 116)
                    Circle().stroke(Color.white.opacity(0.05), lineWidth: 1).frame(width: 58, height: 58)
                    ForEach(0..<7, id: \.self) { i in wedge(i) }
                    // 声呐光环：从扇心向扇缘扩散的光波，只在花瓣内可见
                    if !gSnapshotMode && fx && ui.animsActive {
                        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                            let t = ctx.date.timeIntervalSinceReferenceDate
                            let prog = t.truncatingRemainder(dividingBy: 2.8) / 2.8
                            Circle()
                                .stroke(Color.white.opacity(0.85 * (1 - prog)), lineWidth: 6)
                                .frame(width: max(2, 150 * prog), height: max(2, 150 * prog))
                                .blur(radius: 2.5)
                        }
                        .mask(
                            ZStack {
                                ForEach(0..<7, id: \.self) { i in
                                    let (a0, a1) = angles(i)
                                    RoseWedge(start: a0, end: a1, frac: frac(i))
                                        .fill(Color.white)
                                }
                            }
                        )
                    }
                    ForEach(0..<7, id: \.self) { i in label(i) }
                }
                .frame(width: 150, height: 150)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// ── 里程碑计数（翻牌里程表 + 下一目标）
struct OdometerModule: View {
    @ObservedObject private var theme = SettingsStore.shared
    let m: Metrics
    private static let milestones: [Double] = [10e6, 20e6, 50e6, 100e6, 200e6, 500e6,
                                               1e9, 2e9, 5e9, 10e9, 20e9, 50e9, 100e9]
    var body: some View {
        let next = Self.milestones.first { $0 > m.lifetime } ?? m.lifetime * 2
        Card {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    ModHeader(icon: "flag.checkered", title: "里程碑计数")
                    Spacer()
                    Tag(text: "历史累计")
                }
                HStack(spacing: 3) {
                    ForEach(Array(Fmt.tokens(m.lifetime).enumerated()), id: \.offset) { _, ch in
                        Text(String(ch))
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(P.text)
                            .frame(width: ch == "." ? 12 : 22, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.white.opacity(0.07))
                                    .overlay(   // 翻牌上半高光
                                        VStack(spacing: 0) {
                                            LinearGradient(colors: [.white.opacity(0.12), .white.opacity(0.02)],
                                                           startPoint: .top, endPoint: .bottom)
                                            Color.clear
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 5)))
                                    .overlay(Rectangle().fill(Color.black.opacity(0.35)).frame(height: 1))
                                    .overlay(RoundedRectangle(cornerRadius: 5)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                            )
                    }
                    Spacer()
                }
                Bar(fraction: m.lifetime / next, height: 4)
                Text("下一里程碑 \(Fmt.tokens(next))，还差 \(Fmt.tokens(next - m.lifetime))")
                    .font(.system(size: 9)).foregroundStyle(P.faint)
            }
        }
    }
}

// ── 缓存命中率（输入侧构成环）
struct CacheModule: View {
    @ObservedObject private var theme = SettingsStore.shared
    let m: Metrics
    var body: some View {
        let sum = max(m.totInput + m.totCacheRead + m.totCacheWrite, 1)
        let read = m.totCacheRead / sum
        let write = m.totCacheWrite / sum
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ModHeader(icon: "memorychip", title: "缓存命中率")
                    Spacer()
                    Tag(text: "输入侧构成")
                }
                HStack(spacing: 14) {
                    ZStack {
                        Circle().stroke(P.track, lineWidth: 10)
                        Circle().trim(from: 0, to: read)
                            .stroke(P.accent, style: StrokeStyle(lineWidth: 10, lineCap: .butt))
                            .rotationEffect(.degrees(-90))
                            .shadow(color: P.accent.opacity(0.5), radius: 4)
                        Circle().trim(from: read, to: read + write)
                            .stroke(P.accent2.opacity(0.75), style: StrokeStyle(lineWidth: 10, lineCap: .butt))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text(Fmt.pct(read))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(P.text)
                            Text("命中").font(.system(size: 8)).foregroundStyle(P.faint)
                        }
                    }
                    .frame(width: 80, height: 80)
                    VStack(alignment: .leading, spacing: 6) {
                        legend(color: P.accent, name: "缓存读取", value: m.totCacheRead)
                        legend(color: P.accent2.opacity(0.75), name: "缓存写入", value: m.totCacheWrite)
                        legend(color: Color.white.opacity(0.35), name: "新鲜输入", value: m.totInput)
                    }
                }
                Text("命中率越高，重复上下文越省——这是省额度的关键指标")
                    .font(.system(size: 9)).foregroundStyle(P.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func legend(color: Color, name: String, value: Double) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(name).font(.system(size: 10)).foregroundStyle(P.sub)
            Spacer()
            Text(Fmt.tokens(value))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(P.text)
        }
    }
}

// MARK: - 可拖拽的液态玻璃分段控件

struct LiquidTabBar: View {
    @Binding var selection: Tab
    @ObservedObject private var theme = SettingsStore.shared
    @State private var dragCenterX: CGFloat? = nil   // 拖动中指示器的中心（覆盖槽位定位）
    @State private var isDragging = false
    @State private var lastNearest = -1

    private let segW: CGFloat = 88
    private let segH: CGFloat = 28
    private let pad: CGFloat = 3
    private var tabs: [Tab] { Tab.allCases }

    var body: some View {
        let selIdx = tabs.firstIndex(of: selection) ?? 0
        let slotCenter = pad + CGFloat(selIdx) * segW + segW / 2
        let center = dragCenterX ?? slotCenter

        ZStack(alignment: .topLeading) {
            // 玻璃凹槽轨道
            Capsule()
                .fill(Color.white.opacity(0.045))
                .overlay(Capsule().strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.05), .white.opacity(0.14)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1))
            // 玻璃透镜（拖动时被"提起"微放大）
            LiquidGlassPill()
                .frame(width: segW, height: segH)
                .offset(x: center - segW / 2, y: pad)
                .scaleEffect(isDragging ? 1.07 : 1)
                .animation(.spring(response: 0.30, dampingFraction: 0.62), value: isDragging)
            // 标签（等宽分段，拖拽计算简单且视觉整齐）
            HStack(spacing: 0) {
                ForEach(tabs, id: \.self) { t in
                    Text(t.rawValue)
                        .font(.system(size: 11, weight: t == selection ? .semibold : .regular))
                        .foregroundStyle(t == selection ? P.text : P.sub)
                        .frame(width: segW, height: segH)
                }
            }
            .padding(pad)
        }
        .frame(width: pad * 2 + segW * CGFloat(tabs.count), height: segH + pad * 2)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    isDragging = true
                    // 指示器中心跟随鼠标，限制在轨道内
                    let c = min(max(v.location.x, pad + segW / 2),
                                pad + (CGFloat(tabs.count) - 0.5) * segW)
                    dragCenterX = c
                    let idx = nearestIndex(c)
                    if idx != lastNearest {
                        if lastNearest >= 0 {   // 越过分界：触控板震动 + 内容实时切换
                            NSHapticFeedbackManager.defaultPerformer
                                .perform(.alignment, performanceTime: .default)
                        }
                        lastNearest = idx
                        withAnimation(.easeOut(duration: 0.15)) { selection = tabs[idx] }
                    }
                }
                .onEnded { _ in
                    let idx = nearestIndex(dragCenterX ?? slotCenter)
                    lastNearest = -1
                    // 松手：弹性吸附到最近槽位（点击 = 没有位移的拖拽，同样生效）
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                        selection = tabs[idx]
                        dragCenterX = nil
                        isDragging = false
                    }
                }
        )
    }

    private func nearestIndex(_ centerX: CGFloat) -> Int {
        let i = Int(round((centerX - pad - segW / 2) / segW))
        return min(max(i, 0), tabs.count - 1)
    }
}

// MARK: - 菜单栏弹出面板（复刻照片 1）

struct PopoverView: View {
    @ObservedObject var store = UsageStore.shared
    @ObservedObject var settings = SettingsStore.shared

    var body: some View {
        let m = store.metrics
        VStack(spacing: 10) {
            // ── 按用户配置渲染模块（超高时可滚动，上限 660）
            MaybeScroll {
                VStack(spacing: 10) {
                    ForEach(settings.popoverModules, id: \.self) { id in
                        if let mod = Module(rawValue: id) {
                            ModuleCard(module: mod, m: m)
                        }
                    }
                    if settings.popoverModules.isEmpty {
                        Card {
                            Text("没有启用任何模块——去 ⚙️ 设置里勾选")
                                .font(.system(size: 11)).foregroundStyle(P.faint)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .frame(maxHeight: gSnapshotMode ? nil : 660)

            // ── 底部按钮
            HStack(spacing: 8) {
                roundBtn("gearshape.fill") { AppDelegate.shared.openSettings() }
                Button { AppDelegate.shared.openMain() } label: {
                    Text("打开 MyClaude")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(P.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Capsule().fill(Color.white.opacity(0.10))
                            .overlay(Capsule().strokeBorder(P.cardStroke, lineWidth: 1)))
                }
                .buttonStyle(.plain)
                roundBtn("power") { AppDelegate.shared.quit() }
            }
        }
        .padding(12)
        .frame(width: 312)
        .background(
            // 几乎全透：颜色由背后毛玻璃透出的壁纸决定 + 可选的用户自定义染色层
            ZStack {
                LinearGradient(colors: [Color.black.opacity(0.06), Color.black.opacity(0.16)],
                               startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [P.tint.opacity(settings.tintStrength * 0.55),
                                        P.tint.opacity(settings.tintStrength)],
                               startPoint: .top, endPoint: .bottom)
            }
        )
    }

    private func roundBtn(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(P.sub)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.08))
                    .overlay(Circle().strokeBorder(P.cardStroke, lineWidth: 1)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 主窗口仪表盘（复刻照片 2）

enum Tab: String, CaseIterable {
    case today = "今日估算", trend = "用量趋势", rank = "项目排行", block = "5h窗"
}

struct DashboardView: View {
    @ObservedObject var store = UsageStore.shared
    @ObservedObject var settings = SettingsStore.shared
    @State private var tab: Tab = .trend
    @ObservedObject private var ui = UIActivity.shared

    var body: some View {
        let m = store.metrics
        VStack(spacing: 12) {
            statRow(m)
            tabRow(m)
            // 左右两栏各自独立滚动：模块再多也不会把顶部内容顶出窗口
            HStack(alignment: .top, spacing: 12) {
                MaybeScroll {
                    VStack(spacing: 12) {
                        leftContent(m)
                        if tab != .today { todayRhythmCard(m) }
                    }
                    .padding(.bottom, 4)
                }
                .frame(maxWidth: .infinity)
                MaybeScroll {
                    VStack(spacing: 12) {
                        ForEach(settings.dashboardModules, id: \.self) { id in
                            if let mod = Module(rawValue: id) {
                                ModuleCard(module: mod, m: m)
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
                .frame(width: 280)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(16)
        .padding(.top, 24)   // 给隐藏标题栏留空间
        .frame(minWidth: 1000, minHeight: 740)
        .background(
            // 液态玻璃：模糊后的桌面透上来 + 可选的用户自定义染色层
            ZStack {
                LinearGradient(colors: [Color.black.opacity(0.05), Color.black.opacity(0.18)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                LinearGradient(colors: [P.tint.opacity(settings.tintStrength * 0.55),
                                        P.tint.opacity(settings.tintStrength)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        )
        .gesture(WindowDragGesture())   // 空白处拖动 = 移动窗口（控件手势优先）
    }

    // ── 顶部统计卡
    private func statRow(_ m: Metrics) -> some View {
        let remain = max(0, 1 - m.week / max(settings.weeklyBudget, 1))
        return HStack(spacing: 12) {
            statCard(icon: "gauge.with.needle", title: "7天剩余", value: Fmt.pct(remain)) {
                VStack(alignment: .leading, spacing: 5) {
                    Bar(fraction: remain)
                    Text("重置 \(Fmt.day(m.nextReset)) \(Fmt.hm(m.nextReset))")
                        .font(.system(size: 9)).foregroundStyle(P.faint)
                }
            }
            statCard(icon: "sun.max.fill", title: "今日", value: Fmt.tokens(m.today)) {
                Text("输入 \(Fmt.tokens(m.todayInput)) · 输出 \(Fmt.tokens(m.todayOutput))")
                    .font(.system(size: 9)).foregroundStyle(P.faint)
            }
            statCard(icon: "clock.arrow.circlepath", title: "近7天", value: Fmt.tokens(m.last7Sum)) {
                Text("日均 \(Fmt.tokens(m.last7Sum / 7))")
                    .font(.system(size: 9)).foregroundStyle(P.faint)
            }
            statCard(icon: "chart.bar.fill", title: "累计", value: Fmt.tokens(m.lifetime)) {
                Text("近90天 \(Fmt.tokens(m.total90))")
                    .font(.system(size: 9)).foregroundStyle(P.faint)
            }
        }
    }

    private func statCard<F: View>(icon: String, title: String, value: String,
                                   @ViewBuilder footer: () -> F) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: icon).font(.system(size: 10)).foregroundStyle(P.accent2)
                    Text(title).font(.system(size: 11)).foregroundStyle(P.sub)
                }
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(P.text)
                footer()
            }
        }
    }

    // ── 标签栏（可拖拽的液态玻璃滑块）
    private func tabRow(_ m: Metrics) -> some View {
        HStack {
            LiquidTabBar(selection: $tab)
            Spacer()
            Text("下次重置 \(Fmt.day(m.nextReset)) · \(m.daysLeft) 天后")
                .font(.system(size: 10)).foregroundStyle(P.sub)
        }
    }

    // ── 左侧主内容
    @ViewBuilder
    private func leftContent(_ m: Metrics) -> some View {
        switch tab {
        case .trend:
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        header("square.grid.3x3.fill", "最近 90 天用量")
                        Spacer()
                        Tag(text: "近90天合计 \(Fmt.tokens(m.total90))")
                    }
                    HStack {
                        Spacer()
                        HeatGrid(days: m.heat, cell: 26, gap: 5, showMonths: true)
                            .environment(\.fxEnabled, fxOf(.heatmap))
                        Spacer()
                    }
                    HStack { Spacer(); HeatLegend() }
                }
            }
        case .today:
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        header("waveform.path.ecg", "今日累计节奏")
                        Spacer()
                        let proj = projected(m)
                        Tag(text: "预计全天 \(Fmt.tokens(proj))")
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Fmt.tokens(m.today))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(P.text)
                        if m.yesterday > 0 {
                            let d = m.today / m.yesterday - 1
                            Text((d >= 0 ? "较昨日 +" : "较昨日 ") + Fmt.pct(d))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(d >= 0 ? P.accent2 : P.sub)
                        }
                    }
                    LineChart(series: m.todayCum, ref: m.avg7Cum,
                              xLabels: ["00", "06", "12", "18", "23"], height: 150)
                        .environment(\.fxEnabled, fxKey("rhythm"))
                }
            }
        case .rank:
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    header("list.number", "项目排行")
                    let top = Array(m.projects.prefix(7))
                    let maxV = top.first?.tokens ?? 1
                    ForEach(Array(top.enumerated()), id: \.offset) { i, p in
                        VStack(spacing: 3) {
                            HStack {
                                Text("\(i + 1). \(p.name)")
                                    .font(.system(size: 11)).foregroundStyle(P.text)
                                    .lineLimit(1)
                                Spacer()
                                Text(Fmt.tokens(p.tokens))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(P.accent2)
                                Text(Fmt.pct(p.tokens / max(m.lifetime, 1)))
                                    .font(.system(size: 9)).foregroundStyle(P.faint)
                                    .frame(width: 34, alignment: .trailing)
                            }
                            Bar(fraction: p.tokens / maxV, height: 4)
                        }
                    }
                    if top.isEmpty { emptyHint }
                }
            }
        case .block:
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    header("timer", "5 小时窗口")
                    if let b = m.block {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(Fmt.tokens(b.tokens))
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(P.text)
                            Text("本窗口用量").font(.system(size: 10)).foregroundStyle(P.sub)
                        }
                        let now = Date()
                        let frac = now.timeIntervalSince(b.start) / (5 * 3600)
                        Bar(fraction: frac)
                        HStack {
                            Text("窗口 \(Fmt.hm(b.start)) – \(Fmt.hm(b.end))")
                                .font(.system(size: 10)).foregroundStyle(P.sub)
                            Spacer()
                            let left = max(0, b.end.timeIntervalSince(now))
                            Text("剩余 \(Int(left) / 3600)时\((Int(left) % 3600) / 60)分")
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(P.accent2)
                        }
                        // 每 30 分钟柱状（带上升光带）
                        let maxBar = max(b.halfHourBars.max() ?? 1, 1)
                        Group {
                            if gSnapshotMode {
                                blockBars(b, maxBar, time: 2.45)
                            } else if !fxKey("blockbars") || !ui.animsActive {
                                blockBars(b, maxBar, time: -1)
                            } else {
                                TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { ctx in
                                    blockBars(b, maxBar, time: ctx.date.timeIntervalSinceReferenceDate)
                                }
                            }
                        }
                        .frame(height: 74, alignment: .bottom)
                    } else {
                        Text("当前没有活跃的 5 小时窗口")
                            .font(.system(size: 12)).foregroundStyle(P.sub)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
            }
        }
    }

    // ── 今日累计节奏（趋势页下方）
    private func todayRhythmCard(_ m: Metrics) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    header("waveform.path.ecg", "今日累计节奏")
                    Spacer()
                    if m.yesterday > 0 {
                        let d = m.today / m.yesterday - 1
                        Tag(text: (d >= 0 ? "较昨日 +" : "较昨日 ") + Fmt.pct(d))
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("今日 \(Fmt.tokens(m.today))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(P.text)
                }
                LineChart(series: m.todayCum, ref: m.avg7Cum,
                          xLabels: ["00", "06", "12", "18", "23"], height: 76)
                    .environment(\.fxEnabled, fxKey("rhythm"))
            }
        }
    }

    private func header(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(P.accent2)
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(P.text)
        }
    }

    /// 5h 窗柱状 + 自下而上的能量传输光带
    private func blockBars(_ b: BlockInfo, _ maxBar: Double, time: Double) -> some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(0..<10, id: \.self) { i in
                let v = b.halfHourBars[i]
                let hb = max(4, 70 * v / maxBar)
                let band: CGFloat = 16
                let prog = (time * 0.35 + Double(i) * 0.09).truncatingRemainder(dividingBy: 1)
                RoundedRectangle(cornerRadius: 3)
                    .fill(v > 0 ? AnyShapeStyle(P.barGrad) : AnyShapeStyle(P.track))
                    .frame(height: hb)
                    .overlay(alignment: .bottom) {
                        if v > 0 && time >= 0 {
                            Rectangle()
                                .fill(LinearGradient(colors: [.clear, .white.opacity(0.8), .clear],
                                                     startPoint: .bottom, endPoint: .top))
                                .frame(height: band)
                                .offset(y: band - (hb + 2 * band) * prog)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .frame(maxWidth: .infinity, alignment: .bottom)
            }
        }
    }

    private var emptyHint: some View {
        Text("暂无数据").font(.system(size: 11)).foregroundStyle(P.faint)
    }

    private func projected(_ m: Metrics) -> Double {
        let frac = Date().timeIntervalSince(Calendar.current.startOfDay(for: Date())) / 86400
        return frac > 0.02 ? m.today / frac : m.today
    }
}

// MARK: - 设置窗口

/// 悬浮芯片的位置锚点
struct HoverAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        if let n = nextValue() { value = n }
    }
}

/// 模块详细介绍浮层（二级菜单）
struct ModuleTooltip: View {
    let module: Module
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: module.icon)
                    .font(.system(size: 10)).foregroundStyle(P.accent2)
                Text(module.name)
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(P.text)
            }
            Text(module.detail)
                .font(.system(size: 9.5))
                .foregroundStyle(Color.white.opacity(0.78))
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(width: 250, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.11, green: 0.09, blue: 0.12).opacity(0.97))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.08)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 14, y: 6)
        )
    }
}

struct SettingsView: View {
    @ObservedObject var settings = SettingsStore.shared
    @State private var dailyText = ""
    @State private var weeklyText = ""
    @State private var hoveredModule: Module? = nil
    @ObservedObject private var gh = GitHubStore.shared
    @State private var ghTokenInput = ""

    /// 预设主题色板
    private static let presets: [[Double]] = [
        [1.00, 0.18, 0.45],   // 霓虹粉（默认）
        [1.00, 0.33, 0.25],   // 珊瑚红
        [1.00, 0.62, 0.20],   // 落日橙
        [0.95, 0.80, 0.25],   // 琥珀金
        [0.35, 0.85, 0.50],   // 翡翠绿
        [0.25, 0.78, 0.88],   // 冰川青
        [0.32, 0.55, 1.00],   // 深海蓝
        [0.66, 0.42, 1.00],   // 星云紫
    ]

    private func colorBinding(_ keyPath: ReferenceWritableKeyPath<SettingsStore, [Double]>) -> Binding<Color> {
        Binding(
            get: {
                let c = settings[keyPath: keyPath]
                return Color(red: c[0], green: c[1], blue: c[2])
            },
            set: { c in
                if let ns = NSColor(c).usingColorSpace(.sRGB) {
                    settings[keyPath: keyPath] = [Double(ns.redComponent),
                                                  Double(ns.greenComponent),
                                                  Double(ns.blueComponent)]
                }
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("设置")
                .font(.system(size: 15, weight: .bold)).foregroundStyle(P.text)
            // 横向三栏：外观 | 模块显示 | 目标与周期
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    appearanceCard
                    fxCard
                    Text("数据来源：~/.claude/projects 会话记录\n口径：输入 + 输出 + 缓存写入 + 缓存读取（混合口径）")
                        .font(.system(size: 9)).foregroundStyle(P.faint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 250)
                modulesCard
                    .frame(width: 280)
                VStack(spacing: 12) {
                    goalsCard
                    githubCard
                }
                .frame(width: 240)
            }
        }
        .padding(16)
        .padding(.top, 22)
        .gesture(WindowDragGesture())   // 空白处拖动移动窗口
        // ── 悬浮二级浮层：显示所悬停模块的详细介绍
        .overlayPreferenceValue(HoverAnchorKey.self) { anchor in
            GeometryReader { geo in
                if let anchor, let mod = hoveredModule {
                    let r = geo[anchor]
                    let x = min(max(r.midX - 125, 8), geo.size.width - 258)
                    // 始终显示在鼠标所悬芯片的上方（底边贴齐芯片顶部）
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        ModuleTooltip(module: mod)
                    }
                    .frame(height: max(60, r.minY - 6), alignment: .bottom)
                    .offset(x: x)
                    .transition(.opacity)
                }
            }
            .allowsHitTesting(false)   // 浮层不拦截鼠标，避免悬停抖动
            .animation(.easeOut(duration: 0.12), value: hoveredModule)
        }
        .onAppear {
            dailyText = String(format: "%g", settings.dailyGoalM)
            weeklyText = String(format: "%g", settings.weeklyBudgetB)
        }
    }

    // ── 第一栏：外观
    private var appearanceCard: some View {
        Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("外观").font(.system(size: 11, weight: .semibold)).foregroundStyle(P.sub)
                    row("主题色") {
                        ColorPicker("", selection: colorBinding(\.accentRGB), supportsOpacity: false)
                            .labelsHidden()
                    }
                    // 预设色板
                    HStack(spacing: 7) {
                        ForEach(Array(Self.presets.enumerated()), id: \.offset) { _, c in
                            Button {
                                settings.accentRGB = c
                            } label: {
                                Circle()
                                    .fill(Color(red: c[0], green: c[1], blue: c[2]))
                                    .frame(width: 20, height: 20)
                                    .overlay(Circle().strokeBorder(
                                        settings.accentRGB == c ? Color.white.opacity(0.9) : Color.white.opacity(0.15),
                                        lineWidth: settings.accentRGB == c ? 2 : 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    row("玻璃染色") {
                        ColorPicker("", selection: colorBinding(\.tintRGB), supportsOpacity: false)
                            .labelsHidden()
                    }
                    row("染色强度 \(Int(settings.tintStrength / 0.6 * 100))%") {
                        Slider(value: $settings.tintStrength, in: 0...0.6)
                            .frame(width: 110)
                    }
                    Text("强度 0% = 纯玻璃（透出壁纸原色）；调高后玻璃带上你选的颜色")
                        .font(.system(size: 9)).foregroundStyle(P.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
    }

    // ── 第二栏：模块显示（点选芯片；两个面板独立配置）
    private var modulesCard: some View {
        Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("模块显示").font(.system(size: 11, weight: .semibold)).foregroundStyle(P.sub)
                    HStack {
                        Text("小面板").font(.system(size: 10)).foregroundStyle(P.faint)
                        Spacer()
                        resetBtn { settings.popoverModules = SettingsStore.defaultPopoverModules }
                    }
                    moduleChips(\.popoverModules)
                    Divider().overlay(Color.white.opacity(0.08))
                    HStack {
                        Text("主面板右栏").font(.system(size: 10)).foregroundStyle(P.faint)
                        Spacer()
                        resetBtn { settings.dashboardModules = SettingsStore.defaultDashboardModules }
                    }
                    moduleChips(\.dashboardModules)
                }
            }
    }

    // ── 第三栏：目标与周期
    private var goalsCard: some View {
        Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("目标与周期").font(.system(size: 11, weight: .semibold)).foregroundStyle(P.sub)
                    row("今日目标 (M)") {
                        TextField("300", text: $dailyText, onCommit: {
                            if let v = Double(dailyText), v > 0 { settings.dailyGoalM = v }
                        })
                        .textFieldStyle(.roundedBorder).frame(width: 90)
                    }
                    row("每周预算 (B)") {
                        TextField("3.0", text: $weeklyText, onCommit: {
                            if let v = Double(weeklyText), v > 0 { settings.weeklyBudgetB = v }
                        })
                        .textFieldStyle(.roundedBorder).frame(width: 90)
                    }
                    row("重置星期") {
                        Picker("", selection: $settings.resetWeekday) {
                            ForEach(1...7, id: \.self) { w in
                                Text(["日", "一", "二", "三", "四", "五", "六"][w - 1]).tag(w)
                            }
                        }
                        .labelsHidden().frame(width: 90)
                    }
                    row("重置时刻") {
                        Picker("", selection: $settings.resetHour) {
                            ForEach(0..<24, id: \.self) { h in
                                Text(String(format: "%02d:00", h)).tag(h)
                            }
                        }
                        .labelsHidden().frame(width: 90)
                    }
                    row("菜单栏显示数字") {
                        Toggle("", isOn: $settings.showMenuNumber)
                            .toggleStyle(.switch).labelsHidden()
                    }
                }
            }
    }

    private func row<C: View>(_ label: String, @ViewBuilder c: () -> C) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(P.sub)
            Spacer()
            c()
        }
    }

    // ── GitHub 连接
    private var githubCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("GitHub").font(.system(size: 11, weight: .semibold)).foregroundStyle(P.sub)
                switch gh.state {
                case .loaded(let user, _):
                    HStack(spacing: 6) {
                        if let a = gh.avatar {
                            Image(nsImage: a).resizable().scaledToFill()
                                .frame(width: 18, height: 18).clipShape(Circle())
                        }
                        Text("已连接：\(user.login)")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(P.accent2)
                        Spacer()
                        if gh.hasStoredToken {
                            Button("断开") { gh.disconnect() }
                                .buttonStyle(.plain)
                                .font(.system(size: 9)).foregroundStyle(P.hot)
                        }
                    }
                case .loading:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("连接中…").font(.system(size: 10)).foregroundStyle(P.sub)
                    }
                case .failed(let e):
                    Text("连接失败：\(e)").font(.system(size: 9.5)).foregroundStyle(P.hot)
                        .fixedSize(horizontal: false, vertical: true)
                case .notConfigured:
                    Text("未连接").font(.system(size: 10)).foregroundStyle(P.faint)
                }

                deviceFlowSection

                Divider().overlay(Color.white.opacity(0.08))
                Text("高级：手动 Token").font(.system(size: 9)).foregroundStyle(P.faint)
                SecureField("粘贴 Personal Access Token", text: $ghTokenInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10))
                HStack {
                    Button("连接") {
                        gh.setToken(ghTokenInput)
                        ghTokenInput = ""
                    }
                    .disabled(ghTokenInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    .controlSize(.small)
                    Button("刷新") { gh.refresh() }
                        .controlSize(.small)
                    Spacer()
                }
                Text("凭证存入系统钥匙串，不落明文；授权记录显示为 GitHub CLI，可在 GitHub → Settings → Applications 随时撤销。")
                    .font(.system(size: 9)).foregroundStyle(P.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 一键连接（设备授权流）
    @ViewBuilder
    private var deviceFlowSection: some View {
        switch gh.deviceFlow {
        case .idle:
            if !gh.isConnected {
                Button {
                    gh.startDeviceFlow()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.horizontal.fill").font(.system(size: 10))
                        Text("一键连接 GitHub").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(P.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(Capsule().fill(P.accent.opacity(0.35)))
                    .overlay(Capsule().strokeBorder(P.accent.opacity(0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
                Text("自动打开浏览器授权，无需手动创建 Token")
                    .font(.system(size: 9)).foregroundStyle(P.faint)
            }
        case .requesting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("正在获取授权码…").font(.system(size: 10)).foregroundStyle(P.sub)
            }
        case .waiting(let code):
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(code)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(P.hot)
                        .textSelection(.enabled)
                    Spacer()
                    Button("取消") { gh.cancelDeviceFlow() }
                        .buttonStyle(.plain)
                        .font(.system(size: 9)).foregroundStyle(P.sub)
                }
                Text("授权码已复制到剪贴板——在打开的 GitHub 页面粘贴并点击授权，完成后这里会自动连上")
                    .font(.system(size: 9)).foregroundStyle(P.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .failed(let e):
            VStack(alignment: .leading, spacing: 4) {
                Text(e).font(.system(size: 9.5)).foregroundStyle(P.hot)
                Button("重试") { gh.startDeviceFlow() }.controlSize(.small)
            }
        }
    }

    // ── 模块光效开关
    private var fxCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("模块光效").font(.system(size: 11, weight: .semibold)).foregroundStyle(P.sub)
                    Spacer()
                    resetBtn { settings.effectsOff = [] }
                }
                fxChips()
                Text("逐模块开关动态光效（闪烁 / 彗星 / 光点 / 光带 / 声呐）。「今日累计节奏」「5h窗柱状」对应主面板左侧图表；趋势页热力图跟随「90天热力图」")
                    .font(.system(size: 9)).foregroundStyle(P.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func fxChips() -> some View {
        // 模块 + 主面板左栏固定图表，全部独立开关
        let items: [(id: String, name: String)] =
            Module.allCases.map { ($0.rawValue, $0.name) } + extraFXItems
        let allIds = items.map(\.id)
        let off = Set(settings.effectsOff)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 5)],
                         alignment: .leading, spacing: 5) {
            ForEach(items, id: \.id) { item in
                let on = !off.contains(item.id)
                Button {
                    var s = off
                    if on { s.insert(item.id) } else { s.remove(item.id) }
                    settings.effectsOff = allIds.filter { s.contains($0) }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: on ? "bolt.fill" : "bolt.slash")
                            .font(.system(size: 8))
                        Text(item.name)
                            .font(.system(size: 9.5, weight: on ? .semibold : .regular))
                            .lineLimit(1)
                    }
                    .foregroundStyle(on ? P.text : P.sub)
                    .padding(.horizontal, 7).padding(.vertical, 4.5)
                    .frame(maxWidth: .infinity)
                    .background(Capsule().fill(on ? P.accent.opacity(0.32) : Color.white.opacity(0.05)))
                    .overlay(Capsule().strokeBorder(
                        on ? P.accent.opacity(0.55) : Color.white.opacity(0.10), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 一键恢复默认布局的小按钮
    private func resetBtn(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 8))
                Text("恢复默认")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(P.accent2)
            .padding(.horizontal, 7).padding(.vertical, 3.5)
            .background(Capsule().fill(P.accent.opacity(0.12)))
            .overlay(Capsule().strokeBorder(P.accent.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// 模块点选芯片网格（保持 Module.allCases 的规范顺序）
    private func moduleChips(_ keyPath: ReferenceWritableKeyPath<SettingsStore, [String]>) -> some View {
        let enabled = Set(settings[keyPath: keyPath])
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 5)],
                         alignment: .leading, spacing: 5) {
            ForEach(Module.allCases) { mod in
                let on = enabled.contains(mod.rawValue)
                Button {
                    var set = enabled
                    if on { set.remove(mod.rawValue) } else { set.insert(mod.rawValue) }
                    settings[keyPath: keyPath] = Module.allCases.map(\.rawValue).filter { set.contains($0) }
                } label: {
                    Text(mod.name)
                        .font(.system(size: 9.5, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? P.text : P.sub)
                        .lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 4.5)
                        .frame(maxWidth: .infinity)
                        .background(Capsule().fill(on ? P.accent.opacity(0.32) : Color.white.opacity(0.05)))
                        .overlay(Capsule().strokeBorder(
                            on ? P.accent.opacity(0.55) : Color.white.opacity(0.10), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .onHover { h in
                    if h { hoveredModule = mod }
                    else if hoveredModule == mod { hoveredModule = nil }
                }
                .anchorPreference(key: HoverAnchorKey.self, value: .bounds) {
                    hoveredModule == mod ? $0 : nil
                }
            }
        }
    }
}
