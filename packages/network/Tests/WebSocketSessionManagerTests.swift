import Foundation
import Testing
@testable import UtataneNetwork

@Test
func `maps websocket lifecycle events to SHIORI references`() {
    #expect(WebSocketSessionEvent.open(url: "wss://example.com", eventID: "chat").shioriEvent == (
        id: "OnExecuteWebSocketOpen",
        references: [0: "chat", 1: "wss://example.com", 2: "200"]
    ))
    #expect(WebSocketSessionEvent.text(
        url: "wss://example.com",
        eventID: "OnChat",
        value: "one\r\ntwo"
    ).shioriEvent == (
        id: "OnChat",
        references: [0: "OnChat", 1: "wss://example.com", 2: "1", 3: "one\u{1}two"]
    ))
    #expect(WebSocketSessionEvent.close(
        url: "wss://example.com",
        eventID: "OnChat",
        reason: "userbreak"
    ).shioriEvent == (
        id: "OnChatClose",
        references: [0: "OnChat", 1: "wss://example.com", 2: "userbreak"]
    ))
    #expect(WebSocketSessionEvent.reconnect(
        url: "wss://example.com",
        eventID: "chat"
    ).shioriEvent == (
        id: "OnExecuteWebSocketReconnect",
        references: [0: "chat", 1: "wss://example.com", 2: "200"]
    ))
    #expect(WebSocketSessionEvent.sslInfo(
        url: "wss://example.com",
        eventID: "chat",
        protocolVersion: "TLSv1.3",
        cipherSuite: "AES_128_GCM",
        subject: "example.com",
        issuer: "Example CA",
        chain: ["example.com", "Example CA"]
    ).shioriEvent == (
        id: "OnExecuteWebSocket_SSLInfo",
        references: [
            0: "chat", 1: "wss://example.com", 2: "200", 3: "TLSv1.3", 4: "AES_128_GCM",
            5: "example.com", 6: "", 7: "", 8: "Example CA", 9: "example.com,Example CA"
        ]
    ))
}
