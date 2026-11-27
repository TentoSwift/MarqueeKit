"""Regenerate the transparent Live Activity stopwatch font with fontTools."""

from pathlib import Path

from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen


def main():
    digits = [f"d{i}" for i in range(10)]
    positions = [f"phase{i:03d}" for i in range(1000)]
    glyphs = [".notdef", "space", "colon", "decimal", *digits, *positions]
    builder = FontBuilder(1000, isTTF=True)
    builder.setupGlyphOrder(glyphs)
    cmap = {ord(str(i)): digit for i, digit in enumerate(digits)}
    cmap.update({ord(":"): "colon", ord("."): "decimal", ord(","): "decimal"})
    cmap.update({ord(c): "space" for c in " \u202f\u200e\u200f"})
    builder.setupCharacterMap(cmap)
    builder.setupGlyf({name: TTGlyphPen(None).glyph() for name in glyphs})

    # No glyph draws ink. Only the seconds-unit / decimal / fraction ligature
    # occupies horizontal space. Each centisecond removes 1/1000 of a pass.
    advances = {name: (0, 0) for name in glyphs}
    for index, name in enumerate(positions):
        advances[name] = ((999 - index) * 24, 0)
    builder.setupHorizontalMetrics(advances)
    # The invisible prefix stays below the visible text's line height even
    # when the text supplied in the ActivityKit payload is quite wide.
    builder.setupHorizontalHeader(ascent=2, descent=-1, lineGap=0)
    builder.setupOS2(sTypoAscender=2, sTypoDescender=-1, usWinAscent=2, usWinDescent=1)
    builder.setupNameTable({
        "familyName": "Widget Marquee Stopwatch",
        "styleName": "Regular",
        "uniqueFontIdentifier": "WidgetMarqueeStopwatch-Regular-1.0",
        "fullName": "Widget Marquee Stopwatch Regular",
        "psName": "WidgetMarqueeStopwatch-Regular",
    })
    builder.setupPost()
    rules = ["languagesystem DFLT dflt;", "languagesystem latn dflt;", "feature rlig {"]
    for index, name in enumerate(positions):
        seconds, fraction = divmod(index, 100)
        rules.append(f"sub d{seconds} decimal d{fraction // 10} d{fraction % 10} by {name};")
    # Some system presentations use a single decimal digit.
    for index in range(100):
        rules.append(f"sub d{index // 10} decimal d{index % 10} by {positions[index * 10]};")
    rules.append("} rlig;")
    addOpenTypeFeaturesFromString(builder.font, "\n".join(rules))
    builder.font["head"].created = builder.font["head"].modified = 3850000000
    builder.font.recalcTimestamp = False
    resources = Path(__file__).resolve().parents[1] / "Sources" / "WidgetMarquee" / "Resources"
    builder.save(resources / "WidgetMarqueeStopwatch.ttf")


if __name__ == "__main__":
    main()
