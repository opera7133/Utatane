import Foundation

public struct YayaFunctionCallLocation: Equatable, Sendable {
    public let sourceURL: URL
    public let functionName: String
    public let line: Int
    public let column: Int

    public init(sourceURL: URL, functionName: String, line: Int, column: Int) {
        self.sourceURL = sourceURL
        self.functionName = functionName
        self.line = line
        self.column = column
    }
}

public struct YayaUnsupportedFunction: Equatable, Sendable {
    public let name: String
    public let locations: [YayaFunctionCallLocation]

    public var referenceCount: Int {
        locations.count
    }

    public init(name: String, locations: [YayaFunctionCallLocation]) {
        self.name = name
        self.locations = locations
    }
}

public struct YayaRuntimeCompatibilityReport: Equatable, Sendable {
    public let declaredFunctionCount: Int
    public let functionCallCount: Int
    public let unsupportedFunctions: [YayaUnsupportedFunction]

    public var unsupportedFunctionCallCount: Int {
        unsupportedFunctions.reduce(0) { $0 + $1.referenceCount }
    }

    public init(
        declaredFunctionCount: Int,
        functionCallCount: Int,
        unsupportedFunctions: [YayaUnsupportedFunction]
    ) {
        self.declaredFunctionCount = declaredFunctionCount
        self.functionCallCount = functionCallCount
        self.unsupportedFunctions = unsupportedFunctions
    }
}

public struct YayaRuntimeCompatibilityAuditor {
    public init() {}

    public func audit(programs: [(sourceURL: URL, program: YayaProgram)]) -> YayaRuntimeCompatibilityReport {
        let declaredFunctions = Set(programs.flatMap { $0.program.functions.map(\.name) })
        var functionCallCount = 0
        var unsupported: [String: [YayaFunctionCallLocation]] = [:]

        for source in programs {
            for function in source.program.functions {
                visit(function.body) { name, range in
                    functionCallCount += 1
                    guard !declaredFunctions.contains(name),
                          !YayaEvaluator.supportedBuiltinNames.contains(name.uppercased())
                    else { return }
                    unsupported[name, default: []].append(YayaFunctionCallLocation(
                        sourceURL: source.sourceURL,
                        functionName: function.name,
                        line: range.start.line,
                        column: range.start.column
                    ))
                }
            }
        }

        let unsupportedFunctions = unsupported.map { name, locations in
            YayaUnsupportedFunction(name: name, locations: locations)
        }.sorted {
            if $0.referenceCount != $1.referenceCount {
                return $0.referenceCount > $1.referenceCount
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return YayaRuntimeCompatibilityReport(
            declaredFunctionCount: declaredFunctions.count,
            functionCallCount: functionCallCount,
            unsupportedFunctions: unsupportedFunctions
        )
    }

    private func visit(
        _ statements: [YayaStatement],
        onCall: (String, YayaSourceRange) -> Void
    ) {
        for statement in statements {
            switch statement {
            case let .expression(expression), let .parallel(expression, _), let .discard(expression, _):
                visit(expression, onCall: onCall)
            case let .conditional(branches, elseBody, _):
                for branch in branches {
                    visit(branch.condition, onCall: onCall)
                    visit(branch.body, onCall: onCall)
                }
                visit(elseBody, onCall: onCall)
            case let .caseSelection(subject, preamble, branches, othersBody, _):
                visit(subject, onCall: onCall)
                visit(preamble, onCall: onCall)
                for branch in branches {
                    visit(branch.matches, onCall: onCall)
                    visit(branch.body, onCall: onCall)
                }
                visit(othersBody, onCall: onCall)
            case let .switchSelection(index, body, _):
                visit(index, onCall: onCall)
                visit(body, onCall: onCall)
            case let .returnValue(expression, _):
                if let expression {
                    visit(expression, onCall: onCall)
                }
            case let .whileLoop(condition, body, _):
                visit(condition, onCall: onCall)
                visit(body, onCall: onCall)
            case let .forLoop(initializer, condition, increment, body, _):
                visit(initializer, onCall: onCall)
                visit(condition, onCall: onCall)
                visit(increment, onCall: onCall)
                visit(body, onCall: onCall)
            case let .forEach(collection, _, body, _):
                visit(collection, onCall: onCall)
                visit(body, onCall: onCall)
            case let .block(body, _):
                visit(body, onCall: onCall)
            case .breakLoop, .continueLoop, .choiceSeparator:
                break
            }
        }
    }

    private func visit(
        _ expression: YayaExpression,
        onCall: (String, YayaSourceRange) -> Void
    ) {
        switch expression {
        case .literal, .identifier:
            break
        case let .unary(_, operand, _):
            visit(operand, onCall: onCall)
        case let .binary(left, _, right, _):
            visit(left, onCall: onCall)
            visit(right, onCall: onCall)
        case let .call(callee, arguments, range):
            if case let .identifier(name, _) = callee {
                onCall(name, range)
            }
            visit(callee, onCall: onCall)
            for argument in arguments {
                visit(argument, onCall: onCall)
            }
        case let .subscriptAccess(base, index, _):
            visit(base, onCall: onCall)
            visit(index, onCall: onCall)
        }
    }
}
