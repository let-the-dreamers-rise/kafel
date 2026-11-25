Three small independent fixes, one commit each, each with a test that fails on `master`. `make test`: 38/38.

**1. Identifiers may start with an underscore.** The syscall tables contain such names: arguments of `add_key`, `request_key` and others (`_type`, `_description`, `_payload`, `_callout_info`, `_fs_name`, `_key`, `_value`) on every architecture, and the syscalls `_llseek` and `_newselect` on m68k. The lexer only accepted `[A-Za-z][A-Za-z0-9_]*`, so `ERRNO(1) { add_key { _payload == 5 } }` failed with ``unexpected char `_'``.

**2. Octal numbers with the digits 8 or 9 are an error.** The rule for numbers with a leading zero accepts any decimal digit and `strtoull()` stops at the first one it cannot use, so `08` was 0 and `019` was 1:

```
ERRNO(1) { write { fd == 08 } } DEFAULT ALLOW
```

returned the error for fd 0 and let fd 8 through.

**3. Syscall numbers must fit in 32 bits.** `SYSCALL[n]` and constants used as syscall names are 64-bit numbers stored into an `int`:

```
ALLOW { SYSCALL[0x100000001] } DEFAULT KILL
```

allowed syscall 1. This is now a compile error. `SYSCALL[-1]` and other negative 32-bit numbers keep working.

Disclosure: I used an AI assistant (Claude) while finding and preparing these changes; I have reviewed and tested them and can answer for them.
