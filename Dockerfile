# Use a fixed Ubuntu LTS version
FROM ubuntu:latest

# Set environment variables for consistent, non-interactive installs
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"

# Install snapd and dependencies
RUN apt-get update && \
    apt-get install -y \
        snapd fuse squashfuse git tmux && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Snapd needs /run/snapd to exist
RUN mkdir -p /run/snapd

# Start snapd in the background and keep the container alive with bash
CMD ["/bin/bash", "-c", "snapd & exec bash"]
