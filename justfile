watch:
    watchexec -r -e zig -w src -- ./your_program.sh --dir /tmp/redis-files --dbfilename dump.rdb

functional-test:
    ./test_client.sh

unit-test:
    zig test src/main.zig

test: unit-test functional-test

benchmark:
    redis-benchmark -t set,get, -n 100000 -q

