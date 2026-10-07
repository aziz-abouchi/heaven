# src/platform/stubs/start_amd64_linux.s
# Point d'entree _start sans libc. Appelle main(argc, argv), puis exit.
.text
.globl _start
.type _start, @function
_start:
    xorq %rbp, %rbp
    movq (%rsp), %rdi        # argc
    leaq 8(%rsp), %rsi       # argv
    call main
    movq %rax, %rdi          # code retour de main
    movq $60, %rax           # SYS_exit
    syscall
.size _start, .-_start

.section .note.GNU-stack,"",@progbits
