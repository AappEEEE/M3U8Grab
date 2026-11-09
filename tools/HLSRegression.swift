import Foundation

@main
struct HLSRegression {
    static func main() throws {
        let url = URL(string: "https://example.test/video/index.m3u8")!
        let text = """
        #EXTM3U
        #EXT-X-TARGETDURATION:8
        #EXT-X-MEDIA-SEQUENCE:42
        #EXT-X-KEY:METHOD=AES-128,URI="key.bin",IV=0x0000000000000000000000000000002a
        #EXT-X-MAP:URI="init.mp4",BYTERANGE="128@0"
        #EXTINF:8.0,first
        #EXT-X-BYTERANGE:256@128
        media.mp4
        #EXTINF:7.5,second
        #EXT-X-BYTERANGE:256
        media.mp4
        #EXT-X-ENDLIST
        """
        let original = try HLSParser.parse(text: text, url: url)
        precondition(original.segments.count == 2)
        precondition(original.segments[0].sequence == 42)
        precondition(original.segments[1].sequence == 43)
        precondition(original.segments[0].byteRange == HLSByteRange(length: 256, offset: 128))
        precondition(original.segments[1].byteRange == HLSByteRange(length: 256, offset: 384))
        precondition(original.segments[0].key?.uri?.absoluteString == "https://example.test/video/key.bin")
        precondition(original.hasInitMap && original.isEncrypted && !original.usesSampleAES)
        precondition(original.totalDuration == 15.5)
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(HLSPlaylist.self, from: data)
        precondition(restored.segments == original.segments, "Resume must preserve AES IV, key URI, range, map and sequence")
        precondition(restored.segments[0].key?.iv == HLSKey.iv(forSequence: 42))
        precondition(restored.segments[0].map?.range == HLSByteRange(length: 128, offset: 0))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = directory.appendingPathComponent("playlist.json")
        try data.write(to: snapshot, options: .atomic)
        let cold = try JSONDecoder().decode(HLSPlaylist.self, from: Data(contentsOf: snapshot))
        precondition(cold.segments == original.segments)
        let master = try HLSParser.parse(text: "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nlow.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=2000\nhigh.m3u8", url: url)
        precondition(master.bestVariant?.url.lastPathComponent == "high.m3u8")
        // A missing offset is valid only after a range of the same resource.
        let invalidRanges = [
            "#EXTM3U\n#EXTINF:1,\n#EXT-X-BYTERANGE:16\nmedia.mp4",
            "#EXTM3U\n#EXTINF:1,\n#EXT-X-BYTERANGE:16@0\na.mp4\n#EXTINF:1,\n#EXT-X-BYTERANGE:16\nb.mp4",
            "#EXTM3U\n#EXTINF:1,\nmedia.mp4\n#EXTINF:1,\n#EXT-X-BYTERANGE:16\nmedia.mp4"
        ]
        for invalid in invalidRanges {
            var rejected = false
            do { _ = try HLSParser.parse(text: invalid, url: url) }
            catch { rejected = true }
            precondition(rejected, "Implicit range without preceding same-URI range must fail")
        }
        precondition(HLSParser.parseByteRange("0@0", defaultOffset: 0) == nil)
        precondition(HLSParser.parseByteRange("16@-1", defaultOffset: 0) == nil)
        precondition(HLSParser.parseByteRange("16@bad", defaultOffset: 0) == nil)
        precondition(HLSParser.parseByteRange("16@\(Int.max)", defaultOffset: 0) == nil)
        let rotatedText = """
        #EXTM3U
        #EXT-X-KEY:METHOD=AES-128,URI="init.key",IV=0x00000000000000000000000000000001
        #EXT-X-MAP:URI="init.mp4",BYTERANGE="128@0"
        #EXT-X-KEY:METHOD=AES-128,URI="media.key",IV=0x00000000000000000000000000000002
        #EXTINF:1,
        first.m4s
        #EXT-X-KEY:METHOD=NONE
        #EXTINF:1,
        second.m4s
        #EXT-X-MAP:URI="plain-init.mp4"
        #EXTINF:1,
        third.m4s
        #EXT-X-ENDLIST
        """
        let rotated = try HLSParser.parse(text: rotatedText, url: url)
        precondition(rotated.segments[0].map?.key?.uri?.lastPathComponent == "init.key")
        precondition(rotated.segments[0].key?.uri?.lastPathComponent == "media.key")
        precondition(rotated.segments[0].map?.key?.iv == HLSKey.iv(forSequence: 1))
        precondition(rotated.segments[1].key == nil)
        precondition(rotated.segments[1].map?.key?.uri?.lastPathComponent == "init.key")
        precondition(rotated.segments[2].map?.key == nil)
        precondition(rotated.segments[2].map?.url.lastPathComponent == "plain-init.mp4")
        let rotatedData = try JSONEncoder().encode(rotated)
        let rotatedCold = try JSONDecoder().decode(HLSPlaylist.self, from: rotatedData)
        precondition(rotatedCold.segments == rotated.segments, "Cold resume must preserve map declaration key, IV, range and switches")
        // Existing snapshots without the newly optional map key remain decodable.
        let legacyMapData = Data("{\"url\":\"https://example.test/init.mp4\"}".utf8)
        let legacyMap = try JSONDecoder().decode(HLSInitMap.self, from: legacyMapData)
        precondition(legacyMap.key == nil)
        print("PASS: HLS parsing, AES IV, implicit-range URI validation, map-key rotation, legacy map decode, master selection, atomic cold-resume snapshot")
    }
}
