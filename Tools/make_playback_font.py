"""Generate the transparent clock font for timed, eased and paused Live Activity passes."""

import argparse
from pathlib import Path

from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.fontBuilder import FontBuilder
from fontTools.otlLib.builder import buildSingleSubstSubtable
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib.tables.TupleVariation import TupleVariation

from make_speed_font import CLOCK_CONTEXTS, CLOCK_PLACES


PHASE_COUNT = 4096
FULL_ADVANCE = 24_000  # 24 em, matching the Swift font size of one repeat width / 24.

DIGITS = [f"d{digit}" for digit in range(10)]
POSITIONAL_DIGITS = [f"{place}{digit}" for place, _ in CLOCK_PLACES for digit in range(10)]
ACCUMULATORS = [f"a{phase}" for phase in range(PHASE_COUNT)]
# Low, middle, and high nibbles of each 12-bit clock contribution.
BANKS = "ABC"
TOKENS = [
    f"t{bank}{place}{digit}"
    for bank in BANKS for place, maximum in CLOCK_PLACES for digit in range(1, maximum + 1)
]
NIBBLES = [f"n{bank}_{value}" for bank in range(len(BANKS)) for value in range(1, 16)]
# A denser grid near the start resolves short passes followed by long pauses.
GROUP_SAMPLES = [
    *range(32), *range(32, 64, 4), *range(64, 128, 8),
    *range(128, 256, 16), *range(256, PHASE_COUNT + 1, 32),
]
GROUP_AXES = [f"P{index:03d}" for index in range(len(GROUP_SAMPLES))]
GLYPH_ORDER = [
    ".notdef", "blank", "colon", "decimal", *DIGITS, *POSITIONAL_DIGITS,
    *TOKENS, *NIBBLES, *ACCUMULATORS,
]
DEFAULT_PATH = Path(__file__).resolve().parents[1] / "Sources/MarqueeKit/Resources/WidgetMarqueePlayback.ttf"


def glyph_class(name, glyphs):
    return f"@{name} = [{' '.join(glyphs)}];"


def setup_substitutions(builder):
    rules = [
        "languagesystem DFLT dflt;", "languagesystem latn dflt;",
        glyph_class("d", DIGITS), glyph_class("acc", ACCUMULATORS),
        glyph_class("q", DIGITS + POSITIONAL_DIGITS),
    ]
    for place, _ in CLOCK_PLACES:
        rules.append(glyph_class(place, [f"{place}{digit}" for digit in range(10)]))
    rules.append("feature rlig {")
    for place, before, after in CLOCK_CONTEXTS:
        rules.append(f"lookup {place} {{ sub {before} @d' {after} by @{place}; }} {place};")
    rules.append("} rlig;")

    # Seed the sum once, before the first clock digit. Digit glyphs split into
    # three tokens so each feature only needs fifteen alternates.
    rules.append("lookup prepend {")
    for glyph in DIGITS + POSITIONAL_DIGITS:
        rules.append(f"sub {glyph} by a0 {glyph};")
    rules.extend([
        "} prepend;", "feature rlig {",
        "lookup seed { ignore sub [@q colon decimal] @q'; sub @q' lookup prepend; } seed;",
        "lookup split {",
    ])
    for place, maximum in CLOCK_PLACES:
        for digit in range(10):
            parts = [f"t{bank}{place}{digit}" for bank in BANKS] if 0 < digit <= maximum else []
            rules.append(f"sub {place}{digit} by {' '.join(parts) or 'NULL'};")
    for glyph in [*DIGITS, "colon", "decimal"]:
        rules.append(f"sub {glyph} by NULL;")
    rules.append("} split; } rlig;")

    for index, bank in enumerate(BANKS):
        alternates = " ".join(f"n{index}_{value}" for value in range(1, 16))
        for place, maximum in CLOCK_PLACES:
            for digit in range(1, maximum + 1):
                tag = f"{bank}{place.upper()}{digit}"
                token = f"t{bank}{place}{digit}"
                rules.append(f"feature {tag} {{ sub {token} from [{alternates}]; }} {tag};")

    # Each of the three selected nibbles is one operand. Rotate the
    # accumulator by its value directly, consuming up to three per digit.
    rules.append("feature rlig { lookup clear {")
    for token in TOKENS:
        rules.append(f"sub {token} by NULL;")
    rules.append("} clear; } rlig;")
    rules.append("lookup erase {")
    for operand in NIBBLES:
        rules.append(f"sub {operand} by NULL;")
    rules.append("} erase;")
    for bank in range(len(BANKS)):
        for value in range(1, 16):
            shift = value << (4 * bank)
            rules.append(f"lookup rot{bank}_{value} {{ sub a0 by a{shift}; }} rot{bank}_{value};")
    rules.append("lookup consume {")
    for bank in range(len(BANKS)):
        for value in range(1, 16):
            rules.append(f"sub @acc' lookup rot{bank}_{value} n{bank}_{value}' lookup erase;")
    rules.append("} consume;")
    repeated = " ".join(["lookup consume"] * (len(BANKS) * len(CLOCK_PLACES)))
    rules.append(f"feature rlig {{ sub @acc' {repeated}; }} rlig;")

    # A solo pass can rotate its stop onto an exact interpolation sample.
    for bit in range(5):
        tag = f"SHF{bit}"
        rules.append(f"feature {tag} {{ sub a0 by a{1 << bit}; }} {tag};")
    addOpenTypeFeaturesFromString(builder.font, "\n".join(rules))

    # Each rotation placeholder becomes two constant-delta SingleSubst ranges,
    # including wraparound. This avoids enumerating phase × bit ligatures.
    for lookup in builder.font["GSUB"].table.LookupList.Lookup:
        if lookup.LookupType != 1 or len(lookup.SubTable) != 1:
            continue
        mapping = lookup.SubTable[0].mapping
        if len(mapping) == 1 and "a0" in mapping:
            shift = int(mapping["a0"][1:])
            lookup.SubTable = [
                buildSingleSubstSubtable(dict(zip(ACCUMULATORS[:-shift], ACCUMULATORS[shift:]))),
                buildSingleSubstSubtable(dict(zip(ACCUMULATORS[-shift:], ACCUMULATORS[:shift]))),
            ]
            lookup.SubTableCount = len(lookup.SubTable)


def setup_playback_axes(builder):
    builder.setupFvar([(tag, 0, 0, 1, f"{i:02x}") for i, tag in enumerate(GROUP_AXES)], [])
    # Keep the Unicode name for each distinct axis. CoreText uses these names
    # to distinguish axes when reading a font descriptor.
    names = builder.font["name"]
    names.names = [name for name in names.names if name.nameID < 256 or name.platformID == 3]

    # Empty glyphs still have four TrueType phantom points. Moving the second
    # changes just the advance width. gvar shares one peak tuple per sample,
    # letting each phase reference its two neighboring samples and weights.
    variations = {}
    for index, (start, end) in enumerate(zip(GROUP_SAMPLES, GROUP_SAMPLES[1:])):
        left_axis, right_axis = GROUP_AXES[index:index + 2]
        for phase in range(start, end):
            right = round(FULL_ADVANCE * (phase - start) / (end - start))
            variations[ACCUMULATORS[phase]] = [
                TupleVariation({tag: (0, 1, 1)}, [None, (weight, 0), None, None])
                for tag, weight in ((left_axis, FULL_ADVANCE - right), (right_axis, right)) if weight
            ]
    builder.setupGvar(variations)


def build_font(output=DEFAULT_PATH):
    builder = FontBuilder(1000, isTTF=True)
    builder.setupGlyphOrder(GLYPH_ORDER)
    cmap = {ord(str(i)): glyph for i, glyph in enumerate(DIGITS)}
    cmap.update({ord(":"): "colon", ord("."): "decimal", ord(","): "decimal", 32: "blank", 0x200E: "blank"})
    builder.setupCharacterMap(cmap)
    builder.setupGlyf({name: TTGlyphPen(None).glyph() for name in GLYPH_ORDER})
    builder.setupHorizontalMetrics(dict.fromkeys(GLYPH_ORDER, (0, 0)))
    builder.setupHorizontalHeader(ascent=2, descent=-1, lineGap=0)
    builder.setupOS2(sTypoAscender=2, sTypoDescender=-1, usWinAscent=2, usWinDescent=1)
    builder.setupNameTable({
        "familyName": "Widget Marquee Playback Direct", "styleName": "Regular",
        "psName": "WidgetMarqueePlaybackDirect-Regular",
    })
    builder.setupPost(keepGlyphNames=False)
    setup_substitutions(builder)
    setup_playback_axes(builder)
    # Freeze the original creation date and this revision's timestamp for deterministic builds.
    builder.font["head"].created = 3850000000
    builder.font["head"].modified = 3878621914
    builder.font.recalcTimestamp = False
    builder.save(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_PATH)
    build_font(parser.parse_args().output)
