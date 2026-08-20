import Cocoa
import Carbon
import Quartz
import QuickLookThumbnailing

// ---------- Modèle d'un résultat ----------
final class Item {
    let title: String
    let pre: String       // partie blanche avant le résultat (calc/conversion)
    let subtitle: String
    let url: String?      // cible d'ouverture (mail message:// ou chemin fichier)
    let isFile: Bool
    let answer: String?   // pour calcul / conversion (copié à Entrée)
    let symbol: String    // SF Symbol
    let big: Bool         // affichage résultat en gros
    let cat: String       // catégorie (Mail, Documents, Images…)
    let date: String      // date ISO pour le tri
    let mid: String?      // identifiant du mail (pour l'aperçu latéral)
    init(title: String, subtitle: String, url: String? = nil, answer: String? = nil,
         symbol: String = "envelope.fill", big: Bool = false, pre: String = "", isFile: Bool = false, cat: String = "", date: String = "", mid: String? = nil) {
        self.title = title; self.subtitle = subtitle; self.url = url
        self.answer = answer; self.symbol = symbol; self.big = big; self.pre = pre; self.isFile = isFile; self.cat = cat; self.date = date; self.mid = mid
    }
}

struct Hit: Codable {
    let title: String; let sub: String; let symbol: String; let open: String; let isFile: Bool; let cat: String; let date: String; let mid: String?
}

func roundedMask(_ radius: CGFloat) -> NSImage {
    let d = radius * 2 + 1
    let img = NSImage(size: NSSize(width: d, height: d))
    img.lockFocus()
    NSColor.black.setFill()
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: d, height: d), xRadius: radius, yRadius: radius).fill()
    img.unlockFocus()
    img.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
    img.resizingMode = .stretch
    return img
}

func makePdfIcon(_ s: CGFloat = 32) -> NSImage {
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let body = NSBezierPath(roundedRect: NSRect(x: s*0.18, y: s*0.06, width: s*0.64, height: s*0.88), xRadius: s*0.08, yRadius: s*0.08)
    NSColor.white.setFill(); body.fill()
    NSColor(white: 0.72, alpha: 1).setStroke(); body.lineWidth = 1; body.stroke()
    NSColor(white: 0.80, alpha: 1).setStroke()
    for i in 0..<3 {
        let y = s*0.80 - CGFloat(i)*s*0.06
        let l = NSBezierPath(); l.move(to: NSPoint(x: s*0.30, y: y)); l.line(to: NSPoint(x: s*0.70, y: y)); l.lineWidth = 1; l.stroke()
    }
    let badge = NSRect(x: s*0.12, y: s*0.24, width: s*0.60, height: s*0.26)
    NSColor(calibratedRed: 0.85, green: 0.13, blue: 0.13, alpha: 1).setFill()
    NSBezierPath(roundedRect: badge, xRadius: s*0.05, yRadius: s*0.05).fill()
    let txt = "PDF" as NSString
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: s*0.17), .foregroundColor: NSColor.white]
    let ts = txt.size(withAttributes: attrs)
    txt.draw(at: NSPoint(x: badge.midX - ts.width/2, y: badge.midY - ts.height/2 - s*0.01), withAttributes: attrs)
    img.unlockFocus()
    img.isTemplate = false
    return img
}
let gPdfIcon = makePdfIcon()

func badgeColor(_ ext: String) -> NSColor {
    switch ext.lowercased() {
    case "pdf": return NSColor(calibratedRed: 0.85, green: 0.13, blue: 0.13, alpha: 1)
    case "log": return NSColor(calibratedRed: 0.90, green: 0.49, blue: 0.13, alpha: 1)
    case "txt", "md", "markdown", "text", "rtf": return NSColor(calibratedRed: 0.42, green: 0.47, blue: 0.53, alpha: 1)
    case "doc", "docx", "odt", "pages": return NSColor(calibratedRed: 0.16, green: 0.42, blue: 0.85, alpha: 1)
    case "xls", "xlsx", "csv", "numbers": return NSColor(calibratedRed: 0.19, green: 0.60, blue: 0.28, alpha: 1)
    case "ppt", "pptx", "key": return NSColor(calibratedRed: 0.80, green: 0.35, blue: 0.10, alpha: 1)
    case "stl", "obj", "3mf", "step", "stp", "scad", "gcode", "f3d", "dwg", "dxf": return NSColor(calibratedRed: 0.52, green: 0.35, blue: 0.80, alpha: 1)
    case "png", "jpg", "jpeg", "gif", "svg", "webp", "heic", "tif", "tiff", "bmp", "eps": return NSColor(calibratedRed: 0.11, green: 0.62, blue: 0.60, alpha: 1)
    case "zip", "rar", "7z", "tar", "gz", "dmg": return NSColor(calibratedRed: 0.55, green: 0.44, blue: 0.24, alpha: 1)
    case "mp4", "mov", "avi", "mkv", "mp3", "wav", "m4a": return NSColor(calibratedRed: 0.77, green: 0.20, blue: 0.44, alpha: 1)
    default: return NSColor(calibratedWhite: 0.36, alpha: 1)
    }
}

func badgedIcon(_ base: NSImage, _ ext: String, _ s: CGFloat = 28) -> NSImage {
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    base.draw(in: NSRect(x: 0, y: 0, width: s, height: s))
    let e = ext.uppercased()
    if !e.isEmpty {
        let label = String(e.prefix(4)) as NSString
        let font = NSFont.systemFont(ofSize: s * 0.24, weight: .heavy)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let ts = label.size(withAttributes: attrs)
        let padX = s * 0.07, padY = s * 0.04
        let rect = NSRect(x: 0, y: 0, width: ts.width + padX * 2, height: ts.height + padY * 2)
        badgeColor(ext).setFill()
        NSBezierPath(roundedRect: rect, xRadius: s * 0.07, yRadius: s * 0.07).fill()
        label.draw(at: NSPoint(x: padX, y: padY), withAttributes: attrs)
    }
    img.unlockFocus()
    return img
}

func alog(_ s: String) {
    let p = (NSHomeDirectory() as NSString).appendingPathComponent("Scripts/spotlight-sens/app.log")
    let line = "\(Date()) \(s)\n"
    guard let d = line.data(using: .utf8) else { return }
    if let fh = FileHandle(forWritingAtPath: p) { fh.seekToEndOfFile(); fh.write(d); try? fh.close() }
    else { try? line.write(toFile: p, atomically: true, encoding: .utf8) }
}

// ---------- Panneau qui peut recevoir le clavier ----------
final class KeyPanel: NSPanel {
    weak var controller: Controller?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = controller; panel.delegate = controller }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = nil; panel.delegate = nil }
}

// ---------- Helpers taux / calcul / conversion ----------
func loadRate() -> (usd_eur: Double, eur_usd: Double, date: String)? {
    let p = (NSHomeDirectory() as NSString).appendingPathComponent("Scripts/spotlight-sens/rate.json")
    guard let d = try? Data(contentsOf: URL(fileURLWithPath: p)),
          let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
          let a = j["usd_eur"] as? Double, let b = j["eur_usd"] as? Double else { return nil }
    return (a, b, (j["date"] as? String) ?? "")
}

func tryCalc(_ q: String) -> Item? {
    let e = q.replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: ",", with: ".")
    if e.isEmpty { return nil }
    let allowed = CharacterSet(charactersIn: "0123456789.+-*/()")
    if e.rangeOfCharacter(from: allowed.inverted) != nil { return nil }
    if e.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/")) == nil { return nil }
    let expr = NSExpression(format: e)
    guard let v = expr.expressionValue(with: nil, context: nil) as? NSNumber else { return nil }
    let d = v.doubleValue
    let s = (d == d.rounded()) ? String(Int(d)) : String(format: "%g", d)
    return Item(title: s, subtitle: q.replacingOccurrences(of: " ", with: "") + "   ·   Entrée = copier",
                answer: s, symbol: "equal.circle.fill", big: true, pre: "= ")
}

func tryCurrency(_ q: String) -> Item? {
    let s = q.replacingOccurrences(of: " ", with: "")
    func num(_ pat: String) -> String? {
        guard let r = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]) else { return nil }
        let rng = NSRange(s.startIndex..., in: s)
        guard let m = r.firstMatch(in: s, range: rng), let g = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[g])
    }
    var kind: String? = nil; var n: String? = nil
    if let x = num("^([0-9.,]+)\\$$") { n = x; kind = "usd" }
    else if let x = num("^\\$([0-9.,]+)$") { n = x; kind = "usd" }
    else if let x = num("^([0-9.,]+)€$") { n = x; kind = "eur" }
    else if let x = num("^€([0-9.,]+)$") { n = x; kind = "eur" }
    else if let x = num("^([0-9.,]+)usd$") { n = x; kind = "usd" }
    else if let x = num("^([0-9.,]+)eur$") { n = x; kind = "eur" }
    guard let ns = n, let k = kind, let val = Double(ns.replacingOccurrences(of: ",", with: ".")),
          let r = loadRate() else { return nil }
    if k == "usd" {
        let v = val * r.usd_eur
        return Item(title: String(format: "%.2f €", v),
                    subtitle: "conversion · taux du \(r.date) · Entrée = copier",
                    answer: String(format: "%.2f", v), symbol: "arrow.left.arrow.right.circle.fill", big: true,
                    pre: String(format: "%g $  =  ", val))
    } else {
        let v = val * r.eur_usd
        return Item(title: String(format: "%.2f $", v),
                    subtitle: "conversion · taux du \(r.date) · Entrée = copier",
                    answer: String(format: "%.2f", v), symbol: "arrow.left.arrow.right.circle.fill", big: true,
                    pre: String(format: "%g €  =  ", val))
    }
}

func whoName(_ frm: String) -> String {
    if let r = frm.range(of: "\"([^\"]+)\"", options: .regularExpression) {
        return String(frm[r]).replacingOccurrences(of: "\"", with: "")
    }
    if let i = frm.firstIndex(of: "<") { return frm[..<i].trimmingCharacters(in: .whitespaces) }
    return frm
}

// ---------- Thèmes ----------
func hexColor(_ s: String, _ alpha: CGFloat = 1) -> NSColor {
    var h = s.trimmingCharacters(in: .whitespaces); if h.hasPrefix("#") { h.removeFirst() }
    if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
    var v: UInt64 = 0; Scanner(string: h).scanHexInt64(&v)
    return NSColor(calibratedRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                   blue: CGFloat(v & 0xff) / 255, alpha: alpha)
}
func spotDir() -> String { (NSHomeDirectory() as NSString).appendingPathComponent("Scripts/spotlight-sens") }
func themesDir() -> String { (spotDir() as NSString).appendingPathComponent("themes") }
func configPath() -> String { (spotDir() as NSString).appendingPathComponent("config.json") }

struct Theme {
    var name = "Défaut", bg = "#1c1c1e", text = "#f2f2f7", subtext = "#9aa0a6"
    var accent = "#3b82f6", result = "#dcc766", border = "#3a3a3c"
    var dark = true; var opacity: CGFloat = 0; var corner: CGFloat = 18
}
func currentThemeSlug() -> String {
    if let d = try? Data(contentsOf: URL(fileURLWithPath: configPath())),
       let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let s = j["theme"] as? String { return s }
    return "defaut-verre-fonce"
}
func loadTheme(_ slug: String) -> Theme {
    var t = Theme()
    let p = (themesDir() as NSString).appendingPathComponent(slug + ".json")
    guard let d = try? Data(contentsOf: URL(fileURLWithPath: p)),
          let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return t }
    if let s = j["name"] as? String { t.name = s }
    if let s = j["bg"] as? String { t.bg = s }
    if let s = j["text"] as? String { t.text = s }
    if let s = j["subtext"] as? String { t.subtext = s }
    if let s = j["accent"] as? String { t.accent = s }
    if let s = j["result"] as? String { t.result = s }
    if let s = j["border"] as? String { t.border = s }
    if let b = j["dark"] as? Bool { t.dark = b }
    if let o = j["opacity"] as? Double { t.opacity = CGFloat(o) }
    if let c = j["corner"] as? Double { t.corner = CGFloat(c) }
    return t
}

func readConfig() -> [String: Any] {
    guard let d = try? Data(contentsOf: URL(fileURLWithPath: configPath())),
          let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return [:] }
    return j
}
func writeConfig(_ c: [String: Any]) {
    if let d = try? JSONSerialization.data(withJSONObject: c, options: [.prettyPrinted]) {
        try? d.write(to: URL(fileURLWithPath: configPath()))
    }
}
func defaultFolders() -> [String] {
    ["Documents", "Desktop", "Downloads"].map { (NSHomeDirectory() as NSString).appendingPathComponent($0) } + ["/Applications"]
}
func indexedFolders() -> [String] {
    if let f = readConfig()["folders"] as? [String], !f.isEmpty { return f }
    return defaultFolders()
}
func resultCount() -> Int { (readConfig()["results"] as? Int) ?? 60 }

final class ThemeRowView: NSTableRowView {
    var accent: NSColor = .controlAccentColor
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        accent.withAlphaComponent(0.30).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 8, yRadius: 8).fill()
    }
}


final class ResultTableView: NSTableView {
    weak var controller: Controller?
    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        let row = self.row(at: p)
        guard row >= 0 else { return nil }
        selectRowIndexes([row], byExtendingSelection: false)
        return controller?.contextMenu()
    }
}

final class PreviewImageView: NSImageView {
    weak var controller: Controller?
    override func menu(for event: NSEvent) -> NSMenu? { controller?.contextMenu() }
}

final class PreviewQLView: QLPreviewView {
    weak var controller: Controller?
    override func menu(for event: NSEvent) -> NSMenu? { controller?.contextMenu() }
    // NE PAS voler le focus clavier du panneau (sinon la fenêtre paraît figée).
    // La rotation 3D / le défilement à la SOURIS restent possibles.
    override var acceptsFirstResponder: Bool { false }
}

final class ResizeGrip: NSView {
    weak var win: NSWindow?
    private var startFrame = NSZeroRect
    private var startMouse = NSZeroPoint
    override func mouseDown(with e: NSEvent) { if let w = win { startFrame = w.frame; startMouse = NSEvent.mouseLocation } }
    override func mouseDragged(with e: NSEvent) {
        guard let w = win else { return }
        let m = NSEvent.mouseLocation
        var f = startFrame
        f.size.width = max(430, startFrame.width + (m.x - startMouse.x))
        f.size.height = max(240, startFrame.height - (m.y - startMouse.y))
        f.origin.y = startFrame.maxY - f.size.height
        w.setFrame(f, display: true)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 1, alpha: 0.30).setStroke()
        let p = NSBezierPath(); p.lineWidth = 1.3
        for o in stride(from: CGFloat(4), through: 12, by: 4) {
            p.move(to: NSPoint(x: bounds.maxX - o, y: 3)); p.line(to: NSPoint(x: bounds.maxX - 3, y: o))
        }
        p.stroke()
    }
}

// ---------- Contrôleur principal ----------
final class Controller: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSWindowDelegate, NSSplitViewDelegate {
    var cw: CGFloat { panel.contentView?.bounds.width ?? 660 }
    var chh: CGFloat { panel.contentView?.bounds.height ?? 430 }
    let panel: KeyPanel
    let search = NSTextField()
    let table = ResultTableView()
    let tint = NSView()
    var theme = loadTheme(currentThemeSlug())
    var items: [Item] = []
    var allItems: [Item] = []
    var currentCat = "Tout"
    var filterCats: [String] = []
    let filterBar = NSSegmentedControl()
    let scroll = NSScrollView()
    let CATS = ["Mail", "Documents", "Dossiers", "Applications", "Réglages", "Images", "Médias", "3D", "Archives", "Design"]
    var previewURLs: [URL] = []
    var sortByDate = false
    let sortBtn = NSButton()
    let split = NSSplitView()
    let previewPane = NSView()
    let previewQL = PreviewQLView(frame: .zero, style: .normal)!
    let previewMailScroll = NSScrollView()
    let previewMailText = NSTextView()
    let previewChk = NSButton()
    var previewEnabled = (readConfig()["preview"] as? Bool) ?? true
    var previewToken = 0
    var lastCat = "Tout"
    var pendingCat: String? = nil
    var lastSel = 0
    var pendingSel: Int? = nil
    var seq = 0
    var lastQ = ""; var lastAt = Date.distantPast
    let daemon = "http://127.0.0.1:8799/search?"

    override init() {
        let W: CGFloat = 660, H: CGFloat = 430
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: W, height: H),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        table.controller = self
        previewQL.controller = self
        panel.controller = self
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.delegate = self

        let ve = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        ve.material = .hudWindow
        ve.blendingMode = .behindWindow
        ve.state = .active
        ve.maskImage = roundedMask(18)
        panel.contentView = ve

        tint.wantsLayer = true
        tint.frame = ve.bounds
        tint.autoresizingMask = [.width, .height]
        ve.addSubview(tint)

        search.frame = NSRect(x: 20, y: H - 54, width: W - 40, height: 36)
        search.font = NSFont.systemFont(ofSize: 22, weight: .regular)
        search.isBordered = false
        search.drawsBackground = false
        search.focusRingType = .none
        search.placeholderString = "Cherche un mail, calcule, convertis (53$)…"
        search.delegate = self
        search.autoresizingMask = [.minYMargin, .width]
        ve.addSubview(search)

        let sep = NSBox(frame: NSRect(x: 0, y: H - 60, width: W, height: 1))
        sep.boxType = .separator
        sep.autoresizingMask = [.minYMargin, .width]
        ve.addSubview(sep)

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        table.headerView = nil
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.rowHeight = 50
        table.intercellSpacing = NSSize(width: 0, height: 2)
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        col.width = W
        table.addTableColumn(col)
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(activateSel)   // double-clic = ouvrir (simple clic = sélection seule)
        scroll.documentView = table

        split.frame = NSRect(x: 0, y: 0, width: W, height: H - 60)
        split.autoresizingMask = [.width, .height]
        split.isVertical = true
        split.dividerStyle = .thin
        split.delegate = self
        previewPane.wantsLayer = true
        previewQL.translatesAutoresizingMaskIntoConstraints = false
        previewQL.shouldCloseWithWindow = false
        previewPane.addSubview(previewQL)
        NSLayoutConstraint.activate([
            previewQL.leadingAnchor.constraint(equalTo: previewPane.leadingAnchor, constant: 6),
            previewQL.trailingAnchor.constraint(equalTo: previewPane.trailingAnchor, constant: -6),
            previewQL.topAnchor.constraint(equalTo: previewPane.topAnchor, constant: 6),
            previewQL.bottomAnchor.constraint(equalTo: previewPane.bottomAnchor, constant: -6),
        ])
        // panneau texte pour l'aperçu des mails (superposé, affiché à la place du Quick Look)
        previewMailScroll.translatesAutoresizingMaskIntoConstraints = false
        previewMailScroll.drawsBackground = false
        previewMailScroll.hasVerticalScroller = true
        previewMailScroll.isHidden = true
        previewMailText.isEditable = false
        previewMailText.isSelectable = false   // ne pas capter le focus clavier du panneau
        previewMailText.drawsBackground = false
        previewMailText.textContainerInset = NSSize(width: 6, height: 8)
        previewMailText.minSize = NSSize(width: 0, height: 0)
        previewMailText.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        previewMailText.isVerticallyResizable = true
        previewMailText.isHorizontallyResizable = false
        previewMailText.autoresizingMask = [.width]
        previewMailText.textContainer?.widthTracksTextView = true
        previewMailScroll.documentView = previewMailText
        previewPane.addSubview(previewMailScroll)
        NSLayoutConstraint.activate([
            previewMailScroll.leadingAnchor.constraint(equalTo: previewPane.leadingAnchor, constant: 6),
            previewMailScroll.trailingAnchor.constraint(equalTo: previewPane.trailingAnchor, constant: -6),
            previewMailScroll.topAnchor.constraint(equalTo: previewPane.topAnchor, constant: 6),
            previewMailScroll.bottomAnchor.constraint(equalTo: previewPane.bottomAnchor, constant: -6),
        ])
        split.addSubview(scroll)
        split.addSubview(previewPane)
        ve.addSubview(split)

        filterBar.frame = NSRect(x: 12, y: H - 90, width: W - 24 - 196, height: 24)
        filterBar.segmentStyle = .roundRect
        filterBar.autoresizingMask = [.minYMargin, .width]
        filterBar.target = self; filterBar.action = #selector(filterChanged)
        filterBar.isHidden = true
        ve.addSubview(filterBar)

        previewChk.frame = NSRect(x: W - 12 - 80 - 8 - 92, y: H - 90, width: 92, height: 24)
        previewChk.setButtonType(.switch); previewChk.title = "Aperçu"
        previewChk.font = .systemFont(ofSize: 11); previewChk.state = previewEnabled ? .on : .off
        previewChk.autoresizingMask = [.minYMargin, .minXMargin]
        previewChk.target = self; previewChk.action = #selector(previewToggled)
        previewChk.isHidden = true
        ve.addSubview(previewChk)

        sortBtn.frame = NSRect(x: W - 12 - 80, y: H - 90, width: 80, height: 24)
        sortBtn.title = "⇅ Récent"; sortBtn.bezelStyle = .roundRect
        sortBtn.setButtonType(.pushOnPushOff); sortBtn.font = .systemFont(ofSize: 11)
        sortBtn.autoresizingMask = [.minYMargin, .minXMargin]
        sortBtn.target = self; sortBtn.action = #selector(sortToggled)
        sortBtn.isHidden = true
        ve.addSubview(sortBtn)

        let grip = ResizeGrip(frame: NSRect(x: W - 18, y: 2, width: 16, height: 16))
        grip.win = panel; grip.autoresizingMask = [.minXMargin, .maxYMargin]
        ve.addSubview(grip)

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self = self, self.panel.isVisible else { return e }
            switch e.keyCode {
            case 125: self.move(1); return nil
            case 126: self.move(-1); return nil
            case 36, 76:
                if e.modifierFlags.contains(.command) { self.revealSel() } else { self.activateSel() }
                return nil
            case 16 where e.modifierFlags.contains(.command): self.quickLook(); return nil
            case 53: self.hide(); return nil
            default: return e
            }
        }
        applyTheme()
        startHeartbeat()
    }

    // --- battement de cœur pour le poste de contrôle ---
    // Un Timer sur la boucle principale : il ne se déclenche QUE si le thread
    // principal tourne. Si l'app est figée, le battement se tait → le poste de
    // contrôle la passe au jaune (le PID seul ne suffit pas à dire "vivante").
    func startHeartbeat() {
        beat()
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.beat() }
    }
    func beat() {
        let p = (NSHomeDirectory() as NSString).appendingPathComponent("Scripts/poste-controle-battements.json")
        DispatchQueue.global(qos: .utility).async {
            var d: [String: Double] = [:]
            if let data = try? Data(contentsOf: URL(fileURLWithPath: p)),
               let j = try? JSONSerialization.jsonObject(with: data) as? [String: Double] { d = j }
            d["com.vassili.spotlightsens-app"] = Date().timeIntervalSince1970
            if let out = try? JSONSerialization.data(withJSONObject: d) {
                try? out.write(to: URL(fileURLWithPath: p), options: .atomic)
            }
        }
    }

    // --- recherche ---
    func controlTextDidChange(_ obj: Notification) { alog("frappe: '\(search.stringValue)'"); performSearch(search.stringValue) }

    func performSearch(_ raw: String) {
        let q = raw.trimmingCharacters(in: .whitespaces)
        if q.count >= 1, let r = tryCurrency(q) ?? tryCalc(q) {
            allItems = [r]; currentCat = "Tout"; filterBar.isHidden = true; sortBtn.isHidden = true; previewChk.isHidden = true
            split.frame = NSRect(x: 0, y: 0, width: cw, height: chh - 60); previewPane.isHidden = true
            items = [r]; table.reloadData(); selectFirst(); return
        }
        if q.count < 2 {
            allItems = []; items = []; filterBar.isHidden = true; sortBtn.isHidden = true; previewChk.isHidden = true
            split.frame = NSRect(x: 0, y: 0, width: cw, height: chh - 60); previewPane.isHidden = true
            table.reloadData(); return
        }
        lastQ = q; lastAt = Date()
        seq += 1; let mine = seq
        let k = resultCount()
        guard let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed),
              let url = URL(string: daemon + "k=\(k)&q=" + enc) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self = self, mine == self.seq, let d = data,
                  let arr = try? JSONDecoder().decode([Hit].self, from: d) else { return }
            let its = arr.map { h in Item(title: h.title, subtitle: h.sub, url: h.open, symbol: h.symbol, isFile: h.isFile, cat: h.cat, date: h.date, mid: h.mid) }
            DispatchQueue.main.async {
                self.allItems = its
                self.currentCat = self.pendingCat ?? "Tout"; self.pendingCat = nil
                self.rebuildFilterBar(); self.applyFilter()
                if let ps = self.pendingSel {
                    let r = max(0, min(self.items.count - 1, ps))
                    if self.items.indices.contains(r) { self.table.selectRowIndexes([r], byExtendingSelection: false); self.table.scrollRowToVisible(r) }
                    self.pendingSel = nil
                }
            }
        }.resume()
    }

    func rebuildFilterBar() {
        var counts: [String: Int] = [:]
        for it in allItems where !it.cat.isEmpty { counts[it.cat, default: 0] += 1 }
        filterCats = ["Tout"]; var labels = ["Tout (\(allItems.count))"]
        for c in CATS where counts[c] != nil { filterCats.append(c); labels.append("\(c) (\(counts[c]!))") }
        if !filterCats.contains(currentCat) { currentCat = "Tout" }
        let hasCats = filterCats.count > 2
        let hasResults = !allItems.isEmpty
        filterBar.isHidden = !hasCats
        sortBtn.isHidden = !hasResults
        previewChk.isHidden = !hasResults
        split.frame = NSRect(x: 0, y: 0, width: cw, height: hasResults ? chh - 96 : chh - 60)
        if hasCats {
            filterBar.segmentCount = labels.count
            for (i, l) in labels.enumerated() { filterBar.setLabel(l, forSegment: i); filterBar.setWidth(0, forSegment: i) }
            filterBar.selectedSegment = max(0, filterCats.firstIndex(of: currentCat) ?? 0)
        }
        applyPreviewVisibility()
    }
    @objc func filterChanged() {
        let i = filterBar.selectedSegment
        currentCat = (i >= 0 && i < filterCats.count) ? filterCats[i] : "Tout"
        lastCat = currentCat
        applyFilter()
    }
    func applyFilter() {
        var base = currentCat == "Tout" ? allItems : allItems.filter { $0.cat == currentCat }
        if sortByDate { base.sort { $0.date > $1.date } }
        items = base
        table.reloadData(); selectFirst()
    }
    @objc func sortToggled() { sortByDate = (sortBtn.state == .on); applyFilter() }
    @objc func previewToggled() {
        previewEnabled = (previewChk.state == .on)
        var c = readConfig(); c["preview"] = previewEnabled; writeConfig(c)
        applyPreviewVisibility()
    }
    @objc func previewClicked() { activateSel() }
    func applyPreviewVisibility() {
        previewPane.isHidden = !previewEnabled
        let w = split.bounds.width
        if w > 0 {
            if previewEnabled {
                let pw = CGFloat((readConfig()["previewWidth"] as? Double) ?? 240)
                split.setPosition(max(200, w - max(140, pw)), ofDividerAt: 0)
            } else {
                split.setPosition(w, ofDividerAt: 0)
            }
        }
        updatePreview()
    }
    func updatePreview() {
        // quoi qu'il arrive, le clavier revient sur la barre (panneau jamais "figé")
        defer {
            if panel.isVisible {
                panel.makeFirstResponder(search)
                if let ed = search.currentEditor() { ed.selectedRange = NSRange(location: search.stringValue.count, length: 0) }
            }
        }
        guard previewEnabled else { return }
        previewToken += 1; let tok = previewToken
        let r = table.selectedRow
        guard r >= 0, r < items.count else {
            previewQL.previewItem = nil; previewQL.isHidden = false; previewMailScroll.isHidden = true; return
        }
        let it = items[r]
        if it.isFile, let u = it.url {                       // fichier -> Quick Look interactif
            previewMailScroll.isHidden = true; previewQL.isHidden = false
            previewQL.previewItem = URL(fileURLWithPath: u) as NSURL
        } else if it.cat == "Mail", let mid = it.mid {       // mail -> panneau texte
            previewQL.previewItem = nil; previewQL.isHidden = true
            previewMailScroll.isHidden = false
            previewMailText.string = "…"
            loadMailPreview(mid: mid, token: tok)
        } else {                                             // réglage, calcul… -> rien
            previewQL.previewItem = nil; previewQL.isHidden = false; previewMailScroll.isHidden = true
        }
    }

    func loadMailPreview(mid: String, token: Int) {
        guard let enc = mid.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed),
              let url = URL(string: "http://127.0.0.1:8799/mailbody?mid=" + enc) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self = self, let d = data,
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
            let from = (j["from"] as? String) ?? ""
            let subj = (j["subject"] as? String) ?? ""
            let date = (j["date"] as? String) ?? ""
            let body = (j["body"] as? String) ?? ""
            DispatchQueue.main.async {
                guard token == self.previewToken else { return }
                let att = NSMutableAttributedString()
                let hAttr: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: hexColor(self.theme.text)]
                let sAttr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: hexColor(self.theme.subtext)]
                let bAttr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: hexColor(self.theme.text)]
                att.append(NSAttributedString(string: subj + "\n", attributes: hAttr))
                att.append(NSAttributedString(string: from + (date.isEmpty ? "" : "  ·  " + date) + "\n\n", attributes: sAttr))
                att.append(NSAttributedString(string: body, attributes: bAttr))
                self.previewMailText.textStorage?.setAttributedString(att)
                self.previewMailText.scrollRangeToVisible(NSRange(location: 0, length: 0))
            }
        }.resume()
    }
    func tableViewSelectionDidChange(_ notification: Notification) { if table.selectedRow >= 0 { lastSel = table.selectedRow }; updatePreview() }
    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool { subview === previewPane }
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMin: CGFloat, ofSubviewAt i: Int) -> CGFloat { 220 }
    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMax: CGFloat, ofSubviewAt i: Int) -> CGFloat { max(220, split.bounds.width - 140) }
    func splitViewDidResizeSubviews(_ notification: Notification) {
        if previewEnabled, previewPane.frame.width > 0 { var c = readConfig(); c["previewWidth"] = Double(previewPane.frame.width); writeConfig(c) }
    }

    // --- table ---
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        let it = items[row]
        let v = NSView(frame: NSRect(x: 0, y: 0, width: tv.bounds.width, height: 50))
        let icon = NSImageView(frame: NSRect(x: 14, y: 11, width: 28, height: 28))
        icon.imageScaling = .scaleProportionallyUpOrDown
        if it.isFile, let u = it.url {
            let base = NSWorkspace.shared.icon(forFile: u)
            let ext = (u as NSString).pathExtension
            icon.image = badgedIcon(base, ext); icon.contentTintColor = nil
        } else {
            icon.image = NSImage(systemSymbolName: it.symbol, accessibilityDescription: nil)
            icon.contentTintColor = it.big ? hexColor(theme.subtext) : hexColor(theme.accent)
        }
        v.addSubview(icon)
        let title = NSTextField(labelWithString: "")
        title.lineBreakMode = .byTruncatingTail
        title.autoresizingMask = [.width]
        title.frame = NSRect(x: 52, y: it.big ? 12 : 24, width: tv.bounds.width - 64, height: it.big ? 28 : 18)
        if it.big {
            let a = NSMutableAttributedString()
            a.append(NSAttributedString(string: it.pre, attributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: hexColor(theme.text)]))
            a.append(NSAttributedString(string: it.title, attributes: [.font: NSFont.systemFont(ofSize: 24, weight: .semibold), .foregroundColor: hexColor(theme.result)]))
            title.attributedStringValue = a
        } else {
            title.font = NSFont.systemFont(ofSize: 14)
            title.textColor = hexColor(theme.text)
            title.stringValue = it.title
        }
        v.addSubview(title)
        if !it.subtitle.isEmpty {
            let sub = NSTextField(labelWithString: it.subtitle)
            sub.font = NSFont.systemFont(ofSize: 11.5)
            sub.textColor = hexColor(theme.subtext)
            sub.lineBreakMode = .byTruncatingTail
            sub.frame = NSRect(x: 52, y: it.big ? 0 : 7, width: tv.bounds.width - 64, height: 15)
            sub.autoresizingMask = [.width]
            v.addSubview(sub)
        }
        return v
    }

    func selectFirst() { if !items.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) } }
    func move(_ d: Int) {
        guard !items.isEmpty else { return }
        let r = max(0, min(items.count - 1, table.selectedRow + d))
        table.selectRowIndexes([r], byExtendingSelection: false)
        table.scrollRowToVisible(r)
    }
    @objc func activateSel() {
        let r = table.selectedRow
        guard r >= 0, r < items.count else { return }
        let it = items[r]
        if let a = it.answer {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(a, forType: .string)
        } else if let u = it.url {
            if it.isFile { NSWorkspace.shared.open(URL(fileURLWithPath: u)) }
            else if let url = URL(string: u) { NSWorkspace.shared.open(url) }
        }
        hide()
    }

    @objc func clicked() {
        if table.clickedRow >= 0 { table.selectRowIndexes([table.clickedRow], byExtendingSelection: false) }
        let cmd = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
        if cmd { revealSel() } else { activateSel() }
    }
    @objc func quickLook() {
        previewURLs = items.filter { $0.isFile }.compactMap { $0.url }.map { URL(fileURLWithPath: $0) }
        guard !previewURLs.isEmpty, let ql = QLPreviewPanel.shared() else { return }
        var idx = 0
        let sel = table.selectedRow
        if sel >= 0, sel < items.count, items[sel].isFile, let u = items[sel].url,
           let i = previewURLs.firstIndex(of: URL(fileURLWithPath: u)) { idx = i }
        ql.makeKeyAndOrderFront(nil); ql.reloadData(); ql.currentPreviewItemIndex = idx
    }
    func contextMenu() -> NSMenu {
        let m = NSMenu()
        let r = table.selectedRow
        guard r >= 0, r < items.count else { return m }
        let it = items[r]
        if it.answer != nil {
            m.addItem(withTitle: "Copier", action: #selector(activateSel), keyEquivalent: "")
        } else if it.isFile {
            m.addItem(withTitle: "Aperçu (Quick Look)", action: #selector(quickLook), keyEquivalent: "")
            m.addItem(withTitle: "Ouvrir", action: #selector(activateSel), keyEquivalent: "")
            m.addItem(withTitle: "Ouvrir l'emplacement", action: #selector(revealSel), keyEquivalent: "")
        } else {
            m.addItem(withTitle: "Ouvrir dans Mail", action: #selector(activateSel), keyEquivalent: "")
        }
        m.items.forEach { $0.target = self }
        return m
    }
    @objc func revealSel() {
        let r = table.selectedRow
        guard r >= 0, r < items.count else { return }
        let it = items[r]
        if it.isFile, let u = it.url {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: u)]); hide()
        } else { activateSel() }
    }

    // --- fenêtre ---
    func show() {
        if let s = NSScreen.main {
            let f = panel.frame
            panel.setFrameOrigin(NSPoint(x: s.frame.midX - f.width / 2, y: s.frame.midY - f.height / 2 + 120))
        }
        if !lastQ.isEmpty && Date().timeIntervalSince(lastAt) <= 120 {
            search.stringValue = lastQ; pendingCat = lastCat; pendingSel = lastSel; performSearch(lastQ)
        } else { search.stringValue = ""; allItems = []; items = []; table.reloadData() }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(search)
        applyPreviewVisibility()
        if let ed = search.currentEditor() { ed.selectedRange = NSRange(location: search.stringValue.count, length: 0) }
    }
    func hide() { panel.orderOut(nil) }
    func toggle() { panel.isVisible ? hide() : show() }
    func applyTheme() {
        panel.appearance = NSAppearance(named: theme.dark ? .darkAqua : .aqua)
        if let ve = panel.contentView as? NSVisualEffectView {
            ve.material = theme.dark ? .hudWindow : .popover
            ve.maskImage = roundedMask(theme.corner)
        }
        tint.layer?.backgroundColor = hexColor(theme.bg, theme.opacity).cgColor
        tint.layer?.cornerRadius = theme.corner
        tint.layer?.masksToBounds = true
        previewPane.layer?.backgroundColor = hexColor(theme.bg, 0.22).cgColor
        search.textColor = hexColor(theme.text)
        table.reloadData()
    }
    func reloadTheme() { theme = loadTheme(currentThemeSlug()); applyTheme() }
    func tableView(_ tv: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rv = ThemeRowView(); rv.accent = hexColor(theme.accent); return rv
    }
    func windowDidResignKey(_ n: Notification) { hide() }
}

extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var c = CharacterSet.urlQueryAllowed; c.remove(charactersIn: "&+"); return c
    }()
}

extension Controller: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { previewURLs[index] as NSURL }
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        if event.type == .keyDown {
            if event.keyCode == 125 { panel.currentPreviewItemIndex = min(previewURLs.count - 1, panel.currentPreviewItemIndex + 1); return true }
            if event.keyCode == 126 { panel.currentPreviewItemIndex = max(0, panel.currentPreviewItemIndex - 1); return true }
        }
        return false
    }
}


// ---------- Raccourci global (Carbon) ----------
var gController: Controller?
var gHotKeyRef: EventHotKeyRef?

func hkHandler(_ next: EventHandlerCallRef?, _ evt: EventRef?, _ ud: UnsafeMutableRawPointer?) -> OSStatus {
    DispatchQueue.main.async { gController?.toggle() }
    return noErr
}

func registerHotKey() {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), hkHandler, 1, &spec, nil, nil)
    let hkID = EventHotKeyID(signature: OSType(0x53504F54), id: 1)
    RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey), hkID, GetApplicationEventTarget(), 0, &gHotKeyRef)
}

// ---------- Réglages ----------
final class SettingsController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var window: NSWindow?
    let cbDocs = NSButton(checkboxWithTitle: "Mes documents  (~/Documents)", target: nil, action: nil)
    let cbDesk = NSButton(checkboxWithTitle: "Bureau  (~/Desktop)", target: nil, action: nil)
    let cbDl = NSButton(checkboxWithTitle: "Téléchargements  (~/Downloads)", target: nil, action: nil)
    let cbApps = NSButton(checkboxWithTitle: "Applications  (/Applications)", target: nil, action: nil)
    let table = NSTableView()
    let resultsField = NSTextField()
    var stepper: NSStepper?
    var extra: [String] = []

    func show() { build(); loadState(); window?.center(); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func stepChanged(_ s: NSStepper) { resultsField.integerValue = s.integerValue }

    func build() {
        if window != nil { return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 500),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Réglages"
        w.isReleasedWhenClosed = false
        let v = w.contentView!
        func label(_ s: String, _ y: CGFloat, _ size: CGFloat, _ bold: Bool) -> NSTextField {
            let l = NSTextField(labelWithString: s); l.frame = NSRect(x: 20, y: y, width: 440, height: 20)
            l.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size); v.addSubview(l); return l
        }
        _ = label("Dossiers indexés par la recherche", 464, 14, true)
        for (i, cb) in [cbDocs, cbDesk, cbDl, cbApps].enumerated() {
            cb.frame = NSRect(x: 24, y: 432 - CGFloat(i) * 26, width: 440, height: 20); v.addSubview(cb)
        }
        _ = label("Nombre de résultats affichés", 348, 13, true)
        resultsField.frame = NSRect(x: 262, y: 344, width: 70, height: 24); resultsField.alignment = .right
        v.addSubview(resultsField)
        let step = NSStepper(); step.frame = NSRect(x: 338, y: 342, width: 20, height: 28)
        step.minValue = 5; step.maxValue = 300; step.increment = 10; step.valueWraps = false
        step.target = self; step.action = #selector(stepChanged(_:)); v.addSubview(step); stepper = step
        _ = label("Dossiers supplémentaires", 308, 13, true)
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 100, width: 440, height: 200))
        scroll.borderType = .bezelBorder; scroll.hasVerticalScroller = true
        table.headerView = nil; table.rowHeight = 22
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("f")); col.width = 420
        table.addTableColumn(col); table.dataSource = self; table.delegate = self
        scroll.documentView = table; v.addSubview(scroll)
        let add = NSButton(title: "Ajouter un dossier…", target: self, action: #selector(addFolder)); add.frame = NSRect(x: 20, y: 60, width: 180, height: 30); v.addSubview(add)
        let rm = NSButton(title: "Retirer", target: self, action: #selector(removeFolder)); rm.frame = NSRect(x: 206, y: 60, width: 90, height: 30); v.addSubview(rm)
        let save = NSButton(title: "Enregistrer", target: self, action: #selector(saveAndReindex)); save.frame = NSRect(x: 330, y: 16, width: 130, height: 34); save.keyEquivalent = "\r"; v.addSubview(save)
        window = w
    }

    func loadState() {
        let f = Set(indexedFolders()); let home = NSHomeDirectory()
        cbDocs.state = f.contains(home + "/Documents") ? .on : .off
        cbDesk.state = f.contains(home + "/Desktop") ? .on : .off
        cbDl.state = f.contains(home + "/Downloads") ? .on : .off
        cbApps.state = f.contains("/Applications") ? .on : .off
        let defs = Set(defaultFolders())
        extra = indexedFolders().filter { !defs.contains($0) }
        resultsField.integerValue = resultCount(); stepper?.integerValue = resultCount()
        table.reloadData()
    }

    func numberOfRows(in t: NSTableView) -> Int { extra.count }
    func tableView(_ t: NSTableView, viewFor c: NSTableColumn?, row: Int) -> NSView? {
        NSTextField(labelWithString: (extra[row] as NSString).abbreviatingWithTildeInPath)
    }
    @objc func addFolder() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = true
        if p.runModal() == .OK { for u in p.urls where !extra.contains(u.path) { extra.append(u.path) }; table.reloadData() }
    }
    @objc func removeFolder() { let r = table.selectedRow; if r >= 0 && r < extra.count { extra.remove(at: r); table.reloadData() } }
    @objc func saveAndReindex() {
        let home = NSHomeDirectory(); var folders: [String] = []
        if cbDocs.state == .on { folders.append(home + "/Documents") }
        if cbDesk.state == .on { folders.append(home + "/Desktop") }
        if cbDl.state == .on { folders.append(home + "/Downloads") }
        if cbApps.state == .on { folders.append("/Applications") }
        folders += extra
        let n = max(5, min(300, resultsField.integerValue == 0 ? 60 : resultsField.integerValue))
        let changed = folders != indexedFolders()
        var c = readConfig(); c["folders"] = folders; c["results"] = n; writeConfig(c)
        window?.close()
        if changed {
            let proc = Process(); proc.launchPath = "/bin/bash"
            proc.arguments = ["-lc", "\(home)/Scripts/semsearch/venv/bin/python \(home)/Scripts/spotlight-sens/docs_index.py && launchctl kickstart -k gui/$(id -u)/com.vassili.spotlight-sens-daemon"]
            try? proc.run()
            let a = NSAlert(); a.messageText = "Ré-indexation lancée"
            a.informativeText = "Les dossiers choisis s'indexent en arrière-plan (quelques minutes). La recherche se met à jour toute seule à la fin."
            a.runModal()
        }
    }
}

// ---------- Lancement ----------
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    let settings = SettingsController()
    func applicationDidFinishLaunching(_ n: Notification) {
        gController = Controller()
        registerHotKey()
        let si = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        si.button?.image = NSImage(systemSymbolName: "magnifyingglass.circle.fill", accessibilityDescription: "Recherche par le sens")
        let menu = NSMenu()
        let open = NSMenuItem(title: "Ouvrir la recherche", action: #selector(openBar), keyEquivalent: ""); open.target = self; menu.addItem(open)
        let themeItem = NSMenuItem(title: "Thème", action: nil, keyEquivalent: "")
        let tm = NSMenu(); let cur = currentThemeSlug()
        if let files = try? FileManager.default.contentsOfDirectory(atPath: themesDir()) {
            for f in files.sorted() where f.hasSuffix(".json") {
                let slug = String(f.dropLast(5))
                let mi = NSMenuItem(title: loadTheme(slug).name, action: #selector(selectTheme(_:)), keyEquivalent: "")
                mi.target = self; mi.representedObject = slug; mi.state = (slug == cur) ? .on : .off
                tm.addItem(mi)
            }
        }
        themeItem.submenu = tm; menu.addItem(themeItem)
        let set = NSMenuItem(title: "Réglages…", action: #selector(openSettings), keyEquivalent: ","); set.target = self; menu.addItem(set)
        menu.addItem(.separator())
        let ri = NSMenuItem(title: "Ré-indexer les mails", action: #selector(reindex), keyEquivalent: ""); ri.target = self; menu.addItem(ri)
        menu.addItem(.separator())
        let q = NSMenuItem(title: "Quitter", action: #selector(quitApp), keyEquivalent: "q"); q.target = self; menu.addItem(q)
        si.menu = menu
        statusItem = si
    }
    @objc func openBar() { gController?.show() }
    @objc func openSettings() { settings.show() }
    @objc func reindex() {
        let p = Process(); p.launchPath = "/bin/zsh"
        p.arguments = ["-lc", "launchctl kickstart -k gui/$(id -u)/com.vassili.spotlight-sens-reindex"]
        try? p.run()
    }
    @objc func selectTheme(_ sender: NSMenuItem) {
        guard let slug = sender.representedObject as? String else { return }
        var c = readConfig(); c["theme"] = slug; writeConfig(c)
        sender.menu?.items.forEach { $0.state = (($0.representedObject as? String) == slug) ? .on : .off }
        gController?.reloadTheme()
    }
    @objc func quitApp() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
