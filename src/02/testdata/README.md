# src/02/testdata/ — test fonts for module 02 font tests

Place a TrueType font file here before running the font-dependent acceptance tests.

## Required file

```
src/02/testdata/DejaVuSans.ttf
```

The acceptance test (`docs/specs/02.acceptance_test.zig`) references this path via the
constant `TEST_FONT_PATH = "testdata/DejaVuSans.ttf"` (relative to the test working
directory, which is `src/02/`).  If the file is absent the font tests automatically
**skip** — pure tests (measureWidth, blockHeight, wrap, atlas) still run.

## Recommended font

**DejaVu Sans** — free, open source, includes both Latin and Cyrillic coverage (required
by INV-1.3) and has a `kern` table (required for the kerning acceptance tests).

Download: https://dejavu-fonts.github.io/ (DejaVuSans.ttf from the fonts/ archive)

## Alternative

Any TTF file with:
- Latin Basic (`A`–`Z`, `a`–`z`, common punctuation)
- Cyrillic (`U+0410`–`U+044F` at minimum; `Д` = U+0414 is tested)
- A `kern` or `GPOS` table

will satisfy the acceptance tests.  The kerning test uses
`stbtt_GetCodepointKernAdvance`, which reads `kern` tables only (GPOS is out of scope
per spec.md caveat); the result may be 0 for fonts with GPOS-only kerning, and that is
still a passing result.

## Do NOT commit font files

`.gitignore` should exclude `*.ttf` from this directory to avoid binary blobs in the
repository.  The acceptance tests are designed to skip gracefully when the font is absent.
