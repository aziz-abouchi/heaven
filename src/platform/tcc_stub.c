// Stub TCC : tcc_new() -> NULL -> error.TccInitFailed cote Zig.
// Utilise sur les plateformes ou TCC ne compile pas (WASM, aarch64,
// Windows). L'autofab/JIT n'est donc pas disponible, mais le reste
// du langage fonctionne.
//
// Note : seules les fonctions utilisees par autofab.zig sont stubbees.
#include "libtcc.h"
#include <stddef.h>

TCCState* tcc_new(void) { return NULL; }
void tcc_delete(TCCState* s) { (void)s; }
void tcc_set_options(TCCState* s, const char* options) { (void)s; (void)options; }
int tcc_set_output_type(TCCState* s, int output_type) { (void)s; (void)output_type; return -1; }
int tcc_compile_string(TCCState* s, const char* buf) { (void)s; (void)buf; return -1; }
int tcc_relocate(TCCState* s, void* ptr) { (void)s; (void)ptr; return -1; }
void* tcc_get_symbol(TCCState* s, const char* name) { (void)s; (void)name; return NULL; }
int tcc_add_symbol(TCCState* s, const char* name, const void* val) { (void)s; (void)name; (void)val; return -1; }
