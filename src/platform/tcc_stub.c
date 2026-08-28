// Stub TCC : tcc_new() retourne NULL → error.TccInitFailed côté Zig,
// la compilation runtime (mir) échoue proprement sans libtcc.
#include "libtcc.h"
#include <stddef.h>

TCCState* tcc_new(void) { return NULL; }
void tcc_delete(TCCState* s) { (void)s; }
int tcc_set_output_type(TCCState* s, int output_type) { (void)s; (void)output_type; return -1; }
int tcc_compile_string(TCCState* s, const char* buf) { (void)s; (void)buf; return -1; }
int tcc_relocate(TCCState* s, void* ptr) { (void)s; (void)ptr; return -1; }
void* tcc_get_symbol(TCCState* s, const char* name) { (void)s; (void)name; return NULL; }
int tcc_add_symbol(TCCState* s, const char* name, const void* val) { (void)s; (void)name; (void)val; return -1; }
int tcc_add_include_path(TCCState* s, const char* pathname) { (void)s; (void)pathname; return -1; }
int tcc_set_lib_path(TCCState* s, const char* path) { (void)s; (void)path; return -1; }
