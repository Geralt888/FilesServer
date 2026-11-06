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
    func contentsOfDirectory(atPath path: String) async throws -> [FileObject]
    func contents(atPath path: String) async throws -> Data
    func removeItem(atPath path: String) async throws
    func createDirectory(atPath path: String) async throws
    func play(for url: URL) async throws -> Either<URL, AbstractAVIOContext>
}

public protocol FilesSearchServer: FilesServer {
    func search(term _: String) async throws -> [FileObject]
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
    static func scheme(isHttps: Bool) -> String {
        isHttps ? "https" : "http"
    }

    func play(for url: URL) async throws -> Either<URL, AbstractAVIOContext> {
        .left(url)
    }

    /// 默认使用URLRequest下载，ftp和http协议都可以使用URLRequest。
    func contents(atPath path: String) async throws -> Data {
        try await url.appendingPathComponent(path).data()
    }

    static func url(isHttps: Bool, host: String, port: Int?, path: String?, username: String?, password: String?) -> URL? {
        URL.url(scheme: scheme(isHttps: isHttps), host: host, port: port, path: path, username: username, password: password)
    }

    static func getServer(url: URL) -> FilesServer? {
        if let drive = drives.first(where: { url.absoluteString.hasPrefix($0.url.absoluteString) }) {
            return drive
        } else if let drive = startDiscovery(url: url) {
            drives.append(drive)
            return drive
        } else {
            return nil
        }
    }

    static func play(url: URL) async -> Either<URL, AbstractAVIOContext> {
        do {
            var components = URLComponents()
            components.scheme = url.scheme
            components.host = url.host
            components.port = url.port
            components.user = url.user
            components.password = url.password
            if let baseURL = components.url, let drive = startDiscovery(url: baseURL) {
                return try await drive.play(for: url)
            }
        } catch {
            KSLog(error)
        }
        return .left(url)
    }
}
