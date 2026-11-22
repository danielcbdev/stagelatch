# Demo 1 of README.md: a partially staged commit. The staged file is
# formatted in the index; the unstaged edit on top is left alone.
#
# Regenerate from the repository root:
#   vhs docs/assets/commit-autofix.tape

Output docs/assets/commit-autofix.gif

Set Shell "bash"
Set FontSize 18
Set Width 1200
Set Height 660
Set Padding 20
Set Margin 16
Set MarginFill "#11111b"
Set BorderRadius 10
Set WindowBar Colorful
Set TypingSpeed 40ms
Set Theme "Catppuccin Mocha"

Source docs/assets/_setup.tape

# A badly formatted file, ready to be staged.
Hide
Type `printf 'int total( List<int> xs ){return xs.fold(0,(a,b)=>a+b);}\n' > lib/cart.dart && clear`
Enter
Show

Type `# lib/cart.dart is badly formatted. Stage it, then keep editing.`
Enter
Type `cat lib/cart.dart`
Enter
Sleep 1500ms
Type `git add lib/cart.dart`
Enter
Type `echo '// work in progress, not staged' >> lib/cart.dart`
Enter
Sleep 600ms
Type `git commit -qm 'Add cart total'`
Enter
Sleep 4s

Type `clear`
Enter
Type `# What was committed is formatted. Your unstaged edit is untouched.`
Enter
Type `git show :lib/cart.dart`
Enter
Sleep 2500ms
Type `tail -n 1 lib/cart.dart`
Enter
Sleep 4s
