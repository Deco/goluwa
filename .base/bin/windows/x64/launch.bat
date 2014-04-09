#!/bin/bash

if %OS% == Windows_NT goto WINDOWS
then
:
## Hack to make a cross-OS compatible script
fi 2> /dev/null

# ------------------------------------------------------------------------------
# Unix execution
# ------------------------------------------------------------------------------

ARCH=$(getconf LONG_BIT)



fi

while true; do
	$(hash screen 2> /dev/null && echo "screen") env LD_LIBRARY_PATH=. ./luajit ../../../lua/init.lua
	# BROKE (when using screen) ==> if [ $? -eq 0 ] || [ $? -ge 128 ]; then echo "im outta here"; break; fi
	sleep 1
done

# ------------------------------------------------------------------------------
# Windows execution
# ------------------------------------------------------------------------------

:WINDOWS

luajit.exe ../../../lua/init.lua
pause