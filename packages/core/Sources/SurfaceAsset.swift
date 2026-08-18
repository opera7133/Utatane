import Foundation

/// Files needed to render one shell surface. Decoding is owned by the platform renderer.
public struct SurfaceAsset: Sendable, Equatable {
    public let id: Int
    public let imageURL: URL
    public let alphaMaskURL: URL?

    public init(id: Int, imageURL: URL, alphaMaskURL: URL?) {
        self.id = id
        self.imageURL = imageURL
        self.alphaMaskURL = alphaMaskURL
    }
}
