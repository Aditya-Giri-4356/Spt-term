import Foundation
import Combine

final class MockAuthService: STAuthServiceProtocol, ObservableObject {
    @Published var isAuthorized: Bool

    var authorizedPublisher: AnyPublisher<Bool, Never> {
        $isAuthorized.eraseToAnyPublisher()
    }

    init(isAuthorized: Bool = true) {
        self.isAuthorized = isAuthorized
    }

    func authorize() async throws {
        isAuthorized = true
    }

    func signOut() {
        isAuthorized = false
    }

    func handle(url: URL) -> Bool {
        return true
    }
}
