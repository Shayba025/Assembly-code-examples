;;; code-0000.asm
;;; The do-nothing program: int main() { return 0; }
;;;
;;; Programmer: Mayer Goldberg, 2026

global main
section .text
main:				; int main() { return 0; }
	mov rax, 0		; this is the return value
	ret			; and now we return

section .note.GNU-stack noalloc noexec
