#!/usr/bin/env bash
# Marker only — agent will run the actual fix; this reminds if session died
echo "CORS_FIX_WINDOW_OPEN $(TZ=Europe/Zurich date -Iseconds)" >> /Users/fred/Helveticleads/Helveticleads-deploy/ops/api-server-sauvetage/cors-fix-window.log
