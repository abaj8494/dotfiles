#!/usr/bin/env bash
# calc.sh — backend for the `calc` tv cable.
# Args:
#   $1 = operation key (gcd, lcm, fib, ...)
#   $2 = arg template, space-separated arg names (e.g. "a b", "n", "matrix")
#
# Prompts for each arg via gum input, dispatches to a Python one-liner,
# and shows the result via gum style. Pauses for any key before exiting
# so the result stays visible after tv tears down.

set -u

op="${1:?missing op}"
template="${2:-}"

# Collect args. Special-cased templates ("expression", "matrix") get one
# free-form prompt; everything else is per-token.
declare -a args=()
case "$template" in
  ""|"expression")
    args+=("$(gum input --prompt "expr> " --placeholder "any python expression" --width 80)")
    ;;
  "matrix")
    args+=("$(gum input --prompt "matrix> " --placeholder "1 2, 3 4" --width 80)")
    ;;
  *)
    for name in $template; do
      case "$op:$name" in
        dsize:from_unit|dsize:to_unit)
          val="$(gum choose --header "${name}" \
            B KB MB GB TB \
            KiB MiB GiB TiB \
            bit Kbit Mbit Gbit Tbit \
            Kibit Mibit Gibit Tibit)"
          ;;
        *)
          val="$(gum input --prompt "${name}> " --width 40)"
          ;;
      esac
      args+=("$val")
    done
    ;;
esac

# Compute via embedded Python. Args are passed via argv to dodge quoting hell.
result=$(OP="$op" python3 - "${args[@]}" <<'PY'
import os, sys, math, statistics, fractions

op = os.environ["OP"]
a = sys.argv[1:]

def ipart(s):  # int parse
    return int(s, 0) if s.strip() else 0

def fpart(s):
    return float(s)

def gcd(x, y): return math.gcd(x, y)
def lcm(x, y): return abs(x*y)//math.gcd(x, y) if x and y else 0

def primefac(n):
    n = abs(n); out = {}
    d = 2
    while d*d <= n:
        while n % d == 0:
            out[d] = out.get(d, 0) + 1
            n //= d
        d += 1
    if n > 1: out[n] = out.get(n, 0) + 1
    return out

def divisors(n):
    n = abs(n); c = 0; i = 1
    while i*i <= n:
        if n % i == 0:
            c += 1 if i*i == n else 2
        i += 1
    return c

def perfect(n):
    if n <= 1: return False
    s = 1; i = 2
    while i*i <= n:
        if n % i == 0:
            s += i
            if i != n//i: s += n//i
        i += 1
    return s == n

def collatz_len(n):
    steps = 0
    while n != 1:
        n = n//2 if n % 2 == 0 else 3*n+1
        steps += 1
    return steps

def quad(a, b, c):
    d = b*b - 4*a*c
    if d < 0: return f"complex roots, discriminant={d}"
    r = math.sqrt(d)
    return ((-b + r)/(2*a), (-b - r)/(2*a))

def parse_matrix(s):
    return [[float(x) for x in row.split()] for row in s.split(",")]

def det(M):
    n = len(M)
    if any(len(r) != n for r in M):
        raise ValueError("matrix not square")
    M = [row[:] for row in M]
    sign = 1
    for i in range(n):
        pivot = i
        while pivot < n and M[pivot][i] == 0: pivot += 1
        if pivot == n: return 0
        if pivot != i:
            M[i], M[pivot] = M[pivot], M[i]
            sign = -sign
        for j in range(i+1, n):
            f = M[j][i]/M[i][i]
            for k in range(i, n):
                M[j][k] -= f*M[i][k]
    d = sign
    for i in range(n): d *= M[i][i]
    return d

# https://en.wikipedia.org/wiki/Probit#Approximation: Beasley-Springer-Moro is
# overkill here — statistics.NormalDist gives both directions cleanly.
def zpct(z): return statistics.NormalDist().cdf(z)
def pctz(p): return statistics.NormalDist().inv_cdf(p)

UNITS = {  # bytes per unit
    "B":1, "KB":1e3, "MB":1e6, "GB":1e9, "TB":1e12,
    "KIB":2**10, "MIB":2**20, "GIB":2**30, "TIB":2**40,
    "BIT":0.125, "KBIT":125, "MBIT":1.25e5, "GBIT":1.25e8, "TBIT":1.25e11,
    "KIBIT":2**10/8, "MIBIT":2**20/8, "GIBIT":2**30/8, "TIBIT":2**40/8,
}

def dsize(v, fr, to):
    return v * UNITS[fr.upper()] / UNITS[to.upper()]

try:
    if op == "gcd":      out = gcd(ipart(a[0]), ipart(a[1]))
    elif op == "lcm":    out = lcm(ipart(a[0]), ipart(a[1]))
    elif op == "fib":
        n = ipart(a[0])
        x, y = 0, 1
        for _ in range(n): x, y = y, x+y
        out = x
    elif op == "fact":   out = math.factorial(ipart(a[0]))
    elif op == "prime":
        n = ipart(a[0])
        out = "prime" if n >= 2 and all(n % d for d in range(2, int(math.isqrt(n))+1)) else "not prime"
    elif op == "factor":
        f = primefac(ipart(a[0]))
        out = " * ".join(f"{p}^{e}" if e > 1 else str(p) for p, e in sorted(f.items())) or "1"
    elif op == "divisors": out = divisors(ipart(a[0]))
    elif op == "perfect":  out = perfect(ipart(a[0]))
    elif op == "collatz":  out = f"{collatz_len(ipart(a[0]))} steps"
    elif op == "nCr":      out = math.comb(ipart(a[0]), ipart(a[1]))
    elif op == "nPr":      out = math.perm(ipart(a[0]), ipart(a[1]))
    elif op == "quad":     out = quad(fpart(a[0]), fpart(a[1]), fpart(a[2]))
    elif op == "disc":     b = fpart(a[1]); out = b*b - 4*fpart(a[0])*fpart(a[2])
    elif op == "zpct":     out = zpct(fpart(a[0]))
    elif op == "pctz":     out = pctz(fpart(a[0]))
    elif op == "base":
        n = int(a[0], int(a[1]))
        b = int(a[2])
        if b == 10: out = str(n)
        else:
            digits = "0123456789abcdefghijklmnopqrstuvwxyz"
            sign = "-" if n < 0 else ""; n = abs(n); s = ""
            if n == 0: s = "0"
            while n: s = digits[n % b] + s; n //= b
            out = sign + s
    elif op == "hex":
        n = ipart(a[0]); out = f"hex={hex(n)}  bin={bin(n)}  oct={oct(n)}"
    elif op == "f2c":  out = (fpart(a[0]) - 32) * 5/9
    elif op == "c2f":  out = fpart(a[0]) * 9/5 + 32
    elif op == "c2k":  out = fpart(a[0]) + 273.15
    elif op == "k2c":  out = fpart(a[0]) - 273.15
    elif op == "det":  out = det(parse_matrix(a[0]))
    elif op == "dsize": out = f"{dsize(fpart(a[0]), a[1], a[2])} {a[2]}"
    elif op == "expr":
        out = eval(a[0], {"__builtins__": {}},
                   {"math": math, "statistics": statistics, "fractions": fractions,
                    **{k: getattr(math, k) for k in dir(math) if not k.startswith("_")}})
    else:
        out = f"unknown op: {op}"
    print(out)
except Exception as e:
    print(f"error: {e}", file=sys.stderr)
    sys.exit(1)
PY
)
status=$?

clear
if [[ $status -eq 0 ]]; then
  gum style --border rounded --padding "1 2" --border-foreground 212 \
    "$op" "" "$result"
  gum style --faint "enter = copy to clipboard · any other key = dismiss"
  read -rsn1 key
  if [[ -z $key ]]; then
    printf '%s' "$result" | pbcopy && gum style --foreground 212 "copied"
    sleep 0.4
  fi
else
  gum style --border rounded --padding "1 2" --border-foreground 196 \
    "$op — error" "" "$result"
  gum style --faint "press any key to dismiss"
  read -rsn1
fi
