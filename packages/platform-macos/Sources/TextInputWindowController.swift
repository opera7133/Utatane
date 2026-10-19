import AppKit
import SwiftUI
import UtataneBalloon
import UtataneCore
import UtataneSakuraScript

@MainActor
public final class TextInputWindowController: NSObject, NSWindowDelegate {
    public enum InputKind: Sendable, Equatable {
        case text
        case password
        case textArea
        case date
        case slider(minimum: Int, maximum: Int)
        case time
        case ipAddress

        public init(_ kind: SakuraScriptInputCommand.Kind) {
            switch kind {
            case .text: self = .text
            case .textArea: self = .textArea
            case .password: self = .password
            case .date: self = .date
            case let .slider(minimum, maximum): self = .slider(minimum: minimum, maximum: maximum)
            case .time: self = .time
            case .ipAddress: self = .ipAddress
            }
        }
    }

    public enum InputResult: Sendable, Equatable {
        case submitted(String)
        case cancelled(timedOut: Bool, value: String = "")
    }

    public struct Appearance: Sendable, Equatable {
        public let fontName: String?
        public let fontHeight: Int
        public let placeholderColor: BalloonColor?
        public let fontColor: BalloonColor
        public let backgroundColor: BalloonColor?
        public let inputX: Int
        public let inputY: Int
        public let inputWidth: Int?
        public let inputHeight: Int?
        public let usesSelfAlpha: Bool
        public let usesFullSelfAlpha: Bool
        public let backgroundImageURL: URL?
        public let confirmButtonUpImageURL: URL?
        public let confirmButtonDownImageURL: URL?
        public let cancelButtonUpImageURL: URL?
        public let cancelButtonDownImageURL: URL?

        public init(balloon: BalloonDefinition, backgroundImageURL: URL?, usesBalloonTextArea: Bool = false) {
            fontName = usesBalloonTextArea ? balloon.fontName : balloon.communicateBoxFontName
            fontHeight = usesBalloonTextArea ? balloon.fontHeight : balloon.communicateBoxFontHeight
            fontColor = usesBalloonTextArea ? balloon.fontColor : balloon.communicateBoxFontColor
            placeholderColor = balloon.communicateBoxPlaceholderColor
            backgroundColor = balloon.communicateBoxBackgroundColor
            let imageSize = backgroundImageURL.flatMap { NSImage(contentsOf: $0)?.size }
            inputX = usesBalloonTextArea ? balloon.validRectLeft : balloon.communicateBoxX
            inputY = usesBalloonTextArea ? balloon.validRectTop : balloon.communicateBoxY
            inputWidth = usesBalloonTextArea
                ? imageSize.map { max(1, (balloon.validRectRight ?? Int($0.width) - 14) - balloon.validRectLeft) }
                : balloon.communicateBoxWidth
            inputHeight = usesBalloonTextArea
                ? imageSize.map { max(1, (balloon.validRectBottom ?? Int($0.height) - 14) - balloon.validRectTop) }
                : balloon.communicateBoxHeight
            usesSelfAlpha = balloon.usesSelfAlpha
            usesFullSelfAlpha = balloon.usesFullSelfAlpha
            self.backgroundImageURL = backgroundImageURL
            confirmButtonUpImageURL = Self.imageURL(named: "ok_up.png", in: balloon.directory)
            confirmButtonDownImageURL = Self.imageURL(named: "ok_down.png", in: balloon.directory)
            cancelButtonUpImageURL = Self.imageURL(named: "cancel_up.png", in: balloon.directory)
            cancelButtonDownImageURL = Self.imageURL(named: "cancel_down.png", in: balloon.directory)
        }

        public static func textArea(
            balloon: BalloonDefinition, balloonID: Int?, scope: Int, surfaceID: Int?
        ) -> Self {
            let loader = BalloonLoader()
            let id = balloonID ?? BalloonInputStyle.textArea.rawValue
            if let image = loader.inputImageURL(id: id, in: balloon) {
                return .init(balloon: loader.effectiveInputDefinition(for: balloon, id: id), backgroundImageURL: image)
            }
            let style = max(0, surfaceID ?? 0)
            let speaker: BalloonSpeaker = scope == 0 ? .sakura : (scope == 1 ? .kero : .character(scope: scope))
            return .init(
                balloon: loader.effectiveDefinition(for: balloon, speaker: speaker, style: style),
                backgroundImageURL: try? loader.imageURL(speaker: speaker, style: style, in: balloon),
                usesBalloonTextArea: true
            )
        }

        private static func imageURL(named name: String, in directory: URL) -> URL? {
            let direct = directory.appending(path: name, directoryHint: .notDirectory)
            if FileManager.default.fileExists(atPath: direct.path) {
                return direct
            }
            return try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).first { $0.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame }
        }
    }

    public struct Request: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let prompt: String?
        public let initialValue: String
        public let inputKind: InputKind
        public let maximumLength: Int?
        public let autocompleteValues: [String]
        public let placeholder: String?
        public let actionTitle: String
        public let allowsCancel: Bool
        public let appearance: Appearance?
        public let keepsOpenAfterCommit: Bool
        public let clearsValueAfterCommit: Bool
        public let onCommit: @MainActor @Sendable (String) -> Void
        public let onCancel: (@MainActor @Sendable () -> Void)?

        public init(
            id: String = UUID().uuidString,
            title: String,
            prompt: String? = nil,
            initialValue: String = "",
            inputKind: InputKind = .text,
            maximumLength: Int? = nil,
            autocompleteValues: [String] = [],
            placeholder: String? = nil,
            actionTitle: String = String(localized: "OK"),
            allowsCancel: Bool = true,
            appearance: Appearance? = nil,
            keepsOpenAfterCommit: Bool = false,
            clearsValueAfterCommit: Bool = false,
            onCommit: @escaping @MainActor @Sendable (String) -> Void,
            onCancel: (@MainActor @Sendable () -> Void)? = nil
        ) {
            self.id = id
            self.title = title
            self.prompt = prompt
            self.initialValue = initialValue
            self.inputKind = inputKind
            self.maximumLength = maximumLength
            self.autocompleteValues = autocompleteValues
            self.placeholder = placeholder
            self.actionTitle = actionTitle
            self.allowsCancel = allowsCancel
            self.appearance = appearance
            self.keepsOpenAfterCommit = keepsOpenAfterCommit
            self.clearsValueAfterCommit = clearsValueAfterCommit
            self.onCommit = onCommit
            self.onCancel = onCancel
        }
    }

    public private(set) var currentValue = ""
    private(set) var window: NSWindow?
    private var currentRequest: Request?
    private var timeoutTask: Task<Void, Never>?
    private var timeoutHandler: (@MainActor () -> Void)?

    override public init() {
        super.init()
    }

    public func show(_ request: Request) {
        closeCurrentWindow(invokeCancel: true)
        currentRequest = request
        currentValue = Self.editableValue(request.initialValue, kind: request.inputKind, maximumLength: request.maximumLength)

        let backgroundImage = request.prompt?.isEmpty == false ? nil : request.appearance.flatMap { appearance in
            appearance.backgroundImageURL.flatMap { try? Self.loadSkinImage($0, appearance: appearance) }
        }
        let view = TextInputDialogView(
            request: request,
            backgroundImage: backgroundImage,
            onTextChange: { [weak self] text in self?.updateCurrentText(text) },
            onCommit: { [weak self] text in
                self?.submitCurrent(text)
            },
            onCancel: { [weak self] in
                guard let self else { return }
                let req = currentRequest
                closeCurrentWindow(invokeCancel: false)
                req?.onCancel?()
            }
        )

        let backgroundImageSize = backgroundImage?.size
        let panelSize = Self.panelSize(for: request.appearance, backgroundImageSize: backgroundImageSize, hasPrompt: request.prompt?.isEmpty == false, allowsCancel: request.allowsCancel, isTextArea: request.inputKind == .textArea)
        let panel = InputPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.title = request.title
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.contentViewController = NSHostingController(rootView: view.frame(width: panelSize.width, height: panelSize.height))
        panel.setContentSize(panelSize)
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window = panel
    }

    func updateCurrentText(_ text: String) {
        guard let request = currentRequest else { return }
        currentValue = Self.editableValue(text, kind: request.inputKind, maximumLength: request.maximumLength)
    }

    func submitCurrent(_ text: String) {
        updateCurrentText(text)
        let value = currentValue
        let request = currentRequest
        if request?.keepsOpenAfterCommit == true {
            timeoutTask?.cancel()
            timeoutTask = nil
            timeoutHandler = nil
        } else {
            closeCurrentWindow(invokeCancel: false)
        }
        if request?.keepsOpenAfterCommit == true, request?.clearsValueAfterCommit == true {
            currentValue = ""
        }
        request?.onCommit(value)
    }

    public func showPrompt(
        id: String = UUID().uuidString,
        title: String,
        prompt: String? = nil,
        initialValue: String = "",
        autocompleteValues: [String] = [],
        placeholder: String? = nil,
        actionTitle: String = String(localized: "OK"),
        allowsCancel: Bool = true,
        appearance: Appearance? = nil,
        timeoutMilliseconds: Int? = nil
    ) async -> String? {
        await withCheckedContinuation { continuation in
            show(Request(
                id: id,
                title: title,
                prompt: prompt,
                initialValue: initialValue,
                autocompleteValues: autocompleteValues,
                placeholder: placeholder,
                actionTitle: actionTitle,
                allowsCancel: allowsCancel,
                appearance: appearance,
                onCommit: { text in
                    continuation.resume(returning: text)
                },
                onCancel: {
                    continuation.resume(returning: nil)
                }
            ))
            if let timeoutMilliseconds, timeoutMilliseconds > 0 {
                timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(timeoutMilliseconds))
                    guard !Task.isCancelled else { return }
                    self?.closeCurrentWindow(invokeCancel: true)
                }
            }
        }
    }

    public func showInput(
        id: String,
        title: String,
        initialValue: String,
        inputKind: InputKind,
        maximumLength: Int?,
        autocompleteValues: [String],
        placeholder: String? = nil,
        appearance: Appearance?,
        timeoutMilliseconds: Int?
    ) async -> InputResult {
        await withCheckedContinuation { continuation in
            show(Request(
                id: id,
                title: title,
                initialValue: initialValue,
                inputKind: inputKind,
                maximumLength: maximumLength,
                autocompleteValues: autocompleteValues,
                placeholder: placeholder,
                appearance: appearance,
                onCommit: { value in continuation.resume(returning: .submitted(value)) },
                onCancel: {
                    continuation.resume(returning: .cancelled(timedOut: false, value: inputKind == .textArea ? self.currentValue : ""))
                }
            ))
            if let timeoutMilliseconds, timeoutMilliseconds > 0 {
                timeoutHandler = {
                    continuation.resume(returning: .cancelled(timedOut: true, value: inputKind == .textArea ? self.currentValue : ""))
                }
                timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(timeoutMilliseconds))
                    guard !Task.isCancelled, let self else { return }
                    let handler = timeoutHandler
                    closeCurrentWindow(invokeCancel: false)
                    handler?()
                }
            }
        }
    }

    public func showPersistentInput(
        id: String,
        title: String,
        initialValue: String,
        maximumLength: Int?,
        autocompleteValues: [String],
        appearance: Appearance?,
        timeoutMilliseconds: Int?,
        clearsValueAfterSubmit: Bool,
        inputKind: InputKind = .text,
        placeholder: String? = nil,
        onSubmit: @escaping @MainActor @Sendable (String) -> Void,
        onCancel: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        show(Request(
            id: id,
            title: title,
            initialValue: initialValue,
            inputKind: inputKind,
            maximumLength: maximumLength,
            autocompleteValues: autocompleteValues,
            placeholder: placeholder,
            appearance: appearance,
            keepsOpenAfterCommit: true,
            clearsValueAfterCommit: clearsValueAfterSubmit,
            onCommit: onSubmit,
            onCancel: { onCancel(false) }
        ))
        if let timeoutMilliseconds, timeoutMilliseconds > 0 {
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(timeoutMilliseconds))
                guard !Task.isCancelled, let self else { return }
                closeCurrentWindow(invokeCancel: false)
                onCancel(true)
            }
        }
    }

    public func showTextArea(
        command: SakuraScriptInputCommand,
        appearance: Appearance?,
        sendEvent: @escaping @MainActor @Sendable (GhostEvent) async -> SakuraScript?,
        playResponse: @escaping @MainActor @Sendable (SakuraScript) -> Void
    ) async -> SakuraScript? {
        if command.keepsOpenAfterSubmit {
            showPersistentInput(
                id: command.id, title: String(localized: "文字を入力"), initialValue: command.initialValue,
                maximumLength: command.maximumLength, autocompleteValues: [], appearance: appearance,
                timeoutMilliseconds: command.timeoutMilliseconds, clearsValueAfterSubmit: !command.keepsValueAfterSubmit,
                inputKind: .textArea, placeholder: command.placeholder,
                onSubmit: { value in
                    Task {
                        if let response = await sendEvent(SHIORIEventFactory.textAreaInput(id: command.id, value: value, additionalReferences: command.references)) {
                            playResponse(response)
                        }
                    }
                },
                onCancel: { [weak self] timedOut in
                    let value = self?.currentValue ?? ""
                    Task {
                        if let response = await sendEvent(SHIORIEventFactory.textAreaInputCancel(id: command.id, timedOut: timedOut, value: value, additionalReferences: command.references)) {
                            playResponse(response)
                        }
                    }
                }
            )
            return nil
        }
        let result = await showInput(
            id: command.id, title: String(localized: "文字を入力"), initialValue: command.initialValue,
            inputKind: .textArea, maximumLength: command.maximumLength, autocompleteValues: [],
            placeholder: command.placeholder, appearance: appearance, timeoutMilliseconds: command.timeoutMilliseconds
        )
        guard !Task.isCancelled else { return nil }
        switch result {
        case let .submitted(value):
            return await sendEvent(SHIORIEventFactory.textAreaInput(id: command.id, value: value, additionalReferences: command.references))
        case let .cancelled(timedOut, value):
            return await sendEvent(SHIORIEventFactory.textAreaInputCancel(id: command.id, timedOut: timedOut, value: value, additionalReferences: command.references))
        }
    }

    public static func autocompleteValues(from value: String?) -> [String] {
        guard let value else { return [] }
        var seen = Set<String>()
        return value
            .split(separator: "\u{1}", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func loadSkinImage(_ url: URL, appearance: Appearance) throws -> NSImage {
        let mask = url.deletingPathExtension().appendingPathExtension("pna")
        return try SurfaceImageLoader().load(
            SurfaceAsset(id: -1, imageURL: url, alphaMaskURL: FileManager.default.fileExists(atPath: mask.path) ? mask : nil),
            usesSelfAlpha: appearance.usesSelfAlpha, usesFullSelfAlpha: appearance.usesFullSelfAlpha
        )
    }

    static func panelSize(for appearance: Appearance?, backgroundImageSize: NSSize?, hasPrompt: Bool = false, allowsCancel: Bool = true, isTextArea: Bool = false) -> NSSize {
        if let backgroundImageSize, !hasPrompt {
            return backgroundImageSize
        }
        let inputWidth = CGFloat(max(appearance?.inputWidth ?? 280, 120))
        let inputHeight = CGFloat(max(appearance?.inputHeight ?? (isTextArea ? 160 : 24), 24))
        let buttonsWidth: CGFloat = allowsCancel ? 78 : 44
        let contentWidth = CGFloat(max(appearance?.inputX ?? 10, 8)) + inputWidth + buttonsWidth + 22
        let contentHeight = CGFloat(max(appearance?.inputY ?? 24, 24)) + inputHeight + 10 + (hasPrompt ? 46 : 0) + (isTextArea ? 32 : 0)
        return NSSize(
            width: max(380, contentWidth, backgroundImageSize?.width ?? 0),
            height: max(58, contentHeight, backgroundImageSize?.height ?? 0)
        )
    }

    static func editableValue(_ value: String, kind: InputKind, maximumLength: Int?) -> String {
        let normalized = kind == .textArea
            ? value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\u{1}", with: "\n")
            : value
        guard let maximumLength, maximumLength >= 0 else { return normalized }
        return String(normalized.prefix(maximumLength))
    }

    public func close(id: String? = nil) {
        if let id {
            if currentRequest?.id == id || id == "__SYSTEM_ALL_INPUT__" {
                closeCurrentWindow(invokeCancel: true)
            }
        } else {
            closeCurrentWindow(invokeCancel: true)
        }
    }

    private func closeCurrentWindow(invokeCancel: Bool) {
        timeoutTask?.cancel()
        timeoutTask = nil
        timeoutHandler = nil
        let request = currentRequest
        currentRequest = nil
        if let window {
            self.window = nil
            window.delegate = nil
            window.close()
        }
        if invokeCancel {
            request?.onCancel?()
        }
    }

    public func windowWillClose(_: Notification) {
        if let request = currentRequest {
            timeoutTask?.cancel()
            timeoutTask = nil
            timeoutHandler = nil
            currentRequest = nil
            window = nil
            request.onCancel?()
        }
    }
}

private final class InputPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }
}

private struct TextInputDialogView: View {
    let request: TextInputWindowController.Request
    let backgroundImage: NSImage?
    let onTextChange: (String) -> Void
    let onCommit: (String) -> Void
    let onCancel: () -> Void
    @State private var text: String
    @State private var dateValue: Date
    @State private var sliderValue: Double
    @FocusState private var isFocused: Bool

    init(
        request: TextInputWindowController.Request,
        backgroundImage: NSImage?,
        onTextChange: @escaping (String) -> Void,
        onCommit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.request = request
        self.backgroundImage = backgroundImage
        self.onTextChange = onTextChange
        self.onCommit = onCommit
        self.onCancel = onCancel
        _text = State(initialValue: TextInputWindowController.editableValue(request.initialValue, kind: request.inputKind, maximumLength: request.maximumLength))
        _dateValue = State(initialValue: Self.initialDate(for: request))
        _sliderValue = State(initialValue: Double(request.initialValue) ?? 0)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            inputBackground
            // Skins can include their own title in the background image.
            if backgroundImage == nil {
                Text(request.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(inputForegroundColor)
                    .lineLimit(1)
                    .padding(.leading, inputOriginX)
                    .padding(.trailing, 10)
                    .padding(.top, 5)
            }
            VStack(alignment: .leading, spacing: 8) {
                if let prompt = request.prompt, !prompt.isEmpty {
                    Text(prompt)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                inputLayout {
                    Group {
                        switch request.inputKind {
                        case .textArea:
                            MultilineInputField(
                                text: $text,
                                placeholder: request.placeholder?.replacingOccurrences(of: "\u{1}", with: "\n") ?? "",
                                font: inputNSFont,
                                textColor: request.appearance.map { nsColor($0.fontColor) } ?? .textColor,
                                placeholderColor: placeholderNSColor,
                                maximumLength: request.maximumLength,
                                onChange: onTextChange,
                                onCommit: submit
                            )
                        case .password:
                            SecureField("", text: $text, prompt: Text(request.placeholder ?? "").foregroundColor(Color(placeholderNSColor)))
                                .textFieldStyle(.roundedBorder)
                                .focused($isFocused)
                                .onSubmit { submit() }
                        case .date:
                            DatePicker("", selection: $dateValue, displayedComponents: .date)
                                .labelsHidden()
                        case .time:
                            DatePicker("", selection: $dateValue, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        case let .slider(minimum, maximum):
                            HStack {
                                Slider(
                                    value: $sliderValue,
                                    in: Double(minimum) ... Double(max(maximum, minimum + 1)),
                                    step: 1
                                )
                                Text(String(Int(sliderValue.rounded())))
                                    .monospacedDigit()
                                    .frame(minWidth: 64, alignment: .trailing)
                            }
                        case .text where request.autocompleteValues.isEmpty,
                             .ipAddress where request.autocompleteValues.isEmpty:
                            TextField(
                                request.placeholder ?? "",
                                text: $text,
                                prompt: Text(request.placeholder ?? "").foregroundColor(Color(placeholderNSColor))
                            )
                            .textFieldStyle(.roundedBorder)
                            .focused($isFocused)
                            .onSubmit {
                                submit()
                            }
                        default:
                            AutocompleteTextField(
                                text: $text,
                                placeholder: request.placeholder ?? "",
                                placeholderColor: placeholderNSColor,
                                values: request.autocompleteValues,
                                fontName: request.appearance?.fontName,
                                fontHeight: CGFloat(max(request.appearance?.fontHeight ?? 13, 1)),
                                fontColor: request.appearance.map { nsColor($0.fontColor) } ?? .textColor,
                                backgroundColor: request.appearance?.backgroundColor.map(nsColor),
                                onCommit: { _ in onCommit(submittedValue) }
                            )
                        }
                    }
                    .font(inputFont)
                    .foregroundStyle(inputForegroundColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: inputHeight)
                    .background(inputBackgroundColor, in: RoundedRectangle(cornerRadius: 5))
                    HStack(spacing: 6) {
                        dialogButton(
                            title: request.actionTitle,
                            upURL: request.appearance?.confirmButtonUpImageURL,
                            downURL: request.appearance?.confirmButtonDownImageURL,
                            action: submit
                        )
                        .keyboardShortcut(.return, modifiers: request.inputKind == .textArea ? .control : [])
                        if request.allowsCancel {
                            dialogButton(
                                title: String(localized: "キャンセル"),
                                upURL: request.appearance?.cancelButtonUpImageURL,
                                downURL: request.appearance?.cancelButtonDownImageURL,
                                isCancel: true,
                                action: onCancel
                            )
                            .keyboardShortcut(.cancelAction)
                        }
                    }
                }
                .frame(width: request.inputKind == .textArea ? request.appearance?.inputWidth.map(CGFloat.init) : nil)
            }
            .padding(.leading, inputOriginX)
            .padding(.top, inputOriginY)
            .padding(.trailing, 10)
            .padding(.bottom, backgroundImage == nil ? 10 : 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: backgroundImage == nil ? 10 : 0))
        .onAppear {
            isFocused = true
        }
        .onChange(of: text) { _, value in
            if let limit = request.maximumLength, limit >= 0, value.count > limit {
                text = String(value.prefix(limit))
            }
            onTextChange(TextInputWindowController.editableValue(value, kind: request.inputKind, maximumLength: request.maximumLength))
            if request.inputKind == .ipAddress {
                let filtered = value.filter { $0.isNumber || $0 == "." || $0 == "," }
                if filtered != value {
                    text = filtered
                }
            }
        }
    }

    private var inputLayout: AnyLayout {
        request.inputKind == .textArea ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
    }

    private func submit() {
        onCommit(submittedValue)
        if request.keepsOpenAfterCommit, request.clearsValueAfterCommit {
            text = ""
        }
    }

    @ViewBuilder
    private func dialogButton(
        title: String,
        upURL: URL?,
        downURL: URL?,
        isCancel: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        if let appearance = request.appearance, let upURL,
           let upImage = try? TextInputWindowController.loadSkinImage(upURL, appearance: appearance)
        {
            let downImage = downURL.flatMap { try? TextInputWindowController.loadSkinImage($0, appearance: appearance) } ?? upImage
            Button(title, action: action)
                .buttonStyle(BalloonImageButtonStyle(upImage: upImage, downImage: downImage))
                .accessibilityLabel(title)
        } else {
            Button(action: action) {
                if isCancel {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: buttonHeight)
                } else {
                    Text(title).font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 8).frame(minWidth: 28, minHeight: buttonHeight)
                }
            }
            .buttonStyle(.plain)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(inputForegroundColor.opacity(0.35)))
            .accessibilityLabel(title)
            .help(title)
        }
    }

    private var submittedValue: String {
        let calendar = Calendar(identifier: .gregorian)
        switch request.inputKind {
        case .date:
            let parts = calendar.dateComponents([.year, .month, .day], from: dateValue)
            return "\(parts.year ?? 0),\(parts.month ?? 0),\(parts.day ?? 0)"
        case .time:
            let parts = calendar.dateComponents([.hour, .minute, .second], from: dateValue)
            return "\(parts.hour ?? 0),\(parts.minute ?? 0),\(parts.second ?? 0)"
        case .slider:
            return String(Int(sliderValue.rounded()))
        case .ipAddress:
            return text.replacingOccurrences(of: ".", with: ",")
        case .text, .password, .textArea:
            return text
        }
    }

    private static func initialDate(for request: TextInputWindowController.Request) -> Date {
        let values = request.initialValue.split(separator: ",").compactMap { Int($0) }
        var components = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date()
        )
        switch request.inputKind {
        case .date where values.count >= 3:
            components.year = values[0]
            components.month = values[1]
            components.day = values[2]
        case .time where values.count >= 2:
            components.hour = values[0]
            components.minute = values[1]
            components.second = values.count >= 3 ? values[2] : 0
        default:
            break
        }
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }

    @ViewBuilder
    private var inputBackground: some View {
        if let image = backgroundImage {
            Image(nsImage: image)
                .interpolation(.none)
                .frame(width: image.size.width, height: image.size.height)
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.25)))
        }
    }

    private var inputOriginX: CGFloat {
        CGFloat(max(request.appearance?.inputX ?? 10, 8))
    }

    private var inputOriginY: CGFloat {
        CGFloat(max(request.appearance?.inputY ?? 24, backgroundImage == nil ? 24 : 0))
    }

    private var buttonHeight: CGFloat {
        min(24, backgroundImage.map { max(16, $0.size.height - inputOriginY - 4) } ?? 24)
    }

    private var inputHeight: CGFloat {
        let isTextArea = request.inputKind == .textArea
        let requested = CGFloat(max(request.appearance?.inputHeight ?? (isTextArea ? 160 : 24), 20))
        let available = backgroundImage.map { max(16, $0.size.height - inputOriginY - (isTextArea ? 36 : 4)) } ?? requested
        return min(requested, available)
    }

    private var inputNSFont: NSFont {
        let height = CGFloat(max(request.appearance?.fontHeight ?? 13, 1))
        return request.appearance?.fontName?.split(separator: ",").lazy.compactMap {
            NSFont(name: $0.trimmingCharacters(in: .whitespacesAndNewlines), size: height)
        }.first ?? .systemFont(ofSize: height)
    }

    private var placeholderNSColor: NSColor {
        request.appearance?.placeholderColor.map(nsColor) ?? .placeholderTextColor
    }

    private var inputFont: Font {
        let height = CGFloat(max(request.appearance?.fontHeight ?? 13, 1))
        guard let name = request.appearance?.fontName?.split(separator: ",").first else {
            return .system(size: height)
        }
        return .custom(name.trimmingCharacters(in: .whitespacesAndNewlines), size: height)
    }

    private var inputForegroundColor: Color {
        request.appearance.map { color($0.fontColor) } ?? .primary
    }

    private var inputBackgroundColor: Color {
        guard let backgroundColor = request.appearance?.backgroundColor else {
            return Color(NSColor.textBackgroundColor)
        }
        return color(backgroundColor)
    }

    private func color(_ value: BalloonColor) -> Color {
        Color(
            red: Double(value.red) / 255,
            green: Double(value.green) / 255,
            blue: Double(value.blue) / 255
        )
    }

    private func nsColor(_ value: BalloonColor) -> NSColor {
        NSColor(
            red: CGFloat(value.red) / 255,
            green: CGFloat(value.green) / 255,
            blue: CGFloat(value.blue) / 255,
            alpha: 1
        )
    }
}

private struct BalloonImageButtonStyle: ButtonStyle {
    let upImage: NSImage
    let downImage: NSImage

    func makeBody(configuration: Configuration) -> some View {
        let image = configuration.isPressed ? downImage : upImage
        Image(nsImage: image)
            .resizable()
            .frame(width: max(image.size.width, 1), height: max(image.size.height, 1))
            .contentShape(Rectangle())
    }
}

private struct AutocompleteTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let placeholderColor: NSColor
    let values: [String]
    let fontName: String?
    let fontHeight: CGFloat
    let fontColor: NSColor
    let backgroundColor: NSColor?
    let onCommit: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit)
    }

    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.usesDataSource = false
        comboBox.completes = true
        comboBox.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [.foregroundColor: placeholderColor])
        comboBox.addItems(withObjectValues: values)
        comboBox.stringValue = text
        applyAppearance(to: comboBox)
        comboBox.delegate = context.coordinator
        return comboBox
    }

    func updateNSView(_ comboBox: NSComboBox, context: Context) {
        if comboBox.stringValue != text {
            comboBox.stringValue = text
        }
        let currentValues = comboBox.objectValues.compactMap { $0 as? String }
        if currentValues != values {
            comboBox.removeAllItems()
            comboBox.addItems(withObjectValues: values)
        }
        applyAppearance(to: comboBox)
    }

    private func applyAppearance(to comboBox: NSComboBox) {
        comboBox.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [.foregroundColor: placeholderColor])
        let names = fontName?.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        } ?? []
        comboBox.font = names.lazy.compactMap { NSFont(name: $0, size: fontHeight) }.first
            ?? NSFont.systemFont(ofSize: fontHeight)
        comboBox.textColor = fontColor
        if let backgroundColor {
            comboBox.backgroundColor = backgroundColor
        }
    }

    final class Coordinator: NSObject, NSComboBoxDelegate, NSTextFieldDelegate {
        private var text: Binding<String>
        private let onCommit: (String) -> Void

        init(text: Binding<String>, onCommit: @escaping (String) -> Void) {
            self.text = text
            self.onCommit = onCommit
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            text.wrappedValue = comboBox.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox,
                  notification.userInfo?["NSTextMovement"] as? Int == NSReturnTextMovement
            else { return }
            onCommit(comboBox.stringValue)
        }
    }
}

struct MultilineInputField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let font: NSFont
    let textColor: NSColor
    let placeholderColor: NSColor
    let maximumLength: Int?
    let onChange: (String) -> Void
    let onCommit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let editor = TextAreaEditor(frame: scroll.bounds)
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width: 4, height: 4)
        editor.drawsBackground = false
        editor.delegate = context.coordinator
        scroll.documentView = editor
        updateNSView(scroll, context: context)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? TextAreaEditor else { return }
        if editor.string != text, !editor.hasMarkedText() {
            editor.string = text
        }
        editor.font = font
        editor.textColor = textColor
        editor.placeholder = placeholder
        editor.placeholderColor = placeholderColor
        editor.onCommit = onCommit
        editor.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MultilineInputField
        init(_ parent: MultilineInputField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView, !editor.hasMarkedText() else { return }
            let value = TextInputWindowController.editableValue(editor.string, kind: .textArea, maximumLength: parent.maximumLength)
            if value != editor.string {
                editor.string = value
            }
            parent.text = value
            parent.onChange(value)
            editor.needsDisplay = true
        }
    }
}

final class TextAreaEditor: NSTextView {
    var placeholder = ""
    var placeholderColor: NSColor = .placeholderTextColor
    var onCommit: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        if [36, 76].contains(event.keyCode), event.modifierFlags.contains(.control), !hasMarkedText() {
            onCommit?()
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText(), !placeholder.isEmpty else { return }
        let inset = textContainerInset
        let padding = textContainer?.lineFragmentPadding ?? 0
        (placeholder as NSString).draw(
            in: NSRect(x: inset.width + padding, y: inset.height, width: max(0, bounds.width - 2 * (inset.width + padding)), height: bounds.height - inset.height),
            withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: placeholderColor]
        )
    }
}
