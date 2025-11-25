//
//  DrumStockpileSupportViews.swift
//  MacStudioServerSimulator
//
//  Shared view helpers for the stockpile UI (table widths, waveform renderers).
//

import SwiftUI
import AppKit

// MARK: - Table Column Width Persistence (AppKit bridge)

struct TableColumnWidthPersister: NSViewRepresentable {
    let storageKey: String
    
    func makeCoordinator() -> Coordinator {
        Coordinator(storageKey: storageKey)
    }
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.attach(to: view)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    final class Coordinator: NSObject {
        private let storageKey: String
        private weak var observedTable: NSTableView?
        private var observer: NSObjectProtocol?
        
        init(storageKey: String) {
            self.storageKey = storageKey
        }
        
        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        
        func attach(to hostView: NSView) {
            guard observedTable == nil else { return }
            guard let table = findTable(from: hostView) else { return }
            observedTable = table
            applySavedWidths(to: table)
            
            observer = NotificationCenter.default.addObserver(
                forName: NSTableView.columnDidResizeNotification,
                object: table,
                queue: .main
            ) { [weak self, weak table] _ in
                guard let table else { return }
                self?.persistWidths(of: table)
            }
        }
        
        private func applySavedWidths(to table: NSTableView) {
            let defaults = UserDefaults.standard
            guard let saved = defaults.array(forKey: storageKey) as? [CGFloat],
                  !saved.isEmpty else { return }
            let count = min(saved.count, table.tableColumns.count)
            guard count > 0 else { return }
            for idx in 0..<count {
                table.tableColumns[idx].width = saved[idx]
            }
        }
        
        private func persistWidths(of table: NSTableView) {
            let widths = table.tableColumns.map { $0.width }
            UserDefaults.standard.set(widths, forKey: storageKey)
        }
        
        private func findTable(from root: NSView) -> NSTableView? {
            var queue: [NSView] = [root]
            var seen = Set<ObjectIdentifier>()
            
            while !queue.isEmpty {
                let current = queue.removeFirst()
                let id = ObjectIdentifier(current)
                guard !seen.contains(id) else { continue }
                seen.insert(id)
                
                if let table = current as? NSTableView {
                    return table
                }
                queue.append(contentsOf: current.subviews)
                if let superview = current.superview {
                    queue.append(superview)
                }
            }
            return nil
        }
    }
}

// MARK: - Split View Autosave (persists panel widths)

struct SplitViewAutosaveAttacher: NSViewRepresentable {
    let storageKey: String
    
    func makeCoordinator() -> Coordinator {
        Coordinator(storageKey: storageKey)
    }
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.attach(to: view)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    final class Coordinator {
        private let storageKey: String
        
        init(storageKey: String) {
            self.storageKey = storageKey
        }
        
        func attach(to hostView: NSView) {
            let splits = findSplitViews(from: hostView)
            for (idx, split) in splits.enumerated() {
                if split.autosaveName == nil || split.autosaveName?.isEmpty == true {
                    split.autosaveName = "\(storageKey).\(idx)"
                }
            }
        }
        
        private func findSplitViews(from root: NSView) -> [NSSplitView] {
            var queue: [NSView] = [root]
            var seen = Set<ObjectIdentifier>()
            var matches: [NSSplitView] = []
            
            while !queue.isEmpty {
                let current = queue.removeFirst()
                let id = ObjectIdentifier(current)
                guard !seen.contains(id) else { continue }
                seen.insert(id)
                
                if let split = current as? NSSplitView {
                    matches.append(split)
                }
                queue.append(contentsOf: current.subviews)
                if let superview = current.superview {
                    queue.append(superview)
                }
            }
            return matches
        }
    }
}

// MARK: - Visualizers

struct WaveformView: View {
    let data: [Float]
    let gatedOverlay: [Float]?
    let duration: TimeInterval
    let floorLevel: Float?
    @Binding var currentTime: TimeInterval
    let loopEnabled: Bool
    @Binding var loopRange: ClosedRange<TimeInterval>?
    @State private var isDraggingHandle = false
    @State private var handleDragBase: ClosedRange<TimeInterval>?
    @State private var zoom: CGFloat = 1
    @State private var viewStart: CGFloat = 0
    
    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let width = proxy.size.width
            let samples = data
            ZStack(alignment: .leading) {
                Canvas { context, _ in
                    guard samples.count > 1 else { return }
                    let slice = visibleSlice(from: samples)
                    guard slice.count > 1 else { return }
                    let step = max(1, slice.count / Int(max(80, width * 1.5)))
                    
                    var upper: [CGPoint] = []
                    var lower: [CGPoint] = []
                    for (offset, sample) in slice.enumerated() where offset % step == 0 || offset == slice.count - 1 {
                        let x = CGFloat(offset) / CGFloat(slice.count - 1) * width
                        let magnitude = CGFloat(sample.clamped(to: 0...1)) * (height / 2)
                        let mid = height / 2
                        upper.append(CGPoint(x: x, y: mid - magnitude))
                        lower.append(CGPoint(x: x, y: mid + magnitude))
                    }
                    
                    let waveformPath = Path { path in
                        guard let first = upper.first, let lastLower = lower.last else { return }
                        path.move(to: first)
                        for point in upper.dropFirst() {
                            path.addLine(to: point)
                        }
                        for point in lower.reversed() {
                            path.addLine(to: point)
                        }
                        path.addLine(to: lastLower)
                        path.closeSubpath()
                    }
                    let gradient = Gradient(colors: [
                        Color.accentColor.opacity(0.35),
                        Color.accentColor.opacity(0.15)
                    ])
                    context.fill(
                        waveformPath,
                        with: .linearGradient(
                            gradient,
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: 0, y: height)
                        )
                    )
                    context.stroke(waveformPath, with: .color(.accentColor.opacity(0.8)), lineWidth: 1)
                    
                    if let overlay = gatedOverlay, overlay.count > 1 {
                        let overlaySlice = visibleSlice(from: overlay)
                        if overlaySlice.count > 1 {
                            let overlayStep = max(1, overlaySlice.count / Int(max(80, width * 1.5)))
                            var upperO: [CGPoint] = []
                            var lowerO: [CGPoint] = []
                            for (offset, sample) in overlaySlice.enumerated() where offset % overlayStep == 0 || offset == overlaySlice.count - 1 {
                                let x = CGFloat(offset) / CGFloat(overlaySlice.count - 1) * width
                                let magnitude = CGFloat(sample.clamped(to: 0...1)) * (height / 2)
                                let mid = height / 2
                                upperO.append(CGPoint(x: x, y: mid - magnitude))
                                lowerO.append(CGPoint(x: x, y: mid + magnitude))
                            }
                            
                            let overlayPath = Path { path in
                                guard let first = upperO.first, let last = lowerO.last else { return }
                                path.move(to: first)
                                for point in upperO.dropFirst() { path.addLine(to: point) }
                                for point in lowerO.reversed() { path.addLine(to: point) }
                                path.addLine(to: last)
                                path.closeSubpath()
                            }
                            context.fill(overlayPath, with: .color(Color.green.opacity(0.55)))
                            context.stroke(overlayPath, with: .color(.green.opacity(0.95)), lineWidth: 1.4)
                        }
                    }
                    
                    let midLine = Path { path in
                        path.move(to: CGPoint(x: 0, y: height / 2))
                        path.addLine(to: CGPoint(x: width, y: height / 2))
                    }
                    context.stroke(midLine, with: .color(.secondary.opacity(0.2)), lineWidth: 0.8)
                    
                    if let floorLevel {
                        let level = CGFloat(floorLevel.clamped(to: 0...1))
                        let offset = level * (height / 2)
                        let yTop = (height / 2) - offset
                        let yBottom = (height / 2) + offset
                        let floorPath = Path { path in
                            path.move(to: CGPoint(x: 0, y: yTop))
                            path.addLine(to: CGPoint(x: width, y: yTop))
                            path.move(to: CGPoint(x: 0, y: yBottom))
                            path.addLine(to: CGPoint(x: width, y: yBottom))
                        }
                        context.stroke(
                            floorPath,
                            with: .color(.red.opacity(0.45)),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(nsColor: .textBackgroundColor),
                                    Color(nsColor: .textBackgroundColor).opacity(0.9)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2)
                    .offset(x: scrubX(in: width))
                
                if loopEnabled, let range = loopRange {
                    let startX = xPosition(for: range.lowerBound, width: width)
                    let endX = xPosition(for: range.upperBound, width: width)
                    let loopColor = Color.accentColor.opacity(0.2)
                    
                    Rectangle()
                        .fill(loopColor)
                        .frame(width: max(0, endX - startX), height: height)
                        .offset(x: startX)
                    
                    loopHandle(x: startX, height: height, isStart: true, width: width)
                    loopHandle(x: endX, height: height, isStart: false, width: width)
                }
            }
            .coordinateSpace(name: "waveform-area")
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("waveform-area"))
                    .onChanged { value in
                        guard !isDraggingHandle else { return }
                        let t = time(at: value.location.x, width: width)
                        guard t.isFinite else { return }
                        currentTime = t
                    }
                    .onEnded { value in
                        guard !isDraggingHandle else { return }
                        let t = time(at: value.location.x, width: width)
                        guard t.isFinite else { return }
                        currentTime = t
                    }
            )
            .overlay(
                ScrollWheelCatcher { deltaY, location, size in
                    handleScroll(deltaY: deltaY, location: location, size: size)
                }
                .allowsHitTesting(false)
            )
        }
    }
    
    private func scrubX(in width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        let window = visibleWindow()
        let start = clampedViewStart()
        let ratio = (currentTime / duration - start) / window
        return CGFloat(ratio.clamped(to: 0...1)) * width
    }
    
    private func xPosition(for time: TimeInterval, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        let window = visibleWindow()
        let start = clampedViewStart()
        let ratio = (time / duration - start) / window
        return CGFloat(ratio.clamped(to: 0...1)) * width
    }
    
    private func loopHandle(x: CGFloat, height: CGFloat, isStart: Bool, width: CGFloat) -> some View {
        let hitWidth: CGFloat = 28
        let barWidth: CGFloat = 8
        
        return ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(0.1))
                .frame(width: hitWidth, height: height)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.accentColor)
                .frame(width: barWidth, height: height)
                .shadow(color: .accentColor.opacity(0.35), radius: 2)
            Capsule()
                .fill(Color.white.opacity(0.65))
                .frame(width: 3, height: 26)
        }
        .frame(width: hitWidth, height: height)
        .offset(x: x - (hitWidth / 2))
        .contentShape(Rectangle())
        .highPriorityGesture(handleDrag(isStart: isStart, width: width))
        .accessibilityLabel(isStart ? "Loop start handle" : "Loop end handle")
        .accessibilityHint("Drag to adjust the loop \(isStart ? "start" : "end") point")
    }
    
    private func handleDrag(isStart: Bool, width: CGFloat) -> some Gesture {
        let minSpan: TimeInterval = 0.05
        return DragGesture(minimumDistance: 0, coordinateSpace: .named("waveform-area"))
            .onChanged { value in
                guard duration > 0, width > 0 else { return }
                if !isDraggingHandle { isDraggingHandle = true }
                
                if handleDragBase == nil {
                    let current = loopRange ?? 0...duration
                    let lower = max(0, min(duration, current.lowerBound))
                    let upper = max(lower + minSpan, min(duration, current.upperBound))
                    handleDragBase = lower...upper
                }
                guard let base = handleDragBase else { return }
                
                let secondsPerPoint = duration / width
                let delta = TimeInterval(value.translation.width) * secondsPerPoint
                
                if isStart {
                    let maxStart = base.upperBound - minSpan
                    let newStart = min(max(0, base.lowerBound + delta), maxStart)
                    loopRange = newStart...base.upperBound
                } else {
                    let newEnd = max(base.lowerBound + minSpan, min(duration, base.upperBound + delta))
                    loopRange = base.lowerBound...newEnd
                }
            }
            .onEnded { _ in
                handleDragBase = nil
                isDraggingHandle = false
            }
    }
    
    private func time(at x: CGFloat, width: CGFloat) -> TimeInterval {
        guard duration > 0 else { return 0 }
        let clampedX = min(max(0, x), width)
        let ratio = clampedX / width
        let window = visibleWindow()
        let start = clampedViewStart()
        let position = (start + ratio * window).clamped(to: 0...1)
        return position * duration
    }
    
    private func visibleSlice(from samples: [Float]) -> ArraySlice<Float> {
        guard samples.count > 1 else { return samples[0..<samples.count] }
        let window = visibleWindow()
        let start = clampedViewStart()
        let end = min(1.0, start + window)
        let startIdx = Int(start * CGFloat(samples.count - 1))
        let endIdx = Int(end * CGFloat(samples.count - 1))
        let clampedEnd = max(startIdx + 1, min(samples.count - 1, endIdx))
        return samples[startIdx...clampedEnd]
    }
    
    private func visibleWindow() -> CGFloat {
        let z = max(1, zoom)
        return 1 / z
    }
    
    private func clampedViewStart() -> CGFloat {
        let window = visibleWindow()
        return min(max(viewStart, 0), max(0, 1 - window))
    }
    
    private func handleScroll(deltaY: CGFloat, location: CGPoint, size: CGSize) {
        guard size.width > 1 else { return }
        let factor: CGFloat = deltaY > 0 ? 1.1 : 0.9
        let newZoom = min(80, max(1, zoom * factor))
        let oldWindow = visibleWindow()
        let oldStart = clampedViewStart()
        let cursorRatio = (location.x / max(size.width, 1)).clamped(to: 0...1)
        let center = oldStart + oldWindow * cursorRatio
        
        zoom = newZoom
        let newWindow = visibleWindow()
        var newStart = center - newWindow * cursorRatio
        newStart = min(max(0, newStart), max(0, 1 - newWindow))
        viewStart = newStart
    }
}

struct SpectrogramView: View {
    let data: [[Float]]
    
    var body: some View {
        GeometryReader { proxy in
            let rows = data.count
            let cols = data.first?.count ?? 0
            Canvas { context, size in
                guard rows > 0, cols > 0 else { return }
                let cellWidth = size.width / CGFloat(cols)
                let cellHeight = size.height / CGFloat(rows)
                
                for row in 0..<rows {
                    for col in 0..<cols {
                        let value = data[row][col].clamped(to: 0...1)
                        let hue = 0.6 - 0.6 * Double(value)
                        let color = Color(hue: hue, saturation: 0.9, brightness: 0.9)
                        let rect = CGRect(x: CGFloat(col) * cellWidth, y: CGFloat(row) * cellHeight, width: cellWidth, height: cellHeight)
                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }
            .background(
                LinearGradient(colors: [.black.opacity(0.6), .black.opacity(0.2)], startPoint: .top, endPoint: .bottom)
            )
        }
    }
}

// Bridge to capture mouse wheel for zooming.
struct ScrollWheelCatcher: NSViewRepresentable {
    var onScroll: (CGFloat, CGPoint, CGSize) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll)
    }
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setAccessibilityElement(false)
        view.postsFrameChangedNotifications = false
        context.coordinator.attach(to: view)
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.view = nsView
    }
    
    final class Coordinator {
        var onScroll: (CGFloat, CGPoint, CGSize) -> Void
        weak var view: NSView?
        private var monitor: Any?
        
        init(onScroll: @escaping (CGFloat, CGPoint, CGSize) -> Void) {
            self.onScroll = onScroll
        }
        
        func attach(to view: NSView) {
            self.view = view
            if monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    guard let self, let host = self.view else { return event }
                    let locationInHost = host.convert(event.locationInWindow, from: nil)
                    self.onScroll(event.scrollingDeltaY, locationInHost, host.bounds.size)
                    return event
                }
            }
        }
        
        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

// MARK: - Helpers

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
