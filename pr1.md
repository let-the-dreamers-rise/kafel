Two fixes in `codegen.c`, one commit each, with tests. Both were found by comparing randomly generated policies against a small reference evaluator (details at the end), and both are reproduced on a real kernel (6.18, x86_64).

### 1. Instructions of an expression decided at compile time stay in the filter

The filter is generated back to front and starts with the instruction emitted last. Some expressions turn out to be constant only after instructions were emitted for a part of them:

- the high words of a 64-bit comparison differ at compile time, e.g. `(a & 1) == 0x100000001`, after the low word compare was emitted;
- the left side of `&&` / `||` is constant after the right side was emitted;
- a rule always matches, after the rules that follow it were emitted.

The result is then an older location and what was emitted since is unreachable, but it stays in the buffer. Normally that only wastes a few instructions. If nothing else is emitted afterwards (the whole policy boils down to the default action), the leftover is the beginning of the filter and runs instead of the architecture and syscall number checks:

```
ALLOW { SYSCALL[-1](a) { (a & 1) == 0x100000001 } } DEFAULT KILL
```

```
$ ./tools/dump_policy_bpf/dump_policy_bpf < policy
BPF program with 5 instructions
  0: A := arg 0 low
  1: A := A & 0x1
  2: if A == 0x1 goto 4
  3: KILL
  4: ALLOW
```

The condition can never hold, so this should be a plain `KILL`. Instead every syscall with an odd first argument is allowed, on every architecture. On a real kernel `getpid()` and `exit_group(7)` called with an odd first argument both go through this filter.

With several target architectures it is enough that the rules of *one* of them collapse. For `KAFEL_TARGET_ARCH_X86 | KAFEL_TARGET_ARCH_X86_64` and

```
ALLOW { getpid ON x86, write ON x86_64 { (fd & 0xff) == 0x100000001 } } DEFAULT KILL
```

the leftover sits right after the architecture load: x86_64 `execve(1, ...)` is allowed and x86 `getpid()` is killed.

I do not claim this is common: it needs a rule that is always false (or always true) in a way `expr_simplify` does not see. It is still a filter that contradicts its policy without any diagnostic, and the fix is small: drop the instructions (and the cached `RET` locations inside them) as soon as the result is known.

### 2. Negative constants never match 32-bit arguments the way callers pass them

Numbers are 64-bit, so `-1` is read as `0xffffffffffffffff`, and any number above `UINT32_MAX` makes the comparison 64-bit. With

```
KILL { kill { pid == -1 } } DEFAULT ALLOW
```

the rule only matches if all 64 bits of the register are set. The kernel reads the low 32 bits for `pid_t`, and a caller is free to zero-extend (`mov $-1, %edi`):

```
kill(0xffffffffffffffff, 0) -> SIGSYS
kill(0x00000000ffffffff, 0) -> 0        (kill(-1, 0) went through)
```

The other direction fails too. With `ERRNO(1) { openat { dfd != -100 } } DEFAULT ALLOW`, a plain glibc `openat(AT_FDCWD, "/dev/null", O_RDONLY)` gets `EPERM`, because glibc passes `0x00000000ffffff9c`.

The second commit treats negative 32-bit numbers (down to `INT32_MIN`) as fitting into 32 bits, so a comparison of 32-bit arguments with them looks at the low words only.

**What I deliberately left alone:** `32bit_args` documents that a 64-bit constant makes a comparison with a 32-bit argument check the whole register (`fd == 0x100001234`). That still holds and the test is unchanged. I added a case next to it (`fd == 0xffffffff7fffffff`) so the boundary is pinned down. The README now says how sizes and negative numbers are handled; please correct the wording if I misread your intent.

### Testing

- `make test`: 38/38 (35 existing + 3 new). The three new cases fail on `master` and pass here.
- Reference comparison: random policies (conditions over 64-bit and real 32-bit arguments, up to several hundred rules, nested `USE`, multiple architectures including big-endian with `ON` guards) are compiled and run through `test/runner/interpreter.c`; a ~100-line Python evaluator of the documented semantics (first matching rule wins, unsigned compare) computes the expected action. Numbers are in the first comment. I can contribute the generator under `tools/` or `test/` in a follow-up if you would like it.

### Not in this PR, for your judgement

- Comparing a 32-bit argument with a 64-bit one (`fd == count`) reads the upper half of the 32-bit argument's register, which the kernel ignores. Zero-extending would be the obvious fix, but it interacts with the `32bit_args` behaviour above, so I did not touch it.
- `umode_t` arguments (`mode` of `chmod`, `open`, ...) are 16-bit in the table but compared as 32-bit.

Disclosure: I used an AI assistant (Claude) while building the test generator and preparing this change. I have reviewed and tested everything here and can answer for it.
