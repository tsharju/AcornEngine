import Foundation
import Compression
import AcornMapGeometry

/// Actor responsible for asynchronously loading, decompressing, and processing Mapbox Vector Tiles into engine meshes.
public actor MapTileLoader {
    /// Initializes a new MapTileLoader.
    public init() {}
    
    /// Decompresses GZIP-compressed data using native Apple libcompression, with fallback to zlib.
    /// Returns the original data if not GZIP-compressed.
    public static func decompressGzip(data: Data) -> Data? {
        guard data.count >= 2 else { return nil }
        
        // If not GZIP magic bytes (0x1f, 0x8b), return data as-is
        if data[0] != 0x1f || data[1] != 0x8b {
            return data
        }
        
        // 1. First attempt native Apple libcompression
        if let nativeResult = decompressWithLibcompression(data: data) {
            return nativeResult
        }
        
        // 2. Fallback to AcornMapGeometry zlib decompressor
        let res = data.withUnsafeBytes { buffer -> AcornMap.DecompressionResult? in
            guard let ptr = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
            return AcornMap.MapboxTileProcessor.decompressGzip(ptr, buffer.count)
        }
        
        if let res = res, res.success {
            let count = res.size()
            var bytes = [UInt8](repeating: 0, count: count)
            bytes.withUnsafeMutableBufferPointer { buf in
                res.copyTo(buf.baseAddress)
            }
            return Data(bytes)
        }
        
        return nil
    }
    
    /// Native decompression using Apple's libcompression framework (COMPRESSION_ZLIB).
    public static func decompressWithLibcompression(data: Data) -> Data? {
        // GZIP requires at least 10-byte header and 8-byte trailer
        guard data.count >= 18 else { return nil }
        guard data[0] == 0x1f, data[1] == 0x8b, data[2] == 0x08 else { return nil }
        
        let flags = data[3]
        var headerOffset = 10
        
        // FEXTRA
        if flags & 0x04 != 0 {
            guard data.count > headerOffset + 2 else { return nil }
            let xlen = Int(data[headerOffset]) | (Int(data[headerOffset + 1]) << 8)
            headerOffset += 2 + xlen
        }
        
        // FNAME
        if flags & 0x08 != 0 {
            while headerOffset < data.count && data[headerOffset] != 0 {
                headerOffset += 1
            }
            headerOffset += 1 // null terminator
        }
        
        // FCOMMENT
        if flags & 0x10 != 0 {
            while headerOffset < data.count && data[headerOffset] != 0 {
                headerOffset += 1
            }
            headerOffset += 1 // null terminator
        }
        
        // FHCRC
        if flags & 0x02 != 0 {
            headerOffset += 2
        }
        
        guard headerOffset < data.count - 8 else { return nil }
        
        // Read uncompressed size (ISIZE) from the last 4 bytes (little endian)
        let isizeOffset = data.count - 4
        let isize = Int(data[isizeOffset]) |
                   (Int(data[isizeOffset + 1]) << 8) |
                   (Int(data[isizeOffset + 2]) << 16) |
                   (Int(data[isizeOffset + 3]) << 24)
        
        // Target capacity: ISIZE or proportional estimate
        let capacity = isize > 0 ? isize : max(data.count * 4, 1024)
        var destination = [UInt8](repeating: 0, count: capacity)
        
        let compressedPayloadSize = (data.count - 8) - headerOffset
        
        let decodedSize = data.withUnsafeBytes { rawBuffer -> Int in
            guard let basePtr = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            let payloadPtr = basePtr + headerOffset
            return destination.withUnsafeMutableBufferPointer { destBuffer in
                guard let destPtr = destBuffer.baseAddress else { return 0 }
                return compression_decode_buffer(
                    destPtr,
                    capacity,
                    payloadPtr,
                    compressedPayloadSize,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        
        if decodedSize > 0 {
            return Data(destination.prefix(decodedSize))
        }
        
        return nil
    }
    
    /// Processes raw tile data (compressed or uncompressed MVT bytes) into CPUMeshData.
    /// - Parameters:
    ///   - data: The raw vector tile byte data (.pbf / .mvt).
    ///   - coordinate: The slippy tile coordinate.
    ///   - referenceLatitude: The reference latitude in degrees for metric scale calculation.
    /// - Returns: CPUMeshData containing 3D vertex positions, normals, colors, and indices.
    public func processTile(
        data: Data,
        coordinate: TileCoordinate,
        referenceLatitude: Double
    ) -> CPUMeshData {
        let (widthMeters, heightMeters) = coordinate.groundDimensions(atLatitude: referenceLatitude)
        
        return data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self), buffer.count > 0 else {
                return CPUMeshData()
            }
            
            let result = AcornMap.MapboxTileProcessor.processTile(
                baseAddress,
                buffer.count,
                Float(widthMeters),
                Float(heightMeters)
            )
            
            let vertexCount = result.getVertexCount()
            var vertices = [Vertex]()
            vertices.reserveCapacity(vertexCount)
            for i in 0..<vertexCount {
                let v = result.getVertex(i)
                vertices.append(Vertex(
                    position: SIMD3<Float>(v.x, v.y, v.z),
                    color: SIMD4<Float>(v.r, v.g, v.b, v.a),
                    texCoord: SIMD2<Float>(v.u, v.v),
                    normal: SIMD3<Float>(v.nx, v.ny, v.nz)
                ))
            }
            
            let indexCount = result.getIndexCount()
            var indices = [UInt32]()
            indices.reserveCapacity(indexCount)
            for i in 0..<indexCount {
                indices.append(result.getIndex(i))
            }
            
            return CPUMeshData(vertices: vertices, indices: indices)
        }
    }
    
    /// Fetches a vector tile from a network URL or file URL, decompresses, and meshes it.
    /// - Parameters:
    ///   - url: URL to fetch tile from.
    ///   - coordinate: Slippy tile coordinate.
    ///   - referenceLatitude: Reference latitude in degrees for metric scale calculation.
    ///   - session: URLSession to perform fetch.
    /// - Returns: CPUMeshData for the tile.
    public func fetchTile(
        from url: URL,
        coordinate: TileCoordinate,
        referenceLatitude: Double,
        session: URLSession = .shared
    ) async throws -> CPUMeshData {
        let (data, response) = try await session.data(from: url)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return processTile(data: data, coordinate: coordinate, referenceLatitude: referenceLatitude)
    }
    
    /// Loads a vector tile from local filesystem storage.
    /// - Parameters:
    ///   - filePath: Absolute path to the vector tile file.
    ///   - coordinate: Slippy tile coordinate.
    ///   - referenceLatitude: Reference latitude in degrees for metric scale calculation.
    /// - Returns: CPUMeshData for the tile.
    public func loadTileFromDisk(
        filePath: String,
        coordinate: TileCoordinate,
        referenceLatitude: Double
    ) throws -> CPUMeshData {
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        return processTile(data: data, coordinate: coordinate, referenceLatitude: referenceLatitude)
    }
    
    /// Generates a demo 3D building mesh with courtyard hole, outward normals, and triangulated roof.
    public func createDemoBuildingTile(
        tileWidthMeters: Float = 4.0,
        tileHeightMeters: Float = 4.0,
        buildingHeight: Float = 1.5
    ) -> CPUMeshData {
        var outerRing = AcornMap.PolygonRing()
        outerRing.addPoint(1000.0, 1000.0)
        outerRing.addPoint(3000.0, 1000.0)
        outerRing.addPoint(3000.0, 3000.0)
        outerRing.addPoint(1000.0, 3000.0)
        outerRing.addPoint(1000.0, 1000.0)
        
        var holeRing = AcornMap.PolygonRing()
        holeRing.addPoint(1600.0, 1600.0)
        holeRing.addPoint(1600.0, 2400.0)
        holeRing.addPoint(2400.0, 2400.0)
        holeRing.addPoint(2400.0, 1600.0)
        holeRing.addPoint(1600.0, 1600.0)
        
        var input = AcornMap.TestPolygonInput()
        input.addRing(outerRing)
        input.addRing(holeRing)
        
        var result = AcornMap.TileMeshResult()
        AcornMap.MapboxTileProcessor.processPolygon(
            input,
            Double(buildingHeight),
            0.0,
            4096,
            tileWidthMeters,
            tileHeightMeters,
            &result,
            false
        )
        
        let vertexCount = result.getVertexCount()
        var vertices = [Vertex]()
        vertices.reserveCapacity(vertexCount)
        for i in 0..<vertexCount {
            let v = result.getVertex(i)
            vertices.append(Vertex(
                position: SIMD3<Float>(v.x - tileWidthMeters / 2.0, v.y, v.z - tileHeightMeters / 2.0),
                color: SIMD4<Float>(v.r, v.g, v.b, v.a),
                texCoord: SIMD2<Float>(v.u, v.v),
                normal: SIMD3<Float>(v.nx, v.ny, v.nz)
            ))
        }
        
        let indexCount = result.getIndexCount()
        var indices = [UInt32]()
        indices.reserveCapacity(indexCount)
        for i in 0..<indexCount {
            indices.append(result.getIndex(i))
        }
        
        return CPUMeshData(vertices: vertices, indices: indices)
    }
}
