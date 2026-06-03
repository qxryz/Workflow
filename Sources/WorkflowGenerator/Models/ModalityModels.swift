import Foundation

enum Modality: String, Codable, CaseIterable, Identifiable {
    case text
    case image
    case video
    case audio
    case audioVideo = "audio_video"
    case file
    case json
    case embedding
    case scores
    case music
    case threeD = "three_d"
    case mask
    case bbox
    case reference
    case unknown

    var id: String { rawValue }
    var title: String {
        switch self {
        case .audioVideo: "AudioVideo"
        case .threeD: "3D"
        default: rawValue.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
        }
    }
    var symbolName: String {
        switch self {
        case .text: "text.alignleft"
        case .image: "photo"
        case .video: "film"
        case .audio: "waveform"
        case .audioVideo: "waveform.and.film"
        case .file: "doc"
        case .json: "curlybraces"
        case .embedding: "number.square"
        case .scores: "list.number"
        case .music: "music.note"
        case .threeD: "cube"
        case .mask: "rectangle.dashed"
        case .bbox: "viewfinder.rectangular"
        case .reference: "paperclip"
        case .unknown: "questionmark.circle"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = Modality(rawValue: raw) ?? .unknown
    }
}
