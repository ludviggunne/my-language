
syn keyword myLanguageKeyword    fn return if else continue
syn keyword myLanguageKeyword    break let while print
syn keyword myLanguageBoolean    true false
syn keyword myLanguageType       int bool
syn match   myLanguageComment    "#.*$"
syn match   myLanguageNumber     "\d\+"
syn match   myLanguageIdentifier "[a-zA-Z_][a-zA-Z_0-9]*"

hi def link myLanguageKeyword    Keyword
hi def link myLanguageComment    Comment
hi def link myLanguageNumber     Number
hi def link myLanguageIdentifier Identifier
hi def link myLanguageBoolean    Boolean
hi def link myLanguageType       Type
