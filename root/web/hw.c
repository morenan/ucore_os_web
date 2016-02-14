#include <stdio.h>

struct Haha {
	int i, j, k;
	char c;
};

struct Hoho {
	int i;
	double d;
};

void xopowo() {
	printf("xopowo!\n");
}

void niconiconi(int i) {
	printf("%d %d %d\n", i, i, i);
}

int main(int argc, char** argv) {
	int i, j;
	struct Haha haha;
	niconiconi();
	niconiconi(i, j);
	niconiconi(haha);
		
}


