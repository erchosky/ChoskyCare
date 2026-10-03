import SwiftUI

struct TreemapView: View {
    let nodes: [StorageNode]
    var maxTiles = 14
    var onOpen: (StorageNode) -> Void = { _ in }

    private static let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green, .yellow, .mint, .cyan]

    private struct Tile: Identifiable {
        let id: String
        let name: String
        let bytes: Int64
        let node: StorageNode?
    }

    /// The biggest items, plus one "Other" tile so the map always adds up to the whole scan.
    private var tiles: [Tile] {
        let visible = nodes.filter { $0.byteCount > 0 }.sorted { $0.byteCount > $1.byteCount }
        var tiles = visible.prefix(maxTiles).map { Tile(id: $0.url.path, name: $0.name, bytes: $0.byteCount, node: $0) }
        let rest = visible.dropFirst(maxTiles)
        if !rest.isEmpty {
            tiles.append(Tile(
                id: "__other__",
                name: L("treemap.other", rest.count),
                bytes: rest.reduce(0) { $0 + $1.byteCount },
                node: nil
            ))
        }
        return tiles
    }

    var body: some View {
        let tiles = self.tiles
        GeometryReader { proxy in
            let rectangles = TreemapLayout.layout(
                weights: tiles.map { Double($0.bytes) },
                in: CGRect(origin: .zero, size: proxy.size).insetBy(dx: 3, dy: 3)
            )

            ZStack(alignment: .topLeading) {
                ForEach(Array(zip(tiles, rectangles).enumerated()), id: \.element.0.id) { index, pair in
                    let (tile, frame) = pair
                    let rect = frame.insetBy(dx: 2, dy: 2)
                    TileView(tile: tile, color: tile.node == nil ? .gray : Self.palette[index % Self.palette.count], size: rect.size)
                        .frame(width: max(0, rect.width), height: max(0, rect.height))
                        .offset(x: rect.minX, y: rect.minY)
                        .onTapGesture {
                            if let node = tile.node { onOpen(node) }
                        }
                }
            }
        }
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("treemap.accessibility"))
        .overlay {
            if tiles.isEmpty {
                Text(L("treemap.empty"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private struct TileView: View {
        let tile: Tile
        let color: Color
        let size: CGSize

        var body: some View {
            RoundedRectangle(cornerRadius: min(10, min(size.width, size.height) / 3))
                .fill(color.opacity(0.45).gradient)
                .overlay(alignment: .topLeading) {
                    if size.width > 64, size.height > 34 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tile.name)
                                .font(.headline)
                                .lineLimit(1)
                            Text(tile.bytes.formattedBytes)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: min(10, min(size.width, size.height) / 3)))
                .contentShape(Rectangle())
                .help(tile.node.map { "\($0.url.path)\n\(tile.bytes.formattedBytes)" } ?? "\(tile.name)\n\(tile.bytes.formattedBytes)")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(tile.name), \(tile.bytes.formattedBytes)")
                .accessibilityAddTraits(tile.node?.isDirectory == true ? .isButton : [])
        }
    }
}

enum TreemapLayout {
    /// Squarified treemap (Bruls, Huizing & van Wijk). Weights should be sorted
    /// in descending order for the best aspect ratios; the result keeps input order.
    static func layout(weights: [Double], in bounds: CGRect) -> [CGRect] {
        guard !weights.isEmpty else { return [] }
        var result = Array(repeating: CGRect(origin: bounds.origin, size: .zero), count: weights.count)
        let clean = weights.map { $0.isFinite ? max(0, $0) : 0 }
        let total = clean.reduce(0, +)
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return result }

        let scale = Double(bounds.width * bounds.height) / total
        let order = clean.indices.filter { clean[$0] > 0 }.sorted { clean[$0] > clean[$1] }
        var remaining = order[...]
        var rect = bounds

        while !remaining.isEmpty {
            let side = Double(min(rect.width, rect.height))
            var row: [Int] = []
            var rowArea = 0.0

            while let next = remaining.first {
                let area = clean[next] * scale
                let candidate = row + [next]
                if row.isEmpty || worstRatio(candidate.map { clean[$0] * scale }, side: side)
                    <= worstRatio(row.map { clean[$0] * scale }, side: side) {
                    row = candidate
                    rowArea += area
                    remaining = remaining.dropFirst()
                } else {
                    break
                }
            }

            // Lay the row along the shorter side of the remaining rectangle.
            if rect.width >= rect.height {
                let width = rect.height > 0 ? CGFloat(rowArea) / rect.height : 0
                var y = rect.minY
                for index in row {
                    let height = width > 0 ? CGFloat(clean[index] * scale) / width : 0
                    result[index] = CGRect(x: rect.minX, y: y, width: width, height: height)
                    y += height
                }
                rect = CGRect(x: rect.minX + width, y: rect.minY, width: max(0, rect.width - width), height: rect.height)
            } else {
                let height = rect.width > 0 ? CGFloat(rowArea) / rect.width : 0
                var x = rect.minX
                for index in row {
                    let width = height > 0 ? CGFloat(clean[index] * scale) / height : 0
                    result[index] = CGRect(x: x, y: rect.minY, width: width, height: height)
                    x += width
                }
                rect = CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: max(0, rect.height - height))
            }
        }
        return result
    }

    private static func worstRatio(_ areas: [Double], side: Double) -> Double {
        let sum = areas.reduce(0, +)
        guard sum > 0, side > 0, let maxArea = areas.max(), let minArea = areas.min(), minArea > 0 else {
            return .infinity
        }
        let sideSquared = side * side
        let sumSquared = sum * sum
        return max(sideSquared * maxArea / sumSquared, sumSquared / (sideSquared * minArea))
    }
}
