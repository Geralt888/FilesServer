import Foundation
@testable import FilesServer
import KSPlayer
import Testing

private struct MoveCapableFilesServer: FilesServer {
    nonisolated(unsafe) static var drives: [FilesServer] = []

    let url: URL

    static func startDiscovery(url: URL) -> Self? {
        Self(url: url)
    }

    static func scheme(isHttps: Bool) -> String {
        isHttps ? "https" : "http"
    }

    func listShares() async throws -> [String] {
        []
    }

    func connect(share _: String) async throws {}

    func contentsOfDirectory(atPath _: String) async throws -> [KSPlayer.FileObject] {
        []
    }

    func contents(atPath _: String) async throws -> Data {
        Data()
    }

    func removeItem(atPath _: String) async throws {}

    func moveItem(atPath _: String, toPath _: String) async throws {}

    func createDirectory(atPath _: String) async throws {}
}

@Test
func URL可以移除并重新附加凭据() throws {
    let source = try #require(URL(string: "https://alice:secret@example.com:8443/media/file%20name.mkv?download=1"))

    let withoutCredentials = source.withoutUserPassword
    #expect(withoutCredentials.absoluteString == "https://example.com:8443/media/file%20name.mkv?download=1")
    #expect(withoutCredentials.user == nil)
    #expect(withoutCredentials.password == nil)
    #expect(withoutCredentials.add(username: "alice", password: "secret") == source)
}

@Test
func 文件服务器协议可以实现移动文件() async throws {
    let server: any FilesServer = MoveCapableFilesServer(url: URL(string: "smb://example.com/share")!)

    try await server.moveItem(atPath: "/old.txt", toPath: "/new.txt")
}

@Test
func 文件服务器播放入口是异步API() async throws {
    let play = 接受异步播放入口(MoveCapableFilesServer.play(url:))
    let url = URL(string: "http://example.com/media/file.mp4")!

    _ = await play(url)
}

private func 接受异步播放入口<Result>(_ play: @escaping (URL) async -> Result) -> (URL) async -> Result {
    play
}
