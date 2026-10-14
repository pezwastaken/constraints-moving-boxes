#!/bin/bash

# clang -c -o gen_actions.o gen_actions.c -Weverything -Werror \
#     -Wno-variadic-macros -Wno-declaration-after-statement -Wno-padded \
#     -Wno-unsafe-buffer-usage -Wno-unused-function \
#     -ferror-limit=100 -fsanitize=address -fPIC
#

clang -shared -fPIC -o gen_actions.so gen_actions.c \
    -Weverything -Werror \
    -Wno-variadic-macros -Wno-declaration-after-statement -Wno-padded \
    -Wno-unsafe-buffer-usage -Wno-unused-function -Wno-covered-switch-default \
    -ferror-limit=100

