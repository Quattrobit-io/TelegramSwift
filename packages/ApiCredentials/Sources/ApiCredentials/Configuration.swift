//
//  File.swift
//  
//
//  Created by Mikhail Filimonov on 29.11.2021.
//

import Foundation
import Darwin

public enum Configuration : String {
    enum Error: Swift.Error {
        case missingKey, invalidValue
    }
    case source = "SOURCE"
    
    public static func value(for key: Configuration) -> String? {
        guard let value = Bundle.main.infoDictionary?[key.rawValue] as? String else {
            return nil
        }
        return value
    }
}

public struct TelegramApplicationCredentials: Decodable {
    public let apiId: Int32
    public let apiHash: String

    private enum CodingKeys: String, CodingKey {
        case apiId = "api_id"
        case apiHash = "api_hash"
    }

    public enum ConfigurationError: LocalizedError, Equatable {
        case missingFile, unreadableFile, invalidFormat, invalidCredentials, unsafeStorage

        public var errorDescription: String? {
            switch self {
            case .missingFile:
                return "Telegram application.json is missing from Application Support/Octron/Telegram."
            case .unreadableFile:
                return "Telegram application.json could not be read."
            case .invalidFormat:
                return "Telegram application.json must contain api_id and api_hash."
            case .invalidCredentials:
                return "Telegram requires an Octron-owned API ID and a 32-character hexadecimal API hash."
            case .unsafeStorage:
                return "Telegram storage must use private directories owned by the current user, without symbolic links."
            }
        }
    }

    static func openPrivateDirectory(at directory: URL) throws -> Int32 {
        let namespace = open(directory.deletingLastPathComponent().path,
                             O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard namespace >= 0 else {
            throw errno == ENOENT ? ConfigurationError.missingFile : ConfigurationError.unsafeStorage
        }
        defer { close(namespace) }
        var metadata = stat()
        guard fstat(namespace, &metadata) == 0, metadata.st_uid == geteuid() else {
            throw ConfigurationError.unsafeStorage
        }
        let descriptor = openat(namespace, directory.lastPathComponent,
                                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw errno == ENOENT ? ConfigurationError.missingFile : ConfigurationError.unsafeStorage
        }
        guard fstat(descriptor, &metadata) == 0, metadata.st_uid == geteuid(),
              metadata.st_mode & 0o077 == 0 else {
            close(descriptor)
            throw ConfigurationError.unsafeStorage
        }
        return descriptor
    }

    public static func load(from url: URL) throws -> TelegramApplicationCredentials {
        let parent = try openPrivateDirectory(at: url.deletingLastPathComponent())
        defer { close(parent) }
        let descriptor = openat(parent, url.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw errno == ENOENT ? ConfigurationError.missingFile : ConfigurationError.unreadableFile
        }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_uid == geteuid(), metadata.st_mode & 0o077 == 0,
              metadata.st_size <= 4096 else {
            throw ConfigurationError.unreadableFile
        }
        var buffer = [UInt8](repeating: 0, count: 4097)
        var length = 0
        while length < buffer.count {
            let count = buffer.withUnsafeMutableBytes {
                read(descriptor, $0.baseAddress!.advanced(by: length), $0.count - length)
            }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw ConfigurationError.unreadableFile }
            if count == 0 { break }
            length += count
        }
        guard length <= 4096 else { throw ConfigurationError.unreadableFile }
        let data = Data(buffer.prefix(length))
        let credentials: TelegramApplicationCredentials
        do {
            credentials = try JSONDecoder().decode(Self.self, from: data)
        } catch {
            throw ConfigurationError.invalidFormat
        }
        let isHex = credentials.apiHash.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
        guard credentials.apiId > 0, credentials.apiId != 9,
              credentials.apiHash.utf8.count == 32, isHex else {
            throw ConfigurationError.invalidCredentials
        }
        return credentials
    }
}
