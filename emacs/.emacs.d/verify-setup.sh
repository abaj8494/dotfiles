#!/bin/bash
# Verification script for Emacs setup

echo "🔍 Verifying Emacs Configuration Setup..."
echo ""

# Check fd
echo "1. Checking fd (fuzzy finder)..."
if command -v fd &> /dev/null; then
    echo "   ✅ fd found: $(which fd)"
    echo "   Version: $(fd --version)"
else
    echo "   ❌ fd not found! Install with: brew install fd"
fi
echo ""

# Check MacPorts GCC
echo "2. Checking MacPorts GCC-15..."
if [ -f "/opt/local/bin/gcc-mp-15" ]; then
    echo "   ✅ gcc-mp-15 found"
    echo "   Version: $(/opt/local/bin/gcc-mp-15 --version | head -1)"
else
    echo "   ❌ gcc-mp-15 not found! Install with: sudo port install gcc15"
fi
echo ""

# Check libgccjit
echo "3. Checking libgccjit..."
if [ -f "/opt/local/lib/gcc15/libgccjit.dylib" ]; then
    echo "   ✅ libgccjit.dylib found"
    ls -lh /opt/local/lib/gcc15/libgccjit.dylib | awk '{print "   Size:", $5}'
else
    echo "   ⚠️  libgccjit.dylib not found at expected location"
fi
echo ""

# Check Emacs
echo "4. Checking Emacs..."
if [ -f "/Applications/Emacs.app/Contents/MacOS/Emacs" ]; then
    echo "   ✅ Emacs.app found"
    /Applications/Emacs.app/Contents/MacOS/Emacs --version | head -1
else
    echo "   ❌ Emacs.app not found at /Applications/Emacs.app"
fi
echo ""

# Check early-init.el
echo "5. Checking early-init.el..."
if [ -f "$HOME/.emacs.d/early-init.el" ]; then
    echo "   ✅ early-init.el exists"
    grep -q "gcc-mp-15" "$HOME/.emacs.d/early-init.el" && echo "   ✅ gcc-mp-15 configured" || echo "   ⚠️  gcc-mp-15 not configured"
else
    echo "   ❌ early-init.el not found"
fi
echo ""

# Check package-config.el
echo "6. Checking package-config.el..."
if [ -f "$HOME/.emacs.d/elisp/package-config.el" ]; then
    echo "   ✅ package-config.el exists"
    grep -q "aj/helm-fd" "$HOME/.emacs.d/elisp/package-config.el" && echo "   ✅ helm-fd functions configured" || echo "   ⚠️  helm-fd functions not found"
    grep -q "helm-mode 1" "$HOME/.emacs.d/elisp/package-config.el" && echo "   ✅ helm-mode enabled" || echo "   ⚠️  helm-mode not enabled"
else
    echo "   ❌ package-config.el not found"
fi
echo ""

# Test fd in Documents
echo "7. Testing fd in ~/Documents..."
if [ -d "$HOME/Documents" ]; then
    file_count=$(cd "$HOME/Documents" && fd --color=never --hidden --follow . 2>/dev/null | wc -l | tr -d ' ')
    if [ "$file_count" -gt 0 ]; then
        echo "   ✅ fd works! Found $file_count files/directories"
    else
        echo "   ⚠️  fd returned no results (Documents might be empty)"
    fi
else
    echo "   ⚠️  ~/Documents directory not found"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ Verification complete!"
echo ""
echo "Next steps:"
echo "  1. Restart Emacs completely"
echo "  2. Open a file in ~/Documents"
echo "  3. Press s-f (Command+F) to test fuzzy finding"
echo "  4. Type 'new-site' or 'library' to search"
echo ""
echo "See SETUP_INSTRUCTIONS.md for more details."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

