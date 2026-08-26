;;; sum-digits-cps.asm
;;; מחשב סכום ספרות של מספר בשיטת המשכיות (Continuations)
;;; השראה מהמבנה של Mayer Goldberg בקובץ code-0005.asm

section .data
    fmt_res:   db `The sum of digits is: %ld\n\0`
    fmt_usage: db `Usage: sum-digits <positive integer>\n\0`

section .text
extern atoll, printf, exit
global main

main:
    push rbp
    mov rbp, rsp
    and rsp, -16                ; יישור המחסנית כפי שראינו ב
    
    cmp rdi, 2                  ; בדיקת argc
    jne error_usage

    mov rdi, qword [rsi + 8*1]  ; argv[1]
    call atoll                  ; המרה למספר 64 ביט (RAX)
    
    mov rdi, rax                ; המספר לעיבוד
    mov rsi, 0                  ; אוגר צובר (הסכום)
    
    ; הגדרת ה"המשכיות": לאן ללכת כשנסיים את החישוב
    mov rdx, print_result
    jmp digit_step              ; קפיצה לצעד הראשון

digit_step:
    ; rdi = המספר שנשאר לעבד
    ; rsi = הסכום שנצבר עד כה
    ; rdx = הכתובת להמשך (ההמשכיות)
    
    cmp rdi, 0
    je .finish                  ; אם המספר התרוקן, קפוץ לסיום

    ; בידוד הספרה האחרונה בעזרת חילוק ב-10
    mov rax, rdi
    mov rcx, 10
    mov rdx, 0                  ; איפוס rdx לפני div (חובה!)
    div rcx                     ; rax = מנה, rdx = שארית (הספרה)
    
    add rsi, rdx                ; הוספת הספרה לסכום הכללי ב-rsi
    mov rdi, rax                ; עדכון המספר שנשאר (המנה)
    
    ; כאן הקסם: במקום ret, אנחנו פשוט קופצים חזרה לתחילת הצעד
    ; הכתובת המקורית לסיום עדיין "נמצאת באוויר" (לא השתמשה במחסנית)
    jmp digit_step

.finish:
    ; סיימנו את כל הספרות, עכשיו עוברים ליעד הסופי שנקבע ב-main
    ; בגישת CPS אמיתית, היינו קופצים לכתובת דינמית, כאן זהו .print_result
    jmp print_result

print_result:
    mov rdi, fmt_res
    ; rsi כבר מכיל את הסכום הסופי
    mov rax, 0
    call printf
    jmp end

error_usage:
    mov rdi, fmt_usage
    mov rax, 0
    call printf
    
end:
    mov rsp, rbp
    pop rbp
    ret