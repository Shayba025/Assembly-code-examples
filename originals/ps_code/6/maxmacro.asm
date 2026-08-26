;;; max-with-macros.asm
;;; Programmer: Gemini AI (based on Mayer Goldberg)

; --- הגדרת מאקרו 1: הדפסת הודעה עם מספר ---
%macro PRINT_MSG 3 ; שם המאקרו, וכמות פרמטרים
    mov rdi, %1    ; מחרוזת הפורמט
    mov rsi, %2    ; הפרמטר הראשון (כמות המספרים)
    mov rdx, %3    ; הפרמטר השני (הערך)
    mov rax, 0
    call printf
%endmacro

; --- הגדרת מאקרו 2: עדכון מקסימום ---
%macro UPDATE_MAX 2 ; מקבל ערך נוכחי וכתובת של המקסימום
    cmp %1, [%2]
    jle %%skip      ; שימוש ב-%% כדי ליצור לייבל מקומי למאקרו
    mov [%2], %1
%%skip:
%endmacro

section .data
fmt_max: db `The maximum of %ld number(s) is %ld\n\0`
i:       dq 1
max_val: dq -9223372036854775808

section .bss
argc: resq 1
argv: resq 1

extern atoi, printf
global main
section .text
main:
    push rbp
    mov rbp, rsp
    
    mov qword [argc], rdi
    mov qword [argv], rsi

.L:
    mov rax, qword [i]
    cmp rax, qword [argc]
    je .done

    mov rdi, qword [argv]
    mov rdi, qword [rdi + 8*rax]
    call atoi             ; התוצאה ב-RAX
    
    ; שימוש במאקרו לעדכון המקסימום
    UPDATE_MAX rax, max_val

    inc qword [i]
    jmp .L

.done:
    ; שימוש במאקרו להדפסה
    mov rsi, qword [argc]
    dec rsi
    PRINT_MSG fmt_max, rsi, qword [max_val]

    mov rsp, rbp
    pop rbp
    ret