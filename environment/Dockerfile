FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    python3 \
    python3-pip \
    rustc \
    cargo \
    golang-go \
    clang \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# Agent will work here
COPY workspace/ /workspace/
