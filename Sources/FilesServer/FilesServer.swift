//
//  FilesServer.swift
//  FilesServer
//
//  Created by kintan on 12/26/24.
//

import Foundation
import KSPlayer

private let discoveryLock = NSRecursiveLock()

public protocol FilesServer: Sendable {
    static var drives: [FilesServer] { get set }
    static func startDiscovery(url: URL) -> Self?
    static func scheme(isHttps: Bool) -> String
    var url: URL { get }
    func contentsOfDirectory(atPath path: String) async throws -> [FileObject]
    func contents(atPath path: String) async throws -> Data
    func removeItem(atPath path: String) async throws
    func moveItem(atPath path: String, toPath: String) async throws
    func createDirectory(atPath path: String) async throws
    func play(for url: URL) async throws -> Either<URL, AbstractAVIOContext>
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
        if let username {
            urlComponents.user = username
        }
        if let password {
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

private extension URL {
    func matches(driveURL: URL) -> Bool {
        guard scheme?.lowercased() == driveURL.scheme?.lowercased(),
              host?.lowercased() == driveURL.host?.lowercased(),
              port == driveURL.port,
              decodedUsername == driveURL.decodedUsername,
              decodedPassword == driveURL.decodedPassword,
              let targetPathComponents = normalizedPathComponents,
              let drivePathComponents = driveURL.normalizedPathComponents
        else {
            return false
        }

        return targetPathComponents.count >= drivePathComponents.count
            && targetPathComponents.starts(with: drivePathComponents)
    }

    var normalizedPathComponents: [String]? {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return components.percentEncodedPath.normalizedPathComponents
    }

    var decodedUsername: String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .percentEncodedUser?.removingPercentEncoding
    }

    var decodedPassword: String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .percentEncodedPassword?.removingPercentEncoding
    }
}

private extension String {
    var normalizedPathComponents: [String]? {
        var result = [String]()
        for rawComponent in split(separator: "/", omittingEmptySubsequences: true) {
            guard let component = String(rawComponent).removingPercentEncoding else {
                return nil
            }
            guard component != ".", component != "..",
                  !component.contains("/"), !component.contains("\\")
            else {
                return nil
            }
            result.append(component)
        }
        return result
    }
}

public extension FilesServer {
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
        guard url.normalizedPathComponents != nil else {
            return nil
        }
        // Discovery remains synchronous while cache lookup and insertion stay serialized.
        discoveryLock.lock()
        defer { discoveryLock.unlock() }
        if let drive = drives
            .filter({ url.matches(driveURL: $0.url) })
            .max(by: { ($0.url.normalizedPathComponents?.count ?? 0) < ($1.url.normalizedPathComponents?.count ?? 0) })
        {
            return drive
        }
        guard let drive = startDiscovery(url: url) else {
            return nil
        }
        drives.append(drive)
        return drive
    }

    static func play(url: URL) async -> Either<URL, AbstractAVIOContext> {
        do {
            if let drive = getServer(url: url) {
                return try await drive.play(for: url)
            }
        } catch {
            KSLog(error)
        }
        return .left(url)
    }
}
