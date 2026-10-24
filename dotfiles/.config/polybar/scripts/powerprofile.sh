#!/usr/bin/env bash
command -v powerprofilesctl >/dev/null || exit 0
case $(powerprofilesctl get 2>/dev/null) in
  performance) echo "󰓅" ;;
  balanced)    echo "󰾅" ;;
  power-saver) echo "󰾆" ;;
esac
