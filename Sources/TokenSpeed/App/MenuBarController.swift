import AppKit
import Observation
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let store: MonitorStore
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    init(store: MonitorStore, showSettings: @escaping () -> Void) {
        self.store = store
        super.init()

        popover.behavior = .transient
        popover.animates = false
        let host = NSHostingController(rootView: MonitorPopover(store: store) { [weak self] in
            self?.popover.performClose(nil)
            showSettings()
        })
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "speedometer", accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePopover)
        }
        observeStatus()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard !popover.isShown, let button = item.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func observeStatus() {
        withObservationTracking {
            updateButton()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeStatus() }
        }
    }

    private func updateButton() {
        guard let button = item.button else { return }
        let model = store.headline
        let isStale = model.map(store.isStale) ?? false
        let reading = model.flatMap { store.reading(for: $0) }
        let badges = store.matchingRules
        let status = reading?.tps?.tpsText
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if isStale { attributes[.foregroundColor] = NSColor.secondaryLabelColor }
        let title = NSMutableAttributedString(string: model == nil ? "" : (status ?? "–"), attributes: attributes)
        if !badges.isEmpty {
            title.append(NSAttributedString(string: " ", attributes: [.font: NSFont.systemFont(ofSize: 4)]))
        }
        for badge in badges {
            title.append(Self.dot(badge.color.appKitColor, font: font))
        }
        button.attributedTitle = title
        var summary = model.map {
            "\($0.title), \(status.map { "\($0) tokens per second" } ?? "TPS unavailable")\(isStale ? ", stale" : "")"
        } ?? "TokenSpeed"
        if !badges.isEmpty {
            summary += ", " + badges.map(\.label).joined(separator: ", ")
        }
        button.toolTip = summary
        button.setAccessibilityLabel(summary)
    }

    /// A small filled circle, vertically centered on the title's digits.
    private static func dot(_ color: NSColor, font: NSFont) -> NSAttributedString {
        let diameter: CGFloat = 7
        let image = NSImage(size: NSSize(width: diameter + 3, height: diameter), flipped: false) { _ in
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 1.5, y: 0, width: diameter, height: diameter)).fill()
            return true
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: (font.capHeight - diameter) / 2, width: image.size.width, height: diameter)
        return NSAttributedString(attachment: attachment)
    }
}

extension BadgeColor {
    var appKitColor: NSColor {
        switch self {
        case .blue: .systemBlue
        case .green: .systemGreen
        case .orange: .systemOrange
        case .red: .systemRed
        case .purple: .systemPurple
        }
    }
}
