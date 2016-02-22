int strlen(char* s) {
	char* end = s;
	while (*end != '\0') end++;
	return int(end-s);
}

void printC(char c) {
	asm("SB 0xbf00[4] c");
	asm("SB 0xbf00[5] 0x01");
	char fb = 0;
	asm("LB 0xbf00[6] fb");
	while (!fb) asm("LB 0xbf00[6] fb");
	asm("SB 0xbf00[5] 0x00");
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
	printD(long(((lf>0)?(lf-long(lf)):(long(lf)-lf))*10000));
}

void printf(char* format, ...) {
	void* args = va_list_args;
	int i = 0;
	char* end = format+strlen(format);
	while (*end != '\0') end++;
	while (format < end) {
		if (*format == '%' && format+1<end)
			switch (format[1]) {
				case 'd' : printD(*((int*)(args+(i--)))); format+=2; break;
				case 'l' : 
					switch (format[2]) {
						case 'd' : printLD(*((long*)(args+(i--)))); format+=3; break;
						case 'f' : printLF(*((double*)(args+(i--)))); format+=3; break;
						default  : printC(*(format++)); break;
					}
				case 'f' : printF(*((float*)(args+(i--)))); break;
				case 'c' : printC(*((char*)(args+(i--)))); format+=2; break;
				case 's' : printS((char*)(args+(i--))); format+=2; break;
				default  : printC(*(format++)); break;
			}
		else
			printC(*(format++));
	}
}

char seek() {
	char c = 0;
	char fb = 0;
	asm("SB 0xbf00[1] 0x01");
	asm("LB 0xbf00[2] fb");
	while (!fb) asm("LB 0xbf00[2] fb");
	asm("LB 0xbf00[0] c");
	return c;
}

char getchar() {
	char c = 0;
	char fb = 0;
	asm("SB 0xbf00[1] 0x02");
	asm("LB 0xbf00[2] fb");
	while (!fb) asm("LB 0xbf00[2] fb");
	asm("LB 0xbf00[0] c");
	return c;
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

void scanLF(double* lf) {
	char c;
	while ((c=getchar())==' ' || c=='\n');
	long d;
	scanLD(&d);
	*lf = (double)d;
	if (seek() != '.') return;
	getchar();
	double lfb = 1.0;
	while ((c=seek())>='0' && c<='9') {
		*lf = lfb*(int)(c-'0');
		lfb /= 10; getchar();
	}
}

void scanf(char* format, ...) {
	void* args = va_list_args;
	int i = 0;
	char* end = format+strlen(format);
	while (*end != '\0') end++;
	while (format < end) {
		if (*format == '%' && format+1<end) 
			switch (format[1]) {
				case 'd' : scanD((int*)(args+(i--))); format+=2; break;
				case 'l' : 
					switch (format[2]) {
						case 'd' : scanLD((long*)(args+(i--))); format+=3; break;
						case 'f' : scanLF((double*)(args+(i--))); format+=3; break;
						default  : scanC(format++); break;
					}
					break;
				case 'f' : scanF((float*)(args+(i--))); break;
				case 'c' : scanC((char*)(args+(i--))); format+=2; break;
				case 's' : scanS((char*)(args+(i--))); format+=2; break;
				default  : scanC(format++); break;
			}
		else
			printC(*(format++));
	}
}



