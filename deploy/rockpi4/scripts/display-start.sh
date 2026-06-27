#!/bin/bash
# ExecStartPre for display-stream.service
# Clears the primary DRM framebuffer to black before MPV takes over,
# preventing stale frames from lingering during reconnects.

dd if=/dev/zero of=/dev/fb0 bs=1M count=8 2>/dev/null || true
