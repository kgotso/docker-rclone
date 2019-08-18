#!/bin/sh

set -e

echo "INFO: Starting clear.sh pid $$ $(date)"

# Delete left over import files
find /downloads/* -mtime +1 -exec rm -rf {} \;
