# src/platform/stubs/syscall_amd64_linux.s
# Stub syscall Linux x86-64, convention C :
#   long heaven_syscall6(long n, long a1, long a2, long a3, long a4, long a5, long a6)
# Entree : rdi=n, rsi=a1, rdx=a2, rcx=a3, r8=a4, r9=a5, [rsp+8]=a6
# Retour : rax
.text
.globl heaven_syscall6
.type heaven_syscall6, @function
heaven_syscall6:
    movq %rdi, %rax
    movq %rsi, %rdi
    movq %rdx, %rsi
    movq %rcx, %rdx
    movq %r8,  %r10
    movq %r9,  %r8
    movq 8(%rsp), %r9
    syscall
    ret
.size heaven_syscall6, .-heaven_syscall6

.section .note.GNU-stack,"",@progbits
