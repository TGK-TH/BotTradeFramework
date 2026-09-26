#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_ROOT_WIN="$(/usr/local/bin/winepath -w "$PROJECT_ROOT/Python")"
export WINEPREFIX="$HOME/wine-python-mt5"

if [ "$#" -lt 1 ]; then
  echo "Usage:" >&2
  echo "  $0 Python/script.py [args...]" >&2
  echo "  $0 -m module [args...]" >&2
  echo "  $0 -c 'code'" >&2
  exit 1
fi

case "$1" in
  -m|-c)
    exec /usr/local/bin/wine \
      'C:\Python312\python.exe' \
      "$1" "$2" "${@:3}"
    ;;
  *)
    SCRIPT_PATH="$1"
    shift
    SCRIPT_WIN="$(/usr/local/bin/winepath -w "$PROJECT_ROOT/$SCRIPT_PATH")"

    exec /usr/local/bin/wine \
      'C:\Python312\python.exe' \
      -c "import runpy, sys; sys.path.insert(0, r'$PYTHON_ROOT_WIN'); sys.argv = [r'$SCRIPT_WIN'] + sys.argv[1:]; runpy.run_path(r'$SCRIPT_WIN', run_name='__main__')" \
      "$SCRIPT_WIN" "$@"
    ;;
esac
