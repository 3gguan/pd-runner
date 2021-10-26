//
//  AppDelegate.swift
//  PD Runner
//
//  Created by lihaoyun on 2021/10/7.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    var statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
    var timer: Timer?
    let menu = NSMenu()
    let scriptPath = Bundle.main.resourcePath! + "/PDST.scpt"
    
    func applicationDidFinishLaunching(_ aNotification: Notification){
        // Insert code here to initialize your application
        checkUser()
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
        let ret = runWithOutput("sudo -u "+getUser()+" /usr/local/bin/prlctl start \""+sender.title+"\" 2>&1").output!.components(separatedBy: "\n").last!
        skipProCheck(ret: ret,vm: sender.title)
        chTime("+")
        PDST("restart")
        NSWorkspace.shared.launchApplication("Parallels Desktop")
    }
    
    @objc func startAll(_ sender: Any?) {
        let vmlist = runWithOutput("sudo -u "+getUser()+" /usr/local/bin/prlctl list -ao name -s uuid 2>/dev/null").output!.components(separatedBy: "\n")
        runPD()
        for vm in vmlist[1..<vmlist.count] {
            let ret = runWithOutput("sudo -u "+getUser()+" /usr/local/bin/prlctl start \""+vm+"\" 2>&1").output!.components(separatedBy: "\n").last!
            skipProCheck(ret: ret,vm: vm)
        }
        chTime("+")
        PDST("restart")
        NSWorkspace.shared.launchApplication("Parallels Desktop")
    }
    
    @objc func stopAll(_ sender: Any?) {
        let unstoppedVMs = runWithOutput("sudo -u "+getUser()+" /usr/local/bin/prlctl list -ao status,-,name -s uuid 2>/dev/null|grep -v stopped|sed 's/.*- *//g'").output!.components(separatedBy: "\n")
        for vm in unstoppedVMs[1..<unstoppedVMs.count] {
            run("sudo -u "+getUser()+" /usr/local/bin/prlctl resume \""+vm+"\"")
            run("sudo -u "+getUser()+" /usr/local/bin/prlctl stop \""+vm+"\"&")
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
    
    func loop() {
        timer = Timer(timeInterval: 8, repeats: true, block: {timer in self.loopFireHandler(timer)})
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    func chTime(_ cmd: String){
        if cmd == "+"{
            run("date $(date -j -f %s $((`date +%s`+315360000)) +%m%d%H%M%Y.%S)")
            run("sntp -sS time.apple.com >/dev/null 2>&1")
        }else if cmd == "-"{
            run("date $(date -j -f %s $((`date -%s`+315360000)) +%m%d%H%M%Y.%S)")
        }
    }
    
    func PDST(_ cmd:String) {
        if (cmd == "start"){
            run("sudo -u "+getUser()+" /usr/bin/osascript \""+scriptPath+"\"&")
        }else if (cmd == "restart"){
            run("kill -9 `ps ax -o pid,command|grep PDST.scpt|grep -v grep|awk '{print $1}'`")
            run("sudo -u "+getUser()+" /usr/bin/osascript \""+scriptPath+"\"&")
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
            run("sudo -u "+getUser()+" /usr/local/bin/prlctl start \""+vm+"\"")
        }
    }
    
    func checkUser(){
        let appBundle = Bundle(path: NSWorkspace.shared.fullPath(forApplication: "Parallels Desktop")!)
        let pdVersion = appBundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        let comp = pdVersion.compare("17.1.0", options: .numeric)
        let user = runWithOutput("whoami").output!
        if [ComparisonResult.orderedDescending,ComparisonResult.orderedSame].contains(comp) && user != "root"{
            NSAppleScript(source: "do shell script \""+CommandLine.arguments[0].replacingOccurrences(of: " ", with: "\\\\ ")+" "+user+" > /dev/null 2>&1 &\" with prompt \""+NSLocalizedString("For Parallels Desktop 17.1.0 or later, PD runner need to run with administrator privileges.", comment: "提权提示")+"\" with administrator privileges")!.executeAndReturnError(nil)
            exit(1)}
    }
    
    func getUser() -> String{
        let user = runWithOutput("whoami").output!
        if user == "root"{
            return CommandLine.arguments[1]
        }else{
            return user
        }
    }
    
    func constructMenu() {
        menu.removeAllItems()
        let vmlist = runWithOutput("sudo -u "+getUser()+" /usr/local/bin/prlctl list -ao name -s uuid 2>/dev/null").output!.components(separatedBy: "\n")
        let oslist = runWithOutput("sudo -u "+getUser()+" /usr/local/bin/prlctl list -ao ostemplate -s uuid 2>/dev/null").output!.components(separatedBy: "\n")
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
}
