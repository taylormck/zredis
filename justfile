watch:
    watchexec -r -e zig -w src -- ./your_program.sh

functional-test:
    ./test_client.sh

unit-test:
    zig test src/main.zig

test: unit-test functional-test

