.text
f73:
	pushq %rbp
	movq %rsp, %rbp
	movq %rsi, %rax
	movq %rax, %rsi
.Lbb2:
	cmpl $0, %edi
	setz %al
	movzbl %al, %eax
	movslq %eax, %rax
	cmpl $0, %eax
	jnz .Lbb4
	subq $1, %rdi
	addq $1, %rsi
	jmp .Lbb2
.Lbb4:
	movq %rsi, %rax
	leave
	ret
.type f73, @function
.size f73, .-f73
/* end function f73 */

.text
heaven_main:
	pushq %rbp
	movq %rsp, %rbp
	movl $0, %esi
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
	subq $8, %rsp
	pushq %rbx
	movl $0, %ebx
	movl $0, %eax
.Lbb10:
	cmpq $100, %rbx
	jge .Lbb12
	callq heaven_main
	addq $1, %rbx
	jmp .Lbb10
.Lbb12:
	movq %rax, %rsi
	leaq fmt(%rip), %rdi
	callq printf
	popq %rbx
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
