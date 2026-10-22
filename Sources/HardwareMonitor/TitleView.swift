import AppKit

/// Menggambar judul langsung di atas tombol status item: CPU, GPU, dan RAM bertumpuk dalam satu kolom,
/// label rata kiri dan nilai rata kanan.
/// Lebih murah daripada `button.attributedTitle`, yang memicu perhitungan ulang Auto Layout setiap kali berubah.
final class TitleView: NSView {
    struct Row {
        var label: String
        var value: String
        var color: NSColor
    }

    private struct Fonts {
        let label: NSFont
        let value: NSFont
    }

    private static let padding: CGFloat = 4
    private static let labelGap: CGFloat = 3
    private static let lineGap: CGFloat = 2.5

    // Menu bar MacBook dengan notch setinggi ±38 pt; menu bar biasa (monitor eksternal) 24 pt.
    private static let regularFonts = Fonts(
        label: .systemFont(ofSize: 7, weight: .semibold),
        value: .monospacedDigitSystemFont(ofSize: 9, weight: .regular)
    )
    private static let compactFonts = Fonts(
        label: .systemFont(ofSize: 6.5, weight: .semibold),
        value: .monospacedDigitSystemFont(ofSize: 8, weight: .regular)
    )

    var rows: [Row] = [] {
        didSet { needsDisplay = true }
    }

    /// Lebar total item untuk baris terlebar.
    func measure(widest: [Row]) -> CGFloat {
        let fonts = Self.regularFonts
        let labelWidth = widest.map { label($0, fonts).size().width }.max() ?? 0
        let valueWidth = widest.map { value($0, fonts).size().width }.max() ?? 0
        return Self.padding * 2 + labelWidth + Self.labelGap + valueWidth
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !rows.isEmpty else { return }
        let fonts = bounds.height < 30 ? Self.compactFonts : Self.regularFonts
        let capHeight = fonts.value.capHeight

        // Angka dan huruf kapital tidak punya descender, jadi jarak baris cukup capHeight + celah kecil.
        let blockHeight = capHeight * CGFloat(rows.count) + Self.lineGap * CGFloat(rows.count - 1)
        var capTop = (bounds.height + blockHeight) / 2
        for row in rows {
            let baseline = capTop - capHeight
            // Label lebih kecil, diletakkan di tengah tinggi huruf nilai.
            let labelBaseline = baseline + (capHeight - fonts.label.capHeight) / 2
            label(row, fonts).draw(at: NSPoint(x: Self.padding, y: labelBaseline + fonts.label.descender))
            let valueText = value(row, fonts)
            let valueX = bounds.width - Self.padding - valueText.size().width
            valueText.draw(at: NSPoint(x: valueX, y: baseline + fonts.value.descender))
            capTop -= capHeight + Self.lineGap
        }
    }

    private func label(_ row: Row, _ fonts: Fonts) -> NSAttributedString {
        NSAttributedString(string: row.label, attributes: [
            .font: fonts.label,
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }

    private func value(_ row: Row, _ fonts: Fonts) -> NSAttributedString {
        NSAttributedString(string: row.value, attributes: [
            .font: fonts.value,
            .foregroundColor: row.color,
        ])
    }

    override func viewDidChangeEffectiveAppearance() {
        // Warna dinamis (labelColor dll.) perlu digambar ulang saat menu bar berganti terang/gelap.
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Klik diteruskan ke tombol di bawahnya supaya menu tetap terbuka.
        nil
    }
}
