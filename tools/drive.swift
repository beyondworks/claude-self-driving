// self-driving: drive the Claude desktop app's own windows (computer-use tools cannot target this app).
// Keys and clicks are posted to the Claude app's process only. `type` and `enter` first bring the Claude
// app to the front and refuse unless the window `newwin` opened is the frontmost window.
// Needs Accessibility and "post events" permission for the app that runs Claude Code
// (System Settings > Privacy & Security > Accessibility). The person grants it; this tool never asks.
//
// Build once:  swiftc -O drive.swift -o drive
// Safety by design: this tool only starts a NEW session with ONE prompt.
//   - It acts only on the window that `newwin` opened (remembered in ~/.claude/self-driving-drive.json).
//   - Clicks must land inside that window's prompt box; keys go only while that window is the frontmost
//     window on screen and the app's focused window, checked again before every character.
//   - It refuses while any sheet or dialog is open in the app.
//   - After `enter` has sent the prompt once, click/type/enter are refused for that window, so it cannot
//     answer permission prompts or questions the new session raises. Talk to sessions with messages instead.
// Commands:
//   drive windows                      list Claude windows: id, title, bounds (points)
//   drive newwin "<menu item title>"   press an item of the File menu (the one that opens a new session in a new
//                                      window; its title depends on the app language) and print the new window id
//   drive click <x> <y>                left click at screen point (x, y); only inside the prompt box of the window newwin opened
//   drive type "<text>"                paste the text one character at a time (clipboard is restored afterwards)
//   drive enter                        press Return once to send the prompt
//   drive closewin                     press the close button of the window newwin opened
import AppKit
import ApplicationServices

let bid = "com.anthropic.claudefordesktop"
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first else { print("Claude app is not running"); exit(1) }
let pid = app.processIdentifier
let ax = AXUIElementCreateApplication(pid)
func attr(_ e: AXUIElement, _ k: String) -> AnyObject? { var v: AnyObject?; AXUIElementCopyAttributeValue(e, k as CFString, &v); return v }
func kids(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func title(_ e: AXUIElement) -> String { (attr(e, kAXTitleAttribute) as? String) ?? "" }
func role(_ e: AXUIElement) -> String { (attr(e, kAXRoleAttribute) as? String) ?? "" }
func windows() -> [[String: Any]] {
  ((CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? [])
    .filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
}
func findMenu(_ e: AXUIElement, _ name: String, depth: Int = 0) -> AXUIElement? {
  if depth > 6 { return nil }
  for k in kids(e) {
    if role(k) == "AXMenuItem" && title(k) == name { return k }
    if let f = findMenu(k, name, depth: depth + 1) { return f }
  }
  return nil
}
let stateURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/self-driving-drive.json")
struct DriveState: Codable { var window: Int; var sent: Bool }
func loadState() -> DriveState? { (try? Data(contentsOf: stateURL)).flatMap { try? JSONDecoder().decode(DriveState.self, from: $0) } }
func saveState(_ st: DriveState) { try? FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true); try? JSONEncoder().encode(st).write(to: stateURL) }
func fail(_ m: String, _ code: Int32 = 7) -> Never { print(m); exit(code) }
func boundsOf(_ id: Int) -> CGRect? {
  guard let w = windows().first(where: { ($0[kCGWindowNumber as String] as? Int) == id }), let b = w[kCGWindowBounds as String] as? NSDictionary else { return nil }
  return CGRect(dictionaryRepresentation: b as CFDictionary)
}
// the AX window that IS this CG window, matched by window number (not by position: two windows can share a frame).
// _AXUIElementGetWindow is the long-standing private call that maps an AX window to its CG window id.
typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
let getWindow: GetWindowFn? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow").map { unsafeBitCast($0, to: GetWindowFn.self) }
func axWindow(_ id: Int) -> AXUIElement? {
  guard let gw = getWindow else { fail("cannot match windows by number on this macOS; refusing") }
  for w in (attr(ax, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
    var n: CGWindowID = 0
    if gw(w, &n) == .success, Int(n) == id { return w }
  }
  return nil
}
// refuse while any sheet or dialog is open anywhere in the app
func dialogOpen() -> String? {
  for w in (attr(ax, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
    let sub = (attr(w, kAXSubroleAttribute) as? String) ?? ""
    if sub == "AXDialog" || sub == "AXSystemDialog" || sub == "AXFloatingWindow" { return "a dialog is open" }
    if kids(w).contains(where: { role($0) == "AXSheet" }) { return "a sheet is open" }
  }
  return nil
}
func noDialogs() { if let why = dialogOpen() { fail(why + "; refusing") } }
// nil when the window newwin opened is the frontmost window on screen and the app's focused window.
// NSRunningApplication.isActive is not refreshed without a run loop, so read the window server's
// front-to-back list instead of it.
func notFront(_ id: Int, _ w: AXUIElement) -> String? {
  let front = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
    .first(where: { ($0[kCGWindowLayer as String] as? Int) == 0 })
  guard (front?[kCGWindowOwnerPID as String] as? Int32) == pid, (front?[kCGWindowNumber as String] as? Int) == id else {
    return "the window newwin opened is not the frontmost window"
  }
  guard let f = attr(ax, kAXFocusedWindowAttribute), CFEqual(f, w) else { return "the window newwin opened is not the focused window" }
  return nil
}
// the window newwin opened, still open, not yet sent
func target(forKeys: Bool) -> (DriveState, AXUIElement) {
  guard let st = loadState() else { fail("no window opened by newwin; run newwin first") }
  if st.sent { fail("this window already sent its prompt; drive only starts sessions. Use session messages for the rest.") }
  guard let w = axWindow(st.window) else { fail("the window newwin opened is gone") }
  noDialogs()
  if forKeys {
    // Keys posted to the app land in its key window, and a window is key only while the app is active.
    // AXRaise alone can leave another window (or none) key when the app is in the background, so the
    // keys would be lost or go elsewhere. Activate the app, raise the window, then require both.
    _ = app.activate()
    AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
    AXUIElementPerformAction(w, kAXRaiseAction as CFString)
    usleep(250_000)
    if let why = notFront(st.window, w) { fail(why + "; refusing to send keys") }
  }
  return (st, w)
}

func key(_ code: CGKeyCode, cmd: Bool = false) {
  let src = CGEventSource(stateID: .hidSystemState)
  for down in [true, false] {
    let ev = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)!
    if cmd { ev.flags = .maskCommand }
    ev.postToPid(pid)
    usleep(12_000)
  }
}
guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary) else {
  print("Accessibility permission is missing for the app running this tool. Ask the person to grant it; do not work around it."); exit(6)
}
let a = CommandLine.arguments
switch a.count > 1 ? a[1] : "" {
case "windows":
  for w in windows() { print(w[kCGWindowNumber as String]!, w[kCGWindowName as String] ?? "", w[kCGWindowBounds as String]!) }
case "check":  // check <window id>: which AX window that number maps to (no input is sent)
  guard a.count > 2, let id = Int(a[2]) else { print("usage: check <window id>"); exit(2) }
  if let w = axWindow(id) { print("window \(id) → \(title(w))") } else { print("window \(id) → not found") }
case "newwin":
  let before = Set(windows().compactMap { $0[kCGWindowNumber as String] as? Int })
  guard a.count > 2, let barRef = attr(ax, kAXMenuBarAttribute) else { print("usage: newwin <menu item title>"); exit(2) }
  // the File menu: the menu bar item titled File (or its translation); the Apple and app menus come first
  let menus = kids(barRef as! AXUIElement)
  let fileNames: Set<String> = ["File", "파일", "ファイル", "文件", "檔案", "Datei", "Fichier", "Archivo", "File "]
  let fileMenu = menus.first(where: { fileNames.contains(title($0)) }) ?? (menus.count > 2 ? menus[2] : nil)
  guard let fm = fileMenu, let item = findMenu(fm, a[2]) else { print("not found in the File menu: \(a[2])"); exit(2) }
  AXUIElementPerformAction(item, kAXPressAction as CFString)
  for _ in 0..<40 {
    usleep(250_000)
    if let n = windows().compactMap({ $0[kCGWindowNumber as String] as? Int }).first(where: { !before.contains($0) }) { saveState(DriveState(window: n, sent: false)); print(n); exit(0) }
  }
  print("no new window appeared"); exit(3)
case "click":
  guard a.count > 3, let x = Double(a[2]), let y = Double(a[3]) else { print("usage: click <x> <y>"); exit(2) }
  let (st, _) = target(forKeys: false)
  let p = CGPoint(x: x, y: y)
  guard let r = boundsOf(st.window), r.contains(p) else { fail("point is outside the window newwin opened") }
  // only the prompt box: the band above the bottom row (the bottom row holds model and permission-mode pickers)
  let box = CGRect(x: r.minX + 40, y: r.maxY - 115, width: r.width - 80, height: 70)
  guard box.contains(p) else { fail("only the prompt box at the bottom of the window can be clicked") }
  for t in [CGEventType.leftMouseDown, .leftMouseUp] {
    CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)!.postToPid(pid)
    usleep(30_000)
  }
case "type":
  guard a.count > 2 else { print("usage: type <text>"); exit(2) }
  let (tst, tw) = target(forKeys: true)
  let pb = NSPasteboard.general
  // keep every item and type on the clipboard (images, files, rich text), not only plain text
  let saved: [NSPasteboardItem] = (pb.pasteboardItems ?? []).map { it in
    let c = NSPasteboardItem(); for t in it.types { if let d = it.data(forType: t) { c.setData(d, forType: t) } }; return c
  }
  // mark each character as transient so clipboard-history apps skip it
  let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
  func restoreAndFail(_ why: String) -> Never {
    pb.clearContents(); if !saved.isEmpty { pb.writeObjects(saved) }
    fail(why + "; stopped typing (clipboard restored). Some characters may be left in the prompt box: clear it before typing again.")
  }
  for ch in a[2] {
    pb.clearContents(); pb.setString(String(ch), forType: .string); pb.setData(Data(), forType: transient)
    usleep(20_000)
    // check again right before every paste: another window, app, sheet, or dialog may have come up
    // meanwhile, and the rest of the text would then be lost or pasted somewhere else
    if let why = notFront(tst.window, tw) { restoreAndFail(why) }
    if let why = dialogOpen() { restoreAndFail(why) }
    key(9, cmd: true)                                      // ⌘V
    usleep(UInt32(Double.random(in: 0.6...1.4) * 50_000))  // about 14 characters a second, slightly uneven
  }
  pb.clearContents(); if !saved.isEmpty { pb.writeObjects(saved) }
case "enter":
  var (st, _) = target(forKeys: true)
  key(36)
  st.sent = true; saveState(st)
case "closewin":
  guard let st = loadState(), let w = axWindow(st.window) else { fail("no window opened by newwin is open") }
  guard let b = attr(w, kAXCloseButtonAttribute) else { print("no close button"); exit(5) }
  AXUIElementPerformAction(b as! AXUIElement, kAXPressAction as CFString)
  try? FileManager.default.removeItem(at: stateURL)
default:
  print("windows | newwin <File menu item title> | click <x> <y> | type <text> | enter | closewin")
}
