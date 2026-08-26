;;; subset-gen.asm
;;; יצירת כל תתי-הקבוצות של מחרוזת קלט
;;; מבוסס על הלוגיקה של Mayer Goldberg

section .data
    fmt_subset: db `{%s}\n\0`
    empty_msg:  db `Empty set included\n\0`
    i:          dq 0    ; אינדקס במחרוזת המקורית
    j:          dq 0    ; אינדקס בבאפר התוצאה
    input_str:  dq 0    ; מצביע למחרוזת שקיבלנו מהמשתמש

section .bss
    n:          resq 1  ; אורך מחרוזת הקלט
    result_buf: resb 128 ; באפר לבניית תת-הקבוצה הנוכחית

extern printf, strlen
global main
section .text

main:
    push rbp
    mov rbp, rsp
    and rsp, -16

    cmp rdi, 2          ; בדיקה שקיבלנו ארגומנט (מחרוזת)
    jne .exit

    mov rsi, qword [rsi + 8*1] ; קבלת כתובת המחרוזת (argv[1])
    mov qword [input_str], rsi
    
    mov rdi, rsi
    call strlen         ; חישוב אורך המחרוזת
    mov qword [n], rax

    call generate_subsets

.exit:
    mov rsp, rbp
    pop rbp
    ret

generate_subsets:
    mov rax, qword [i]
    cmp rax, qword [n]  ; תנאי עצירה: הגענו לסוף המחרוזת
    je .print_subset

    ; אפשרות 1: לא להכליל את האות הנוכחית
    inc qword [i]       ; עוברים לאות הבאה
    call generate_subsets
    dec qword [i]       ; חוזרים (Backtrack)

    ; אפשרות 2: כן להכליל את האות הנוכחית
    mov rsi, qword [input_str]
    mov rdx, qword [i]
    mov al, byte [rsi + rdx]   ; טעינת האות הנוכחית
    
    mov rdx, qword [j]
    mov byte [result_buf + rdx], al ; הוספה לבאפר התוצאה
    
    inc qword [j]
    inc qword [i]
    call generate_subsets
    
    ; חזרה למצב קודם (Backtrack)
    dec qword [i]
    dec qword [j]
    ret

.print_subset:
    ; סגירת המחרוזת בבאפר התוצאה עם NULL
    mov rdx, qword [j]
    mov byte [result_buf + rdx], 0
    
    mov rdi, fmt_subset
    mov rsi, result_buf
    mov rax, 0
    call printf
    ret