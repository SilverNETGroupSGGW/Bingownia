#!/bin/sh
# Chrome for `flutter test --platform chrome`; set CHROME_BIN to any Chrome/Chromium binary.
exec "${CHROME_BIN:-chromium}" --no-sandbox "$@"
