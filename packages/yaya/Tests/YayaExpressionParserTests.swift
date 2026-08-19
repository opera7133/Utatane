import Testing
@testable import UtataneYaya

@Test func `parses operator precedence`() throws {
    let expression = try YayaExpressionParser.parse(source: "1 + 2 * 3")

    guard case let .binary(left, "+", right, _) = expression,
          case .literal(.integer(1), _) = left,
          case let .binary(multiplyLeft, "*", multiplyRight, _) = right,
          case .literal(.integer(2), _) = multiplyLeft,
          case .literal(.integer(3), _) = multiplyRight
    else {
        Issue.record("Unexpected AST: \(expression)")
        return
    }
}

@Test func `parses calls subscripts and assignment`() throws {
    let expression = try YayaExpressionParser.parse(source: "_script = E.EvalEmbedValue(reference[0])")

    guard case let .binary(left, "=", right, _) = expression,
          case .identifier("_script", _) = left,
          case let .call(callee, arguments, _) = right,
          case .identifier("E.EvalEmbedValue", _) = callee,
          arguments.count == 1,
          case let .subscriptAccess(base, index, _) = arguments[0],
          case .identifier("reference", _) = base,
          case .literal(.integer(0), _) = index
    else {
        Issue.record("Unexpected AST: \(expression)")
        return
    }
}

@Test func `parses yaya membership and array comma expression`() throws {
    let membership = try YayaExpressionParser.parse(source: "'Phase4' _in_ SHIORI3FW.ShellName")
    guard case .binary(_, "_in_", _, _) = membership else {
        Issue.record("Unexpected membership AST: \(membership)")
        return
    }

    let array = try YayaExpressionParser.parse(source: "(OnBoot_UserBirthday, IARRAY)")
    guard case .binary(_, ",", _, _) = array else {
        Issue.record("Unexpected array AST: \(array)")
        return
    }
}

@Test func `parses function arguments separately from comma operator`() throws {
    let expression = try YayaExpressionParser.parse(source: "STRFORM('$02d$02d', GETTIME[1], GETTIME[2])")

    guard case let .call(_, arguments, _) = expression else {
        Issue.record("Unexpected AST: \(expression)")
        return
    }
    #expect(arguments.count == 3)
}

@Test func `parses postfix increment`() throws {
    let expression = try YayaExpressionParser.parse(source: "_i++")

    guard case let .unary("++", operand, _) = expression,
          case .identifier("_i", _) = operand
    else {
        Issue.record("Expected postfix increment")
        return
    }
}

@Test func `parses a reference to an array element`() throws {
    let expression = try YayaExpressionParser.parse(source: "&_array[_index]")

    guard case let .unary("&", operand, _) = expression,
          case let .subscriptAccess(base, index, _) = operand,
          case .identifier("_array", _) = base,
          case .identifier("_index", _) = index
    else {
        Issue.record("Expected an array element reference")
        return
    }
}
