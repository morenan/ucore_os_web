int strlen(char* s) {
	char* end = s;
	while (*end != '\0') end++;
	return int(end-s);
}

void printC(char c) {
	asm("SB 0xbf01, $c");
	asm("INT 0x0a");
}

void printS(char* s) {
	char* end = s+strlen(s);
	while (s < end)
		printC(*(s++));
}

void printD(int d) {
	if (!d) return;
	printD(d/10);
	printC((char)(d%10+'0'));
}

void printLD(long ld) {
	if (!ld) return;
	printLD(ld/10);
	printC((char)(ld%10+'0'));
}

void printF(float f) {
	printD(int(f));
	printC('.');
	int i;
	printD(int(((f>0)?(f-int(f)):(int(f)-f))*10000));
}

void printLF(double lf) {
	printD(long(lf));
	printC('.');
	int i;
	printD(long(((lf>0)?(f-long(f)):(long(f)-f))*10000));
}

void printf(char* format, ...) {
	int i = 0;
	char* end = format+strlen(format);
	while (*end != '\0') end++;
	while (format < end) {
		if (*format == '%' && format+1<end) {
			switch (format[1]) {
				case 'd' : printD(*((int*)(args+(i++)))); format+=2; break;
				case 'l' : 
					switch (format[2]) {
						case 'd' : printLD(*((long*)(args+(i++)))); format+=3; break;
						case 'f' : printLF(*((double*)(args+(i++)))); format+=3; break;
						default  : printC(*(format++)); break;
					}
				case 'f' : printF(*((float*)(args+(i++)))); break;
				case 'c' : printC(*((char*)(args+(i++)))); format+=2; break;
				case 's' : printS((char*)(args+(i++))); format+=2; break;
				default : printC(*(format++)); break;
		} else
			printC(*(format++));
	}
}

char seek() {
	asm("LB 0xbf00, ra");
	asm("RET");
}

char getchar() {
	asm("LB 0xbf00, ra");
	asm("SB 0xbf02, 1");
	asm("INT 0x0a");
	asm("SB 0xbf02, 0");
	asm("RET");
}

void scanC(char* c) {
	*c = getchar();
}

void scanS(char* s) {
	while ((*s=getchar())==' ' || *s=='\n');
	s++;
	while ((*s=getchar())!=' ' && *s!='\n') s++;
	*s = '\0';
}

void scanD(int* d) {
	char c;
	while ((c=getchar())==' ' || c=='\n');
	*d = (int)(c-'0');
	while ((c=seek())>='0' && c<='9') { 
		*d = (*d)*10 + (int)(c-'0'); getchar();
	}
}
	
void scanLD(long* ld) {
	char c;
	while ((c=getchar())==' ' || c=='\n');
	*ld = (long)(c-'0');
	while ((c=seek())>='0' && c<='9') {
		*ld = (*ld)*10 + (long)(c-'0');
		getchar();
	}
}

void scanF(float* f) {
	char c;
	while ((c=getchar())==' ' || c=='\n');
	int d;
	scanD(d);
	*f = (float)d;
	if (seek() != '.') return;
	getchar();
	float fb = 1.0;
	while ((c=seek())>='0' && c<='9') {
		*f = fb*(int)(c-'0');
		fb /= 10; getchar();
	}
}

void scanLF(double* f) {
	char c;
	while ((c=getchar())==' ' || c=='\n');
	long d;
	scanLD(d);
	*lf = (double)d;
	if (seek() != '.') return;
	getchar();
	double lfb = 1.0;
	while ((c=seek())>='0' && c<='9') {
		*lf = lfb*(int)(c-'0');
		fb /= 10; getchar();
	}
}

void scanf(char* format, ...) {
	int i = 0;
	char* end = format+strlen(format);
	while (*end != '\0') end++;
	while (format < end) {
		if (*format == '%' && format+1<end) {
			switch (format[1]) {
				case 'd' : scanD(((int*)(args+(i++)))); format+=2; break;
				case 'l' : 
					switch (format[2]) {
						case 'd' : scanLD(((long*)(args+(i++)))); format+=3; break;
						case 'f' : scanLF(((double*)(args+(i++)))); format+=3; break;
						default  : scanC((format++)); break;
					}
				case 'f' : scanF(((float*)(args+(i++)))); break;
				case 'c' : scanC(((char*)(args+(i++)))); format+=2; break;
				case 's' : scanS((char*)(args+(i++))); format+=2; break;
				default  : scanC((format++)); break;
		} else
			printC(*(format++));
	}
}



