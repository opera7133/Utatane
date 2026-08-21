import Testing
@testable import UtataneShell

@Test
func `parses collisions and animation patterns`() throws {
    let source = """
    charset,UTF-8

    surface0
    {
    element0,overlay,surface0000.png,0,0
    element1,overlay,face.png,10,20
    animation0.name,blink
    animation0.interval,sometimes
    animation0.pattern1,overlay,1000,100,3,4
    animation0.pattern2,overlay,-1,200,0,0
    collision0,10,20,30,40,Head
    }
    """

    let surface = try #require(SurfacesParser().parse(source)[0])
    let collision = try #require(surface.collisions.first)
    let animation = try #require(surface.animations.first)

    #expect(surface.elements.map(\.filename) == ["surface0000.png", "face.png"])
    #expect(surface.elements.last?.x == 10)
    #expect(surface.elements.last?.y == 20)
    #expect(collision.name == "Head")
    #expect(collision.contains(x: 20, y: 30))
    #expect(!collision.contains(x: 9, y: 30))
    #expect(animation.interval == "sometimes")
    #expect(animation.name == "blink")
    #expect(animation.patterns.map(\.surfaceID) == [1000, -1])
    #expect(animation.patterns.first?.x == 3)
    #expect(animation.patterns.first?.y == 4)
}

@Test
func `parses stop animation pattern without wait field`() throws {
    let surfaces = SurfacesParser().parse("""
    surface0
    {
    animation101.interval,bind+rarely
    animation101.pattern0,stop,100
    animation101.pattern1,overlay,16000,0,0,0
    }
    """)

    let animation = try #require(surfaces[0]?.animations.first)
    #expect(animation.patterns.count == 2)
    #expect(animation.patterns[0].method == "stop")
    #expect(animation.patterns[0].surfaceID == 100)
    #expect(animation.patterns[0].waitMilliseconds == 0)
}

@Test
func `parses ranges exclusions append definitions and aliases`() {
    let source = """
    surface0-3,!2
    {
    collision0,0,0,10,10,Base
    }

    surface.append0-4
    {
    collision1,10,10,20,20,Added
    }

    sakura.surface.alias
    {
    smile,[1,3]
    }

    kero.surface.alias
    {
    normal,[10]
    }
    """

    let document = SurfacesParser().parseDocument(source)

    #expect(document.surfaces.keys.sorted() == [0, 1, 3])
    #expect(document.surfaces[0]?.collisions.map(\.name) == ["Base", "Added"])
    #expect(document.surfaces[3]?.collisions.map(\.name) == ["Base", "Added"])
    #expect(document.aliases[0]?["smile"] == [1, 3])
    #expect(document.aliases[1]?["normal"] == [10])
}

@Test
func `parses extended rectangle and polygon collisions`() throws {
    let source = """
    surface0
    {
    collisionex0,head,rect,1,2,10,20
    collisionex1,hair,polygon,0,0,20,0,20,20,0,20
    }
    """

    let surface = try #require(SurfacesParser().parse(source)[0])
    let head = try #require(surface.collisions.first { $0.name == "head" })
    let hair = try #require(surface.collisions.first { $0.name == "hair" })

    #expect(head.contains(x: 5, y: 10))
    #expect(!head.contains(x: 0, y: 10))
    #expect(hair.polygon.count == 4)
    #expect(hair.contains(x: 10, y: 10))
    #expect(!hair.contains(x: 21, y: 10))
}
