#pragma once

#include <cstdint>
#include <cstddef>
#include <cstring>
#include <vector>
#include <array>
#include <string>

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
    std::vector<MapVertex> roadVertices;
    std::vector<uint32_t> roadIndices;

    size_t getVertexCount() const { return vertices.size(); }
    size_t getIndexCount() const { return indices.size(); }
    MapVertex getVertex(size_t i) const { return vertices[i]; }
    uint32_t getIndex(size_t i) const { return indices[i]; }

    size_t getRoadVertexCount() const { return roadVertices.size(); }
    size_t getRoadIndexCount() const { return roadIndices.size(); }
    MapVertex getRoadVertex(size_t i) const { return roadVertices[i]; }
    uint32_t getRoadIndex(size_t i) const { return roadIndices[i]; }
};

struct RoadLayerStyle {
    float widthMeters = 6.0f;
    float outlineRatio = 0.18f;
    float elevation = 0.05f;
    float r = 0.98f;
    float g = 0.98f;
    float b = 0.98f;
    float a = 1.0f;
    float outlineR = 0.55f;
    float outlineG = 0.55f;
    float outlineB = 0.60f;
    float outlineA = 1.0f;
};

struct RoadConfiguration {
    bool filterNonCarRoads = true;
    bool renderOnlyConfiguredClasses = true;
    bool hasDefaultStyle = false;
    RoadLayerStyle defaultStyle;

    std::vector<std::string> classes;
    std::vector<RoadLayerStyle> styles;

    void addStyle(const std::string& roadClass, const RoadLayerStyle& style) {
        for (size_t i = 0; i < classes.size(); ++i) {
            if (classes[i] == roadClass) {
                styles[i] = style;
                return;
            }
        }
        classes.push_back(roadClass);
        styles.push_back(style);
    }

    void clearStyles() {
        classes.clear();
        styles.clear();
    }

    size_t styleCount() const {
        return classes.size();
    }

    std::string getClass(size_t index) const {
        if (index < classes.size()) return classes[index];
        return "";
    }

    RoadLayerStyle getStyleByIndex(size_t index) const {
        if (index < styles.size()) return styles[index];
        return RoadLayerStyle{};
    }

    bool getStyle(const std::string& roadClass, RoadLayerStyle& outStyle) const {
        for (size_t i = 0; i < classes.size(); ++i) {
            if (classes[i] == roadClass) {
                outStyle = styles[i];
                return true;
            }
        }
        return false;
    }

    bool shouldRender(const std::string& roadClass, RoadLayerStyle& outStyle) const;

    static RoadConfiguration carOnly();
    static RoadConfiguration allRoads();
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

struct TileProcessorOptions {
    bool processBuildings = true;
    bool processWater = true;
    bool processLanduse = true;
    bool processRoads = true;
    bool generateRoadJunctionCaps = true;
    double defaultBuildingHeight = 10.0;
    double defaultBuildingMinHeight = 0.0;
    RoadConfiguration roadConfig = RoadConfiguration::carOnly();
    PolygonRing clipPolygon;
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

    /// Directly processes a polygon with optional holes, clipping against an arbitrary 2D polygon (e.g. H3 hexagon).
    static void processPolygon(
        const TestPolygonInput& input,
        double height,
        double minHeight,
        int extent,
        float tileGroundWidth,
        float tileGroundHeight,
        TileMeshResult& outResult,
        bool isWater,
        const PolygonRing& clipPolygon
    );

    /// Directly clips an existing TileMeshResult against a 2D convex polygon.
    static TileMeshResult clipTileMesh(
        const TileMeshResult& inMesh,
        const PolygonRing& clipPolygon
    );

    /// Helper to create an in-memory MVT vector tile protobuf containing a test polygon building.
    static DecompressionResult createTestTile(
        const std::string& layerName,
        const PolygonRing& outerRing,
        double height,
        double minHeight
    );

    /// Helper to create an in-memory MVT vector tile protobuf containing a test road linestring.
    static DecompressionResult createTestRoadTile(
        const std::string& layerName,
        const PolygonRing& linePoints,
        const std::string& roadClass,
        bool generateCaps = false
    );
};

} // namespace AcornMap
