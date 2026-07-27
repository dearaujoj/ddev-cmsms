#!/usr/bin/env bash
# Interactive wizard to create a new CMSMS extension project with ddev-cmsms.
# Asks for project name, location, extension type, and CMSMS/PHP versions,
# then runs the full setup sequence.
#
# Prerequisites: ddev (v1.24.0+) must be installed and working.
#
# Usage: scripts/cmsms-new-project.sh
set -eu -o pipefail

# --- Defaults ----------------------------------------------------------------

DEFAULT_LOCATION="."
DEFAULT_TYPE="module"
DEFAULT_VERSION="2.2.22"
DEFAULT_PHP="8.3"
ADDON_REPO="dearaujoj/ddev-cmsms"

# --- Helpers -----------------------------------------------------------------

die() { echo "Error: $*" >&2; exit 1; }

bold() { printf '\033[1m%s\033[0m' "$1"; }

prompt() {
  local var=$1 msg=$2 default=$3
  if [ -n "$default" ]; then
    printf '%s [%s]: ' "$msg" "$default"
  else
    printf '%s: ' "$msg"
  fi
  read -r input
  eval "$var=\${input:-$default}"
}

confirm() {
  local msg=$1
  printf '%s (y/n): ' "$msg"
  read -r yn
  case "$yn" in y|Y|yes|Yes) return 0 ;; *) return 1 ;; esac
}

validate_name() {
  if ! [[ "$1" =~ ^[A-Za-z0-9_]+$ ]]; then
    die "invalid name '$1': must match ^[A-Za-z0-9_]+\$"
  fi
}

# --- Preflight ---------------------------------------------------------------

command -v ddev >/dev/null 2>&1 || die "ddev not found. Install it first: https://ddev.readthedocs.io/en/stable/users/install/ddev-installation/"

# --- Wizard ------------------------------------------------------------------

echo ""
echo "$(bold 'CMSMS New Project Wizard')"
echo "========================="
echo ""

# Project name
prompt PROJECT_NAME "Project name (becomes directory and DDEV project name)" ""
[ -z "$PROJECT_NAME" ] && die "project name is required"
validate_name "$PROJECT_NAME"

# Location
prompt LOCATION "Parent directory to create project in" "$DEFAULT_LOCATION"
LOCATION=$(cd "$LOCATION" 2>/dev/null && pwd) || die "directory '$LOCATION' does not exist"
PROJECT_DIR="$LOCATION/$PROJECT_NAME"

if [ -d "$PROJECT_DIR" ]; then
  die "directory already exists: $PROJECT_DIR"
fi

# Extension type
echo ""
echo "Extension types:"
echo "  1) module     - Standard CMSMS module"
echo "  2) plugin     - Smarty plugin (function/modifier)"
echo "  3) theme      - Admin theme"
echo "  4) workspace  - Multiple extensions in one project"
echo ""
prompt TYPE_CHOICE "Extension type (1-4 or name)" "$DEFAULT_TYPE"

case "$TYPE_CHOICE" in
  1|module)    EXT_TYPE="module" ;;
  2|plugin)    EXT_TYPE="plugin" ;;
  3|theme)     EXT_TYPE="theme" ;;
  4|workspace) EXT_TYPE="workspace" ;;
  *) die "invalid type choice '$TYPE_CHOICE'" ;;
esac

# Extension name(s)
EXTENSIONS=""
EXT_NAME=""

if [ "$EXT_TYPE" = "workspace" ]; then
  echo ""
  echo "Enter extensions as space-separated type:Name pairs."
  echo "Example: module:CartUtils module:StoreFront plugin:CartHelpers"
  echo "Order matters: list dependencies before dependents."
  echo ""
  prompt EXTENSIONS "Extensions list" ""
  [ -z "$EXTENSIONS" ] && die "workspace needs at least one extension"
else
  prompt EXT_NAME "Extension name" "$PROJECT_NAME"
  validate_name "$EXT_NAME"
fi

# Scaffold option (workspace only)
SCAFFOLD="no"
if [ "$EXT_TYPE" = "workspace" ]; then
  echo ""
  if confirm "Scaffold starter code in each extension directory?"; then
    SCAFFOLD="yes"
  fi
fi

# CMSMS version
prompt CMSMS_VERSION "CMSMS version" "$DEFAULT_VERSION"

# PHP version
prompt PHP_VERSION "PHP version" "$DEFAULT_PHP"

# Sample content
SAMPLE_CONTENT="no"
if confirm "Install sample/demo content? (otherwise minimal single page)"; then
  SAMPLE_CONTENT="yes"
fi

# --- Summary -----------------------------------------------------------------

echo ""
echo "$(bold 'Summary')"
echo "-------"
echo "  Project:    $PROJECT_NAME"
echo "  Directory:  $PROJECT_DIR"
echo "  Type:       $EXT_TYPE"
if [ "$EXT_TYPE" = "workspace" ]; then
  echo "  Extensions: $EXTENSIONS"
  echo "  Scaffold:   $SCAFFOLD"
else
  echo "  Name:       $EXT_NAME"
fi
echo "  CMSMS:      $CMSMS_VERSION"
echo "  PHP:        $PHP_VERSION"
echo "  Sample content: $SAMPLE_CONTENT"
echo ""

confirm "Create this project?" || { echo "Cancelled."; exit 0; }

# --- Execute -----------------------------------------------------------------

echo ""
echo "Creating project..."

# Create directory structure
mkdir -p "$PROJECT_DIR/.cmsms/public"
cd "$PROJECT_DIR"

# Initialize DDEV
echo "Configuring DDEV..."
ddev config \
  --project-type=php \
  --docroot=.cmsms/public \
  --project-name="$PROJECT_NAME" \
  --php-version="$PHP_VERSION"

# Install the add-on
echo "Installing ddev-cmsms add-on..."
ddev add-on get "$ADDON_REPO"

# Run setup
echo "Running cmsms setup..."
if [ "$EXT_TYPE" = "workspace" ]; then
  ddev cmsms setup --extensions "$EXTENSIONS" --version "$CMSMS_VERSION" --yes

  # Create extension directories
  if [ "$SCAFFOLD" = "yes" ]; then
    for entry in $EXTENSIONS; do
      etype="${entry%%:*}"
      ename="${entry##*:}"
      if [ ! -d "$ename" ]; then
        echo "  Scaffolding $etype:$ename..."
        ddev cmsms scaffold --type "$etype" --name "$ename" --dir "$ename" --yes
      else
        echo "  $ename/ already exists, skipping"
      fi
    done
  else
    for entry in $EXTENSIONS; do
      ename="${entry##*:}"
      mkdir -p "$ename"
      echo "  Created empty $ename/"
    done
  fi
else
  ddev cmsms setup --type "$EXT_TYPE" --name "$EXT_NAME" --version "$CMSMS_VERSION" --yes
fi

# Set sample content env if requested (after setup writes the config, before start triggers install)
if [ "$SAMPLE_CONTENT" = "yes" ]; then
  if grep -q '^web_environment:' .ddev/config.cmsms-project.yaml 2>/dev/null; then
    sed -i '/^web_environment:/a\  - CMSMS_SAMPLE_CONTENT=1' .ddev/config.cmsms-project.yaml
  else
    printf '\nweb_environment:\n  - CMSMS_SAMPLE_CONTENT=1\n' >> .ddev/config.cmsms-project.yaml
  fi
fi

# Start the site
echo ""
echo "Starting DDEV (this downloads and installs CMSMS, may take a minute)..."
ddev start

# --- Done --------------------------------------------------------------------

echo ""
echo "$(bold 'Done!')"
echo ""
echo "  Site:   $(ddev describe -j 2>/dev/null | grep -o '"primary_url":"[^"]*"' | head -1 | cut -d'"' -f4 || echo 'run: ddev describe')"
echo "  Admin:  ddev cmsms admin"
echo "  Stop:   ddev stop"
echo "  Resume: ddev start"
echo ""
echo "  cd $PROJECT_DIR"
echo ""
