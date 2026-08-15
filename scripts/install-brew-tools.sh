#!/usr/bin/env bash
# Instala herramientas de desarrollo con Homebrew.
#
#   chmod +x scripts/install-brew-tools.sh
#   ./scripts/install-brew-tools.sh

set -euo pipefail

FORMULAE=(git ocaml jq)
CASKS=(visual-studio-code insomnia)

ensure_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    return
  fi

  echo "Homebrew no está instalado. Instalando..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

ensure_homebrew

echo "Actualizando Homebrew..."
brew update

echo "Instalando fórmulas: ${FORMULAE[*]}"
brew install "${FORMULAE[@]}"

echo "Instalando casks: ${CASKS[*]}"
brew install --cask "${CASKS[@]}"

echo
echo "Listo. Versiones:"
git --version
jq --version
ocaml -version
brew list --cask visual-studio-code insomnia
