import AppKit
import SwiftUI
import UniformTypeIdentifiers
import UtataneCore

struct UtataneSchedule: Codable, Identifiable, Equatable {
    enum Repetition: String, Codable, CaseIterable, Identifiable {
        case none, weekly, monthly, yearly

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .none: String(localized: "なし")
            case .weekly: String(localized: "毎週")
            case .monthly: String(localized: "毎月")
            case .yearly: String(localized: "毎年")
            }
        }
    }

    var id = UUID()
    var type = "event"
    var caption = ""
    var subtitle = ""
    var script = ""
    var start: Date
    var end: Date
    var isAllDay = false
    var repetition = Repetition.none
    var soundPath: String?
}

@MainActor
final class CalendarWindowController: NSWindowController, ObservableObject {
    @Published private(set) var schedules: [UtataneSchedule] = []
    @Published private(set) var skins: [CalendarSkin] = []
    @Published var selectedSkinID: String? {
        didSet { UserDefaults.standard.set(selectedSkinID, forKey: "UtataneCalendarSkin") }
    }

    var onRead: ((UtataneSchedule, String) -> Void)?
    var onCalendarEvent: ((String, [Int: String]) -> Void)?

    private let storeURL: URL
    private let skinDirectories: [URL]
    private var notifiedOccurrences = Set<String>()

    init(storeURL: URL, skinDirectories: [URL] = []) {
        self.storeURL = storeURL
        self.skinDirectories = skinDirectories
        skins = CalendarSkinLoader().load(from: skinDirectories)
        selectedSkinID = UserDefaults.standard.string(forKey: "UtataneCalendarSkin")
        super.init(window: nil)
        load()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func showCalendar() {
        if window == nil {
            let view = CalendarView(controller: self)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = String(localized: "カレンダー")
            window.setContentSize(NSSize(width: 680, height: 440))
            window.minSize = NSSize(width: 620, height: 420)
            window.styleMask.insert([.resizable, .closable, .miniaturizable, .titled])
            window.isReleasedWhenClosed = false
            self.window = window
        }
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func schedules(on date: Date, calendar: Calendar = .current) -> [UtataneSchedule] {
        schedules.filter { occurs($0, on: date, calendar: calendar) }.sorted { $0.start < $1.start }
    }

    var selectedSkin: CalendarSkin? {
        guard let selectedSkinID else { return nil }
        return skins.first(where: { $0.id == selectedSkinID })
    }

    func reloadSkins() {
        skins = CalendarSkinLoader().load(from: skinDirectories)
        if let selectedSkinID, !skins.contains(where: { $0.id == selectedSkinID }) {
            self.selectedSkinID = nil
        }
    }

    func add(on date: Date, calendar: Calendar = .current) -> UUID {
        let day = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .hour, value: 12, to: day) ?? day
        let schedule = UtataneSchedule(start: start, end: start.addingTimeInterval(3600))
        schedules.append(schedule)
        save()
        return schedule.id
    }

    func update(_ schedule: UtataneSchedule) {
        guard let index = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        schedules[index] = schedule
        save()
    }

    func delete(_ id: UUID) {
        schedules.removeAll { $0.id == id }
        save()
    }

    func deleteSchedules(on date: Date, calendar: Calendar = .current) {
        schedules.removeAll { occurs($0, on: date, calendar: calendar) }
        save()
    }

    func deleteSchedules(inMonthContaining date: Date, calendar: Calendar = .current) {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return }
        schedules.removeAll { schedule in
            switch schedule.repetition {
            case .none:
                interval.contains(schedule.start)
            case .weekly, .monthly:
                schedule.start < interval.end
            case .yearly:
                schedule.start < interval.end
                    && calendar.component(.month, from: schedule.start) == calendar.component(.month, from: date)
            }
        }
        save()
    }

    func deleteAllSchedules() {
        schedules.removeAll()
        save()
    }

    func importICalendar(from url: URL) {
        let sensorName = url.deletingPathExtension().lastPathComponent
        onCalendarEvent?("OnSchedulesenseBegin", [0: sensorName])
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            let imported = try ICalendarCodec().decode(source)
            schedules.append(contentsOf: imported)
            save()
            onCalendarEvent?("OnSchedulesenseComplete", [0: sensorName, 1: String(imported.count)])
        } catch {
            onCalendarEvent?("OnSchedulesenseFailure", [0: error is CocoaError ? "fileio" : "can't analyze"])
        }
    }

    func beginICalendarExport() {
        onCalendarEvent?("OnSchedulepostBegin", [0: "iCalendar"])
    }

    func completeICalendarExport(succeeded: Bool) {
        if succeeded {
            onCalendarEvent?("OnSchedulepostComplete", [0: "iCalendar"])
        }
    }

    var iCalendarDocument: ICalendarDocument {
        ICalendarDocument(source: ICalendarCodec().encode(schedules))
    }

    func checkFiveMinuteReminders(at now: Date, calendar: Calendar = .current) {
        for schedule in schedules where !schedule.isAllDay {
            guard let occurrence = occurrenceStart(for: schedule, around: now, calendar: calendar) else { continue }
            let remaining = occurrence.timeIntervalSince(now)
            guard remaining > 270, remaining <= 300 else { continue }
            let key = "\(schedule.id.uuidString):\(Int(occurrence.timeIntervalSince1970))"
            guard notifiedOccurrences.insert(key).inserted else { continue }
            if let soundPath = schedule.soundPath, !soundPath.isEmpty {
                NSSound(contentsOfFile: soundPath, byReference: true)?.play()
            }
            onRead?(schedule, "OnSchedule5MinutesToGo")
        }
    }

    private func occurs(_ schedule: UtataneSchedule, on date: Date, calendar: Calendar) -> Bool {
        let candidate = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        let origin = calendar.dateComponents([.year, .month, .day, .weekday], from: schedule.start)
        guard calendar.startOfDay(for: date) >= calendar.startOfDay(for: schedule.start) else { return false }
        return switch schedule.repetition {
        case .none:
            candidate.year == origin.year && candidate.month == origin.month && candidate.day == origin.day
        case .weekly: candidate.weekday == origin.weekday
        case .monthly: candidate.day == origin.day
        case .yearly: candidate.month == origin.month && candidate.day == origin.day
        }
    }

    private func occurrenceStart(for schedule: UtataneSchedule, around date: Date, calendar: Calendar) -> Date? {
        guard occurs(schedule, on: date, calendar: calendar) else { return nil }
        let time = calendar.dateComponents([.hour, .minute, .second], from: schedule.start)
        return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: date)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([UtataneSchedule].self, from: data)
        else { return }
        schedules = decoded
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(schedules)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            AppLogStore.shared.error("カレンダーの保存に失敗しました: \(error.localizedDescription)", category: "Calendar")
        }
    }
}

private struct CalendarView: View {
    @ObservedObject var controller: CalendarWindowController
    @State private var selectedDate = Date()
    @State private var selectedID: UUID?
    @State private var deletion: ScheduleDeletion?
    @State private var importsCalendar = false
    @State private var exportsCalendar = false

    private var daySchedules: [UtataneSchedule] {
        controller.schedules(on: selectedDate)
    }

    var body: some View {
        HSplitView {
            VStack {
                if let skin = controller.selectedSkin {
                    CalendarSkinView(
                        skin: skin,
                        selectedDate: $selectedDate,
                        schedules: controller.schedules
                    )
                    .frame(width: skin.size.width, height: skin.size.height)
                } else {
                    NativeCalendarView(
                        selectedDate: $selectedDate,
                        schedules: controller.schedules
                    )
                    .frame(width: 360, height: 320)
                }
                Picker("スキン", selection: $controller.selectedSkinID) {
                    Text("Utatane標準").tag(String?.none)
                    if !controller.skins.isEmpty {
                        ForEach(controller.skins) { skin in
                            Text(skin.name).tag(Optional(skin.id))
                        }
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)
                Spacer(minLength: 0)
            }
            .padding(.vertical)
            .frame(minWidth: 400, idealWidth: 420, maxWidth: 440, maxHeight: .infinity, alignment: .top)
            Group {
                if let selectedID, let schedule = controller.schedules.first(where: { $0.id == selectedID }) {
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            self.selectedID = nil
                        } label: {
                            Label("戻る", systemImage: "chevron.left")
                        }
                        .buttonStyle(.plain)
                        Divider()
                        ScrollView {
                            ScheduleEditor(schedule: schedule, onUpdate: controller.update, onDelete: {
                                controller.delete(selectedID)
                                self.selectedID = nil
                            }, onRead: { controller.onRead?($0, "OnScheduleRead") })
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(selectedDate.formatted(date: .long, time: .omitted)).font(.headline)
                            Spacer()
                            Menu {
                                Button("iCalendarを読み込む…") { importsCalendar = true }
                                Button("iCalendarを書き出す…") {
                                    controller.beginICalendarExport()
                                    exportsCalendar = true
                                }
                                Divider()
                                Button("この日の予定を削除", role: .destructive) { deletion = .day }
                                Button("この月の予定を削除", role: .destructive) { deletion = .month }
                                Button("すべての予定を削除", role: .destructive) { deletion = .all }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            Button("追加") { selectedID = controller.add(on: selectedDate) }
                        }
                        List(daySchedules, selection: $selectedID) { schedule in
                            VStack(alignment: .leading) {
                                Text(schedule.caption.isEmpty ? String(localized: "新しい予定") : schedule.caption)
                                Text(schedule.isAllDay ? String(localized: "時間指定なし") : schedule.start.formatted(date: .omitted, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }.tag(schedule.id)
                        }
                    }
                }
            }
            .padding()
            .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: 760, minHeight: 420)
        .confirmationDialog("予定を削除しますか？", isPresented: Binding(
            get: { deletion != nil },
            set: {
                if !$0 {
                    deletion = nil
                }
            }
        ), titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                switch deletion {
                case .day: controller.deleteSchedules(on: selectedDate)
                case .month: controller.deleteSchedules(inMonthContaining: selectedDate)
                case .all: controller.deleteAllSchedules()
                case nil: break
                }
                deletion = nil
            }
            Button("キャンセル", role: .cancel) { deletion = nil }
        }
        .fileImporter(isPresented: $importsCalendar, allowedContentTypes: [.calendarEvent]) { result in
            guard case let .success(url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            controller.importICalendar(from: url)
        }
        .fileExporter(
            isPresented: $exportsCalendar,
            document: controller.iCalendarDocument,
            contentType: .calendarEvent,
            defaultFilename: "Utatane Calendar"
        ) { result in
            controller.completeICalendarExport(succeeded: (try? result.get()) != nil)
        }
    }
}

private enum ScheduleDeletion {
    case day, month, all
}

struct ICalendarDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.calendarEvent]
    }

    let source: String

    init(source: String) {
        self.source = source
    }

    init(configuration: ReadConfiguration) throws {
        source = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(source.utf8))
    }
}

struct ICalendarCodec {
    func decode(_ source: String) throws -> [UtataneSchedule] {
        let lines = unfoldedLines(source)
        var schedules: [UtataneSchedule] = []
        var fields: [String: String] = [:]
        var isEvent = false
        for line in lines {
            if line == "BEGIN:VEVENT" {
                fields = [:]
                isEvent = true
            } else if line == "END:VEVENT", isEvent {
                guard let startSource = fields["DTSTART"], let start = parseDate(startSource) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let allDay = startSource.count == 8
                let end = fields["DTEND"].flatMap(parseDate) ?? start.addingTimeInterval(allDay ? 86400 : 3600)
                schedules.append(UtataneSchedule(
                    type: fields["CATEGORIES"]?.lowercased() ?? "event",
                    caption: unescape(fields["SUMMARY"] ?? ""),
                    subtitle: unescape(fields["DESCRIPTION"] ?? ""),
                    start: start,
                    end: end,
                    isAllDay: allDay,
                    repetition: repetition(fields["RRULE"])
                ))
                isEvent = false
            } else if isEvent, let separator = line.firstIndex(of: ":") {
                let rawKey = String(line[..<separator])
                let key = rawKey.split(separator: ";", maxSplits: 1).first.map(String.init) ?? rawKey
                fields[key.uppercased()] = String(line[line.index(after: separator)...])
            }
        }
        return schedules
    }

    func encode(_ schedules: [UtataneSchedule]) -> String {
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Utatane//Calendar//JA"]
        for schedule in schedules {
            lines += [
                "BEGIN:VEVENT",
                "UID:\(schedule.id.uuidString)@utatane",
                schedule.isAllDay ? "DTSTART;VALUE=DATE:\(formatDate(schedule.start, allDay: true))" : "DTSTART:\(formatDate(schedule.start, allDay: false))",
                schedule.isAllDay ? "DTEND;VALUE=DATE:\(formatDate(schedule.end, allDay: true))" : "DTEND:\(formatDate(schedule.end, allDay: false))",
                "SUMMARY:\(escape(schedule.caption))",
                "DESCRIPTION:\(escape(schedule.subtitle))",
                "CATEGORIES:\(schedule.type)"
            ]
            if schedule.repetition != .none {
                lines.append("RRULE:FREQ=\(schedule.repetition.rawValue.uppercased())")
            }
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private func unfoldedLines(_ source: String) -> [String] {
        source.replacingOccurrences(of: "\r\n ", with: "").replacingOccurrences(of: "\r\n\t", with: "")
            .components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .newlines) }
    }

    private func parseDate(_ source: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = source.hasSuffix("Z") ? TimeZone(secondsFromGMT: 0) : .current
        formatter.dateFormat = source.count == 8 ? "yyyyMMdd" : source.hasSuffix("Z") ? "yyyyMMdd'T'HHmmss'Z'" : "yyyyMMdd'T'HHmmss"
        return formatter.date(from: source)
    }

    private func formatDate(_ date: Date, allDay: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = allDay ? "yyyyMMdd" : "yyyyMMdd'T'HHmmss"
        return formatter.string(from: date)
    }

    private func repetition(_ rule: String?) -> UtataneSchedule.Repetition {
        guard let frequency = rule?.uppercased().split(separator: ";").first(where: { $0.hasPrefix("FREQ=") })?
            .dropFirst("FREQ=".count)
        else { return .none }
        return UtataneSchedule.Repetition(rawValue: frequency.lowercased()) ?? .none
    }

    private func escape(_ source: String) -> String {
        source.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: ",", with: "\\,")
    }

    private func unescape(_ source: String) -> String {
        source.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\\\", with: "\\")
    }
}

private struct NativeCalendarView: View {
    @Binding var selectedDate: Date
    let schedules: [UtataneSchedule]
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { changeMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                Spacer()
                Text(monthTitle).font(.headline)
                Spacer()
                Button { changeMonth(1) } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                    Text(symbol)
                        .font(.caption)
                        .foregroundStyle(index == 0 ? .red : index == 6 ? .blue : .secondary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayButton(date)
                    } else {
                        Color.clear.frame(height: 38)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.6)))
    }

    private var monthTitle: String {
        selectedDate.formatted(.dateTime.year().month(.wide))
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var days: [Date?] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)),
              let range = calendar.range(of: .day, in: .month, for: monthStart)
        else { return [] }
        let weekday = calendar.component(.weekday, from: monthStart)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var result = [Date?](repeating: nil, count: leading)
        result += range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: monthStart) }
        result += Array(repeating: nil, count: max(0, 42 - result.count))
        return result
    }

    private func dayButton(_ date: Date) -> some View {
        let selected = calendar.isDate(date, inSameDayAs: selectedDate)
        let today = calendar.isDateInToday(date)
        let hasSchedule = schedules.contains { scheduleOccurs($0, on: date) }
        let weekday = calendar.component(.weekday, from: date)
        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 1) {
                Text(String(calendar.component(.day, from: date)))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(weekday == 1 ? .red : weekday == 7 ? .blue : .primary)
                Circle()
                    .fill(hasSchedule ? Color.accentColor : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(selected ? Color.accentColor.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                if today {
                    RoundedRectangle(cornerRadius: 7).stroke(Color.accentColor, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func scheduleOccurs(_ schedule: UtataneSchedule, on date: Date) -> Bool {
        guard calendar.startOfDay(for: date) >= calendar.startOfDay(for: schedule.start) else { return false }
        let candidate = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        let origin = calendar.dateComponents([.year, .month, .day, .weekday], from: schedule.start)
        return switch schedule.repetition {
        case .none: candidate.year == origin.year && candidate.month == origin.month && candidate.day == origin.day
        case .weekly: candidate.weekday == origin.weekday
        case .monthly: candidate.day == origin.day
        case .yearly: candidate.month == origin.month && candidate.day == origin.day
        }
    }

    private func changeMonth(_ amount: Int) {
        if let changed = calendar.date(byAdding: .month, value: amount, to: selectedDate) {
            selectedDate = changed
        }
    }
}

struct CalendarSkin: Identifiable {
    let id: String
    let name: String
    let directory: URL
    let values: [String: String]
    let icons: [String: String]

    var size: CGSize {
        image(named: values["background.filename"])?.size ?? CGSize(width: 400, height: 320)
    }

    func integer(_ key: String, default fallback: Int = 0) -> Int {
        Int(values[key] ?? "") ?? fallback
    }

    func image(named path: String?) -> NSImage? {
        guard var path, !path.isEmpty else { return nil }
        path = path.replacingOccurrences(of: "\\", with: "/")
        if URL(filePath: path).pathExtension.isEmpty {
            path += ".png"
        }
        return NSImage(contentsOf: directory.appending(path: path))
    }
}

struct CalendarSkinLoader {
    func load(from roots: [URL]) -> [CalendarSkin] {
        var result: [CalendarSkin] = []
        for root in roots {
            guard let directories = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for directory in directories where (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let values = parse(directory.appending(path: "descript.txt"))
                guard values["type"]?.lowercased() == "calendar" else { continue }
                result.append(CalendarSkin(
                    id: values["id"] ?? directory.lastPathComponent,
                    name: values["name"] ?? directory.lastPathComponent,
                    directory: directory,
                    values: values,
                    icons: parse(directory.appending(path: "icon.txt"))
                ))
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func parse(_ url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let text = String(data: data, encoding: .shiftJIS) ?? String(data: data, encoding: .utf8) ?? ""
        return Dictionary(uniqueKeysWithValues: text.components(separatedBy: .newlines).compactMap { line in
            let fields = line.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2 else { return nil }
            return (String(fields[0]).trimmingCharacters(in: .whitespaces), String(fields[1]).trimmingCharacters(in: .whitespaces))
        })
    }
}

private struct CalendarSkinView: View {
    let skin: CalendarSkin
    @Binding var selectedDate: Date
    let schedules: [UtataneSchedule]
    private let calendar = Calendar.current

    var body: some View {
        ZStack(alignment: .topLeading) {
            skinImage(skin.values["background.filename"], x: 0, y: 0)
            yearImages
            skinImage(skin.values["month.filename"].map { "\($0)\(month)" }, x: skin.integer("month.pos.x"), y: skin.integer("month.pos.y"))
            ForEach(days, id: \.date) { day in
                dayCell(day)
            }
            ForEach(days, id: \.date) { day in
                dayClickArea(day)
            }
            Button { changeMonth(-1) } label: { Color.clear.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .frame(width: regionWidth("prev"), height: regionHeight("prev"))
                .position(x: regionCenterX("prev"), y: regionCenterY("prev"))
                .zIndex(10)
            Button { changeMonth(1) } label: { Color.clear.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .frame(width: regionWidth("next"), height: regionHeight("next"))
                .position(x: regionCenterX("next"), y: regionCenterY("next"))
                .zIndex(10)
        }
        .frame(width: skin.size.width, height: skin.size.height, alignment: .topLeading)
    }

    private var month: Int {
        calendar.component(.month, from: selectedDate)
    }

    private var year: Int {
        calendar.component(.year, from: selectedDate)
    }

    private var tableLeft: CGFloat {
        CGFloat(skin.integer("table.left"))
    }

    private var tableTop: CGFloat {
        CGFloat(skin.integer("table.top"))
    }

    private var cellWidth: CGFloat {
        CGFloat(skin.integer("table.right") - skin.integer("table.left")) / 7
    }

    private var cellHeight: CGFloat {
        CGFloat(skin.integer("table.bottom") - skin.integer("table.top")) / 5
    }

    private var days: [(date: Date, column: Int, row: Int)] {
        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: start)
        else { return [] }
        let offset = calendar.component(.weekday, from: start) - 1
        return range.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: start).map {
                let index = offset + day - 1
                return ($0, index % 7, index / 7)
            }
        }
    }

    @ViewBuilder private var yearImages: some View {
        let digits = String(year).compactMap { Int(String($0)) }
        let spacing = skin.integer("year.spacing")
        let base = skin.values["year.filename"] ?? ""
        ForEach(Array(digits.enumerated()), id: \.offset) { index, digit in
            let width = skin.image(named: "\(base)\(digit)")?.size.width ?? 0
            skinImage("\(base)\(digit)", x: skin.integer("year.pos.x") + index * (Int(width) + spacing), y: skin.integer("year.pos.y"))
        }
    }

    @ViewBuilder private func dayCell(_ day: (date: Date, column: Int, row: Int)) -> some View {
        let originX = tableLeft + CGFloat(day.column) * cellWidth
        let originY = tableTop + CGFloat(day.row) * cellHeight
        let isToday = calendar.isDateInToday(day.date)
        let isSelected = calendar.isDate(day.date, inSameDayAs: selectedDate)
        if isSelected {
            skinImage(skin.values["current.filename"], x: Int(originX) + skin.integer("current.pos.x"), y: Int(originY) + skin.integer("current.pos.y"))
        }
        if isToday {
            skinImage(skin.values["today.filename"], x: Int(originX) + skin.integer("today.pos.x"), y: Int(originY) + skin.integer("today.pos.y"))
        }
        let dayNumber = calendar.component(.day, from: day.date)
        let prefixKey = day.column == 6 ? "saturday.filename" : day.column == 0 ? "holiday.filename" : "day.filename"
        let prefix = skin.values[prefixKey] ?? skin.values["day.filename"] ?? ""
        digitImages(dayNumber, prefix: prefix, x: Int(originX) + skin.integer("day.pos.x"), y: Int(originY) + skin.integer("day.pos.y"))
        if let schedule = schedules.first(where: { calendar.isDate($0.start, inSameDayAs: day.date) }),
           let icon = skin.icons[schedule.type] ?? skin.icons["default"]
        {
            skinImage(icon, x: Int(originX) + skin.integer("icon.left"), y: Int(originY) + skin.integer("icon.top"))
        }
    }

    private func digitImages(_ number: Int, prefix: String, x: Int, y: Int) -> some View {
        let images = String(number).compactMap { skin.image(named: "\(prefix)\($0)") }
        let spacing = CGFloat(skin.integer("day.spacing"))
        let width = images.reduce(0) { $0 + $1.size.width } + spacing * CGFloat(max(0, images.count - 1))
        let height = images.map(\.size.height).max() ?? 0
        return HStack(spacing: CGFloat(skin.integer("day.spacing"))) {
            ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                Image(nsImage: image).interpolation(.none)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .position(x: CGFloat(x) + width / 2, y: CGFloat(y) + height / 2)
    }

    private func dayClickArea(_ day: (date: Date, column: Int, row: Int)) -> some View {
        Button {
            selectedDate = day.date
        } label: {
            Color.clear.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: cellWidth, height: cellHeight)
        .position(
            x: tableLeft + (CGFloat(day.column) + 0.5) * cellWidth,
            y: tableTop + (CGFloat(day.row) + 0.5) * cellHeight
        )
        .zIndex(5)
    }

    @ViewBuilder
    private func skinImage(_ path: String?, x: Int, y: Int) -> some View {
        if let image = skin.image(named: path) {
            Image(nsImage: image)
                .interpolation(.none)
                .frame(width: image.size.width, height: image.size.height)
                .position(x: CGFloat(x) + image.size.width / 2, y: CGFloat(y) + image.size.height / 2)
        }
    }

    private func changeMonth(_ value: Int) {
        if let date = calendar.date(byAdding: .month, value: value, to: selectedDate) {
            selectedDate = date
        }
    }

    private func regionWidth(_ name: String) -> CGFloat {
        CGFloat(skin.integer("\(name).right") - skin.integer("\(name).left"))
    }

    private func regionHeight(_ name: String) -> CGFloat {
        CGFloat(skin.integer("\(name).bottom") - skin.integer("\(name).top"))
    }

    private func regionCenterX(_ name: String) -> CGFloat {
        CGFloat(skin.integer("\(name).left") + skin.integer("\(name).right")) / 2
    }

    private func regionCenterY(_ name: String) -> CGFloat {
        CGFloat(skin.integer("\(name).top") + skin.integer("\(name).bottom")) / 2
    }
}

private struct ScheduleEditor: View {
    @State var schedule: UtataneSchedule
    let onUpdate: (UtataneSchedule) -> Void
    let onDelete: () -> Void
    let onRead: (UtataneSchedule) -> Void
    @State private var importsSound = false

    var body: some View {
        Form {
            TextField("内容", text: binding(\.caption))
            TextField("補足", text: binding(\.subtitle))
            TextField("種類", text: binding(\.type))
            Toggle("時間指定なし", isOn: binding(\.isAllDay))
            if !schedule.isAllDay {
                DatePicker("開始", selection: binding(\.start))
                DatePicker("終了", selection: binding(\.end))
            }
            Picker("繰り返し", selection: binding(\.repetition)) {
                ForEach(UtataneSchedule.Repetition.allCases) { repetition in
                    Text(repetition.title).tag(repetition)
                }
            }
            TextField("詳しい内容（SakuraScript使用可）", text: binding(\.script), axis: .vertical)
            HStack {
                TextField("通知音", text: optionalBinding(\.soundPath))
                Button("選択…") { importsSound = true }
            }
            HStack {
                Button("予定を読む") { onRead(schedule) }
                Spacer()
                Button("削除", role: .destructive, action: onDelete)
            }
        }
        .fileImporter(isPresented: $importsSound, allowedContentTypes: [.audio]) { result in
            guard case let .success(url) = result else { return }
            schedule.soundPath = url.path
            onUpdate(schedule)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<UtataneSchedule, Value>) -> Binding<Value> {
        Binding(get: { schedule[keyPath: keyPath] }, set: {
            schedule[keyPath: keyPath] = $0
            onUpdate(schedule)
        })
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<UtataneSchedule, String?>) -> Binding<String> {
        Binding(get: { schedule[keyPath: keyPath] ?? "" }, set: {
            schedule[keyPath: keyPath] = $0.isEmpty ? nil : $0
            onUpdate(schedule)
        })
    }
}
