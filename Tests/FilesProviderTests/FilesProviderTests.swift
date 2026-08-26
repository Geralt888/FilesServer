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

private struct PlayPathFilesServer: FilesServer {
    nonisolated(unsafe) static var drives: [FilesServer] = []

    let url: URL

    static func startDiscovery(url _: URL) -> Self? {
        Self(url: URL(string: "smb://host/share")!)
    }

    static func scheme(isHttps: Bool) -> String {
        isHttps ? "https" : "http"
    }

    func listShares() async throws -> [String] {
        ["share"]
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

    func play(for _: URL, path: String) -> Either<URL, AbstractAVIOContext> {
        .left(URL(fileURLWithPath: path))
    }
}

private final class DiscoveryShareFilesServer: FilesServer, @unchecked Sendable {
    nonisolated(unsafe) static var drives: [FilesServer] = []

    private let serverURL: URL
    private var connectedShare: String?

    var url: URL {
        guard let connectedShare else {
            return serverURL
        }
        return serverURL.appendingPathComponent(connectedShare)
    }

    init(url: URL) {
        serverURL = url
    }

    static func startDiscovery(url: URL) -> Self? {
        Self(url: url)
    }

    static func scheme(isHttps: Bool) -> String {
        isHttps ? "https" : "http"
    }

    func listShares() async throws -> [String] {
        ["share", "share2"]
    }

    func connect(share: String) async throws {
        connectedShare = share
    }

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

private final class DiscoveryURLFilesServer: FilesServer, @unchecked Sendable {
    nonisolated(unsafe) static var drives: [FilesServer] = []
    nonisolated(unsafe) static var discoveredURL: URL?

    private let serverURL: URL
    private var connectedShare: String?

    var url: URL {
        guard let connectedShare else {
            return serverURL
        }
        return serverURL.appendingPathComponent(connectedShare)
    }

    init(url: URL) {
        serverURL = url
    }

    static func startDiscovery(url: URL) -> Self? {
        discoveredURL = url
        return Self(url: url)
    }

    static func scheme(isHttps: Bool) -> String {
        isHttps ? "https" : "http"
    }

    func listShares() async throws -> [String] {
        ["share", "share/sub"]
    }

    func connect(share: String) async throws {
        connectedShare = share
    }

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

@Suite(.serialized)
struct 文件服务器播放入口测试 {
    @Test
    func 服务器路径不匹配时返回原始URL() async throws {
        PlayPathFilesServer.drives = []
        defer { PlayPathFilesServer.drives = [] }

        let url = try #require(URL(string: "smb://host"))
        let result = await PlayPathFilesServer.play(url: url)

        #expect(result.left == url)
    }

    @Test
    func 向服务器传递正确的相对路径() async throws {
        let driveURL = try #require(URL(string: "smb://host/share"))
        PlayPathFilesServer.drives = [PlayPathFilesServer(url: driveURL)]
        defer { PlayPathFilesServer.drives = [] }

        let url = try #require(URL(string: "smb://host/share/media/file.mp4"))
        let result = await PlayPathFilesServer.play(url: url)

        #expect(result.left?.path == "/media/file.mp4")
    }

    @Test
    func 缓存服务器路径按组件边界匹配并继续选择正确服务器() async throws {
        let shareURL = try #require(URL(string: "smb://host/share"))
        let share2URL = try #require(URL(string: "smb://host/share2"))
        PlayPathFilesServer.drives = [
            PlayPathFilesServer(url: shareURL),
            PlayPathFilesServer(url: share2URL),
        ]
        defer { PlayPathFilesServer.drives = [] }

        let url = try #require(URL(string: "smb://host/share2/file"))
        let server = try await #require(PlayPathFilesServer.getServer(url: url))

        #expect(server.url == share2URL)
    }

    @Test
    func 缓存服务器路径存在嵌套时选择最长合法前缀() async throws {
        let shareURL = try #require(URL(string: "smb://host/share"))
        let nestedURL = try #require(URL(string: "smb://host/share/sub"))
        PlayPathFilesServer.drives = [
            PlayPathFilesServer(url: shareURL),
            PlayPathFilesServer(url: nestedURL),
        ]
        defer { PlayPathFilesServer.drives = [] }

        let url = try #require(URL(string: "smb://host/share/sub/file"))
        let server = try await #require(PlayPathFilesServer.getServer(url: url))

        #expect(server.url == nestedURL)
    }

    @Test
    func 缓存服务器根路径可以匹配无斜杠的根URL() async throws {
        let rootURL = try #require(URL(string: "smb://host/"))
        PlayPathFilesServer.drives = [PlayPathFilesServer(url: rootURL)]
        defer { PlayPathFilesServer.drives = [] }

        let url = try #require(URL(string: "smb://host"))
        let server = try await #require(PlayPathFilesServer.getServer(url: url))

        #expect(server.url == rootURL)
    }

    @Test
    func 首次发现服务器时按路径组件边界选择最长共享目录() async throws {
        DiscoveryShareFilesServer.drives = []
        defer { DiscoveryShareFilesServer.drives = [] }

        let url = try #require(URL(string: "smb://host/share2/file"))
        let server = try await #require(DiscoveryShareFilesServer.getServer(url: url))

        #expect(server.url == URL(string: "smb://host/share2"))
    }

    @Test
    func 缓存服务器匹配时忽略scheme和主机大小写() async throws {
        let driveURL = try #require(URL(string: "SMB://HOST/share"))
        PlayPathFilesServer.drives = [PlayPathFilesServer(url: driveURL)]
        defer { PlayPathFilesServer.drives = [] }

        let url = try #require(URL(string: "smb://host/share/file"))
        let server = try await #require(PlayPathFilesServer.getServer(url: url))

        #expect(server.url == driveURL)
    }

    @Test
    func 缓存服务器不匹配不同端口() async throws {
        let driveURL = try #require(URL(string: "smb://host:445/share"))
        MoveCapableFilesServer.drives = [MoveCapableFilesServer(url: driveURL)]
        defer { MoveCapableFilesServer.drives = [] }

        let url = try #require(URL(string: "smb://host:446/share/file"))
        let server = try await #require(MoveCapableFilesServer.getServer(url: url))

        #expect(server.url != driveURL)
        #expect(server.url.port == 446)
    }

    @Test
    func 缓存服务器不匹配不同凭据() async throws {
        let driveURL = try #require(URL(string: "smb://alice:secret@host/share"))
        MoveCapableFilesServer.drives = [MoveCapableFilesServer(url: driveURL)]
        defer { MoveCapableFilesServer.drives = [] }

        let url = try #require(URL(string: "smb://bob:secret@host/share/file"))
        let server = try await #require(MoveCapableFilesServer.getServer(url: url))

        #expect(server.url != driveURL)
        #expect(server.url.user == "bob")
    }

    @Test
    func 缓存服务器匹配等价的凭据编码() async throws {
        let driveURL = try #require(URL(string: "smb://alice:p%3Aass@host/share"))
        MoveCapableFilesServer.drives = [MoveCapableFilesServer(url: driveURL)]
        defer { MoveCapableFilesServer.drives = [] }

        let url = try #require(URL(string: "smb://alice:p:ass@host/share/file"))
        let server = try await #require(MoveCapableFilesServer.getServer(url: url))

        #expect(server.url == driveURL)
    }

    @Test
    func 缓存服务器区分缺失密码和空密码() async throws {
        let driveURL = try #require(URL(string: "smb://alice:@host/share"))
        MoveCapableFilesServer.drives = [MoveCapableFilesServer(url: driveURL)]
        defer { MoveCapableFilesServer.drives = [] }

        let url = try #require(URL(string: "smb://alice@host/share/file"))
        let server = try await #require(MoveCapableFilesServer.getServer(url: url))

        #expect(server.url != driveURL)
        #expect(server.url.password == nil)
    }

    @Test
    func URL构造器保留显式空用户名和空密码() throws {
        let missing = try #require(URL.url(
            scheme: "smb",
            host: "host",
            port: nil,
            path: nil,
            username: nil,
            password: nil
        ))
        let blank = try #require(URL.url(
            scheme: "smb",
            host: "host",
            port: nil,
            path: nil,
            username: "",
            password: ""
        ))

        #expect(missing.user == nil)
        #expect(missing.password == nil)
        #expect(blank.user == "")
        #expect(blank.password == "")
        #expect(blank != missing)
    }

    @Test
    func discovery重建URL保留percentEncoded凭据语义() async throws {
        DiscoveryURLFilesServer.drives = []
        DiscoveryURLFilesServer.discoveredURL = nil
        defer {
            DiscoveryURLFilesServer.drives = []
            DiscoveryURLFilesServer.discoveredURL = nil
        }

        let url = try #require(URL(string: "smb://domain%5Cuser:p%40ss@host/share/sub/file"))
        _ = try await #require(DiscoveryURLFilesServer.getServer(url: url))
        let discoveredURL = try #require(DiscoveryURLFilesServer.discoveredURL)

        #expect(discoveredURL.user?.removingPercentEncoding == "domain\\user")
        #expect(discoveredURL.password?.removingPercentEncoding == "p@ss")
        #expect(discoveredURL.password != "p%2540ss")
    }

    @Test
    func discovery嵌套共享目录选择最长合法前缀() async throws {
        DiscoveryURLFilesServer.drives = []
        DiscoveryURLFilesServer.discoveredURL = nil
        defer {
            DiscoveryURLFilesServer.drives = []
            DiscoveryURLFilesServer.discoveredURL = nil
        }

        let url = try #require(URL(string: "smb://host/share/sub/file"))
        let server = try await #require(DiscoveryURLFilesServer.getServer(url: url))

        #expect(server.url == URL(string: "smb://host/share/sub"))
    }

    @Test
    func 缓存匹配拒绝percentEncoded点段越过共享目录() async throws {
        let driveURL = try #require(URL(string: "smb://host/share"))
        PlayPathFilesServer.drives = [PlayPathFilesServer(url: driveURL)]
        defer { PlayPathFilesServer.drives = [] }

        let url = try #require(URL(string: "smb://host/share/%2E%2E/other"))
        let server = try await PlayPathFilesServer.getServer(url: url)

        #expect(server == nil)
    }

    @Test
    func 播放路径使用规范化组件且不转发共享目录外路径() async throws {
        let driveURL = try #require(URL(string: "smb://host/share"))
        PlayPathFilesServer.drives = [PlayPathFilesServer(url: driveURL)]
        defer { PlayPathFilesServer.drives = [] }

        let url = try #require(URL(string: "smb://host/share/%2E%2E/other"))
        let result = await PlayPathFilesServer.play(url: url)

        #expect(result.left == url)
    }

    @Test
    func 缓存匹配区分不同scheme() async throws {
        let driveURL = try #require(URL(string: "smb://host/share"))
        MoveCapableFilesServer.drives = [MoveCapableFilesServer(url: driveURL)]
        defer { MoveCapableFilesServer.drives = [] }

        let url = try #require(URL(string: "https://host/share/file"))
        let server = try await #require(MoveCapableFilesServer.getServer(url: url))

        #expect(server.url.scheme == "https")
        #expect(server.url != driveURL)
    }
}

private func 接受异步播放入口<Result>(_ play: @escaping (URL) async -> Result) -> (URL) async -> Result {
    play
}
