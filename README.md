# pwsh-review

A PowerShell 7+ port of [Re:VIEW](https://reviewml.org)'s **PDF generation pipeline** —
the Ruby toolchain used to author technical books in a lightweight markup (`.re` files)
and compile them to PDF via LaTeX.

Re:VIEW itself never implements LaTeX typesetting — it generates `.tex` and shells out to
external `uplatex`/`dvipdfmx`/`mendex` binaries. This port does the same, except the LaTeX
toolchain runs inside a Docker container (see [LaTeX backend](#latex-backend-docker)
below) rather than assuming a native TeX Live/MiKTeX install.

## Status

**M0 through M4 are complete.** The module scaffold, Docker-backed process runner,
`Configure`/`Catalog`/Book model, the full markup parser (`Compiler`), the pass-1 index
builder, a useful subset of the LaTeX builder (headlines, paragraphs, lists, captioned
code blocks, footnotes, core inline formatting, cross-chapter reference resolution), and
the full PDF-maker orchestration (hand-ported LaTeX templates, colophon/author/history
rendering, and the Docker-backed `uplatex`×3 → `mendex` (conditional) → `dvipdfmx`
pipeline) are all in place and tested — 56 Pester tests pass.

**`Invoke-ReviewPdfMaker` produces a real, valid PDF end-to-end.** With deterministic
inputs (pinned `date`/`urnid`), the generated `__REVIEW_BOOK__.tex` master file is
**byte-for-byte identical** to the one the real Ruby Re:VIEW produces in the
`review-oracle:5.9` Docker container — captured as a permanent regression test in
`tests/Integration/PdfMaker.Tests.ps1`. A representative chapter's own compiled output
was separately verified byte-for-byte identical too (`tests/Unit/LATEXBuilder.Tests.ps1`).
Cross-chapter references — both chapter-level (`@<chapref>`, `@<chap>`, `@<title>`,
forward and backward) and item-level (`@<list>`, `@<table>` via `otherchapter|id`
syntax) — are also verified against 2-chapter fixtures and the Docker oracle.

Still to do: `//table`/`//image`/`//bibpaper`/`//graph`/`//texequation` LaTeX
*rendering* (the cross-reference *lookups* for list/table work already; the block
syntax that defines a table/image itself doesn't render yet), and the restricted
ERB-subset interpreter for project-local template overrides (`layouts/layout.tex.erb`,
`layouts/config-local.tex.erb`, `sty/*.erb`) — currently these throw a clear
"not yet supported" error rather than silently ignoring the override, which blocks
building `FirstStepReVIEW-v3` (M6) until implemented. See [Roadmap](#roadmap) below.

## Scope (v1)

1. **PDF pipeline only.** Compiler (markup parser) → LaTeX builder → Book/Catalog/Configure
   model → PDF-maker orchestration. EPUB/HTML/text/IDGXML/Markdown/RST output formats are
   out of scope for v1.
2. **Shells out to real LaTeX tools** (`uplatex`/`platex`/`lualatex`, `dvipdfmx`,
   `mendex`) exactly as Ruby Re:VIEW does — this port does not reimplement LaTeX
   typesetting.
3. **The LaTeX toolchain runs inside Docker, not natively on Windows.** Plain Windows has
   no `uplatex`/`dvipdfmx`/`mendex` on PATH, and a native TeX Live/MiKTeX install is a
   multi-GB ask this project avoids. Docker is a **hard runtime prerequisite**: the same
   `review-oracle` image doubles as (a) the oracle that produces golden `.tex` fixtures
   for diffing, and (b) the actual execution backend every `uplatex`/`dvipdfmx`/`mendex`
   call runs against.
4. **Verification** = Docker-based golden-file diffing (capture real Ruby Re:VIEW's `.tex`
   output as golden fixtures) plus Pester ports of Ruby's `test_latexbuilder.rb`-style
   exact-string unit tests.
5. **Target:** PowerShell 7+ (`pwsh`), using PowerShell classes for the OOP structure.

## Prerequisites

- PowerShell 7+
- [`powershell-yaml`](https://github.com/cloudbase/powershell-yaml) module (`Install-Module powershell-yaml`)
- [Pester](https://pester.dev/) 5.5+ for running tests (`Install-Module Pester -MinimumVersion 5.5.0`)
- Docker Desktop, with the `review-oracle:5.9` image built locally:
  ```powershell
  docker build -t review-oracle:5.9 <path-to-docker-review>\review-5.9
  ```
  (or pull a published equivalent, e.g. `vvakame/review:5.9`, and re-tag it)

## Usage

```powershell
Import-Module .\PwshReview.psd1

# Resolve a Re:VIEW project's config.yml + catalog.yml and print the ordered chapter list
Test-ReviewCatalog -Path .\path\to\articles\config.yml

# Build config.yml into a real PDF (shells uplatex/mendex/dvipdfmx into Docker) --
# the project needs its own sty/ directory vendoring the review-jsbook .sty/.cls files
# (as a real Re:VIEW project does; see Resources/latex/review-jsbook/ in this repo for
# copies), though this port also auto-falls-back to its own bundled copies if a project
# doesn't provide one.
Invoke-ReviewPdfMaker -Path .\path\to\articles\config.yml

# Keep the build directory (./<bookname>-pdf/) instead of deleting it, and tolerate
# chapters that failed to compile:
Invoke-ReviewPdfMaker -Path .\path\to\articles\config.yml -KeepBuildDir -IgnoreCompileErrors
```

## Running the tests

```powershell
Invoke-Pester tests\Unit          # fast, no Docker required
Invoke-Pester tests\Integration    # exercises the Docker-backed process runner
```

## Architecture

### Why this isn't a naive line-by-line translation

Two facts drive the design: (a) Re:VIEW's `Compiler` has zero format knowledge — it
dispatches to builder methods by name (`@builder.send(syntax.name, *args)`), which
PowerShell supports natively via `$obj.$methodName(...)`; (b) every chapter is compiled
**twice** — once with a silent `IndexBuilder` across the *whole book* to populate
cross-reference numbering, then again with the real LaTeX builder — so forward/cross-chapter
references (`@<img>`, `@<chapref>`, `@<list>`) resolve correctly. This two-pass design is
built in from the start, not bolted on later.

### Module layout

```
PwshReview.psd1 / PwshReview.psm1   # manifest + root module: explicit ordered dot-sourcing
Classes/
  00.Exceptions.ps1          # ReviewError hierarchy (mirrors review/lib/review/exception.rb)
  01.LineInput.ps1           # pushback-capable line reader (review/lib/review/lineinput.rb)
  02.YamlLoader.ps1          # YAML + 'inherit:' chain-merge (review/lib/review/yamlloader.rb)
  03.Configure.ps1           # defaults, maker-shadowed overrides, version checks (configure.rb)
  04.I18n.ps1                # locale strings / numbering formats (review/lib/review/i18n.rb)
  05.Catalog.ps1             # catalog.yml wrapper (review/lib/review/catalog.rb)
  06.BookIndex.ps1           # Index + Item + per-kind index registries (book/index.rb)
  07.BookUnit.ps1            # shared Chapter/Part base (book/book_unit.rb)
  08.Chapter.ps1             # book/chapter.rb
  09.Part.ps1                # book/part.rb
  10.BookBase.ps1            # the "project" object: catalog parsing, Parts/Chapters tree (book/base.rb)
  11.SecCounter.ps1          # per-chapter heading/section counter (sec_counter.rb)
  12.LaTeXEscaper.ps1        # LaTeX escaping (composed into the LaTeX builder, not inherited)
  13.Compiler.ps1            # markup parser: SYNTAX/INLINE dispatch tables, do_compile loop
  14.Builder.ps1             # builder base class
  15.IndexBuilder.ps1        # pass-1 silent indexing builder
  16.LATEXBuilder.ps1        # pass-2 LaTeX builder (M2 subset -- see Status)
  17.Converter.ps1           # one Compiler + one Builder instance per book
  18.LaTeXBox.ps1            # tcolorbox minicolumn styling (latexbox.rb)
  20.ExternalProcessRunner.ps1  # Docker-backed shell-out layer (see below)
  19.PdfMaker.ps1            # orchestration (pdfmaker.rb) -- loaded after 20 despite the
                              #   filename number: array ORDER in PwshReview.psm1 controls
                              #   load order, not filename prefixes, since PdfMaker
                              #   references [ReviewProcessRunner] by type literal
  [planned, not yet implemented — see Roadmap:]
  ErbLiteTemplate.ps1        # restricted ERB-subset interpreter for project-local overrides
Private/
  LatexTemplates.ps1         # hand-ported config.erb / layout.tex.erb (New-ReviewLatexConfigBlock/
                              #   New-ReviewLatexLayout) -- plain functions, not class methods,
                              #   specifically so they can take a duck-typed binding parameter
                              #   without a forward-reference to ReviewPdfMaker
  ConvertTo-ReviewArgv.ps1   # minimal shellsplit-equivalent for texoptions/dvioptions strings
Public/
  Test-ReviewCatalog.ps1     # load + validate a book's catalog.yml
  Invoke-ReviewPdfMaker.ps1  # build config.yml -> PDF (the module's main entry point)
  [planned:] ConvertTo-ReviewLatex.ps1
Resources/
  i18n/i18n.yml              # locale data (copied from review/lib/review/i18n.yml)
  latex/review-jsbook/*      # .sty/.cls files copied byte-for-byte from
                              #   review/templates/latex/review-jsbook/ -- pure LaTeX,
                              #   interpreted by the engine itself, nothing to port
  [planned:] latex/review-jlreq/*
tests/
  Unit/           # Pester, fast, no Docker -- includes golden-diff regression tests
                  # captured from real review-oracle:5.9 runs (see Status)
  Integration/    # Pester, Docker-gated (skips if Docker unavailable) -- includes the
                  # full real-PDF-build + oracle .tex diff test
  [planned:] Golden/, tools/Update-GoldenFixtures.ps1
```

### PowerShell-specific mitigations

Porting Ruby's class hierarchy to PowerShell classes surfaced several real quirks, now
documented in code comments where they bite:

- **A method with a typed return value silently coerces a returned `$null`** into that
  type's default (e.g. `""` for `[string]`) — any method whose Ruby counterpart can
  return `nil` must be declared `[object]`, not `[string]` or left untyped (an *untyped*
  method actually defaults to `[void]`, which rejects `return` entirely).
- **A local variable whose name case-insensitively matches a class property name is a
  parse error**, not a silent shadow — the parser insists on `$this.PropName`.
- **No mixins** — Ruby's `LaTeXUtils` module is `include`d into multiple classes; this
  port uses composition (a `$Escaper` property) instead.
- **No forward references across class files** — `PwshReview.psm1` dot-sources files via
  an explicit, hand-maintained ordered array, not a sorted glob, since a class that
  references a not-yet-defined type fails to *parse*, not just to run.
- **No abstract methods** — the builder base class gives every method a real default
  body, same as Ruby's base `Builder`.
- **Dynamic dispatch** via `$obj.$methodName(@args)` is the direct analog of Ruby's
  `@builder.send(syntax.name, *args)` — the core mechanism the Compiler/Builder split
  depends on.
- Internal classes are **not exported**; the module's real surface is `Public/*.ps1`
  cmdlets. Tests reach internals via Pester's `InModuleScope PwshReview`.
- **A parameter literally named `$Args`/`$args` collides with PowerShell's automatic
  per-scriptblock `$args` variable and silently fails to bind** — no parse error, no
  runtime error, it just never receives the caller's value. This bit the Compiler's
  argument-count checker, the LaTeX `macro()` escaper (silently dropped every `{...}`
  argument), and `ReviewI18n`'s sprintf-style formatter (silently dropped every `%s`/`%d`
  substitution — the kind of bug a test can mask entirely if it asserts against a second
  call to the same broken function instead of a literal expected string). Renamed to
  `$ArgList`/`$MacroArgs`/`$FormatArgs` throughout.
- **`$this` inside a scriptblock resolves dynamically by call stack, not lexically.**
  Defining a scriptblock inside method A, then invoking it via `& $sb` from inside
  method B of a *different* class (e.g. passing a callback into `ReviewLineInput`'s
  `WhileMatch`/`UntilMatch`) rebinds `$this` to B's own instance, not A's — confirmed
  empirically, not documented anywhere obvious. Fixed by capturing `$self = $this` as a
  plain variable before defining any such scriptblock, and referencing `$self` inside it.
  `.GetNewClosure()` does not fix this — it actually breaks `$this` resolution inside a
  class method scriptblock differently (returns empty), so it's avoided entirely.
- **A single-match `[regex]::Matches(...) | ForEach-Object {...}` collapses to a scalar**
  (PowerShell's single-item-pipeline-result unwrapping), so `$result[0]` silently indexes
  a *character* out of the resulting string instead of the first array element — no
  error, just a wrong-typed value a few lines later. Force array wrapping with `@(...)`
  whenever the result might be indexed.
- **A `System.Object[]` does not bind to a .NET generic constructor's `IEnumerable<T>`
  overload, even when every element is actually a `T`** — `[List[string]]::new(@($arr))`
  throws "Cannot find an overload for 'new' and the argument count: 1" (a misleading
  message for what's actually a type mismatch, not an arity mismatch) unless `$arr` is
  first cast to `[string[]]`. This is specific to .NET generic type instantiation;
  ordinary PowerShell-defined class methods accept an `Object[]` for a declared
  `[string[]]` parameter without complaint (confirmed both ways).
- **`[CmdletBinding()]` already provides a built-in `-Debug` common parameter** — a
  cmdlet's own parameter cannot be named `Debug` without colliding with it (renamed to
  `-KeepBuildDir` in `Invoke-ReviewPdfMaker`).
- Ruby's YAML loader (Psych) **auto-parses an unquoted ISO-date-looking scalar
  (`date: 2026-10-09`) into a `Date` object**, not a string — this is a Ruby/YAML quirk
  the real `review-pdfmaker` is itself not immune to (passing such a value through its
  own `Date.parse` crashes with a `TypeError`), encountered while building a byte-for-byte
  comparison fixture against the oracle. Always quote date-like YAML scalars
  (`date: "2026-10-09"`).

### Two-pass compile/index architecture

- A builder's `Bind()` (shared by both the index-pass and LaTeX-pass builders) triggers
  `GenerateIndexes()` on the chapter and the whole book **before** doing anything else —
  so by the time any chapter is actually rendered, the entire book's cross-reference index
  already exists.
- The index-pass builder implements every syntax hook as a near-no-op that only records
  into the relevant index object, swallowing compile errors.
- The book model indexes every chapter/part across the whole book before any chapter is
  rendered, then builds the chapter index.

### Templating (ERB equivalents)

Hybrid approach:

1. **Hand-port the 2 bundled templates** (`config.erb`, `layout.tex.erb`) into native
   PowerShell string-builder functions that mirror their control flow 1:1 — small, fixed,
   and need to be byte-identical to the oracle for golden diffing.
2. **A small restricted ERB-subset interpreter** for project-local overrides
   (`layouts/layout.tex.erb`, `layouts/config-local.tex.erb`, `sty/*.erb`) — not optional,
   since `FirstStepReVIEW-v3` actually uses a live `config-local.tex.erb`. Arbitrary Ruby
   beyond the documented restricted grammar is an explicit non-goal (a clear error, not a
   silent misrender).

### LaTeX backend (Docker)

A single process-runner class wraps every shell-out, mirroring Ruby's
`Open3.capture2e`-based `system_or_raise`/`system_with_info` — but every invocation runs
inside the `review-oracle` Docker container via
`docker run --rm -v "<WorkDir>:/work" -w /work <image> <command> <args...>`, rather than
as a native Windows process. One `docker run --rm` per external command (matching Ruby's
one-process-per-call model); a longer-lived container via `docker exec` is a possible
later optimization, not required now. The PDF-maker orchestration will replicate Ruby's
exact sequence: `texcommand` ×2 unconditionally → conditional `mendex` pass + one more
`texcommand` pass → unconditional final `texcommand` pass → conditional `dvipdfmx` pass.

## Roadmap

Each milestone is independently demonstrable:

- [x] **M0 — Scaffolding.** Module manifest/root module, exception classes, line reader,
      Docker-backed process runner. `Invoke-Pester` runs green.
- [x] **M1 — Configure + Catalog + Book model.** `Test-ReviewCatalog` prints the correct
      ordered chapter list and maker-shadowed config overrides resolve correctly, against
      the real `FirstStepReVIEW-v3` fixture.
- [x] **M2 — Compiler + LaTeX builder, useful subset.** Headlines (+nonum/notoc/nodisp/
      column), paragraphs, ul/ol/dl lists, `//list`/`//emlist`/`//listnum`/`//emlistnum`/
      `//source`/`//cmd`, footnotes, and core inline ops (b/code/tt/em/strong/i/u/sub/sup/
      href/kw/ruby/br/...). Verified byte-for-byte against the Ruby oracle for a
      representative chapter. `//table`/`//image`/`//bibpaper`/`//graph`/`//texequation`
      deferred to M5.
- [x] **M3 — Two-pass index builder wired in.** Cross-chapter `@<chapref>`/`@<chap>`/
      `@<title>` (chapter-level) and `@<list>`/`@<table>` via `otherchapter|id` syntax
      (item-level, through that chapter's own index without rendering it) resolve forward
      and backward against 2-chapter fixtures, with output verified against the Docker
      oracle. `@<img>`/`@<eq>` follow the identical code path and macro pattern
      (`inline_img`/`inline_eq`) but full `//image`/`//texequation` block *rendering* —
      and thus an end-to-end test of them — waits on M5.
- [x] **M4 — Real PDF output.** The hand-ported templates (`config.erb`/`layout.tex.erb`
      equivalents), colophon/author/history rendering, and the Docker-backed process
      runner wired into the full build sequence (`uplatex`×3 → conditional `mendex` →
      `dvipdfmx`) via `Invoke-ReviewPdfMaker`, producing a real `.pdf`. With deterministic
      inputs, the generated `__REVIEW_BOOK__.tex` is byte-for-byte identical to the real
      Ruby Re:VIEW oracle's. First milestone that requires Docker Desktop running.
- [ ] **M5 — Broaden syntax coverage** against Re:VIEW's own `samples/syntax-book` and
      `samples/debug-book` fixtures via Docker golden-diffing. Adds `//table`/`//image`/
      `//bibpaper`/`//graph`/`//texequation` LaTeX rendering.
- [ ] **M6 — Full `FirstStepReVIEW-v3` end-to-end** vs. the Docker oracle. Needs the
      ERB-subset interpreter (that project uses a real `layouts/config-local.tex.erb`,
      which this port currently refuses with a clear error) plus full `Configure` schema
      coverage.

## Explicit non-goals / gaps (v1)

| Gap | Why |
|---|---|
| `review-ext.rb` (arbitrary Ruby extension loading) | No safe PowerShell equivalent without embedding a scripting engine; against the "shell out, don't reimplement" philosophy |
| MeCab Japanese index yomi/sort-key generation | `mendex` indexing itself still works without it |
| `//graph` (dot/gnuplot/blockdiag/aafigure/plantuml/mermaid) and `//texequation` imgmath rendering | Large external-tool surface, not exercised by the in-scope fixtures |
| Legacy flat-file catalog (`PREDEF`/`CHAPS`/`PART`/`POSTDEF` as plain text files) | `catalog.yml` is the modern format used by every in-scope fixture |
| EPUB/HTML/text/IDGXML/Markdown/RST builders | Explicit v1 scope decision |
| `review-preproc` (`#@mapfile`/`#@maprange`) | Not required by any in-scope fixture |
| `REVIEW_SAFE_MODE` bitmask enforcement | Stretch goal |
| Arbitrary-Ruby `.erb` beyond the documented restricted grammar | Same risk category as `review-ext.rb` |
| PDF byte-for-byte binary diffing | PDF embeds non-deterministic metadata even from identical `.tex`; `.tex`-level diff is the real contract |

## Reference material

- [`review`](https://github.com/kmuto/review) — the Ruby Re:VIEW source this ports from.
- [`docker-review`](https://github.com/vvakame/docker-review) — the Docker images used as
  both test oracle and LaTeX execution backend.
- [`FirstStepReVIEW-v3`](https://github.com/TechBooster/FirstStepReVIEW-v3) — a real-world
  example Re:VIEW book project, used as the end-to-end acceptance fixture.
