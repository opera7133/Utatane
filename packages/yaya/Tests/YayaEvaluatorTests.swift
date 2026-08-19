import Testing
@testable import UtataneYaya

@Test func `evaluates a minimal OnBoot dictionary`() throws {
    let source = """
    Greet
    {
        return 'hello ' + _argv[0]
    }

    OnBoot
    {
        if username == '' {
            username = 'User'
        }
        return Greet(username)
    }
    """
    let program = try YayaDictionaryParser.parse(source: source)
    var evaluator = YayaEvaluator(program: program, globals: ["username": .string("")])

    let result = try evaluator.call("OnBoot")

    #expect(result == .string("hello User"))
    #expect(evaluator.globals["username"] == .string("User"))
}

@Test func `evaluates elseif and builtins`() throws {
    let source = """
    OnBoot
    {
        if STRLEN(username) == 0 {
            return 'empty'
        }
        elseif username == 'Admin' {
            return 'root'
        }
        else {
            return 'hello ' + username
        }
    }
    """
    let program = try YayaDictionaryParser.parse(source: source)
    var evaluator = YayaEvaluator(program: program, globals: ["username": .string("Admin")])

    #expect(try evaluator.call("OnBoot") == .string("root"))
}

@Test func `uses final expression as function result`() throws {
    let program = try YayaDictionaryParser.parse(source: "OnBoot { 'talk\\e' }")
    var evaluator = YayaEvaluator(program: program)

    #expect(try evaluator.call("OnBoot") == .string("talk\\e"))
}

@Test func `bare return keeps values accumulated before it`() throws {
    let program = try YayaDictionaryParser.parse(source: "Value { 'kept'; return; 'ignored' }")
    var evaluator = YayaEvaluator(program: program)

    #expect(try evaluator.call("Value") == .string("kept"))
}

@Test func `evaluates array functions and random choice areas`() throws {
    let source = """
    Words : array
    {
        'one'
        'two'
    }

    Talk
    {
        'prefix:'
        --
        'A'
        'B'
        --
        ':suffix'
    }
    """
    let program = try YayaDictionaryParser.parse(source: source)
    var evaluator = YayaEvaluator(program: program, randomIndex: { $0 - 1 })

    #expect(try evaluator.call("Words") == .array([.string("one"), .string("two")]))
    #expect(try evaluator.call("Talk") == .string("prefix:B:suffix"))
}

@Test func `evaluates sequential and nonoverlap choices`() throws {
    let source = """
    Sequence : sequential
    {
        'first'
        'second'
    }

    Shuffle : nonoverlap
    {
        'A'
        'B'
    }
    """
    let program = try YayaDictionaryParser.parse(source: source)
    var evaluator = YayaEvaluator(program: program, randomIndex: { _ in 0 })

    #expect(try evaluator.call("Sequence") == .string("first"))
    #expect(try evaluator.call("Sequence") == .string("second"))
    #expect(try evaluator.call("Sequence") == .string("first"))
    #expect(try evaluator.call("Shuffle") == .string("A"))
    #expect(try evaluator.call("Shuffle") == .string("B"))
}

@Test func `evaluates case lists and others`() throws {
    let source = """
    Direction
    {
        case reference[0] {
            when 'right' { return '右' }
            when 'left','left_up' { return '左' }
            others { return '不明' }
        }
    }
    """
    let program = try YayaDictionaryParser.parse(source: source)
    var left = YayaEvaluator(program: program, globals: ["reference": .array([.string("left_up")])])
    var unknown = YayaEvaluator(program: program, globals: ["reference": .array([.string("down")])])

    #expect(try left.call("Direction") == .string("左"))
    #expect(try unknown.call("Direction") == .string("不明"))
}

@Test func `evaluates YAYA discovery and dynamic call builtins`() throws {
    let source = """
    Greeting { return 'hello' }
    OnBoot
    {
        if ISFUNC('Greeting') && ISVAR('username') {
            return EVAL('Greeting')
        }
        return RAND(10)
    }
    """
    let program = try YayaDictionaryParser.parse(source: source)
    var evaluator = YayaEvaluator(
        program: program,
        globals: ["username": .string("Emily")],
        randomIndex: { _ in 7 }
    )

    #expect(try evaluator.call("OnBoot") == .string("hello"))
}

@Test func `RAND without an argument uses the YAYA default range`() throws {
    let program = try YayaDictionaryParser.parse(source: "Value { return RAND() }")
    var evaluator = YayaEvaluator(program: program, randomIndex: { count in count - 1 })

    #expect(try evaluator.call("Value") == .integer(99))
}

@Test func `evaluates for while foreach and loop control`() throws {
    let source = """
    Build : array
    {
        for _i = 0; _i < 4; _i++ {
            if _i == 1 { continue }
            if _i == 3 { break }
            'for%(_i)'
        }

        _i = 0
        while _i < 2 {
            'while%(_i)'
            _i++
        }

        foreach ('A','B'); _item {
            'each%(_item)'
        }
    }
    """
    let program = try YayaDictionaryParser.parse(source: source)
    var evaluator = YayaEvaluator(program: program)

    let result = try evaluator.call("Build")
    #expect(result == .array([
        .string("for0"), .string("for2"),
        .string("while0"), .string("while1"),
        .string("eachA"), .string("eachB")
    ]))
}

@Test func `parallel expands array values into selection candidates`() throws {
    let source = """
    Source : array { 'A'; 'B' }
    Pick
    {
        parallel Source
        'C'
    }
    """
    let program = try YayaDictionaryParser.parse(source: source)
    var evaluator = YayaEvaluator(program: program, randomIndex: { count in count - 1 })

    #expect(try evaluator.call("Pick") == .string("C"))
}

@Test func `expands nested expressions inside strings`() throws {
    let source = """
    Name { return 'Emily' }
    Talk { 'Hello %(Name), %((RAND(10) + 10) * 100)m' }
    """
    let program = try YayaDictionaryParser.parse(source: source)
    var evaluator = YayaEvaluator(program: program, randomIndex: { _ in 3 })

    #expect(try evaluator.call("Talk") == .string("Hello Emily, 1300m"))
}

@Test func `loop limit stops runaway dictionaries`() throws {
    let program = try YayaDictionaryParser.parse(source: "Forever { while 1 { void 0 } }")
    var evaluator = YayaEvaluator(program: program, loopLimit: 3)

    #expect(throws: YayaRuntimeError.loopLimitExceeded) {
        try evaluator.call("Forever")
    }
}

@Test func `assigns and appends through array subscripts`() throws {
    let source = """
    Update
    {
        _array = (1, 2)
        _array[0] += 4
        _array[3] = 9
        return _array
    }
    """
    let program = try YayaDictionaryParser.parse(source: source)
    var evaluator = YayaEvaluator(program: program)

    #expect(try evaluator.call("Update") == .array([.integer(5), .integer(2), .void, .integer(9)]))
}

@Test func `writes reference arguments back through user functions`() throws {
    let source = """
    E.Swap
    {
        _temp = _argv[0]
        _argv[0] = _argv[1]
        _argv[1] = _temp
    }

    SwapArray
    {
        _array = _argv[0]
        E.Swap(&_array[0], &_array[1])
        _argv[0] = _array
    }

    OnBoot
    {
        _array = ('left', 'right')
        SwapArray(&_array)
        return _array
    }
    """
    let program = try YayaDictionaryParser.parse(source: source)
    var evaluator = YayaEvaluator(program: program)

    #expect(try evaluator.call("OnBoot") == .array([.string("right"), .string("left")]))
}

@Test func `switch chooses a candidate by zero based index`() throws {
    let source = """
    Name
    {
        switch TOINT(_argv[0]) {
            'Emily'
            'Teddy'
            'Emilio'
        }
    }
    """
    let program = try YayaDictionaryParser.parse(source: source)
    var evaluator = YayaEvaluator(program: program)

    #expect(try evaluator.call("Name", arguments: [.integer(0)]) == .string("Emily"))
    #expect(try evaluator.call("Name", arguments: [.integer(2)]) == .string("Emilio"))
    #expect(try evaluator.call("Name", arguments: [.integer(4)]) == .void)
}

@Test func `case executes setup statements before matching`() throws {
    let source = """
    Event
    {
        case _argv[0] {
            _prefix = 'selected:'
            when 1 { return _prefix + 'one' }
            others return _prefix + 'other'
        }
    }
    """
    let program = try YayaDictionaryParser.parse(source: source)
    var evaluator = YayaEvaluator(program: program)

    #expect(try evaluator.call("Event", arguments: [.integer(1)]) == .string("selected:one"))
    #expect(try evaluator.call("Event", arguments: [.integer(2)]) == .string("selected:other"))
}

@Test func `evaluates core YAYA string builtins`() throws {
    let source = """
    Strings
    {
        return REPLACE('a-b-b', 'b', 'x', 1) + '|' + SUBSTR('abcdef', -3, 2) + '|' + ERASE('abcdef', 2, 2) + '|' + INSERT('abef', 2, 'cd') + '|' + CUTSPACE('  ok  ') + '|' + CHR(65, 66) + '|' + STRSTR('abcdef', 'cd', 0)
    }
    """
    let program = try YayaDictionaryParser.parse(source: source)
    var evaluator = YayaEvaluator(program: program)

    #expect(try evaluator.call("Strings") == .string("a-x-b|de|abef|abcdef|ok|AB|2"))
}

@Test func `evaluates core YAYA conversion and array builtins`() throws {
    let source = """
    SplitValue { return SPLIT('a,b,c', ',', 2) }
    Search { return ASEARCH('b', ('a', 'b', 'c')) }
    Convert { return TOSTR(('a', 'b')) + '|' + GETTYPE(1.5) + '|' + TOLOWER('ABC') }
    Dedup { return ARRAYDEDUP(('a', 'b', 'a')) }
    Sort { return ASORT('string,descending', ('a', 'c', 'b')) }
    AnyValue { return ANY(('a', 'b', 'c')) }
    EraseValue { temporary = 1; ERASEVAR('temporary'); return ISVAR('temporary') }
    """
    let program = try YayaDictionaryParser.parse(source: source)
    var evaluator = YayaEvaluator(program: program, randomIndex: { $0 - 1 })

    #expect(try evaluator.call("SplitValue") == .array([.string("a"), .string("b,c")]))
    #expect(try evaluator.call("Search") == .integer(1))
    #expect(try evaluator.call("Convert") == .string("a\u{1}b|2|abc"))
    #expect(try evaluator.call("Dedup") == .array([.string("a"), .string("b")]))
    #expect(try evaluator.call("Sort") == .array([.string("c"), .string("b"), .string("a")]))
    #expect(try evaluator.call("AnyValue") == .string("c"))
    #expect(try evaluator.call("EraseValue") == .integer(0))
}

@Test func `evaluates YAYA regular expression and formatting builtins`() throws {
    let source = """
    Search { return RE_SEARCH('Emily/4', '(.+)/(\\d+)') + ':' + RE_GETSTR(1) }
    Match { return RE_MATCH('abc', '[a-z]+') }
    Replace { return RE_REPLACE('a1b2', '\\d', 'x') }
    SplitRegex { return RE_SPLIT('a  b\tc', '[ \\t]+') }
    Format { return STRFORM('$04d/$02d', 7, 3) }
    """
    let program = try YayaDictionaryParser.parse(source: source)
    var evaluator = YayaEvaluator(program: program)

    #expect(try evaluator.call("Search") == .string("1:Emily"))
    #expect(try evaluator.call("Match") == .integer(1))
    #expect(try evaluator.call("Replace") == .string("axbx"))
    #expect(try evaluator.call("SplitRegex") == .array([.string("a"), .string("b"), .string("c")]))
    #expect(try evaluator.call("Format") == .string("0007/03"))
}
