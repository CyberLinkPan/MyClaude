import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static var shared: AppDelegate!

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var timer: Timer?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)   // 不占 Dock

        // 菜单栏
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            // 菜单栏图标：Clawd 像素形象（彩色）；缺失时退回 SF Symbol
            if let url = Bundle.main.url(forResource: "MenuIcon", withExtension: "png"),
               let clawd = NSImage(contentsOf: url) {
                clawd.size = NSSize(width: 18, height: 18)
                clawd.isTemplate = false
                b.image = clawd
            } else {
                b.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "MyClaude")
                b.image?.isTemplate = true
            }
            b.imagePosition = .imageLeading
            b.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            b.target = self
            b.action = #selector(togglePopover)
        }

        // 弹出面板（毛玻璃：vibrantDark 外观下 NSPopover 自带磨砂背景）
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: PopoverView())
        popover.appearance = NSAppearance(named: .vibrantDark)
        popover.delegate = self   // 跟踪关闭事件，停掉动画时钟

        // 菜单栏标题 = 今日用量（默认关闭，占宽在满菜单栏上易被刘海挤掉）
        UsageStore.shared.$metrics
            .receive(on: DispatchQueue.main)
            .sink { [weak self] m in
                self?.statusItem.button?.title =
                    SettingsStore.shared.showMenuNumber ? " " + Fmt.tokens(m.today) : ""
            }
            .store(in: &bag)

        // 诊断：记录状态栏项的实际位置（判断是否被刘海遮挡）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            let f = self.statusItem.button?.window?.frame ?? .zero
            let sw = NSScreen.main?.frame.width ?? 0
            let msg = "statusItem x=\(Int(f.origin.x)) w=\(Int(f.width)) screenW=\(Int(sw)) visible=\(self.statusItem.isVisible)\n"
            try? msg.write(toFile: "/tmp/myclaude-diag.txt", atomically: true, encoding: .utf8)
        }

        UsageStore.shared.refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            UsageStore.shared.refresh()
        }

        if CommandLine.arguments.contains("--open") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.openMain() }
        }
    }

    /// 双击 App 图标（或 open 已运行的 App）时打开主窗口——菜单栏图标被挤掉时的备用入口
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        openMain()
        return true
    }

    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let b = statusItem.button {
            UsageStore.shared.refresh()
            UIActivity.shared.popoverOpen = true
            popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        UIActivity.shared.popoverOpen = false
    }

    func openMain() {
        if mainWindow == nil {
            let w = makeGlassWindow(size: NSSize(width: 1080, height: 780),
                                    root: AnyView(DashboardView()))
            mainWindow = w
            // 跟踪窗口可见性（关闭/最小化/被完全遮挡/切换空间都会触发）：
            // 不可见时停掉仪表盘的所有动画时钟
            NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: w, queue: .main) { [weak w] _ in
                    guard let w else { return }
                    UIActivity.shared.mainVisible =
                        w.isVisible && w.occlusionState.contains(.visible)
                }
        }
        UIActivity.shared.mainVisible = true
        show(mainWindow)
    }

    func openSettings() {
        if settingsWindow == nil {
            settingsWindow = makeGlassWindow(size: NSSize(width: 840, height: 680),
                                             root: AnyView(SettingsView()), resizable: false)
        }
        show(settingsWindow)
    }

    func quit() { NSApp.terminate(nil) }

    private func show(_ w: NSWindow?) {
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        w?.makeKeyAndOrderFront(nil)
    }

    /// 透明毛玻璃窗口：全尺寸内容 + 桌面级模糊
    private func makeGlassWindow(size: NSSize, root: AnyView, resizable: Bool = true) -> NSWindow {
        var mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if resizable { mask.insert(.resizable) }
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: mask, backing: .buffered, defer: false)
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        // 关闭"按背景拖动窗口"：会抢走滑块等控件的拖拽手势。
        // 改由根视图上的 WindowDragGesture 负责（子视图手势优先，不冲突）。
        w.isMovableByWindowBackground = false
        w.isOpaque = false
        w.backgroundColor = .clear
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: .vibrantDark)

        let fx = NSVisualEffectView()
        fx.material = .popover          // 比 hudWindow 更透，壁纸颜色能透上来（液态玻璃感）
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 12

        let host = NSHostingView(rootView: root)
        host.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            host.topAnchor.constraint(equalTo: fx.topAnchor),
            host.bottomAnchor.constraint(equalTo: fx.bottomAnchor),
        ])
        w.contentView = fx
        w.center()
        return w
    }
}

// --snapshot 模式：离屏渲染两个界面为 PNG（自检用，不需要屏幕权限）
@MainActor
func snapshotSave(_ view: AnyView, size: CGSize, name: String, dir: URL) {
    // size.height <= 0 表示按内容自适应高度
    let sized: AnyView = size.height > 0
        ? AnyView(view.frame(width: size.width, height: size.height))
        : AnyView(view.frame(width: size.width).fixedSize(horizontal: false, vertical: true))
    let wrapped = sized
        .background(Color(red: 0.09, green: 0.02, blue: 0.05))   // 玻璃占位底色
    let renderer = ImageRenderer(content: wrapped)
    renderer.scale = 2
    guard let img = renderer.nsImage,
          let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("渲染失败: \(name)"); return
    }
    try? png.write(to: dir.appendingPathComponent(name))
    print("已保存: \(name)")
}

@MainActor
func runSnapshot(dir: URL) {
    gSnapshotMode = true
    UsageStore.shared.refreshSync()
    snapshotSave(AnyView(PopoverView()), size: CGSize(width: 312, height: 0), name: "popover.png", dir: dir)
    snapshotSave(AnyView(DashboardView()), size: CGSize(width: 1080, height: 780), name: "dashboard.png", dir: dir)
    snapshotSave(AnyView(SettingsView()), size: CGSize(width: 840, height: 0), name: "settings.png", dir: dir)
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    MainActor.assumeIsolated { runSnapshot(dir: dir) }
    exit(0)
}

// --icon 模式：渲染 App 图标（1024）和菜单栏 Clawd 图标（36）
@MainActor
func iconSave(_ view: AnyView, size: CGFloat, name: String, dir: URL) {
    let renderer = ImageRenderer(content: view.frame(width: size, height: size))
    renderer.scale = 1
    if let img = renderer.nsImage,
       let tiff = img.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: dir.appendingPathComponent(name))
        print("已保存: \(name)")
    }
}

if let i = CommandLine.arguments.firstIndex(of: "--icon"), i + 1 < CommandLine.arguments.count {
    let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    MainActor.assumeIsolated {
        iconSave(AnyView(IconView()), size: 1024, name: "icon_1024.png", dir: dir)
        iconSave(AnyView(ClawdSprite().padding(4)), size: 112, name: "menubar.png", dir: dir)
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
