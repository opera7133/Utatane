import Foundation
import Testing
@testable import UtataneShell

@Test func `parses legacy SERIKO interval and pattern directives`() throws {
    let surfaces = SurfacesParser().parse("""
    surface1
    {
    6interval,never
    6pattern0,160,0,overlay,8,0
    }
    """)
    let animation = try #require(surfaces[1]?.animations.first)
    #expect(animation.id == 6)
    #expect(animation.interval == "never")
    #expect(animation.patterns == [
        SurfaceAnimationPattern(
            order: 0,
            method: "overlay",
            surfaceID: 160,
            waitMilliseconds: 0,
            x: 8,
            y: 0
        )
    ])
}

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
func `parses parameterized animation intervals`() throws {
    let surface = try #require(SurfacesParser().parse("""
    surface0
    {
    animation0.interval,random,5
    animation0.pattern0,overlay,1,0,0,0
    animation1.interval,bind+periodic,12
    animation1.pattern0,overlay,2,0,0,0
    }
    """)[0])

    #expect(surface.animations.first { $0.id == 0 }?.interval == "random")
    #expect(surface.animations.first { $0.id == 0 }?.intervalParameter == 5)
    #expect(surface.animations.first { $0.id == 1 }?.interval == "bind+periodic")
    #expect(surface.animations.first { $0.id == 1 }?.intervalParameter == 12)
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
    3,[1]
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
    #expect(document.aliases[0]?["3"] == [1])
    #expect(document.aliases[1]?["normal"] == [10])
    let shell = ShellDefinition(
        directory: URL(filePath: "/tmp/numeric-alias-test"),
        surfaces: document.surfaces,
        surfaceAliases: document.aliases
    )
    #expect(shell.resolveSurface("3", scope: 0) == 1)
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

@Test
func `parses curved and animation specific collisions and options`() throws {
    let surface = try #require(SurfacesParser().parse("""
    surface0
    {
    collisionex0,face,ellipse,0,0,20,10
    collisionex1,button,circle,30,30,5
    animation2.interval,sometimes
    animation2.option,exclusive+background+shared-index
    animation2.collision0,1,2,11,12,hand
    animation2.collisionex1,effect,ellipse,20,20,40,30
    animation2.pattern0,overlay,100,50,0,0
    }
    """)[0])
    let face = try #require(surface.collisions.first { $0.name == "face" })
    let button = try #require(surface.collisions.first { $0.name == "button" })
    let animation = try #require(surface.animations.first)

    #expect(face.contains(x: 10, y: 5))
    #expect(!face.contains(x: 0, y: 0))
    #expect(button.contains(x: 33, y: 33))
    #expect(!button.contains(x: 36, y: 30))
    #expect(animation.options == ["exclusive", "background", "shared-index"])
    #expect(animation.collisions.map(\.name) == ["hand", "effect"])
}

@Test
func `parses surface names offsets points and icon rectangle`() throws {
    let surface = try #require(SurfacesParser().parse("""
    surface0
    {
    name,normal
    balloon.offsetx,10
    balloon.offsety,-20
    sakura.balloon.offsetx,30
    sakura.balloon.offsety,40
    point.centerx,50
    point.centery,60
    point.kinoko.centerx,70
    point.kinoko.centery,80
    point.basepos.x,90
    point.basepos.y,100
    icon.rect,1,2,31,42
    }
    """)[0])

    #expect(surface.name == "normal")
    #expect(surface.balloonOffset == SurfacePoint(x: 10, y: -20))
    #expect(surface.scopeBalloonOffsets[0] == SurfacePoint(x: 30, y: 40))
    #expect(surface.points["center"] == SurfacePoint(x: 50, y: 60))
    #expect(surface.points["kinoko.center"] == SurfacePoint(x: 70, y: 80))
    #expect(surface.points["basepos"] == SurfacePoint(x: 90, y: 100))
    #expect(surface.iconRect == SurfaceRect(left: 1, top: 2, right: 31, bottom: 42))
}

@Test
func `parses descript width and applies collision and animation sorting`() throws {
    let document = SurfacesParser().parseDocument("""
    descript
    {
    version,1
    maxwidth,640
    collision-sort,descend
    animation-sort,ascend
    }
    surface0
    {
    collision1,0,0,10,10,lower
    collision3,0,0,10,10,higher
    animation3.interval,runonce
    animation1.interval,runonce
    }
    """)
    let surface = try #require(document.surfaces[0])

    #expect(document.maximumSurfaceWidth == 640)
    #expect(document.collisionSort == .descending)
    #expect(document.animationSort == .ascending)
    #expect(surface.collisions.map(\.id) == [3, 1])
    #expect(surface.animations.map(\.id) == [1, 3])
    #expect(surface.collisionSort == .descending)
    #expect(surface.animationSort == .ascending)
}

@Test
func `preserves collision definition order when collision sorting is omitted`() throws {
    let surface = try #require(SurfacesParser().parse("""
    surface0
    {
    collision7,0,0,10,10,first
    collision2,0,0,10,10,second
    }
    """)[0])

    #expect(surface.collisions.map(\.id) == [7, 2])
}

@Test
func `parses scoped cursor and tooltip braces`() {
    let document = SurfacesParser().parseDocument("""
    sakura.cursor
    {
    mouseup0,Head,system:hand
    mousedown0,Head,system:grip
    mouserightdown0,Bust,system:finger
    mousewheel0,Face,system:cross
    mousehover0,MenuButton,system:help
    }
    char2.tooltips
    {
    Head,頭です。
    Bust,カンマ,も保持します。
    }
    """)

    #expect(document.cursorDefinitions[0] == [
        SurfaceCursorDefinition(trigger: .mouseUp, region: "Head", cursor: "system:hand"),
        SurfaceCursorDefinition(trigger: .mouseDown, region: "Head", cursor: "system:grip"),
        SurfaceCursorDefinition(trigger: .mouseRightDown, region: "Bust", cursor: "system:finger"),
        SurfaceCursorDefinition(trigger: .mouseWheel, region: "Face", cursor: "system:cross"),
        SurfaceCursorDefinition(trigger: .mouseHover, region: "MenuButton", cursor: "system:help")
    ])
    #expect(document.tooltips[2]?["Head"] == "頭です。")
    #expect(document.tooltips[2]?["Bust"] == "カンマ,も保持します。")
}
