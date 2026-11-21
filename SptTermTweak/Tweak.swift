import Orion
import UIKit

struct SptTermTweak: Tweak {
    init() {
        DispatchQueue.main.async {
            STWindowHost.shared.install()
        }
    }
}
