import Cocoa
import ServiceManagement

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, AppProtocol {

    // MARK: -
    // MARK: Variables

    private var currentHelperConnection: NSXPCConnection?

    @objc dynamic private var currentHelperAuthData: NSData?
    private let currentHelperAuthDataKeyPath: String

    @objc dynamic private var helperIsInstalled = false
    private let helperIsInstalledKeyPath: String

    var statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
    var timer: Timer?
    let menu = NSMenu()
    let scriptPath = Bundle.main.resourcePath! + "/PDST.scpt"
    
    
    // MARK: -
    // MARK: NSApplicationDelegate Methods
    
    override init() {
        self.currentHelperAuthDataKeyPath = NSStringFromSelector(#selector(getter: self.currentHelperAuthData))
        self.helperIsInstalledKeyPath = NSStringFromSelector(#selector(getter: self.helperIsInstalled))
        super.init()
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification){
        // Insert code here to initialize your application
        checkPDVersion()
        
        do {
            try HelperAuthorization.authorizationRightsUpdateDatabase()
        } catch {
            log("Failed to update the authorization database rights with error: \(error)")
        }
        // Check if the current embedded helper tool is installed on the machine.
        self.helperStatus() { installed in
            let status = (installed) ? "Helper Launched" : "Helper Not Launched!"
            self.log(status)
        }

        constructMenu()
        if let button = statusItem.button {
            button.image = NSImage(named:NSImage.Name("MenuBarIcon"))
        }
        setPDST(nil)
        loop()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        PDST("stop")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    // MARK: -
    // MARK: runShell Methods
    
    @discardableResult
    func run(_ command: String) -> Int32 {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]
        task.launch()
        task.waitUntilExit()
        return task.terminationStatus
    }
    
    @discardableResult
    func runWithOutput(_ command: String) -> (status:Int32, output:String?) {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.launch()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)
        task.waitUntilExit()
        return (task.terminationStatus, output!.trimmingCharacters(in: NSCharacterSet.newlines))
    }
    
    // MARK: -
    // MARK: OBJC Func Methods
    
    @objc func loopFireHandler(_ timer: Timer?) -> Void {
        for app in NSWorkspace.shared.runningApplications
        {
            if app.activationPolicy == .regular && app.localizedName! == "Parallels Desktop"{
                constructMenu()
            }
        }
    }
    
    @objc func aboutDialog(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(self)
    }
    
    @objc func startVM(_ sender: NSMenuItem) {
        runPD()
        let ret = runWithOutput("/usr/local/bin/prlctl start \""+sender.title+"\" 2>&1").output!.components(separatedBy: "\n").last!
        skipProCheck(ret: ret,vm: sender.title)
        chTime("+")
        PDST("restart")
        NSWorkspace.shared.launchApplication("Parallels Desktop")
    }
    
    @objc func startAll(_ sender: Any?) {
        let vmlist = runWithOutput("/usr/local/bin/prlctl list -ao name -s uuid 2>/dev/null").output!.components(separatedBy: "\n")
        runPD()
        for vm in vmlist[1..<vmlist.count] {
            let ret = runWithOutput("/usr/local/bin/prlctl start \""+vm+"\" 2>&1").output!.components(separatedBy: "\n").last!
            skipProCheck(ret: ret,vm: vm)
        }
        chTime("+")
        PDST("restart")
        NSWorkspace.shared.launchApplication("Parallels Desktop")
    }
    
    @objc func stopAll(_ sender: Any?) {
        let unstoppedVMs = runWithOutput("/usr/local/bin/prlctl list -ao status,-,name -s uuid 2>/dev/null|grep -v stopped|sed 's/.*- *//g'").output!.components(separatedBy: "\n")
        for vm in unstoppedVMs[1..<unstoppedVMs.count] {
            run("/usr/local/bin/prlctl resume \""+vm+"\"")
            run("/usr/local/bin/prlctl stop \""+vm+"\"&")
        }
        PDST("restart")
    }
    
    @objc func setPDST(_ sender: Any?) {
        var PDSTstatus = UserDefaults.standard.bool(forKey: "PDST")
        if sender == nil{
            PDSTstatus = !UserDefaults.standard.bool(forKey: "PDST")
        }
        if PDSTstatus != true{
            menu.item(withTitle: NSLocalizedString("Kill Purchase UI", comment: "自动关闭购买窗口"))?.state = NSControl.StateValue.on
            UserDefaults.standard.set(true, forKey: "PDST")
            PDST("start")
        }else{
            if sender != nil{
                menu.item(withTitle: NSLocalizedString("Kill Purchase UI", comment: "自动关闭购买窗口"))?.state = NSControl.StateValue.off
                UserDefaults.standard.set(false, forKey: "PDST")
                PDST("stop")
            }
        }
        UserDefaults.standard.synchronize()
    }
    
    // MARK: -
    // MARK: Func Methods
    
    func dialogOKCancel(question: String, text: String) -> Bool {
        let myPopup: NSAlert = NSAlert()
        myPopup.messageText = question
        myPopup.informativeText = text
        myPopup.alertStyle = NSAlert.Style.warning
        myPopup.addButton(withTitle: "OK")
        //myPopup.addButton(withTitle: "取消")
        return myPopup.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn
    }
    
    func sudo(_ cmd: String){
        guard let helper = self.helper(nil) else { return }
        helper.runTask(arguments: cmd) {(exitCode) in self.log("Command exit code: \(exitCode)")}
    }
    
    func loop() {
        timer = Timer(timeInterval: 8, repeats: true, block: {timer in self.loopFireHandler(timer)})
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    func chTime(_ cmd: String){
        sudo("date $(date -j -f %s $((`date +%s`"+cmd+"315360000)) +%m%d%H%M%Y.%S)")
        if cmd == "+"{
            sudo("sntp -sS time.apple.com >/dev/null 2>&1")
        }
    }
    
    func PDST(_ cmd:String) {
        if (cmd == "start"){
            run("/usr/bin/osascript \""+scriptPath+"\"&")
        }else if (cmd == "restart"){
            run("kill -9 `ps ax -o pid,command|grep PDST.scpt|grep -v grep|awk '{print $1}'`")
            run("/usr/bin/osascript \""+scriptPath+"\"&")
        }else if (cmd == "stop"){
            run("kill -9 `ps ax -o pid,command|grep PDST.scpt|grep -v grep|awk '{print $1}'`")
        }
    }
    
    func runPD(){
        var apps = [String]()
        for app in NSWorkspace.shared.runningApplications
        {
            if(app.activationPolicy == .regular){
                apps.append(app.localizedName!)
            }
        }
        if apps.contains("Parallels Desktop"){
            chTime("-")
        }else{
            NSWorkspace.shared.launchApplication("Parallels Desktop")
            sleep(2)
            chTime("-")
        }
    }
    
    func skipProCheck(ret:String,vm:String){
        if (ret == "The command is available only in Parallels Desktop for Mac Pro or Business Edition."){
            run("killall prl_client_app")
            chTime("+")
            NSWorkspace.shared.launchApplication("Parallels Desktop")
            sleep(4)
            chTime("-")
            run("/usr/local/bin/prlctl start \""+vm+"\"")
        }
    }
    
    func checkPDVersion(){
        let appBundle = Bundle(path: NSWorkspace.shared.fullPath(forApplication: "Parallels Desktop")!)
        let pdVersion = appBundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        let comp = pdVersion.compare("17.1.0", options: .numeric)
        if [ComparisonResult.orderedDescending,ComparisonResult.orderedSame].contains(comp){
            if !checkHelper(){
                if !installHelper(){
                    _ = dialogOKCancel(question: NSLocalizedString("Failed to install helper!", comment: "安装帮助程序失败"), text: NSLocalizedString("Click OK to exit", comment: "点击OK退出程序"))
                    exit(1)
                }
            }
        }
    }
    
    func constructMenu() {
        menu.removeAllItems()
        let vmlist = runWithOutput("/usr/local/bin/prlctl list -ao name -s uuid 2>/dev/null").output!.components(separatedBy: "\n")
        let oslist = runWithOutput("/usr/local/bin/prlctl list -ao ostemplate -s uuid 2>/dev/null").output!.components(separatedBy: "\n")
        if vmlist[0] == "NAME" {
            if vmlist.count == 1 {
                menu.addItem(withTitle: NSLocalizedString("No VMs were found", comment: "未找到任何已安装的虚拟机"), action:nil, keyEquivalent: "")
            }else if vmlist.count > 1 {
                var num = 1
                for vm in vmlist[1..<vmlist.count] {
                    let os = oslist[vmlist.firstIndex(of: vm)!]
                    var icon = NSImage(named:NSImage.Name("Other"))
                    if ["ubuntu","fedora","fedora-core","debina","kali","linux","centos","redhat","mint","opensuse","manjaro", "arch"].contains(os){
                        icon = NSImage(named:NSImage.Name("Linux"))
                    }else if os.contains("win")||os.contains("Win"){
                        icon = NSImage(named:NSImage.Name("Win"))
                    }else if os.contains("macos"){
                        icon = NSImage(named:NSImage.Name("macOS"))
                    }
                    menu.addItem(withTitle: String(vm), action: #selector(AppDelegate.startVM(_:)), keyEquivalent: String(num)).image = icon
                    num += 1
                }
                //menu.addItem(withTitle: NSLocalizedString("Update VM List", comment: "更新虚拟机列表"), action: #selector(AppDelegate.updateMenu(_:)), keyEquivalent: "r")
                menu.addItem(NSMenuItem.separator())
                let submenu = NSMenu()
                menu.setSubmenu(submenu, for: menu.addItem(withTitle: NSLocalizedString("Batch action", comment: "启动所有虚拟机"), action: nil, keyEquivalent: ""))
                submenu.addItem(withTitle: NSLocalizedString("Start all VMs", comment: "启动所有虚拟机"), action: #selector(AppDelegate.startAll(_:)), keyEquivalent: "")
                submenu.addItem(withTitle: NSLocalizedString("Stop all VMs", comment: "关闭所有虚拟机"), action: #selector(AppDelegate.stopAll(_:)), keyEquivalent: "")
                menu.addItem(withTitle: NSLocalizedString("Block trial alert", comment: "自动关闭购买窗口"), action: #selector(AppDelegate.setPDST(_:)), keyEquivalent: "b")
                let PDSTstatus = UserDefaults.standard.bool(forKey: "PDST")
                if PDSTstatus == true{
                    menu.item(withTitle: NSLocalizedString("Block trial alert", comment: "自动关闭购买窗口"))?.state = NSControl.StateValue.on
                }else{
                    menu.item(withTitle: NSLocalizedString("Block trial alert", comment: "自动关闭购买窗口"))?.state = NSControl.StateValue.off
                }
            }
        } else {
            menu.addItem(withTitle: NSLocalizedString("Parallels Desktop not installed", comment: "未安装PD"), action:nil, keyEquivalent: "")
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: NSLocalizedString("About PD Runner", comment: "关于"), action: #selector(AppDelegate.aboutDialog(_:)), keyEquivalent: "")
        menu.addItem(withTitle: NSLocalizedString("Quit", comment: "退出"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }
    // MARK: -
    // MARK: AppProtocol Methods

    func log(_ log: String) {
        print(log)
    }

    // MARK: -
    // MARK: Helper Connection Methods

    func installHelper() -> Bool{
        do {
            if try self.helperInstaller() {
                log("Helper installed successfully.")
                return true
            } else {
                log("Failed install helper with unknown error.")
                return false
            }
        } catch {
            log("Failed to install helper with error: \(error)")
            return false
        }
    }
    
    func checkHelper() -> Bool {
        let helperPath = "/Library/PrivilegedHelperTools/com.lihaoyun6.PD-Runner-Helper"
        if !FileManager.default.fileExists(atPath: helperPath){
            return false
        }else{
            return true
        }
    }
    
    func helperConnection() -> NSXPCConnection? {
        guard self.currentHelperConnection == nil else {
            return self.currentHelperConnection
        }

        let connection = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)
        connection.exportedInterface = NSXPCInterface(with: AppProtocol.self)
        connection.exportedObject = self
        connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.invalidationHandler = {
            self.currentHelperConnection?.invalidationHandler = nil
            OperationQueue.main.addOperation {
                self.currentHelperConnection = nil
            }
        }

        self.currentHelperConnection = connection
        self.currentHelperConnection?.resume()

        return self.currentHelperConnection
    }

    func helper(_ completion: ((Bool) -> Void)?) -> HelperProtocol? {

        // Get the current helper connection and return the remote object (Helper.swift) as a proxy object to call functions on.

        guard let helper = self.helperConnection()?.remoteObjectProxyWithErrorHandler({ error in
            self.log("Helper connection was closed with error: \(error)")
            if let onCompletion = completion { onCompletion(false) }
        }) as? HelperProtocol else { return nil }
        return helper
    }

    func helperStatus(completion: @escaping (_ installed: Bool) -> Void) {

        // Comppare the CFBundleShortVersionString from the Info.plist in the helper inside our application bundle with the one on disk.

        let helperURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchServices/" + HelperConstants.machServiceName)
        guard
            let helperBundleInfo = CFBundleCopyInfoDictionaryForURL(helperURL as CFURL) as? [String: Any],
            let helperVersion = helperBundleInfo["CFBundleShortVersionString"] as? String,
            let helper = self.helper(completion) else {
                completion(false)
                return
        }

        helper.getVersion { installedHelperVersion in
            completion(installedHelperVersion == helperVersion)
        }
    }

    func helperInstaller() throws -> Bool {

        // Install and activate the helper inside our application bundle to disk.

        var cfError: Unmanaged<CFError>?
        var authItem = AuthorizationItem(name: kSMRightBlessPrivilegedHelper, valueLength: 0, value:UnsafeMutableRawPointer(bitPattern: 0), flags: 0)
        var authRights = AuthorizationRights(count: 1, items: &authItem)

        guard
            let authRef = try HelperAuthorization.authorizationRef(&authRights, nil, [.interactionAllowed, .extendRights, .preAuthorize]),
            SMJobBless(kSMDomainSystemLaunchd, HelperConstants.machServiceName as CFString, authRef, &cfError) else {
                if let error = cfError?.takeRetainedValue() { throw error }
                return false
        }

        self.currentHelperConnection?.invalidate()
        self.currentHelperConnection = nil

        return true
    }
}

