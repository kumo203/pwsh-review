# Mirrors review/lib/review/exception.rb's exception hierarchy:
#   Error -> ApplicationError -> ConfigError
#                             -> CompileError -> SyntaxError
#                                              -> KeyError
#                             -> FileNotFound
#                             -> BuildError

class ReviewError : System.Exception {
    ReviewError([string]$Message) : base($Message) {}
    ReviewError([string]$Message, [System.Exception]$InnerException) : base($Message, $InnerException) {}
}

class ReviewApplicationError : ReviewError {
    ReviewApplicationError([string]$Message) : base($Message) {}
    ReviewApplicationError([string]$Message, [System.Exception]$InnerException) : base($Message, $InnerException) {}
}

class ReviewConfigError : ReviewApplicationError {
    ReviewConfigError([string]$Message) : base($Message) {}
}

class ReviewCompileError : ReviewApplicationError {
    ReviewCompileError([string]$Message) : base($Message) {}
}

class ReviewSyntaxError : ReviewCompileError {
    ReviewSyntaxError([string]$Message) : base($Message) {}
}

class ReviewKeyError : ReviewCompileError {
    ReviewKeyError([string]$Message) : base($Message) {}
}

class ReviewFileNotFoundError : ReviewApplicationError {
    ReviewFileNotFoundError([string]$Message) : base($Message) {}
}

class ReviewBuildError : ReviewApplicationError {
    [string]$Location

    ReviewBuildError([string]$Message, [string]$Location) : base($Message) {
        $this.Location = $Location
    }
}
