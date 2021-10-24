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
    let menu = NSMenu()
    let scriptPath = Bundle.main.resourcePath! + "/PDST.scpt"
    var windowController : NSWindowController?
    
    func applicationDidFinishLaunching(_ aNotification: Notification){
        // Insert code here to initialize your application
        if let button = statusItem.button {
          button.image = NSImage(named:NSImage.Name("MenuBarIcon"))
        }
        checkUser()
        constructMenu()
        setPDST(nil)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        PDST(cmd:"stop")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    @objc func aboutDialog(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(self)
    }
    
    @objc func startVM(_ sender: NSMenuItem) {
        runPD()
        runShell("sudo -u "+getUser()+" /usr/local/bin/prlctl start \""+sender.title+"\"")
        runShell("date $(date -j -f %s $((`date +%s`+315360000)) +%m%d%H%M%Y.%S)")
        PDST(cmd: "restart")
        NSWorkspace.shared.launchApplication("Parallels Desktop")
    }
    
    @objc func startAll(_ sender: Any?) {
        let vmlist = runShellAndOutput("sudo -u "+getUser()+" /usr/local/bin/prlctl list -ao name 2>/dev/null").output!.components(separatedBy: "\n")
        runPD()
        for vm in vmlist[1..<vmlist.count] {
            runShell("sudo -u "+getUser()+" /usr/local/bin/prlctl start \""+vm+"\"")
        }
        runShell("date $(date -j -f %s $((`date +%s`+315360000)) +%m%d%H%M%Y.%S)")
        NSWorkspace.shared.launchApplication("Parallels Desktop")
    }
    
    @objc func stopAll(_ sender: Any?) {
        let unstoppedVMs = runShellAndOutput("sudo -u "+getUser()+" /usr/local/bin/prlctl list -ao status,-,name 2>/dev/null|grep -v stopped|sed 's/.*- *//g'").output!.components(separatedBy: "\n")
        runPD()
        for vm in unstoppedVMs[1..<unstoppedVMs.count] {
            runShell("sudo -u "+getUser()+" /usr/local/bin/prlctl resume \""+vm+"\"")
            runShell("sudo -u "+getUser()+" /usr/local/bin/prlctl stop \""+vm+"\"&")
        }
        runShell("date $(date -j -f %s $((`date +%s`+315360000)) +%m%d%H%M%Y.%S)")
    }
    
    @objc func setPDST(_ sender: Any?) {
        var PDSTstatus = UserDefaults.standard.bool(forKey: "PDST")
        if sender == nil{
            PDSTstatus = !UserDefaults.standard.bool(forKey: "PDST")
        }
        if PDSTstatus != true{
            menu.item(withTitle: NSLocalizedString("Kill Purchase UI", comment: "自动关闭购买窗口"))?.state = NSControl.StateValue.on
            UserDefaults.standard.set(true, forKey: "PDST")
            PDST(cmd:"start")
        }else{
            if sender != nil{
                menu.item(withTitle: NSLocalizedString("Kill Purchase UI", comment: "自动关闭购买窗口"))?.state = NSControl.StateValue.off
                UserDefaults.standard.set(false, forKey: "PDST")
                PDST(cmd:"stop")
            }
        }
        UserDefaults.standard.synchronize()
    }
    
    func PDST(cmd:String) {
        if (cmd == "start"){
            runShell("sudo -u "+getUser()+" /usr/bin/osascript \""+scriptPath+"\"&")
        }else if (cmd == "restart"){
            runShell("kill -9 `ps ax -o pid,command|grep PDST.scpt|grep -v grep|awk '{print $1}'`")
            runShell("sudo -u "+getUser()+" /usr/bin/osascript \""+scriptPath+"\"&")
        }else if (cmd == "stop"){
            runShell("kill -9 `ps ax -o pid,command|grep PDST.scpt|grep -v grep|awk '{print $1}'`")
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
            runShell("date $(date -j -f %s $((`date +%s`-315360000)) +%m%d%H%M%Y.%S)")
        }else{
            NSWorkspace.shared.launchApplication("Parallels Desktop")
            runShell("sleep 3;date $(date -j -f %s $((`date +%s`-315360000)) +%m%d%H%M%Y.%S)")
        }
    }
    
    @discardableResult
    func runShell(_ command: String) -> Int32 {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]
        task.launch()
        task.waitUntilExit()
        return task.terminationStatus
    }
    
    @discardableResult
    func runShellAndOutput(_ command: String) -> (status:Int32, output:String?) {
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
    
    func checkUser(){
        let workspace = NSWorkspace.shared
        let appPath = workspace.fullPath(forApplication: "Parallels Desktop")
        if let appPath = appPath {
            let appBundle = Bundle(path: appPath)
            let pdVersion = appBundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
            let comp = pdVersion.compare("17.1.0", options: .numeric)
            if comp == ComparisonResult.orderedDescending||comp == ComparisonResult.orderedSame{
                let user = runShellAndOutput("whoami").output!
                if user != "root"{
                    runShell("/usr/bin/osascript -e 'do shell script \""+CommandLine.arguments[0].replacingOccurrences(of: " ", with: "\\\\ ")+" "+user+" > /dev/null 2>&1 &\" with prompt \""+NSLocalizedString("For Parallels Desktop 17.1.0 or later, PD runner need to run with administrator privileges.", comment: "提权提示")+"\" with administrator privileges'&")
                    exit(1)
                }
            }
        }
    }
    
    func getUser() -> String{
        let user = runShellAndOutput("whoami").output!
        if user == "root"{
            return CommandLine.arguments[1]
        }else{
            return user
        }
    }
    
    func constructMenu() {
        let vmlist = runShellAndOutput("sudo -u "+getUser()+" /usr/local/bin/prlctl list -ao name 2>/dev/null").output!.components(separatedBy: "\n")
        if vmlist[0] == "NAME" {
            for vm in vmlist[1..<vmlist.count] {
                menu.addItem(withTitle: String(vm), action: #selector(AppDelegate.startVM(_:)), keyEquivalent: "")
            }
            if vmlist.count == 1 {
                menu.addItem(withTitle: NSLocalizedString("No VMs", comment: "未找到任何已安装的虚拟机"), action:nil, keyEquivalent: "")
            }else if vmlist.count > 1 {
                menu.addItem(NSMenuItem.separator())
                menu.addItem(withTitle: NSLocalizedString("Kill Purchase UI", comment: "自动关闭购买窗口"), action: #selector(AppDelegate.setPDST(_:)), keyEquivalent: "")
                menu.addItem(withTitle: NSLocalizedString("Stop all VMs", comment: "关闭所有虚拟机"), action: #selector(AppDelegate.stopAll(_:)), keyEquivalent: "")
            }else if vmlist.count > 2 {
                menu.addItem(withTitle: NSLocalizedString("Start all VMs", comment: "启动所有虚拟机"), action: #selector(AppDelegate.startAll(_:)), keyEquivalent: "")
            }
        } else {
            menu.addItem(withTitle: NSLocalizedString("No PD", comment: "未安装PD"), action:nil, keyEquivalent: "")
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: NSLocalizedString("About PD Runner", comment: "关于"), action: #selector(AppDelegate.aboutDialog(_:)), keyEquivalent: "")
        menu.addItem(withTitle: NSLocalizedString("Quit PD Runner", comment: "退出"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem.menu = menu
    }
    
}
