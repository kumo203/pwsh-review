# pwsh-review: a self-contained image with PowerShell 7, the PwshReview module and the
# same TeX Live toolchain as the Ruby review-oracle image (docker-review/review-5.9), but
# WITHOUT Ruby Re:VIEW. Inside this image the module runs uplatex/mendex/dvipdfmx
# directly (PWSHREVIEW_LATEX_BACKEND=Native) instead of starting a container per call.
#
# Build from the repository root (the build context must contain the module):
#   docker build -f docker/Dockerfile -t pwsh-review:latest .
# See docker/README.md for usage.

FROM debian:bookworm-slim

ARG TARGETARCH
ARG POWERSHELL_VERSION=7.6.6
ARG POWERSHELL_YAML_VERSION=0.4.12

ENV LANG=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive \
    POWERSHELL_TELEMETRY_OPTOUT=1 \
    POWERSHELL_UPDATECHECK=Off

# for Debian Bug#955619
RUN mkdir -p /usr/share/man/man1

# TeX toolchain: the same LaTeX package set as review-oracle:5.9 (so typesetting is
# identical), minus Ruby. `zip` is what Re:VIEW's epubmaker shells out to for packaging
# (config epubmaker.zip_stage1/zip_stage2), kept ready for the planned EPUB support.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates curl zip \
      texlive-lang-japanese texlive-fonts-recommended texlive-latex-extra lmodern fonts-lmodern \
      cm-super tex-gyre fonts-texgyre texlive-pictures texlive-plain-generic texlive-luatex \
      texlive-extra-utils ghostscript gsfonts poppler-data poppler-utils \
      libicu72 libssl3 zlib1g && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Same Japanese font mapping as review-oracle:5.9.
RUN kanji-config-updmap-sys haranoaji

# PowerShell 7 from the official release tarball (works for both amd64 and arm64).
RUN case "${TARGETARCH:-amd64}" in \
      amd64) PS_ARCH=x64 ;; \
      arm64) PS_ARCH=arm64 ;; \
      *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac && \
    curl -fsSL -o /tmp/powershell.tar.gz \
      "https://github.com/PowerShell/PowerShell/releases/download/v${POWERSHELL_VERSION}/powershell-${POWERSHELL_VERSION}-linux-${PS_ARCH}.tar.gz" && \
    mkdir -p /opt/microsoft/powershell/7 && \
    tar -xzf /tmp/powershell.tar.gz -C /opt/microsoft/powershell/7 && \
    chmod +x /opt/microsoft/powershell/7/pwsh && \
    ln -s /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh && \
    rm /tmp/powershell.tar.gz

# powershell-yaml (the module's only PowerShell dependency), installed for all users.
# (The version is expanded by /bin/sh from the build arg, not by pwsh.)
RUN pwsh -NoLogo -NoProfile -Command \
      "Install-Module powershell-yaml -RequiredVersion ${POWERSHELL_YAML_VERSION} -Scope AllUsers -Force -ErrorAction Stop"

# The PwshReview module itself, on the all-users module path.
COPY PwshReview.psd1 PwshReview.psm1 /usr/local/share/powershell/Modules/PwshReview/
COPY Classes   /usr/local/share/powershell/Modules/PwshReview/Classes
COPY Private   /usr/local/share/powershell/Modules/PwshReview/Private
COPY Public    /usr/local/share/powershell/Modules/PwshReview/Public
COPY Resources /usr/local/share/powershell/Modules/PwshReview/Resources

# review-pdfmaker-style command-line wrappers.
COPY docker/bin/ /opt/pwsh-review/bin/
RUN for cmd in pwsh-review-pdfmaker pwsh-review-tex; do \
      printf '#!/bin/sh\nexec pwsh -NoLogo -NoProfile -File /opt/pwsh-review/bin/%s.ps1 "$@"\n' "$cmd" > "/usr/local/bin/$cmd" && \
      chmod +x "/usr/local/bin/$cmd"; \
    done && \
    pwsh -NoLogo -NoProfile -Command "Import-Module PwshReview -ErrorAction Stop; Get-Command -Module PwshReview | Out-String | Write-Host"

# ---------------------------------------------------------------------------------------
# Reserved for future features (EPUB etc.). Taken from docker-review/review-5.9/Dockerfile;
# uncomment when the port gains the feature that needs it.
#
# Node.js + Playwright (+ CJK/emoji fonts, ~350MB): used by Re:VIEW for browser-based
# rendering, e.g. math_format: imgmath with the playwright converter
# (config playwright_options).
# ARG NODEJS_VERSION=20
# RUN apt-get update && apt-get install -y --no-install-recommends gnupg && \
#     curl -fsSL https://deb.nodesource.com/setup_${NODEJS_VERSION}.x | bash - && \
#     apt-get install -y --no-install-recommends nodejs && \
#     apt-get clean && rm -rf /var/lib/apt/lists/*
# RUN apt-get update && apt-get -y install --no-install-recommends \
#       fonts-noto-cjk-extra fonts-noto-color-emoji libatk1.0-0 libatk-bridge2.0-0 libdrm2 \
#       libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libgbm1 libpango-1.0-0 && \
#     apt-get clean && rm -rf /var/lib/apt/lists/*
# RUN npm install -g playwright && \
#     rm -rf /root/.cache/ms-playwright/firefox* /root/.cache/ms-playwright/webkit*
#
# MeCab: Japanese index readings for PDF (pdfmaker.makeindex_mecab; a current non-goal).
# RUN apt-get update && apt-get install -y --no-install-recommends \
#       mecab mecab-ipadic-utf8 mecab-jumandic- mecab-jumandic-utf8- && \
#     apt-get clean && rm -rf /var/lib/apt/lists/*
#
# pandoc: Markdown -> Re:VIEW conversion (pandoc2review in the Ruby image).
# RUN apt-get update && apt-get install -y --no-install-recommends pandoc && \
#     apt-get clean && rm -rf /var/lib/apt/lists/*
# ---------------------------------------------------------------------------------------

ENV PWSHREVIEW_LATEX_BACKEND=Native

WORKDIR /work
CMD ["pwsh-review-pdfmaker", "config.yml"]
