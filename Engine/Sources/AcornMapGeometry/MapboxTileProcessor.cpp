#include "MapboxTileProcessor.hpp"

#include <mapbox/earcut.hpp>
#include <clipper2/clipper.h>
#include <vtzero/vector_tile.hpp>
#include <vtzero/builder.hpp>

#include <zlib.h>
#include <cmath>
#include <algorithm>
#include <string>
#include <sstream>
#include <iostream>
#include <unordered_set>

namespace AcornMap {

namespace {

// MARK: - GZIP Decompression

bool decompressGzipIfNeeded(const uint8_t* inData, size_t inLength, std::vector<uint8_t>& outData) {
    if (inLength < 2) return false;

    // Check GZIP magic bytes: 0x1f, 0x8b
    if (inData[0] != 0x1f || inData[1] != 0x8b) {
        outData.assign(inData, inData + inLength);
        return true;
    }

    z_stream stream{};
    stream.next_in = const_cast<Bytef*>(reinterpret_cast<const Bytef*>(inData));
    stream.avail_in = static_cast<uInt>(inLength);

    // 32 + MAX_WBITS enables automatic detection and decoding of GZIP or ZLIB header
    if (inflateInit2(&stream, 32 + MAX_WBITS) != Z_OK) {
        return false;
    }

    outData.resize(inLength * 4);
    stream.next_out = reinterpret_cast<Bytef*>(outData.data());
    stream.avail_out = static_cast<uInt>(outData.size());

    int ret = Z_OK;
    while (ret == Z_OK) {
        if (stream.avail_out == 0) {
            size_t oldSize = outData.size();
            outData.resize(oldSize * 2);
            stream.next_out = reinterpret_cast<Bytef*>(outData.data() + oldSize);
            stream.avail_out = static_cast<uInt>(oldSize);
        }
        ret = inflate(&stream, Z_NO_FLUSH);
    }

    if (ret != Z_STREAM_END) {
        inflateEnd(&stream);
        return false;
    }

    outData.resize(stream.total_out);
    inflateEnd(&stream);
    return true;
}

// MARK: - Property Extraction

double extractDouble(const vtzero::property_value& val, double defaultVal) {
    switch (val.type()) {
        case vtzero::property_value_type::float_value:
            return static_cast<double>(val.float_value());
        case vtzero::property_value_type::double_value:
            return val.double_value();
        case vtzero::property_value_type::int_value:
            return static_cast<double>(val.int_value());
        case vtzero::property_value_type::uint_value:
            return static_cast<double>(val.uint_value());
        case vtzero::property_value_type::sint_value:
            return static_cast<double>(val.sint_value());
        case vtzero::property_value_type::string_value: {
            try {
                std::string s(val.string_value());
                return std::stod(s);
            } catch (...) {
                return defaultVal;
            }
        }
        default:
            return defaultVal;
    }
}

bool extractBool(const vtzero::property_value& val, bool defaultVal) {
    if (val.type() == vtzero::property_value_type::bool_value) {
        return val.bool_value();
    }
    if (val.type() == vtzero::property_value_type::string_value) {
        std::string s(val.string_value());
        if (s == "true" || s == "yes" || s == "1") return true;
        if (s == "false" || s == "no" || s == "0") return false;
    }
    if (val.type() == vtzero::property_value_type::int_value ||
        val.type() == vtzero::property_value_type::uint_value ||
        val.type() == vtzero::property_value_type::sint_value) {
        return val.int_value() != 0;
    }
    return defaultVal;
}

// MARK: - Geometry Decoding Handler

struct VtzeroPolygonHandler {
    struct PolygonEntry {
        std::vector<vtzero::point> outer;
        std::vector<std::vector<vtzero::point>> holes;
    };
    std::vector<PolygonEntry> polygons;
    std::vector<vtzero::point> currentRing;

    void ring_begin(uint32_t count) {
        currentRing.clear();
        currentRing.reserve(count);
    }

    void ring_point(vtzero::point p) {
        currentRing.push_back(p);
    }

    void ring_end(vtzero::ring_type type) {
        if (type == vtzero::ring_type::outer) {
            PolygonEntry entry;
            entry.outer = std::move(currentRing);
            polygons.push_back(std::move(entry));
        } else if (type == vtzero::ring_type::inner) {
            if (!polygons.empty()) {
                polygons.back().holes.push_back(std::move(currentRing));
            }
        }
        currentRing.clear();
    }
};

struct Point2D {
    double x;
    double y;
};

// MARK: - Triangulation and Extrusion Engine

void triangulateAndExtrudePolygon(
    const std::vector<Point2D>& outer,
    const std::vector<std::vector<Point2D>>& holes,
    double height,
    double minHeight,
    int extent,
    float tileGroundWidth,
    float tileGroundHeight,
    TileMeshResult& outResult,
    bool isSurface,
    const std::array<float, 4>& wallColor,
    const std::array<float, 4>& roofColor
) {
    if (outer.size() < 3) return;

    using EarcutPoint = std::array<double, 2>;
    std::vector<std::vector<EarcutPoint>> earcutInput;

    // 1. Prepare outer ring
    std::vector<EarcutPoint> outerRing;
    outerRing.reserve(outer.size());
    for (size_t i = 0; i < outer.size(); ++i) {
        // Strip duplicate closing vertex if present
        if (i == outer.size() - 1 && outer.size() > 1 &&
            outer[i].x == outer[0].x && outer[i].y == outer[0].y) {
            continue;
        }
        outerRing.push_back({outer[i].x, outer[i].y});
    }
    if (outerRing.size() < 3) return;
    earcutInput.push_back(std::move(outerRing));

    // 2. Prepare holes
    for (const auto& hole : holes) {
        std::vector<EarcutPoint> holeRing;
        holeRing.reserve(hole.size());
        for (size_t i = 0; i < hole.size(); ++i) {
            if (i == hole.size() - 1 && hole.size() > 1 &&
                hole[i].x == hole[0].x && hole[i].y == hole[0].y) {
                continue;
            }
            holeRing.push_back({hole[i].x, hole[i].y});
        }
        if (holeRing.size() >= 3) {
            earcutInput.push_back(std::move(holeRing));
        }
    }

    // 3. Triangulate with earcut.hpp
    std::vector<uint32_t> triIndices = mapbox::earcut<uint32_t>(earcutInput);
    if (triIndices.empty()) return;

    // 4. Generate roof (or water/ground) mesh vertices
    uint32_t baseVertexIndex = static_cast<uint32_t>(outResult.vertices.size());
    float roofY = static_cast<float>(height);
    float groundY = static_cast<float>(minHeight);
    float targetY = isSurface ? 0.0f : roofY;

    for (const auto& ring : earcutInput) {
        for (const auto& pt : ring) {
            MapVertex v;
            v.x = static_cast<float>(pt[0] / static_cast<double>(extent) * tileGroundWidth);
            v.y = targetY;
            v.z = static_cast<float>(pt[1] / static_cast<double>(extent) * tileGroundHeight);
            v.nx = 0.0f;
            v.ny = 1.0f; // Upward normal
            v.nz = 0.0f;
            v.r = roofColor[0];
            v.g = roofColor[1];
            v.b = roofColor[2];
            v.a = roofColor[3];
            v.u = static_cast<float>(pt[0] / static_cast<double>(extent));
            v.v = static_cast<float>(pt[1] / static_cast<double>(extent));
            outResult.vertices.push_back(v);
        }
    }

    // 5. Add roof/surface triangle indices with upward winding guarantee
    for (size_t i = 0; i < triIndices.size(); i += 3) {
        uint32_t idx0 = baseVertexIndex + triIndices[i];
        uint32_t idx1 = baseVertexIndex + triIndices[i + 1];
        uint32_t idx2 = baseVertexIndex + triIndices[i + 2];

        const auto& p0 = outResult.vertices[idx0];
        const auto& p1 = outResult.vertices[idx1];
        const auto& p2 = outResult.vertices[idx2];

        // Normal y cross-product: (p1.z - p0.z)*(p2.x - p0.x) - (p1.x - p0.x)*(p2.z - p0.z)
        float ny = (p1.z - p0.z) * (p2.x - p0.x) - (p1.x - p0.x) * (p2.z - p0.z);
        if (ny > 0.0f) {
            outResult.indices.push_back(idx0);
            outResult.indices.push_back(idx1);
            outResult.indices.push_back(idx2);
        } else {
            outResult.indices.push_back(idx0);
            outResult.indices.push_back(idx2);
            outResult.indices.push_back(idx1);
        }
    }

    // 6. Extrude walls (for 3D buildings)
    if (isSurface || height <= minHeight) {
        return;
    }

    const double seamEps = 0.5;

    for (const auto& ring : earcutInput) {
        size_t n = ring.size();
        if (n < 3) continue;

        // Compute ring signed area to determine winding
        double signedArea = 0.0;
        for (size_t i = 0; i < n; ++i) {
            size_t next = (i + 1) % n;
            signedArea += ring[i][0] * ring[next][1] - ring[next][0] * ring[i][1];
        }

        for (size_t i = 0; i < n; ++i) {
            size_t next = (i + 1) % n;
            double x1 = ring[i][0], y1 = ring[i][1];
            double x2 = ring[next][0], y2 = ring[next][1];

            // TILE SEAM WALL SUPPRESSION:
            // If the edge lies directly on any tile boundary [0, extent], suppress wall generation!
            bool isSeam = (x1 <= seamEps && x2 <= seamEps) ||
                          (x1 >= extent - seamEps && x2 >= extent - seamEps) ||
                          (y1 <= seamEps && y2 <= seamEps) ||
                          (y1 >= extent - seamEps && y2 >= extent - seamEps);

            if (isSeam) {
                continue; // Suppress internal partition wall
            }

            float mx1 = static_cast<float>(x1 / static_cast<double>(extent) * tileGroundWidth);
            float mz1 = static_cast<float>(y1 / static_cast<double>(extent) * tileGroundHeight);
            float mx2 = static_cast<float>(x2 / static_cast<double>(extent) * tileGroundWidth);
            float mz2 = static_cast<float>(y2 / static_cast<double>(extent) * tileGroundHeight);

            float dx = mx2 - mx1;
            float dz = mz2 - mz1;
            float len = std::sqrt(dx * dx + dz * dz);
            if (len < 1e-4f) continue;

            // Outward normal:
            // For signedArea > 0: normal is (dz, -dx) / len
            // For signedArea < 0: normal is (-dz, dx) / len
            float nx = (signedArea > 0.0) ? (dz / len) : (-dz / len);
            float nz = (signedArea > 0.0) ? (-dx / len) : (dx / len);

            uint32_t wBase = static_cast<uint32_t>(outResult.vertices.size());

            MapVertex vBot1{mx1, groundY, mz1, nx, 0.0f, nz, wallColor[0], wallColor[1], wallColor[2], wallColor[3], 0.0f, 0.0f};
            MapVertex vBot2{mx2, groundY, mz2, nx, 0.0f, nz, wallColor[0], wallColor[1], wallColor[2], wallColor[3], 1.0f, 0.0f};
            MapVertex vTop2{mx2, roofY, mz2, nx, 0.0f, nz, wallColor[0], wallColor[1], wallColor[2], wallColor[3], 1.0f, 1.0f};
            MapVertex vTop1{mx1, roofY, mz1, nx, 0.0f, nz, wallColor[0], wallColor[1], wallColor[2], wallColor[3], 0.0f, 1.0f};

            outResult.vertices.push_back(vBot1);
            outResult.vertices.push_back(vBot2);
            outResult.vertices.push_back(vTop2);
            outResult.vertices.push_back(vTop1);

            // Verify triangle 1 normal orientation against (nx, 0, nz)
            // e1 = vBot2 - vBot1 = (dx, 0, dz)
            // e2 = vTop2 - vBot1 = (dx, dy, dz)
            // cross = (-dz * dy, 0, dx * dy)
            float cx = -dz * (roofY - groundY);
            float cz = dx * (roofY - groundY);
            float dotN = cx * nx + cz * nz;

            if (dotN > 0.0f) {
                outResult.indices.push_back(wBase + 0); // vBot1
                outResult.indices.push_back(wBase + 1); // vBot2
                outResult.indices.push_back(wBase + 2); // vTop2

                outResult.indices.push_back(wBase + 0); // vBot1
                outResult.indices.push_back(wBase + 2); // vTop2
                outResult.indices.push_back(wBase + 3); // vTop1
            } else {
                outResult.indices.push_back(wBase + 0); // vBot1
                outResult.indices.push_back(wBase + 2); // vTop2
                outResult.indices.push_back(wBase + 1); // vBot2

                outResult.indices.push_back(wBase + 0); // vBot1
                outResult.indices.push_back(wBase + 3); // vTop1
                outResult.indices.push_back(wBase + 2); // vTop2
            }
        }
    }
}

// MARK: - Multi-Tier Clipping Pipeline

void clipAndProcessPolygon(
    const std::vector<Point2D>& outer,
    const std::vector<std::vector<Point2D>>& holes,
    double height,
    double minHeight,
    int extent,
    float tileGroundWidth,
    float tileGroundHeight,
    TileMeshResult& outResult,
    bool isSurface,
    const std::array<float, 4>& wallColor,
    const std::array<float, 4>& roofColor
) {
    if (outer.empty()) return;

    // Compute AABB of outer ring
    double minX = outer[0].x, maxX = outer[0].x;
    double minY = outer[0].y, maxY = outer[0].y;
    for (const auto& pt : outer) {
        minX = std::min(minX, pt.x);
        maxX = std::max(maxX, pt.x);
        minY = std::min(minY, pt.y);
        maxY = std::max(maxY, pt.y);
    }

    // Fully outside tile bounds: discard
    if (maxX < 0 || minX > extent || maxY < 0 || minY > extent) {
        return;
    }

    // Tier 1: Fully inside tile bounds: bypass clipping!
    if (minX >= 0 && maxX <= extent && minY >= 0 && maxY <= extent) {
        triangulateAndExtrudePolygon(
            outer, holes, height, minHeight, extent,
            tileGroundWidth, tileGroundHeight, outResult,
            isSurface, wallColor, roofColor
        );
        return;
    }

    // Tier 2: Intersects tile boundary with NO holes (fast path using RectClip64)
    if (holes.empty()) {
        Clipper2Lib::Rect64 clipRect(0, 0, extent, extent);
        Clipper2Lib::Path64 path;
        path.reserve(outer.size());
        for (const auto& pt : outer) {
            path.emplace_back(static_cast<int64_t>(std::round(pt.x)), static_cast<int64_t>(std::round(pt.y)));
        }

        Clipper2Lib::RectClip64 rectClip(clipRect);
        Clipper2Lib::Paths64 inPaths = { path };
        Clipper2Lib::Paths64 clipped = rectClip.Execute(inPaths);

        for (const auto& cpath : clipped) {
            if (cpath.size() < 3) continue;
            std::vector<Point2D> clippedOuter;
            clippedOuter.reserve(cpath.size());
            for (const auto& cpt : cpath) {
                clippedOuter.push_back({static_cast<double>(cpt.x), static_cast<double>(cpt.y)});
            }
            triangulateAndExtrudePolygon(
                clippedOuter, {}, height, minHeight, extent,
                tileGroundWidth, tileGroundHeight, outResult,
                isSurface, wallColor, roofColor
            );
        }
        return;
    }

    // Tier 3: Intersects tile boundary WITH holes (robust path using Clipper64 + PolyTree64)
    Clipper2Lib::Clipper64 clipper;
    Clipper2Lib::Paths64 subjects;
    Clipper2Lib::Path64 outerPath;
    outerPath.reserve(outer.size());
    for (const auto& pt : outer) {
        outerPath.emplace_back(static_cast<int64_t>(std::round(pt.x)), static_cast<int64_t>(std::round(pt.y)));
    }
    subjects.push_back(std::move(outerPath));

    for (const auto& hole : holes) {
        Clipper2Lib::Path64 holePath;
        holePath.reserve(hole.size());
        for (const auto& pt : hole) {
            holePath.emplace_back(static_cast<int64_t>(std::round(pt.x)), static_cast<int64_t>(std::round(pt.y)));
        }
        subjects.push_back(std::move(holePath));
    }
    clipper.AddSubject(subjects);

    Clipper2Lib::Rect64 clipRect(0, 0, extent, extent);
    clipper.AddClip(Clipper2Lib::Paths64{ clipRect.AsPath() });

    Clipper2Lib::PolyTree64 polyTree;
    clipper.Execute(Clipper2Lib::ClipType::Intersection, Clipper2Lib::FillRule::EvenOdd, polyTree);

    auto extractPolyTree = [&](auto& self, const Clipper2Lib::PolyPath64* node) -> void {
        for (size_t i = 0; i < node->Count(); ++i) {
            const auto* child = node->Child(i);
            if (!child->Polygon().empty()) {
                std::vector<Point2D> clippedOuter;
                clippedOuter.reserve(child->Polygon().size());
                for (const auto& pt : child->Polygon()) {
                    clippedOuter.push_back({static_cast<double>(pt.x), static_cast<double>(pt.y)});
                }

                std::vector<std::vector<Point2D>> clippedHoles;
                for (size_t j = 0; j < child->Count(); ++j) {
                    const auto* holeChild = child->Child(j);
                    if (!holeChild->Polygon().empty()) {
                        std::vector<Point2D> clippedHole;
                        clippedHole.reserve(holeChild->Polygon().size());
                        for (const auto& pt : holeChild->Polygon()) {
                            clippedHole.push_back({static_cast<double>(pt.x), static_cast<double>(pt.y)});
                        }
                        clippedHoles.push_back(std::move(clippedHole));

                        // If holeChild has nested islands, recurse for them
                        self(self, holeChild);
                    }
                }

                triangulateAndExtrudePolygon(
                    clippedOuter, clippedHoles, height, minHeight, extent,
                    tileGroundWidth, tileGroundHeight, outResult,
                    isSurface, wallColor, roofColor
                );
            }
        }
    };

    extractPolyTree(extractPolyTree, &polyTree);
}

// MARK: - Road Processing

struct VtzeroLineHandler {
    std::vector<std::vector<vtzero::point>> lines;
    std::vector<vtzero::point> currentLine;

    void linestring_begin(uint32_t count) {
        currentLine.clear();
        currentLine.reserve(count);
    }
    void linestring_point(vtzero::point p) {
        currentLine.push_back(p);
    }
    void linestring_end() {
        if (currentLine.size() >= 2) {
            lines.push_back(std::move(currentLine));
        }
        currentLine.clear();
    }
};

void addJunctionCap(
    const Point2D& center,
    const RoadLayerStyle& style,
    TileMeshResult& outResult
) {
    constexpr int M = 8;
    uint32_t centerIdx = static_cast<uint32_t>(outResult.roadVertices.size());

    // Center vertex (u = 0.0)
    MapVertex vCenter;
    vCenter.x = static_cast<float>(center.x);
    vCenter.y = style.elevation;
    vCenter.z = static_cast<float>(center.y);
    vCenter.nx = 0.0f;
    vCenter.ny = style.widthMeters;
    vCenter.nz = 0.0f;
    vCenter.r = style.r;
    vCenter.g = style.g;
    vCenter.b = style.b;
    vCenter.a = style.a;
    vCenter.u = 0.0f;
    vCenter.v = style.outlineRatio;
    outResult.roadVertices.push_back(vCenter);

    // Perimeter vertices (u = 1.0, radial direction in nx, nz)
    uint32_t perimStart = static_cast<uint32_t>(outResult.roadVertices.size());
    for (int k = 0; k < M; ++k) {
        double angle = 2.0 * 3.14159265358979323846 * k / M;
        float nx = static_cast<float>(std::cos(angle));
        float nz = static_cast<float>(std::sin(angle));

        MapVertex vPerim;
        vPerim.x = static_cast<float>(center.x);
        vPerim.y = style.elevation;
        vPerim.z = static_cast<float>(center.y);
        vPerim.nx = nx;
        vPerim.ny = style.widthMeters;
        vPerim.nz = nz;
        vPerim.r = style.r;
        vPerim.g = style.g;
        vPerim.b = style.b;
        vPerim.a = style.a;
        vPerim.u = 1.0f;
        vPerim.v = style.outlineRatio;
        outResult.roadVertices.push_back(vPerim);
    }

    // Fan triangles: centerIdx -> perimStart + k -> perimStart + (k+1)%M
    for (int k = 0; k < M; ++k) {
        outResult.roadIndices.push_back(centerIdx);
        outResult.roadIndices.push_back(perimStart + k);
        outResult.roadIndices.push_back(perimStart + ((k + 1) % M));
    }
}

void processRoadLineString(
    const std::vector<vtzero::point>& line,
    const RoadLayerStyle& style,
    int extent,
    float tileGroundWidth,
    float tileGroundHeight,
    TileMeshResult& outResult,
    bool generateJunctionCaps = true
) {
    if (line.size() < 2) return;

    std::vector<Point2D> pts;
    pts.reserve(line.size());
    for (const auto& p : line) {
        double mx = p.x / static_cast<double>(extent) * tileGroundWidth;
        double mz = p.y / static_cast<double>(extent) * tileGroundHeight;
        if (!pts.empty()) {
            double dx = mx - pts.back().x;
            double dz = mz - pts.back().y;
            if (dx * dx + dz * dz < 1e-4) {
                continue;
            }
        }
        pts.push_back({mx, mz});
    }

    if (pts.size() < 2) return;

    size_t n = pts.size();
    uint32_t baseVertex = static_cast<uint32_t>(outResult.roadVertices.size());

    struct MiterPoint {
        double nx = 0.0;
        double nz = 0.0;
        double miterScale = 1.0;
    };
    std::vector<MiterPoint> miters(n);

    std::vector<Point2D> segNormals(n - 1);
    for (size_t i = 0; i < n - 1; ++i) {
        double dx = pts[i + 1].x - pts[i].x;
        double dz = pts[i + 1].y - pts[i].y;
        double len = std::sqrt(dx * dx + dz * dz);
        if (len > 1e-6) {
            segNormals[i] = {-dz / len, dx / len};
        } else {
            segNormals[i] = {0.0, 1.0};
        }
    }

    miters[0].nx = segNormals[0].x;
    miters[0].nz = segNormals[0].y;
    miters[0].miterScale = 1.0;

    miters[n - 1].nx = segNormals[n - 2].x;
    miters[n - 1].nz = segNormals[n - 2].y;
    miters[n - 1].miterScale = 1.0;

    for (size_t i = 1; i < n - 1; ++i) {
        double sx = segNormals[i - 1].x + segNormals[i].x;
        double sz = segNormals[i - 1].y + segNormals[i].y;
        double slen = std::sqrt(sx * sx + sz * sz);
        if (slen < 1e-4) {
            miters[i].nx = segNormals[i].x;
            miters[i].nz = segNormals[i].y;
            miters[i].miterScale = 1.0;
        } else {
            double mx = sx / slen;
            double mz = sz / slen;
            double cosA = mx * segNormals[i - 1].x + mz * segNormals[i - 1].y;
            double mScale = (cosA > 0.35) ? (1.0 / cosA) : 2.0;
            miters[i].nx = mx;
            miters[i].nz = mz;
            miters[i].miterScale = std::min(mScale, 2.0);
        }
    }

    float roadY = style.elevation;

    for (size_t i = 0; i < n; ++i) {
        float effectiveWidth = style.widthMeters * static_cast<float>(miters[i].miterScale);

        // Left vertex (u = -1.0)
        MapVertex vLeft;
        vLeft.x = static_cast<float>(pts[i].x);
        vLeft.y = roadY;
        vLeft.z = static_cast<float>(pts[i].y);
        vLeft.nx = static_cast<float>(miters[i].nx);
        vLeft.ny = effectiveWidth;
        vLeft.nz = static_cast<float>(miters[i].nz);
        vLeft.r = style.r;
        vLeft.g = style.g;
        vLeft.b = style.b;
        vLeft.a = style.a;
        vLeft.u = -1.0f;
        vLeft.v = style.outlineRatio;
        outResult.roadVertices.push_back(vLeft);

        // Right vertex (u = +1.0)
        MapVertex vRight;
        vRight.x = static_cast<float>(pts[i].x);
        vRight.y = roadY;
        vRight.z = static_cast<float>(pts[i].y);
        vRight.nx = static_cast<float>(miters[i].nx);
        vRight.ny = effectiveWidth;
        vRight.nz = static_cast<float>(miters[i].nz);
        vRight.r = style.r;
        vRight.g = style.g;
        vRight.b = style.b;
        vRight.a = style.a;
        vRight.u = 1.0f;
        vRight.v = style.outlineRatio;
        outResult.roadVertices.push_back(vRight);
    }

    for (size_t i = 0; i < n - 1; ++i) {
        uint32_t i0 = baseVertex + static_cast<uint32_t>(2 * i);
        uint32_t i1 = baseVertex + static_cast<uint32_t>(2 * i + 1);
        uint32_t i2 = baseVertex + static_cast<uint32_t>(2 * (i + 1) + 1);
        uint32_t i3 = baseVertex + static_cast<uint32_t>(2 * (i + 1));

        // Triangle 1: i0 -> i1 -> i2
        outResult.roadIndices.push_back(i0);
        outResult.roadIndices.push_back(i1);
        outResult.roadIndices.push_back(i2);

        // Triangle 2: i0 -> i2 -> i3
        outResult.roadIndices.push_back(i0);
        outResult.roadIndices.push_back(i2);
        outResult.roadIndices.push_back(i3);
    }

    if (generateJunctionCaps) {
        addJunctionCap(pts.front(), style, outResult);
        addJunctionCap(pts.back(), style, outResult);
    }
}

} // anonymous namespace

// MARK: - Road Configuration Implementation

bool RoadConfiguration::shouldRender(const std::string& roadClass, RoadLayerStyle& outStyle) const {
    if (filterNonCarRoads) {
        static const std::unordered_set<std::string> nonCarClasses = {
            "pedestrian", "path", "cycleway", "footway", "steps",
            "track", "bridleway", "corridor", "sidewalk", "crossing",
            "ferry", "aerialway", "golf_cart"
        };
        if (nonCarClasses.find(roadClass) != nonCarClasses.end()) {
            return false;
        }
    }

    if (getStyle(roadClass, outStyle)) {
        return true;
    }

    if (!renderOnlyConfiguredClasses && hasDefaultStyle) {
        outStyle = defaultStyle;
        return true;
    }

    return false;
}

RoadConfiguration RoadConfiguration::carOnly() {
    RoadConfiguration config;
    config.filterNonCarRoads = true;
    config.renderOnlyConfiguredClasses = true;
    config.hasDefaultStyle = false;

    // Motorway
    config.addStyle("motorway", {14.0f, 0.18f, 0.10f, 0.98f, 0.70f, 0.35f, 1.0f, 0.45f, 0.30f, 0.15f, 1.0f});
    config.addStyle("motorway_link", {14.0f, 0.18f, 0.10f, 0.98f, 0.70f, 0.35f, 1.0f, 0.45f, 0.30f, 0.15f, 1.0f});

    // Trunk
    config.addStyle("trunk", {12.0f, 0.18f, 0.09f, 0.98f, 0.78f, 0.40f, 1.0f, 0.50f, 0.35f, 0.20f, 1.0f});
    config.addStyle("trunk_link", {12.0f, 0.18f, 0.09f, 0.98f, 0.78f, 0.40f, 1.0f, 0.50f, 0.35f, 0.20f, 1.0f});

    // Primary
    config.addStyle("primary", {10.5f, 0.18f, 0.08f, 0.99f, 0.88f, 0.55f, 1.0f, 0.55f, 0.45f, 0.25f, 1.0f});
    config.addStyle("primary_link", {10.5f, 0.18f, 0.08f, 0.99f, 0.88f, 0.55f, 1.0f, 0.55f, 0.45f, 0.25f, 1.0f});

    // Secondary
    config.addStyle("secondary", {8.5f, 0.18f, 0.07f, 0.96f, 0.95f, 0.88f, 1.0f, 0.50f, 0.50f, 0.52f, 1.0f});
    config.addStyle("secondary_link", {8.5f, 0.18f, 0.07f, 0.96f, 0.95f, 0.88f, 1.0f, 0.50f, 0.50f, 0.52f, 1.0f});

    // Tertiary
    config.addStyle("tertiary", {7.0f, 0.18f, 0.06f, 0.93f, 0.93f, 0.93f, 1.0f, 0.55f, 0.55f, 0.58f, 1.0f});
    config.addStyle("tertiary_link", {7.0f, 0.18f, 0.06f, 0.93f, 0.93f, 0.93f, 1.0f, 0.55f, 0.55f, 0.58f, 1.0f});

    // Residential and streets
    config.addStyle("street", {6.0f, 0.18f, 0.05f, 0.98f, 0.98f, 0.98f, 1.0f, 0.55f, 0.55f, 0.60f, 1.0f});
    config.addStyle("residential", {6.0f, 0.18f, 0.05f, 0.98f, 0.98f, 0.98f, 1.0f, 0.55f, 0.55f, 0.60f, 1.0f});
    config.addStyle("street_limited", {6.0f, 0.18f, 0.05f, 0.98f, 0.98f, 0.98f, 1.0f, 0.55f, 0.55f, 0.60f, 1.0f});
    config.addStyle("living_street", {6.0f, 0.18f, 0.05f, 0.98f, 0.98f, 0.98f, 1.0f, 0.55f, 0.55f, 0.60f, 1.0f});

    // Service, driveway, alley
    config.addStyle("service", {4.5f, 0.20f, 0.045f, 0.88f, 0.88f, 0.88f, 1.0f, 0.60f, 0.60f, 0.62f, 1.0f});
    config.addStyle("driveway", {4.5f, 0.20f, 0.045f, 0.88f, 0.88f, 0.88f, 1.0f, 0.60f, 0.60f, 0.62f, 1.0f});
    config.addStyle("alley", {4.5f, 0.20f, 0.045f, 0.88f, 0.88f, 0.88f, 1.0f, 0.60f, 0.60f, 0.62f, 1.0f});

    return config;
}

RoadConfiguration RoadConfiguration::allRoads() {
    RoadConfiguration config = carOnly();
    config.filterNonCarRoads = false;
    config.renderOnlyConfiguredClasses = false;
    config.hasDefaultStyle = true;
    config.defaultStyle = {5.5f, 0.18f, 0.05f, 0.92f, 0.92f, 0.92f, 1.0f, 0.55f, 0.55f, 0.58f, 1.0f};

    // Non-car layers
    config.addStyle("pedestrian", {4.0f, 0.22f, 0.04f, 0.85f, 0.82f, 0.78f, 1.0f, 0.60f, 0.58f, 0.55f, 1.0f});
    config.addStyle("path", {3.0f, 0.22f, 0.04f, 0.85f, 0.82f, 0.78f, 1.0f, 0.60f, 0.58f, 0.55f, 1.0f});
    config.addStyle("cycleway", {3.0f, 0.20f, 0.04f, 0.80f, 0.85f, 0.82f, 1.0f, 0.50f, 0.58f, 0.55f, 1.0f});
    config.addStyle("footway", {2.5f, 0.22f, 0.04f, 0.85f, 0.82f, 0.78f, 1.0f, 0.60f, 0.58f, 0.55f, 1.0f});
    config.addStyle("steps", {2.5f, 0.25f, 0.04f, 0.82f, 0.80f, 0.80f, 1.0f, 0.55f, 0.55f, 0.55f, 1.0f});
    config.addStyle("track", {3.5f, 0.22f, 0.04f, 0.82f, 0.78f, 0.72f, 1.0f, 0.58f, 0.54f, 0.50f, 1.0f});

    return config;
}

// MARK: - Public API

DecompressionResult MapboxTileProcessor::decompressGzip(const uint8_t* inData, size_t inLength) {
    DecompressionResult res;
    res.success = decompressGzipIfNeeded(inData, inLength, res.data);
    return res;
}

TileMeshResult MapboxTileProcessor::processTile(
    const uint8_t* data,
    size_t length,
    float tileGroundWidth,
    float tileGroundHeight
) {
    return processTile(data, length, tileGroundWidth, tileGroundHeight, TileProcessorOptions{});
}

void MapboxTileProcessor::processPolygon(
    const TestPolygonInput& input,
    double height,
    double minHeight,
    int extent,
    float tileGroundWidth,
    float tileGroundHeight,
    TileMeshResult& outResult,
    bool isWater
) {
    if (input.rings.empty()) return;

    std::vector<Point2D> outer;
    outer.reserve(input.rings[0].points.size());
    for (const auto& pt : input.rings[0].points) {
        outer.push_back({pt.x, pt.y});
    }

    std::vector<std::vector<Point2D>> holes;
    for (size_t i = 1; i < input.rings.size(); ++i) {
        std::vector<Point2D> hole;
        hole.reserve(input.rings[i].points.size());
        for (const auto& pt : input.rings[i].points) {
            hole.push_back({pt.x, pt.y});
        }
        holes.push_back(std::move(hole));
    }

    std::array<float, 4> wallColor = {0.85f, 0.85f, 0.88f, 1.0f};
    std::array<float, 4> roofColor = isWater ? std::array<float, 4>{0.18f, 0.45f, 0.72f, 1.0f} : std::array<float, 4>{0.75f, 0.75f, 0.78f, 1.0f};

    clipAndProcessPolygon(
        outer, holes, height, minHeight, extent,
        tileGroundWidth, tileGroundHeight, outResult,
        isWater, wallColor, roofColor
    );
}

TileMeshResult MapboxTileProcessor::processTile(
    const uint8_t* data,
    size_t length,
    float tileGroundWidth,
    float tileGroundHeight,
    const TileProcessorOptions& options
) {
    TileMeshResult result;
    if (!data || length == 0) return result;

    std::vector<uint8_t> uncompressed;
    if (!decompressGzipIfNeeded(data, length, uncompressed)) {
        return result;
    }

    try {
        vtzero::vector_tile tile(reinterpret_cast<const char*>(uncompressed.data()), uncompressed.size());

        while (auto layer = tile.next_layer()) {
            std::string layerName(layer.name());
            int extent = static_cast<int>(layer.extent());
            if (extent <= 0) extent = 4096;

            bool isBuilding = (layerName == "building" || layerName == "building:part" || layerName == "buildings");
            bool isWater = (layerName == "water" || layerName == "waterway" || layerName == "ocean" || layerName == "lake");
            bool isLanduse = (layerName == "landuse" || layerName == "landcover" || layerName == "earth");
            bool isRoad = (layerName == "road" || layerName == "roads" || layerName == "transportation");

            if (isBuilding && !options.processBuildings) continue;
            if (isWater && !options.processWater) continue;
            if (isLanduse && !options.processLanduse) continue;
            if (isRoad && !options.processRoads) continue;
            if (!isBuilding && !isWater && !isLanduse && !isRoad) continue;

            if (isRoad) {
                while (auto feature = layer.next_feature()) {
                    if (feature.geometry_type() != vtzero::GeomType::LINESTRING) {
                        continue;
                    }

                    std::string roadClass = "street";
                    std::string roadType = "";
                    bool generateCaps = options.generateRoadJunctionCaps;
                    while (auto prop = feature.next_property()) {
                        std::string key(prop.key());
                        if (key == "class") {
                            if (prop.value().type() == vtzero::property_value_type::string_value) {
                                roadClass = std::string(prop.value().string_value());
                            }
                        } else if (key == "type") {
                            if (prop.value().type() == vtzero::property_value_type::string_value) {
                                roadType = std::string(prop.value().string_value());
                            }
                        } else if (key == "generate_caps") {
                            generateCaps = extractBool(prop.value(), generateCaps);
                        }
                    }
                    if (roadClass.empty() && !roadType.empty()) {
                        roadClass = roadType;
                    }

                    RoadLayerStyle style;
                    if (!options.roadConfig.shouldRender(roadClass, style)) {
                        continue;
                    }

                    VtzeroLineHandler handler;
                    vtzero::decode_linestring_geometry(feature.geometry(), handler);

                    for (const auto& line : handler.lines) {
                        processRoadLineString(line, style, extent, tileGroundWidth, tileGroundHeight, result, generateCaps);
                    }
                }
                continue;
            }

            std::array<float, 4> wallColor = {0.85f, 0.85f, 0.88f, 1.0f};
            std::array<float, 4> roofColor = {0.75f, 0.75f, 0.78f, 1.0f};

            if (isWater) {
                roofColor = {0.18f, 0.45f, 0.72f, 1.0f};
            } else if (isLanduse) {
                roofColor = {0.35f, 0.65f, 0.40f, 1.0f};
            }

            while (auto feature = layer.next_feature()) {
                if (feature.geometry_type() != vtzero::GeomType::POLYGON) {
                    continue;
                }

                double height = options.defaultBuildingHeight;
                double minHeight = options.defaultBuildingMinHeight;
                bool extrude = true;

                while (auto prop = feature.next_property()) {
                    std::string key(prop.key());
                    if (key == "height" || key == "render_height") {
                        height = extractDouble(prop.value(), height);
                    } else if (key == "min_height" || key == "render_min_height") {
                        minHeight = extractDouble(prop.value(), minHeight);
                    } else if (key == "levels" || key == "building:levels") {
                        double levels = extractDouble(prop.value(), 0.0);
                        if (levels > 0.0) height = levels * 3.0;
                    } else if (key == "min_level") {
                        double minLevel = extractDouble(prop.value(), 0.0);
                        if (minLevel > 0.0) minHeight = minLevel * 3.0;
                    } else if (key == "extrude") {
                        extrude = extractBool(prop.value(), extrude);
                    }
                }

                if (isBuilding && (!extrude || height <= minHeight)) {
                    // Non-extruded building or flat
                    height = minHeight;
                }

                VtzeroPolygonHandler handler;
                vtzero::decode_polygon_geometry(feature.geometry(), handler);

                for (const auto& poly : handler.polygons) {
                    std::vector<Point2D> outer;
                    outer.reserve(poly.outer.size());
                    for (const auto& pt : poly.outer) {
                        outer.push_back({static_cast<double>(pt.x), static_cast<double>(pt.y)});
                    }

                    std::vector<std::vector<Point2D>> holes;
                    for (const auto& h : poly.holes) {
                        std::vector<Point2D> hole;
                        hole.reserve(h.size());
                        for (const auto& pt : h) {
                            hole.push_back({static_cast<double>(pt.x), static_cast<double>(pt.y)});
                        }
                        holes.push_back(std::move(hole));
                    }

                    bool isSurface = !isBuilding;
                    double featureHeight = isBuilding ? height : 0.0;
                    double featureMinHeight = isBuilding ? minHeight : 0.0;

                    clipAndProcessPolygon(
                        outer, holes, featureHeight, featureMinHeight, extent,
                        tileGroundWidth, tileGroundHeight, result,
                        isSurface, wallColor, roofColor
                    );
                }
            }
        }
    } catch (const std::exception& e) {
        // Return whatever geometry was decoded before exception
        std::cerr << "MapboxTileProcessor error: " << e.what() << std::endl;
    }

    return result;
}

DecompressionResult MapboxTileProcessor::createTestTile(
    const std::string& layerName,
    const PolygonRing& outerRing,
    double height,
    double minHeight
) {
    DecompressionResult res;
    if (outerRing.points.size() < 3) return res;

    try {
        vtzero::tile_builder tbuilder;
        vtzero::layer_builder lbuilder{tbuilder, layerName, 2, 4096};
        vtzero::polygon_feature_builder fbuilder{lbuilder};

        std::vector<vtzero::point> pts;
        pts.reserve(outerRing.points.size() + 1);
        for (const auto& pt : outerRing.points) {
            pts.emplace_back(static_cast<int32_t>(pt.x), static_cast<int32_t>(pt.y));
        }
        if (pts.front() != pts.back()) {
            pts.push_back(pts.front());
        }
        fbuilder.add_ring_from_container(pts);

        fbuilder.add_property("height", height);
        fbuilder.add_property("min_height", minHeight);
        fbuilder.commit();

        std::string serialized = tbuilder.serialize();
        res.data.assign(serialized.begin(), serialized.end());
        res.success = true;
    } catch (...) {
        res.success = false;
    }

    return res;
}

DecompressionResult MapboxTileProcessor::createTestRoadTile(
    const std::string& layerName,
    const PolygonRing& linePoints,
    const std::string& roadClass,
    bool generateCaps
) {
    DecompressionResult res;
    if (linePoints.points.size() < 2) return res;

    try {
        vtzero::tile_builder tbuilder;
        vtzero::layer_builder lbuilder{tbuilder, layerName, 2, 4096};
        vtzero::linestring_feature_builder fbuilder{lbuilder};

        fbuilder.add_linestring(static_cast<uint32_t>(linePoints.points.size()));
        for (const auto& pt : linePoints.points) {
            fbuilder.set_point(static_cast<int32_t>(pt.x), static_cast<int32_t>(pt.y));
        }

        fbuilder.add_property("class", roadClass);
        fbuilder.add_property("generate_caps", generateCaps);
        fbuilder.commit();

        std::string serialized = tbuilder.serialize();
        res.data.assign(serialized.begin(), serialized.end());
        res.success = true;
    } catch (...) {
        res.success = false;
    }

    return res;
}

} // namespace AcornMap
