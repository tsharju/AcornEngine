import Testing
import Foundation
@testable import AcornEngine

struct MapTileLoaderTests {
    @Test("GZIP decompression of valid gzip stream")
    func testDecompressGzipValid() {
        // GZIP compressed payload of "Hello Mapbox 3D"
        let gzipBytes: [UInt8] = [
            0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0xf3, 0x48,
            0xcd, 0xc9, 0xc9, 0x57, 0xf0, 0x4d, 0x2c, 0x48, 0xca, 0xaf, 0x50, 0x30,
            0x76, 0x01, 0x00, 0xe2, 0x82, 0x09, 0x7d, 0x0f, 0x00, 0x00, 0x00
        ]
        let compressedData = Data(gzipBytes)
        
        let decompressed = MapTileLoader.decompressGzip(data: compressedData)
        #expect(decompressed != nil)
        if let decompressed = decompressed {
            let text = String(data: decompressed, encoding: .utf8)
            #expect(text == "Hello Mapbox 3D")
        }
    }
    
    @Test("Native libcompression direct decompression of GZIP payload")
    func testNativeLibcompressionDirect() {
        let gzipBytes: [UInt8] = [
            0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0xf3, 0x48,
            0xcd, 0xc9, 0xc9, 0x57, 0xf0, 0x4d, 0x2c, 0x48, 0xca, 0xaf, 0x50, 0x30,
            0x76, 0x01, 0x00, 0xe2, 0x82, 0x09, 0x7d, 0x0f, 0x00, 0x00, 0x00
        ]
        let compressedData = Data(gzipBytes)
        
        let decompressed = MapTileLoader.decompressWithLibcompression(data: compressedData)
        #expect(decompressed != nil)
        if let decompressed = decompressed {
            let text = String(data: decompressed, encoding: .utf8)
            #expect(text == "Hello Mapbox 3D")
        }
    }
    
    @Test("Uncompressed data passthrough")
    func testDecompressGzipPassthrough() {
        let plainText = "Plain uncompressed data stream"
        let data = Data(plainText.utf8)
        
        let result = MapTileLoader.decompressGzip(data: data)
        #expect(result == data)
    }
    
    @Test("Corrupted GZIP header or payload rejection")
    func testDecompressGzipCorrupted() {
        // Starts with GZIP magic 0x1f 0x8b but followed by garbage
        let corruptBytes: [UInt8] = [0x1f, 0x8b, 0xff, 0xff, 0x00, 0x12, 0x34]
        let result = MapTileLoader.decompressGzip(data: Data(corruptBytes))
        #expect(result == nil)
    }
    
    @Test("Empty data processing returns empty CPUMeshData")
    func testProcessTileEmptyData() async {
        let loader = MapTileLoader()
        let coord = TileCoordinate(zoom: 15, x: 100, y: 100)
        let mesh = await loader.processTile(data: Data(), coordinate: coord, referenceLatitude: 60.0)
        
        #expect(mesh.vertices.isEmpty)
        #expect(mesh.indices.isEmpty)
    }
}
