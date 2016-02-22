void main(int argc, char** argv) {
	int i, j = 1, k;
	for (i = 0 ; i < 10 ; i++) {
		j = 100;
		while (j > 0) {
			k += i*j--;
			k -= i*--j;
			if (j+k > 10000) 
				break;
		}
	}
}
