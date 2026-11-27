"""Generate the transparent clock font for timed, eased and paused Live Activity passes."""

import argparse
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

from make_speed_font import CLOCK_CONTEXTS, CLOCK_PLACES


PHASE_COUNT = 4096
BIT_COUNT = (PHASE_COUNT - 1).bit_length()
FULL_ADVANCE = 24_000  # 24 em, matching the font size of one repeat width / 24 in Swift.

DIGITS = [f"d{digit}" for digit in range(10)]
POSITIONAL_DIGITS = [f"{place}{digit}" for place, _ in CLOCK_PLACES for digit in range(10)]
PHASES = [f"p{phase}" for phase in range(PHASE_COUNT)]
ACCUMULATORS = [f"a{phase}" for phase in range(PHASE_COUNT)]
ADD_BITS = [f"o{bit}" for bit in range(BIT_COUNT)]
EASED_PHASES = [f"e{phase}" for phase in range(PHASE_COUNT)]
GLYPH_ORDER = [
    ".notdef", "blank", "colon", "decimal", *DIGITS, *POSITIONAL_DIGITS,
    *PHASES, *ACCUMULATORS, *ADD_BITS, *EASED_PHASES,
]
DEFAULT_PATH = Path(__file__).resolve().parents[1] / "Sources/WidgetMarquee/Resources/WidgetMarqueePlayback.ttf"


def glyph_class(name, glyphs):
    return f"@{name} = [{' '.join(glyphs)}];"


def setup_substitutions(builder):
    rules = [
        "languagesystem DFLT dflt;", "languagesystem latn dflt;",
        glyph_class("d", DIGITS), glyph_class("ph", PHASES), glyph_class("acc", ACCUMULATORS),
        glyph_class("out", EASED_PHASES), glyph_class("ops", ADD_BITS),
    ]
    for place, _ in CLOCK_PLACES:
        rules.append(glyph_class(place, [f"{place}{digit}" for digit in range(10)]))
    rules.append("feature rlig {")
    for place, before, after in CLOCK_CONTEXTS:
        rules.append(f"lookup {place} {{ sub {before} @d' {after} by @{place}; }} {place};")
    rules.append("} rlig;")

    # The Swift clock assigns each nonzero digit an alternate equal to the time
    # that digit represents, reduced modulo one cycle and quantized to a phase.
    for place, maximum in CLOCK_PLACES:
        for digit in range(1, maximum + 1):
            tag = f"W{place.upper()}{digit}"
            rules.append(f"feature {tag} {{ sub {place}{digit} from @ph; }} {tag};")

    rules.extend(["feature rlig {", "lookup cleanup {"])
    for glyph in POSITIONAL_DIGITS + DIGITS:
        rules.append(f"sub {glyph} by p0;")
    for separator in ["colon", "decimal"]:
        rules.append(f"sub {separator} by NULL;")
    rules.extend([
        "} cleanup;",
        "lookup first { ignore sub [@ph @acc] @ph'; sub @ph' by @acc; } first;",
        "lookup expand {",
    ])

    # Keep the first phase as the accumulator. Expand every remaining phase into
    # powers of two, so addition needs only PHASE_COUNT × BIT_COUNT ligatures.
    for phase, glyph in enumerate(PHASES):
        bits = [name for bit, name in enumerate(ADD_BITS) if phase & (1 << bit)]
        rules.append(f"sub {glyph} by {' '.join(bits) or 'NULL'};")
    rules.extend(["} expand;", "} rlig;", "lookup add {"])
    for phase, accumulator in enumerate(ACCUMULATORS):
        for bit, operand in enumerate(ADD_BITS):
            result = ACCUMULATORS[(phase + (1 << bit)) % PHASE_COUNT]
            rules.append(f"sub {accumulator} {operand} by {result};")

    # Each lookup consumes one bit. At most seven clock places contribute values.
    additions = " ".join(["lookup add"] * (BIT_COUNT * len(CLOCK_PLACES)))
    rules.extend([
        "} add;", "feature rlig {", f"sub @acc' {additions};", "} rlig;",
        "feature EASE { sub @acc by @out; } EASE;",
    ])
    addOpenTypeFeaturesFromString(builder.font, "\n".join(rules))


def advance_width(phase, moving_fraction, eased):
    """Remaining space ahead of the message. Holding at the loop head uses zero width."""
    if moving_fraction > 0:
        progress = min(1, phase / moving_fraction)
    else:
        progress = 1 if phase else 0
    if eased:
        progress = progress * progress * (3 - 2 * progress)
    return round(FULL_ADVANCE * (1 - progress))


def setup_duty_axis(builder):
    # DUTY is travel / (travel + pause). The extra samples near zero resolve
    # short movements followed by long holds. Each sample defines one HVAR region.
    samples = sorted({0.0, 1.0, *(i / 128 for i in range(1, 128)), *(2 ** -i for i in range(8, 16))})
    builder.setupFvar([("DUTY", 0, 1, 1, "Moving fraction")], [])
    builder.setupGvar({})
    regions = []
    for index, value in enumerate(samples[:-1]):
        previous = samples[max(0, index - 1)]
        following = samples[index + 1]
        regions.append({"DUTY": (previous - 1, value - 1, following - 1)})

    rows = [[0] * len(regions)]
    row_for_glyph = dict.fromkeys(GLYPH_ORDER, 0)
    for glyphs, eased in [(ACCUMULATORS, False), (EASED_PHASES, True)]:
        for index, glyph in enumerate(glyphs):
            phase = index / PHASE_COUNT
            default = advance_width(phase, 1, eased)
            row_for_glyph[glyph] = len(rows)
            rows.append([advance_width(phase, sample, eased) - default for sample in samples[:-1]])

    table = otTables.HVAR()
    table.Version = 0x00010000
    region_list = buildVarRegionList(regions, ["DUTY"])
    table.VarStore = buildVarStore(region_list, [buildVarData(list(range(len(regions))), rows)])
    table.AdvWidthMap = buildDeltaSetIndexMap([row_for_glyph[name] for name in GLYPH_ORDER])
    table.LsbMap = None
    table.RsbMap = None
    hvar = newTable("HVAR")
    hvar.table = table
    builder.font["HVAR"] = hvar


def build_font(output=DEFAULT_PATH):
    builder = FontBuilder(1000, isTTF=True)
    builder.setupGlyphOrder(GLYPH_ORDER)
    cmap = {ord(str(i)): glyph for i, glyph in enumerate(DIGITS)}
    cmap.update({ord(":"): "colon", ord("."): "decimal", ord(","): "decimal", 32: "blank", 0x200E: "blank"})
    builder.setupCharacterMap(cmap)
    builder.setupGlyf({name: TTGlyphPen(None).glyph() for name in GLYPH_ORDER})
    metrics = dict.fromkeys(GLYPH_ORDER, (0, 0))
    for index in range(PHASE_COUNT):
        phase = index / PHASE_COUNT
        metrics[ACCUMULATORS[index]] = (advance_width(phase, 1, False), 0)
        metrics[EASED_PHASES[index]] = (advance_width(phase, 1, True), 0)
    builder.setupHorizontalMetrics(metrics)
    builder.setupHorizontalHeader(ascent=2, descent=-1, lineGap=0)
    builder.setupOS2(sTypoAscender=2, sTypoDescender=-1, usWinAscent=2, usWinDescent=1)
    builder.setupNameTable({
        "familyName": "Widget Marquee Playback", "styleName": "Regular", "psName": "WidgetMarqueePlayback-Regular",
    })
    builder.setupPost()
    setup_substitutions(builder)
    setup_duty_axis(builder)
    builder.font["head"].created = builder.font["head"].modified = 3850000000
    builder.font.recalcTimestamp = False
    builder.save(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_PATH)
    build_font(parser.parse_args().output)
