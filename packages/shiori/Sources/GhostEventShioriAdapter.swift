import UtataneCore

public struct ShioriEventContext: Equatable, Sendable {
    public var sender: String
    public var charset: String
    public var securityLevel: String
    public var scope: Int
    public var mouseX: Int?
    public var mouseY: Int?
    public var mouseButton: Int

    public init(
        sender: String = "Utatane",
        charset: String = "UTF-8",
        securityLevel: String = "local",
        scope: Int = 0,
        mouseX: Int? = nil,
        mouseY: Int? = nil,
        mouseButton: Int = 0
    ) {
        self.sender = sender
        self.charset = charset
        self.securityLevel = securityLevel
        self.scope = scope
        self.mouseX = mouseX
        self.mouseY = mouseY
        self.mouseButton = mouseButton
    }
}

public struct GhostEventShioriAdapter: Sendable {
    public init() {}

    public func request(
        for event: GhostEvent,
        context: ShioriEventContext = .init()
    ) -> ShioriRequest {
        let mapping = map(event, context: context)
        var headers = ShioriHeaders([
            ShioriHeader(name: "Charset", value: context.charset),
            ShioriHeader(name: "Sender", value: context.sender),
            ShioriHeader(name: "SecurityLevel", value: context.securityLevel),
            ShioriHeader(name: "ID", value: mapping.id)
        ])
        for (index, value) in mapping.references.sorted(by: { $0.key < $1.key }) {
            headers.append(name: "Reference\(index)", value: value)
        }
        return ShioriRequest(method: "GET", headers: headers)
    }

    private func map(
        _ event: GhostEvent,
        context: ShioriEventContext
    ) -> (id: String, references: [Int: String]) {
        switch event {
        case .boot:
            return ("OnBoot", [:])
        case .close:
            return ("OnClose", [:])
        case let .ghostChanging(name):
            return ("OnGhostChanging", name.map { [0: $0] } ?? [:])
        case let .mouseClick(scope, region):
            return (
                "OnMouseClick",
                [
                    0: context.mouseX.map(String.init),
                    1: context.mouseY.map(String.init),
                    3: String(scope),
                    4: region,
                    5: String(context.mouseButton)
                ].compactMapValues { $0 }
            )
        case let .mouse(event):
            let id: String
            var references: [Int: String] = [
                0: String(event.x),
                1: String(event.y),
                2: "0",
                3: String(event.scope),
                5: String(event.button),
                6: "mouse"
            ]
            if let region = event.region {
                references[4] = region
            }
            switch event.kind {
            case .move:
                id = "OnMouseMove"
            case .enter:
                id = "OnMouseEnter"
            case .leave:
                id = "OnMouseLeave"
            case .enterAll:
                id = "OnMouseEnterAll"
            case .leaveAll:
                id = "OnMouseLeaveAll"
            case .down:
                id = event.button <= 1 ? "OnMouseDown" : "OnMouseDownEx"
                references[5] = Self.mouseButtonReference(event.button)
            case .up:
                id = event.button <= 1 ? "OnMouseUp" : "OnMouseUpEx"
                references[5] = Self.mouseButtonReference(event.button)
            case .click:
                id = event.button <= 1 ? "OnMouseClick" : "OnMouseClickEx"
                references[5] = Self.mouseButtonReference(event.button)
            case .doubleClick:
                id = event.button <= 1 ? "OnMouseDoubleClick" : "OnMouseDoubleClickEx"
                references[5] = Self.mouseButtonReference(event.button)
            case let .multipleClick(count):
                id = event.button <= 1 ? "OnMouseMultipleClick" : "OnMouseMultipleClickEx"
                references[5] = Self.mouseButtonReference(event.button)
                references[7] = String(count)
            case .dragStart:
                id = "OnMouseDragStart"
            case .dragEnd:
                id = "OnMouseDragEnd"
            case .hover:
                id = "OnMouseHover"
            case let .wheel(delta):
                id = "OnMouseWheel"
                references[2] = String(delta)
            }
            return (id, references)
        case let .shiori(id, references):
            return (id, references)
        case .randomTalk:
            return ("OnAITalk", [:])
        case let .choice(id, arguments):
            if id.hasPrefix("On") {
                return (id, Dictionary(uniqueKeysWithValues: arguments.enumerated().map {
                    ($0.offset, $0.element)
                }))
            }
            var references = Dictionary(uniqueKeysWithValues: arguments.enumerated().map {
                ($0.offset + 1, $0.element)
            })
            references[0] = id
            return ("OnChoiceSelect", references)
        }
    }

    private static func mouseButtonReference(_ button: Int) -> String {
        switch button {
        case 2: "middle"
        case 3: "xbutton1"
        case 4: "xbutton2"
        default: String(button)
        }
    }
}
