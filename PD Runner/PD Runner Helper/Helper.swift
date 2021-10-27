import Foundation

class Helper: NSObject, NSXPCListenerDelegate, HelperProtocol {

    // MARK: -
    // MARK: Private Constant Variables

    private let listener: NSXPCListener

    // MARK: -
    // MARK: Private Variables

    private var connections = [NSXPCConnection]()
//    private var shouldQuit = false
    private var shouldQuitCheckInterval = 1.0

    // MARK: -
    // MARK: Initialization

    override init() {
        self.listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
        super.init()
        self.listener.delegate = self
    }

    public func run() {
        self.listener.resume()

        // Keep the helper tool running until the variable shouldQuit is set to true.
        // The variable should be changed in the "listener(_ listener:shoudlAcceptNewConnection:)" function.

//        while !self.shouldQuit {
//            RunLoop.current.run(until: Date(timeIntervalSinceNow: self.shouldQuitCheckInterval))
//        }
        RunLoop.current.run()
    }

    // MARK: -
    // MARK: NSXPCListenerDelegate Methods

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {

        // Verify that the calling application is signed using the same code signing certificate as the helper
        guard self.isValid(connection: connection) else {
            return false
        }

        // Set the protocol that the calling application conforms to.
        connection.remoteObjectInterface = NSXPCInterface(with: AppProtocol.self)

        // Set the protocol that the helper conforms to.
        connection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.exportedObject = self

        // Set the invalidation handler to remove this connection when it's work is completed.
        connection.invalidationHandler = {
            if let connectionIndex = self.connections.firstIndex(of: connection) {
                self.connections.remove(at: connectionIndex)
            }

            if self.connections.isEmpty {
                exit(0)
//                self.shouldQuit = true
            }
        }

        self.connections.append(connection)
        connection.resume()

        return true
    }

    // MARK: -
    // MARK: HelperProtocol Methods

    func getVersion(completion: (String) -> Void) {
        completion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")
    }

    func runTaskAuth(withArgs args: String, authData: NSData?, completion: @escaping (NSNumber) -> Void) {

        // Check the passed authorization, if the user need to authenticate to use this command the user might be prompted depending on the settings and/or cached authentication.

        guard self.verifyAuthorization(authData, forCommand: #selector(HelperProtocol.runTaskAuth(withArgs:authData:completion:))) else {
            completion(kAuthorizationFailedExitCode)
            return
        }

        self.runTask(arguments: args, completion: completion)
    }

    // MARK: -
    // MARK: Private Helper Methods

    private func isValid(connection: NSXPCConnection) -> Bool {
        do {
            return try CodesignCheck.codeSigningMatches(pid: connection.processIdentifier)
        } catch {
            NSLog("Code signing check failed with error: \(error)")
            return false
        }
    }

    private func verifyAuthorization(_ authData: NSData?, forCommand command: Selector) -> Bool {
        do {
            try HelperAuthorization.verifyAuthorization(authData, forCommand: command)
        } catch {
            if let remoteObject = self.connection()?.remoteObjectProxy as? AppProtocol {
                remoteObject.log("Authentication Error: \(error)")
            }
            return false
        }
        return true
    }

    private func connection() -> NSXPCConnection? {
        return self.connections.last
    }

    func runTask(arguments: String, completion:@escaping ((NSNumber) -> Void)) -> Void {
        let task = Process()
        let stdOut = Pipe()
        let stdOutHandler =  { (file: FileHandle!) -> Void in
            let data = file.availableData
            guard let output = NSString(data: data, encoding: String.Encoding.utf8.rawValue) else { return }
            if let remoteObject = self.connection()?.remoteObjectProxy as? AppProtocol {
                remoteObject.log(output as String)
            }
        }
        stdOut.fileHandleForReading.readabilityHandler = stdOutHandler

        let stdErr:Pipe = Pipe()
        let stdErrHandler =  { (file: FileHandle!) -> Void in
            let data = file.availableData
            guard let output = NSString(data: data, encoding: String.Encoding.utf8.rawValue) else { return }
            if let remoteObject = self.connection()?.remoteObjectProxy as? AppProtocol {
                remoteObject.log(output as String)
            }
        }
        stdErr.fileHandleForReading.readabilityHandler = stdErrHandler

        task.launchPath = "/bin/bash"
        task.arguments = ["-c", arguments]
        task.standardOutput = stdOut
        task.standardError = stdErr

        task.terminationHandler = { task in
            completion(NSNumber(value: task.terminationStatus))
        }

        task.launch()
    }
}
