import AppKit

/// A modal AppKit loop does not run the main dispatch queue. Ask to activate
/// after its window is visible, using the current app as activation context.
func modalActivationWorkItem() -> DispatchWorkItem {
    DispatchWorkItem {
        if let source = NSWorkspace.shared.frontmostApplication,
           source.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            NSRunningApplication.current.activate(from: source)
        } else {
            NSRunningApplication.current.activate()
        }
    }
}
