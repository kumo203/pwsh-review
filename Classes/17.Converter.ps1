# Port of review/lib/review/converter.rb -- one Compiler bound to one Builder instance
# for a whole book; Convert() compiles a single chapter (looked up by basename-without-
# extension via the book's chapter index) and writes the result to a file.

class ReviewConverter {
    hidden [object] $Book
    hidden [object] $BuilderInstance
    hidden [ReviewCompiler] $CompilerInstance

    ReviewConverter([object]$Book, [object]$Builder) {
        $this.Book = $Book
        $this.Book.Config.Set('builder', $Builder.target_name())
        $this.BuilderInstance = $Builder
        $this.CompilerInstance = [ReviewCompiler]::new($Builder)
    }

    [void] Convert([string]$File, [string]$OutputPath) {
        $chapName = [System.IO.Path]::GetFileNameWithoutExtension($File)
        $chap = $this.Book.Chapter($chapName)
        $result = $this.CompilerInstance.Compile($chap)
        Set-Content -LiteralPath $OutputPath -Value $result -NoNewline -Encoding utf8
    }
}
