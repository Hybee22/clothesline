import AppKit

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--cmd"), i + 1 < args.count {
    // Send a command to the running Clothesline and exit.
    DistributedNotificationCenter.default().postNotificationName(commandNotification, object: args[i + 1], deliverImmediately: true)
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
