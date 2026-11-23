import SwiftUI
import HealthKit
import CoreLocation
import Photos
import PhotosUI
import UIKit
import ImageIO


struct RouteArtView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let backgrounds = ["山", "森", "夕暮れ"]
    @State private var background = ["山", "森", "夕暮れ"].randomElement() ?? "山"
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var customBackground: UIImage?
    @State private var photoRequestID = UUID()
    @State private var backgroundRevision = UUID()
    @State private var photoMessage = ""
    @State private var isLoadingPhoto = false
    @State private var points: [CLLocationCoordinate2D] = []
    @State private var breakIndices: Set<Int> = []
    @State private var status = "ヘルスケアのランを読み込んで作品を作れます"
    @State private var selectedWorkout: HKWorkout?
    @State private var workouts: [HKWorkout] = []
    @State private var selectedIndex = 0
    @State private var isSelectingWorkout = false
    @State private var showingSavedArtworks = false
    @State private var selectionFeedbackWorkoutID: UUID?
    @State private var routeUpdateAvailable = false
    @State private var routeObserverFailed = false
    @State private var storageMessage = ""
    @State private var lineColor = "オレンジ"
    @State private var lineStyle = "実線"
    @State private var sceneryFocused = true
    @State private var hideEndpoints = true
    @State private var exportMessage = ""
    @State private var exportRequestID = UUID()
    @State private var hasRequestedRoute = false
    @State private var needsRefresh = false
    @State private var requestID = UUID()
    @State private var routeObserver: HKAnchoredObjectQuery?
    @State private var observerID = UUID()
    private var sceneryAssetName: String {
        assetName(for: background)
    }
    private func assetName(for background: String) -> String {
        switch background {
        case "山": return "RouteSceneryCoast"
        case "森": return "RouteSceneryForest"
        default: return "RouteScenerySunset"
        }
    }
    private var routeColor: Color {
        switch lineColor { case "オレンジ": return .orange; case "水色": return .cyan; default: return .white }
    }
    private var artworkRoute: (points: [CLLocationCoordinate2D], breaks: Set<Int>) {
        let input = points
        let originalBreaks = breakIndices
        guard hideEndpoints else { return (input, originalBreaks) }
        return RoutePrivacyProbe.mask(input, breaks: originalBreaks, radius: 200)
    }
    private var hasVisibleLine: Bool {
        let route = artworkRoute
        return RoutePrivacyProbe.hasDrawableLine(route.points, breaks: route.breaks)
    }
    private var exportSettings: ExportSettings {
        let segmentEnds = false
        return ExportSettings(background: background, backgroundRevision: backgroundRevision, color: lineColor, style: lineStyle,
                              hideEndpoints: hideEndpoints, hideSegmentEnds: segmentEnds,
                              sceneryFocused: sceneryFocused)
    }
    private let store = HKHealthStore()
    var body: some View {
            ScrollView {
                VStack(spacing: 16) {
                    Text("ヘルスケアに保存されたランとルートから作品を作ります。保存は任意です。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("ヘルスケアのランを読み込む") { read() }.buttonStyle(.borderedProminent)
                    Button("保存した作品を見る") { showingSavedArtworks = true }
                    artwork.aspectRatio(4.0 / 5.0, contentMode: .fit)
                    Text(status).font(.footnote)
                    Text("背景を選ぶ").font(.headline)
                    HStack(spacing: 8) {
                        ForEach(backgrounds, id: \.self) { name in
                            Button {
                                photoRequestID = UUID()
                                isLoadingPhoto = false
                                selectedPhoto = nil
                                customBackground = nil
                                background = name
                                backgroundRevision = UUID()
                                photoMessage = ""
                            } label: {
                                VStack(spacing: 4) {
                                    Image(uiImage: UIImage(named: assetName(for: name)) ?? UIImage())
                                        .resizable().scaledToFill().frame(height: 64).clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    Text(name).font(.caption)
                                    if customBackground == nil && background == name {
                                        Image(systemName: "checkmark.circle.fill").accessibilityLabel("選択中")
                                    }
                                }.frame(maxWidth: .infinity)
                            }.buttonStyle(.plain).accessibilityLabel("\(name)の背景")
                        }
                    }
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("自分の写真を選ぶ", systemImage: "photo")
                    }.buttonStyle(.bordered)
                    if isLoadingPhoto { ProgressView("写真を読み込み中") }
                    if !photoMessage.isEmpty { Text(photoMessage).font(.caption).foregroundStyle(.secondary) }
                    Text("地図風の模様は架空のデザインです。実際の道路や景色を表すものではありません。")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("背景を広く見せる", isOn: $sceneryFocused)
                    Picker("線の色", selection: $lineColor) {
                        Text("白").tag("白"); Text("オレンジ").tag("オレンジ"); Text("水色").tag("水色")
                    }.pickerStyle(.segmented)
                    Picker("線の見た目", selection: $lineStyle) {
                        Text("実線").tag("実線"); Text("点線").tag("点線"); Text("太線").tag("太線"); Text("光る線").tag("光る線")
                    }.pickerStyle(.segmented)
                    Toggle("開始・終了地点の周囲を隠す（約200m）", isOn: $hideEndpoints)
                    if !points.isEmpty && !hasVisibleLine {
                        Text(hideEndpoints ? "表示できるルートが残りません。設定を変更してください。" : "表示できるルートがありません。別のランをお試しください。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("一部を隠しても、ルートの形などから場所が推測される可能性があります。保存前に画像をご確認ください。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("作品をアプリ内に保存") { saveProbeArtwork() }
                        .buttonStyle(.borderedProminent).disabled(!hasVisibleLine || isSelectingWorkout || isLoadingPhoto)
                    if !storageMessage.isEmpty { Text(storageMessage).font(.caption) }
                    Button("写真に保存") { saveImage() }.buttonStyle(.bordered)
                        .disabled(!hasVisibleLine || isSelectingWorkout || isLoadingPhoto)
                    if !exportMessage.isEmpty { Text(exportMessage).font(.caption) }
                    if !workouts.isEmpty {
                        DisclosureGroup("直近のランから選ぶ（最大30件）") {
                            Text("ルートがないランも表示されます。選択後にルートを確認します。")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(Array(workouts.enumerated()), id: \.element.uuid) { index, workout in
                                Button {
                                    selectWorkout(at: index)
                                } label: {
                                    workoutRow(workout)
                                }
                                .disabled(isSelectingWorkout)
                                if selectionFeedbackWorkoutID == workout.uuid {
                                    Text(status).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if selectedWorkout != nil {
                        Button("次に新しいルート付きランを探す") { selectWorkout(step: -1) }
                            .buttonStyle(.bordered).disabled(isSelectingWorkout)
                        Button("次に古いルート付きランを探す") { selectWorkout(step: 1) }
                            .buttonStyle(.bordered).disabled(isSelectingWorkout)
                    }
                    if routeUpdateAvailable {
                        Text("ルートが更新された可能性があります。読み込み直して確認してください。")
                            .font(.caption)
                    }
                    if routeObserverFailed {
                        Text("ルートの更新を確認できません。読み込み直して再試行してください。")
                            .font(.caption)
                    }
                    Text("ヘルスケアのランとルートを読み取り、作品を作ります。保存は任意です。") .font(.caption).foregroundStyle(.secondary)
                }.padding()
            }.navigationTitle("ルートアート")
                .navigationDestination(isPresented: $showingSavedArtworks) { ProbeSavedArtworks() }
        .onDisappear {
            // 一覧への遷移でも発火するため、編集中のルートを保持する。
            guard !showingSavedArtworks else { return }
            photoRequestID = UUID()
            isLoadingPhoto = false
            requestID = UUID()
            stopRouteObserver()
            points = []; breakIndices = []; selectedWorkout = nil; workouts = []
            hasRequestedRoute = false
            needsRefresh = false
            isSelectingWorkout = false
            routeUpdateAvailable = false
            status = "ヘルスケアのランを読み込んで作品を作れます"
        }
        .onChange(of: exportSettings) { _, _ in
            clearExportFeedback()
            storageMessage = ""
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            let request = UUID()
            photoRequestID = request
            isLoadingPhoto = true
            photoMessage = ""
            Task { @MainActor in
                do {
                    let data = try await item.loadTransferable(type: Data.self)
                    guard request == photoRequestID else { return }
                    guard let data, let image = Self.backgroundImage(from: data) else {
                        isLoadingPhoto = false
                        photoMessage = "写真を読み込めませんでした。別の写真をお試しください。"
                        selectedPhoto = nil
                        return
                    }
                    customBackground = image
                    backgroundRevision = UUID()
                    isLoadingPhoto = false
                    photoMessage = "選んだ写真を背景にしています"
                    selectedPhoto = nil
                } catch {
                    guard request == photoRequestID else { return }
                    isLoadingPhoto = false
                    photoMessage = "写真を読み込めませんでした。もう一度お試しください。"
                    selectedPhoto = nil
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && hasRequestedRoute {
                storageMessage = ""
                requestID = UUID()
                clearExportFeedback()
                isSelectingWorkout = false
                selectionFeedbackWorkoutID = nil
                stopRouteObserver()
                points = []; breakIndices = []; selectedWorkout = nil; workouts = []
                status = "ルートを再確認します"
                needsRefresh = true
            } else if phase == .active && needsRefresh {
                needsRefresh = false
                read()
            }
        }
    }
    static func backgroundImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2400
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
    private func workoutRow(_ workout: HKWorkout) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                workoutDate(workout).fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                workoutDurationAndSelection(workout).fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 4) {
                workoutDate(workout)
                workoutDurationAndSelection(workout)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
    private func workoutDate(_ workout: HKWorkout) -> some View {
        Text(workout.endDate, format: .dateTime.year().month().day().hour().minute())
    }
    private func workoutDurationAndSelection(_ workout: HKWorkout) -> some View {
        HStack {
            Text("\(Int(workout.duration / 60))分")
            if workout.uuid == selectedWorkout?.uuid {
                Image(systemName: "checkmark").accessibilityLabel("選択中")
            }
        }
    }
    private var artwork: some View {
        GeometryReader { geometry in
                        ZStack {
                            if let image = customBackground ?? UIImage(named: sceneryAssetName) {
                                Image(uiImage: image).resizable().scaledToFill()
                                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                            } else {
                                SceneryBackground(name: background)
                            }
                            LinearGradient(colors: [.black.opacity(0.56), .clear, .black.opacity(0.34)], startPoint: .top, endPoint: .bottom)
                            VStack(spacing: 0) {
                                VStack(spacing: 5) {
                                    Text("MY RUN").font(.system(size: 10, weight: .semibold)).tracking(3)
                                    if let workout = selectedWorkout {
                                        Text(workout.endDate, format: .dateTime.year().month().day())
                                            .font(.system(size: 24, weight: .medium, design: .serif))
                                        HStack(spacing: 12) {
                                            if let distance = workout.totalDistance?.doubleValue(for: .meter()), distance > 0 {
                                                Text(String(format: "%.2f KM", distance / 1000))
                                            }
                                            Text("\(Int(workout.duration / 60))分")
                                        }.font(.system(size: 11, weight: .semibold)).tracking(1)
                                    } else {
                                        Text("走った日の記録").font(.system(size: 23, weight: .medium, design: .serif))
                                    }
                                }
                                .foregroundStyle(.white).shadow(color: .black.opacity(0.6), radius: 4)
                                .padding(.top, geometry.size.height * 0.07)
                                Spacer(minLength: 0)
                                ZStack {
                                    Image("FictionalMap").resizable().scaledToFit()
                                    let shape = RouteShape(points: artworkRoute.points, smoothSample: false, breakIndices: artworkRoute.breaks)
                                    let width: CGFloat = lineStyle == "太線" ? 7 : 4
                                    let dash: [CGFloat] = lineStyle == "点線" ? [3, 8] : []
                                    shape.stroke(lineColor == "白" ? .black.opacity(0.75) : .white.opacity(0.95), style: StrokeStyle(lineWidth: width + 3, lineCap: .round, lineJoin: .round, dash: dash))
                                        .padding(geometry.size.width * 0.08)
                                    shape.stroke(routeColor, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash))
                                        .shadow(color: lineStyle == "光る線" ? routeColor.opacity(0.8) : .black.opacity(0.25), radius: lineStyle == "光る線" ? 6 : 1)
                                        .padding(geometry.size.width * 0.08)
                                }
                                .frame(width: min(geometry.size.width * (sceneryFocused ? 0.94 : 0.98), geometry.size.height * (sceneryFocused ? 0.64 : 0.69)),
                                       height: min(geometry.size.width * (sceneryFocused ? 0.94 : 0.98), geometry.size.height * (sceneryFocused ? 0.64 : 0.69)))
                                Spacer(minLength: 0)
                                Text("架空の地図風デザイン").font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.white).shadow(color: .black, radius: 3)
                                    .padding(.bottom, 12)
                            }
                        }.frame(width: geometry.size.width, height: geometry.size.height).clipped().clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    @MainActor private func renderImage() -> UIImage? {
        let renderer = ImageRenderer(content: artwork.frame(width: 360, height: 450))
        renderer.scale = 3
        return renderer.uiImage
    }


    @MainActor private func saveImage() {
        clearExportFeedback()
        let currentExport = exportRequestID
        guard let image = renderImage() else { exportMessage = "画像を作成できませんでした"; return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    guard exportRequestID == currentExport else { return }
                    exportMessage = "写真への追加が許可されていません"
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, _ in
                DispatchQueue.main.async {
                    guard exportRequestID == currentExport else { return }
                    exportMessage = success ? "写真に保存しました" : "写真に保存できませんでした"
                }
            }
        }
    }

    private func clearExportFeedback() {
        exportRequestID = UUID()
        exportMessage = ""
    }

    func authorize(write: Bool, isCurrent: @escaping () -> Bool = { true }, completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async { if isCurrent() { status = "HealthKitを利用できません"; completion(false) } }
            return
        }
        let workout = HKObjectType.workoutType(), route = HKSeriesType.workoutRoute()
        store.requestAuthorization(toShare: write ? [workout, route] : [], read: [workout, route]) { ok, error in
            DispatchQueue.main.async {
                guard isCurrent() else { return }
                if let error {
                    status = "権限要求エラー: \(error.localizedDescription)"
                } else if !ok {
                    status = "ヘルスケアへのアクセスを確認できませんでした。もう一度お試しください"
                }
                completion(ok && error == nil)
            }
        }
    }
    func read() {
        isSelectingWorkout = false
        selectionFeedbackWorkoutID = nil
        storageMessage = ""
        hasRequestedRoute = true
        let currentRequest = UUID()
        requestID = currentRequest
        points = []; breakIndices = []; selectedWorkout = nil; workouts = []
        routeUpdateAvailable = false
        clearExportFeedback()
        status = "ルートを読み込み中"
        authorize(write: false, isCurrent: { currentRequest == requestID }) { ok in
            guard currentRequest == requestID, ok else { return }
            startRouteObserver()
            let predicate = HKQuery.predicateForWorkouts(with: .running)
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: 30, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                DispatchQueue.main.async {
                    guard currentRequest == requestID else { return }
                    guard let workouts = samples as? [HKWorkout], error == nil else { status = "ランの読み込みに失敗"; return }
                    self.workouts = workouts
                    findRoute(workouts, index: 0, request: currentRequest)
                }
            }
            store.execute(query)
        }
    }
    // 編集中の自動切替を避け、更新があったことを知らせる検証用の方式。
    func startRouteObserver() {
        guard routeObserver == nil else { return }
        let currentObserver = UUID()
        observerID = currentObserver
        let query = HKAnchoredObjectQuery(type: HKSeriesType.workoutRoute(), predicate: nil, anchor: nil, limit: HKObjectQueryNoLimit) { _, _, _, _, error in
            DispatchQueue.main.async {
                guard currentObserver == observerID else { return }
                if error != nil { routeObserverFailed = true; stopRouteObserver(); return }
                routeObserverFailed = false
                // 初回スナップショットと検索の間の変更も取りこぼさないようにする。
                handleRouteUpdate()
            }
        }
        query.updateHandler = { _, added, deleted, _, error in
            DispatchQueue.main.async {
                guard currentObserver == observerID else { return }
                if error != nil { routeObserverFailed = true; stopRouteObserver(); return }
                if !(added ?? []).isEmpty || !(deleted ?? []).isEmpty {
                    handleRouteUpdate()
                }
            }
        }
        routeObserver = query
        store.execute(query)
    }
    private func handleRouteUpdate() {
        if selectedWorkout == nil && !isSelectingWorkout {
            read()
        } else {
            routeUpdateAvailable = true
        }
    }
    func stopRouteObserver() {
        observerID = UUID()
        if let routeObserver { store.stop(routeObserver) }
        routeObserver = nil
    }
    func selectWorkout(step: Int) {
        selectionFeedbackWorkoutID = nil
        let currentRequest = UUID()
        requestID = currentRequest
        isSelectingWorkout = true
        clearExportFeedback()
        status = "次のルート付きランを検索中"
        findRoute(workouts, index: selectedIndex + step, request: currentRequest, step: step, preserveSelection: true)
    }
    func selectWorkout(at index: Int) {
        guard workouts.indices.contains(index), !isSelectingWorkout else { return }
        selectionFeedbackWorkoutID = workouts[index].uuid
        let currentRequest = UUID()
        requestID = currentRequest
        isSelectingWorkout = true
        clearExportFeedback()
        status = "選んだランのルートを検索中"
        findRoute(workouts, index: index, request: currentRequest, step: 0, preserveSelection: true)
    }
    func skipOrReportMissingRoute(_ workouts: [HKWorkout], index: Int, request: UUID, step: Int, preserveSelection: Bool) {
        if step == 0 {
            isSelectingWorkout = false
            status = "選んだランに利用できるルートが見つかりません。アクセス設定や記録を確認してください"
        } else {
            findRoute(workouts, index: index + step, request: request, step: step, preserveSelection: preserveSelection)
        }
    }
    func findRoute(_ workouts: [HKWorkout], index: Int, request: UUID, step: Int = 1, preserveSelection: Bool = false) {
        guard request == requestID else { return }
        guard workouts.indices.contains(index) else {
            isSelectingWorkout = false
            if preserveSelection {
                status = step < 0 ? "これより新しいルート付きランは検索範囲にありません" : "これより古いルート付きランは検索範囲にありません"
            } else {
                status = "直近30件にルート付きランが見つかりません。アクセス設定や記録を確認してください"
            }
            return
        }
        let query = HKSampleQuery(sampleType: HKSeriesType.workoutRoute(), predicate: HKQuery.predicateForObjects(from: workouts[index]), limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
            DispatchQueue.main.async {
            guard request == requestID else { return }
            if error != nil { isSelectingWorkout = false; status = "ルートの読み込みに失敗"; return }
            guard let routes = samples as? [HKWorkoutRoute], !routes.isEmpty else { skipOrReportMissingRoute(workouts, index: index, request: request, step: step, preserveSelection: preserveSelection); return }
            let ordered = routes.sorted { a, b in
                a.startDate == b.startDate ? a.uuid.uuidString < b.uuid.uuidString : a.startDate < b.startDate
            }
            readRoutes(ordered, index: 0, workoutIndex: index, searchStep: step, preserveSelection: preserveSelection, request: request, accumulated: [], breaks: [])
            }
        }
        store.execute(query)
    }
    // ルートごとに全バッチを読み、異なるルート間は線で結ばない。
    func readRoutes(_ routes: [HKWorkoutRoute], index: Int, workoutIndex: Int, searchStep: Int, preserveSelection: Bool, request: UUID, accumulated: [CLLocationCoordinate2D], breaks: Set<Int>) {
        guard request == requestID, workouts.indices.contains(workoutIndex) else { return }
        guard index < routes.count else {
            guard !accumulated.isEmpty else {
                skipOrReportMissingRoute(workouts, index: workoutIndex, request: request, step: searchStep, preserveSelection: preserveSelection)
                return
            }
            points = accumulated; breakIndices = breaks; selectedWorkout = workouts[workoutIndex]
            storageMessage = ""
            isSelectingWorkout = false
            selectedIndex = workoutIndex
            clearExportFeedback()
            status = "HealthKitから \(accumulated.count) 点を読み込み、\(breaks.count) 箇所を分断候補として表示"
            return
        }
        var locations: [CLLocation] = []
        let query = HKWorkoutRouteQuery(route: routes[index]) { _, batch, done, error in
            DispatchQueue.main.async {
                guard request == requestID else { return }
                if error != nil { isSelectingWorkout = false; status = "位置データの読み込みに失敗"; return }
                locations.append(contentsOf: batch ?? [])
                guard done else { return }
                let result = RouteGapProbe.analyze(locations)
                var nextBreaks = breaks
                if !accumulated.isEmpty && !result.points.isEmpty { nextBreaks.insert(accumulated.count) }
                nextBreaks.formUnion(result.breakIndices.map { $0 + accumulated.count })
                readRoutes(routes, index: index + 1, workoutIndex: workoutIndex, searchStep: searchStep, preserveSelection: preserveSelection, request: request, accumulated: accumulated + result.points, breaks: nextBreaks)
            }
        }
        store.execute(query)
    }
    @MainActor private func saveProbeArtwork() {
        guard let data = renderImage()?.pngData() else { storageMessage = "画像を作成できませんでした"; return }
        do {
            let directory = try ProbeSavedArtworks.directory()
            try ProbeArtworkLibrary.prepareDirectory(directory)
            try data.write(to: directory.appendingPathComponent("\(UUID().uuidString).png"), options: .atomic)
            storageMessage = "作品を保存しました"
        } catch {
            storageMessage = "作品を保存できませんでした"
        }
    }
}

struct ProbeSavedArtworks: View {
    @State private var images: [URL] = []
    @State private var message = "読み込み中"
    @State private var deleteTarget: URL?
    @State private var showDeleteConfirmation = false
    @State private var attributesMessage = ""
    var body: some View {
        ScrollView {
            LazyVStack {
                Text(message)
                ForEach(images, id: \.self) { url in
                    VStack {
                        if let thumbnail = ProbeArtworkLibrary.thumbnail(at: url) {
                            NavigationLink {
                                ScrollView {
                                    if let image = UIImage(contentsOfFile: url.path) {
                                        Image(uiImage: image).resizable().scaledToFit()
                                    } else {
                                        Text("保存画像を読み込めません")
                                    }
                                }.navigationTitle("作品")
                            } label: {
                                Image(decorative: thumbnail, scale: 1).resizable().scaledToFit()
                            }.accessibilityLabel("保存作品を開く")
                        } else {
                            Text("保存画像を読み込めません: \(url.lastPathComponent)")
                        }
                        Button("この作品を削除", role: .destructive) { deleteTarget = url; showDeleteConfirmation = true }
                    }
                }
            }.padding()
        }.navigationTitle("保存した作品").onAppear { load() }
            .confirmationDialog("この作品を削除しますか？", isPresented: $showDeleteConfirmation, titleVisibility: .visible, presenting: deleteTarget) { target in
                Button("削除", role: .destructive) {
                    do {
                        try ProbeArtworkDeletion.remove(target, in: Self.directory())
                        load()
                    } catch { message = "作品を削除できませんでした" }
                    deleteTarget = nil
                }
                Button("キャンセル", role: .cancel) { deleteTarget = nil }
            } message: { _ in
                Text("アプリ内の画像のみ削除します。写真や共有先のコピーは削除されません。")
            }
    }
    static func directory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("RouteArtImages", isDirectory: true)
    }
    private func load() {
        do {
            let directory = try Self.directory()
            let backupProtected = (try? ProbeArtworkLibrary.prepareDirectory(directory)) != nil
            images = try ProbeArtworkLibrary.images(in: directory)
            message = images.isEmpty ? "保存作品はありません" : "保存作品: \(images.count) 件"
            if !backupProtected { message += "。バックアップ設定を確認できません" }
        } catch {
            images = []; message = "保存作品を読み込めませんでした"
        }
    }
}

struct RouteShape: Shape {
    let points: [CLLocationCoordinate2D]
    let smoothSample: Bool
    let breakIndices: Set<Int>
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let valid = points.filter { CLLocationCoordinate2DIsValid($0) }
        let longitudes = RoutePrivacyProbe.drawingLongitudes(valid)
        guard valid.count > 1, let minLat = valid.map(\.latitude).min(), let maxLat = valid.map(\.latitude).max(), let minLon = longitudes.min(), let maxLon = longitudes.max() else { return path }
        let lonScale = cos((minLat + maxLat) / 2 * .pi / 180)
        let width = max((maxLon - minLon) * lonScale, 0.000001), height = max(maxLat - minLat, 0.000001)
        let scale = min(rect.width / width, rect.height / height)
        let xOffset = (rect.width - width * scale) / 2, yOffset = (rect.height - height * scale) / 2
        let projected = zip(valid, longitudes).map { point, longitude in
            CGPoint(x: xOffset + (longitude - minLon) * lonScale * scale, y: yOffset + (maxLat - point.latitude) * scale)
        }
        path.move(to: projected[0])
        if smoothSample {
            for index in 1..<projected.count {
                let previous = projected[index - 1], current = projected[index]
                let midpoint = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
                path.addQuadCurve(to: midpoint, control: previous)
            }
            path.addLine(to: projected[projected.count - 1])
        } else {
            for index in 1..<projected.count {
                if breakIndices.contains(index) { path.move(to: projected[index]) } else { path.addLine(to: projected[index]) }
            }
        }
        return path
    }
}

private struct ExportSettings: Equatable {
    let background: String
    let backgroundRevision: UUID
    let color: String
    let style: String
    let hideEndpoints: Bool
    let hideSegmentEnds: Bool
    let sceneryFocused: Bool
}

// アプリ内で描画する風景。外部素材や通信を使わない。
private struct SceneryBackground: View {
    let name: String
    var colors: [Color] {
        switch name {
        case "山": return [Color(red: 0.25, green: 0.55, blue: 0.70), Color(red: 0.72, green: 0.81, blue: 0.76), Color(red: 0.12, green: 0.35, blue: 0.43)]
        case "森": return [Color(red: 0.60, green: 0.74, blue: 0.69), Color(red: 0.28, green: 0.49, blue: 0.40), Color(red: 0.07, green: 0.20, blue: 0.16)]
        default: return [Color(red: 0.73, green: 0.42, blue: 0.36), Color(red: 0.91, green: 0.66, blue: 0.43), Color(red: 0.23, green: 0.25, blue: 0.32)]
        }
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geometry.size.height * 0.63))
                    path.addCurve(to: CGPoint(x: geometry.size.width, y: geometry.size.height * 0.55), control1: CGPoint(x: geometry.size.width * 0.35, y: geometry.size.height * 0.35), control2: CGPoint(x: geometry.size.width * 0.60, y: geometry.size.height * 0.75))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                    path.addLine(to: CGPoint(x: 0, y: geometry.size.height))
                    path.closeSubpath()
                }.fill(colors.last!.opacity(0.7))
            }
        }
    }
}
