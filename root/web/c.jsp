<html>
	<body>
		<div id="board"></div>
	</body>
	<script type="text/javascript">
		var SEG_SZ    = 8*1024*1024, // max size of text+data+bss seg
  		var EXPR_SZ   =      4*1024, // size of expression stack
  		var VAR_SZ    =     64*1024, // size of symbol table
  		var PSTACK_SZ =     64*1024, // size of patch stacks
  		var LSTACK_SZ =      4*1024, // size of locals stack
  		var HASH_SZ   =      8*1024, // number of hash table entries
  		var BSS_TAG   =  0x10000000, // tag for patching global offsets
  		
  		var ts_seg 		 = new Array(SEG_SZ);
  		var gs_seg 		 = new Array(SEG_SZ);
  		var va_var 		 = new Array(VAR_SZ);
  		var pdata_pstack = new Array(PSTACK_SZ);
  		var pbss_pstack  = new Array(PSTACK_SZ);
  		var ploc_lstack  = new Array(LSTACK_SZ);
  		var expr  		 = new Array(EXPR_SZ);
  		var ht_hash		 = new Array(HASH_SZ);
  		
  		var tk = 0;       // current token
    	var ts = 0;		  // text segment 
    	var ip = 0;    	  // current pointer
    	var gs = 0;		  // data segment 
    	var data = 0; 	  // current offset
    	var bss = 0;      // bss offset
    	var loc = 0;      // locals frame offset
    	var line = 0;     // line number
    	var ival = 0;     // current token integer value
    	var errs = 0;     // number of errors
    	var verbose = 0;  // print additional verbiage
    	var debug = 0;    // print source and object code
    	var ffun = 0;     // unresolved forward function counter
    	var va = 0;		  // variable pool 
    	var vp = 0;   	  // current pointer
   		var e = 0;        // expression tree pointer
    	var pdata = 0;    // data segment patchup pointer
    	var pbss = 0;     // bss segment patchup pointer
		var id = 0;  	  // current parsed identifier
		var fval = 0.0;   // current token double value
		var ty = 0;       // current parsed subexpression type
     	var rt = 0;       // current parsed function return type
     	var bigend = 0;   // big-endian machine
		var file = null;  // input file name
     	var cmd = null;   // command name
     	var incl = null;  // include path
		var pos = null;   // input file	
  		var pos_id = 0;	  // input file index
		var ploc = 0;  	  // local variable stack pointer
		
		var board = document.getElementById("board");

		function main() {
			var verbose = "<%= request.getParameter("verbose") %>";
			var debug   = "<%= request.getParameter("debug") %>";
			var ipath   = "<%= request.getParameter("ipath") %>";
			var opath   = "<%= request.getParameter("opath") %>";
			if (verbose != "0" && verbose != "1" && verbose != "null") {
				print("usage: %s [-v] [-s] [-Ipath] [-o exefile] file ...\n"); return -1;
			}
			if (debug != "0" && debug != "1" && debug != "null") {
				print("usage: %s [-v] [-s] [-Ipath] [-o exefile] file ...\n"); return -1;
			}
			if (ipath == "null" || opath == "null") {
				print("usage: %s [-v] [-s] [-Ipath] [-o exefile] file ...\n"); return -1;
			}
			ip = 0; vp = 0;
			bigend = 1; // bigend = ((char *)&bigend)[3];
			pos = "asm auto break case char continue default do double else enum float for goto if int long return short "
        		+ "sizeof static struct switch typedef union unsigned void while va_list va_start va_arg main";	
			for (var i = Asm; i <= Va_arg; i++) {
				 next(); 
				 id.tk = i; 
			}
			next();
  			tmain = id;
  			
  			line = 1;
  			if (stat(file, st)) { 
  				print(sprintf("%s : [%s:%d] error: can't stat file %s\n", cmd, file, line, file)); return -1; 
  			} // XXX fstat inside mapfile?
  			pos = mapfile(file, st.st_size);

  			e = EXPR_SZ;
  			pdata = 0; patchdata = 0;
  			pbss  = 0; patchbss  = 0;
  			ploc  = 0;

  			if (verbose) print(sprintf("%s : compiling %s\n", cmd, file));
  			if (debug) dline();
  			next();
  			decl(Static);
  			if (!errs && ffun) err("unresolved forward function (retry with -v)");
    
  			ip = (ip + 7) & -8;
  			text = ip - ts;
  			data = (data + 7) & -8;
  			bss = (bss + 7) & -8;
    
  			if (text + data + bss > SEG_SZ && err("text + data + bss segment exceeds maximum size") != 0)
  				return -1;
  			amain = tmain->val;
  			if (amain == null && err("main() not defined") != 0) 
  				return -1;
  			if (verbose || errs) print(sprintf("%s : %s compiled with %d errors\n", cmd, file, errs));
  			if (verbose) print(sprintf("entry = %d text = %d data = %d bss = %d\n", amain - ts, text, data, bss));

  			if (!errs && !debug) {
    			while (pdata != patchdata) { 
    				pdata -= 1; 
    				*(int *)*pdata += (ip - *pdata - 4) << 8; 
    			}
    			while (pbss  != patchbss ) { 
    				pbss -= 1;  
    				*(int *)*pbss  += (ip + data - *pbss  - 4) << 8; 
    			}
    			if (outfile) {
    				var fso = new ActiveXObject("Scripting.FileSystemObject");
      				var f1 = fso.CreateTextFile(outfile, true);
      				if (f1 == null) { 
      					print(sprintf("%s : error: can't open output file %s\n", cmd, outfile)); return -1; 
      				}
      				hdr.magic = 0xC0DEF00D;
      				hdr.bss   = bss;
      				hdr.entry = amain - ts;
      				hdr.flags = 0;
      				write(i, &hdr, sizeof(hdr));
      				write(i, (void *) ts, text);
      				write(i, (void *) gs, data);
      				close(i);
    			} else {
      				memcpy((void *)ip, (void *)gs, data);
      				sbrk(sbrk_start + text + data + 8 - (int)sbrk(0)); // free compiler memory    
      				sbrk(bss);
      				if (verbose) dprintf(2,"%s : running %s\n", cmd, file);
      				errs = ((int (*)())amain)(argc, argv);
      				if (verbose) dprintf(2,"%s : %s main returned %d\n", cmd, file, errs);
    			}
  			}
  			if (verbose) print(sprintf("%s : exiting\n", cmd));
  			return errs;
		}
		
		function print(msg) {
			board.innerHTML = board.innerHTML + msg;
		}
		function err(msg) {
  			print(sprintf("%s : [%s:%d] error: %s\n", cmd, file, line, msg)); // XXX need errs to power past tokens (validate for each err case.)
  			errs += 1;
  			if (errs > 10) { 
  				print(sprintf("%s : fatal: maximum errors exceeded\n", cmd)); return -1;
  			}
  			return 0;
  		}
  		function mapfile(name, size) // XXX replace with mmap
  		{
  			var fso = new ActiveXObject("Scripting.FileSystemObject");
      		var f1 = fso.CreateTextFile(name, true);
  			if (f1 == null) { 
  				print(sprintf("%s : [%s:%d] error: can't open file %s\n", cmd, file, line, name)); return -1; 
  			}
  			var p = f1.Read(size);
  			if (p.length != size) {
  				print(sprintf("%s : [%s:%d] error: can't read file %s\n", cmd, file, line, name)); return -1; 
  			}
			return p;
		}
		
		// instruction emitter
		function em(i) {
  			if (debug == 1) 
  				print(sprintf("%08x  %08x%6.4s\n", TS_ADDR+ip, i, ops[i*5]));
  			ts_seg[ip] = i;
  			ip += 4;
		}
		function emi(i, c) {
  			if (debug == 1) 
  				print(sprintf("%08x  %08x%6.4s  %d\n", TS_ADDR+ip, i|(c<<8), ops[i*5], c));
  			if (c<<8>>8 != c) err("emi() constant out of bounds"); 
  			ts_seg[ip] = i|(c<<8);
  			ip += 4;
		}
		function emj(i, c) { // jump
			emi(i, c - ip - 4); 
		}
		function eml(i, c) { // local
			emi(i, c - loc); 
		}
		function emg(i, c) { // global 
			if (c < BSS_TAG) {
				pdata_pstack[pdata] = ip;
				pdata += 1; 
			} else { 
				pbss_pstack[pbss] = ip;
				pbss += 1;
				c -= BSS_TAG; 
			} 
			emi(i, c); 
		}
		function emf(i, c) { // forward
  			if (debug == 1) 
  				print(sprintf("%08x  %08x%6.4s  <fwd>\n", TS_ADDR+ip, i|(c<<8), ops[i*5]));
  			if (c<<8>>8 != c) err("emf() offset out of bounds");
  			ts_seg[ip] = i|(c<<8);
  			ip += 4;
  			return ip-4;
		}
		function patch(t, a) {
  			var n = 0;
  			while (t != 0) {
    			t += ts;
    			n = ts_seg[t];
    			ts_seg[t] = (n & 0xff) | ((a-t-4) << 8);
    			t = n>>8;
  			}
		}
		// parser
		function dline() {
  			for (var p = 0 ; p < pos.length ; p++)
  				print(sprintf("%s  %d: %.*s\n", file, line, p-pos, pos));
  		}
  		function next() {
  			var ipos = 0;
  			var ipos_str = null;
  			var ifile = null;
  			var iline = 0;
  			while (pos_id < pos.length) {
  				switch (pos[pos_id++]) {
  					case ' ': case '\t': case '\v': case '\r': case '\f':
      					continue;
					case '\n':
      					line += 1; 
      					if (debug) dline();
      					continue;
      				case '#':
      					if (pos.substring(pos_id, pos_id+7).big() != "INCLUDE") {
        					if (ifile) { err("can't nest include files"); return -1; } // include errors bail out otherwise it gets messy
        					pos_id += 7;
        					while (pos[pos_id] == ' ' || pos[pos_id] == '\t') pos_id += 1;
        					ipos = pos.substring(pos_id).match("^(\".+\")|(<.+>)");
        					if (ipos == null) {
        						err("bad include file name"); return -1;
        					}
        					if (ipos[1] == '/')
        						b = 0;
        					else if (incl != null) {
          						iname = new String(incl) + '/';
          						b = iname.length;
        					} else {
          						for (b = file.length; b != 0 ; b -= 1) 
          							if (file[b-1] == '/') { 
          								iname = file.substring(0, b); 
          								break; 
          							}
        					} 
        					iname = iname + filepath.substring(1,ipos.length);
        					if (stat(iname, st)) {
          						if (ipos[0] == '"' || ipos[1] == '/') { 
          							print(dprintf("%s : [%s:%d] error: can't stat file %s\n", cmd, file, line, iname)); 
          							return -1; 
          						}
          						iname = "/lib/" + ipos.substring(1,ipos.length);
          						if (stat(iname, st)) { 
          							print(dprintf("%s : [%s:%d] error: can't stat file %s\n", cmd, file, line, iname)); 
          							return -1; 
          						}
        					}
        					pos_id += filepath.length;
        					while (pos[pos_id] != '\0' && pos[pos_id] != '\n') pos_id += 1;
        					ipos_id = pos_id; ipos = pos; 
        					pos = mapfile(iname, st.st_size);
        					ifile = file; file = iname;
        					iline = line; line = 1;
        					if (debug) dline();
        					continue;
      					}
      					while (pos[pos_id] != '\0' && pos[pos_id] != '\n') pos++;
      					continue;
      				case 'a' ... 'z': case 'A' ... 'Z': case '_': case '$':
      					ipos = pos.substring(pos_id-1).match("^[a-zA-Z0-9_$]+");
      					if (ipos == null) {
      						print(sprintf("%s : [%s:%d] error: can't match name\n", cmd, file, line));
      						return -1;
      					}
      					pos_id += ipos.length - 1;
      					for (tk = 0, i = 0 ; i < ipos.length ; i++)
      						tk = tk*147 + ipos[i]; 
      					id = ht[tk&(HASH_SZ-1)];
      					while (id != null) {
        					if (tk == id.tk) return 0;
        					id = id.next;
      					}
      					id = new Object(); 
     				 	id.name = p;
      					id.tk = tk;
      					id.next = ht[tk&(HASH_SZ-1)];
      					ht[tk&(HASH_SZ-1)] = id;
      					return 0;
      				case '0' ... '9':
      					if (pos[pos_id] == 'x' || pos[pos_id] == 'X') {
      						ipos = pos.substring(pos_id++).match("^[0-9|A-F|a-f]+").big();
      						if (ipos == null) {
      							print(sprintf("%s : [%s:%d] error: can't match number\n", cmd, file, line)); 
          						return -1;
          					}
      						ival = hexValueOf(ipos);
      						pos_id += ipos.length;
      						ty = INT;
      						tk = Num;
      					} else if (pos[pos_id] == 'b' || pos[pos_id] == 'B') {
      						ipos = pos.substring(pos_id++).match("^[0-1]+");
      						if (ipos == null) {
      							print(dprintf("%s : [%s:%d] error: can't match number\n", cmd, file, line)); 
          						return -1;
          					}
      						ival = binValueOf(ipos);
      						pos_id += ipos.length;
      						ty = INT;
      						tk = Num;
      					} else {
      						ipos = pos.substring(pos_id-1).match("^[0-9]+(.[0-9]+)?");
      						if (ipos == null) {
      							print(dprintf("%s : [%s:%d] error: can't match number\n", cmd, file, line)); 
          						return -1;
          					}
          					pos_id += ipos.length;
          					if (ipos.match(".") == null) {
          						ival = parseInt(num_str);
          						ty = INT;
          						tk = Num;
          					} else {
      							fval = Number(num_str);
      							ty = DOUBLE;
          						tk = Numf;
          					}
      					}
      					if (ty == INT) {
      						if (pos[pos_id] == 'u' || pos[pos_id] == 'U') {
      							ty = UINT; pos_id++;
      						} else if (pos[pos_id] == 'l' || pos[pos_id] == 'L') {
      							ty = INT; pos_id++;
      						}
      					}
      					return 0;
      				case '/':
      					if (pos[pos_id] == '/') { // single line comment
        					pos_id += 1;
        					while (pos_id < pos.length && pos[pos_id] != '\n')
        						pos_id += 1;
        					continue;
        				} else if (pos[pos_id] == '*') { // comment
        					pos_id += 1;
        					while (pos_id+1 < pos.length) {
          						if (pos[pos_id] == '*' && pos[pos_id+1] == '/') { 
          							pos_id += 2; break; 
          						} else if (*pos == '\n') { 
          							line += 1; 
          							if (debug) { 
          								pos_id += 1; 
          								dline(); 
          								pos_id -= 1; 
          							} 
          						}
          					}
          					continue;
          				} else if (pos[pos_id] == '=') { 
          					pos_id += 1; tk = Diva; 
          				} else 
          					tk = Div;
      					return;
      				case '\'': case '"':
      					ival = data;
      					tk = pos[pos_id-1];
      					while (pos_id < pos.length && (b = pos[pos_id++]) != tk) {
        					if (b == '\\') {
          						switch (b = pos[pos_id++]) {
          							case '\'': case '"': case '?': case '\\': break;
          							case 'a': b = '\a'; break; // alert
									case 'b': b = '\b'; break; // backspace
									case 'f': b = '\f'; break; // form feed
									case 'n': b = '\n'; break; // new line
									case 'r': b = '\r'; break; // carriage return
									case 't': b = '\t'; break; // horizontal tab
									case 'v': b = '\v'; break; // vertical tab
									case 'e': b = '\e'; break; // escape
									case '\r': while (*pos == '\r' || *pos == '\n') pos++; // XXX not sure if this is right
          							case '\n': line++; if (debug) dline(); continue;
          							case 'x':
										// b = (*pos - '0') * 16 + pos[1] - '0'; pos += 2; // XXX this is broke!!! 0xFF needs to become -1 also
            							switch (pos[pos_id]) {
											case '0' ... '9': b = pos[pos_id++] - '0'; break;
											case 'a' ... 'f': b = pos[pos_id++] - 'a' + 10; break;
											case 'A' ... 'F': b = pos[pos_id++] - 'A' + 10; break;
											default: b = 0; pos_id += 1; break;                  // XXX you can try a few in a reg c compiler?!
										}
										switch (pos[pos_id]) {
											case '0' ... '9': b = b*16 + pos[pos_id++] - '0'; break;
											case 'a' ... 'f': b = b*16 + pos[pos_id++] - 'a' + 10; break;
											case 'A' ... 'F': b = b*16 + pos[pos_id++] - 'A' + 10; break;
											default: break;              
										}
            							// XXX			b = (char) b; // make sure 0xFF becomes -1 XXX do some other way!
            							break;
          							case '0' ... '7': 
            							b -= '0';
            							if (pos[pod_id] >= '0' && pos[pos_id] <= '7') {
              								b = b*8 + pos[pos_id++] - '0';
              								if (pos[pos_id] >= '0' && pos[pos_id] <= '7') 
              									b = b*8 + pos[pos_id++] - '0';
            							}
            							break;
          							default: err("bad escape sequence");
          						}
          					}
        					gs_seg[gs + data++] = b;
        				}
        				if (tk == '\'') {
        					ival = gs_seg[gs+data-1];
        					ty = INT; tk = Num;
						}
      					return 0;	
      				case '=': if (pos[pos_id] == '=') { pos_id += 1; tk = Eq;   } else tk = Assign; return 0;
    				case '+': if (pos[pos_id] == '+') { pos_id += 1; tk = Inc;  } 
    					 else if (pos[pos_id] == '=') { pos_id += 1; tk = Adda; } else tk = Add; return 0;
    				case '-': if (pos[pos_id] == '-') { pos_id += 1; tk = Dec;  } 
         				 else if (pos[pos_id] == '>') { pos_id += 1; tk = Arrow;} 
         				 else if (pos[pos_id] == '=') { pos_id += 1; tk = Suba; } else tk = Sub; return 0;
					case '*': if (pos[pos_id] == '=') { pos_id += 1; tk = Mula; } else tk = Mul; return 0;
					case '<': if (pos[pos_id] == '=') { pos_id += 1; tk = Le;   } 
						 else if (pos[pos_id] == '<') { 
						 	  		if (*pos[++pos_id] == '=') { pos_id += 1; tk = Shla; } 
						 	  			else tk = Shl; } 
						 else tk = Lt; return 0;
					case '>': if (pos[pos_id] == '=') { pos_id += 1; tk = Ge;   }
						 else if (pos[pos_id] == '>') { 
						 			if (pos[++pos_id] == '=') { pos_id += 1; tk = Shra; } 
						 				else tk = Shr; } 
						 else tk = Gt; return 0;
					case '|': if (pos[pos_id] == '|') { pos_id += 1; tk = Lor;  } 
						 else if (pos[pos_id] == '=') { pos_id += 1; tk = Ora;  } else tk = Or;  return;
					case '&': if (pos[pos_id] == '&') { pos_id += 1; tk = Lan;  } 
						 else if (pos[pos_id] == '=') { pos_id += 1; tk = Anda; } else tk = And; return;
					case '!': if (pos[pos_id] == '=') { pos_id += 1; tk = Ne;   } return;
					case '%': if (pos[pos_id] == '=') { pos_id += 1; tk = Moda; } else tk = Mod; return;
					case '^': if (pos[pos_id] == '=') { pos_id += 1; tk = Xora; } else tk = Xor; return;
					case ',': tk = Comma; return;
					case '?': tk = Cond; return;
					case '.':
					  if (pos[pos_id] == '.' && pos[pos_id+1] == '.') { pos_id += 2; tk = Dots; }
					  else if (pos[pos_id] >= '0' && pos[pos_id] <= '9') { fval = 0.0; goto frac; }
					  else tk = Dot; return;
					  // XXX eventually test for float? is this structure access x.y or floating point .5?
					  // XXX lookup strtod() for guidance/implementation

					case '(': tk = Paren; return;
					case '[': tk = Brak; return;
					case '~':
					case ';':
					case ':':
					case '{':
					case '}':
					case ')':
					case ']': return;
					default: err("bad token"); continue;
				}
			}
			if (ifile == null) { pos_id -= 1; return 0; }
			file = ifile; ifile = 0;
			pos = ipos;
			pos_id = ipos_id;
			line = iline;
			return 0;
		}		  			
        
    	function skip(c) {
  			if (tk != c) { print(sprintf("%s : [%s:%d] error: '%c' expected\n", cmd, file, line, c)); errs++; }
  			next();
		}
		
		function imm() /// XXX move these back down once I validate prototypes working for double immf()
		{
			int *b = e, c;
			expr(Cond);
			if (*e == Num) c = e[2];
			else if (*e == Numf) c = (int) *(double *)(e+2);
			else { err("bad constant expression"); c = 0; }
			e = b;
			return c;
		}

		function immf()
		{
			int *b = e; double c;
			expr(Cond);
			if (*e == Num) c = e[2];
			else if (*e == Numf) c = *(double *)(e+2);
			else { err("bad float constant expression"); c = 0.0; }
			e = b;
			return c;
		}
		
		function tsize(t) // XXX return unsigned? or error checking on size
		{
  			var a ;   // type : array_t *a; 
  			var s ;   // type : struct_t *s;
  			switch (t & TMASK) {
  				case ARRAY:  
  					a = va_var[t>>TSHIFT]; 
  					return a.size * tsize(a.type);  
  				case STRUCT:
  					s = va_var[t>>TSHIFT];
    				if (s.align) return s.size;
    				err("can't compute size of incomplete struct");
				case CHAR:
				case UCHAR:
				case VOID:
				case FUN: 
					return 1;
				case SHORT:
				case USHORT: 
					return 2;
				case DOUBLE: 
					return 8;
				default: 
					return 4;
  			}
		}

		function tinc(t) // XXX return unsigned?
		{
  			if (t & PMASK) return tsize(t - PTR);
  	   else if (t & ARRAY) return tsize(va_var[t>>TSHIFT].type);  // XXX need to test this!
  	   else return 1;
		}

		function talign(uint t) {
  			var a;
			switch (t & TMASK) {
				case ARRAY:  
					return talign(va_var[t>>TSHIFT].type);
			  	case STRUCT:
			  		a = va_var[t>>TSHIFT].align;
					if (a != 0) return a;
					err("can't compute alignment of incomplete struct");
				case CHAR:
				case UCHAR: 
					return 1;
				case SHORT:
				case USHORT: 
					return 2;
				case DOUBLE: 
					return 8;
				default: 
					return 4;
			}
		}
		
		function basetype() {
  			var m ; // int m;
  			var n ; // ident_t *n;
  			var s ; // struct_s *s;
  			
  			switch (tk) {
  				case Void:    next(); return VOID; // XXX
  				case Va_list: next(); return CHAR + PTR;

				case Unsigned: // not standard, but reasonable
					next();
					if (tk == Char) { next(); return UCHAR; }
					if (tk == Short) { next(); if (tk == Int) next(); return USHORT; }
					if (tk == Long) next(); 
					if (tk == Int) next();
					return UINT;

  				case Char:   next(); return CHAR;
				case Short:  next(); if (tk == Int) next(); return SHORT;
			 	case Long:   next(); if (tk == Int) next(); return INT;
				case Int:    next(); return INT;
				case Float:  next(); return FLOAT;
				case Double: next(); return DOUBLE;

				case Union:
				case Struct:
					m = tk;
					next();
					if (tk == Id) {
						var goto_found = false;
						for (s = structs; s; s = s.next) 
							if (s->id == id) goto_found = true;
						if (goto_found == false) {
							s = va_var[vp++]; 
					  		s.id = id; // XXX redefinitions
					  		s.next = structs; 
					  		structs = s;
					  	}
						next();
					  	if (tk != '{') 
					  		return STRUCT | (s.addr<<TSHIFT);
					  	if (s.align) err("struct or union redefinition");
					  	next();
					} else {
						skip('{');
						s = va_var[vp++];   
						s->next = structs; 
						structs = s;
					}
					member(m,s);
					skip('}');
					return STRUCT | (s.addr<<TSHIFT);

  				case Enum:
					next();
					if (tk != '{') next();
					if (tk == '{') {
						next();
						m = 0;
						while (tk != null && tk != '}') {
							if (tk != Id) {err("bad enum identifier"); break; }
							n = id; // XXX redefinitions
							next();
							if (tk == Assign) { next(); m = imm(); }
							n.Class = Num;
							n.type = INT;
							n.val = m++;
							if (tk != Comma) break;
							next();
					  	}
					  	skip('}');
					}
					return INT;

  				case Id:
    				if (id.Class == Typedef) {
      					m = id.type; next();
      					return m;
    				}
  				default:
    				return 0;
  			}
		}

		function type(bt) {		// uint arg[1], ident_t arg[2],
			var t, v;
			var p, a, pt, d ; 	//uint p, a, pt, d; 
			var n;				//ident_t *n; 
			var ap;				//array_t *ap;
			
			while (tk == Mul) { next(); bt += PTR; }
  			if (tk == Paren) {
				next();
				if (tk == ')') {
					if (arguments[2] != null) err("bad abstract function type");
					next();
					arguments[1] |= FUN | (vp<<TSHIFT);
					va_var[vp].val = bt;
    				va_var[vp+1].addr = va_val[vp].addr+8;
					return vp++;
				}
				t = type(0, arguments);
				skip(')');
			} else if (tk == Id) { // type identifier
				if (arguments[2] != null) arguments[2] = id; else err("bad abstract type");
				next();
			}
			
			if (tk == Paren) { // function
    			next();
    			for (pt=p=0; tk != ')'; p++) {
      				n = 0;
      				if ((a = basetype()) != 0) {
        				if (tk == ')' && a == VOID) break;
        				d = 0;
        				type(a, d, n); // XXX should accept both arg/non arg if v == 0  XXX i.e. function declaration!
        				if (d == FLOAT) d = DOUBLE; // XXX not ANSI
      				} else if (tk == Id) { //ASSERT
        				d = INT;
        				n = id;
        				next();
      				} else {
        				err("bad function parameter");
        				next();
        				continue;
        			}
		  			if (n != null) {
		    			if (n.Class && n.local) err("duplicate definition");
		    			ploc_lstack[ploc].Class = n.Class; // XXX make sure these are unwound for abstract types and forward decls
		    			ploc_lstack[ploc].type = n.type;
		    			ploc_lstack[ploc].val = n.val;
		    			ploc_lstack[ploc].id = n;
		    			ploc += 1;
		    			if (arguments[2] == n) arguments[2] = ploc_lstack[ploc].id; // hack if function name same as parameter 
		    			if ((d & TMASK) == ARRAY) 
		    				d = va_var[d>>TSHIFT].type + PTR; // convert array to pointer
		    			n.local = 1;
		    			n.Class = Auto;
		    			n.type = d;
		    			n.val = p*8 + 8;
		    			if (bigend) {
		      				switch (d) {
		      					case CHAR: case UCHAR: n.val += 3; break;
		      					case SHORT: case USHORT: n.val += 2;
		      				}
		    			}
		  			}
      				pt |= (d == DOUBLE ? 1 : (d < UINT ? 2 : 3)) << p*2;
      				if (tk == Comma) next(); // XXX desparately need to flag an error if not a comma or close paren!
      				if (tk == Dots) { next(); if (tk != ')') err("expecting close parens after dots"); break; }
    			}
    			next(); // skip ')'
    			arguments[1] |= FUN | (vp<<TSHIFT);
    			va_var[vp].val = pt;
    			va_var[vp+1].addr = va_val[vp].addr+8;
    			vp += 1;
  			} else while (tk == Brak) { // array
    			next();
    			a = 0;
    			if (tk != ']') {
      				// XXX need constant in vc...not tree!  I think this is going go be a bug unless you push vs,ty
      				if ((a = imm()) < 0) err("bad array size");
    			}
    			skip(']');
    			arguments[1] |= ARRAY | (vp<<TSHIFT); 
    			va_var[vp].size = a;
    			va_var[vp+1].addr = va_var[vp].addr + SIZEOF_ARRAY_T;
    			t = vp++;
    		}
  			va_var[t].type += bt;
  			return t;
		}
	
		function member(stype) {  // struct_t arg[1]
			var size, align, ssize, salign;
			var bt, t;
			var v; // ident_v *v;
			var m, mp; // member_t *m ,**mp;
  
  			while (tk && tk != '}') {
				bt = basetype();
				if (bt == 0) bt = INT;
				if (tk == 0) break;
				if (tk == ';') { next(); continue; } // XXX
				for (;;) {
					t = 0; v = new Object();
				  	type(bt, t, v);
				  	if (v == null) 
				  		err("bad member declaration");
				  	else {
						for (mp = arguments[1].member; mp != null; mp = mp.next) 
							if (mp.id == v) err("duplicate member declaration");
						va_var[vp].id = v;
						va_var[vp].type = t;
						va_var[vp+1].addr = va_var[vp].addr + SIZEOF_MENBER_T;
						mp = vp;
						size = tsize(t);
						align = talign(t);
						if (stype == Struct) {
							va_var[mp].offset = (ssize + align - 1) & -align;
					  		ssize = (va_vap[mp].offset) + size;
					  	} else if (size > ssize)
					  		ssize = size;
				  		if (align > salign) salign = align;
				  	}
				  	if (tk != Comma) {
						skip(';');
						break;
				  	}
				  	next();
				}
			}
			s.align = salign;
			s.size = (ssize + salign - 1) & -salign;  
		}
		
		// expression parsing
		function node(n, a, b) {
			expr[e].value = n;
			expr[e].lChild = a;
			expr[e].rChild = b;
			expr[e+1].addr = expr[e].addr + 1;
			e += 1; 
		}
		function nodc(n, a, b) // commutative
		{
			expr[e].value = n;
			if (a.value < b.value) { 
				expr[e].lChild = b; 
				expr[e].rChild = a; 
			} else { 
				expr[e].lChild = a; 
				expr[e].rChild = b; 
			} // put simpler expression in rhs
			expr[e+1].addr = expr[e].addr + 1;
			e += 1;	
		}
		function unode(n) {
			expr[e].value = n;
			expr[e+1].addr = expr[e].addr+1;
			e += 1;
		}
		function mul(b) // XXX does this handle unsigned correctly?
		{
  			if (b.value == Num) {
    			if (expr[e-1].value == Num) { expr[e-1].rChild *= b.rChild; return; }
    			if (b.rChild == 1) return;
  			}
  			if (expr[e-1].value == Num && e.rChild == 1) { 
  				e = b.addr+1; return;
  			} // XXX reliable???
  			nodc(Mul,expr[e-1],b);
		}
		function add(b)  // XXX make sure to optimize (a + 9 + 2) -> (a + 11)    and    (a + 9 - 2) -> (a + 7)
		{
  			if (b.value == Num) {
    			if (expr[e-1].value == Num || expr[e-1].value == Lea || expr[e-1] == Leag) { 
    				expr[e-1].rChild += b[e-1].rChild; return; } // XXX  <<>> check
    			if (b.rChild == null) return;
  			}
  			if (expr[e-1].value == Num) {
    			if (b.value == Lea) { expr[e-1].rChild += b.rChild; expr[e-1].value = Lea; return; } // XXX structure offset optimizations
    			if (b.value == Leag) { expr[e-1].rChild += b.rChild; expr[e-1].value = Leag; return; }
    			if (expr[e-1].rChild == null) { e = b.addr+1; return; } // XXX reliable???
    		}
 			nodc(Add,b,expr[e-1]);
		}
		function flot(t) { // expr_tree arg[1] 
  			if (t == DOUBLE || t == FLOAT) 
  				return argument[1].addr;
  			if (arguments[1].value == Num) {
    			arguments[1].value = Numf;
    			arguments[1].rChild = Number(arguments[1].rChild);
    			return argument[1].addr;
    		}
    		expr[e].value = t < UINT ? Cid : Cud;
  			expr[e].lChild = (int)b;
  			expr[e].rChild = null;
  			expr[e+1].addr = expr[e].addr+1;
  			return e++;
  		}
  		function ind() {
  			if (ty & PMASK)
    			ty -= PTR;
  			else if (ty & ARRAY) {
    			ty = va_var[ty>>TSHIFT].type;
    			if ((ty & TMASK) == ARRAY) return; // was a ref, still a ref
  			} else
    			err("dereferencing a non-pointer");
  			if ((ty & TMASK) == FUN) return; // XXX
  			switch (expr[e-1].value) {
  				case Leag: expr[e-1].value = Static; expr[e-1].lChild = ty; return;
  				case Lea:  expr[e-1].value = Auto;   expr[e-1].lChild = ty; return;
  				default: expr[e].value = Ptr; expr[e] = ty; expr[e+1].addr = expr[e].addr+1; e+=1; return;
  			}
		}
		function addr() {
  			ty += PTR;
  			switch (expr[e-1].value) {
				case Fun: return; // XXX dont think ty is going to be right?
				case Leag: case Lea: return; // XXX
				case Static: expr[e-1].value = Leag; return;
				case Auto: expr[e-1].value = Lea; return;
				case Ptr: e -= 1; return;
				default: err("lvalue expected");
			}
		}
		function assign(n, b) {
  			expr[e].value = n; 
  			expr[e].rChild = b; 
  			expr[e+1].addr = expr[e].addr+1;
  			e += 1;
  			switch (ty) { // post-cast usually removed by trim()
  				case CHAR:   unode(Cic); break;
 	 			case UCHAR:  unode(Cuc); break;
  				case SHORT:  unode(Cis); break;
  				case USHORT: unode(Cus); break;
  			}
  		}
  		function trim() // trim dead code from expression statements (just the common cases)
		{
  			if (expr[e-1].value >= Cic && expr[e-1].value <= Cus) 
  				e -= 1;
  			if (expr[e-1].value == Add && expr[e-1].rChild.value == Num) 
  				e = e.lChild.addr+1; // convert x++ into ++x
		}
		
		function cast(t) {
			if (t == DOUBLE || t == FLOAT) {
				if (ty < UINT) {
					if (expr[e-1].value == Num) {
						expr[e-1].value = Numf;
						ep = expr[e-1].rChild.addr;
						expr[ep].rChild.value = Number(expr[ep].rChild.value);
					} else {
						expr[e].value = Cid;
						expr[e].lChild = expr[e-1];
						expr[e+1].addr=expr[e].addr+1;
						e+=1;
					}
				else if (ty != DOUBLE && ty != FLOAT) {
					if (expr[e-1].value == Num) {
						expr[e-1].value = Numf;
						ep = expr[e-1].rChild.addr;
						expr[ep].rChild.value = Number(expr[ep].rChild.value);
					} else {
						expr[e].value = Cud;
						expr[e].lChild = expr[e-1];
						expr[e+1].addr=expr[e].addr+1;
						e+=1;
					}
				}
			} else if (t < UINT) {
				if (ty == DOUBLE || ty == FLOAT) 
					if (expr[e-1].value == Numf) {
						expr[e-1].value = Num; expr[e-1].lChild = ParseInt(expr[e-1].lChild);
					} else 
						unode(cdi);
				switch (t) {
					case CHAR:   if (expr[e-1].value == Num) expr[e-1].rChild = toChar(expr[e-1].rChild);  else unode(Cic); break;
					case UCHAR:  if (expr[e-1].value == Num) expr[e-1].rChild = toUChar(expr[e-1].rChild); else unode(Cuc); break;
					case SHORT:  if (expr[e-1].value == Num) expr[e-1].rChild = toShort(expr[e-1].rChild); else unode(Cis); break;	
					case USHORT: if (expr[e-1].value == Num) expr[e-1].rChild = toUShort(expr[e-1].rChild);else unode(Cus); break;
				}
			} else if (ty == DOUBLE || ty == FLOAT) {
				if (expr[e-1].value == Numf) {
					expr[e-1].value = Num;
					expr[e-1].rChild = toUint(expr[e-1].rChild);
				} else unode(Cdu);
			}
		}
		
		void expr(lev) {
  			int *b, *d, *dd; uint t, tt; member_t *m;

  			switch (tk) {
  				case Num:
					expr[e].value = Num;
					expr[e].rChild = ival;
					expr[e+1].addr = expr[e].addr+1;
					e += 1;
					next();
					break;
				case Numf:
					expr[e].value = Numf;
					expr[e].rChild = fval;
					expr[e+1].addr = expr[e].addr+1;
					e += 1;
					next();
					break;
				case '"':
					ty = PTR | CHAR;
					expr[e].value = Leag;
					expr[e].rChild = ival;
					expr[e+1].addr = expr[e].addr+1;
					e += 1;
					next();
					while (tk == '"') next();
					data+=;
					break;
				case Id:
					if (id.Class != null) {
						node(id.Class, id.type, (id.Class == FFun) ? id : id.val);
						next();
						break;
					}
					id.Class = FFun;
					ffun += 1;
					ty = id.type = FUN | (vp<<TSHIFT);
					va_val[vp].value = INT;
					va_val[vp+1].addr = va_val[vp].addr + 8;
					vp += 1;
					node(FFunl, 0, id);
					next();
					if (tk != Paren) 
						err("undefined symbol");
					else if (verbose)
						print(sprintf("%s : [%s:%d] warning: undeclared function called here\n", cmd, file, line));
					break;
				case Va_arg: // va_arg(list,mode) *(mode *)(list += 8)
    				next();
					skip(Paren);
					expr(Assign);
					skip(Comma);
					b = e; 
					expr[e].value = Num;
					expr[e].rChild = 8;
					expr[e+1].value = Adda;
					expr[e+1].lChild = b;
					expr[e+1].addr = expr[e].addr+1;
					expr[e+2].addr = expr[e+1].addr+1;
					e += 2;
					tt = basetype() ;
					if (tt == 0) {
						err("bad_va_arg"); tt = INT;}
					t = 0;
					type(tt, t, null);
					skip(')');
					ty = t + PTR;
					ind();
					break;
				case Paren:
					next();
					tt = basetype();
					if (tt == 0) {
						t = 0;
						type(tt, t, null);
						skip(')');
						expr(Inc);
						cast(t);
						ty = t;
						break;
					}
					expr(Comma);
					skip(')');
					break;
				case '"':
					ty = PTR | CHAR;
					expr[e].value = Leag;
					expr[e].rChild = ival;
					expr[e+1].addr = expr[e].addr + 1;
					e += 1;
					next();
					while (tk == '"') next();
					data++;
					break;
				case Id:
					if (id.Class != null) {
						node(id.Class, ty = id.type, (id.Class == FFun) ? id : id.val);
						next();
						break;
					}
					id.Class = FFun; ffun++;
					ty = id->type | (vp<<TSHIFT);
					va_var[vp].value = INT;
					va_var[vp+1].addr = va_var[vp].addr+1;
					vp += 1;
					node(FFun, 0, id);
					next();
					if (tk != Paren) 
						err("undefined symbol");
					else if (verbose)
						print(sprintf("%s : [%s:%d] warning: undeclared function called here\n", cmd, file, line));
					break;
				case Va_arg: // va_arg(list,mode) *(mode *)(list += 8)
					next();
					skip(Paren);
					expr(Assign);
					skip(Comma);
					b = e-1;
					expr[e].value = Num;
					expr[e].rChild = 8;
					expr[e+1].value = Adda;
					expr[e].lChild = expr[b];
					expr[e+1].addr = expr[e].addr+1;
					expr[e+2].addr = expr[e+1].addr+1;
					e += 2;
					tt = basetype();
					if (tt == 0) {
						err("bad va_arg"); tt = INT;
					}
					t = 0;
					type(tt, t, null);
					skip(')');
					ty = t + PTR;
					ind();
					break;
				case Paren:
					next();
					tt = basetype();
					if (tt != 0) {
						t = 0;
						type(tt, t, null);
						skip(')');
						expr(Inc);
						cast(t);
						ty = t;
						break;
					}
					expr(Comma);
					skip(')');
					break;
				case Mul:
					next(); expr(Inc); ind();
				case And:
					next(); expr(Inc); ind();
				case '!':
					next(); expr(Inc);
					switch (expr[e-1].value) {
						case Eq:  expr[e-1].value = Ne;  break;
						case Ne:  expr[e-1].value = Eq;  break;
						case Lt:  expr[e-1].value = Ge;  break;
						case Ge:  expr[e-1].value = Lt;  break;
						case Ltu: expr[e-1].value = Geu; break;
						case Geu: expr[e-1].value = Ltu; break;
						case Eqf: expr[e-1].value = Nef; break;
						case Nef: expr[e-1].value = Eqf; break;
						case Ltf: expr[e-1].value = Gef; break;
						case Gef: expr[e-1].value = Ltf; break;
						default:
							if (ty < FLOAT || (ty & PMASK)) unode(Not);
					   else if (ty >= STRUCT) err("bas operand to !");
					   else unode(Notf);
					   		ty = INT;
					}
					break;
				case '~':
					next(); expr(Inc);
					if (ty >= FLOAT) 
						err("bad operand to ~");
					else {
						if (expr[e-1].value == Num)
							expr[e-1].rChild = ~expr[e-1].rChild;
						else {
							expr[e].value = Num;
							expr[e].rChild = -1;
							expr[e+1].addr = expr[e].addr+1;
							e += 1;
							nodc(Xor, expr[e-1], expr[e]);
						} 
						ty = ty < UINT ? INT : UINT;
					}
					break;
				case Add:
					next(); expr(Inc);
					if (ty >= STRUCT) err("bad operand to +");
					break;
				case Sub:
					next(); expr(Inc);
					if (ty >= STRUCT) err("bad operand to -");
			   else if ((ty & FLOAT) != 0) {
			   			if (expr[e-1].value == Numf)
			   				expr[e-1].rChild = -1.0;
			   			else {
			   				expr[e].value = Numf;
			   				expr[e].rChild = -1.0;
			   				expr[e+1].addr = expr[e].addr+1;
			   				e += 1;
			   				nodc(Mulf, e-1, e);
			   			}
			   			ty = DOUBLE;
			   		} else {
			   			if (expr[e-1].value == Num) 
			   				expr[e-1].rChild *= -1;
			   			else {
			   				expr[e].value = Numf;
			   				expr[e].rChild = -1.0;
			   				expr[e+1].addr = expr[e].addr+1;
			   				e += 1;
			   				nodc(Mul, e-1, e);
			   			}
			   			ty = ty < UINT ? INT : UINT;
			   		}
			   		break;
			   	case Inc:
			   		next(); expr(Inc);
			   		if (!(ty & PMASK) && ty >= FLOAT)
			   			err("bad operand to ++");
			   		else {
			   			expr[e].value = Num;
			   			expr[e].rChild = tinc(ty);
			   			expr[e+1].addr = expr[e].addr + 1;
			   			e += 1;
			   			assign(Adda, e-1);
			   		}
			   		break;
			   	case Dec:
			   		next(); expr(Inc);
			   		if (!(ty & PMASK) && ty >= FLOAT)
			   			err("bad operand to --");
			   		else {
			   			expr[e].value = Num;
			   			expr[e].rChild = tinc(ty);
			   			expr[e+1].addr = expr[e].addr + 1;
			   			e += 1;
			   			assign(Suba, e-1);
			   		}
			   		break;
			   	case Sizeof:
			   		next();
			   		if ((t = tk) == Paren) next();
			   		tt = basetype();
			   		if (tt != 0) {
			   			ty = 0; type(tt, ty, null);
			   		} else {
			   			b = e; expr(Dot); e = b;
			   		}
			   		expr[e].value = Num;
			   		expr[e].rChild = tsize(ty);
			   		expr[e+1].addr = expr[e].addr+1;
			   		e += 1;
			   		ty = INT;
			   		if (t != 0) skip(')');
			   		break;
			   	default:
			   		next();
			   		err("bad expression");
			   		return;
			}
			while (tk >= lev) {
    			b = e-1; t = ty;
    			switch (tk) {
    				case Comma: 
    					trim(); 
    					b = e-1; 
    					next(); 
    					expr(Assign); 
    					expr[e].value = Comma;
    					expr[e].lChild = expr[b];
    					expr[e+1].addr = expr[e].addr+1;
    					e += 1;
    					continue;
    				case Assign: 
    					next(); 
    					expr(Assign); 
    					cast(t < UINT ? INT : t); 
    					ty = t; 
    					assign(Assign,b); 
    					continue;
					case Adda:
						next(); 
						expr(Assign);
						if ((t & PAMASK) && ty <= UINT) { 
							if ((tt = tinc(t)) > 1) { 
								expr[e].value = Num;
								expr[e].rChild = tt;
								expr[e+1].addr = expr[e].addr+1;
								e += 1; mul(expr[e-1]);
							}
							ty = t;
							assign(Adda, expr[b]);
						} else if ((tt = t|ty) >= STRUCT)
							err("bad operands to +=");
						else if (tt & FLOAT) {
							e = flot(expr[e-1], ty);
							ty = t;
							assign(Addaf, expr[b-1]);
						} else {
							ty = t;
							assign(Adda, expr[b-1]);
						}
						continue;
					case Suba:
						next();
						expr(Assign);
						if ((t & PAMASK) && ty <= UINT) {
							if ((tt = tinc(t)) > 1) { 
								expr[e].value = Num;
								expr[e].rChild = tt;
								expr[e+1].addr = expr[e].addr+1;
								e += 1; mul(expr[e-1]);
							}
							ty = t;
							assign(Suba, expr[b]);
						} else if ((tt = t|ty) >= STRUCT)
							err("bad operands to -=");
						else if (tt & FLOAT) {
							e = flot(expr[e-1], ty);
							ty = t;
							assign(Subaf, expr[b-1]);
						} else {
							ty = t;
							assign(Suba, expr[b-1]);
						}
						continue;
					case Mula:
						next();
						expr(Assign);
						if ((tt = t|ty) >= STRUCT)
							err("bad operands to *=");
						else if (tt & FLOAT) {
							e = flot(expr[e-1], ty);
							ty = t;
							assign(Mulaf, expr[b-1]);
						} else {
							ty = t;
							assign(Mula, expr[b-1]);
						}
						continue;
					case Diva:
						next();
						expr(Assign);
						if ((tt = t|ty) >= STRUCT)
							err("bad operands to /=");
						else if (tt & FLOAT) {
							e = flot(expr[e-1], ty);
							ty = t;
							assign(Divaf, expr[b-1]);
						} else {
							ty = t;
							assign((tt & UINT) ? Dvua : Diva, expr[b-1]);
						}
						continue;
					case Moda:
						next();
						expr(Assign);
						if ((tt = t|ty) >= STRUCT)
							err("bad operands to %=");
						else {
							ty = t;
							assign((tt & UINT) ? Mdua : Moda, expr[b-1]);
						}
						continue;
					case Anda:
						next();
						expr(Assign);
						if ((tt = t|ty) >= STRUCT)
							err("bad operands to &=");
						else {
							ty = t;
							assign(Anda, expr[b-1]);
						}
						continue;
					case Ora:
						next();
						expr(Assign);
						if ((tt = t|ty) >= STRUCT)
							err("bad operands to |=");
						else {
							ty = t;
							assign(Ora, expr[b-1]);
						}
						continue;
					case Xora:
						next();
						expr(Assign);
						if ((tt = t|ty) >= STRUCT)
							err("bad operands to ^=");
						else {
							ty = t;
							assign(Xora, expr[b-1]);
						}
						continue;
      				case Shla:
      					next();
						expr(Assign);
						if ((tt = t|ty) >= STRUCT)
							err("bad operands to <<=");
						else {
							ty = t;
							assign(Shla, expr[b-1]);
						}
						continue;
					case Shra:
      					next();
						expr(Assign);
						if ((tt = t|ty) >= STRUCT)
							err("bad operands to >>=");
						else {
							ty = t;
							assign(Shra, expr[b-1]);
						}
						continue;
					case Cond:
						if (ty == DOUBLE || ty == FLOAT) {
							b = e; unode(Nzf);
						}
						next();
						expr(Comma);
						d = e-1; 
						t = ty; 
						skip(':'); 
						expr(Cond);
						dd = e-1;
						if (((ty & PAMASK) && ((t & PAMASK) || t <= UINT)) == 0) {
							if ((t & PAMASK) != 0 && ty <= UINT) ty = t;
					   else if ((tt = t|ty) >= STRUCT) err("bad conditional expression types");
					   else if ((tt & FLOAT) != 0) {
					   			dd = flot(dd, ty);
					   			d = flot(d, t);
					   			ty = DOUBLE;
					   		} else {
					   			ty = (tt & UINT) ? UINT : INT;
					   		}
					   	}
					   	node(Cond, expr[b], expr[d]);
					   	expr[e-1].value3 = expr[dd];
					   	continue;
					case Lor:
      					if (ty == DOUBLE || ty == FLOAT) {
      						 b = e; unode(Nzf);
      					}
      					next(); expr(Lan);
      					if (ty == DOUBLE || ty == FLOAT) 
      						unode(Nzf);
      					expr[e].value = Lor;
      					expr[e].lChild = expr[b];
      					expr[e+1].addr = expr[e].addr+1;
      					e += 1; ty = INT;
      					continue;
      				case Lan:
      					if (ty == DOUBLE || ty == FLOAT) {
      						 b = e; unode(Nzf);
      					}
      					next(); expr(Or);
      					if (ty == DOUBLE || ty == FLOAT) 
      						unode(Nzf);
      					expr[e].value = Lan;
      					expr[e].lChild = expr[b];
      					expr[e+1].addr = expr[e].addr+1;
      					e += 1; ty = INT;
      					continue;
      				case Or:
      					next(); expr(Xor);
      					if ((tt = t|ty) >= FLOAT) 
      						err("bad operands to |");
      					else {
      						if (expr[b].value == Num && expr[e-1].value == Num)
      							expr[e-1].rChild |= expr[b].rChild;
      						else
      							nodc(Or, expr[b], expr[e-1]);
      						ty = ((tt & UINT) != 0) ? UINT : INT; 
      					}
      					continue;
      				case Xor:
      					next(); expr(And);
      					if ((tt=t|ty) >= FLOAT)
      						err("bad operands to ^");
      					else {
      						if (expr[b].value == Num && expr[e-1].value == Num)
      							expr[e-1].rChild |= expr[b].rChild;
      						else
      							nodc(Xor, expr[b], expr[e-1]);
      						ty = ((tt & UINT) != 0) ? UINT : INT;
      					}
      					continue;
      				case And:
      					next(); expr(Eq);
      					if ((tt=t|ty) >= FLOAT)
      						err("bad operands to &");
      					else {
      						if (expr[b].value == Num && expr[e-1].value == Num)
      							expr[e-1].rChild |= expr[b].rChild;
      						else
      							nodc(And, expr[b], expr[e-1]);
      						ty = ((tt & UINT) != 0) ? UINT : INT;
      					}
      					continue;
      				case Eq:
      					next(); expr(Lt);
      					if ((t < FLOAT || (t & PAMASK) != 0) && (ty < FLOAT || (ty & PAMASK) != 0)) { 
      						if (expr[b].value == Num && expr[e-1].value == Num) 
      							expr[e-1].rChild = (expr[b].rChild == expr[e-1].rChild); 
      						else 
      							nodc(Eq, expr[b], expr[e-1]); 
      					} else if ((tt=t|ty) >= STRUCT) 
      						err("bad operands to ==");
		  				else if (tt & FLOAT) {
		    				d = flot(e,ty); 
		    				b = flot(b,t);
		    				if (expr[b].value == Numf && expr[d].value == Numf) { 
		    					expr[e-1].value = Num; 
		    					expr[e-1].rChild = (Number(expr[b].rChild) == Number(expr[d].rChild));
		    				} else 
		    					nodc(Eqf, expr[b], expr[d]);
		    			} else {
		    				if (expr[b].value == Num && expr[e-1].value == Num) 
		  						expr[e-1].rChild = (expr[b].rChild == expr[e-1].rChild);
		  					else
		  						nodc(Eq, expr[b], expr[e-1]);
		    			}
		    			ty = INT;
		    			continue;
		    			
		    		case Ne:
		    			next(); expr(Lt);
		    			if ((t < FLOAT || (t & PAMASK) != 0) && (ty < FLOAT || (ty & PAMASK) != 0)) { 
      						if (expr[b].value == Num && expr[e-1].value == Num) 
      							expr[e-1].rChild = (expr[b].rChild == expr[e-1].rChild); 
      						else 
      							nodc(Ne, expr[b], expr[e-1]); 
      					} else if ((tt=t|ty) >= STRUCT) 
      						err("bad operands to !=");
		  				else if (tt & FLOAT) {
		    				d = flot(e,ty); 
		    				b = flot(b,t);
		    				if (expr[b].value == Numf && expr[d].value == Numf) { 
		    					expr[e-1].value = Num; 
		    					expr[e-1].rChild = (Number(expr[b].rChild) == Number(expr[d].rChild));
		    				} else 
		    					nodc(Nef, expr[b], expr[d]);
		    			} else {
		    				if (expr[b].value == Num && expr[e-1].value == Num) 
		  						expr[e-1].rChild = (expr[b].rChild == expr[e-1].rChild);
		  					else
		  						nodc(Ne, expr[b], expr[e-1]);
		    			}
		    			ty = INT;
		    			continue;
		    		
		    		case Lt:
		    			next(); expr(Shl);
		    			if ((t < FLOAT || (t & PAMASK) != 0) && (ty < FLOAT || (ty & PAMASK) != 0)) { 
      						if (expr[b].value == Num && expr[e-1].value == Num) 
      							expr[e-1].rChild = (expr[b].rChild < expr[e-1].rChild); 
      						else 
      							nodc(Ltu, expr[b], expr[e-1]); 
      					} else if ((tt=t|ty) >= STRUCT) 
      						err("bad operands to <");
		  				else if (tt & FLOAT) {
		    				d = flot(e,ty); 
		    				b = flot(b,t);
		    				if (expr[b].value == Numf && expr[d].value == Numf) { 
		    					expr[e-1].value = Num; 
		    					expr[e-1].rChild = (Number(expr[b].rChild) < Number(expr[d].rChild));
		    				} else 
		    					nodc(Ltf, expr[b], expr[d]);
		    			} else if (tt & UINT) {
		    				if (expr[b].value == Num && expr[e-1].value == Num) 
		    					expr[e-1].rChild = (expr[b].rChild < expr[e-1].rChild ? 1 : 0);
		    				else
		    					node(Ltu, expr[b], expr[e-1]);
		    			} else {
		    				if (expr[b].value == Num && expr[e-1].value == Num) 
		    					expr[e-1].rChild = (expr[b].rChild < expr[e-1].rChild ? 1 : 0);
		    				else
		    					node(Lt, expr[b], expr[e-1]);
		    			}
		    			ty = INT;
		    			continue;
		    		
		    		case Gt: 
		    			next(); expr(Shl);
		    			if ((t < FLOAT || (t & PAMASK) != 0) && (ty < FLOAT || (ty & PAMASK) != 0)) { 
      						if (expr[b].value == Num && expr[e-1].value == Num) 
      							expr[e-1].rChild = (expr[b].rChild > expr[e-1].rChild); 
      						else 
      							nodc(Ltu, expr[e-1], expr[b]); 
      					} else if ((tt=t|ty) >= STRUCT) 
      						err("bad operands to >");
		  				else if (tt & FLOAT) {
		    				d = flot(e,ty); 
		    				b = flot(b,t);
		    				if (expr[b].value == Numf && expr[d].value == Numf) { 
		    					expr[e-1].value = Num; 
		    					expr[e-1].rChild = (Number(expr[b].rChild) > Number(expr[d].rChild));
		    				} else 
		    					nodc(Ltf, expr[d], expr[b]);
		    			} else if (tt & UINT) {
		    				if (expr[b].value == Num && expr[e-1].value == Num) 
		    					expr[e-1].rChild = (expr[b].rChild < expr[e-1].rChild ? 1 : 0);
		    				else
		    					node(Ltu, expr[e-1], expr[b]);
		    			} else {
		    				if (expr[b].value == Num && expr[e-1].value == Num) 
		    					expr[e-1].rChild = (expr[b].rChild < expr[e-1].rChild ? 1 : 0);
		    				else
		    					node(Lt, expr[e-1], expr[b]);
		    			}
		    			ty = INT;
		    			continue;

					case Shl:
      					next(); expr(Add);
      					if ((tt=t|ty) >= FLOAT) 
      						err("bad operands to <<");
      					else { 
      						if (expr[b].value == Num && expr[e-1].value == Num) 
      							expr[e-1].rChild = (expr[b].rChild << expr[e-1].rChild);
      						else
      							node(Shl, expr[b], expr[e-1]);
      						ty = (tt & UINT) ? UINT : INT;
      					}
      					continue;

					case Shr:
      					next(); expr(Add);
      					if ((tt=t|ty) >= FLOAT) 
      						err("bad operands to >>");
      					else if ((tt & UINT) != 0) {
      						if (expr[b].value == Num && expr[e-1].value == Num)
      							expr[e-1].rChild = (expr[b].rChild >> expr[e-1].rChild);
      						else
      							node(Sru, expr[b], expr[e-1]);
      						ty = UINT;
      					} else { 
      						if (expr[b].value == Num && expr[e-1].value == Num) 
      							expr[e-1].rChild = (expr[b].rChild >> expr[e-1].rChild);
      						else
      							node(Shr, expr[b], expr[e-1]);
      						ty = (tt & UINT) ? UINT : INT;
      					}
      					continue;
					
					case Add:
						next(); expr(Mul);
						if ((t & PAMASK) != 0 && t <= UINT) {
							if ((tt = tinc(t) > 1) {
								expr[e].value = Num;
								expr[e].rChild = tt;
								expr[e+1].addr = expr[e].addr + 1;
								e += 1; mul(expr[e-2]);
							}
							add(expr[b]); ty = t;
						} else if ((ty & PAMASK) != 0 && t <= UINT) {
							if ((tt = tinc(ty)) > 1) {
								d = e - 1;
								expr[e].value = Num;
								expr[e].rChild = tt;
								expr[e+1].addr = expr[e].addr + 1;
								e += 1; mul(expr[b]); add(expr[d]);
							} else
								add(expr[b]);
						} else if ((tt = t|ty) >= STRUCT)
							err("bad operands to +");
						else if (tt && FLOAT) {
							d = flot(expr[e-1], ty);
							b = flot(expr[b], t);
							if (expr[b] == Numf && expr[d] == Numf) {
								expr[e-1].value = Numf;
								expr[e-1].rChild = Number(expr[b].rChild) + Number(expr[d].rChild);
							} else
								nodc(Addf, expr[b], expr[d]);
							ty = DOUBLE;
						} else {
							add(expr[b]);
							ty = (tt & UINT) ? UINT : INT;
						}
						continue;
						
					case Sub:
						next(); expr(Mul);
						if ((t & PAMASK) != 0 && (ty & PAMASK) != 0 && (tt = tinc(t)) == tinc(ty)) {
							node(Sub, expr[b], expr[e-1]);
							d = e - 1;
							expr[e].value = Num;
							expr[e].rChild = tt;
							expr[e+1].addr = expr[e].addr + 1;
							e += 1;
							node(Div, expr[d]. expr[e-1]);
							ty = INT;
						} else if ((t & PAMASK) != 0 && ty <= UINT) {
							if ((tt = tinc(t)) > 1) {
								expr[e].value = Num;
								expr[e].rChild = tt;
								expr[e+1].addr = expr[e].addr + 1;
								e += 1;
								mul(expr[e-2]);
							}
							if (expr[e-1].value == Num) {
								expr[e-1].rChild *= -1;
								add(expr[b]);
							} else
								node(Sub, expr[b], expr[e-1]);
							ty = t;
						} else if ((tt=t|ty) >= STRUCT)
							err("bad operands to -");
						else if (tt & FLOAT) {
							d = flot(expr[e-1], ty);
							b = flot(expr[b], t);
							if (expr[b].value == Numf && expr[d].value == Numf) {
								expr[e-1].value = Numf;
								expr[e-1].rChild = Number(expr[b].rChild) - Number(expr[d].rChild);
							} else node(Subf, expr[b], expr[d]);
							ty = DOUBLE;
						} else {
							if (expr[e-1].value == Num) {
								expr[e-1].rChild *= -1;
								add(expr[b]);
							} else
								node(Sub, expr[b], expr[e-1]);
							ty = (tt & UINT) ? UINT : INT;
						}
						continue;
						
					case Mul:
      					next(); expr(Inc);
      					if ((tt=t|ty) >= STRUCT) 
      						err("bad operands to *");
      					else if ((tt & FLOAT) != 0) {
        					d = flot(expr[e-1], ty); 
        					b = flot(expr[b], t);
        					if (expr[b].value == Numf && expr[d].value == Numf) {
          						expr[e-1].value = Numf; 
          						expr[e-1].rChild = Number(expr[b].rChild) & Number(expr[d].rChild);
          					} else 
          						nodc(Mulf, expr[b], expr[d]);
          					ty = DOUBLE;
          				} else {
          					mul(expr[b]);
          					ty = (tt & UINT) ? UINT : INT;
          				}
          				continue;
          				
          			case Div:
          				next(); expr(Inc);
          				if ((tt=t|ty) >= STRUCT) 
      						err("bad operands to /");
      					else if ((tt & FLOAT) != 0) {
        					d = flot(expr[e-1], ty); 
        					b = flot(expr[b], t);
        					if (expr[b].value == Numf && expr[d].value == Numf) {
          						expr[e-1].value = Numf; 
          						expr[e-1].rChild = Number(expr[b].rChild) / Number(expr[d].rChild);
          					} else 
          						nodc(Divf, expr[b], expr[d]);
          					ty = DOUBLE;
          				} else if ((tt & UINT) != 0) {
          					if (expr[b].value == Num && expr[e-1].value == Num && expr[e-1].rChild != 0) 
          						expr[e-1].rChild = expr[b].rChild / expr[e-1].rChild;
          					else
          						node(Dvu, expr[e], expr[e-1]);
          					ty = UINT;
          				} else {
          					mul(expr[b]);
          					ty = INT;
          				}
          				continue;
          				
          			case Mod:
						next(); expr(Inc);
						if ((tt=t|ty) >= FLOAT) 
					  		err("bad operands to %");
					  	else if ((tt & UINT) != 0) { 
					  		if (expr[b].value == Num && expr[e-1].value == Num && expr[e-1].rChild != 0) 
					  			expr[e-1].rChild = expr[b].rChild % expr[e-1].rChild; 
					  		else 
					  			node(Mdu, expr[b], expr[e-1]); 
					  		ty = UINT; 
					  	} else { 
					  		if (expr[b].value == Num && expr[e-1].value == Num && expr[e-1].rChild != 0) 
					  			expr[e-1].rChild = expr[b].rChild % expr[e-1].rChild; 
					  		else 
					  			node(Mod, expr[b], expr[e-1]); 
					  		ty = INT; 
					  	}
					 	continue;

    				case Inc:
						next();
					  	if ((ty & PMASK) == 0 && ty >= FLOAT) 
					  		err("bad operand to ++"); // XXX doesn't support floats
					  	else { 
					  		expr[e].value = Num;
					  		expr[e].rChild = -tinc(ty);
					  		expr[e+1].addr = expr[e].addr + 1;
					  		expr[++e].value = Suba;
					  		expr[e].lChild = expr[b];
					  		expr[e+1].addr = expr[e].addr + 1;
					  		e += 1; add(expr[e-2]);
					  	}
					  	continue;
		
					case Dec:
						next();
					  	if ((ty & PMASK) == 0 && ty >= FLOAT) 
					  		err("bad operand to --"); // XXX doesn't support floats
					  	else { 
					  		expr[e].value = Num;
					  		expr[e].rChild = tinc(ty);
					  		expr[e+1].addr = expr[e].addr + 1;
					  		expr[++e].value = Suba;
					  		expr[e].lChild = expr[b];
					  		expr[e+1].addr = expr[e].addr + 1;
					  		e += 1; add(expr[e-2]);
						}
					  	continue;
					  	
					case Dot: // XXX do some optimization for x.y on stack or global, then work on x.y.z (cause it wont be done in rval or lval)
      					addr(); //  a.b --> (&a)->b --> *((&a) + b)
    				case Arrow:
						if ((ty & TMASK) != (STRUCT | PTR)) 
							err("expected structure or union");
						next();
						if (tk != Id) { 
							err("expected structure or union member"); 
							continue; 
						}
						var found = false;
						for (m = va_var[ty>>TSHIFT].member; m != null; m = m.next) 
							if (m.id == id) found = true;
						if (found == false) { 
							err("struct or union member not found");
							next();
							continue;
						}
						expr[e].value = Num;
						expr[e].rChild = m.offset;
						expr[e+1].addr = expr[e].addr + 1;
						e += 1; add(expr[e-2]);
						if ((m.type & TMASK) == ARRAY)
							ty = m.type;
						else {
							ty = m->type + PTR; 
							ind(); 
						}      
      					next();
      					continue;
		
    				case Brak: // XXX these dont quite work when used with pointers?  still? test?
      					next();  // addr(); b = e; t = ty; // XXX
						expr(Comma);
						skip(']');
						d = e-1;
						expr[e].value = Num;
						expr[e].rChild = tinc(t);
						mul(expr[d]);
						add(expr[b]);
						ty = t;
						ind();
						continue;

					case Paren: // function call
						if ((ty & TMASK) != FUN && (ty & TMASK) != (PTR|FUN)) 
					  		err("bad function call type");
					  	else { 
					  		t = va_var[ty>>TSHIFT].value; 
					  		tt = va_var[(ty>>TSHIFT)+1].value; 
					  	}
						next();
					  	d = e-1;
					  	b = 0;
					  	while (tk != ')') {
							expr(Assign);
							switch (tt & 3) {
								case 1: cast(DOUBLE); ty = DOUBLE; break;
								case 2: cast(INT); 	  ty = INT; break;
								case 3: cast(UINT);   ty = UINT;
							}
							tt >>= 2;
							expr[e].value = b;
							expr[e].lChild = ty;
							expr[e+1].addr = expr[e].addr + 1;
							b = e++;
							if (tk == Comma) next();
					  	}
					  	skip(')');
					  	node(Fcall, expr[d], expr[b]);
					  	ty = t;
					  	continue;
					  	
					 default:
      					print(sprintf("fatal compiler error expr() tk=%d\n", tk)); 
      					return -1;
    			}
  			}
  		}
  		
  		// expression generation
		function lmod(t) {
		  switch (t) {
			  default: if ((t & PMASK) == 0 && (t & TMASK) != FUN) 
			  				err("can't dereference that type");
			  case INT:
			  case UINT:   return 0; 
			  case SHORT:  return LLS - LL;
			  case USHORT: return LLH - LL; 
			  case CHAR:   return LLC - LL;
			  case UCHAR:  return LLB - LL; 
			  case DOUBLE: return LLD - LL;
			  case FLOAT:  return LLF - LL;
		  }
		}

		function smod(t) {
		  switch (t) {
			  default: if ((t & PMASK) == 0) 
			  		err("can't dereference that type");
			  case INT:
			  case UINT:   return 0; 
			  case SHORT:
			  case USHORT: return SLH - SL;
			  case CHAR:
			  case UCHAR:  return SLB - SL;
			  case DOUBLE: return SLD - SL;
			  case FLOAT:  return SLF - SL;
		  }
		}
		
		function lbf(b) {
  			var d = null; // double d;
  			switch (b.value) {
  				case Auto: eml(LBL+lmod(b.lChild), b.rChild); return;
  				case Static: emg(LBG+lmod(b.lChild), b.rChild); return;
  				case Numf:
					d = Number(b.rChild);
					if ((parseInt(d*256.0)<<8>>8)/256.0 == d) 
						emi(LBIF, d*256.0);
					else { 
						data = (data+7)&-8; 
						gs_seg[data].value = d;
						emg(LBGD, data);
						gs_seg[data+1].addr = gs_seg[data].addr + 8;
						data += 1;
					}
					return;
				default: 
					rv(b); em(LBAD); 
					return;
			}
		}

		function opf(a) {
  			var b = a.rChild;
			switch (b.value) {
				case Auto:
				case Static:
				case Numf: 
					rv(a.lChild); 
					lbf(b); 
					return;
			  	default:
					rv(b);
					a = a.lChild;
					switch (a.value) {
						case Auto:
						case Static:
						case Numf: 
							em(LBAD); 
							rv(a); 
							return;
						default: 
							loc -= 8; 
							em(PSHF); 
							rv(a); 
							em(POPG); 
							loc += 8; 
							return;
					}
			}
		}
		
		function opaf(a, o, comm) {
  			var t ;
  			var b = a.rChild;
  			a = a.lChild;
  			t = (a.lChild == FLOAT || a.lChild == DOUBLE);	// XXX need more testing before confident
  			switch (a.value) {
  				case Auto: // loc fop= expr
					if (comm != 0 && t != 0) { 
						rv(b); 
						eml(LBL+lmod(a.lChild), a.rChild); 
					} else { 
						lbf(b); 
						eml(LL+lmod(a.lChild),a.rChild); 
						if (t == 0) em(a.lChild < UINT ? CID : CUD); 
					}
					em(o); 
					if (t == 0) em(a.lChild < UINT ? CDI : CDU); 
					eml(SL+smod(a.lChild),a.rChild);
					return 0;
				case Static: // glo fop= expr  
					if (comm != 0 && t != 0) { 
						rv(b); 
						emg(LBG+lmod(a.lChild),a.rChild); 
					} else { 
						lbf(b); 
						emg(LG+lmod(a.lChild), a.rChild); 
						if (t == 0) em(a.lChild < UINT ? CID : CUD); 
					}
					em(o); 
					if (t == 0) em(a[1] < UINT ? CDI : CDU); 
					emg(SG+smod(a.lChild), a.rChild);
					return 0;
				case Ptr:
					switch (b.value) {
						case Auto:
						case Static:
						case Numf: rv(expr[a.addr-1]); lbf(b); loc -= 8; break; // *expr fop= simple
						default: rv(b); loc -= 8; em(PSHF); rv(expr[a.addr-1]); em(POPG); break; // *expr fop= expr
					}
					em(PSHA); em(LX+lmod(a.lChild));
					if (t == 0) em(a.lChild < UINT ? CID : CUD);
					em(o); em(POPB); loc += 8; 
					if (t == 0) em(a.lChild < UINT ? CDI : CDU); 
					em(SX+smod(a.lChild));
					return 0;
				default: err("lvalue expected");
			}
		}
		
		function lbi(i) { 
			if (((i<<8)>>8) == i) 
				emi(LBI,i); 
			else { 
				emi(LBI,i>>24); 
				emi(LBHI,(i<<8)>>8); 
			} 
		}
			
		function lb(b) {
  			switch (b.value) {
				case Auto: eml(LBL+lmod(b.lChild), b.rChild); return 0;
				case Static: emg(LBG+lmod(b.lChild), b.rChild); return 0;
				case Num: lbi(b.rChild); return 0;
				default: rv(b); em(LBA); return 0;
			}
		}

		function opt(a) {
			var b = a.rChild;
		  	switch (b.value) {
		  		case Auto:
				case Static:
				case Num: 
					rv(a.lChild); 
					lb(b); 
					return;
				default:
					rv(b);
					a = a.lChild;
					switch (a.value) {
						case Auto:
						case Static:
						case Num: em(LBA); rv(a); return;
						default: loc -= 8; em(PSHA); rv(a); em(POPB); loc += 8; return;
					}
			}
		}
		
		function opi(o, i) { 
			if ((i<<8)>>8 == i) 
				emi(o+OPI, i); 
			else { 
				emi(LBI,i>>24); 
				emi(LBHI,(i<<8)>>8); 
				em(o); 
			} 
		}

		function op(a, o) {
			var t = null;
			var b = a.rChild;
			switch (b.value) {
				case Auto: 
					rv(a.lChild); 
					if (t = lmod(b.lChild)) { 
						eml(LBL+t, b.rChild); 
						em(o); 
					} else 
						eml(o+OPL, b.rChild); 
					return;
				case Static: 
					rv(a.lChild); 
					emg(LBG+lmod(b.lChild), b.rChild); 
					em(o); 
					return;
				case Num: 
					rv(a.lChild); 
					opi(o,b.rChild); 
					return;
			  	default:
					rv(b);
					a = a.lChild;
					switch (a.lChild) {
						case Auto: 
						case Static: 
						case Num: em(LBA); rv(a); em(o); return;
						default: loc -= 8; em(PSHA); rv(a); em(POPB); em(o); loc += 8; return;
					}
			}
		}
		
		function opa(a, o, comm) {
			var t ;
			var b = expr[a.addr-1];
		  	a = a.lChild;
		  	switch (a.value) {
		  		case Auto:
					if (b.value == Num && (b.rChild<<8)>>8 == b.rChild) { 
						eml(LL+lmod(a.lChild),a.rChild); 
						emi(o+OPI,b.rChild); 
					} // loc op= num
					else if (b.value == Auto && lmod(b.lChild) == 0)  { 
						eml(LL+lmod(a.lChild),a.rChild); 
						eml(o+OPL,b.rChild); 
					} // loc op= locint
					else if (comm != 0) { 
						rv(b); 
						if (t = lmod(a.lChild)) { 
							eml(LBL+t,a.rChild); 
							em(o); 
						} else eml(o+OPL,a.rChild); 
					} // loc comm= expr
					else { 
						lb(b); 
						eml(LL+lmod(a.lChild),a.rChild); 
						em(o); 
					} // loc op= expr
					eml(SL+smod(a.lChild),a.rChild);
					return 0;
			    case Static:
					if (b.value == Num && (b.rChild<<8)>>8 == b.rChild) { 
						emg(LG+lmod(a.lChild), a.rChild); 
						emi(o+OPI,b.rChild); 
					} // glo op= num
					else if (b.value == Auto && lmod(b.lChild) == 0)  { 
						emg(LG+lmod(a[1]),a[2]); eml(o+OPL,b[2]); } // glo op= locint
					else if (comm) { rv(b); emg(LBG+lmod(a[1]),a[2]); em(o); } // glo comm= expr
					else { lb(b); emg(LG+lmod(a[1]),a[2]); em(o); } // glo op= expr
					emg(SG+smod(a[1]),a[2]);
					return;
		  case Ptr: 
			if (*b == Num && b[2]<<8>>8 == b[2]) { rv(a+2); em(LBA); em(LX+lmod(a[1])); emi(o+OPI,b[2]); } // *expr op= num
			else if (*b == Auto && !lmod(b[1]))  { rv(a+2); em(LBA); em(LX+lmod(a[1])); eml(o+OPL,b[2]); } // *expr op= locint
			else {
			  switch (*b) {
			  case Auto:
			  case Static:
			  case Num: rv(a+2); lb(b); loc -= 8; em(PSHA); em(LX+lmod(a[1])); em(o); em(POPB); loc += 8; break; // *expr op= simple
			  default: rv(b); loc -= 8; em(PSHA); rv(a+2); em(LBA); em(LX+lmod(a[1])); em(o+OPL); emi(ENT,8); loc += 8; // *expr op= expr
			  }    
			}
			em(SX+smod(a[1])); // XXX many more (SX,imm) optimizations possible (here and elsewhere)
			return;
		  default: err("lvalue expected");
		  }  
		}
	</script>
</html>
