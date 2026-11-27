"""Regenerate the Live Activity timer mask with fontTools."""

from pathlib import Path

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen


def main():
    builder = FontBuilder(1000, isTTF=True)
    builder.setupGlyphOrder([".notdef", "transparent", "square"])
    builder.setupCharacterMap({
        ord(char): "square" if char == "0" else "transparent"
        for char in "0123456789:,. "
    })

    pen = TTGlyphPen(None)
    pen.moveTo((0, -200))
    pen.lineTo((0, 800))
    pen.lineTo((1000, 800))
    pen.lineTo((1000, -200))
    pen.closePath()
    empty = TTGlyphPen(None).glyph()
    builder.setupGlyf({".notdef": empty, "transparent": empty, "square": pen.glyph()})
    builder.setupHorizontalMetrics({name: (1000, 0) for name in builder.font.getGlyphOrder()})
    builder.setupHorizontalHeader(ascent=800, descent=-200)
    builder.setupNameTable({
        "familyName": "Widget Marquee Timer Gate",
        "styleName": "Regular",
        "uniqueFontIdentifier": "WidgetMarqueeTimerGate-Regular-1.0",
        "fullName": "Widget Marquee Timer Gate Regular",
        "psName": "WidgetMarqueeTimerGate-Regular",
    })
    builder.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
    builder.setupPost()
    # Use a fixed OpenType epoch timestamp so rebuilding the bundled asset is reproducible.
    builder.font["head"].created = builder.font["head"].modified = 3850000000
    builder.font.recalcTimestamp = False
    resources = Path(__file__).resolve().parents[1] / "Sources" / "WidgetMarquee" / "Resources"
    builder.save(resources / "WidgetMarqueeTimerGate.ttf")


if __name__ == "__main__":
    main()
