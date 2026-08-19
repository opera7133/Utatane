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
            ("OnBoot", [:])
        case .close:
            ("OnClose", [:])
        case let .ghostChanging(name):
            ("OnGhostChanging", name.map { [0: $0] } ?? [:])
        case let .mouseClick(scope, region):
            (
                "OnMouseClick",
                [
                    0: context.mouseX.map(String.init),
                    1: context.mouseY.map(String.init),
                    3: String(scope),
                    4: region,
                    5: String(context.mouseButton)
                ].compactMapValues { $0 }
            )
        case .randomTalk:
            ("OnAITalk", [:])
        case let .choice(id, arguments):
            (id, Dictionary(uniqueKeysWithValues: arguments.enumerated().map { ($0.offset, $0.element) }))
        }
    }
}
