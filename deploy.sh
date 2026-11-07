#!/usr/bin/env bash
set -e

echo ""
echo ">>> Starting RESPAWN: PARALLAX GitHub Pages Deployment..."
echo ""

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

# 1. Locate Godot
GODOT_CMD="${GODOT_PATH:-}"
if [ -z "$GODOT_CMD" ]; then
  for candidate in \
    "/c/Godot_v4.7.2-stable_win64.exe" \
    "C:\\Godot_v4.7.2-stable_win64.exe" \
    "$HOME/Desktop/Godot_v4.7.2-stable_win64.exe" \
    "godot"; do
    if command -v "$candidate" >/dev/null 2>&1 || [ -f "$candidate" ]; then
      GODOT_CMD="$candidate"
      break
    fi
  done
fi

if [ -z "$GODOT_CMD" ]; then
  echo "Error: Godot executable not found. Set GODOT_PATH environment variable." >&2
  exit 1
fi

echo "[1/5] Exporting Web release using: $GODOT_CMD"
mkdir -p build/web
"$GODOT_CMD" --headless --path . --export-release "Web" "build/web/index.html"
echo "[OK] Godot Web export complete."

# 2. Ensure .nojekyll exists
touch build/web/.nojekyll
echo "[OK] Verified build/web/.nojekyll"

# 3. Git Stage & Commit
echo "[2/5] Staging changes..."
git add -A
if ! git diff-index --quiet HEAD --; then
  echo "[3/5] Committing project and build files..."
  git commit -m "Update Godot web build for GitHub Pages"
else
  echo "[3/5] Working tree is clean, no new commit needed."
fi

# 4. Push main
echo "[4/5] Pushing main branch to origin..."
git push origin main || echo "Warning: Push to origin/main returned non-zero code. Check GitHub repository write permissions."

# 5. Push subtree to gh-pages
echo "[5/5] Pushing build/web subtree to origin/gh-pages..."
if ! git subtree push --prefix build/web origin gh-pages; then
  echo "Executing fallback subtree split push..."
  SPLIT_COMMIT=$(git subtree split --prefix build/web main)
  git push origin "${SPLIT_COMMIT}:refs/heads/gh-pages" --force || echo "Warning: Push to gh-pages failed."
fi

# 6. Print Live URL
REMOTE_URL=$(git remote get-url origin 2>/dev/null || true)
if [[ "$REMOTE_URL" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)? ]]; then
  USER="${BASH_REMATCH[1]}"
  REPO="${BASH_REMATCH[2]}"
  echo ""
  echo "======================================================="
  echo "   DEPLOYMENT PROCESS COMPLETE"
  echo "======================================================="
  echo "Live GitHub Pages URL: https://${USER}.github.io/${REPO}/"
  echo ""
fi
