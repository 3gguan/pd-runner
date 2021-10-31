import Cocoa
import ServiceManagement

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, AppProtocol {

    // MARK: -
    // MARK: Variables

    var currentHelperConnection: NSXPCConnection?
    var statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
    var timer: Timer?
    let menu = NSMenu()
    let scriptPath = Bundle.main.resourcePath! + "/PDST.scpt"
    let appPath = Bundle.main.bundlePath
    var vmListBak = [String]()
    var sudoLock = false
    var helperConnectionState: Bool?
    
    // MARK: -
    // MARK: NSApplicationDelegate Methods
    
    func applicationDidFinishLaunching(_ aNotification: Notification){
        // Insert code here to initialize your application
        checkHelper()
        constructMenu()
        if let button = statusItem.button {
            button.image = NSImage(named:NSImage.Name("MenuBarIcon"))
        }
        setPDST(nil)
        loop()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        if UserDefaults.standard.bool(forKey: "PDST") {
            PDST("stop")
        }
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
        log("Starting VM: "+sender.title)
        runPD()
        prlctl("start", sender.title)
        PDST("restart")
    }
    
    @objc func startAll(_ sender: Any?) {
        let vmList = runWithOutput("/usr/local/bin/prlctl list -ao name -s mac 2>/dev/null").output!.components(separatedBy: "\n")
        runPD()
        for vm in vmList[1..<vmList.count] {
            log("Starting VM: "+vm)
            prlctl("start", vm)
        }
        PDST("restart")
    }
    
    @objc func stopAll(_ sender: Any?) {
        let vmList = runWithOutput("/usr/local/bin/prlctl list -ao name,-,-,-,-,status -s mac 2>/dev/null|sed 's/[ ]*-[ ]*/-/g;s/----/:/g'").output!.components(separatedBy: "\n")
        for vm in vmList[1..<vmList.count] {
            let vm = vm.components(separatedBy: ":")
            if vm[1] == "running"{
                log("Stoping VM: "+vm[0])
                prlctl("stop", vm[0])
            }
        }
        PDST("restart")
    }
    
    @objc func setPDST(_ sender: Any?) {
        let menuTitle = NSLocalizedString("Block trial alert", comment: "自动关闭购买窗口")
        var PDSTstatus = UserDefaults.standard.bool(forKey: "PDST")
        if sender == nil{
            PDSTstatus = !UserDefaults.standard.bool(forKey: "PDST")
        }
        if PDSTstatus != true{
            menu.item(withTitle: menuTitle)?.state = NSControl.StateValue.on
            PDST("start")
            if sender != nil{
                log("Run PDST = on")
                UserDefaults.standard.set(true, forKey: "PDST")
                UserDefaults.standard.synchronize()
            }
        }else{
            if sender != nil{
                log("Run PDST = off")
                menu.item(withTitle: menuTitle)?.state = NSControl.StateValue.off
                UserDefaults.standard.set(false, forKey: "PDST")
                UserDefaults.standard.synchronize()
                PDST("stop")
            }
        }
    }
    
    @objc func setLoginItem(_ sender: Any?) {
        let menuTitle = NSLocalizedString("Launch at Login", comment: "登录时启动")
        let loginItems = runWithOutput("osascript -e 'tell application \"System Events\" to get the name of every login item'").output!.components(separatedBy: ", ")
        if UserDefaults.standard.bool(forKey: "runAtLogin") != true {
            log("Run at Login = on")
            menu.item(withTitle: menuTitle)?.state = NSControl.StateValue.on
            UserDefaults.standard.set(true, forKey: "runAtLogin")
            if !loginItems.contains("PD Runner"){
                NSAppleScript(source: "tell application \"System Events\" to make login item with properties {path:\"\(appPath)\", hidden:false}")!.executeAndReturnError(nil)
            }
        }else{
            log("Run at Login = off")
            menu.item(withTitle: menuTitle)?.state = NSControl.StateValue.off
            UserDefaults.standard.set(false, forKey: "runAtLogin")
            if loginItems.contains("PD Runner"){
                NSAppleScript(source: "tell application \"System Events\" to delete login item \"PD Runner\"")!.executeAndReturnError(nil)
            }
        }
        UserDefaults.standard.synchronize()
    }
    
    // MARK: -
    // MARK: Func Methods
    
    @discardableResult
    func dialogOK(question: String, text: String) -> Bool {
        let myPopup: NSAlert = NSAlert()
        myPopup.messageText = question
        myPopup.informativeText = text
        myPopup.alertStyle = NSAlert.Style.warning
        myPopup.addButton(withTitle: "OK")
        //myPopup.addButton(withTitle: "取消")
        return myPopup.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn
    }
    
    func getString(title: String, question: String, defaultValue: String) -> String {
        let msg = NSAlert()
        msg.addButton(withTitle: NSLocalizedString("OK", comment: "确认"))
        msg.addButton(withTitle: NSLocalizedString("Cancel", comment: "取消"))
        msg.messageText = title
        msg.informativeText = question

        let txt = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        txt.stringValue = defaultValue

        msg.accessoryView = txt
        let response: NSApplication.ModalResponse = msg.runModal()

        if (response == NSApplication.ModalResponse.alertFirstButtonReturn) {
            return txt.stringValue
        } else {
            return ""
        }
    }
    
    func prlctl(_ cmd: String, _ vm: String){
        if runWithOutput("/usr/local/bin/prlctl list -i \"\(vm)\"|grep Encrypted|awk '{print $NF}'").output! == "yes"{
            let pass = getString(title: NSLocalizedString("Input password", comment: "虚拟机需要密码"), question: "\"\(vm)\" "+NSLocalizedString("is encrypted", comment: "已被加密"), defaultValue: "")
            if pass != "" {
                chTime("-")
                let ret = runWithOutput("echo \(pass)|/usr/local/bin/prlctl \(cmd) \"\(vm)\" 2>&1").output!.components(separatedBy: "\n").last!
                if skipProCheck(ret){run("echo \(pass)|/usr/local/bin/prlctl \(cmd) \"\(vm)\"")}
                chTime("+")
            }else{
                dialogOK(question: NSLocalizedString("No password entered", comment: "未输入密码"), text: "\"\(vm)\" "+NSLocalizedString("will not be started", comment: "将不会被启动"))
            }
        }else{
            chTime("-")
            let ret = runWithOutput("/usr/local/bin/prlctl \(cmd) \"\(vm)\" 2>&1").output!.components(separatedBy: "\n").last!
            if skipProCheck(ret){run("/usr/local/bin/prlctl \(cmd) \"\(vm)\"")}
            chTime("+")
        }
    }
    
    func sudo(_ cmd: String, _ log:Bool=false){
        sudoLock.toggle()
        guard let helper = self.helper(nil) else { return }
        helper.runTask(arguments: cmd) {(exitCode) in
            self.sudoLock.toggle()
            if log{ self.log("Command: [\(cmd)] with exit code: \(exitCode)") }
        }
        while true{if !sudoLock{break}}
    }
    
    func loop() {
        timer = Timer(timeInterval: 8, repeats: true, block: {timer in self.loopFireHandler(timer)})
        log("Run loop...")
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    func chTime(_ cmd: String){
        if cmd == "+"{
            log("Time+")
            sudo("date $(date -j -f %s $((`date +%s`+315360000)) +%m%d%H%M%Y.%S) >/dev/null 2>&1",true)
            sudo("sntp -sS time.apple.com >/dev/null 2>&1",true)
        }else if cmd == "-"{
            log("Time-")
            sudo("date $(date -j -f %s $((`date +%s`-315360000)) +%m%d%H%M%Y.%S) >/dev/null 2>&1;",true)
        }
    }
    
    func PDST(_ cmd:String) {
        if (cmd == "start"){
            log("Run PDST...")
            run("/usr/bin/osascript \"\(scriptPath)\"&")
        }else if (cmd == "restart"){
            if UserDefaults.standard.bool(forKey: "PDST") {
                log("restart PDST...")
                run("kill -9 `ps ax -o pid,command|grep PDST.scpt|grep -v grep|awk '{print $1}'`")
                run("/usr/bin/osascript \"\(scriptPath)\"&")
            }
        }else if (cmd == "stop"){
            log("Stop PDST")
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
            log("Parallels Desktop is running.")
            NSWorkspace.shared.launchApplication("Parallels Desktop")
        }else{
            log("Launching Parallels Desktop...")
            NSWorkspace.shared.launchApplication("Parallels Desktop")
            sleep(2)
        }
    }
    
    func skipProCheck(_ ret:String) -> Bool{
        log(ret)
        if (ret == "The command is available only in Parallels Desktop for Mac Pro or Business Edition."){
            log("Skipping Pro/Business Edition detection...")
            run("killall prl_client_app")
            chTime("+")
            NSWorkspace.shared.launchApplication("Parallels Desktop")
            sleep(4)
            chTime("-")
            return true
        }
        return false
    }
    
    func getIcon(_ os: String) -> NSImage{
        if ["win-11","win-10","ubuntu","fedora","fedora-core","debian","kali","centos","macos"].contains(os){
            return NSImage(named:NSImage.Name(os))!
        }else if os.contains("win")||os.contains("Win"){
            return NSImage(named:NSImage.Name("win"))!
        }else if ["redhat","mint","opensuse","manjaro", "arch", "linux", "lin"].contains(os){
            return NSImage(named:NSImage.Name("linux"))!
        }
        return NSImage(named:NSImage.Name("other"))!
    }
    
    func constructMenu() {
        menu.removeAllItems()
        let vmList = runWithOutput("/usr/local/bin/prlctl list -ao name,-,-,-,-,ostemplate -s mac 2>/dev/null|sed 's/[ ]*-[ ]*/-/g;s/----/:/g'").output!.components(separatedBy: "\n")
        //let vmList = runWithOutput("/usr/local/bin/prlctl list -ao name -s mac 2>/dev/null").output!.components(separatedBy: "\n")
        //let oslist = runWithOutput("/usr/local/bin/prlctl list -ao ostemplate,-,- -s mac 2>/dev/null").output!.replacingOccurrences(of: " ", with: "").components(separatedBy: "\n")
        if vmList[0] == "NAME:OSTEMPLATE" {
            if vmList.count == 1 {
                log("No VM are installed!")
                menu.addItem(withTitle: NSLocalizedString("No VMs were found", comment: "未找到任何已安装的虚拟机"), action:nil, keyEquivalent: "")
            }else if vmList.count > 1 {
                if vmList != vmListBak{
                    vmListBak = vmList
                    log("VM list: ["+vmList[1..<vmList.count].joined(separator: ",")+"]")
                }
                var num = 1
                for vm in vmList[1..<vmList.count] {
                    let vm = vm.components(separatedBy: ":")
                    //let os = oslist[vmList.firstIndex(of: vm)!]
                    //let vmState = runWithOutput("/usr/local/bin/prlctl list -i \"\(vm)\"|grep -E \"OS:|State:\"|awk -F ': ' '{print $NF}'").output!.components(separatedBy: "\n")
                    if vm[1] == "" {
                        menu.addItem(withTitle: String(vm[0]), action:nil, keyEquivalent: "").image = NSImage(named:NSImage.Name("invalid"))!
                    }else{
                        let icon = getIcon(vm[1])
                        menu.addItem(withTitle: String(vm[0]), action: #selector(AppDelegate.startVM(_:)), keyEquivalent: String(num)).image = icon
                        num += 1
                    }
                }
                //menu.addItem(withTitle: NSLocalizedString("Update VM List", comment: "更新虚拟机列表"), action: #selector(AppDelegate.updateMenu(_:)), keyEquivalent: "r")
                menu.addItem(NSMenuItem.separator())
                let submenu = NSMenu()
                menu.setSubmenu(submenu, for: menu.addItem(withTitle: NSLocalizedString("Batch action", comment: "启动所有虚拟机"), action: nil, keyEquivalent: ""))
                submenu.addItem(withTitle: NSLocalizedString("Start all VMs", comment: "启动所有虚拟机"), action: #selector(AppDelegate.startAll(_:)), keyEquivalent: "")
                submenu.addItem(withTitle: NSLocalizedString("Stop all VMs", comment: "关闭所有虚拟机"), action: #selector(AppDelegate.stopAll(_:)), keyEquivalent: "")
                menu.addItem(withTitle: NSLocalizedString("Block trial alert", comment: "自动关闭购买窗口"), action: #selector(AppDelegate.setPDST(_:)), keyEquivalent: "b")
                menu.addItem(withTitle: NSLocalizedString("Launch at Login", comment: "登录时启动"), action: #selector(AppDelegate.setLoginItem(_:)), keyEquivalent: "l")
                if UserDefaults.standard.bool(forKey: "PDST") == true { menu.item(withTitle: NSLocalizedString("Block trial alert", comment: "自动关闭购买窗口"))?.state = NSControl.StateValue.on }
                if UserDefaults.standard.bool(forKey: "runAtLogin") == true { menu.item(withTitle: NSLocalizedString("Launch at Login", comment: "登录时启动"))?.state = NSControl.StateValue.on }
            }
        } else {
            log("Parallels Desktop not installed!")
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
        let df = DateFormatter()
        df.dateFormat = "y-MM-dd H:m:ss.SSSS"
        print(df.string(from: Date()),log)
    }

    // MARK: -
    // MARK: Helper Connection Methods
    
    func checkHelper(){
        self.log("Check helper status...")
        
        let helperPath = "/Library/PrivilegedHelperTools/\(HelperConstants.machServiceName)"
        if !FileManager.default.fileExists(atPath: helperPath) {
            log("Helper not installed!")
            self.installHelper()
        } else {
            log("Helper installed.")
            let helperURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchServices/" + HelperConstants.machServiceName)
            guard
                let helperBundleInfo = CFBundleCopyInfoDictionaryForURL(helperURL as CFURL) as? [String: Any],
                let helperVersion = helperBundleInfo["CFBundleShortVersionString"] as? String,
                let helper = self.helper(nil) else { return }
            helper.getVersion { installedHelperVersion in
                self.log("Installed version: \(installedHelperVersion), InBundle version: \(helperVersion)")
                if (installedHelperVersion != helperVersion){
                    self.log("Helper needs to be updated!")
                    self.installHelper()
                }
            }
            while true{
                if helperConnectionState != nil{
                    if !helperConnectionState!{
                        self.log("Helper needs to be updated!")
                        self.installHelper()
                    }
                }
                break
            }
        }
        self.helperStatus() { installed in
            if !installed {
                self.log("Helper not installed!")
                self.installHelper()
            }else{
                self.log("Helper installed.")
            }
        }
    }
    
    func installHelper(){
        do {
            self.log("Try to install helper")
            if try self.helperInstaller() {
                self.log("Helper installed successfully.")
            } else {
                self.log("Failed install helper with unknown error.")
                NSAppleScript(source: "display dialog \"\(NSLocalizedString("Unknown error.", comment: "未知错误"))\" with title \"\(NSLocalizedString("Failed to install helper!", comment: "安装失败"))\" with icon 2")!.executeAndReturnError(nil)
                exit(1)
            }
        } catch {
            self.log("Failed to install helper with error: \(error)")
            let error = "\(error)"
            NSAppleScript(source: "display dialog \"\(error.replacingOccurrences(of: "\"", with: "\\\""))\" with title \"\(NSLocalizedString("Failed to install helper!", comment: "安装失败"))\" with icon 2")!.executeAndReturnError(nil)
            exit(1)
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
            self.helperConnectionState = false
            if let onCompletion = completion { onCompletion(false) }
        }) as? HelperProtocol else {
            self.helperConnectionState = true
            self.log("Helper connection succeeded.")
            return nil
        }
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
        log("Start installation...")
        guard
            let authRef = try HelperAuthorization.authorizationRef(&authRights, nil, [.interactionAllowed, .extendRights, .preAuthorize]),
            SMJobBless(kSMDomainSystemLaunchd, HelperConstants.machServiceName as CFString, authRef, &cfError) else {
                if let error = cfError?.takeRetainedValue() { throw error }
                return false
        }

        currentHelperConnection?.invalidate()
        currentHelperConnection = nil

        return true
    }
}




