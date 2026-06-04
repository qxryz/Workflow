import Foundation

// MARK: - Consistency Policies

enum ConsistencyWritePolicy: String, Codable, CaseIterable, Identifiable {
    case append
    case merge
    case replace
    case versioned
    var id: String { rawValue }
}

enum ConsistencyConflictPolicy: String, Codable, CaseIterable, Identifiable {
    case preferLocked = "prefer_locked"
    case preferNewer = "prefer_newer"
    case askUser = "ask_user"
    case keepBoth = "keep_both"
    var id: String { rawValue }
}

// MARK: - Category

enum ConsistencyCategoryKind: String, Codable, CaseIterable, Identifiable {
    case character
    case visualStyle
    case product
    case scene
    case motion
    case voice
    case music
    case sound
    case custom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .character: "人物"
        case .visualStyle: "视觉风格"
        case .product: "产品/品牌"
        case .scene: "场景/地点"
        case .motion: "镜头/动作"
        case .voice: "语音/说话人"
        case .music: "音乐"
        case .sound: "音效/环境声"
        case .custom: "自定义"
        }
    }
    var symbolName: String {
        switch self {
        case .character: "person.crop.square"
        case .visualStyle: "paintpalette"
        case .product: "shippingbox"
        case .scene: "map"
        case .motion: "video"
        case .voice: "waveform.and.person.filled"
        case .music: "music.note"
        case .sound: "speaker.wave.2"
        case .custom: "square.stack.3d.up"
        }
    }
    var guidance: String {
        switch self {
        case .character: "角色身份、脸型、服装、发型、年龄感、表情范围，以及可复用的人物参考图。"
        case .visualStyle: "统一画风、色彩、光线、镜头质感、构图语言和后期风格。"
        case .product: "品牌资产、Logo、包装、产品外观、材质和不可变设计细节。"
        case .scene: "固定地点、空间布局、时代背景、天气、道具和环境连续性。"
        case .motion: "视频节奏、镜头运动、角色动作、转场方式和动态参考。"
        case .voice: "说话人音色、语速、口音、情绪、录音质量，以及可用的参考音频。"
        case .music: "曲风、速度、配器、情绪、结构、主题动机和音乐参考。"
        case .sound: "环境底噪、拟音、空间混响、关键音效和声音世界观。"
        case .custom: "放置暂时无法归类的参考材料，后续可以再拆分为更具体的类别。"
        }
    }
    var preferredModalities: Set<Modality> {
        switch self {
        case .character, .visualStyle, .product, .scene: [.image, .video]
        case .motion: [.video, .image]
        case .voice, .music, .sound: [.audio, .video]
        case .custom: Set(Modality.allCases)
        }
    }
}

struct ConsistencyCategory: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var kind: ConsistencyCategoryKind
    var description: String
    var assetPaths: [String] = []

    static let defaults: [ConsistencyCategory] = [
        ConsistencyCategory(name: "主角/人物", kind: .character, description: ""),
        ConsistencyCategory(name: "视觉风格", kind: .visualStyle, description: ""),
        ConsistencyCategory(name: "场景/地点", kind: .scene, description: ""),
        ConsistencyCategory(name: "品牌/产品", kind: .product, description: ""),
        ConsistencyCategory(name: "镜头/动作", kind: .motion, description: ""),
        ConsistencyCategory(name: "语音/说话人", kind: .voice, description: ""),
        ConsistencyCategory(name: "音乐", kind: .music, description: ""),
        ConsistencyCategory(name: "音效/环境声", kind: .sound, description: "")
    ]
}

// MARK: - Asset & Anchors

struct ConsistencyAnchors: Codable, Hashable {
    var identity: [String] = []
    var style: [String] = []
    var colorPalette: [String] = []
    var composition: [String] = []
    var voice: [String] = []
    var motion: [String] = []
    var negativeConstraints: [String] = []
}

struct ConsistencyPromptSnippets: Codable, Hashable {
    var positive: [String] = []
    var negative: [String] = []
}

struct ConsistencyEmbeddingRefs: Codable, Hashable {
    var textEmbeddingId: String?
    var imageEmbeddingId: String?
    var audioEmbeddingId: String?
    var perceptualHash: String?
}

struct ConsistencyAsset: Identifiable, Codable, Hashable {
    var id = UUID()
    var entityId = UUID()
    var category: ConsistencyCategoryKind
    var displayCategory: String
    var name: String
    var assetType: Modality
    var artifactPath: String
    var sourceNodeId: UUID?
    var sourceRunId: UUID?
    var sourceRouteId: UUID?
    var description = ""
    var tags: [String] = []
    var aliases: [String] = []
    var canonical = false
    var locked = false
    var version = 1
    var strength = 1.0
    var metadata: [String: String] = [:]
    var anchors = ConsistencyAnchors()
    var promptSnippets = ConsistencyPromptSnippets()
    var embeddingRefs = ConsistencyEmbeddingRefs()
    var createdAt = Date()
    var updatedAt = Date()
}

// MARK: - Conflicts & Entities

enum ConsistencyConflictType: String, Codable, CaseIterable, Identifiable {
    case duplicate
    case categoryConflict = "category_conflict"
    case identityConflict = "identity_conflict"
    case styleConflict = "style_conflict"
    case lockedConflict = "locked_conflict"
    case versionConflict = "version_conflict"
    var id: String { rawValue }
}

enum ConsistencyConflictSeverity: String, Codable, CaseIterable, Identifiable {
    case low
    case medium
    case high
    var id: String { rawValue }
}

struct ConsistencyConflict: Identifiable, Codable, Hashable {
    var id = UUID()
    var type: ConsistencyConflictType
    var category: ConsistencyCategoryKind
    var assetIds: [UUID]
    var severity: ConsistencyConflictSeverity
    var message: String
    var resolution = "unresolved"
    var createdAt = Date()
}

struct ConsistencyEntity: Identifiable, Codable, Hashable {
    var id = UUID()
    var category: ConsistencyCategoryKind
    var name: String
    var versions: [UUID] = []
    var canonicalAssetId: UUID?
    var lockedAssetIds: [UUID] = []
}

// MARK: - Validation & Context

struct ConsistencyValidationSettings: Codable, Hashable {
    var enabled = true
    var threshold = 0.75
    var autoRepair = false
    var maxRepairAttempts = 1
}

struct ConsistencyContext: Codable, Hashable {
    var globalPrompt = ""
    var categoryPrompts: [ConsistencyCategoryKind: String] = [:]
    var positivePromptSnippets: [String] = []
    var negativePromptSnippets: [String] = []
    var referenceArtifacts: [String] = []
    var lockedConstraints: [String] = []
    var softConstraints: [String] = []
    var validationRules: [String] = []
}

struct ConsistencyValidationIssue: Identifiable, Codable, Hashable {
    var id = UUID()
    var category: ConsistencyCategoryKind
    var severity: ConsistencyConflictSeverity
    var message: String
    var suggestedFix: String
}

struct ConsistencyValidationResult: Codable, Hashable {
    var score = 1.0
    var categoryScores: [ConsistencyCategoryKind: Double] = [:]
    var passed = true
    var issues: [ConsistencyValidationIssue] = []
}

// MARK: - Media Profile

struct MediaConsistencyProfile: Codable, Hashable {
    var enabled = true
    var stylePrompt = "cinematic, consistent lighting, coherent character identity"
    var seed = "locked-seed-001"
    var referenceAssets: [String] = []
    var categories: [ConsistencyCategory] = ConsistencyCategory.defaults
    var assets: [ConsistencyAsset] = []
    var entities: [ConsistencyEntity] = []
    var conflicts: [ConsistencyConflict] = []
    var validation = ConsistencyValidationSettings()

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        stylePrompt = try container.decodeIfPresent(String.self, forKey: .stylePrompt) ?? "cinematic, consistent lighting, coherent character identity"
        seed = try container.decodeIfPresent(String.self, forKey: .seed) ?? "locked-seed-001"
        referenceAssets = try container.decodeIfPresent([String].self, forKey: .referenceAssets) ?? []
        categories = try container.decodeIfPresent([ConsistencyCategory].self, forKey: .categories) ?? ConsistencyCategory.defaults
        assets = try container.decodeIfPresent([ConsistencyAsset].self, forKey: .assets) ?? []
        entities = try container.decodeIfPresent([ConsistencyEntity].self, forKey: .entities) ?? []
        conflicts = try container.decodeIfPresent([ConsistencyConflict].self, forKey: .conflicts) ?? []
        validation = try container.decodeIfPresent(ConsistencyValidationSettings.self, forKey: .validation) ?? ConsistencyValidationSettings()
        if categories.isEmpty {
            categories = ConsistencyCategory.defaults
        }
        if !referenceAssets.isEmpty, let firstIndex = categories.indices.first {
            let existing = Set(categories.flatMap(\.assetPaths))
            categories[firstIndex].assetPaths.append(contentsOf: referenceAssets.filter { !existing.contains($0) })
        }
    }
}
