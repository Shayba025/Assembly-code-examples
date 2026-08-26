;;; code-0021.asm
;;; Bubble Sort in x86/64
;;;
;;; Programmer: Mayer Goldberg, 2026

section .data
fmt_usage:
        db `Usage: program num₁ num₂ ⋯ numₙ, where n ≥ 1\n\0`
fmt_pre_sort:
        db `Before sorting the array:\n\0`
fmt_post_sort:
        db `After sorting the array:\n\0`
fmt_array_element:
        db `Arr[%lld] == %lld; \0`
fmt_newline:
        db `\n\0`

section .bss
size:
        resq 1
array:
        resq 1

extern printf, stderr, fprintf, exit, malloc, atoll
global main
section .text
main:
	push rbp
	mov rbp, rsp
        sub rsp, 8*3
        and rsp, -16

;;; The activation frame:
;;; |         | ret addr | qword [rbp + 8*1] |
;;; | rbp --> | old rbp  | qword [rbp]       |
;;; |         | source   | qword [rbp - 8*1] |
;;; |         | dest     | qword [rbp - 8*2] |
;;; |         | index    | qword [rbp - 8*3] |

	cmp rdi, 2
        jl .usage
        add rsi, 8
        mov qword [rbp - 8*1], rsi
        dec rdi
        mov qword [size], rdi
        mov qword [rbp - 8*3], rdi
        shl rdi, 3              ; rdi *= 8
        call malloc
        mov qword [array], rax
        mov qword [rbp - 8*2], rax

.loop:
        cmp qword [rbp - 8*3], 0
        jz .done
        mov rdi, qword [rbp - 8*1]
        mov rdi, qword [rdi]
        call atoll
        mov rbx, qword [rbp - 8*2]
        mov qword [rbx], rax
        dec qword [rbp - 8*3]
        add qword [rbp - 8*1], 8*1
        add qword [rbp - 8*2], 8*1
        jmp .loop

.done:
        mov rdi, fmt_pre_sort
        mov rax, 0
        call printf
        
        push qword [array]
        push qword [size]
        call print_array
	call bubble_sort

	mov rdi, fmt_post_sort
	mov rax, 0
	call printf
	
        call print_array
	
	mov rax, 0
	mov rsp, rbp
	pop rbp
	ret

.usage:
        mov rdi, qword [stderr]
        mov rsi, fmt_usage
        mov rax, 0
        and rsp, -16
        call fprintf

        mov rax, -1
        call exit

bubble_sort:
        push rbp
        mov rbp, rsp
        sub rsp, 8*3

;;; The activation frame:
;;; |         | array    | qword [rbp + 8*3] |
;;; |         | size     | qword [rbp + 8*2] |
;;; |         | ret addr | qword [rbp + 8*1] |
;;; | rbp --> | old rbp  | qword [rbp]       |
;;; |         | i1       | qword [rbp - 8*1] |
;;; |         | i2       | qword [rbp - 8*2] |
;;; |         | changed  | qword [rbp - 8*3] |

	mov rax, qword [rbp + 8*2]
	dec rax
	mov qword [rbp - 8*1], rax ; max index
.loop1:
	cmp qword [rbp - 8*1], 0
	jz .done
	mov qword [rbp - 8*2], 0
	mov qword [rbp - 8*3], 0
.loop2:
	mov rax, qword [rbp - 8*2]
	mov rbx, qword [rbp - 8*1]
	cmp rbx, 0
	jz .done
	cmp rax, rbx
	je .done2
	mov rdx, qword [rbp + 8*3]
	mov r8, qword [rdx + 8*rax] ; Array[i2]
	mov r9, qword [rdx + 8*rax + 8] ; Array[i2 + 1]
	cmp r8, r9
	jg .swap
	inc qword [rbp - 8*2]
	jmp .loop2
.swap:
	mov qword [rdx + 8*rax], r9
	mov qword [rdx + 8*rax + 8], r8
	mov qword [rbp - 8*3], 1
	inc qword [rbp - 8*2]
	jmp .loop2

.done2:
	cmp qword [rbp - 8*3], 0
	jz .done
	mov qword [rbp - 8*3], 0
	dec qword [rbp - 8*1]
	jmp .loop1

.done:
        mov rsp, rbp
        pop rbp
        ret

print_array:
        push rbp
        mov rbp, rsp
        sub rsp, 8*2
        and rsp, -16

;;; The activation frame:
;;; |         | array    | qword [rbp + 8*3] |
;;; |         | size     | qword [rbp + 8*2] |
;;; |         | ret addr | qword [rbp + 8*1] |
;;; | rbp --> | old rbp  | qword [rbp]       |
;;; |         | index    | qword [rbp - 8*1] |

        mov qword [rbp - 8*1], 0
.loop:
        mov rax, qword [rbp - 8*1]
        cmp rax, qword [rbp + 8*2]
        je .done
        mov rdi, fmt_array_element
        mov rsi, rax
        mov rdx, qword [rbp + 8*3]
        mov rdx, qword [rdx + 8*rax]
        mov rax, 0
        call printf
        inc qword [rbp - 8*1]
        jmp .loop

.done:
        mov rdi, fmt_newline
        mov rax, 0
        call printf

        mov rsp, rbp
        pop rbp
        ret

section .note.GNU-stack noalloc noexec
