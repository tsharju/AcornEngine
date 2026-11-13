import Testing
import simd
import Foundation
@testable import AcornEngine

@MainActor
struct TextRenderingTests {

    @Test("Text Mesh Generation - Standard Output")
    func testTextMeshGeneration() throws {
        let renderer = try NoGraphicsRenderer()
        let atlas = try SDFFontAtlasGenerator.generate(
            fontName: "Helvetica",
            fontSize: 24.0,
            renderer: renderer
        )

        let text = "Hello"
        let vertices = TextMeshGenerator.generateVertices(for: text, in: atlas)

        // "Hello" has 5 characters, each character is a quad (6 vertices)
        #expect(vertices.count == 5 * 6)

        // Verify UV coordinates are populated (not all zero)
        for vertex in vertices {
            #expect(vertex.texCoord != .zero)
        }
    }

    @Test("Text Mesh Generation - Special Cases")
    func testSpecialCases() throws {
        let renderer = try NoGraphicsRenderer()
        let atlas = try SDFFontAtlasGenerator.generate(
            fontName: "Helvetica",
            fontSize: 24.0,
            renderer: renderer
        )

        let emptyVertices = TextMeshGenerator.generateVertices(for: "", in: atlas)
        #expect(emptyVertices.isEmpty)

        let newlineVertices = TextMeshGenerator.generateVertices(for: "A\nB", in: atlas)
        // 2 characters (not counting newline) = 12 vertices
        #expect(newlineVertices.count == 12)

        // The first quad top Y should be higher than the second quad top Y
        let firstCharY = newlineVertices[1].position.y // Top-left of 'A'
        let secondCharY = newlineVertices[7].position.y // Top-left of 'B'
        #expect(secondCharY < firstCharY)
    }

    @Test("Text Component Dirty State")
    func testTextComponentDirtyState() throws {
        let renderer = try NoGraphicsRenderer()
        let atlas1 = try SDFFontAtlasGenerator.generate(fontName: "Helvetica", fontSize: 24.0, renderer: renderer)
        let atlas2 = try SDFFontAtlasGenerator.generate(fontName: "Courier", fontSize: 24.0, renderer: renderer)

        var component = TextComponent(text: "Initial", fontAtlas: atlas1)
        #expect(component.isDirty)

        component.isDirty = false
        component.text = "New Text"
        #expect(component.isDirty)

        component.isDirty = false
        component.textColor = SIMD4<Float>(1, 0, 0, 1)
        #expect(component.isDirty)

        component.isDirty = false
        component.fontAtlas = atlas2
        #expect(component.isDirty)
    }

    @Test("RenderSystem Text Rendering Integration")
    func testRenderSystemIntegration() throws {
        let renderer = try NoGraphicsRenderer()
        let world = World()
        let renderSystem = RenderSystem(renderer: renderer)

        let atlas = try SDFFontAtlasGenerator.generate(fontName: "Helvetica", fontSize: 24.0, renderer: renderer)
        let entity = world.createEntity()

        let textComponent = TextComponent(text: "Test", fontAtlas: atlas)
        world.addComponent(textComponent, to: entity)
        world.addComponent(TransformComponent(position: .zero), to: entity)

        let context = try #require(renderer.beginFrame(clearColor: SIMD4<Float>(0, 0, 0, 1)))
        renderSystem.render(world: world, context: context)
        renderer.endFrame(context: context)
        renderer.waitIdle()

        // Retrieve component back to verify mesh caching
        let updatedComponent = try #require(world.component(ofType: TextComponent.self, for: entity))
        #expect(updatedComponent.mesh != nil)
        #expect(!updatedComponent.isDirty)
    }
}
