import Cocoa
import Darwin

public final class ApiEnvironment {
    private static var credentials: TelegramApplicationCredentials?

    private static var applicationDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Octron/Telegram", isDirectory: true)
    }

    public static var configurationURL: URL {
        applicationDirectory.appendingPathComponent("application.json")
    }

    public static func initialize() throws {
        guard credentials == nil else { return }
        let loaded = try TelegramApplicationCredentials.load(from: configurationURL)
        try prepareStorageDirectory(at: applicationDirectory)
        credentials = loaded
    }

    static func prepareStorageDirectory(at directory: URL) throws {
        let parent = try TelegramApplicationCredentials.openPrivateDirectory(at: directory)
        defer { close(parent) }
        if mkdirat(parent, "account-data", 0o700) != 0, errno != EEXIST {
            throw TelegramApplicationCredentials.ConfigurationError.unsafeStorage
        }
        let descriptor = openat(parent, "account-data", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw TelegramApplicationCredentials.ConfigurationError.unsafeStorage
        }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_uid == geteuid(),
              metadata.st_mode & 0o077 == 0 else {
            throw TelegramApplicationCredentials.ConfigurationError.unsafeStorage
        }
    }

    public static var apiId: Int32 {
        guard let credentials else { preconditionFailure("Telegram has not been initialized") }
        return credentials.apiId
    }

    public static var apiHash: String {
        guard let credentials else { preconditionFailure("Telegram has not been initialized") }
        return credentials.apiHash
    }

    public static var bundleId: String { "io.quattrobit.octron.v1" }
    public static var intentsBundleId: String { bundleId + ".FocusIntents" }

    public static var containerURL: URL? {
        guard credentials != nil else { return nil }
        return applicationDirectory.appendingPathComponent("account-data", isDirectory: true)
    }

    public static var appData: Data {
        let apiData = evaluateApiData() ?? ""
        let dict:[String: String] = ["bundleId": bundleId, "data": apiData]
        return try! JSONSerialization.data(withJSONObject: dict, options: [])
    }
    public static var language: String {
        return "macos"
    }
    
    public static var resolvedDeviceName:[String : String]? {
        if let file = Bundle.main.path(forResource: "mac_devices", ofType: "txt") {
            if let string = try? String(contentsOf: .init(fileURLWithPath: file)) {
                let lines = string.components(separatedBy: "\n\n")
                
                var result:[String : String] = [:]
                for line in lines {
                    let resolved = line.components(separatedBy: "\n")
                    if resolved.count == 2 {
                        result[resolved[1]] = resolved[0]
                    }
                }
                
                return result
            }
        }
        return nil
    }
    
    public static var prefix: String {
        var prefix: String = ""
        switch Configuration.value(for: .source) {
        case "DEBUG":
            prefix = "debug"
        case "STABLE":
            prefix = "stable"
        case "APP_STORE":
            prefix = "appstore"
        default:
            prefix = "beta"
        }
        return prefix
    }
    
    public static var version: String {
        var suffix: String = ""
        
        suffix = Configuration.value(for: .source) ?? "DEBUG"
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? ""
        return "\(shortVersion) \(suffix)"
    }
    
    public static var premiumProductId: String {
        return "org.telegram.telegramPremium.monthly"
    }
}



