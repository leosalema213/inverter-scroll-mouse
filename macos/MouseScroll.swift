import AppKit
import ApplicationServices
import CoreGraphics
import IOKit.hid
import ServiceManagement
import CryptoKit

let appVersion = "1.1.0-preview.4"
let repository = "leosalema213/inverter-scroll-mouse"
let maximumDownload = 10_000_000

// Only discrete wheel events are modified. Continuous trackpad/smooth-scroll events pass through.
func reverseWheel(_ event: CGEvent) {
    guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else { return }
    for field in [CGEventField.scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1] {
        let value = event.getIntegerValueField(field)
        if value != Int64.min { event.setIntegerValueField(field, value: -value) }
    }
}

final class WheelController {
    var tap: CFMachPort?
    var source: CFRunLoopSource?
    var inverted = true
    func start() -> Bool {
        if tap != nil { return true }
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1) << CGEventType.scrollWheel.rawValue, callback: { _, type, event, info in
                let owner = Unmanaged<WheelController>.fromOpaque(info!).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                } else if type == .scrollWheel && owner.inverted { reverseWheel(event) }
                return Unmanaged.passUnretained(event)
            }, userInfo: pointer)
        guard let tap else { return false }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
    }
    deinit { stop() }
}

struct MouseDevice { let name: String; let transport: String }
func mice() -> [MouseDevice] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let filter: [String: Any] = [kIOHIDDeviceUsagePageKey: 1, kIOHIDDeviceUsageKey: 2]
    IOHIDManagerSetDeviceMatching(manager, filter as CFDictionary)
    guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
    var seen = Set<String>()
    return devices.compactMap { device in
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Mouse"
        let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? "HID"
        guard !name.lowercased().contains("trackpad"), seen.insert(name + transport).inserted else { return nil }
        return MouseDevice(name: name, transport: transport)
    }.sorted { $0.name < $1.name }
}

func isNewer(_ remote: String, than installed: String) -> Bool {
    let clean = remote.hasPrefix("v") ? String(remote.dropFirst()) : remote
    guard clean.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil else { return false }
    let base = String(installed.split(separator: "-")[0])
    let comparison = clean.compare(base, options: .numeric)
    return comparison == .orderedDescending || (comparison == .orderedSame && installed.contains("-preview."))
}

struct Release: Decodable {
    struct Asset: Decodable { let name: String; let size: Int; let browser_download_url: String; let digest: String? }
    let tag_name: String; let draft: Bool; let prerelease: Bool; let assets: [Asset]
}
enum UpdateFailure: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let wheel = WheelController()
    let defaults = UserDefaults.standard
    var window: NSWindow!
    let table = NSTableView()
    let direction = NSPopUpButton()
    let status = NSTextField(labelWithString: "")
    let theme = NSButton()
    var devices: [MouseDevice] = []
    var menuItem: NSStatusItem!
    var checking = false
    var updateTask: Task<Void, Never>?
    var dark: Bool { defaults.string(forKey: "theme") == "dark" }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if defaults.object(forKey: "inverted") == nil { defaults.set(true, forKey: "inverted") }
        if defaults.string(forKey: "theme") == nil {
            defaults.set(NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light", forKey: "theme")
        }
        wheel.inverted = defaults.bool(forKey: "inverted")
        buildWindow()
        menuItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menuItem.button?.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "Mouse Scroll")
        let menu = NSMenu()
        menu.addItem(withTitle: "Abrir Mouse Scroll", action: #selector(showWindow), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Sair", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }; menuItem.menu = menu
        if defaults.bool(forKey: "active") && AXIsProcessTrusted() { _ = wheel.start() }
        refresh()
        showWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.checkUpdates(manual: false) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { wheel.stop(); updateTask?.cancel() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    @objc func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func quit() { NSApp.terminate(nil) }

    func label(_ text: String, _ frame: NSRect, size: CGFloat = 13, bold: Bool = false, in parent: NSView? = nil) {
        let field = NSTextField(labelWithString: text); field.frame = frame
        field.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        (parent ?? window.contentView!).addSubview(field)
    }
    @discardableResult func button(_ title: String, _ frame: NSRect, _ action: Selector, in parent: NSView? = nil) -> NSButton {
        let value = NSButton(title: title, target: self, action: action); value.frame = frame; value.bezelStyle = .rounded
        (parent ?? window.contentView!).addSubview(value); return value
    }
    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 820,height: 540), styleMask: [.titled,.closable,.miniaturizable], backing: .buffered, defer: false)
        window.title = "Mouse Scroll"; window.delegate = self; window.isReleasedWhenClosed = false; window.center()
        let content = window.contentView!
        let icon = NSImageView(frame: NSRect(x:24,y:454,width:64,height:64)); icon.image = NSImage(named: "AppIcon"); content.addSubview(icon)
        label("Mouse Scroll", NSRect(x:104,y:480,width:540,height:40), size:30,bold:true)
        label("Ajuste a direção da roda em conexões com e sem fio.", NSRect(x:107,y:448,width:620,height:24))
        theme.frame = NSRect(x:700,y:484,width:32,height:32); theme.target = self; theme.action = #selector(toggleTheme); theme.isBordered = false; theme.toolTip = "Trocar tema"; content.addSubview(theme)
        let gear = button("", NSRect(x:750,y:484,width:32,height:32), #selector(settings)); gear.isBordered = false; gear.toolTip = "Configurações"
        gear.image = NSImage(contentsOf: Bundle.main.url(forResource:"settings-dark",withExtension:"png")!)
        gear.image?.isTemplate = true
        label("Mouses encontrados", NSRect(x:24,y:382,width:480,height:30),size:16,bold:true)
        button("Atualizar lista",NSRect(x:666,y:380,width:130,height:34),#selector(refresh))
        for (name,width) in [("Dispositivo no macOS",CGFloat(505)),("Conexão",100),("Direção",163)] {
            let column = NSTableColumn(identifier:NSUserInterfaceItemIdentifier(name)); column.title = name; column.width = width; table.addTableColumn(column)
        }
        table.delegate = self; table.dataSource = self; table.rowHeight = 26; table.usesAlternatingRowBackgroundColors = true
        let scroll = NSScrollView(frame:NSRect(x:24,y:181,width:772,height:194)); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder; content.addSubview(scroll)
        status.frame = NSRect(x:24,y:148,width:772,height:25); status.font = .systemFont(ofSize:12); status.textColor = .secondaryLabelColor; content.addSubview(status)
        label("Direção da rolagem",NSRect(x:38,y:104,width:310,height:26))
        label("Início com o macOS",NSRect(x:412,y:104,width:360,height:26))
        direction.frame = NSRect(x:38,y:65,width:126,height:34); direction.addItems(withTitles:["Invertida","Padrão"]); direction.selectItem(at:wheel.inverted ? 0 : 1); content.addSubview(direction)
        button("Aplicar a todos",NSRect(x:174,y:65,width:160,height:34),#selector(apply))
        button("Ativar",NSRect(x:412,y:65,width:102,height:34),#selector(enableStartup))
        button("Desativar",NSRect(x:524,y:65,width:102,height:34),#selector(disableStartup))
        label("Mantém o aplicativo ativo na barra de menus.",NSRect(x:412,y:25,width:370,height:24),size:12)
        applyTheme()
    }
    func applyTheme() {
        window.appearance = NSAppearance(named:dark ? .darkAqua : .aqua)
        window.backgroundColor = dark ? NSColor(white:0.063,alpha:1) : NSColor(white:0.965,alpha:1)
        theme.image = NSImage(contentsOf:Bundle.main.url(forResource:dark ? "sun-dark" : "moon-light",withExtension:"png")!); theme.image?.isTemplate = true
    }
    @objc func toggleTheme() { defaults.set(dark ? "light" : "dark",forKey:"theme"); applyTheme() }
    @objc func refresh() {
        devices = mice(); table.reloadData()
        let startup = SMAppService.mainApp.status == .enabled ? "Ativa" : SMAppService.mainApp.status == .requiresApproval ? "Aguardando aprovação" : "Desativada"
        status.stringValue = "Mouses encontrados: \(devices.count)   |   Início com macOS: \(startup)   |   \(wheel.tap == nil ? "Ajuste inativo" : "Ajuste ativo")"
    }
    func numberOfRows(in tableView:NSTableView) -> Int { devices.count }
    func tableView(_ tableView:NSTableView,viewFor column:NSTableColumn?,row:Int) -> NSView? {
        let mouse = devices[row]; let id = column?.identifier.rawValue ?? ""
        let text = id == "Conexão" ? mouse.transport : id == "Direção" ? (wheel.tap == nil ? "Sistema" : wheel.inverted ? "Invertida" : "Padrão") : mouse.name
        let field = NSTextField(labelWithString:text); field.lineBreakMode = .byTruncatingTail; return field
    }
    func alert(_ message:String,_ detail:String = "") {
        let value = NSAlert(); value.messageText = message; value.informativeText = detail; value.addButton(withTitle:"OK"); value.runModal()
    }
    @objc func apply() {
        let inverted = direction.indexOfSelectedItem == 0
        if !inverted { wheel.inverted = false; wheel.stop(); defaults.set(false,forKey:"inverted"); defaults.set(false,forKey:"active"); refresh(); return }
        guard AXIsProcessTrusted() else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            alert("Permita o acesso em Acessibilidade", "Em Ajustes do Sistema → Privacidade e Segurança → Acessibilidade, autorize o Mouse Scroll. Depois clique em Aplicar a todos novamente.")
            return
        }
        wheel.inverted = inverted
        guard wheel.start() else { alert("Não foi possível ativar a rolagem", "Confira a permissão de Acessibilidade. Se o macOS solicitar Monitoramento de Entrada, autorize o aplicativo e tente novamente."); return }
        defaults.set(inverted,forKey:"inverted"); defaults.set(true,forKey:"active"); refresh()
    }
    @objc func enableStartup() {
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else { alert("Mova o aplicativo para Aplicativos", "Abra o Mouse Scroll pela pasta Aplicativos antes de ativar o início automático."); return }
        apply()
        guard wheel.tap != nil || direction.indexOfSelectedItem == 1 else { return }
        do { try SMAppService.mainApp.register(); refresh() }
        catch { alert("Não foi possível ativar o início automático",error.localizedDescription) }
        if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }
    @objc func disableStartup() { do { try SMAppService.mainApp.unregister(); refresh() } catch { alert("Não foi possível desativar",error.localizedDescription) } }
    @objc func settings() {
        let value = NSAlert(); value.messageText = "Mouse Scroll \(appVersion)"; value.informativeText = "Atualizações\nVerificação automática ao abrir o aplicativo."
        value.addButton(withTitle:"Verificar atualização"); value.addButton(withTitle:"Concluir")
        if value.runModal() == .alertFirstButtonReturn { checkUpdates(manual:true) }
    }
    func checkUpdates(manual:Bool) {
        guard !checking else { return }; checking = true
        updateTask = Task { @MainActor in
            defer { checking = false }
            do {
                var request = URLRequest(url:URL(string:"https://api.github.com/repos/\(repository)/releases/latest")!); request.timeoutInterval = 20
                request.setValue("MouseScroll/\(appVersion)",forHTTPHeaderField:"User-Agent")
                let (data,response) = try await URLSession.shared.data(for:request)
                guard let http = response as? HTTPURLResponse else { throw UpdateFailure.invalid("Resposta inválida.") }
                if http.statusCode == 404 { if manual { alert("Nenhuma atualização publicada ainda.") }; return }
                guard http.statusCode == 200, data.count <= 1_000_000 else { throw UpdateFailure.invalid("Não foi possível consultar as versões.") }
                let release = try JSONDecoder().decode(Release.self,from:data)
                guard !release.draft,!release.prerelease,isNewer(release.tag_name,than:appVersion) else { if manual { alert("Você está na versão mais recente.") }; return }
                guard let asset = release.assets.first(where:{$0.name == "MouseScroll-macOS.dmg"}), asset.size > 0,asset.size <= maximumDownload,
                    asset.browser_download_url == "https://github.com/\(repository)/releases/download/\(release.tag_name)/MouseScroll-macOS.dmg" else { throw UpdateFailure.invalid("O instalador de Mac ainda não está disponível.") }
                let prompt = NSAlert(); prompt.messageText = "Nova versão disponível"; prompt.informativeText = "Mouse Scroll \(appVersion) → \(release.tag_name). Deseja baixar o instalador?"; prompt.addButton(withTitle:"Baixar atualização");prompt.addButton(withTitle:"Depois")
                guard prompt.runModal() == .alertFirstButtonReturn else { return }
                try await download(asset,release:release)
            } catch { if manual { alert("Não foi possível atualizar",error.localizedDescription) } }
        }
    }
    @MainActor func download(_ asset:Release.Asset,release:Release) async throws {
        var expected = asset.digest?.hasPrefix("sha256:") == true ? String(asset.digest!.dropFirst(7)) : ""
        if expected.isEmpty, let checksum = release.assets.first(where:{$0.name == asset.name + ".sha256"}) {
            guard checksum.browser_download_url == asset.browser_download_url + ".sha256" else { throw UpdateFailure.invalid("Endereço de verificação inválido.") }
            let (data,response) = try await URLSession.shared.data(from:URL(string:checksum.browser_download_url)!)
            guard (response as? HTTPURLResponse)?.statusCode == 200,data.count < 4096 else { throw UpdateFailure.invalid("Verificação indisponível.") }
            expected = String(data:data,encoding:.utf8)?.components(separatedBy:.whitespacesAndNewlines).first ?? ""
        }
        guard expected.range(of:#"^[a-fA-F0-9]{64}$"#,options:.regularExpression) != nil else { throw UpdateFailure.invalid("Verificação SHA-256 ausente.") }
        let (bytes,response) = try await URLSession.shared.bytes(from:URL(string:asset.browser_download_url)!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateFailure.invalid("O download falhou.") }
        var data = Data(); data.reserveCapacity(asset.size)
        for try await byte in bytes {
            guard data.count < asset.size,data.count < maximumDownload else { throw UpdateFailure.invalid("O download excedeu o tamanho informado.") }; data.append(byte)
        }
        let actual = SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
        guard data.count == asset.size,actual == expected.lowercased() else { throw UpdateFailure.invalid("A verificação falhou. Nada foi instalado.") }
        let folder = FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("MouseScroll/\(release.tag_name)")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let file = folder.appendingPathComponent(asset.name); try data.write(to:file,options:.atomic)
        let prompt = NSAlert();prompt.messageText = "Atualização pronta";prompt.informativeText = "O aplicativo será encerrado. No instalador, arraste Mouse Scroll para Aplicativos e substitua a versão anterior. Suas preferências serão mantidas.";prompt.addButton(withTitle:"Abrir instalador");prompt.addButton(withTitle:"Depois")
        if prompt.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(file); NSApp.terminate(nil) }
    }
}

if CommandLine.arguments.contains("--self-test") {
    precondition(isNewer("v1.1.0",than:"1.1.0-preview.4")); precondition(!isNewer("v1.0.9",than:appVersion)); precondition(!isNewer("bad",than:appVersion))
    let event = CGEvent(scrollWheelEvent2Source:nil,units:.line,wheelCount:1,wheel1:3,wheel2:0,wheel3:0)!
    event.setIntegerValueField(.scrollWheelEventIsContinuous,value:0); reverseWheel(event); precondition(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == -3)
    event.setIntegerValueField(.scrollWheelEventIsContinuous,value:1); reverseWheel(event); precondition(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == -3)
    print("macOS self-tests passed: versions, discrete wheel reversal, continuous events preserved.")
} else {
    let application = NSApplication.shared
    let delegate = AppDelegate(); application.delegate = delegate; application.setActivationPolicy(.regular)
    application.run()
}
