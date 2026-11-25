$ErrorActionPreference = 'Stop'
$base = 'https://raw.githubusercontent.com/let-the-dreamers-rise/kafel/pr-tools'
$d = Join-Path $env:TEMP 'kafel-prs'
New-Item -ItemType Directory -Force -Path $d | Out-Null
Invoke-WebRequest "$base/pr1.md" -OutFile "$d\pr1.md" -UseBasicParsing
Invoke-WebRequest "$base/pr2.md" -OutFile "$d\pr2.md" -UseBasicParsing
gh pr create -R google/kafel --base master --head let-the-dreamers-rise:codegen-fixes --title 'Fix two cases where the compiled filter does not do what the policy says' --body-file "$d\pr1.md"
gh pr create -R google/kafel --base master --head let-the-dreamers-rise:input-validation --title 'Lexer/parser: accept `_` identifiers, reject bad octal numbers and oversized syscall numbers' --body-file "$d\pr2.md"
