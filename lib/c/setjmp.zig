const std = @import("std");
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
            .arm, .armeb, .thumb, .thumbeb => if (std.Target.arm.featureSetHasAny(builtin.cpu.features, .{
                .has_v8,
                .has_v8m,
                .has_v8m_main,
            })) asm (
                \\.syntax unified
                \\.global __setjmp
                \\.global _setjmp
                \\.global setjmp
                \\.type __setjmp,%function
                \\.type _setjmp,%function
                \\.type setjmp,%function
                \\__setjmp:
                \\_setjmp:
                \\setjmp:
                \\    mov ip,r0
                \\    stmia ip!,{v1,v2,v3,v4,v5,v6,sl,fp}
                \\    mov r2,sp
                \\    stmia ip!,{r2,lr}
                \\    mov r0,#0
                \\    adr r1,1f
                \\    ldr r2,1f
                \\    ldr r1,[r1,r2]
                \\2:  tst r1,#0x40
                \\    beq 2f
                \\    .fpu vfp
                \\    vstmia ip!, {d8-d15}
                \\    .fpu softvfp
                \\    .eabi_attribute 10, 0
                \\    .eabi_attribute 27, 0
                \\2:
                \\3:  bx lr
                \\.hidden __hwcap
                \\.align 2
                \\1:  .word __hwcap-1b
                \\
                \\.global _longjmp
                \\.global longjmp
                \\.type _longjmp,%function
                \\.type longjmp,%function
                \\_longjmp:
                \\longjmp:
                \\    mov ip,r0
                \\    mov r0,r1
                \\    cmp r0,#0
                \\    bne 4f
                \\    mov r0,#1
                \\4:
                \\    ldmia ip!, {v1,v2,v3,v4,v5,v6,sl,fp}
                \\    ldmia ip!, {r2,lr}
                \\    mov sp,r2
                \\    adr r1,1f
                \\    ldr r2,1f
                \\    ldr r1,[r1,r2]
                \\2:  tst r1,#0x40
                \\    beq 2f
                \\    .fpu vfp
                \\    vldmia ip!, {d8-d15}
                \\    .fpu softvfp
                \\    .eabi_attribute 10, 0
                \\    .eabi_attribute 27, 0
                \\2:
                \\3:  bx lr
                \\.hidden __hwcap
                \\.align 2
                \\1:  .word __hwcap-1b
                \\
                \\.global sigsetjmp
                \\.global __sigsetjmp
                \\.type sigsetjmp,%function
                \\.type __sigsetjmp,%function
                \\sigsetjmp:
                \\__sigsetjmp:
                \\    tst r1,r1
                \\    bne 1f
                \\    b setjmp
                \\1:  str lr,[r0,#256]
                \\    str r4,[r0,#260+8]
                \\    mov r4,r0
                \\    bl setjmp
                \\    mov r1,r0
                \\    mov r0,r4
                \\    ldr lr,[r0,#256]
                \\    ldr r4,[r0,#260+8]
                \\.hidden __sigsetjmp_tail
                \\    b __sigsetjmp_tail
            ) else asm (
                \\.syntax unified
                \\.global __setjmp
                \\.global _setjmp
                \\.global setjmp
                \\.type __setjmp,%function
                \\.type _setjmp,%function
                \\.type setjmp,%function
                \\__setjmp:
                \\_setjmp:
                \\setjmp:
                \\    mov ip,r0
                \\    stmia ip!,{v1,v2,v3,v4,v5,v6,sl,fp}
                \\    mov r2,sp
                \\    stmia ip!,{r2,lr}
                \\    mov r0,#0
                \\    adr r1,1f
                \\    ldr r2,1f
                \\    ldr r1,[r1,r2]
                \\    tst r1,#0x260
                \\    beq 3f
                \\    tst r1,#0x20
                \\    beq 2f
                \\    stc p2, cr4, [ip], #48
                \\2:  tst r1,#0x40
                \\    beq 2f
                \\    .fpu vfp
                \\    vstmia ip!, {d8-d15}
                \\    .fpu softvfp
                \\    .eabi_attribute 10, 0
                \\    .eabi_attribute 27, 0
                \\2:  tst r1,#0x200
                \\    beq 3f
                \\    stcl p1, cr10, [ip], #8
                \\    stcl p1, cr11, [ip], #8
                \\    stcl p1, cr12, [ip], #8
                \\    stcl p1, cr13, [ip], #8
                \\    stcl p1, cr14, [ip], #8
                \\    stcl p1, cr15, [ip], #8
                \\2:
                \\3:  bx lr
                \\.hidden __hwcap
                \\.align 2
                \\1:  .word __hwcap-1b
                \\
                \\.global _longjmp
                \\.global longjmp
                \\.type _longjmp,%function
                \\.type longjmp,%function
                \\_longjmp:
                \\longjmp:
                \\    mov ip,r0
                \\    mov r0,r1
                \\    cmp r0,#0
                \\    bne 4f
                \\    mov r0,#1
                \\4:
                \\    ldmia ip!, {v1,v2,v3,v4,v5,v6,sl,fp}
                \\    ldmia ip!, {r2,lr}
                \\    mov sp,r2
                \\    adr r1,1f
                \\    ldr r2,1f
                \\    ldr r1,[r1,r2]
                \\    tst r1,#0x260
                \\    beq 3f
                \\    tst r1,#0x20
                \\    beq 2f
                \\    ldc p2, cr4, [ip], #48
                \\2:  tst r1,#0x40
                \\    beq 2f
                \\    .fpu vfp
                \\    vldmia ip!, {d8-d15}
                \\    .fpu softvfp
                \\    .eabi_attribute 10, 0
                \\    .eabi_attribute 27, 0
                \\2:  tst r1,#0x200
                \\    beq 3f
                \\    ldcl p1, cr10, [ip], #8
                \\    ldcl p1, cr11, [ip], #8
                \\    ldcl p1, cr12, [ip], #8
                \\    ldcl p1, cr13, [ip], #8
                \\    ldcl p1, cr14, [ip], #8
                \\    ldcl p1, cr15, [ip], #8
                \\2:
                \\3:  bx lr
                \\.hidden __hwcap
                \\.align 2
                \\1:  .word __hwcap-1b
                \\
                \\.global sigsetjmp
                \\.global __sigsetjmp
                \\.type sigsetjmp,%function
                \\.type __sigsetjmp,%function
                \\sigsetjmp:
                \\__sigsetjmp:
                \\    tst r1,r1
                \\    bne 1f
                \\    b setjmp
                \\1:  str lr,[r0,#256]
                \\    str r4,[r0,#260+8]
                \\    mov r4,r0
                \\    bl setjmp
                \\    mov r1,r0
                \\    mov r0,r4
                \\    ldr lr,[r0,#256]
                \\    ldr r4,[r0,#260+8]
                \\.hidden __sigsetjmp_tail
                \\    b __sigsetjmp_tail
            ),
            .riscv32 => if (std.Target.riscv.featureSetHas(builtin.cpu.features, .d)) asm (
                \\.global __setjmp
                \\.global _setjmp
                \\.global setjmp
                \\.type __setjmp, %function
                \\.type _setjmp,  %function
                \\.type setjmp,   %function
                \\__setjmp:
                \\_setjmp:
                \\setjmp:
                \\    sw s0,    0(a0)
                \\    sw s1,    4(a0)
                \\    sw s2,    8(a0)
                \\    sw s3,    12(a0)
                \\    sw s4,    16(a0)
                \\    sw s5,    20(a0)
                \\    sw s6,    24(a0)
                \\    sw s7,    28(a0)
                \\    sw s8,    32(a0)
                \\    sw s9,    36(a0)
                \\    sw s10,   40(a0)
                \\    sw s11,   44(a0)
                \\    sw sp,    48(a0)
                \\    sw ra,    52(a0)
                \\    fsd fs0,  56(a0)
                \\    fsd fs1,  64(a0)
                \\    fsd fs2,  72(a0)
                \\    fsd fs3,  80(a0)
                \\    fsd fs4,  88(a0)
                \\    fsd fs5,  96(a0)
                \\    fsd fs6,  104(a0)
                \\    fsd fs7,  112(a0)
                \\    fsd fs8,  120(a0)
                \\    fsd fs9,  128(a0)
                \\    fsd fs10, 136(a0)
                \\    fsd fs11, 144(a0)
                \\    li a0, 0
                \\    ret
                \\
                \\.global __longjmp
                \\.global _longjmp
                \\.global longjmp
                \\.type __longjmp, %function
                \\.type _longjmp,  %function
                \\.type longjmp,   %function
                \\__longjmp:
                \\_longjmp:
                \\longjmp:
                \\    lw s0,    0(a0)
                \\    lw s1,    4(a0)
                \\    lw s2,    8(a0)
                \\    lw s3,    12(a0)
                \\    lw s4,    16(a0)
                \\    lw s5,    20(a0)
                \\    lw s6,    24(a0)
                \\    lw s7,    28(a0)
                \\    lw s8,    32(a0)
                \\    lw s9,    36(a0)
                \\    lw s10,   40(a0)
                \\    lw s11,   44(a0)
                \\    lw sp,    48(a0)
                \\    lw ra,    52(a0)
                \\    fld fs0,  56(a0)
                \\    fld fs1,  64(a0)
                \\    fld fs2,  72(a0)
                \\    fld fs3,  80(a0)
                \\    fld fs4,  88(a0)
                \\    fld fs5,  96(a0)
                \\    fld fs6,  104(a0)
                \\    fld fs7,  112(a0)
                \\    fld fs8,  120(a0)
                \\    fld fs9,  128(a0)
                \\    fld fs10, 136(a0)
                \\    fld fs11, 144(a0)
                \\    seqz a0, a1
                \\    add a0, a0, a1
                \\    ret
                \\
                \\.global sigsetjmp
                \\.global __sigsetjmp
                \\.type sigsetjmp, %function
                \\.type __sigsetjmp, %function
                \\sigsetjmp:
                \\__sigsetjmp:
                \\    bnez a1, 1f
                \\    tail setjmp
                \\1:
                \\    sw ra, 152(a0)
                \\    sw s0, 164(a0)
                \\    mv s0, a0
                \\    call setjmp
                \\    mv a1, a0
                \\    mv a0, s0
                \\    lw s0, 164(a0)
                \\    lw ra, 152(a0)
                \\.hidden __sigsetjmp_tail
                \\    tail __sigsetjmp_tail
            ) else asm (
                \\.global __setjmp
                \\.global _setjmp
                \\.global setjmp
                \\.type __setjmp, %function
                \\.type _setjmp,  %function
                \\.type setjmp,   %function
                \\__setjmp:
                \\_setjmp:
                \\setjmp:
                \\    sw s0,    0(a0)
                \\    sw s1,    4(a0)
                \\    sw s2,    8(a0)
                \\    sw s3,    12(a0)
                \\    sw s4,    16(a0)
                \\    sw s5,    20(a0)
                \\    sw s6,    24(a0)
                \\    sw s7,    28(a0)
                \\    sw s8,    32(a0)
                \\    sw s9,    36(a0)
                \\    sw s10,   40(a0)
                \\    sw s11,   44(a0)
                \\    sw sp,    48(a0)
                \\    sw ra,    52(a0)
                \\    li a0, 0
                \\    ret
                \\
                \\.global __longjmp
                \\.global _longjmp
                \\.global longjmp
                \\.type __longjmp, %function
                \\.type _longjmp,  %function
                \\.type longjmp,   %function
                \\__longjmp:
                \\_longjmp:
                \\longjmp:
                \\    lw s0,    0(a0)
                \\    lw s1,    4(a0)
                \\    lw s2,    8(a0)
                \\    lw s3,    12(a0)
                \\    lw s4,    16(a0)
                \\    lw s5,    20(a0)
                \\    lw s6,    24(a0)
                \\    lw s7,    28(a0)
                \\    lw s8,    32(a0)
                \\    lw s9,    36(a0)
                \\    lw s10,   40(a0)
                \\    lw s11,   44(a0)
                \\    lw sp,    48(a0)
                \\    lw ra,    52(a0)
                \\    seqz a0, a1
                \\    add a0, a0, a1
                \\    ret
                \\
                \\.global sigsetjmp
                \\.global __sigsetjmp
                \\.type sigsetjmp, %function
                \\.type __sigsetjmp, %function
                \\sigsetjmp:
                \\__sigsetjmp:
                \\    bnez a1, 1f
                \\    tail setjmp
                \\1:
                \\    sw ra, 152(a0)
                \\    sw s0, 164(a0)
                \\    mv s0, a0
                \\    call setjmp
                \\    mv a1, a0
                \\    mv a0, s0
                \\    lw s0, 164(a0)
                \\    lw ra, 152(a0)
                \\.hidden __sigsetjmp_tail
                \\    tail __sigsetjmp_tail
            ),
            .riscv64 => if (std.Target.riscv.featureSetHas(builtin.cpu.features, .d)) asm (
                \\.global __setjmp
                \\.global _setjmp
                \\.global setjmp
                \\.type __setjmp, %function
                \\.type _setjmp,  %function
                \\.type setjmp,   %function
                \\__setjmp:
                \\_setjmp:
                \\setjmp:
                \\    sd s0,    0(a0)
                \\    sd s1,    8(a0)
                \\    sd s2,    16(a0)
                \\    sd s3,    24(a0)
                \\    sd s4,    32(a0)
                \\    sd s5,    40(a0)
                \\    sd s6,    48(a0)
                \\    sd s7,    56(a0)
                \\    sd s8,    64(a0)
                \\    sd s9,    72(a0)
                \\    sd s10,   80(a0)
                \\    sd s11,   88(a0)
                \\    sd sp,    96(a0)
                \\    sd ra,    104(a0)
                \\    fsd fs0,  112(a0)
                \\    fsd fs1,  120(a0)
                \\    fsd fs2,  128(a0)
                \\    fsd fs3,  136(a0)
                \\    fsd fs4,  144(a0)
                \\    fsd fs5,  152(a0)
                \\    fsd fs6,  160(a0)
                \\    fsd fs7,  168(a0)
                \\    fsd fs8,  176(a0)
                \\    fsd fs9,  184(a0)
                \\    fsd fs10, 192(a0)
                \\    fsd fs11, 200(a0)
                \\    li a0, 0
                \\    ret
                \\
                \\.global __longjmp
                \\.global _longjmp
                \\.global longjmp
                \\.type __longjmp, %function
                \\.type _longjmp,  %function
                \\.type longjmp,   %function
                \\__longjmp:
                \\_longjmp:
                \\longjmp:
                \\    ld s0,    0(a0)
                \\    ld s1,    8(a0)
                \\    ld s2,    16(a0)
                \\    ld s3,    24(a0)
                \\    ld s4,    32(a0)
                \\    ld s5,    40(a0)
                \\    ld s6,    48(a0)
                \\    ld s7,    56(a0)
                \\    ld s8,    64(a0)
                \\    ld s9,    72(a0)
                \\    ld s10,   80(a0)
                \\    ld s11,   88(a0)
                \\    ld sp,    96(a0)
                \\    ld ra,    104(a0)
                \\    fld fs0,  112(a0)
                \\    fld fs1,  120(a0)
                \\    fld fs2,  128(a0)
                \\    fld fs3,  136(a0)
                \\    fld fs4,  144(a0)
                \\    fld fs5,  152(a0)
                \\    fld fs6,  160(a0)
                \\    fld fs7,  168(a0)
                \\    fld fs8,  176(a0)
                \\    fld fs9,  184(a0)
                \\    fld fs10, 192(a0)
                \\    fld fs11, 200(a0)
                \\    seqz a0, a1
                \\    add a0, a0, a1
                \\    ret
                \\
                \\.global sigsetjmp
                \\.global __sigsetjmp
                \\.type sigsetjmp, %function
                \\.type __sigsetjmp, %function
                \\sigsetjmp:
                \\__sigsetjmp:
                \\    bnez a1, 1f
                \\    tail setjmp
                \\1:
                \\    sd ra, 208(a0)
                \\    sd s0, 224(a0)
                \\    mv s0, a0
                \\    call setjmp
                \\    mv a1, a0
                \\    mv a0, s0
                \\    ld s0, 224(a0)
                \\    ld ra, 208(a0)
                \\.hidden __sigsetjmp_tail
                \\    tail __sigsetjmp_tail
            ) else asm (
                \\.global __setjmp
                \\.global _setjmp
                \\.global setjmp
                \\.type __setjmp, %function
                \\.type _setjmp,  %function
                \\.type setjmp,   %function
                \\__setjmp:
                \\_setjmp:
                \\setjmp:
                \\    sd s0,    0(a0)
                \\    sd s1,    8(a0)
                \\    sd s2,    16(a0)
                \\    sd s3,    24(a0)
                \\    sd s4,    32(a0)
                \\    sd s5,    40(a0)
                \\    sd s6,    48(a0)
                \\    sd s7,    56(a0)
                \\    sd s8,    64(a0)
                \\    sd s9,    72(a0)
                \\    sd s10,   80(a0)
                \\    sd s11,   88(a0)
                \\    sd sp,    96(a0)
                \\    sd ra,    104(a0)
                \\    li a0, 0
                \\    ret
                \\
                \\.global __longjmp
                \\.global _longjmp
                \\.global longjmp
                \\.type __longjmp, %function
                \\.type _longjmp,  %function
                \\.type longjmp,   %function
                \\__longjmp:
                \\_longjmp:
                \\longjmp:
                \\    ld s0,    0(a0)
                \\    ld s1,    8(a0)
                \\    ld s2,    16(a0)
                \\    ld s3,    24(a0)
                \\    ld s4,    32(a0)
                \\    ld s5,    40(a0)
                \\    ld s6,    48(a0)
                \\    ld s7,    56(a0)
                \\    ld s8,    64(a0)
                \\    ld s9,    72(a0)
                \\    ld s10,   80(a0)
                \\    ld s11,   88(a0)
                \\    ld sp,    96(a0)
                \\    ld ra,    104(a0)
                \\    seqz a0, a1
                \\    add a0, a0, a1
                \\    ret
                \\
                \\.global sigsetjmp
                \\.global __sigsetjmp
                \\.type sigsetjmp, %function
                \\.type __sigsetjmp, %function
                \\sigsetjmp:
                \\__sigsetjmp:
                \\    bnez a1, 1f
                \\    tail setjmp
                \\1:
                \\    sd ra, 208(a0)
                \\    sd s0, 224(a0)
                \\    mv s0, a0
                \\    call setjmp
                \\    mv a1, a0
                \\    mv a0, s0
                \\    ld s0, 224(a0)
                \\    ld ra, 208(a0)
                \\.hidden __sigsetjmp_tail
                \\    tail __sigsetjmp_tail
            ),
            .powerpc, .powerpcle => if (switch (builtin.abi) {
                .eabi, .gnueabi, .musleabi => true,
                else => false,
            }) asm (
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
                \\    mflr 0
                \\    stw 0, 0(3)
                \\    stw 1, 4(3)
                \\    mfcr 0
                \\    stw 0, 8(3)
                \\    stw 14, 12(3)
                \\    stw 15, 16(3)
                \\    stw 16, 20(3)
                \\    stw 17, 24(3)
                \\    stw 18, 28(3)
                \\    stw 19, 32(3)
                \\    stw 20, 36(3)
                \\    stw 21, 40(3)
                \\    stw 22, 44(3)
                \\    stw 23, 48(3)
                \\    stw 24, 52(3)
                \\    stw 25, 56(3)
                \\    stw 26, 60(3)
                \\    stw 27, 64(3)
                \\    stw 28, 68(3)
                \\    stw 29, 72(3)
                \\    stw 30, 76(3)
                \\    stw 31, 80(3)
                \\    mflr 0
                \\    bl 1f
                \\.hidden __hwcap
                \\    .long __hwcap-.
                \\1:  mflr 4
                \\    lwz 5, 0(4)
                \\    lwzx 4, 4, 5
                \\    andis. 4, 4, 0x80
                \\    beq 1f
                \\    .long 0x11c35b21
                \\    .long 0x11e36321
                \\    .long 0x12036b21
                \\    .long 0x12237321
                \\    .long 0x12437b21
                \\    .long 0x12638321
                \\    .long 0x12838b21
                \\    .long 0x12a39321
                \\    .long 0x12c39b21
                \\    .long 0x12e3a321
                \\    .long 0x1303ab21
                \\    .long 0x1323b321
                \\    .long 0x1343bb21
                \\    .long 0x1363c321
                \\    .long 0x1383cb21
                \\    .long 0x13a3d321
                \\    .long 0x13c3db21
                \\    .long 0x13e3e321
                \\    .long 0x11a3eb21
                \\1:  mtlr 0
                \\    li 3, 0
                \\    blr
                \\
                \\.global _longjmp
                \\.global longjmp
                \\.type _longjmp,@function
                \\.type longjmp,@function
                \\_longjmp:
                \\longjmp:
                \\    lwz 0, 0(3)
                \\    mtlr 0
                \\    lwz 1, 4(3)
                \\    lwz 0, 8(3)
                \\    mtcr 0
                \\    lwz 14, 12(3)
                \\    lwz 15, 16(3)
                \\    lwz 16, 20(3)
                \\    lwz 17, 24(3)
                \\    lwz 18, 28(3)
                \\    lwz 19, 32(3)
                \\    lwz 20, 36(3)
                \\    lwz 21, 40(3)
                \\    lwz 22, 44(3)
                \\    lwz 23, 48(3)
                \\    lwz 24, 52(3)
                \\    lwz 25, 56(3)
                \\    lwz 26, 60(3)
                \\    lwz 27, 64(3)
                \\    lwz 28, 68(3)
                \\    lwz 29, 72(3)
                \\    lwz 30, 76(3)
                \\    lwz 31, 80(3)
                \\    mflr 0
                \\    bl 1f
                \\.hidden __hwcap
                \\    .long __hwcap-.
                \\1:  mflr 6
                \\    lwz 5, 0(6)
                \\    lwzx 6, 6, 5
                \\    andis. 6, 6, 0x80
                \\    beq 1f
                \\    .long 0x11c35b01
                \\    .long 0x11e36301
                \\    .long 0x12036b01
                \\    .long 0x12237301
                \\    .long 0x12437b01
                \\    .long 0x12638301
                \\    .long 0x12838b01
                \\    .long 0x12a39301
                \\    .long 0x12c39b01
                \\    .long 0x12e3a301
                \\    .long 0x1303ab01
                \\    .long 0x1323b301
                \\    .long 0x1343bb01
                \\    .long 0x1363c301
                \\    .long 0x1383cb01
                \\    .long 0x13a3d301
                \\    .long 0x13c3db01
                \\    .long 0x13e3e301
                \\    .long 0x11a3eb01
                \\1:  mtlr 0
                \\    mr 3, 4
                \\    cmpwi cr7, 4, 0
                \\    bne cr7, 1f
                \\    li 3, 1
                \\1:  blr
                \\
                \\.global sigsetjmp
                \\.global __sigsetjmp
                \\.type sigsetjmp,%function
                \\.type __sigsetjmp,%function
                \\sigsetjmp:
                \\__sigsetjmp:
                \\    cmpwi cr7, 4, 0
                \\    beq- cr7, 1f
                \\    mflr 5
                \\    stw 5, 448(3)
                \\    stw 16, 448+4+8(3)
                \\    mr 16, 3
                \\.hidden ___setjmp
                \\    bl ___setjmp
                \\    mr 4, 3
                \\    mr 3, 16
                \\    lwz 5, 448(3)
                \\    mtlr 5
                \\    lwz 16, 448+4+8(3)
                \\.hidden __sigsetjmp_tail
                \\    b __sigsetjmp_tail
                \\1:  b ___setjmp
            ) else asm (
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
                \\    mflr 0
                \\    stw 0, 0(3)
                \\    stw 1, 4(3)
                \\    mfcr 0
                \\    stw 0, 8(3)
                \\    stw 14, 12(3)
                \\    stw 15, 16(3)
                \\    stw 16, 20(3)
                \\    stw 17, 24(3)
                \\    stw 18, 28(3)
                \\    stw 19, 32(3)
                \\    stw 20, 36(3)
                \\    stw 21, 40(3)
                \\    stw 22, 44(3)
                \\    stw 23, 48(3)
                \\    stw 24, 52(3)
                \\    stw 25, 56(3)
                \\    stw 26, 60(3)
                \\    stw 27, 64(3)
                \\    stw 28, 68(3)
                \\    stw 29, 72(3)
                \\    stw 30, 76(3)
                \\    stw 31, 80(3)
                \\    stfd 14,88(3)
                \\    stfd 15,96(3)
                \\    stfd 16,104(3)
                \\    stfd 17,112(3)
                \\    stfd 18,120(3)
                \\    stfd 19,128(3)
                \\    stfd 20,136(3)
                \\    stfd 21,144(3)
                \\    stfd 22,152(3)
                \\    stfd 23,160(3)
                \\    stfd 24,168(3)
                \\    stfd 25,176(3)
                \\    stfd 26,184(3)
                \\    stfd 27,192(3)
                \\    stfd 28,200(3)
                \\    stfd 29,208(3)
                \\    stfd 30,216(3)
                \\    stfd 31,224(3)
                \\    li 3, 0
                \\    blr
                \\
                \\.global _longjmp
                \\.global longjmp
                \\.type _longjmp,@function
                \\.type longjmp,@function
                \\_longjmp:
                \\longjmp:
                \\    lwz 0, 0(3)
                \\    mtlr 0
                \\    lwz 1, 4(3)
                \\    lwz 0, 8(3)
                \\    mtcr 0
                \\    lwz 14, 12(3)
                \\    lwz 15, 16(3)
                \\    lwz 16, 20(3)
                \\    lwz 17, 24(3)
                \\    lwz 18, 28(3)
                \\    lwz 19, 32(3)
                \\    lwz 20, 36(3)
                \\    lwz 21, 40(3)
                \\    lwz 22, 44(3)
                \\    lwz 23, 48(3)
                \\    lwz 24, 52(3)
                \\    lwz 25, 56(3)
                \\    lwz 26, 60(3)
                \\    lwz 27, 64(3)
                \\    lwz 28, 68(3)
                \\    lwz 29, 72(3)
                \\    lwz 30, 76(3)
                \\    lwz 31, 80(3)
                \\    lfd 14,88(3)
                \\    lfd 15,96(3)
                \\    lfd 16,104(3)
                \\    lfd 17,112(3)
                \\    lfd 18,120(3)
                \\    lfd 19,128(3)
                \\    lfd 20,136(3)
                \\    lfd 21,144(3)
                \\    lfd 22,152(3)
                \\    lfd 23,160(3)
                \\    lfd 24,168(3)
                \\    lfd 25,176(3)
                \\    lfd 26,184(3)
                \\    lfd 27,192(3)
                \\    lfd 28,200(3)
                \\    lfd 29,208(3)
                \\    lfd 30,216(3)
                \\    lfd 31,224(3)
                \\    mr 3, 4
                \\    cmpwi cr7, 4, 0
                \\    bne cr7, 1f
                \\    li 3, 1
                \\1:  blr
                \\
                \\.global sigsetjmp
                \\.global __sigsetjmp
                \\.type sigsetjmp,%function
                \\.type __sigsetjmp,%function
                \\sigsetjmp:
                \\__sigsetjmp:
                \\    cmpwi cr7, 4, 0
                \\    beq- cr7, 1f
                \\    mflr 5
                \\    stw 5, 448(3)
                \\    stw 16, 448+4+8(3)
                \\    mr 16, 3
                \\.hidden ___setjmp
                \\    bl ___setjmp
                \\    mr 4, 3
                \\    mr 3, 16
                \\    lwz 5, 448(3)
                \\    mtlr 5
                \\    lwz 16, 448+4+8(3)
                \\.hidden __sigsetjmp_tail
                \\    b __sigsetjmp_tail
                \\1:  b ___setjmp
            ),
            .powerpc64, .powerpc64le => asm (
                \\.global __setjmp
                \\.global _setjmp
                \\.global setjmp
                \\.type __setjmp,@function
                \\.type _setjmp,@function
                \\.type setjmp,@function
                \\__setjmp:
                \\_setjmp:
                \\setjmp:
                \\    ld 5, 24(1)
                \\    b __setjmp_toc
                \\.localentry __setjmp,.-__setjmp
                \\.localentry _setjmp,.-_setjmp
                \\.localentry setjmp,.-setjmp
                \\    mr 5, 2
                \\.global __setjmp_toc
                \\.hidden __setjmp_toc
                \\__setjmp_toc:
                \\    mflr 0
                \\    std 0, 0*8(3)
                \\    mfcr 0
                \\    std 0, 1*8(3)
                \\    std 1, 2*8(3)
                \\    std 5, 3*8(3)
                \\    std 14, 4*8(3)
                \\    std 15, 5*8(3)
                \\    std 16, 6*8(3)
                \\    std 17, 7*8(3)
                \\    std 18, 8*8(3)
                \\    std 19, 9*8(3)
                \\    std 20, 10*8(3)
                \\    std 21, 11*8(3)
                \\    std 22, 12*8(3)
                \\    std 23, 13*8(3)
                \\    std 24, 14*8(3)
                \\    std 25, 15*8(3)
                \\    std 26, 16*8(3)
                \\    std 27, 17*8(3)
                \\    std 28, 18*8(3)
                \\    std 29, 19*8(3)
                \\    std 30, 20*8(3)
                \\    std 31, 21*8(3)
                \\    stfd 14, 22*8(3)
                \\    stfd 15, 23*8(3)
                \\    stfd 16, 24*8(3)
                \\    stfd 17, 25*8(3)
                \\    stfd 18, 26*8(3)
                \\    stfd 19, 27*8(3)
                \\    stfd 20, 28*8(3)
                \\    stfd 21, 29*8(3)
                \\    stfd 22, 30*8(3)
                \\    stfd 23, 31*8(3)
                \\    stfd 24, 32*8(3)
                \\    stfd 25, 33*8(3)
                \\    stfd 26, 34*8(3)
                \\    stfd 27, 35*8(3)
                \\    stfd 28, 36*8(3)
                \\    stfd 29, 37*8(3)
                \\    stfd 30, 38*8(3)
                \\    stfd 31, 39*8(3)
                \\    addi 3, 3, 40*8
                \\    stvx 20, 0, 3 ; addi 3, 3, 16
                \\    stvx 21, 0, 3 ; addi 3, 3, 16
                \\    stvx 22, 0, 3 ; addi 3, 3, 16
                \\    stvx 23, 0, 3 ; addi 3, 3, 16
                \\    stvx 24, 0, 3 ; addi 3, 3, 16
                \\    stvx 25, 0, 3 ; addi 3, 3, 16
                \\    stvx 26, 0, 3 ; addi 3, 3, 16
                \\    stvx 27, 0, 3 ; addi 3, 3, 16
                \\    stvx 28, 0, 3 ; addi 3, 3, 16
                \\    stvx 29, 0, 3 ; addi 3, 3, 16
                \\    stvx 30, 0, 3 ; addi 3, 3, 16
                \\    stvx 31, 0, 3
                \\    li 3, 0
                \\    blr
                \\
                \\.global _longjmp
                \\.global longjmp
                \\.type _longjmp,@function
                \\.type longjmp,@function
                \\_longjmp:
                \\longjmp:
                \\    ld 0, 0*8(3)
                \\    mtlr 0
                \\    ld 0, 1*8(3)
                \\    mtcr 0
                \\    ld 1, 2*8(3)
                \\    ld 2, 3*8(3)
                \\    std 2, 24(1)
                \\    ld 14, 4*8(3)
                \\    ld 15, 5*8(3)
                \\    ld 16, 6*8(3)
                \\    ld 17, 7*8(3)
                \\    ld 18, 8*8(3)
                \\    ld 19, 9*8(3)
                \\    ld 20, 10*8(3)
                \\    ld 21, 11*8(3)
                \\    ld 22, 12*8(3)
                \\    ld 23, 13*8(3)
                \\    ld 24, 14*8(3)
                \\    ld 25, 15*8(3)
                \\    ld 26, 16*8(3)
                \\    ld 27, 17*8(3)
                \\    ld 28, 18*8(3)
                \\    ld 29, 19*8(3)
                \\    ld 30, 20*8(3)
                \\    ld 31, 21*8(3)
                \\    lfd 14, 22*8(3)
                \\    lfd 15, 23*8(3)
                \\    lfd 16, 24*8(3)
                \\    lfd 17, 25*8(3)
                \\    lfd 18, 26*8(3)
                \\    lfd 19, 27*8(3)
                \\    lfd 20, 28*8(3)
                \\    lfd 21, 29*8(3)
                \\    lfd 22, 30*8(3)
                \\    lfd 23, 31*8(3)
                \\    lfd 24, 32*8(3)
                \\    lfd 25, 33*8(3)
                \\    lfd 26, 34*8(3)
                \\    lfd 27, 35*8(3)
                \\    lfd 28, 36*8(3)
                \\    lfd 29, 37*8(3)
                \\    lfd 30, 38*8(3)
                \\    lfd 31, 39*8(3)
                \\    addi 3, 3, 40*8
                \\    lvx 20, 0, 3 ; addi 3, 3, 16
                \\    lvx 21, 0, 3 ; addi 3, 3, 16
                \\    lvx 22, 0, 3 ; addi 3, 3, 16
                \\    lvx 23, 0, 3 ; addi 3, 3, 16
                \\    lvx 24, 0, 3 ; addi 3, 3, 16
                \\    lvx 25, 0, 3 ; addi 3, 3, 16
                \\    lvx 26, 0, 3 ; addi 3, 3, 16
                \\    lvx 27, 0, 3 ; addi 3, 3, 16
                \\    lvx 28, 0, 3 ; addi 3, 3, 16
                \\    lvx 29, 0, 3 ; addi 3, 3, 16
                \\    lvx 30, 0, 3 ; addi 3, 3, 16
                \\    lvx 31, 0, 3
                \\    mr 3, 4
                \\    cmpwi cr7, 4, 0
                \\    bne cr7, 1f
                \\    li 3, 1
                \\1:  blr
                \\
                \\.global sigsetjmp
                \\.global __sigsetjmp
                \\.type sigsetjmp,%function
                \\.type __sigsetjmp,%function
                \\.hidden __setjmp_toc
                \\sigsetjmp:
                \\__sigsetjmp:
                \\    addis 2, 12, .TOC.-__sigsetjmp@ha
                \\    addi 2, 2, .TOC.-__sigsetjmp@l
                \\    ld 5, 24(1)
                \\    b 1f
                \\.localentry sigsetjmp,.-sigsetjmp
                \\.localentry __sigsetjmp,.-__sigsetjmp
                \\    mr 5, 2
                \\1:
                \\    cmpwi cr7, 4, 0
                \\    beq- cr7, __setjmp_toc
                \\    mflr 6
                \\    std 6, 512(3)
                \\    std 2, 512+16(3)
                \\    std 16, 512+24(3)
                \\    mr 16, 3
                \\    bl __setjmp_toc
                \\    mr 4, 3
                \\    mr 3, 16
                \\    ld 5, 512(3)
                \\    mtlr 5
                \\    ld 2, 512+16(3)
                \\    ld 16, 512+24(3)
                \\.hidden __sigsetjmp_tail
                \\    b __sigsetjmp_tail
            ),
            .s390x => asm (
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
                \\    stmg %r6, %r15, 0(%r2)
                \\    std %f8, 10*8(%r2)
                \\    std %f9, 11*8(%r2)
                \\    std %f10, 12*8(%r2)
                \\    std %f11, 13*8(%r2)
                \\    std %f12, 14*8(%r2)
                \\    std %f13, 15*8(%r2)
                \\    std %f14, 16*8(%r2)
                \\    std %f15, 17*8(%r2)
                \\    lghi %r2, 0
                \\    br %r14
                \\
                \\.global _longjmp
                \\.global longjmp
                \\.type _longjmp,@function
                \\.type longjmp,@function
                \\_longjmp:
                \\longjmp:
                \\    lmg %r6, %r15, 0(%r2)
                \\    ld %f8, 10*8(%r2)
                \\    ld %f9, 11*8(%r2)
                \\    ld %f10, 12*8(%r2)
                \\    ld %f11, 13*8(%r2)
                \\    ld %f12, 14*8(%r2)
                \\    ld %f13, 15*8(%r2)
                \\    ld %f14, 16*8(%r2)
                \\    ld %f15, 17*8(%r2)
                \\    ltgr %r2, %r3
                \\    bnzr %r14
                \\    lhi %r2, 1
                \\    br %r14
                \\
                \\.global sigsetjmp
                \\.global __sigsetjmp
                \\.type sigsetjmp,%function
                \\.type __sigsetjmp,%function
                \\.hidden ___setjmp
                \\sigsetjmp:
                \\__sigsetjmp:
                \\    ltgr %r3, %r3
                \\    jz ___setjmp
                \\    stg %r14, 18*8(%r2)
                \\    stg %r6, 20*8(%r2)
                \\    lgr %r6, %r2
                \\    brasl %r14, ___setjmp
                \\    lgr %r3, %r2
                \\    lgr %r2, %r6
                \\    lg %r14, 18*8(%r2)
                \\    lg %r6, 20*8(%r2)
                \\.hidden __sigsetjmp_tail
                \\    jg __sigsetjmp_tail
            ),
            else => {},
        }
    }
}
