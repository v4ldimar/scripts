#!/bin/bash
# Script to revert Windows timezone to your local setting

LOCAL_TZ="Greenwich Standard Time"

echo "Reverting timezone to $LOCAL_TZ..."
powershell.exe -Command "tzutil /s '$LOCAL_TZ'"

echo "Timezone is now:"
powershell.exe -Command "tzutil /g"

