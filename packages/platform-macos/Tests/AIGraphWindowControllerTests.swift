import Testing
@testable import UtatanePlatformMacOS

@Test
func `parses AI graph resource with SSP defaults`() throws {
    let series = try #require(AIGraphSeries(id: 0, response: "1,2,3,4,5,6"))
    #expect(series.labels == ["Neuron", "NeuronM", "NeuronK", "NeuronD", "NeuronE", "Synapse"])
    #expect(series.additions == [0, 0, 0, 0, 0, 0])
    #expect(series.maxima == [6, 6, 6, 6, 6, 6])
}

@Test
func `parses AI graph labels additions and maxima`() throws {
    let series = try #require(AIGraphSeries(
        id: 2,
        response: "1.5,2\u{1}A,B\u{1}0.5,3\u{1}10,20"
    ))
    #expect(series.id == 2)
    #expect(series.values == [1.5, 2])
    #expect(series.labels == ["A", "B"])
    #expect(series.additions == [0.5, 3])
    #expect(series.maxima == [10, 20])
}

@Test
func `rejects an empty AI graph resource`() {
    #expect(AIGraphSeries(id: 0, response: "") == nil)
}

@Test
func `rejects an AI graph resource containing a nonnumeric value`() {
    #expect(AIGraphSeries(id: 0, response: "1,broken,3") == nil)
}
