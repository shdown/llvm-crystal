#!/bin/sh

select_binary() {
    local arg
    for arg; do
        [ -n "$arg" ] && command -v -- "$arg" && return
    done
    echo >&2 "E: found neither of: $*"
    return 1
}

llvm_config_cmd=$(select_binary \
    "$LLVM_CONFIG" \
    llvm-config-8 \
    llvm-config-7 \
    llvm-config-6.0 llvm-config60 \
    llvm-config-5.0 llvm-config50 \
    llvm-config-4.0 llvm-config40 \
    llvm-config
) || exit $?

join_lines() {
    tr '\n' ' '
}

cat <<__EOF__
@[Link(ldflags: "$($llvm_config_cmd --libs --system-libs --ldflags | join_lines)")]
@[Include(
    "llvm-c/Core.h",
    "llvm-c/BitReader.h",
    flags: "$($llvm_config_cmd --cflags | join_lines)",
    prefix: %w(LLVM_ LLVM)
)]
lib LibLLVM_C
end
__EOF__
