import SwiftUI

// MARK: - Data models

struct GraphNode: Identifiable, Decodable {
    let id: String
    let title: String
    let tags: [String]
    let source_type: String
    let path: String
}

struct GraphEdge: Decodable {
    let source: String
    let target: String
    let weight: Double
}

private struct GraphPayload: Decodable {
    let status: String
    let nodes: [GraphNode]
    let edges: [GraphEdge]
}

// MARK: - Physics node (mutable simulation state)

private class PhysicsNode {
    let node: GraphNode
    var x: Double
    var y: Double
    var vx: Double = 0
    var vy: Double = 0

    init(node: GraphNode, x: Double, y: Double) {
        self.node = node
        self.x = x
        self.y = y
    }
}

// MARK: - View

struct KnowledgeMapView: View {
    var onSelectMemory: ((String) -> Void)? = nil

    @State private var physicsNodes: [PhysicsNode] = []
    @State private var edges: [GraphEdge] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var hoveredID: String? = nil
    @State private var selectedID: String? = nil
    @State private var simTimer: Timer? = nil
    @State private var simSteps = 0
    @State private var canvasSize: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var dragStartOffset: CGSize = .zero
    @State private var scale: Double = 1.0

    private let repulsion: Double = 3000
    private let attraction: Double = 0.04
    private let damping: Double = 0.82
    private let maxSteps = 300

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView("Building knowledge map…")
            } else if let err = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle).foregroundStyle(.secondary)
                    Text(err).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Retry") { loadGraph() }
                }
                .padding(40)
            } else if physicsNodes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 48)).foregroundStyle(.secondary)
                    Text("Capture or import at least 2 items to build a knowledge map.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(40)
            } else {
                HStack(spacing: 0) {
                    graphCanvas
                    Divider()
                    nodePreviewPanel
                        .frame(width: 260)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { resetView() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .help("Reset view")
                Button { loadGraph() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh map")
            }
        }
        .onAppear { loadGraph() }
        .onDisappear { simTimer?.invalidate() }
    }

    // MARK: Canvas

    private var graphCanvas: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cx = w / 2 + dragOffset.width
            let cy = h / 2 + dragOffset.height

            Canvas { ctx, _ in
                // Draw edges
                for edge in edges {
                    guard let src = physicsNodes.first(where: { $0.node.id == edge.source }),
                          let tgt = physicsNodes.first(where: { $0.node.id == edge.target })
                    else { continue }

                    let sx = cx + src.x * scale
                    let sy = cy + src.y * scale
                    let tx = cx + tgt.x * scale
                    let ty = cy + tgt.y * scale

                    var path = Path()
                    path.move(to: CGPoint(x: sx, y: sy))
                    path.addLine(to: CGPoint(x: tx, y: ty))

                    let alpha = 0.15 + (edge.weight - 0.55) * 0.6
                    ctx.stroke(path, with: .color(.secondary.opacity(alpha)), lineWidth: 1)
                }

                // Draw nodes
                for pn in physicsNodes {
                    let px = cx + pn.x * scale
                    let py = cy + pn.y * scale
                    let isHovered = hoveredID == pn.node.id
                    let isSelected = selectedID == pn.node.id
                    let r: Double = isHovered || isSelected ? 10 : 7
                    let color = nodeColor(for: pn.node)

                    let rect = CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(isSelected ? 1.0 : 0.8)))

                    if isSelected {
                        ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)),
                                   with: .color(color), lineWidth: 2)
                    } else if isHovered {
                        ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -1.5, dy: -1.5)),
                                   with: .color(color.opacity(0.6)), lineWidth: 1.5)
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { val in
                        dragOffset = CGSize(
                            width: dragStartOffset.width + val.translation.width,
                            height: dragStartOffset.height + val.translation.height
                        )
                    }
                    .onEnded { _ in dragStartOffset = dragOffset }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { val in scale = max(0.3, min(3.0, scale * val)) }
            )
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { val in
                        let tapped = nearestNode(to: val.location, cx: cx, cy: cy, threshold: 18)
                        if let pn = tapped {
                            selectedID = pn.node.id
                        } else {
                            selectedID = nil
                        }
                    }
            )
            .onContinuousHover { phase in
                if case .active(let loc) = phase {
                    hoveredID = nearestNode(to: loc, cx: cx, cy: cy, threshold: 20)?.node.id
                } else {
                    hoveredID = nil
                }
            }
            .onAppear { canvasSize = geo.size }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: Fixed preview panel

    private var nodePreviewPanel: some View {
        let activeID = hoveredID ?? selectedID
        let pn = activeID.flatMap { id in physicsNodes.first(where: { $0.node.id == id }) }

        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(pn == nil ? "Hover on a node" : "Preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let pn, !pn.node.path.isEmpty {
                    Button("Open") {
                        onSelectMemory?(pn.node.path)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if let pn {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // Source badge
                        Label(pn.node.source_type.replacingOccurrences(of: "_", with: " "),
                              systemImage: sourceIcon(pn.node.source_type))
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        // Title
                        Text(pn.node.title)
                            .font(.callout)
                            .fontWeight(.medium)
                            .fixedSize(horizontal: false, vertical: true)

                        // Tags
                        if !pn.node.tags.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(pn.node.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption2)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Color.accentColor.opacity(0.12))
                                        .foregroundStyle(Color.accentColor)
                                        .clipShape(Capsule())
                                }
                            }
                        }

                        // Connected nodes
                        let connections = connectedNodes(to: pn.node.id)
                        if !connections.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Connected (\(connections.count))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(connections, id: \.node.id) { cn in
                                    Button {
                                        selectedID = cn.node.id
                                        if !cn.node.path.isEmpty {
                                            onSelectMemory?(cn.node.path)
                                        }
                                    } label: {
                                        Text(cn.node.title)
                                            .font(.caption)
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(14)
                }
            } else {
                Spacer()
                Text("Move your cursor over any node to preview it here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(20)
                Spacer()
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func connectedNodes(to id: String) -> [PhysicsNode] {
        let connectedIDs = edges.compactMap { edge -> String? in
            if edge.source == id { return edge.target }
            if edge.target == id { return edge.source }
            return nil
        }
        return connectedIDs.compactMap { cid in physicsNodes.first { $0.node.id == cid } }
    }

    private func sourceIcon(_ type: String) -> String {
        switch type {
        case "capture": return "camera"
        case "pdf", "document": return "doc.text"
        case "clipboard": return "clipboard"
        default: return "circle"
        }
    }

    // MARK: Helpers

    private func nearestNode(to loc: CGPoint, cx: Double, cy: Double, threshold: Double) -> PhysicsNode? {
        let best = physicsNodes.min(by: {
            let ax = cx + $0.x * scale, ay = cy + $0.y * scale
            let bx = cx + $1.x * scale, by = cy + $1.y * scale
            return hypot(ax - loc.x, ay - loc.y) < hypot(bx - loc.x, by - loc.y)
        })
        guard let b = best else { return nil }
        let bx = cx + b.x * scale, by = cy + b.y * scale
        return hypot(bx - loc.x, by - loc.y) < threshold ? b : nil
    }

    private func nodeColor(for node: GraphNode) -> Color {
        switch node.source_type {
        case "capture":        return .blue
        case "pdf", "document": return .orange
        case "clipboard":      return .green
        default:               return .gray
        }
    }

    private func resetView() {
        dragOffset = .zero
        dragStartOffset = .zero
        scale = 1.0
    }

    // MARK: Force simulation

    private func startSimulation() {
        simSteps = 0
        simTimer?.invalidate()
        simTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            guard simSteps < maxSteps else {
                simTimer?.invalidate()
                return
            }
            runSimStep()
            simSteps += 1
        }
    }

    private func runSimStep() {
        let n = physicsNodes.count
        var fx = [Double](repeating: 0, count: n)
        var fy = [Double](repeating: 0, count: n)

        // Repulsion between all pairs
        for i in 0..<n {
            for j in (i+1)..<n {
                let dx = physicsNodes[j].x - physicsNodes[i].x
                let dy = physicsNodes[j].y - physicsNodes[i].y
                let d2 = max(dx*dx + dy*dy, 1)
                let f = repulsion / d2
                let nx = dx / sqrt(d2), ny = dy / sqrt(d2)
                fx[i] -= f * nx; fy[i] -= f * ny
                fx[j] += f * nx; fy[j] += f * ny
            }
        }

        // Attraction along edges
        let nodeIndex: [String: Int] = Dictionary(uniqueKeysWithValues: physicsNodes.enumerated().map { ($1.node.id, $0) })
        for edge in edges {
            guard let i = nodeIndex[edge.source], let j = nodeIndex[edge.target] else { continue }
            let dx = physicsNodes[j].x - physicsNodes[i].x
            let dy = physicsNodes[j].y - physicsNodes[i].y
            let f = attraction * edge.weight
            fx[i] += f * dx; fy[i] += f * dy
            fx[j] -= f * dx; fy[j] -= f * dy
        }

        // Integrate
        for i in 0..<n {
            physicsNodes[i].vx = (physicsNodes[i].vx + fx[i]) * damping
            physicsNodes[i].vy = (physicsNodes[i].vy + fy[i]) * damping
            physicsNodes[i].x += physicsNodes[i].vx
            physicsNodes[i].y += physicsNodes[i].vy
        }
    }

    // MARK: Load

    private func loadGraph() {
        isLoading = true
        errorMessage = nil
        simTimer?.invalidate()

        let projectURL = MemoryStore.defaultProjectDirectory()
        let pythonURL = projectURL.appendingPathComponent(".venv/bin/python")
        guard FileManager.default.fileExists(atPath: pythonURL.path) else {
            isLoading = false
            errorMessage = "Python venv not found."
            return
        }

        let pipe = Pipe()
        let process = Process()
        process.currentDirectoryURL = projectURL
        process.executableURL = pythonURL
        process.arguments = ["main.py", "--map"]
        process.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "PYTHONPATH": projectURL.path,
        ]
        process.standardOutput = pipe
        process.standardError = Pipe()

        process.terminationHandler = { _ in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            DispatchQueue.main.async {
                isLoading = false
                guard let payload = try? JSONDecoder().decode(GraphPayload.self, from: data),
                      payload.status == "success", !payload.nodes.isEmpty else {
                    errorMessage = "Could not load graph data."
                    return
                }

                edges = payload.edges

                // Initialize positions in a circle
                let count = payload.nodes.count
                let radius = Double(count) * 12.0
                physicsNodes = payload.nodes.enumerated().map { i, node in
                    let angle = 2 * Double.pi * Double(i) / Double(count)
                    return PhysicsNode(node: node,
                                       x: radius * cos(angle),
                                       y: radius * sin(angle))
                }

                startSimulation()
            }
        }

        try? process.run()
    }
}
