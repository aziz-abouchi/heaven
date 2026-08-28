#pragma once
// API libtcc minimale utilisée par Heaven (native.zig @cImport + runtime/tcc.zig).
// Machine Guix : le vrai /usr/include/libtcc.h peut primer via -I système.
// Ici : déclarations autonomes pour lier avec tcc_stub.c.

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TCCState TCCState;

enum {
    TCC_OUTPUT_MEMORY = 0,
    TCC_OUTPUT_EXE    = 1,
    TCC_OUTPUT_DLL    = 2,
    TCC_OUTPUT_OBJ    = 3,
    TCC_OUTPUT_PREPROCESS = 5,
};

TCCState* tcc_new(void);
void tcc_delete(TCCState* s);
int tcc_set_output_type(TCCState* s, int output_type);
int tcc_compile_string(TCCState* s, const char* buf);
int tcc_relocate(TCCState* s, void* ptr);
void* tcc_get_symbol(TCCState* s, const char* name);
int tcc_add_symbol(TCCState* s, const char* name, const void* val);
int tcc_add_include_path(TCCState* s, const char* pathname);
int tcc_set_lib_path(TCCState* s, const char* path);

#ifdef __cplusplus
}
#endif
