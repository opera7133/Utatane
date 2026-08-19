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
                3: String(event.scope),
                5: String(event.button)
            ]
            if let region = event.region {
                references[4] = region
            }
            switch event.kind {
            case .move:
                id = "OnMouseMove"
            case .click:
                id = "OnMouseClick"
            case .doubleClick:
                id = "OnMouseDoubleClick"
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
            return (id, Dictionary(uniqueKeysWithValues: arguments.enumerated().map {
                ($0.offset, $0.element)
            }))
        }
    }
}
