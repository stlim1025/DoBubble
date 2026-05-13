import WidgetKit
import SwiftUI
import AppIntents

// iOS 17+ 인터랙티브 위젯을 위한 Intent
@available(iOS 17.0, *)
struct PopBubbleIntent: AppIntent {
    static var title: LocalizedStringResource = "Pop Bubble"
    
    @Parameter(title: "Bubble ID")
    var id: String
    
    init() {}
    
    init(id: String) {
        self.id = id
    }
    
    func perform() async throws -> some IntentResult {
        // UserDefaults에 터뜨린 버블 ID 저장 (Flutter에서 감지할 수 있도록)
        let userDefaults = UserDefaults(suiteName: "group.com.dopop.widget")
        userDefaults?.set(id, forKey: "popped_bubble_id")
        
        // 위젯 즉시 갱신
        WidgetCenter.shared.reloadAllTimelines()
        
        return .result()
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), snapshotKey: "snapshot_small")
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), snapshotKey: getSnapshotKey(for: context.family))
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let entry = SimpleEntry(date: Date(), snapshotKey: getSnapshotKey(for: context.family))
        let timeline = Timeline(entries: [entry], policy: .atEnd)
        completion(timeline)
    }
    
    private func getSnapshotKey(for family: WidgetFamily) -> String {
        switch family {
        case .systemSmall: return "snapshot_small"
        case .systemMedium: return "snapshot_medium"
        case .systemLarge: return "snapshot_large"
        default: return "snapshot_small"
        }
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let snapshotKey: String
}

struct BubbleWidgetEntryView : View {
    var entry: Provider.Entry
    let userDefaults = UserDefaults(suiteName: "group.com.dopop.widget")
    @Environment(\.widgetFamily) var family

    var body: some View {
        ZStack {
            // 1. Flutter에서 렌더링한 스냅샷 이미지
            if let imagePath = userDefaults?.string(forKey: entry.snapshotKey),
               let uiImage = UIImage(contentsOfFile: imagePath) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                FallbackView()
            }
            
            // 2. 인터랙티브 버튼 레이어 (iOS 17+)
            if #available(iOS 17.0, *) {
                InteractiveLayer(family: family, userDefaults: userDefaults)
            }
        }
        .containerBackground(.clear, for: .widget)
    }
}

struct FallbackView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubbles.and.sparkles.fill")
                .font(.system(size: 30))
                .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("DoPop")
                .font(.headline)
                .foregroundColor(.white)
            Text("앱을 열어 데이터를 확인하세요")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 15/255, green: 23/255, blue: 42/255))
    }
}

@available(iOS 17.0, *)
struct InteractiveLayer: View {
    let family: WidgetFamily
    let userDefaults: UserDefaults?
    
    var body: some View {
        let bubbleIdsStr = userDefaults?.string(forKey: "bubble_ids") ?? ""
        let bubbleIds = bubbleIdsStr.isEmpty ? [] : bubbleIdsStr.components(separatedBy: ",")
        
        GeometryReader { geometry in
            if family == .systemSmall {
                // Small: 리스트 형태 터치 영역 (상위 3개)
                VStack(spacing: 0) {
                    Spacer().frame(height: 40) // 헤더 공간 제외
                    ForEach(0..<min(bubbleIds.count, 3), id: \.self) { index in
                        let id = bubbleIds[index]
                        if !id.isEmpty {
                            Button(intent: PopBubbleIntent(id: id)) {
                                Color.white.opacity(0.001)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            } else {
                // Medium/Large: 그리드 형태 터치 영역
                let rows = family == .systemLarge ? 3 : 2
                let cols = 3
                let maxItems = rows * cols
                
                VStack(spacing: 0) {
                    Spacer().frame(height: 40) // 헤더 공간 제외
                    ForEach(0..<rows, id: \.self) { r in
                        HCenter {
                            ForEach(0..<cols, id: \.self) { c in
                                let index = r * cols + c
                                if index < bubbleIds.count {
                                    let id = bubbleIds[index]
                                    if !id.isEmpty {
                                        Button(intent: PopBubbleIntent(id: id)) {
                                            Color.white.opacity(0.001)
                                        }
                                        .buttonStyle(.plain)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    } else {
                                        Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                                    }
                                } else {
                                    Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct HCenter<Content: View>: View {
    let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    var body: some View {
        HStack(spacing: 0) { content() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@main
struct BubbleWidget: Widget {
    let kind: String = "BubbleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            BubbleWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("DoPop")
        .description("오늘의 비눗방울 상태를 확인하세요.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
