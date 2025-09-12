#!/bin/bash
# Script to set Windows timezone to Norway (Oslo)

echo "Changing timezone to Norway Standard Time..."
powershell.exe -Command "tzutil /s 'W. Europe Standard Time'"

echo "Timezone is now:"
powershell.exe -Command "tzutil /g"

