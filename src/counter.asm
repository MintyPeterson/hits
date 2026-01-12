format PE64 NX Console 6.0
entry start

; **************************************
; Define the code section.
; **************************************
section '.text' code readable executable

  ; Enter the application.
  start:

    ; Align the stack.
    sub rsp, 8

    ; Get the standard output handle.
    mov rcx, 0FFFFFFF5h  ; nStdHandle = STD_OUTPUT_HANDLE
    sub rsp, 8 * 4
    call [GetStdHandle]
    add rsp, 8 * 4
    test rax, rax
    jz exit
    mov [output_handle], rax

    ; Get the identifier environment variable.
    mov r8, query_string_size        ; nSize = query_string_size
    lea rdx, [query_string]          ; *lpBuffer = query_string
    lea rcx, [query_string_variable] ; lpName = query_string_variable
    sub rsp, 8 * 4
    call [GetEnvironmentVariableW]
    add rsp, 8 * 4
    test rax, rax
    jz bad_request

    ; Check if the identifier is the correct size.
    cmp rax, (query_string_size - 1)
    jne bad_request

    ; Check if the identifier is the valid format.
    ; The format is xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx.
    ; Also update the placeholder identifier in the insert query as we go.
    mov rdi, insert_query
    mov rsi, query_string
    mov rcx, (query_string_size - 1)
    xor rax, rax
    xor rdx, rdx

    start_scan_identifier:
      lodsw
      ; Check hyphen positions
      cmp rdx, 8
      je compare_hyphen
      cmp rdx, 13
      je compare_hyphen
      cmp rdx, 18
      je compare_hyphen
      cmp rdx, 23
      je compare_hyphen
      ; Character is < 0
      cmp ax, '0'
      jb bad_request
      ; Character is <= 9 (i.e. 0-9)
      cmp ax, '9'
      jbe @f
      ; Character is < A
      cmp ax, 'A'
      jb bad_request
      ; Character is <= F (i.e. A-F)
      cmp ax, 'F'
      jbe @f
      ; Character is < a
      cmp ax, 'a'
      jb bad_request
      ; Character is <= f (i.e. a-f)
      cmp ax, 'f'
      jbe @f
      ; Character is out of all range checks
      jmp bad_request

      compare_hyphen:
        cmp ax, '-'
        jne bad_request

      @@:
        mov [rdi + 168 + rdx], al
        inc rdx
        loop start_scan_identifier

    ; Open the database.
    lea rdx, [database_handle]    ; *ppDb = database_handle
    lea rcx, [database_file_name] ; *filename = database_file_name
    sub rsp, 8 * 4
    call [sqlite3_open]
    add rsp, 8 * 4
    test rax, rax
    jnz insufficient_storage

    ; Execute the query.
    sub rsp, 8
    push 0                     ; &errmsg = 0
    lea r9, [insert_result]    ; *arg = insert_result
    lea r8, [insert_callback]  ; *callback = insert_callback
    lea rdx, [insert_query]    ; *sql = insert_query
    mov rcx, [database_handle] ; *sqlite3 = database_handle
    sub rsp, 8 * 4
    call [sqlite3_exec]
    add rsp, 8 * 6
    mov rbx, rax

    ; Close the database.
    sub rsp, 8 * 4
    mov rcx, [database_handle]
    call [sqlite3_close]
    add rsp, 8 * 4

    ; Check the query response.
    test rbx, rbx
    jnz insufficient_storage

    ; Output accepted response.
    push 0                         ; lpOverlapped = 0
    xor r9, r9                     ; lpNumberOfCharsWritten = 0
    mov r8, accepted_response_size ; nNumberOfCharsToWrite = accepted_response_size
    lea rdx, [accepted_response]   ; *lpBuffer = accepted_response
    mov rcx, [output_handle]       ; hFile = output_handle
    sub rsp, 8 * 4
    call [WriteFile]
    add rsp, 8 * 5

    ; Count the number of characters in the query result.
    xor rsi, rsi
    mov rbx, insert_result
    start_count:
      mov al, [rbx + rsi]
      cmp al, 0
      je @f
      inc rsi
      jmp start_count
    @@:

    ; Output the result.
    push 0                   ; lpOverlapped = 0
    xor r9, r9               ; lpNumberOfCharsWritten = 0
    mov r8, rsi              ; nNumberOfCharsToWrite = rsi
    mov rdx, insert_result   ; *lpBuffer = insert_result
    mov rcx, [output_handle] ; hFile = output_handle
    sub rsp, 8 * 4
    call [WriteFile]
    add rsp, 8 * 5
    jmp exit

  ; Output bad request response.
  bad_request:
    push 0                            ; lpOverlapped = 0
    xor r9, r9                        ; lpNumberOfCharsWritten = 0
    mov r8, bad_request_response_size ; nNumberOfCharsToWrite = bad_request_response_size
    lea rdx, [bad_request_response]   ; *lpBuffer = bad_request_response
    mov rcx, [output_handle]          ; hFile = output_handle
    sub rsp, 8 * 4
    call [WriteFile]
    add rsp, 8 * 5
    jmp exit

  ; Output insufficient storage response.
  insufficient_storage:
    push 0                                     ; lpOverlapped = 0
    xor r9, r9                                 ; lpNumberOfCharsWritten = 0
    mov r8, insufficient_storage_response_size ; nNumberOfCharsToWrite = insufficient_storage_response_size
    lea rdx, [insufficient_storage_response]   ; *lpBuffer = insufficient_storage_response
    mov rcx, [output_handle]                   ; hFile = output_handle
    sub rsp, 8 * 4
    call [WriteFile]
    add rsp, 8 * 5

  ; Exit the application.
  exit:
    xor ecx, ecx  ; uExitCode = 0
    sub rsp, 8 * 4
    call [ExitProcess]

; Insert query callback
insert_callback:
  push rbx
  ; Store the return value in the argument passed into sql3lite_exec
  mov rbx, [r8]
  mov rbx, [rbx]
  mov [rcx], rbx
  ; Restore non-volatile registers and return.
  pop rbx
  xor rax, rax
  ret

; *************************************
; Define the data section.
; *************************************
section '.data' data readable writeable

  output_handle dq ?

  query_string_variable du 'QUERY_STRING', 0
  query_string rb 74
  query_string_size = ($ - query_string) / 2

  database_file_name db 'counter.db', 0
  database_handle dq ?

  insert_query db "BEGIN; CREATE TABLE IF NOT EXISTS Hits (SiteIdentifier TEXT PRIMARY KEY COLLATE NOCASE, NumberOfHits INTEGER); INSERT INTO Hits (SiteIdentifier, NumberOfHits) VALUES ('00000000-0000-0000-0000-000000000000', 1) ON CONFLICT (SiteIdentifier) DO UPDATE SET NumberOfHits = NumberOfHits + 1 RETURNING NumberOfHits; COMMIT;", 0
  insert_result dq ?

  accepted_response db 'Status: 202', 13, 10, 'Content-Type: text/plain', 13, 10, 13, 10, 0
  accepted_response_size = $ - accepted_response - 1

  bad_request_response db 'Status: 400', 13, 10, 13, 10, 0
  bad_request_response_size = $ - bad_request_response - 1

  insufficient_storage_response db 'Status: 507', 13, 10, 13, 10, 0
  insufficient_storage_response_size = $ - insufficient_storage_response - 1

; ****************************************
; Define the import table section.
; ****************************************
section '.idata' import readable writeable

  idt:
    ; Kernel32.
    dd 0
    dd 0
    dd 0
    dd rva kernel32_name
    dd rva kernel32_iat
    ; Sqlite3.
    dd 0
    dd 0
    dd 0
    dd rva sqlite3_name
    dd rva sqlite3_iat
    ; End table.
    dd 0 dup(5)

  ; Kernel32.
  kernel32_name:
    db "kernel32.dll", 0
  kernel32_iat:
    ExitProcess dq rva ExitProcessName
    GetStdHandle dq rva GetStdHandleName
    WriteFile dq rva WriteFileName
    GetEnvironmentVariableW dq rva GetEnvironmentVariableWName
    dq 0

  ; Sqlite3.dll
  sqlite3_name:
    db "sqlite3.dll", 0
  sqlite3_iat:
    sqlite3_open dq rva sqlite3_open_name
    sqlite3_exec dq rva sqlite3_exec_name
    sqlite3_close dq rva sqlite3_close_name
    dq 0

  name_table:
    ExitProcessName\
      dw 0
      db "ExitProcess", 0, 0
    GetStdHandleName\
      dw 0
      db "GetStdHandle", 0, 0
    WriteFileName\
      dw 0
      db "WriteFile", 0, 0
    GetEnvironmentVariableWName\
      dw 0
      db "GetEnvironmentVariableW", 0, 0
    sqlite3_open_name\
      dw 0
      db "sqlite3_open", 0, 0
    sqlite3_exec_name\
      dw 0
      db "sqlite3_exec", 0, 0
    sqlite3_close_name\
      dw 0
      db "sqlite3_close", 0, 0
