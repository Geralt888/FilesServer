//
//  FilesServer.swift
//  FilesServer
//
//  Created by kintan on 12/26/24.
//

import Foundation
import KSPlayer

public protocol FilesServer: Sendable {
    static var drives: [FilesServer] { get set }
    static func startDiscovery(url: URL) -> Self?
    static func scheme(isHttps: Bool) -> String
    var url: URL { get }
    func listShares() async throws -> [String]
    func connect(share: String) async throws
    func contentsOfDirectory(atPath path: String) async throws -> [FileObject]
    func contents(atPath path: String) async throws -> Data
    func removeItem(atPath path: String) async throws
    func moveItem(atPath path: String, toPath: String) async throws
    func createDirectory(atPath path: String) async throws
    func play(for url: URL, path: String) -> Either<URL, AbstractAVIOContext>
}

@globalActor
actor BackgroundActor {
    static let shared = BackgroundActor()
}

public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case head = "HEAD"
    case options = "OPTIONS"
    case propfind = "PROPFIND"
    case mkcol = "MKCOL"
    case move = "MOVE"
    case copy = "COPY"
}

public extension URL {
    static func url(scheme: String?, host: String, port: Int?, path: String?, username: String?, password: String?) -> URL? {
        var urlComponents = URLComponents()
        urlComponents.scheme = scheme
        urlComponents.host = host
        urlComponents.port = port
        // 处理路径
        if let path, !path.isEmpty {
            let trimmedPath = path.hasPrefix("/") ? path : "/\(path)"
            urlComponents.path = trimmedPath
        } else {
            urlComponents.path = ""
        }
        if username?.isEmpty == false {
            urlComponents.user = username
        }
        if password?.isEmpty == false {
            urlComponents.password = password
        }
        return urlComponents.url
    }

    var withoutUserPassword: URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }
        components.user = nil
        components.password = nil
        return components.url ?? self
    }

    func add(username: String, password: String) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }
        components.user = username
        components.password = password
        return components.url ?? self
    }
}

public extension FilesServer {
    func play(for url: URL, path _: String) -> Either<URL, AbstractAVIOContext> {
        .left(url)
    }

    /// 默认使用URLRequest下载，ftp和http协议都可以使用URLRequest。
    func contents(atPath path: String) async throws -> Data {
        try await url.appendingPathComponent(path).data()
    }

    static func url(isHttps: Bool, host: String, port: Int?, path: String?, username: String?, password: String?) -> URL? {
        URL.url(scheme: scheme(isHttps: isHttps), host: host, port: port, path: path, username: username, password: password)
    }

    /// 增加actor，防止并发导致crash
    @BackgroundActor
    static func getServer(url: URL, name: String? = nil) async throws -> FilesServer? {
        if let drive = drives.first(where: { url.absoluteString.hasPrefix($0.url.absoluteString) }) {
            return drive
        } else {
            if let name {
                var url = url
                if url.lastPathComponent == name {
                    url.deleteLastPathComponent()
                }
                if let drive = startDiscovery(url: url) {
                    try await drive.connect(share: name)
                    drives.append(drive)
                    return drive
                } else {
                    return nil
                }
            } else {
                let path = url.path
                var components = URLComponents()
                components.scheme = url.scheme
                components.host = url.host
                components.port = url.port
                components.user = url.user
                components.password = url.password
                guard let url = components.url, let drive = startDiscovery(url: url) else {
                    return nil
                }
                let shares = try await drive.listShares()
                var share = shares.first { share in
                    // nfs的share带有/， 但是smb没有
                    path.hasPrefix("/" + share) || path.hasPrefix(share)
                }
                if share == nil {
                    if let first = shares.first {
                        share = shares.first
                    } else {
                        share = path.split(separator: "/").first.map { String($0) }
                    }
                }
                try await drive.connect(share: share ?? "")
                // 解决多线程并发crash的问题
                if let share, let value = drives.first(where: { $0.url == url.appendingPathComponent(share) }) {
                    return value
                }
                drives.append(drive)
                return drive
            }
        }
    }

    static func play(url: URL) async -> Either<URL, AbstractAVIOContext> {
        do {
            if let drive = try await getServer(url: url) {
                let path = url.path
                let drivePath = drive.url.path
                guard path.count >= drivePath.count, path.hasPrefix(drivePath) else {
                    return .left(url)
                }
                let relativePath = path.dropFirst(drivePath.count)
                guard relativePath.isEmpty || drivePath.hasSuffix("/") || relativePath.first == "/" else {
                    return .left(url)
                }
                return drive.play(for: url, path: String(relativePath))
            }
        } catch {
            KSLog(error)
        }
        return .left(url)
    }
}
