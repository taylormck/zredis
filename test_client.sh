#!/bin/bash

# echo -e "PING\nPING" | redis-cli &
# echo -e "PING\nPING" | redis-cli &
redis-cli set foo bar
redis-cli set foo cookie
redis-cli get foo

redis-cli set foo bar
redis-cli get foo
