#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

extern int64_t heaven_eval0(int64_t expr, int64_t env);
extern int64_t heaven_mkInt(int64_t n);
extern int64_t heaven_mkAdd(int64_t l, int64_t r);
extern int64_t heaven_mkMul(int64_t l, int64_t r);
extern int64_t heaven_mkSub(int64_t l, int64_t r);
extern int64_t heaven_mkVar(int64_t x);

int64_t parse_simple(const char* src) {
	int64_t left = 0, right = 0;
	char op = 0;
	int pos = 0;
	if (src[0] >= '0' && src[0] <= '9') {
		left = heaven_mkInt(atoll(src));
		while (src[pos] >= '0' && src[pos] <= '9') pos++;
	} else if (src[0] == 'x') {
		left = heaven_mkVar(0); pos = 1;
	} else if (src[0] == 'y') {
		left = heaven_mkVar(1); pos = 1;
	}

	while (src[pos] == ' ') pos++;

	if (src[pos] == 0) return left;
	op = src[pos];
	pos++;
	
	while (src[pos] == ' ') pos++;
	
	if (src[pos] >= '0' && src[pos] <= '9') {
		right = heaven_mkInt(atoll(src + pos));
	} else if (src[pos] == 'x') {
		right = heaven_mkVar(0);
	} else if (src[pos] == 'y') {
		right = heaven_mkVar(1);
	}
	
	switch (op) {
		case '+': return heaven_mkAdd(left, right);
		case '-': return heaven_mkSub(left, right);
		case '*': return heaven_mkMul(left, right);
		default: return left;
	}
}

int main(int argc, char** argv) {
	if (argc < 2) {
		printf("Heaven Bootstrap Interpreter v0.1\n");
		printf("Usage: %s 'expr' [x_val]\n", argv[0]);
		return 0;
	}
	
	int64_t ast = parse_simple(argv[1]);
	int64_t x_val = argc > 2 ? atoll(argv[2]) : 0;
	printf("%lld\n", heaven_eval0(ast, x_val));
	return 0;
}