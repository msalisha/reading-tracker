import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

@main
struct ReadingWidgetsBundle: WidgetBundle {
    var body: some Widget {
        StreakWidget()
        CurrentBookWidget()
        ReadingLiveActivity()
    }
}

// MARK: timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let timer: ActiveTimer?
    let theme: AppTheme
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        var s = WidgetSnapshot()
        s.pagesByDay = [Day.key(.now): 24, Day.key(Day.add(-1, to: .now)): 30, Day.key(Day.add(-2, to: .now)): 12]
        s.currentBook = .init(id: "x", title: "Pride and Prejudice", author: "Jane Austen", page: 148, totalPages: 432, cover: nil)
        return SnapshotEntry(date: .now, snapshot: s, timer: nil, theme: .neon)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // Redraw just after midnight so "today" and the streak roll over.
        let midnight = Day.calendar.startOfDay(for: Day.add(1, to: .now)).addingTimeInterval(60)
        completion(Timeline(entries: [entry()], policy: .after(midnight)))
    }

    private func entry() -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load(), timer: TimerStorage.load(), theme: AppTheme.current)
    }
}

// MARK: streak (small + lock screen)

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Streak", provider: SnapshotProvider()) { entry in
            StreakView(entry: entry)
        }
        .configurationDisplayName("Streak")
        .description("Your reading streak and today's pages.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct StreakView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let streak = entry.snapshot.streak(now: entry.date)
        let today = entry.snapshot.pagesToday(now: entry.date)
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: "flame.fill").font(.caption)
                Text("\(streak)").font(.system(.title2, design: .rounded, weight: .black))
            }
            .containerBackground(for: .widget) { AccessoryWidgetBackground() }
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("\(streak)-day streak").font(.headline)
                Text("\(today) pages today").font(.caption)
            }
            .containerBackground(for: .widget) { Color.clear }
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text("STREAK").font(.caption2.weight(.bold)).foregroundStyle(entry.theme.boardMuted)
                Text("\(streak)").font(.system(size: 44, weight: .black, design: .rounded)).foregroundStyle(entry.theme.highlight)
                    .minimumScaleFactor(0.5)
                Text(streak == 1 ? "day" : "days in a row").font(.caption).foregroundStyle(entry.theme.boardMuted)
                Spacer(minLength: 4)
                Text("\(today) pages today").font(.footnote.weight(.bold)).foregroundStyle(entry.theme.boardText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { entry.theme.board }
            .widgetURL(URL(string: "\(Links.scheme)://timer"))
        }
    }
}

// MARK: current book (medium)

struct CurrentBookWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CurrentBook", provider: SnapshotProvider()) { entry in
            CurrentBookView(entry: entry)
        }
        .configurationDisplayName("Current book")
        .description("Your progress, with a button to start the timer.")
        .supportedFamilies([.systemMedium])
    }
}

struct CurrentBookView: View {
    let entry: SnapshotEntry

    var body: some View {
        let theme = entry.theme
        Group {
            if let b = entry.snapshot.currentBook {
                HStack(spacing: 14) {
                    cover(b, theme)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(b.title).font(.headline).foregroundStyle(theme.boardText).lineLimit(2)
                        if !b.author.isEmpty { Text(b.author).font(.caption).foregroundStyle(theme.boardMuted).lineLimit(1) }
                        let frac = Double(b.page) / Double(max(1, b.totalPages))
                        ProgressView(value: frac).tint(theme.brand)
                        Text("Page \(b.page) of \(b.totalPages) · \(Int((frac * 100).rounded()))%")
                            .font(.caption).foregroundStyle(theme.boardMuted)
                        Spacer(minLength: 0)
                        if let t = entry.timer, t.bookID == b.id {
                            Text(t.status == .running ? "Timer running" : "Timer paused")
                                .font(.caption.weight(.bold)).foregroundStyle(theme.highlight)
                        } else {
                            Link(destination: URL(string: "\(Links.scheme)://start?book=\(b.id)")!) {
                                Label("Start timer", systemImage: "timer")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .foregroundStyle(theme.onHighlight)
                                    .background(theme.highlight, in: Capsule())
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nothing on the go").font(.headline).foregroundStyle(theme.boardText)
                    Text("Add a book in the app and it shows here.").font(.caption).foregroundStyle(theme.boardMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .containerBackground(for: .widget) { theme.board }
    }

    @ViewBuilder private func cover(_ b: WidgetSnapshot.CurrentBook, _ theme: AppTheme) -> some View {
        if let data = b.cover, let img = UIImage(data: data) {
            Image(uiImage: img).resizable().scaledToFill().frame(width: 72, height: 108).clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8).fill(theme.brand).frame(width: 72, height: 108)
                .overlay(Text(b.title.prefix(1)).font(.system(.title, design: .rounded, weight: .black)).foregroundStyle(theme.onBrand))
        }
    }
}

// MARK: Live Activity (lock screen + Dynamic Island)

struct ReadingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadingActivityAttributes.self) { context in
            LockScreenTimer(context: context, theme: AppTheme.current)
                .activityBackgroundTint(AppTheme.current.board)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "\(Links.scheme)://timer"))
        } dynamicIsland: { context in
            let theme = AppTheme.current
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Reading", systemImage: "book.fill").font(.caption.weight(.bold)).foregroundStyle(theme.highlight)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerText(state: context.state).font(.system(.title3, design: .rounded, weight: .black))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.bookTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer()
                        PauseResumeButton(isRunning: context.state.isRunning, theme: theme)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isRunning ? "book.fill" : "pause.fill").foregroundStyle(theme.highlight)
            } compactTrailing: {
                TimerText(state: context.state).frame(maxWidth: 52).font(.caption.weight(.bold))
            } minimal: {
                Image(systemName: "book.fill").foregroundStyle(theme.highlight)
            }
            .widgetURL(URL(string: "\(Links.scheme)://timer"))
        }
    }
}

struct TimerText: View {
    let state: ReadingActivityAttributes.ContentState
    var body: some View {
        if state.isRunning {
            Text(timerInterval: ClosedRange(uncheckedBounds: (lower: state.clockStart, upper: Date.distantFuture)), countsDown: false)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        } else {
            Text(ActiveTimer.clock(state.elapsed)).monospacedDigit().opacity(0.6)
        }
    }
}

struct PauseResumeButton: View {
    let isRunning: Bool
    let theme: AppTheme
    var body: some View {
        Group {
            if isRunning {
                Button(intent: PauseReadingIntent()) { Label("Pause", systemImage: "pause.fill") }
            } else {
                Button(intent: ResumeReadingIntent()) { Label("Resume", systemImage: "play.fill") }
            }
        }
        .font(.subheadline.weight(.bold))
        .tint(theme.highlight)
        .foregroundStyle(theme.onHighlight)
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
    }
}

struct LockScreenTimer: View {
    let context: ActivityViewContext<ReadingActivityAttributes>
    let theme: AppTheme

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.state.isRunning ? "READING NOW" : "PAUSED")
                    .font(.caption2.weight(.bold)).foregroundStyle(theme.boardMuted)
                Text(context.attributes.bookTitle).font(.headline).foregroundStyle(.white).lineLimit(1)
                Text("From page \(context.state.startPage)").font(.caption).foregroundStyle(theme.boardMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                TimerText(state: context.state)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(context.state.isRunning ? theme.highlight : .white)
                PauseResumeButton(isRunning: context.state.isRunning, theme: theme)
            }
        }
        .padding(16)
    }
}
