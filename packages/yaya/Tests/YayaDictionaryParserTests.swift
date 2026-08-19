import Testing
@testable import UtataneYaya

@Test func `parses functions conditionals and returns`() throws {
    let source = """
    OnBoot : array
    {
        if username == '' {
            username = 'User'
        }
        elseif username == 'Admin' {
            return 'root'
        }
        else {
            greeting = 'hello'
        }
        return greeting + ' ' + username
    }
    """

    let program = try YayaDictionaryParser.parse(source: source)

    #expect(program.functions.count == 1)
    #expect(program.functions[0].name == "OnBoot")
    #expect(program.functions[0].choiceType == YayaChoiceType(selection: .array))
    #expect(program.functions[0].body.count == 2)
    guard case let .conditional(branches, elseBody, _) = program.functions[0].body[0] else {
        Issue.record("Expected conditional")
        return
    }
    #expect(branches.count == 2)
    #expect(elseBody.count == 1)
}

@Test func `parses case when lists and others`() throws {
    let source = """
    Direction
    {
        case reference[5] {
            when 'right_up' { return '右上' }
            when 'left','left_up' { return '左' }
            others { return '不明' }
        }
    }
    """

    let program = try YayaDictionaryParser.parse(source: source)

    guard case let .caseSelection(_, _, branches, othersBody, _) = program.functions[0].body[0] else {
        Issue.record("Expected case selection")
        return
    }
    #expect(branches.count == 2)
    #expect(othersBody.count == 1)
}

@Test func `parses others with a single unbraced statement`() throws {
    let source = """
    Reply { case _argv[0] { when 'GET' { 'ok' } others 'bad request' } }
    """
    let program = try YayaDictionaryParser.parse(source: source)

    guard case let .caseSelection(_, _, _, othersBody, _) = program.functions[0].body[0] else {
        Issue.record("Expected case selection")
        return
    }
    #expect(othersBody.count == 1)
}

@Test func `parses when with a single unbraced statement`() throws {
    let source = """
    Reply {
        case _argv[0] {
            when 'GET'
                'ok'
            others
                'bad request'
        }
    }
    """
    let program = try YayaDictionaryParser.parse(source: source)

    guard case let .caseSelection(_, _, branches, _, _) = program.functions[0].body[0] else {
        Issue.record("Expected case selection")
        return
    }
    #expect(branches[0].body.count == 1)
}

@Test func `case accepts setup statements before when branches`() throws {
    let source = """
    Event { case _argv[0] { _name = 'user'; when 0 { _name } } }
    """
    let program = try YayaDictionaryParser.parse(source: source)

    guard case let .caseSelection(_, preamble, branches, _, _) = program.functions[0].body[0] else {
        Issue.record("Expected case selection")
        return
    }
    #expect(preamble.count == 1)
    #expect(branches.count == 1)
}

@Test func `parses an unbraced conditional body`() throws {
    let program = try YayaDictionaryParser.parse(source: "Loop { if _done == 0; break }")

    guard case let .conditional(branches, _, _) = program.functions[0].body[0] else {
        Issue.record("Expected conditional")
        return
    }
    #expect(branches[0].body.count == 1)
    #expect(branches[0].body[0].range.start.line == 1)
}

@Test func `parses multiple functions and function calls`() throws {
    let source = """
    Greet
    {
        return 'hello ' + _argv[0]
    }

    OnBoot
    {
        Greet('Emily')
    }
    """

    let program = try YayaDictionaryParser.parse(source: source)

    #expect(program.functions.map(\.name) == ["Greet", "OnBoot"])
}

@Test func `parses loops parallel and loop control`() throws {
    let source = """
    Build : array
    {
        for _i = 0; _i < 3; _i++ {
            if _i == 1 { continue }
            parallel ('item' + _i)
        }
        foreach ('A','B'); _value {
            _value
            break
        }
        while 0 { void SideEffect() }
    }
    """

    let program = try YayaDictionaryParser.parse(source: source)

    #expect(program.functions[0].body.count == 3)
    guard case .forLoop = program.functions[0].body[0],
          case .forEach = program.functions[0].body[1],
          case .whileLoop = program.functions[0].body[2]
    else {
        Issue.record("Expected for, foreach and while statements")
        return
    }
}

@Test func `parses indexed switch selection`() throws {
    let program = try YayaDictionaryParser.parse(source: """
    Name { switch TOINT(_argv[0]) { 'Emily'; 'Teddy'; 'Emilio' } }
    """)

    guard case let .switchSelection(_, body, _) = program.functions[0].body[0] else {
        Issue.record("Expected switch selection")
        return
    }
    #expect(body.count == 3)
}
