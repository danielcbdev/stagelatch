# Demo 3 of README.md: `git push` runs the SDK's analyzer on the commit that
# is being pushed and blocks it; the same engine runs on the pull request.
#
# Regenerate from the repository root:
#   vhs docs/assets/push-and-ci.tape

Output docs/assets/push-and-ci.gif

Set Shell "bash"
Set FontSize 18
Set Width 1200
Set Height 700
Set Padding 20
Set Margin 16
Set MarginFill "#11111b"
Set BorderRadius 10
Set WindowBar Colorful
Set TypingSpeed 40ms
Set Theme "Catppuccin Mocha"

Source docs/assets/_setup.tape

# A feature branch with a commit that does not analyze cleanly.
Hide
Type `git switch -q -c feature`
Enter
Type `printf "import 'dart:io';\n\nString label(int n) {\n  int unused = 1;\n  return n;\n}\n" > lib/label.dart`
Enter
Type `git add lib/label.dart && git commit -qm 'Add label' && clear`
Enter
Sleep 2s
Show

Type `# The commit passed the commit hook. The push runs your SDK's analyzer.`
Enter
Type `git push -u origin feature`
Enter
Sleep 7s

Type `clear`
Enter
Type `# The pull request gets the same verdict from the same engine.`
Enter
Type `stagelatch ci --base origin/main`
Enter
Sleep 8s
