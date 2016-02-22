#include <stdio.h>

void xopowo(int i) {
	printf("xopowo i=%d\n", i);
	if (i > 10) return;
	char* c = "xopowo";
	xopowo(i+1);
	printf("%c%c%c%c%c%c\n", c[0], c[1], c[2], c[3], c[4], c[5]);
	c[0] = 'n'; c[1] = 'i'; c[2] = 'c'; c[3] = 'o'; 
}

void main(int argc, char** argv) {
	xopowo(0);
}
