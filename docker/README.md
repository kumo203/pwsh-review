# pwsh-review Docker image

A single Linux image that contains **everything** needed to turn a Re:VIEW project into a
PDF with the PowerShell port. The host only needs Docker.

```
pwsh-review (debian:bookworm-slim)
├── TeX Live: uplatex, mendex, dvipdfmx, Japanese fonts (HaranoAji)
│     the same LaTeX packages as the Ruby review-oracle:5.9 image
├── PowerShell 7 + powershell-yaml
├── PwshReview module   (/usr/local/share/powershell/Modules/PwshReview)
└── commands: pwsh-review-pdfmaker, pwsh-review-tex
```

There is **no Ruby Re:VIEW** in this image. Inside it, the module runs the TeX tools
directly (`PWSHREVIEW_LATEX_BACKEND=Native`). On a Windows host without this image, the
module instead starts a TeX container for each tool call (the default `Docker` backend).

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | The image. Build context is the **repository root**. |
| `Dockerfile.dockerignore` | Limits the build context to the module sources and `docker/bin`. |
| `compose.yaml` | Build + run with Docker Compose, mounting a project at `/work`. |
| `bin/pwsh-review-pdfmaker.ps1` | `review-pdfmaker`-style CLI for `Invoke-ReviewPdfMaker`. |
| `bin/pwsh-review-tex.ps1` | CLI for `ConvertTo-ReviewLatex` (LaTeX sources only). |

## Build

From the repository root:

```powershell
docker build -f docker/Dockerfile -t pwsh-review:latest .
# or
docker compose -f docker/compose.yaml build
```

Build arguments: `POWERSHELL_VERSION` (default `7.6.6`) and `POWERSHELL_YAML_VERSION`
(default `0.4.12`). Works on `amd64` and `arm64`.

## Use

Run from the directory that contains your project's `config.yml`. The PDF
(`<bookname>.pdf`) is written next to it.

```powershell
# PowerShell
docker run --rm -v "${PWD}:/work" pwsh-review                      # = pwsh-review-pdfmaker config.yml
docker run --rm -v "${PWD}:/work" pwsh-review pwsh-review-pdfmaker config.yml --debug
docker run --rm -v "${PWD}:/work" pwsh-review pwsh-review-tex config.yml out-tex
```

```sh
# bash (Git Bash on Windows: prefix with MSYS_NO_PATHCONV=1)
docker run --rm -v "$PWD:/work" pwsh-review pwsh-review-pdfmaker config.yml
```

With Compose, point `REVIEW_PROJECT` at the project directory (required; use an absolute
path, since relative paths resolve against `docker/`):

```powershell
$env:REVIEW_PROJECT = "C:\path\to\book\articles"
docker compose -f docker/compose.yaml run --rm pwsh-review
```

### `pwsh-review-pdfmaker`

Same options as Ruby's `review-pdfmaker`:

| Option | Meaning |
|---|---|
| `[config.yml]` | Project config (default `config.yml`). |
| `--debug` | Keep the build directory `<bookname>-pdf/` (with all generated `.tex`). |
| `--ignore-errors` | Build the PDF even if some chapters fail to compile. |
| `-y a,b` / `--only a,b` | Build only the named files. |

### `pwsh-review-tex`

`pwsh-review-tex [config.yml] [output-dir] [--ignore-errors]` writes every chapter `.tex`
plus `__REVIEW_BOOK__.tex` to `output-dir` (default `<bookname>-tex`) without running LaTeX.

### Interactive shell

```powershell
docker run --rm -it -v "${PWD}:/work" pwsh-review pwsh
PS /work> Import-Module PwshReview
PS /work> Invoke-ReviewPdfMaker -Path config.yml -KeepBuildDir
```

## Notes

- **File ownership on Linux hosts.** The container runs as root, so generated files are
  root-owned. To keep your own user, add `--user "$(id -u):$(id -g)" -e HOME=/tmp`. Not
  needed with Docker Desktop on Windows/macOS.
- **Case-sensitive paths.** Inside the container the file system is case-sensitive, like
  real Re:VIEW on Linux. An image referenced as `Foo.PNG` must match the file name on disk.
- **Comparing with Ruby Re:VIEW.** The repository's tests still use the Ruby
  `review-oracle:5.9` image (from `docker-review`) as the reference implementation; this
  image doesn't replace it.

## Reserved for future features

The Dockerfile has a commented-out section with the extra tools the Ruby image ships,
ready to re-enable when the port grows the matching feature:

| Tool | Needed for |
|---|---|
| `zip` (**already installed**) | EPUB packaging (`epubmaker.zip_stage1`/`zip_stage2`) |
| Node.js + Playwright + CJK/emoji fonts (~350 MB) | Browser-based rendering, e.g. `math_format: imgmath` with the Playwright converter |
| MeCab | Japanese index readings (`pdfmaker.makeindex_mecab`) |
| pandoc | Markdown → Re:VIEW conversion |
