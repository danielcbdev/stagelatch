#!/bin/sh
# stagelatch:managed
if command -v stagelatch >/dev/null 2>&1; then
  exec stagelatch run pre-commit "$@"
elif command -v stagelatch.bat >/dev/null 2>&1; then
  exec stagelatch.bat run pre-commit "$@"
elif command -v dart >/dev/null 2>&1 &&
  dart pub global list 2>/dev/null | grep -q '^stagelatch '; then
  exec dart pub global run stagelatch run pre-commit "$@"
fi
echo "stagelatch not found; skipping. Install: dart pub global activate stagelatch" >&2
exit 0
