"""Regenerate the small Live Activity mask and spacing fonts with fontTools."""

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
    save(builder, "WidgetMarqueeTimerGate")

    # A one-em invisible glyph gives either scrolling axis a fractional point gap
    # without adding a bitmap or the clock font's lookup tables to every copy.
    spacer = FontBuilder(1000, isTTF=True)
    spacer.setupGlyphOrder([".notdef", "gap", "zero"])
    spacer.setupCharacterMap({0xE000: "gap", 0x200B: "zero"})
    spacer.setupGlyf({name: TTGlyphPen(None).glyph() for name in spacer.font.getGlyphOrder()})
    spacer.setupHorizontalMetrics({".notdef": (0, 0), "gap": (1000, 0), "zero": (0, 0)})
    spacer.setupHorizontalHeader(ascent=1, descent=0, lineGap=0)
    spacer.setupOS2(sTypoAscender=1, sTypoDescender=0, usWinAscent=1, usWinDescent=0)
    spacer.setupNameTable({
        "familyName": "Marquee Repeat Space", "styleName": "Regular",
        "uniqueFontIdentifier": "MarqueeRepeatSpace-Regular-1.0",
        "fullName": "Marquee Repeat Space Regular", "psName": "MarqueeRepeatSpace-Regular",
    })
    save(spacer, "MarqueeRepeatSpace")


def save(builder, name):
    builder.setupPost()
    # Use a fixed OpenType epoch timestamp so rebuilding the bundled asset is reproducible.
    builder.font["head"].created = builder.font["head"].modified = 3850000000
    builder.font.recalcTimestamp = False
    resources = Path(__file__).resolve().parents[1] / "Sources" / "MarqueeKit" / "Resources"
    builder.save(resources / f"{name}.ttf")


if __name__ == "__main__":
    main()
