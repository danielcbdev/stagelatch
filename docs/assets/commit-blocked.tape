# Demo 2 of README.md: a commit blocked by two mistakes that are easy to
# make and hard to undo once pushed: a local path dependency and a committed
# .env file.
#
# Regenerate from the repository root:
#   vhs docs/assets/commit-blocked.tape

Output docs/assets/commit-blocked.gif

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

# A path dependency that leaves the repository, and a secrets file.
Hide
Type `printf 'dependencies:\n  design_system:\n    path: ../design_system\n' >> pubspec.yaml`
Enter
Type `printf 'API_KEY=not-a-real-key\n' > .env && clear`
Enter
Show

Type `# Two things that should never be committed.`
Enter
Type `tail -n 3 pubspec.yaml`
Enter
Sleep 1200ms
Type `cat .env`
Enter
Sleep 1200ms
Type `git add pubspec.yaml .env`
Enter
Sleep 500ms
Type `git commit -m 'Use the design system'`
Enter
Sleep 6s
