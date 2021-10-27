import Foundation

@objc(AppProtocol)
protocol AppProtocol {
    func log(_ log: String)
}

@objc(HelperProtocol)
protocol HelperProtocol {
    func getVersion(completion: @escaping (String) -> Void)
    func runTask(arguments: String, completion: @escaping (NSNumber) -> Void)
    func runTaskAuth(withArgs args: String, authData: NSData?, completion: @escaping (NSNumber) -> Void)
}
