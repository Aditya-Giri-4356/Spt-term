import Foundation
import Combine

protocol STAuthServiceProtocol: AnyObject {
    var isAuthorized: Bool { get }
    var authorizedPublisher: AnyPublisher<Bool, Never> { get }
    func authorize() async throws
    func signOut()
    func handle(url: URL) -> Bool
}
