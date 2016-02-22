void xopowo(int* i, int* j) {
	int tmp = *i; *i = *j; *j = tmp;
}

void main(int argc, char** argv) {
	int i = 1, j = 2;
	xopowo(&i, &j);
	int k = 3;
	xopowo(&i, &k);
	xopowo(&j, &k);
}


