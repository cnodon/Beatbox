import AppKit

enum AudioExportPanel {
    static func request(
        recordingTitle: String,
        initialFormat: AudioExportFormat = .m4aAAC
    ) -> AudioExportRequest? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = false
        panel.message = "选择音频格式和保存位置"
        panel.prompt = "导出"

        let safeTitle = safeFileName(recordingTitle)
        let accessoryController = AudioExportAccessoryController(initialFormat: initialFormat)
        panel.accessoryView = accessoryController.view
        accessoryController.attach(to: panel, baseName: safeTitle)

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return nil }
        let format = accessoryController.selectedFormat
        let destinationURL = selectedURL
            .deletingPathExtension()
            .appendingPathExtension(format.fileExtension)
        return AudioExportRequest(destinationURL: destinationURL, format: format)
    }

    private static func safeFileName(_ title: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:")
        let sanitized = title
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Beatbox Recording" : sanitized
    }
}

private final class AudioExportAccessoryController: NSViewController {
    private let formatPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private weak var panel: NSSavePanel?
    private var baseName = "Beatbox Recording"

    private(set) var selectedFormat: AudioExportFormat

    init(initialFormat: AudioExportFormat) {
        selectedFormat = initialFormat
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let formatLabel = NSTextField(labelWithString: "文件格式：")
        formatLabel.setContentHuggingPriority(.required, for: .horizontal)

        formatPicker.addItems(withTitles: AudioExportFormat.allCases.map(\.title))
        if let selectedIndex = AudioExportFormat.allCases.firstIndex(of: selectedFormat) {
            formatPicker.selectItem(at: selectedIndex)
        }
        formatPicker.target = self
        formatPicker.action = #selector(formatDidChange)
        formatPicker.setAccessibilityLabel("导出文件格式")

        let pickerRow = NSStackView(views: [formatLabel, formatPicker])
        pickerRow.orientation = .horizontal
        pickerRow.alignment = .centerY
        pickerRow.spacing = 8

        detailLabel.textColor = .secondaryLabelColor
        detailLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detailLabel.maximumNumberOfLines = 2
        detailLabel.preferredMaxLayoutWidth = 360

        let stack = NSStackView(views: [pickerRow, detailLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 4, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 380),
        ])
        view = container
        updateDetail()
    }

    func attach(to panel: NSSavePanel, baseName: String) {
        self.panel = panel
        self.baseName = baseName
        updatePanel()
    }

    @objc private func formatDidChange() {
        let index = formatPicker.indexOfSelectedItem
        guard AudioExportFormat.allCases.indices.contains(index) else { return }
        selectedFormat = AudioExportFormat.allCases[index]
        updateDetail()
        updatePanel()
    }

    private func updateDetail() {
        detailLabel.stringValue = selectedFormat.detail
        detailLabel.setAccessibilityLabel(selectedFormat.detail)
    }

    private func updatePanel() {
        guard let panel else { return }
        let currentName = panel.nameFieldStringValue
        let currentBaseName = currentName.isEmpty
            ? baseName
            : (currentName as NSString).deletingPathExtension
        panel.allowedContentTypes = [selectedFormat.contentType]
        panel.nameFieldStringValue = "\(currentBaseName).\(selectedFormat.fileExtension)"
    }
}
