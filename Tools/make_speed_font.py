"""Rebuild the variable-width clock font for the Live Activity speed API."""

from pathlib import Path

from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import newTable
from fontTools.ttLib.tables import otTables
from fontTools.varLib.builder import (
    buildDeltaSetIndexMap,
    buildVarData,
    buildVarRegionList,
    buildVarStore,
)


# The stopwatch displays [hh:]mm:ss.cc. An iOS 17 timer omits the fraction.
# A Live Activity lasts at most eight hours, so only the hours units are needed.
CLOCK_PLACES = [
    ("hr", 9), ("mt", 5), ("mu", 9), ("st", 5),
    ("su", 9), ("dt", 9), ("dc", 9),
]


# First tag the hours and minutes before their colons. This leaves only
# the seconds after a colon untagged. Then tag the two fractional digits.
CLOCK_CONTEXTS = [
    ("hr", "", "colon @d @d colon"),
    ("mu", "", "colon @d @d"),
    ("mt", "", "@mu colon"),
    ("st", "colon", "@d"),
    ("su", "@st", ""),
    ("dt", "decimal", ""),
    ("dc", "@dt", ""),
]


def setup_clock_substitutions(builder, digits):
    rules = [
        "languagesystem DFLT dflt;",
        "languagesystem latn dflt;",
        "@d = [" + " ".join(digits) + "];",
    ]
    for place, _ in CLOCK_PLACES:
        substitutions = [f"{place}{digit}" for digit in range(10)]
        rules.append(f"@{place} = [" + " ".join(substitutions) + "];")

    rules.append("feature rlig {")
    for place, before, after in CLOCK_CONTEXTS:
        rules.append(f"  lookup {place} {{ sub {before} @d' {after} by @{place}; }} {place};")
    rules.append("} rlig;")
    addOpenTypeFeaturesFromString(builder.font, "\n".join(rules))


def setup_variable_advances(builder, glyphs):
    axes = []
    glyph_axes = {}
    for place, maximum in CLOCK_PLACES:
        for digit in range(1, maximum + 1):
            glyph_axes[f"{place}{digit}"] = len(axes)
            axes.append(f"W{place.upper()}{digit}")
    builder.setupFvar([(tag, 0, 0, 1, tag) for tag in axes], [])
    builder.setupGvar({})

    # Every nonzero positional digit has its own horizontal advance (HVAR).
    # One independent region per digit keeps each row to a single delta.
    # The view sets each axis from 0 to 1; at 1, the advance is 24 em.
    regions = buildVarRegionList([{tag: (0, 1, 1)} for tag in axes], axes)
    variation_data = [buildVarData([], [[]])]
    variation_data.extend(buildVarData([index], [[24000]]) for index in range(len(axes)))
    advance_indices = [
        (glyph_axes[name] + 1) << 16 if name in glyph_axes else 0 for name in glyphs
    ]
    table = otTables.HVAR()
    table.Version = 0x00010000
    table.VarStore = buildVarStore(regions, variation_data)
    table.AdvWidthMap = buildDeltaSetIndexMap(advance_indices)
    table.LsbMap = None
    table.RsbMap = None
    hvar = newTable("HVAR")
    hvar.table = table
    builder.font["HVAR"] = hvar


def main():
    digits = [f"d{digit}" for digit in range(10)]
    positional_digits = [f"{place}{digit}" for place, _ in CLOCK_PLACES for digit in range(10)]
    glyphs = [".notdef", "space", "colon", "decimal", *digits, *positional_digits]
    builder = FontBuilder(1000, isTTF=True)
    builder.setupGlyphOrder(glyphs)
    cmap = {ord(str(index)): name for index, name in enumerate(digits)}
    cmap.update({ord(":"): "colon", ord("."): "decimal", ord(","): "decimal"})
    cmap.update({ord(char): "space" for char in " \u202f\u200e\u200f"})
    builder.setupCharacterMap(cmap)
    builder.setupGlyf({name: TTGlyphPen(None).glyph() for name in glyphs})
    builder.setupHorizontalMetrics({name: (0, 0) for name in glyphs})
    builder.setupHorizontalHeader(ascent=2, descent=-1, lineGap=0)
    builder.setupOS2(sTypoAscender=2, sTypoDescender=-1, usWinAscent=2, usWinDescent=1)
    builder.setupNameTable({
        "familyName": "Widget Marquee Speed",
        "styleName": "Regular",
        "uniqueFontIdentifier": "WidgetMarqueeSpeed-Regular-1.0",
        "fullName": "Widget Marquee Speed Regular",
        "psName": "WidgetMarqueeSpeed-Regular",
    })
    builder.setupPost()
    setup_clock_substitutions(builder, digits)
    setup_variable_advances(builder, glyphs)
    builder.font["head"].created = builder.font["head"].modified = 3850000000
    builder.font.recalcTimestamp = False
    resources = Path(__file__).resolve().parents[1] / "Sources" / "MarqueeKit" / "Resources"
    builder.save(resources / "WidgetMarqueeSpeed.ttf")


if __name__ == "__main__":
    main()
