import Testing
@testable import Beatbox

@Suite("LRC 歌词解析")
@MainActor
struct LRCParserTests {
    @Test
    func parsesMultipleTimestampsAndSortsCues() {
        let lyrics = """
        [00:12.50][00:42.500]让我一次爱个够
        [00:05.00]前奏之后
        """

        let cues = LRCParser.parse(lyrics)

        #expect(cues.map(\.time) == [5, 12.5, 42.5])
        #expect(cues.map(\.text) == ["前奏之后", "让我一次爱个够", "让我一次爱个够"])
    }

    @Test
    func appliesMillisecondOffsetAndPreservesInstrumentalCue() {
        let lyrics = """
        [offset:-500]
        [00:02.00]
        [00:03.25]开始
        """

        let cues = LRCParser.parse(lyrics)

        #expect(cues.count == 2)
        #expect(cues[0] == LyricCue(time: 1.5, text: ""))
        #expect(cues[1] == LyricCue(time: 2.75, text: "开始"))
    }

    @Test
    func ignoresMetadataAndMalformedLines() {
        let lyrics = """
        [ar:庾澄庆]
        [ti:让我一次爱个够]
        普通文本
        [01:02.03]有效歌词
        """

        let cues = LRCParser.parse(lyrics)

        #expect(cues == [LyricCue(time: 62.03, text: "有效歌词")])
    }
}
