# Port of review/lib/review/book/bib.rb -- a nameless BookUnit wrapping bib.re's raw
# content, compiled through IndexBuilder once (by ReviewBookBase.GenerateIndexes) purely
# to build the book-wide bibpaper index that @<bib>{id} resolves against. bib.re is
# typically ALSO listed in the catalog as an ordinary chapter, which is what actually
# renders it; this object never renders anything.

class ReviewBib : ReviewBookUnit {
    [object] $Number = $null

    ReviewBib([object]$Book, [string]$FileContent) {
        $this.Book = $Book
        $this.Content = $FileContent
    }

    [string] FormatNumber([bool]$Heading) { return '' }
    [string] FormatNumber() { return '' }
    [bool] OnAppendix() { return $false }
    [bool] IsPart() { return $false }
}
