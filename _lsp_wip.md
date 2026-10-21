# LSP WIP (2026-10-21)

## Fait
- lib/lsp/stdio.hvn : read_stdin, write_stdout (syscalls 0/1)
- lib/lsp/frame.hvn : content_length, frame (encode)
- Tests : frame "HELLO" -> "Content-Length: 5\r\n\r\nHELLO"

## Bloque : decode (parse_len + parse_body)
Recursion let-chain avec peek_byte/string_of_bytes echoue silencieusement.
- `let b = peek_byte (string_ptr s) i in parse_len_rec ...` -> ExecutionFailed
- Idem copy_loop avec poke_byte dans let-chain.

Voir _session_continuity : let-chain complexe + magics peut casser.

## Piste session dediee
- Simplifier : parser_len sur 1 chiffre (assume Content-Length < 10)
- Ou passer le pointeur (`string_ptr s`) en helper avant let-chain
- Ou fix .zig sur let-chain + magic combinaisons

## Next
lib/lsp/handlers.hvn : initialize/textDocument/didSave en .hvn
Peut utiliser frame (encode) deja OK.
