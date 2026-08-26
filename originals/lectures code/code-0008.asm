;;; code-0008.asm
;;; Demonstrating the sys_write system call:
;;;   - How to use the syscall instruction
;;;   - The specific format for sys_write
;;;   - The use of $ to get the current address
;;;   - Printing "strings" without the '\0' at
;;;	the end: Not C-strings!
;;;   - Unicode characters are just bytes...
;;;	We can print them even if we don't know
;;;	or care about the encoding!
;;;
;;; Programmer: Mayer Goldberg, 2026 

section .data
message:
	db `Isn't assembly-language fun??\n`
	db `נָכוֹן שֶׁאֶסְמְבֵּלִי זֶה כֵּיף??\n`
	db `هَلْ أَلَيْسَتِ اللُّغَةُ التَّجْمِيعِيَّةُ مُمْتِعَةً؟؟\n`
	db `Разве язык ассемблера не увлекателен?\n`
	message_length equ $ - message

global main
section .text
main:
	push rbp
	mov rbp, rsp

	mov rax, 1		; sys_write
	mov rdi, 1		; fd out = 1
	mov rsi, message	; the text to be printed
	mov rdx, message_length ; # of bytes: no need for '\0' at the end!
	syscall

	mov rax, 0		; return value: OK

	mov rsp, rbp
	pop rbp
	ret

section .note.GNU-stack noalloc noexec
