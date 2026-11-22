# Shared, hidden setup for the README demos. Sourced by the other tapes:
# it builds a throwaway Dart package with stagelatch installed, so the
# recording starts at a clean `$` prompt in a repository that already uses it.
#
# A shim runs this checkout's bin/stagelatch.dart as `stagelatch`, so the
# recordings show what an installed stagelatch prints, without the dependency
# resolution of a path activation.

Hide
Type `set +H; export SRC="$PWD" SHIM="$(mktemp -d)" PS1='$ ' GIT_PAGER=cat PAGER=cat`
Enter
Type `printf '#!/bin/sh\nexec dart "%s/bin/stagelatch.dart" "$@"\n' "$SRC" > "$SHIM/stagelatch"`
Enter
Type `chmod +x "$SHIM/stagelatch" && export PATH="$SHIM:$PATH"`
Enter
Type `export WORK="$(mktemp -d)" && cd "$WORK" || exit 1`
Enter
Type `git init -q --bare remote.git && git init -q -b main app && cd app || exit 1`
Enter
Type `git config user.name Demo && git config user.email demo@example.invalid`
Enter
Type `printf 'name: app\nenvironment:\n  sdk: ^3.0.0\n' > pubspec.yaml && printf '.dart_tool/\npubspec.lock\n' > .gitignore && mkdir lib`
Enter
Type `printf 'int total(List<int> xs) => xs.fold(0, (a, b) => a + b);\n' > lib/cart.dart`
Enter
Type `dart pub get --offline >/dev/null && git add . && git commit -qm init && stagelatch init >/dev/null`
Enter
Type `git add stagelatch.yaml && git commit -qm config >/dev/null 2>&1`
Enter
Type `git remote add origin ../remote.git && git push -q -u origin main >/dev/null 2>&1; clear`
Enter
Sleep 3s
Show
