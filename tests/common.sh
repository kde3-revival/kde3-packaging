# Helpers for the tests of the KDE 3 packages, sourced by tests/<package>.sh.

fail() { echo "FAIL: $*" >&2; exit 1; }
step() { echo; echo "=== $*"; }

# ldd -r of a module (or a library meant for one program) reports the
# symbols it takes from the program that loads it.  Known ones:
#   kded modules: KDEDModule, from kded (LIB_KDED is empty on Linux);
#   libkscreensaver: kss_*, defined by each screen saver program.
known_undefined() {   # known_undefined <file>: filter stdin (demangled)
    case $1 in
        */lib/kde3/kded_*.so) grep -v '^\(vtable for \|typeinfo for \)\{0,1\}KDEDModule\b' ;;
        */lib/libkscreensaver.so.*) grep -v '^kss_' ;;
        *) cat ;;
    esac
}

check_elf() {   # check_elf <dir> <allowed RUNPATH dirs...>
    local dir=$1; shift
    local n=0 errors=0 f rp d r undef bad
    while IFS= read -r -d '' f; do
        head -c4 "$f" | grep -q $'\x7fELF' || continue
        n=$((n + 1))
        if ldd "$f" 2>/dev/null | grep -q 'not found'; then
            echo "$f has unresolved libraries:"; ldd "$f" | grep 'not found'
            errors=$((errors + 1))
        fi
        undef=$(ldd -r "$f" 2>&1 | sed -n 's/^undefined symbol: \([^ \t]*\).*/\1/p')
        if [[ -n $undef ]]; then
            bad=$(c++filt <<<"$undef" | known_undefined "$f" || true)
            if [[ -n $bad ]]; then
                echo "$f has undefined symbols:"; sed 's/^/    /' <<<"$bad"
                errors=$((errors + 1))
            fi
        fi
        rp=$(readelf -d "$f" | sed -n 's/.*(\(RPATH\|RUNPATH\)).*\[\(.*\)\]/\2/p')
        for d in ${rp//:/ }; do
            if [[ $d == '$ORIGIN'* ]]; then
                r=$(realpath -m "${d//\$ORIGIN/$(dirname "$f")}")
                [[ $r == "$dir"/* || $r == "$dir" ]] && continue
            elif [[ " $* " == *" $d "* ]]; then
                continue
            fi
            echo "$f has RUNPATH entry $d"
            errors=$((errors + 1))
        done
    done < <(find "$dir" -type f \( -name '*.so*' -o -perm -u+x \) -print0)
    echo "$n ELF files checked"
    [[ $errors == 0 ]] || fail "$errors problems in the ELF files"
}
