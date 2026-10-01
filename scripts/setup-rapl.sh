#!/bin/bash
# setup-rapl.sh - permet la lecture de RAPL energy_uj sans sudo
#
# Depuis la CVE-2020-8694, le kernel restreint la lecture de
# /sys/class/powercap/intel-rapl/*/energy_uj aux processus root.
# Ce script detecte la plateforme et propose la bonne methode :
#
#   - Guix System   : snippet /etc/config.scm
#   - NixOS         : snippet configuration.nix
#   - Distros classiques : installation udev directe dans /etc
#
# Usage :
#   sudo bash scripts/setup-rapl.sh          # groupe par defaut : users
#   sudo bash scripts/setup-rapl.sh mon_grp  # groupe explicite

set -euo pipefail

GROUP="${1:-users}"

RAPL_DIR="/sys/class/powercap/intel-rapl/intel-rapl:0"
RAPL_FILE="$RAPL_DIR/energy_uj"

# ---------------------------------------------------------------------
# Detection de plateforme
# ---------------------------------------------------------------------

detect_platform() {
    if [ -e /etc/NIXOS ]; then
        echo "nixos"
    elif command -v guix >/dev/null 2>&1 && [ -e /etc/config.scm ]; then
        echo "guix"
    elif [ -e /run/current-system ] && [ -e /etc/config.scm ]; then
        echo "guix"
    else
        echo "generic"
    fi
}

PLATFORM=$(detect_platform)

# ---------------------------------------------------------------------
# Guix
# ---------------------------------------------------------------------

if [ "$PLATFORM" = "guix" ]; then
    cat <<EOF
Detection Guix System.

Ajoutez ceci a votre /etc/config.scm, dans le bloc (operating-system ...)
ou dans (services ...), puis 'sudo guix system reconfigure /etc/config.scm' :

  (use-modules (gnu services udev))
  (use-modules (gnu services base))  ;; pour udev-service-type

  (simple-service 'rapl-readable udev-service-type
    (list (udev-rule "99-rapl-readable.rules"
            "SUBSYSTEM==\\\\"powercap\\\\", ACTION==\\\\"add|change\\\\", RUN+=\\\\"/run/current-system/profile/bin/chgrp $GROUP %S%p/energy_uj\\\\", RUN+=\\\\"/run/current-system/profile/bin/chmod 0440 %S%p/energy_uj\\\\"")))

En attendant le reconfigure, un 'sudo chmod +r $RAPL_FILE'
temporaire fonctionne pour la session courante.
EOF
    exit 0
fi

# ---------------------------------------------------------------------
# NixOS
# ---------------------------------------------------------------------

if [ "$PLATFORM" = "nixos" ]; then
    cat <<EOF
Detection NixOS.

Ajoutez ceci a votre configuration.nix, puis 'sudo nixos-rebuild switch' :

  services.udev.extraRules = ''
    SUBSYSTEM=="powercap", ACTION=="add|change", \\
      RUN+="\${pkgs.coreutils}/bin/chgrp $GROUP %S%p/energy_uj", \\
      RUN+="\${pkgs.coreutils}/bin/chmod 0440 %S%p/energy_uj"
  '';

En attendant le rebuild, un 'sudo chmod +r $RAPL_FILE'
temporaire fonctionne pour la session courante.
EOF
    exit 0
fi

# ---------------------------------------------------------------------
# Distro classique : on installe
# ---------------------------------------------------------------------

# Sur generique : si deja lisible, on informe et on sort.
if [ -r "$RAPL_FILE" ]; then
    echo "RAPL est deja lisible : $RAPL_FILE"
    exit 0
fi

if [ "$(id -u)" != "0" ]; then
    echo "Sur plateforme generique, ce script doit etre lance en root (sudo)." >&2
    exit 1
fi

RULE_FILE="/etc/udev/rules.d/99-rapl-readable.rules"
RULE_CONTENT="SUBSYSTEM==\"powercap\", ACTION==\"add|change\", RUN+=\"/bin/chgrp $GROUP %S%p/energy_uj\", RUN+=\"/bin/chmod 0440 %S%p/energy_uj\""

echo "Ecriture de $RULE_FILE (groupe : $GROUP)..."
if ! echo "$RULE_CONTENT" > "$RULE_FILE" 2>/dev/null; then
    echo "Echec d'ecriture dans $RULE_FILE." >&2
    echo "Verifiez que /etc n'est pas en lecture seule." >&2
    exit 1
fi

echo "Rechargement des regles udev..."
udevadm control --reload-rules
udevadm trigger --subsystem-match=powercap

echo "OK. Verification :"
ls -la "$RAPL_FILE" || true
