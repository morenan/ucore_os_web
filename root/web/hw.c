#include <stdio.h>

void helloworld() {
	printf("helloworld\n");
}

void main(int argc, char** argv) {
	int i = 0;
	void* f = 0;
	int j = f();
	while (i < 10) {
		helloworld();
		i++;
	}
}

