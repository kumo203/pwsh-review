# pwsh-review

A PowerShell 7+ port of [Re:VIEW](https://reviewml.org)'s **PDF generation pipeline** —
the Ruby toolchain used to author technical books in a lightweight markup (`.re` files)
and compile them to PDF via LaTeX.

Re:VIEW itself never implements LaTeX typesetting — it generates `.tex` and shells out to
external `uplatex`/`dvipdfmx`/`mendex` binaries. This port does the same, except the LaTeX
toolchain runs inside a Docker container (see [LaTeX backend](#latex-backend-docker)
below) rather than assuming a native TeX Live/MiKTeX install.

## Status

**M0 and M1 are complete.** The module scaffold, exception hierarchy, line-reader, and
Docker-backed process runner are in place, along with the `Configure`/`Catalog`/Book
model. 35 Pester tests pass, and `Test-ReviewCatalog` correctly resolves the real
[FirstStepReVIEW-v3](https://github.com/TechBooster/FirstStepReVIEW-v3) project's chapter
order, numbering, and catalog membership end-to-end.

The Compiler (markup parser) and LaTeX builder — the bulk of the remaining work — have
not been started yet. See [Roadmap](#roadmap) below.

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
  20.ExternalProcessRunner.ps1  # Docker-backed shell-out layer (see below)
  [planned, not yet implemented — see Roadmap:]
  11.Compiler.ps1            # markup parser: SYNTAX/INLINE dispatch tables
  12.Builder.ps1             # builder base class
  13.IndexBuilder.ps1        # pass-1 silent indexing builder
  14.LaTeXEscaper.ps1        # LaTeX escaping (composed into the LaTeX builder, not inherited)
  15.LATEXBuilder.ps1        # pass-2 LaTeX builder
  16.LaTeXBox.ps1            # tcolorbox minicolumn styling
  17.ErbLiteTemplate.ps1     # restricted ERB-subset interpreter for project-local overrides
  18.LatexTemplates.ps1      # hand-ported config.erb / layout.tex.erb equivalents
  19.Converter.ps1           # one Compiler + one Builder instance per book
  21.PdfMaker.ps1            # orchestration (mirrors review/lib/review/pdfmaker.rb)
Public/
  Test-ReviewCatalog.ps1     # load + validate a book's catalog.yml (implemented)
  [planned:] Invoke-ReviewPdfMaker.ps1, ConvertTo-ReviewLatex.ps1
Resources/
  i18n/i18n.yml              # locale data (copied from review/lib/review/i18n.yml)
  [planned:] latex/review-jsbook/*, latex/review-jlreq/*
tests/
  Unit/           # Pester, fast, no Docker
  Integration/    # Pester, Docker-gated (skips if Docker unavailable)
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
- [ ] **M2 — Compiler + LaTeX builder, single-pass, useful subset.** Headlines,
      paragraphs, `//list`/`//emlist`, a handful of inline ops, lists.
- [ ] **M3 — Two-pass index builder wired in.** Cross-chapter `@<img>`/`@<chapref>`/
      `@<list>`/`@<fn>` resolve forward and backward.
- [ ] **M4 — Real PDF output for a minimal fixture.** The hand-ported templates plus the
      Docker-backed process runner wired into the full build sequence, producing a real
      `.pdf`. First milestone that requires Docker Desktop running.
- [ ] **M5 — Broaden syntax coverage** against Re:VIEW's own `samples/syntax-book` and
      `samples/debug-book` fixtures via Docker golden-diffing.
- [ ] **M6 — Full `FirstStepReVIEW-v3` end-to-end** vs. the Docker oracle, including the
      ERB-subset interpreter, full `Configure` schema coverage, and colophon/author
      rendering.

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
