# Container image
FROM python:3.12.16-slim-trixie

# Lab packages needed by lab
RUN apt-get update && \ 
    apt-get install -y --no-install-recommends socat curl && \
    rm -rf /var/lib/apt/lists/*
# Create this directory in the base image
RUN mkdir -p /data
