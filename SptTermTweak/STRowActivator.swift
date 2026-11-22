import UIKit

/// Activation helper that robustly triggers navigation on Spotify table/collection view cells.
/// Uses a 3-step cascade:
/// 1. accessibilityActivate() on element and ancestors up to the nearest cell.
/// 2. Delegate didSelectItemAt / didSelectRowAt invocation via nearest UICollectionView/UITableView.
/// 3. UIControl.sendActions(.touchUpInside) on view or ancestor.
@MainActor
final class STRowActivator {

    struct Result {
        let success: Bool
        let message: String
        let method: String?
    }

    /// Activates the given view using the 3-step cascade. Stops at the first step that succeeds.
    static func activate(view: UIView, targetName: String) -> Result {
        STLog.log("SptTerm: STRowActivator starting activation for '\(targetName)'")

        // Step 1: accessibilityActivate() on element, then on ancestors up to nearest cell
        if view.accessibilityActivate() {
            STLog.log("SptTerm: STRowActivator Step 1 accessibilityActivate succeeded on element [\(NSStringFromClass(type(of: view)))]")
            schedulePostNavigationCheck()
            return Result(success: true, message: "ACTIVATED", method: "accessibilityActivate (element)")
        }

        var curr: UIView? = view.superview
        var nearestCell: UIView? = nil

        while let parent = curr {
            let pClass = NSStringFromClass(type(of: parent))
            let isCell = (parent is UICollectionViewCell) || (parent is UITableViewCell) || pClass.contains("Cell")

            if parent.accessibilityActivate() {
                STLog.log("SptTerm: STRowActivator Step 1 accessibilityActivate succeeded on ancestor [\(pClass)]")
                schedulePostNavigationCheck()
                return Result(success: true, message: "ACTIVATED", method: "accessibilityActivate on \(pClass)")
            }

            if isCell {
                nearestCell = parent
                break
            }
            curr = parent.superview
        }

        // Step 2: Nearest UICollectionView / UITableView delegate didSelect call
        let cellToUse = nearestCell ?? view
        var containerCheck: UIView? = cellToUse.superview

        while let container = containerCheck {
            if let cv = container as? UICollectionView, let cell = cellToUse as? UICollectionViewCell {
                if let indexPath = cv.indexPath(for: cell) {
                    let delegate = cv.delegate
                    let responds = delegate?.responds(to: #selector(UICollectionViewDelegate.collectionView(_:didSelectItemAt:))) ?? false
                    STLog.log("SptTerm: STRowActivator Step 2 UICollectionView didSelectItemAt [\(indexPath.section),\(indexPath.item)] responds=\(responds ? 1 : 0)")
                    if responds {
                        delegate?.collectionView?(cv, didSelectItemAt: indexPath)
                        schedulePostNavigationCheck()
                        return Result(success: true, message: "ACTIVATED", method: "UICollectionView didSelectItemAt")
                    }
                }
            }

            if let tv = container as? UITableView, let cell = cellToUse as? UITableViewCell {
                if let indexPath = tv.indexPath(for: cell) {
                    let delegate = tv.delegate
                    let responds = delegate?.responds(to: #selector(UITableViewDelegate.tableView(_:didSelectRowAt:))) ?? false
                    STLog.log("SptTerm: STRowActivator Step 2 UITableView didSelectRowAt [\(indexPath.section),\(indexPath.row)] responds=\(responds ? 1 : 0)")
                    if responds {
                        delegate?.tableView?(tv, didSelectRowAt: indexPath)
                        schedulePostNavigationCheck()
                        return Result(success: true, message: "ACTIVATED", method: "UITableView didSelectRowAt")
                    }
                }
            }

            containerCheck = container.superview
        }

        // Step 3: sendActions(for: .touchUpInside) on nearest UIControl ancestor
        var controlCheck: UIView? = view
        while let c = controlCheck {
            if let ctrl = c as? UIControl {
                let cName = NSStringFromClass(type(of: ctrl))
                STLog.log("SptTerm: STRowActivator Step 3 sendActions(.touchUpInside) on [\(cName)]")
                ctrl.sendActions(for: .touchUpInside)
                schedulePostNavigationCheck()
                return Result(success: true, message: "ACTIVATED", method: "sendActions on \(cName)")
            }
            controlCheck = c.superview
        }

        STLog.log("SptTerm: STRowActivator all steps failed for '\(targetName)'")
        return Result(success: false, message: "ACTIVATION FAILED", method: nil)
    }

    /// Verifies whether the Library view was dismissed/navigated away after 0.8s.
    private static func schedulePostNavigationCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let elements = STSpotifyLibraryScanner.scanOnScreenElements(logSummary: false)
            let libraryRowsOnScreen = elements.contains { elem in
                elem.ancestors.contains { $0.contains("YourLibrary") }
            }
            STLog.log("SptTerm: STRowActivator post-activation check (0.8s): libraryRowsStillOnScreen=\(libraryRowsOnScreen ? 1 : 0)")
        }
    }
}
