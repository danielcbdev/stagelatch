# The demo of README.md: a partially staged commit is formatted in the
# index, then the next commit is blocked by a path dependency.
#
# Regenerate from the repository root:
#   vhs docs/demo.tape
# A hidden shim runs this checkout's bin/stagelatch.dart as `stagelatch`, so
# the recording shows what an installed stagelatch prints, without the
# dependency resolution of a path activation.

Output docs/demo.gif

Set Shell "bash"
Set FontSize 15
Set Width 1280
Set Height 640
Set Padding 18
Set TypingSpeed 35ms
Set Theme "Catppuccin Mocha"

Hide
Type `set +H; export SRC="$PWD" SHIM="$(mktemp -d)" PS1='$ ' GIT_PAGER=cat PAGER=cat`
Enter
Type `printf '#!/bin/sh\nexec dart "%s/bin/stagelatch.dart" "$@"\n' "$SRC" > "$SHIM/stagelatch"`
Enter
Type `chmod +x "$SHIM/stagelatch" && export PATH="$SHIM:$PATH"`
Enter
Type `cd "$(mktemp -d)" || exit 1`
Enter
Type `git init -q app && cd app || exit 1`
Enter
Type `git config user.name Demo && git config user.email demo@example.invalid`
Enter
Type `printf 'name: app\nenvironment:\n  sdk: ^3.0.0\n' > pubspec.yaml && printf '.dart_tool/\npubspec.lock\n' > .gitignore`
Enter
Type `dart pub get --offline >/dev/null && git add . && git commit -qm init && stagelatch init >/dev/null`
Enter
Type `git add stagelatch.yaml && git commit -qm config >/dev/null 2>&1; mkdir -p lib && clear`
Enter
Sleep 3s
Show

# A file with formatting problems, staged; then an unstaged edit on top.
Type `printf 'int total( List<int> xs ){return xs.fold(0,(a,b)=>a+b);}\n' > lib/cart.dart && git add lib/cart.dart`
Enter
Sleep 400ms
Type `echo '// work in progress, not staged' >> lib/cart.dart`
Enter
Sleep 400ms
Type `git commit -qm 'Add cart total'`
Enter
Sleep 4s
Type `git show :lib/cart.dart`
Enter
Sleep 2s
Type `tail -1 lib/cart.dart`
Enter
Sleep 2s

# Now a path dependency that leaves the repository.
Type `printf 'dependencies:\n  design_system:\n    path: ../design_system\n' >> pubspec.yaml && git add pubspec.yaml`
Enter
Sleep 400ms
Type `git commit -qm 'Use the design system'`
Enter
Sleep 5s
