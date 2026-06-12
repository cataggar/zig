const builtin = @import("builtin");

comptime {
    if (builtin.target.isMuslLibC()) {
        switch (builtin.target.cpu.arch) {
            .x86_64 => if (builtin.target.abi == .muslx32) {
                asm (
                    \\.global __setjmp
                    \\.global _setjmp
                    \\.global setjmp
                    \\.type __setjmp,@function
                    \\.type _setjmp,@function
                    \\.type setjmp,@function
                    \\__setjmp:
                    \\_setjmp:
                    \\setjmp:
                    \\    mov %rbx,(%rdi)
                    \\    mov %rbp,8(%rdi)
                    \\    mov %r12,16(%rdi)
                    \\    mov %r13,24(%rdi)
                    \\    mov %r14,32(%rdi)
                    \\    mov %r15,40(%rdi)
                    \\    lea 8(%rsp),%rdx
                    \\    mov %rdx,48(%rdi)
                    \\    mov (%rsp),%rdx
                    \\    mov %rdx,56(%rdi)
                    \\    xor %eax,%eax
                    \\    ret
                    \\
                    \\.global _longjmp
                    \\.global longjmp
                    \\.type _longjmp,@function
                    \\.type longjmp,@function
                    \\_longjmp:
                    \\longjmp:
                    \\    xor %eax,%eax
                    \\    cmp $1,%esi
                    \\    adc %esi,%eax
                    \\    mov (%rdi),%rbx
                    \\    mov 8(%rdi),%rbp
                    \\    mov 16(%rdi),%r12
                    \\    mov 24(%rdi),%r13
                    \\    mov 32(%rdi),%r14
                    \\    mov 40(%rdi),%r15
                    \\    mov 48(%rdi),%rsp
                    \\    jmp *56(%rdi)
                    \\
                    \\.global sigsetjmp
                    \\.global __sigsetjmp
                    \\.type sigsetjmp,@function
                    \\.type __sigsetjmp,@function
                    \\sigsetjmp:
                    \\__sigsetjmp:
                    \\    test %esi,%esi
                    \\    jz 1f
                    \\    popq 64(%rdi)
                    \\    mov %rbx,72+8(%rdi)
                    \\    mov %rdi,%rbx
                    \\    call setjmp@PLT
                    \\    pushq 64(%rbx)
                    \\    movl $0, 4(%rsp)
                    \\    mov %rbx,%rdi
                    \\    mov %eax,%esi
                    \\    mov 72+8(%rbx),%rbx
                    \\.hidden __sigsetjmp_tail
                    \\    jmp __sigsetjmp_tail
                    \\1:  jmp setjmp@PLT
                );
            } else {
                asm (
                    \\.global __setjmp
                    \\.global _setjmp
                    \\.global setjmp
                    \\.type __setjmp,@function
                    \\.type _setjmp,@function
                    \\.type setjmp,@function
                    \\__setjmp:
                    \\_setjmp:
                    \\setjmp:
                    \\    mov %rbx,(%rdi)
                    \\    mov %rbp,8(%rdi)
                    \\    mov %r12,16(%rdi)
                    \\    mov %r13,24(%rdi)
                    \\    mov %r14,32(%rdi)
                    \\    mov %r15,40(%rdi)
                    \\    lea 8(%rsp),%rdx
                    \\    mov %rdx,48(%rdi)
                    \\    mov (%rsp),%rdx
                    \\    mov %rdx,56(%rdi)
                    \\    xor %eax,%eax
                    \\    ret
                    \\
                    \\.global _longjmp
                    \\.global longjmp
                    \\.type _longjmp,@function
                    \\.type longjmp,@function
                    \\_longjmp:
                    \\longjmp:
                    \\    xor %eax,%eax
                    \\    cmp $1,%esi
                    \\    adc %esi,%eax
                    \\    mov (%rdi),%rbx
                    \\    mov 8(%rdi),%rbp
                    \\    mov 16(%rdi),%r12
                    \\    mov 24(%rdi),%r13
                    \\    mov 32(%rdi),%r14
                    \\    mov 40(%rdi),%r15
                    \\    mov 48(%rdi),%rsp
                    \\    jmp *56(%rdi)
                    \\
                    \\.global sigsetjmp
                    \\.global __sigsetjmp
                    \\.type sigsetjmp,@function
                    \\.type __sigsetjmp,@function
                    \\sigsetjmp:
                    \\__sigsetjmp:
                    \\    test %esi,%esi
                    \\    jz 1f
                    \\    popq 64(%rdi)
                    \\    mov %rbx,72+8(%rdi)
                    \\    mov %rdi,%rbx
                    \\    call setjmp@PLT
                    \\    pushq 64(%rbx)
                    \\    mov %rbx,%rdi
                    \\    mov %eax,%esi
                    \\    mov 72+8(%rbx),%rbx
                    \\.hidden __sigsetjmp_tail
                    \\    jmp __sigsetjmp_tail
                    \\1:  jmp setjmp@PLT
                );
            },
            .x86 => asm (
                \\.global ___setjmp
                \\.hidden ___setjmp
                \\.global __setjmp
                \\.global _setjmp
                \\.global setjmp
                \\.type __setjmp,@function
                \\.type _setjmp,@function
                \\.type setjmp,@function
                \\___setjmp:
                \\__setjmp:
                \\_setjmp:
                \\setjmp:
                \\    mov 4(%esp), %eax
                \\    mov %ebx, (%eax)
                \\    mov %esi, 4(%eax)
                \\    mov %edi, 8(%eax)
                \\    mov %ebp, 12(%eax)
                \\    lea 4(%esp), %ecx
                \\    mov %ecx, 16(%eax)
                \\    mov (%esp), %ecx
                \\    mov %ecx, 20(%eax)
                \\    xor %eax, %eax
                \\    ret
                \\
                \\.global _longjmp
                \\.global longjmp
                \\.type _longjmp,@function
                \\.type longjmp,@function
                \\_longjmp:
                \\longjmp:
                \\    mov 4(%esp),%edx
                \\    mov 8(%esp),%eax
                \\    cmp $1,%eax
                \\    adc $0, %al
                \\    mov (%edx),%ebx
                \\    mov 4(%edx),%esi
                \\    mov 8(%edx),%edi
                \\    mov 12(%edx),%ebp
                \\    mov 16(%edx),%esp
                \\    jmp *20(%edx)
                \\
                \\.global sigsetjmp
                \\.global __sigsetjmp
                \\.type sigsetjmp,@function
                \\.type __sigsetjmp,@function
                \\sigsetjmp:
                \\__sigsetjmp:
                \\    mov 8(%esp),%ecx
                \\    jecxz 1f
                \\    mov 4(%esp),%eax
                \\    popl 24(%eax)
                \\    mov %ebx,28+8(%eax)
                \\    mov %eax,%ebx
                \\.hidden ___setjmp
                \\    call ___setjmp
                \\    pushl 24(%ebx)
                \\    mov %ebx,4(%esp)
                \\    mov %eax,8(%esp)
                \\    mov 28+8(%ebx),%ebx
                \\.hidden __sigsetjmp_tail
                \\    jmp __sigsetjmp_tail
                \\1:  jmp ___setjmp
            ),
            .aarch64, .aarch64_be => asm (
                \\.global __setjmp
                \\.global _setjmp
                \\.global setjmp
                \\.type __setjmp,%function
                \\.type _setjmp,%function
                \\.type setjmp,%function
                \\__setjmp:
                \\_setjmp:
                \\setjmp:
                \\    stp x19, x20, [x0,#0]
                \\    stp x21, x22, [x0,#16]
                \\    stp x23, x24, [x0,#32]
                \\    stp x25, x26, [x0,#48]
                \\    stp x27, x28, [x0,#64]
                \\    stp x29, x30, [x0,#80]
                \\    mov x2, sp
                \\    str x2, [x0,#104]
                \\    stp d8, d9, [x0,#112]
                \\    stp d10, d11, [x0,#128]
                \\    stp d12, d13, [x0,#144]
                \\    stp d14, d15, [x0,#160]
                \\    mov x0, #0
                \\    ret
                \\
                \\.global _longjmp
                \\.global longjmp
                \\.type _longjmp,%function
                \\.type longjmp,%function
                \\_longjmp:
                \\longjmp:
                \\    ldp x19, x20, [x0,#0]
                \\    ldp x21, x22, [x0,#16]
                \\    ldp x23, x24, [x0,#32]
                \\    ldp x25, x26, [x0,#48]
                \\    ldp x27, x28, [x0,#64]
                \\    ldp x29, x30, [x0,#80]
                \\    ldr x2, [x0,#104]
                \\    mov sp, x2
                \\    ldp d8, d9, [x0,#112]
                \\    ldp d10, d11, [x0,#128]
                \\    ldp d12, d13, [x0,#144]
                \\    ldp d14, d15, [x0,#160]
                \\    cmp w1, 0
                \\    csinc w0, w1, wzr, ne
                \\    br x30
                \\
                \\.global sigsetjmp
                \\.global __sigsetjmp
                \\.type sigsetjmp,%function
                \\.type __sigsetjmp,%function
                \\sigsetjmp:
                \\__sigsetjmp:
                \\    cbz x1,setjmp
                \\    str x30,[x0,#176]
                \\    str x19,[x0,#176+8+8]
                \\    mov x19,x0
                \\    bl setjmp
                \\    mov w1,w0
                \\    mov x0,x19
                \\    ldr x30,[x0,#176]
                \\    ldr x19,[x0,#176+8+8]
                \\.hidden __sigsetjmp_tail
                \\    b __sigsetjmp_tail
            ),
            else => {},
        }
    }
}
