import CoreGraphics

/// A sticker sheet: page size and where each label sits on it. All values are in PDF points
/// (1/72 inch), measured from the top-left corner of the page.
struct LabelTemplate: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String
    let pageSize: CGSize
    let labelSize: CGSize
    let columns: Int
    let rows: Int
    /// Top-left corner of the first label.
    let origin: CGPoint
    /// Distance from one label's top-left corner to the next, across and down.
    let pitch: CGSize
    let cornerRadius: CGFloat

    var perPage: Int { columns * rows }

    /// Frame of the label at `position` (0-based, left to right then top to bottom).
    func frame(at position: Int) -> CGRect {
        let col = position % columns
        let row = position / columns
        return CGRect(x: origin.x + CGFloat(col) * pitch.width,
                      y: origin.y + CGFloat(row) * pitch.height,
                      width: labelSize.width, height: labelSize.height)
    }

    static func with(id: String) -> LabelTemplate {
        all.first { $0.id == id } ?? all[0]
    }
}

private let inch: CGFloat = 72
private let mm: CGFloat = 72 / 25.4
private let letter = CGSize(width: 8.5 * inch, height: 11 * inch)
private let a4 = CGSize(width: 210 * mm, height: 297 * mm)

extension LabelTemplate {
    /// Common sheets. Measurements follow the manufacturers' published templates; compatible
    /// sheets from other brands use the same numbers.
    static let all: [LabelTemplate] = [
        LabelTemplate(id: "avery-5160", name: "Avery 5160 / 8160", detail: "Address · 1\" × 2⅝\" · 30 per sheet · Letter",
                      pageSize: letter, labelSize: CGSize(width: 2.625 * inch, height: 1 * inch),
                      columns: 3, rows: 10, origin: CGPoint(x: 0.1875 * inch, y: 0.5 * inch),
                      pitch: CGSize(width: 2.75 * inch, height: 1 * inch), cornerRadius: 0.06 * inch),
        LabelTemplate(id: "avery-5163", name: "Avery 5163 / 8163", detail: "Shipping · 2\" × 4\" · 10 per sheet · Letter",
                      pageSize: letter, labelSize: CGSize(width: 4 * inch, height: 2 * inch),
                      columns: 2, rows: 5, origin: CGPoint(x: 0.15625 * inch, y: 0.5 * inch),
                      pitch: CGSize(width: 4.1875 * inch, height: 2 * inch), cornerRadius: 0.06 * inch),
        LabelTemplate(id: "avery-5164", name: "Avery 5164 / 8164", detail: "Shipping · 3⅓\" × 4\" · 6 per sheet · Letter",
                      pageSize: letter, labelSize: CGSize(width: 4 * inch, height: 10.0 / 3.0 * inch),
                      columns: 2, rows: 3, origin: CGPoint(x: 0.15625 * inch, y: 0.5 * inch),
                      pitch: CGSize(width: 4.1875 * inch, height: 10.0 / 3.0 * inch), cornerRadius: 0.06 * inch),
        LabelTemplate(id: "avery-5167", name: "Avery 5167 / 8167", detail: "Return address · ½\" × 1¾\" · 80 per sheet · Letter",
                      pageSize: letter, labelSize: CGSize(width: 1.75 * inch, height: 0.5 * inch),
                      columns: 4, rows: 20, origin: CGPoint(x: 0.28125 * inch, y: 0.5 * inch),
                      pitch: CGSize(width: 2.0625 * inch, height: 0.5 * inch), cornerRadius: 0.04 * inch),
        LabelTemplate(id: "avery-l7160", name: "Avery L7160", detail: "63.5 × 38.1 mm · 21 per sheet · A4",
                      pageSize: a4, labelSize: CGSize(width: 63.5 * mm, height: 38.1 * mm),
                      columns: 3, rows: 7, origin: CGPoint(x: 7.25 * mm, y: 15.15 * mm),
                      pitch: CGSize(width: 66.04 * mm, height: 38.1 * mm), cornerRadius: 2 * mm),
        LabelTemplate(id: "avery-l7163", name: "Avery L7163", detail: "99.1 × 38.1 mm · 14 per sheet · A4",
                      pageSize: a4, labelSize: CGSize(width: 99.1 * mm, height: 38.1 * mm),
                      columns: 2, rows: 7, origin: CGPoint(x: 4.65 * mm, y: 15.15 * mm),
                      pitch: CGSize(width: 101.6 * mm, height: 38.1 * mm), cornerRadius: 2 * mm),
        LabelTemplate(id: "avery-l7165", name: "Avery L7165", detail: "99.1 × 67.7 mm · 8 per sheet · A4",
                      pageSize: a4, labelSize: CGSize(width: 99.1 * mm, height: 67.7 * mm),
                      columns: 2, rows: 4, origin: CGPoint(x: 4.65 * mm, y: 13.1 * mm),
                      pitch: CGSize(width: 101.6 * mm, height: 67.7 * mm), cornerRadius: 2 * mm),
        LabelTemplate(id: "full-letter", name: "Full sheet (Letter)", detail: "8½\" × 11\" · 1 per sheet",
                      pageSize: letter, labelSize: CGSize(width: 8 * inch, height: 10.5 * inch),
                      columns: 1, rows: 1, origin: CGPoint(x: 0.25 * inch, y: 0.25 * inch),
                      pitch: CGSize(width: 8 * inch, height: 10.5 * inch), cornerRadius: 0),
    ]
}
