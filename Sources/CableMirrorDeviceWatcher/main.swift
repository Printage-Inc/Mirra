import AppKit
import Foundation
import IOKit

final class MobileDeviceWatcher {
    private var notificationPort: IONotificationPortRef?
    private var matchedDevicesIterator: io_iterator_t = 0
    private var lastActivationDate = Date.distantPast

    deinit {
        if matchedDevicesIterator != 0 {
            IOObjectRelease(matchedDevicesIterator)
        }
        if let notificationPort {
            IONotificationPortDestroy(notificationPort)
        }
    }

    func run() -> Never {
        guard let notificationPort = IONotificationPortCreate(kIOMainPortDefault),
              let runLoopSource = IONotificationPortGetRunLoopSource(notificationPort),
              let matchingDictionary = IOServiceMatching("IOUSBHostDevice") else {
            exit(EX_UNAVAILABLE)
        }

        self.notificationPort = notificationPort
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource.takeUnretainedValue(), .defaultMode)

        let status = IOServiceAddMatchingNotification(
            notificationPort,
            kIOFirstMatchNotification,
            matchingDictionary,
            { context, iterator in
                guard let context else { return }
                let watcher = Unmanaged<MobileDeviceWatcher>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                watcher.consumeMatchedDevices(iterator)
            },
            Unmanaged.passUnretained(self).toOpaque(),
            &matchedDevicesIterator
        )

        guard status == KERN_SUCCESS else {
            exit(EX_OSERR)
        }

        // Draining the iterator arms the notification and also handles an
        // iPhone/iPad that was already connected when the agent started.
        consumeMatchedDevices(matchedDevicesIterator)
        CFRunLoopRun()
        exit(EXIT_SUCCESS)
    }

    private func consumeMatchedDevices(_ iterator: io_iterator_t) {
        var shouldActivateMirra = false
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if supportsIPhoneOS(service) {
                shouldActivateMirra = true
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        if shouldActivateMirra {
            activateMirra()
        }
    }

    private func supportsIPhoneOS(_ service: io_service_t) -> Bool {
        guard let property = IORegistryEntryCreateCFProperty(
            service,
            "SupportsIPhoneOS" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return false
        }

        if let value = property as? Bool {
            return value
        }
        if let value = property as? NSNumber {
            return value.boolValue
        }
        return false
    }

    private func activateMirra() {
        guard Date().timeIntervalSince(lastActivationDate) > 5,
              let applicationURL = enclosingApplicationURL() else {
            return
        }
        lastActivationDate = Date()

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration
        )
    }

    private func enclosingApplicationURL() -> URL? {
        var url = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        url.deleteLastPathComponent() // MacOS
        url.deleteLastPathComponent() // Contents
        url.deleteLastPathComponent() // Mirra.app
        return url.pathExtension == "app" ? url : nil
    }
}

MobileDeviceWatcher().run()
