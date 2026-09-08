#pragma once

#include <cstdint>
#include <cstddef>
#include <cstring>
#include <vector>
#include <array>
#include <utility>

namespace AcornMap {

struct MapVertex {
    float x = 0.0f;
    float y = 0.0f;
    float z = 0.0f;
    float nx = 0.0f;
    float ny = 1.0f;
    float nz = 0.0f;
    float r = 1.0f;
    float g = 1.0f;
    float b = 1.0f;
    float a = 1.0f;
    float u = 0.0f;
    float v = 0.0f;
};

struct TileMeshResult {
    std::vector<MapVertex> vertices;
    std::vector<uint32_t> indices;

    size_t getVertexCount() const { return vertices.size(); }
    size_t getIndexCount() const { return indices.size(); }
    MapVertex getVertex(size_t i) const { return vertices[i]; }
    uint32_t getIndex(size_t i) const { return indices[i]; }
};

struct TileProcessorOptions {
    bool processBuildings = true;
    bool processWater = true;
    bool processLanduse = true;
    double defaultBuildingHeight = 10.0;
    double defaultBuildingMinHeight = 0.0;
};

struct DecompressionResult {
    std::vector<uint8_t> data;
    bool success = false;

    size_t size() const { return data.size(); }
    void copyTo(uint8_t* dest) const {
        if (dest && !data.empty()) {
            std::memcpy(dest, data.data(), data.size());
        }
    }
};

struct PolygonPoint {
    double x = 0.0;
    double y = 0.0;
};

struct PolygonRing {
    std::vector<PolygonPoint> points;

    void addPoint(double x, double y) {
        points.push_back(PolygonPoint{x, y});
    }

    size_t size() const { return points.size(); }
    PolygonPoint getPoint(size_t i) const { return points[i]; }
};

struct TestPolygonInput {
    std::vector<PolygonRing> rings;

    void addRing(const PolygonRing& ring) {
        rings.push_back(ring);
    }

    size_t size() const { return rings.size(); }
    PolygonRing getRing(size_t i) const { return rings[i]; }
};

class MapboxTileProcessor {
public:
    /// Decompresses GZIP-compressed data (or passes through uncompressed data).
    static DecompressionResult decompressGzip(const uint8_t* inData, size_t inLength);

    /// Processes a vector tile with default options.
    static TileMeshResult processTile(
        const uint8_t* data,
        size_t length,
        float tileGroundWidth,
        float tileGroundHeight
    );

    /// Processes a vector tile (compressed or uncompressed MVT bytes) and generates triangulated 3D meshes.
    static TileMeshResult processTile(
        const uint8_t* data,
        size_t length,
        float tileGroundWidth,
        float tileGroundHeight,
        const TileProcessorOptions& options
    );

    /// Directly processes a polygon with optional holes using TestPolygonInput.
    static void processPolygon(
        const TestPolygonInput& input,
        double height,
        double minHeight,
        int extent,
        float tileGroundWidth,
        float tileGroundHeight,
        TileMeshResult& outResult,
        bool isWater
    );

    /// Helper to create an in-memory MVT vector tile protobuf containing a test polygon building.
    static DecompressionResult createTestTile(
        const std::string& layerName,
        const PolygonRing& outerRing,
        double height,
        double minHeight
    );
};

} // namespace AcornMap
