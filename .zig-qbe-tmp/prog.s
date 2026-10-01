.text
f73:
	pushq %rbp
	movq %rsp, %rbp
	cmpl $0, %edi
	setz %al
	movzbl %al, %eax
	movslq %eax, %rax
	cmpl $0, %eax
	jnz .Lbb3
	subq $1, %rdi
	callq f74
	jmp .Lbb4
.Lbb3:
	movl $1, %eax
.Lbb4:
	leave
	ret
.type f73, @function
.size f73, .-f73
/* end function f73 */

.text
f74:
	pushq %rbp
	movq %rsp, %rbp
	cmpl $0, %edi
	setz %al
	movzbl %al, %eax
	movslq %eax, %rax
	cmpl $0, %eax
	jnz .Lbb8
	subq $1, %rdi
	callq f73
	jmp .Lbb9
.Lbb8:
	movl $0, %eax
.Lbb9:
	leave
	ret
.type f74, @function
.size f74, .-f74
/* end function f74 */

.text
heaven_main:
	pushq %rbp
	movq %rsp, %rbp
	movl $1000000, %edi
	callq f73
	leave
	ret
.type heaven_main, @function
.size heaven_main, .-heaven_main
/* end function heaven_main */

.text
.globl main
main:
	pushq %rbp
	movq %rsp, %rbp
	callq heaven_main
	movq %rax, %rsi
	leaq fmt(%rip), %rdi
	callq printf
	leave
	ret
.type main, @function
.size main, .-main
/* end function main */

.data
.balign 8
fmt:
	.ascii "%ld\n"
	.byte 0
/* end data */

.section .note.GNU-stack,"",@progbits
