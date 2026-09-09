import Foundation
import AcornEngine

/// Service actor responsible for fetching, caching, and serving raw Mapbox vector tiles (`.vector.pbf`).
///
/// This actor provides asynchronous tile fetching with automatic disk caching in the application caches directory.
/// Mapbox vector tiles are fetched from the Mapbox Streets v8 API endpoint using the access token configured
/// in the application's `Info.plist` (under the `MBXAccessToken` key) or passed via the initializer.
public actor MapboxTileService {
    /// Mapbox access token used to authenticate tile requests.
    public let accessToken: String?
    
    /// The URLSession instance used for network requests.
    private let session: URLSession
    
    /// File manager instance used for disk caching operations.
    private let fileManager: FileManager
    
    /// Directory URL where downloaded vector tiles are cached on disk.
    public let cacheDirectoryURL: URL
    
    /// Resolves the access token from explicit arguments, uncommitted credentials plist, environment variables, or Info.plist.
    public static func resolveAccessToken(explicitToken: String? = nil) -> String? {
        if let token = explicitToken {
            return token.isEmpty ? nil : token
        }
        
        // 1. Check for uncommitted MapboxCredentials.plist in main bundle
        if let url = Bundle.main.url(forResource: "MapboxCredentials", withExtension: "plist"),
           let dict = NSDictionary(contentsOf: url) as? [String: Any],
           let token = dict["MBXAccessToken"] as? String,
           !token.isEmpty,
           token != "YOUR_MAPBOX_ACCESS_TOKEN" {
            return token
        }
        
        // 2. Check environment variables (e.g. for CI, scheme or unit tests)
        if let envToken = ProcessInfo.processInfo.environment["MBXAccessToken"], !envToken.isEmpty {
            return envToken
        }
        if let envToken = ProcessInfo.processInfo.environment["MAPBOX_ACCESS_TOKEN"], !envToken.isEmpty {
            return envToken
        }
        
        // 3. Fallback to Bundle.main.infoDictionary
        if let infoToken = Bundle.main.infoDictionary?["MBXAccessToken"] as? String,
           !infoToken.isEmpty,
           infoToken != "YOUR_MAPBOX_ACCESS_TOKEN" {
            return infoToken
        }
        
        return nil
    }
    
    /// Initializes a new `MapboxTileService`.
    ///
    /// - Parameters:
    ///   - accessToken: An optional Mapbox access token. If omitted or `nil`, the service resolves the token
    ///     from `MapboxCredentials.plist`, process environment, or `Info.plist`.
    ///   - session: The `URLSession` used to execute HTTP requests. Defaults to `.shared`.
    ///   - fileManager: The `FileManager` used for disk cache operations. Defaults to `.default`.
    public init(
        accessToken: String? = nil,
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        cacheDirectoryURL: URL? = nil
    ) {
        self.accessToken = Self.resolveAccessToken(explicitToken: accessToken)
        self.session = session
        self.fileManager = fileManager
        
        if let customCache = cacheDirectoryURL {
            self.cacheDirectoryURL = customCache
        } else {
            let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.cacheDirectoryURL = cachesDirectory.appendingPathComponent("MapboxTileCache", isDirectory: true)
        }
        
        // Ensure cache directory exists
        try? fileManager.createDirectory(at: self.cacheDirectoryURL, withIntermediateDirectories: true)
    }
    
    /// Resolves the local disk cache file URL for the given tile coordinate.
    ///
    /// - Parameter coordinate: The slippy map tile coordinate.
    /// - Returns: A file `URL` pointing to `MapboxTileCache/<zoom>_<x>_<y>.pbf`.
    public func cacheFileURL(for coordinate: TileCoordinate) -> URL {
        cacheDirectoryURL.appendingPathComponent("\(coordinate.zoom)_\(coordinate.x)_\(coordinate.y).pbf")
    }
    
    /// Fetches raw vector tile data (`.vector.pbf`) for the specified tile coordinate.
    ///
    /// The fetch workflow:
    /// 1. Checks the local disk cache (`MapboxTileCache/<zoom>_<x>_<y>.pbf`). If present, returns cached data immediately.
    /// 2. Verifies that a valid Mapbox access token is available.
    /// 3. Performs an asynchronous HTTP GET request to `https://api.mapbox.com/v4/mapbox.mapbox-streets-v8/<zoom>/<x>/<y>.vector.pbf`.
    /// 4. On HTTP 200 response, persists data to the disk cache atomically and returns the data.
    /// 5. On HTTP 401 or network error, logs the failure and returns `nil`.
    ///
    /// - Parameter coordinate: The tile coordinate to fetch.
    /// - Returns: The raw tile bytes as `Data`, or `nil` if authentication failed, the tile could not be fetched, or a network error occurred.
    /// - Throws: Rethrows `CancellationError` if the calling task is cancelled.
    public func fetchTileData(coordinate: TileCoordinate) async throws -> Data? {
        try Task.checkCancellation()
        
        // 1. Check disk cache first
        let fileURL = cacheFileURL(for: coordinate)
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                let cachedData = try Data(contentsOf: fileURL)
                return cachedData
            } catch {
                print("MapboxTileService: Failed to read cached tile at \(fileURL.path): \(error)")
                // Fall through to network request
            }
        }
        
        // 2. Resolve access token
        guard let token = accessToken, !token.isEmpty else {
            print("MapboxTileService: Missing or empty MBXAccessToken. Cannot fetch tile \(coordinate).")
            return nil
        }
        
        // 3. Construct URL
        let urlString = "https://api.mapbox.com/v4/mapbox.mapbox-streets-v8/\(coordinate.zoom)/\(coordinate.x)/\(coordinate.y).vector.pbf?access_token=\(token)"
        guard let url = URL(string: urlString) else {
            print("MapboxTileService: Invalid URL string: \(urlString)")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30.0
        
        // 4. Perform network request
        do {
            let (data, response) = try await session.data(for: request)
            
            try Task.checkCancellation()
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("MapboxTileService: Non-HTTP response received for tile \(coordinate)")
                return nil
            }
            
            if httpResponse.statusCode == 200 {
                // Save to disk cache
                do {
                    if !fileManager.fileExists(atPath: cacheDirectoryURL.path) {
                        try fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
                    }
                    try data.write(to: fileURL, options: .atomic)
                } catch {
                    print("MapboxTileService: Failed to save tile to cache at \(fileURL.path): \(error)")
                }
                return data
            } else if httpResponse.statusCode == 401 {
                print("MapboxTileService: Unauthorized (401) fetching tile \(coordinate). Check MBXAccessToken.")
                return nil
            } else {
                print("MapboxTileService: HTTP error \(httpResponse.statusCode) fetching tile \(coordinate)")
                return nil
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            print("MapboxTileService: Network error fetching tile \(coordinate): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Clears all cached tiles from the local disk cache directory.
    public func clearCache() throws {
        if fileManager.fileExists(atPath: cacheDirectoryURL.path) {
            try fileManager.removeItem(at: cacheDirectoryURL)
            try fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        }
    }
}
