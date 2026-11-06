import Foundation
import Testing
import UtataneCore
@testable import UtataneNativeSaori

private struct DescribeMediaReader: InternalSaoriMediaReading {
    func read(_: URL) throws -> InternalSaoriMediaInfo {
        .init()
    }
}

private func describeResponse(_ arguments: [String], service: InternalSaoriService = .init(), charset: String = "UTF-8") throws -> [String: String] {
    let wire = (["EXECUTE SAORI/1.0", "Charset: \(charset)", "Module: internal_system"] + arguments.enumerated().map { "Argument\($0.offset): \($0.element)" }).joined(separator: "\r\n") + "\r\n\r\n"
    let request = try #require(LegacyTextDecoder.encode(wire, charset: charset))
    let response = try #require(LegacyTextDecoder.decode(service.response(to: request), strictlyUsing: charset == "Shift_JIS" ? "CP932" : charset))
    var fields: [String: String] = [:]
    for line in response.components(separatedBy: "\r\n") {
        if let separator = line.range(of: ": ") {
            fields[String(line[..<separator.lowerBound])] = String(line[separator.upperBound...])
        }
    }
    return fields
}

@Test(arguments: ["UTF-8", "Shift_JIS"])
func `Describe returns canonical calls and checksum candidates in either wire charset`(charset: String) throws {
    let fields = try describeResponse(["dEsCrIbE", "INTERNAL_CRYPTO", "dIgEsT"], charset: charset)
    #expect(fields["Result"] == "Digest")
    #expect(fields["Value0"] == "2")
    #expect(fields["Value1"] == "2")
    #expect(fields["Value2"] == "0")
    #expect(fields["Value3"] == "data-in,out,charset,async")
    #expect(fields["Value4"] == "Argument1=md5|sha1|sha256|sha384|sha512|crc32|adler32")
    #expect(fields["Charset"] == charset)
    let hmac = try describeResponse(["Describe", "internal_crypto", "HMAC"])
    #expect(hmac["Value4"] == "Argument1=sha256|sha384|sha512")
}

@Test func `Describe shares registry availability and distinguishes unknown calls from invalid arguments`() throws {
    #expect(try describeResponse(["ListFunctions", "internal_system"])["Result"] == "ListModules,ListFunctions,Describe")
    for module in ["unknown", "string", "internal_file"] {
        #expect(try describeResponse(["Describe", module, "Digest"])["ErrorDescription"] == "unknown module")
    }
    #expect(try describeResponse(["Describe", "internal_crypto", "Encrypt"])["ErrorDescription"] == "unknown function")
    for arguments in [["Describe"], ["Describe", "internal_crypto"],
                      ["Describe", "internal_crypto", "Digest", "extra"],
                      ["Describe", "internal_crypto", "Digest", "--unknown=yes"]]
    {
        #expect(try describeResponse(arguments)["ErrorDescription"] == "invalid parameter")
    }
}

@Test func `Describe exposes optional fixed and variable positions without advertising format encodings`() throws {
    let service = InternalSaoriService(mediaReader: DescribeMediaReader())
    for function in ["MediaInfo", "ImageInfo"] {
        let fields = try describeResponse(["Describe", "internal_file", function], service: service)
        #expect(fields["Value0"] == "12" && fields["Value1"] == "2" && fields["Value2"] == "1")
        #expect(fields["Value3"] == "async")
    }
    let unary = try describeResponse(["Describe", "internal_file", "IsImageLoadable"], service: service)
    #expect(unary["Value0"] == "1" && unary["Value1"] == "1" && unary["Value2"] == "0")
    let format = try describeResponse(["Describe", "internal_time", "Format"])
    #expect(format["Value0"] == "2" && format["Value1"] == "1" && format["Value2"] == "0")
    #expect(format["Value3"] == "tz,async" && format["Value4"] == nil)
    let convert = try describeResponse(["Describe", "internal_data", "Convert"])
    #expect(convert["Value4"] == nil)
}

@Test func `every listed function has matching Describe and async argument boundaries`() throws {
    for service in [InternalSaoriService(), InternalSaoriService(mediaReader: DescribeMediaReader())] {
        let modules = try describeResponse(["ListModules"], service: service)["Result"] ?? ""
        for module in modules.split(separator: ",").map(String.init) {
            let functions = try describeResponse(["ListFunctions", module], service: service)["Result"] ?? ""
            #expect(!functions.isEmpty)
            for function in functions.split(separator: ",").map(String.init) {
                let fields = try describeResponse(["Describe", module, function], service: service)
                let maximum = try #require(fields["Value0"].flatMap(Int.init))
                let required = try #require(fields["Value1"].flatMap(Int.init))
                #expect(fields["Result"] == function)
                #expect(required <= maximum)
                #expect(InternalSaoriService.positionalCount(module: module, function: function) == (fields["Value2"] == "1" ? required : maximum))
                #expect(fields["Value3"]?.split(separator: ",").last == "async")
            }
        }
    }
}
