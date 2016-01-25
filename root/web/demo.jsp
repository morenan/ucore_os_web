<html>
	<head>
		<style type="text/css">
			body {background-color:#000000;}
		</style>
	</head>
	<body>
		<div id="board"></div>
		<script type="text/javascript">
			// -----------------------------------------------------------------------------------------------
			// 		background 
			var board = document.getElementById("board");
			board.style.color = "#FFFFFF";
			board.style.fontFamily = "Courier";
			board.style.fontSize = 16;		
			function print(text) {
				board.innerHTML = board.innerHTML + text + "<br>";
			}
			// -----------------------------------------------------------------------------------------------
			//		exit (use history.back)
			function exit(value) {
				window.history.back(value);
			}
			function err(msg) {
  				print(sprintf("%s : [%s:%d] error: %s\n", cmd, file, line, msg)); // XXX need errs to power past tokens (validate for each err case.)
  				errs += 1;
  				if (errs > 10) { 
  					print(sprintf("%s : fatal: maximum errors exceeded\n", cmd)); exit(-1);
  				}
  				return 0;
  			}
			// -----------------------------------------------------------------------------------------------
			// 		constant value (size)
			var SEG_SZ    = 8*1024*1024; // max size of text+data+bss seg
  			var EXPR_SZ   =      4*1024; // size of expression stack
	  		var VAR_SZ    =     64*1024; // size of symbol table
	  		var PSTACK_SZ =     64*1024; // size of patch stacks
	  		var LSTACK_SZ =      4*1024; // size of locals stack
	  		var HASH_SZ   =      8*1024; // number of hash table entries
	  		var BSS_TAG   =  0x10000000; // tag for patching global offsets
	  		// 		static memory
	  		var ts_seg 		 = new Array(SEG_SZ);  		// value, addr
	  		var gs_seg 		 = new Array(SEG_SZ);
	  		var va_var 		 = new Array(VAR_SZ);
	  		var pdata_pstack = new Array(PSTACK_SZ);	// ts address
	  		var pbss_pstack  = new Array(PSTACK_SZ);
	  		var ploc_lstack  = new Array(LSTACK_SZ);
	  		var expr  		 = new Array(EXPR_SZ);
	  		var ht_hash		 = new Array(HASH_SZ);
	  		// 		variable
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
			// -----------------------------------------------------------------------------------------------
			//  conver integer to ASCII code
			function IntToString(i) {
				return String.fromCharCode((i>>24)&255)
					+  String.fromCharCode((i>>16)&255)
					+  String.fromCharCode((i>>8)&255) 
					+  String.fromCharCode(i&255);
			}
			function LongToString(i) {
				return String.fromCharCode((i>>56)&255)
					+  String.fromCharCode((i>>48)&255)
					+  String.fromCharCode((i>>40)&255) 
					+  String.fromCharCode((i>>32)&255)
					+  String.fromCharCode((i>>24)&255)
					+  String.fromCharCode((i>>16)&255)
					+  String.fromCharCode((i>>8)&255) 
					+  String.fromCharCode(i&255);
			}
			// -----------------------------------------------------------------------------------------------
			//	XXX replace with mmap
			function mapfile(name, size) {
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
			// -----------------------------------------------------------------------------------------------
			// instruction emitter
			function em(i) {
  				if (debug == 1) 
  					print(sprintf("%08x  %08x%6.4s\n", TS_ADDR+ip, i, ops[i*5]));
  				ts_seg[ip] = new Object();
  				ts_seg[ip].value = i;
  				ts_seg[ip].addr = ip*4; 
  				ip += 1;
			}
			function emi(i, c) {
  				if (debug == 1) 
  					print(sprintf("%08x  %08x%6.4s  %d\n", TS_ADDR+ip, i|(c<<8), ops[i*5], c));
  				if ((c<<8)>>8 != c) err("emi() constant out of bounds"); 
  				ts_seg[ip] = new Object();
  				ts_seg[ip].value = i|(c<<8);
  				ts_seg[ip].addr = ip*4;
  				ip += 1;
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
	  			if ((c<<8)>>8 != c) err("emf() offset out of bounds");
	  			ts_seg[ip] = new Object();
	  			ts_seg[ip].value = i|(c<<8);
	  			ts_seg[ip].addr = ip*4;
	  			return ts_seg[ip++].addr;
			}
			function patch(t, a) {
	  			var n = 0;
	  			while (t != 0) {
					//t += ts;
					n = ts_seg[t].value;
					ts_seg[t].value = (n & 0xff) | ((a-t-4) << 8);
					t = (n>>2)>>8;  // virtual index
	  			}
			}
			// -----------------------------------------------------------------------------------------------
			// parser
			function dline() {
  				for (var p = 0 ; p < pos.length ; p++)
  					print(sprintf("%s  %d: %.*s\n", file, line, p-pos, pos));
  			}
  			
  			function hexValueOf(s) {
  				var ret = 0;
  				for (var i = 0 ; i < s.length ; i++) {
  					switch(s[i]) {
  						case '0' : ret = ret*16 + 0 ; break;
  						case '1' : ret = ret*16 + 1 ; break;
  						case '2' : ret = ret*16 + 2 ; break;
  						case '3' : ret = ret*16 + 3 ; break;
  						case '4' : ret = ret*16 + 4 ; break;
  						case '5' : ret = ret*16 + 5 ; break;
  						case '6' : ret = ret*16 + 6 ; break;
  						case '7' : ret = ret*16 + 7 ; break;
  						case '8' : ret = ret*16 + 8 ; break;
  						case '9' : ret = ret*16 + 9 ; break;
  						case 'A' : ret = ret*16 + 10; break;
  						case 'B' : ret = ret*16 + 11; break;
  						case 'C' : ret = ret*16 + 12; break;
  						case 'D' : ret = ret*16 + 13; break;
  						case 'E' : ret = ret*16 + 14; break;
  						case 'F' : ret = ret*16 + 15; break;
  						default : err("unknown alpha %c in hexadecimal.");
  					}
  				}
  				return ret;
  			}
  			
  			function octValueOf(s) {
  				var ret = 0;
  				for (var i = 0 ; i < s.length ; i++) {
  					switch(s[i]) {
  						case '0' : ret = ret*8 + 0 ; break;
  						case '1' : ret = ret*8 + 1 ; break;
  						case '2' : ret = ret*8 + 2 ; break;
  						case '3' : ret = ret*8 + 3 ; break;
  						case '4' : ret = ret*8 + 4 ; break;
  						case '5' : ret = ret*8 + 5 ; break;
  						case '6' : ret = ret*8 + 6 ; break;
  						case '7' : ret = ret*8 + 7 ; break;
  						default : err("unknown alpha %c in octadecimal.");
  					}
  				}
  				return ret;
  			}
  			
  			function binValueOf(s) {
  				var ret = 0;
  				for (var i = 0 ; i < s.length ; i++) {
  					switch(s[i]) {
  						case '0' : ret = (ret<<1)|0 ; break;
  						case '1' : ret = (ret<<1)|1 ; break;
  						default : err("unknown alpha %c in binadecimal.");
  					}
  				}
  				return ret;
  			}
  			
  			var ipos = 0;
	  		var ipos_str = null;
	  		var ifile = null;
	  		var iline = 0;
  			function next() {
	  			while (pos_id < pos.length) {
	  				switch (pos[pos_id++]) {
	  					case ' ': case '\t': case '\v': case '\r': case '\f':
		  					continue;
						case '\n': 
		  					if (debug) dline();
		  					continue;
		  				case '#':
		  					if (pos.substring(pos_id, pos_id+7).big() != "INCLUDE") {
		    					if (ifile != null) { err("can't nest include files"); exit(-1);} // include errors bail out otherwise it gets messy
		    					pos_id += 7;
		    					while (pos[pos_id] == ' ' || pos[pos_id] == '\t') pos_id += 1;
		    					ipos = pos.substring(pos_id).match("^((\".+\")|(<.+>))");
		    					if (ipos == null) {
		    						err("bad include file name"); exit(-1);
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
		    					iname = iname + ipos.substring(1, ipos.length-1);
		    					if (stat(iname, st) != 0) {
		      						if (ipos[0] == '"' || ipos[1] == '/') { 
		      							print(dprintf("%s : [%s:%d] error: can't stat file %s\n", cmd, file, line, iname)); 
		      							exit(-1); 
		      						}
		      						iname = "/lib/" + ipos.substring(1, ipos.length-1);
		      						if (stat(iname, st)) { 
		      							print(dprintf("%s : [%s:%d] error: can't stat file %s\n", cmd, file, line, iname)); 
		      							exit(-1); 
		      						}
		    					}
		    					pos_id += ipos.length;
		    					while (pos[pos_id] != '\0' && pos[pos_id] != '\n') pos_id += 1;
		    					ipos_id = pos_id; ipos = pos; 
		    					pos = mapfile(iname, st.st_size);
		    					ifile = file; file = iname;
		    					iline = line; line = 1;
		    					if (debug) dline();
		    					continue;
		  					}
		  					while (pos[pos_id] != '\0' && pos[pos_id] != '\n') pos_id += 1;
		  					continue;
		  				
		  				case pos.charCodeAt(pos_id-1) >= "a".charCodeAt(0) 
		  				  && pos.charCodeAt(pos_id-1) <= "z".charCodeAt(0) :
		  				case pos.charCodeAt(pos_id-1) >= "A".charCodeAt(0) 
		  				  && pos.charCodeAt(pos_id-1) <= "Z".charCodeAt(0) : 
		  				case '_': case '$':
		  					ipos = pos.substring(pos_id-1).match("^[a-zA-Z0-9_$]+");
		  					if (ipos == null) {
		  						print(sprintf("%s : [%s:%d] error: can't match name\n", cmd, file, line));
		  						exit(-1);
		  					}
		  					pos_id += ipos.length-1;
		  					tk = 0 ; i = 0 ;
		  					for ( ; i < ipos.length ; i++)
		  						tk = tk*147 + ipos.charCodeAt(i); 
		  					id = ht[tk&(HASH_SZ-1)];
		  					while (id != null) {
		    					if (tk == id.tk && ipos == id.name) return 0;
		    					id = id.next;
		  					}
		  					id = new Object(); 
		 				 	id.name = ipos;
		  					id.tk = tk;
		  					id.next = ht[tk&(HASH_SZ-1)];
		  					ht[tk&(HASH_SZ-1)] = id;
		  					return 0;
		  				
		  				case pos.charCodeAt(pos_id-1) >= "0".charCodeAt(0) 
		  				  && pos.charCodeAt(pos_id-1) <= "9".charCodeAt(0) :
		  					if (pos[pos_id] == 'x' || pos[pos_id] == 'X') {
		  						ipos = pos.substring(++pos_id).match("^[0-9|A-F|a-f]+").big();
		  						if (ipos == null) {
		  							print(sprintf("%s : [%s:%d] error: can't match number\n", cmd, file, line)); 
		      						exit(-1);
		      					}
		  						ival = hexValueOf(ipos);
		  						pos_id += ipos.length;
		  						ty = INT;
		  						tk = Num;
		  					} else if (pos[pos_id] == 'b' || pos[pos_id] == 'B') {
		  						ipos = pos.substring(++pos_id).match("^[0-1]+");
		  						if (ipos == null) {
		  							print(dprintf("%s : [%s:%d] error: can't match number\n", cmd, file, line));
		      						exit(-1);
		      					}
		  						ival = binValueOf(ipos);
		  						pos_id += ipos.length;
		  						ty = INT;
		  						tk = Num;
		  					} else {
		  						ipos = pos.substring(pos_id-1).match("^[0-9]+(.[0-9]+)?");
		  						if (ipos == null) {
		  							print(dprintf("%s : [%s:%d] error: can't match number\n", cmd, file, line)); 
		      						exit(-1);
		      					}
		      					pos_id += ipos.length-1;
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
		      						} else if (pos[pos_id] == '\n') {
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
										case '\r': while (pos[pos_id] == '\r' || pos[pos_id] == '\n') pos_id++; // XXX not sure if this is right
		      							case '\n': line++; if (debug) dline(); continue;
		      							case 'x':
											// b = (*pos - '0') * 16 + pos[1] - '0'; pos += 2; // XXX this is broke!!! 0xFF needs to become -1 also
		        							ipos = pos.substring(pos_id).match("^[0-9|A-F|a-f]{2}").big();
		        							if (ipos == null) {
		  										print(dprintf("%s : [%s:%d] error: can't match number\n", cmd, file, line));
		      									exit(-1);
		      								}
		      								b = hexValueOf(ipos);
		      								pos_id += 2;
		        							// XXX			b = (char) b; // make sure 0xFF becomes -1 XXX do some other way!
		        							break;
		      							case '0' ... '7': 
		        							ipos = pos.substring(pos_id-1).match("^[0-7]+");
		        							if (ipos == null) {
		  										print(dprintf("%s : [%s:%d] error: can't match number\n", cmd, file, line));
		      									exit(-1);
		      								}
		      								b = octValueOf(ipos);
		      								pos_id += ipos.length;
		        							break;
		      							default: err("bad escape sequence");
		      						}
		      					}
		    					gs_seg[gs+data++].value = b;
		    				}
		    				if (tk == '\'') {
		    					ival = gs_seg[gs+data-1].value;
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
							 	  		if (pos[++pos_id] == '=') { pos_id += 1; tk = Shla; } 
							 	  			else tk = Shl; } 
							 else tk = Lt; return 0;
						case '>': if (pos[pos_id] == '=') { pos_id += 1; tk = Ge; }
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
						case ',': tk = Comma; return 0;
						case '?': tk = Cond; return 0;
						case '.':
							if (pos[pos_id] == '.' && pos[pos_id+1] == '.') { pos_id += 2; tk = Dots; }
							else if (pos.charCodeAt(pos_id) >= "0".charCodeAt(0) && 
									 pos.charCodeAt(pos_id) <= "9".charCodeAt(0)) { 
								ipos = pos.substring(pos_id).match("^[0-9]+");
								if (ipos == null) {
									print(dprintf("%s : [%s:%d] error: can't match number\n", cmd, file, line));
		      						exit(-1);
								}
								fval = Number("0." + ipos);
								pos_id += ipos.length;
							} else tk = Dot; 
						  return;
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
  				if (tk != c) { print(sprintf("%s : [%s:%d] error: '%c' expected\n", cmd, file, line, c)); errs += 1; }
  				next();
			}
			
			function imm() /// XXX move these back down once I validate prototypes working for double immf()
			{
				var b = e;
				var c;
				expr(Cond);
				if (etree[e].value == Num) c = etree[e].rChild;
				else if (etree[e].value == Numf) c = parseInt(etree[e].rChild);
				else { err("bad constant expression"); c = 0; }
				e = b;
				return c;
			}

			function immf()
			{
				var b = e;
				var c;
				expr(Cond);
				if (etree[e].value == Num) c = etree[e].rChild;
				else if (etree[e].value == Numf) c = Number(etree[e].rChild);
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
	  					a = va_var[t>>TSHIFT].value; 
	  					return a.size * tsize(a.type);  
	  				case STRUCT:
	  					s = va_var[t>>TSHIFT].value;
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
	  	   else if (t & ARRAY) return tsize(va_var[t>>TSHIFT].value.type);  // XXX need to test this!
	  	   else return 1;
			}

			function talign(t) {
	  			var a;
				switch (t & TMASK) {
					case ARRAY:  
						return talign(va_var[t>>TSHIFT].value.type);
				  	case STRUCT:
				  		a = va_var[t>>TSHIFT].value.align;
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
			
			function  basetype() {
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
	
  			
			// -----------------------------------------------------------------------------------------------
			//  'main' process
			alert("b0");
			var verbose = "null";
			var debug   = "null";
			var ipath   = "input.txt";
			var opath   = "output.txt";
			if (verbose != "0" && verbose != "1" && verbose != "null") {
				print("usage: %s [-v] [-s] [-Ipath] [-o exefile] file ...\n"); exit(-1);
			}
			if (debug != "0" && debug != "1" && debug != "null") { 
				print("usage: %s [-v] [-s] [-Ipath] [-o exefile] file ...\n"); exit(-1);
			}
			if (ipath == "null" || opath == "null") { 
				print("usage: %s [-v] [-s] [-Ipath] [-o exefile] file ...\n"); exit(-1);
			}
			ip = 0; vp = 0;
			bigend = 1; // bigend = ((char *)&bigend)[3];
			pos = "asm auto break case char continue default do double else enum float for goto if int long return short "
        		+ "sizeof static struct switch typedef union unsigned void while va_list va_start va_arg main";	
        	pos_id = 0;
        	for (var i = Asm; i <= Va_arg; i++) {
				 next(); id.tk = i; 
			}
			next(); 
			var tmain = id;
			
			line = 1;
  			if (stat(file, st)) { 
  				print(sprintf("%s : [%s:%d] error: can't stat file %s\n", cmd, file, line, file)); exit(-1); 
  			} // XXX fstat inside mapfile?
  			pos = mapfile(file, st.st_size);

  			e = EXPR_SZ;
  			pdata = 0; patchdata = 0;
  			pbss  = 0; patchbss  = 0;
  			ploc  = 0;

  			if (verbose) print(sprintf("%s : compiling %s\n", cmd, file));
  			if (debug) dline();
  			next(); decl(Static);
  			if (errs == 0 && ffun != 0) 
  				err("unresolved forward function (retry with -v)");
    
  			ip = (ip + 7) & (-8);
  			text = ip - ts;
  			data = (data + 7) & (-8);
  			bss = (bss + 7) & (-8);
    		
  			if (text + data + bss > SEG_SZ && err("text + data + bss segment exceeds maximum size") != 0) exit(-1);
  			var amain = tmain.val;
  			if (amain == 0 && err("main() not defined") != 0) exit(-1);
  			if (verbose != 0 || errs != 0) print(sprintf("%s : %s compiled with %d errors\n", cmd, file, errs));
  			if (verbose != 0) print(sprintf("entry = %d text = %d data = %d bss = %d\n", amain - ts, text, data, bss));
			
  			if (errs != 0 && debug != 0) {
    			while (pdata != patchdata) { 
    				pdata -= 1;
    				ts_seg[pdata_pstack[pdata]].value = (ip - ts_seg[pdata_pstack[pdata]].addr - 4) << 8;
    				// *(int *)*pdata += (ip - *pdata - 4) << 8; 
    			}
    			while (pbss  != patchbss ) { 
    				pbss -= 1;
    				ts_seg[pbss_pstack[pbss]].value = (ip + data - ts_seg[pbss_pstack[pbss]].value - 4) << 8;
    				// *(int *)*pbss  += (ip + data - *pbss  - 4) << 8; 
    			}
    			
    			if (opath != null) {
    				
    				var hdr = new Object();
    				hdr.magic = 0xC0DEF00D;
      				hdr.bss   = bss;
      				hdr.entry = amain - ts;
      				hdr.flags = 0;
      				var stream = new ActiveXObject("ADODB.Stream");
   	 				stream.Type = adTypeText;
    				stream.CharSet = "iso-8859-1";
    				stream.Open();
    				stream.WriteText(IntToString(hdr.magic));
    				stream.WriteText(IntToString(hdr.bss));
    				stream.WriteText(IntToString(hdr.entry));
    				stream.WriteText(IntToString(hdr.flags));
    				for (var i = 0 ; i < text ; i++)  
    					stream.WriteText(IntToString(ts_var[i].value));
    				for (var i = 0 ; i < data ; i++)  
    					stream.WriteText(LongToString(gs_var[i].value));
    				stream.SaveToFile(opath, adSaveCreateOverWrite);
    				stream.Close();
    			} else {
    				for (var i = 0 ; i < data ; i++) {
    					gs_var[ip+i] = new Object();
    					gs_var[ip+i].value = gs_var[i].value;
    					gs_var[ip+i].addr = (ip+i)*8;
    				}
      				//memcpy((void *)ip, (void *)gs, data);
      				sbrk(sbrk_start + text + data + 8 - sbrk(0)); // free compiler memory    
      				sbrk(bss);
      				if (verbose != 0) print(sprintf("%s : running %s\n", cmd, file));
      				var errs = amain;
      				// errs = ((int (*)())amain)(argc, argv);
      				if (verbose != 0) print(sprintf("%s : %s main returned %d\n", cmd, file, errs));
    			}

  			}
  			if (verbose != 0) print(sprintf("%s : exiting\n", cmd));
  			exit(errs);
  			
		</script>
	</body>
	
</html>
