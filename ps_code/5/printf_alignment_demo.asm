section .data
  msg db "The sum of %d and %d is %d", 10, 0

section .text
global main
extern printf
add2:
  mov rax, rdi
  add rax, rsi
  ret             ;ret rax

;---------------------------------------------
;  int main (void)                           ;
; calling add2                               ;
; calling printf with correct stack alignment;
;-------------------------------------------
main:
    push rbp
	mov rbp, rsp
	mov rdi, 10
	mov rsi, 20
	  
	call add2 
	;save r12 because it is a callee saved register 
	push r12
	  ;save result for printf
	mov r12 , rax          ; r12 = 10+20
   
	;------------------------------------------------------;
	;   prepare arguments for printf                       ;
	;   printf ('The sum of %d and %d is %d\n", 10, 20, 30);
	;-------------------------------------------------------;

	mov rdi, msg           ; rdi points to the string msg
	mov esi, 10            ; first  %d
	mov edx, 20            ; second %d
	mov ecx, r12d          ; result %d the sum is stored at the lower 32 bits of r12 this is why we use r12d
	
	xor eax, eax 

	;----------------------------------------------------------;
	; stack alignment before printf command                    ; 
	;  at entry to main rsp is aligned to 16 bit (rsp%16=0)    ;
	; but we pushed r12 so we need to realign the stack
	;----------------------------------------------------------;
	sub rsp, 8
	call printf 
	add rsp, 8
	; retreive the content of rsp after retrurn from printf
	pop r12
	;----------------------------------------------------------;
	;   return 0 from main                                     ;
	;----------------------------------------------------------;
	mov eax, 0
	mov rsp, rbp
	pop rbp
	ret

