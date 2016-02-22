void main(int argc, char** argv) {
	int i = 2, j = 3;
	switch (double(i*i)==1.0) {
		case 0 : j = 5; i = i-j;
		case 1 : j = 6; i = j*2;
		case 2 : j = 7; i = j/2; break;
		case 3 : j = 8; i = j+i; break;
		case 5 : j = 9; i = 1;
		case 7 : j = 10; i = (int)(&j); break;
		default : i = j;
	}
}
