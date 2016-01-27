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
		      							case '\n': line++; if (debug != 0) dline(); continue;
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
		      							case pos.charCodeAt(pos_id-1) >= "0".charCodeAt(0) 
		  				  				  && pos.charCodeAt(pos_id-1) <= "7".charCodeAt(0) :
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
	  			if ((t & PMASK) != 0) return tsize(t - PTR);
	  	   else if ((t & ARRAY) != 0) return tsize(va_var[t>>TSHIFT].value.type);  // XXX need to test this!
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
							for (s = structs; s != null; s = s.next) 
								if (s.id == id) goto_found = true;
							if (goto_found == false) {
								va_var[vp] = new Object();
								va_var[vp].value = new Object();
								va_var[vp+1].addr = va_var[vp].addr + SIZEOF_STRUCT_T;
								s = va_var[vp++].value;
						  		s.id = id; // XXX redefinitions
						  		s.next = structs; 
						  		structs = s;
						  	}
							next();
						  	if (tk != '{') 
						  		return STRUCT | (s.addr<<TSHIFT);
						  	if (s.align != 0) err("struct or union redefinition");
						  	next();
						} else {
							skip('{');
							va_var[vp] = new Object();
							va_var[vp].value = new Object();
							va_var[vp+1].addr = va_var[vp].addr + SIZEOF_STRUCT_T;
							s = va_var[vp++].value;   
							s.next = structs; 
							structs = s;
						}
						member(m, s);
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
						va_var[vp] = new Object();
						va_var[vp].value = bt;
						va_var[vp+1].addr = va_val[vp].addr+8;
						return vp++;
					}
					t = type(0, arguments[0], arguments[1]);
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
							ploc_lstack[ploc] = new Object();
							ploc_lstack[ploc].value = new Object();
							ploc_lstack[ploc].value.Class = n.Class; // XXX make sure these are unwound for abstract types and forward decls
							ploc_lstack[ploc].value.type = n.type;
							ploc_lstack[ploc].value.val = n.val;
							ploc_lstack[ploc].value.id = n;
							ploc_lstack[ploc+1].addr = ploc_lstack[ploc].addr + SIZEOF_LOC_T;
							ploc += 1;
							if (arguments[2] == n) arguments[2] = ploc_lstack[ploc-1].value.id; // hack if function name same as parameter
							if ((d & TMASK) == ARRAY) 
								d = va_var[d>>TSHIFT].value.type + PTR; // convert array to pointer
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
					va_var[vp] = new Object();	
					va_var[vp].value = new Object();
					va_var[vp].value.size = a;
					va_var[vp+1].addr = va_var[vp].addr + SIZEOF_ARRAY_T;
					t = vp++;
				}
	  			va_var[t].value.type += bt;
	  			return t;
			}
			
			function decl(bc) {
  				var sc, size, align, hglo ;
  				var b = null, c = null; 
  				var bt, t; 
  				var v; // ident_t *v; 
  				var sp;// loc_t *sp;
  				while (true) {
  					if (tk == Static || tk == Typedef || (tk == Auto && bc == Auto))
      					{ sc = tk; next(); if ((bt = basetype()) == 0) bt = INT; } // XXX typedef inside function?  probably bad!
    				else { 
    					if ((bt = basetype()) == 0) { 
    						if (bc == Auto) break; 
    						bt = INT; 
    					} 
    					sc = bc; 
    				}
    				if (tk == 0) break;
    				if (tk == ';') { next(); continue; } // XXX is this valid?
    				while (true) {
      					v = 0; t = 0;
      					sp = ploc;
      					type(bt, t, v);
      					if (v == null) err("bad declaration");
      					else if (tk == '{') {
							if (bc != Static || sc != Static) err("bad nested function");
							if ((t & TMASK) != FUN) err("bad function definition");
							rt = va_var[va+(t>>TSHIFT)].value;
							if (v.Class == FFun) { 
								patch(v.val,ip); ffun--;
						  		if (rt != va_var[va+(v.type>>TSHIFT)].value || 
						  		(bt = va_var[va+(v.type>>TSHIFT)+1].value) != 0 && 
								bt != va_var[va+(t>>TSHIFT)+1].value) err("conflicting forward function declaration");
							} else if (v.Class) err("duplicate function definition");
							v.Class = Fun;
							v.type = t;
							v.val = ip;
							loc = 0;
							next();
							b = e;
							decl(Auto);
							loc &= -8;
							if (loc) emi(ENT, loc);
							if (e != b) { rv(e); e = b; }
							while (tk != '}') stmt(); // XXX null check
							next();
							emi(LEV,-loc);
							while (ploc != sp) {
								ploc -= 1;
							  	v = ploc_lstack[ploc].id;
							  	v.val = ploc_lstack[ploc].val;
							  	v.type = ploc_lstack[ploc].type;
							 	if (v.Class == FLabel) err("unresoved label");
							  	v.Class = ploc_lstack[ploc].Class;
							  	v.local = 0;
							}        
							break;
						} else if ((t & TMASK) == FUN) {
					//        if (bc != Static || sc != Static) err("bad nested function declaration");
							if (v.Class) err("duplicate function declaration");
							v.Class = FFun;
							v.type = t;
							ffun++;
							while (ploc != sp) {
							  	ploc -= 1;
							  	v = ploc_lstack[ploc].id;
							  	v.val = ploc_lstack[ploc].val;
							  	v.type = ploc_lstack[ploc].type;
							  	v.Class = ploc_lstack[ploc].Class;
							  	v.local = 0;
							}        
						} else {
							if (bc == Auto) {
							  if (v.Class && v.local) err("duplicate definition");
							  ploc_lstack[ploc].Class = v.Class;
							  ploc_lstack[ploc].type = v.type;
							  ploc_lstack[ploc].val = v.val;
							  ploc_lstack[ploc].id = v;
							  ploc += 1;
							  v.local = 1;
							}
							else if (v.Class != 0) err("duplicate definition");
								 
							v.Class = sc;
							v.type = t;
							if (sc != Typedef) { // XXX typedefs local to functions?
								if ((t & TMASK) == ARRAY) v.Class = (sc == Auto) ? Lea : Leag; // not lvalue if array
							  	size = tsize(t);
							  	align = talign(t);
							  	if (sc == Auto) {            
									v.val = loc = (loc - size) & -align; // allocate stack space
									if (tk == Assign) {
								  		node(Auto, t, v.val); b = e;
								  		next();
								  		expr(Cond);
								  		cast(t < UINT ? INT : t);
								  		etree[++e].value = Assign; 
								  		etree[e].lChild = b; 
								  		if (c) { 
								  			etree[++e].value = Comma;
								  			etree[e].lChild = c;
								  		}
								  		c = e;
									}
							  	} else {
									if (tk == Assign) {
								  		v.val = data = (data + align - 1) & -align; // allocate data space
								  		hglo = data;
								  		next();
								  		if (tk == '"') {
											if ((t & TMASK) != ARRAY) err("bad string initializer");
											next(); while (tk == '"') next();
											data = size ? hglo + size : data + 1;
								  		} else if (tk == '{') { // XXX finish this mess!
											if ((t & TMASK) != ARRAY) err("bad array initializer");
											next();
											while (tk != '}') {
											  	switch (va_var[va+(t>>TSHIFT)].type) {
											  		case UCHAR:
											  			gs_var[gs+data].value = toChar(imm()); 
											  			gs_var[gs+data+1].addr = gs_var[gs+data].addr + 1;
											  			data += 1; break;
											  		case CHAR:   
											  			gs_var[gs+data].value = toUChar(imm()); 
											  			gs_var[gs+data+1].addr = gs_var[gs+data].addr + 1;
											  			data += 1; break;
											  		case USHORT:
											  			gs_var[gs+data].value = toUShort(imm()); 
											  			gs_var[gs+data+1].addr = gs_var[gs+data].addr + 2;
											  			data += 1; break;
											  		case SHORT:  
											  			gs_var[gs+data].value = toShort(imm()); 
											  			gs_var[gs+data+1].addr = gs_var[gs+data].addr + 2;
											  			data += 1; break;
											  		case FLOAT:  
											  			gs_var[gs+data].value = toFloat(immf()); 
											  			gs_var[gs+data+1].addr = gs_var[gs+data].addr + 4;
											  			data += 1; break;
											  		case DOUBLE: 
											  			gs_var[gs+data].value = toDouble(immf()); 
											  			gs_var[gs+data+1].addr = gs_var[gs+data].addr + 8;
											  			data += 1; break;
											  		default:     
											  			gs_var[gs+data].value = toInt(imm()); 
											  			gs_var[gs+data+1].addr = gs_var[gs+data].addr + 4;
											  			data += 1; break;
											  	}
									  	  	  	if (tk == Comma) next();
										  	} 
										  	next();
										  	if (size != 0) data = hglo + size * align; // XXX need to zero fill if size > initialized part  XXX but may default since using sbrk vs malloc?
									// XXX else set array size if []
								  		} else {
											switch (t) { // XXX redundant code
												case UCHAR:
											  		gs_var[gs+data].value = toChar(imm()); 
											  		gs_var[gs+data+1].addr = gs_var[gs+data].addr + 1;
											  		data += 1; break;
											  	case CHAR:   
											  		gs_var[gs+data].value = toUChar(imm()); 
											  		gs_var[gs+data+1].addr = gs_var[gs+data].addr + 1;
											  		data += 1; break;
											  	case USHORT:
											  		gs_var[gs+data].value = toUShort(imm()); 
											  		gs_var[gs+data+1].addr = gs_var[gs+data].addr + 2;
											  		data += 1; break;
											  	case SHORT:  
											  		gs_var[gs+data].value = toShort(imm()); 
											  		gs_var[gs+data+1].addr = gs_var[gs+data].addr + 2;
											  		data += 1; break;
											  	case FLOAT:  
											  		gs_var[gs+data].value = toFloat(immf()); 
											  		gs_var[gs+data+1].addr = gs_var[gs+data].addr + 4;
											  		data += 1; break;
											  	case DOUBLE: 
											  		gs_var[gs+data].value = toDouble(immf()); 
											  		gs_var[gs+data+1].addr = gs_var[gs+data].addr + 8;
											  		data += 1; break;
											  	default:     
											  		gs_var[gs+data].value = toInt(imm()); 
											  		gs_var[gs+data+1].addr = gs_var[gs+data].addr + 4;
											  		data += 1; break;
											}
								  		}
									} else {
								  		bss = (bss + align - 1) & -align; // allocate bss space
								  		v.val = bss + BSS_TAG;
								  		bss += size; // XXX check for zero size
									}
							  	}
							}
						}
						if (tk != Comma) {
							skip(';');
							break;
						}
						next();
					}
				}
			}

			
			function member(stype) {  // struct_t arg[0]
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
							va_var[vp] = new Object();
							va_var[vp].value = new Object();
							va_var[vp].value.id = v;
							va_var[vp].value.type = t;
							va_var[vp+1].addr = va_var[vp].addr + SIZEOF_MENBER_T;
							mp = vp++;
							size = tsize(t);
							align = talign(t);
							if (stype == Struct) {
								va_var[mp].value.offset = (ssize + align - 1) & -align;
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
				arguments[0].align = salign;
				arguments[0].size = (ssize + salign - 1) & -salign;  
			}
  			// -----------------------------------------------------------------------------------------------
  			// expression parsing
	  		function node(n, a, b) {
				etree[++e].value = n;
				etree[e].lChild = a;
				etree[e].rChild = b; 
			}
			function nodc(n, a, b) // commutative
			{
				etree[++e].value = n;
				if (a.value < b.value) { 
					etree[e].lChild = b; 
					etree[e].rChild = a; 
				} else { 
					etree[e].lChild = a; 
					etree[e].rChild = b; 
				} // put simpler expression in rhs
			}
			function mul(b) // XXX does this handle unsigned correctly?
			{
	  			if (b.value == Num) {
					if (etree[e].value == Num) { etree[e].rChild *= b.rChild; return; }
					if (b.rChild == 1) return;
	  			}
	  			if (etree[e].value == Num && e.rChild == 1) { 
	  				e = b.addr; return;
	  			} // XXX reliable???
	  			nodc(Mul,expr[e],b);
			}
			function add(b)  // XXX make sure to optimize (a + 9 + 2) -> (a + 11)    and    (a + 9 - 2) -> (a + 7)
			{
	  			if (b.value == Num) {
					if (etree[e].value == Num || etree[e].value == Lea || etree[e] == Leag) { 
						etree[e].rChild += b.rChild; return; } // XXX  <<>> check
					if (b.rChild == null) return;
	  			}
	  			if (etree[e].value == Num) {
					if (b.value == Lea) { etree[e].rChild += b.rChild; etree[e].value = Lea; return; } // XXX structure offset optimizations
					if (b.value == Leag) { etree[e].rChild += b.rChild; etree[e].value = Leag; return; }
					if (etree[e].rChild == null) { e = b.addr; return; } // XXX reliable???
				}
	 			nodc(Add,b,expr[e]);
			}
			function flot(t) { // etree arg[0] 
  				if (t == DOUBLE || t == FLOAT) 
  					return arguments[0].addr;
  				if (arguments[0].value == Num) {
    				arguments[0].value = Numf;
    				arguments[0].rChild = Number(arguments[0].rChild);
    				return arguments[0].addr;
    			}
    			node(t < UINT ? Cid : Cud, b, null);
  				return etree[e-1];
  			}
  			function ind() {
  				if ((ty & PMASK) != 0)
    				ty -= PTR;
	  			else if ((ty & ARRAY) != 0) {
					ty = va_var[ty>>TSHIFT].type;
					if ((ty & TMASK) == ARRAY) return; // was a ref, still a ref
	  			} else
					err("dereferencing a non-pointer");
	  			if ((ty & TMASK) == FUN) return; // XXX
	  			switch (etree[e].value) {
	  				case Leag: etree[e].value = Static; etree[e].lChild = ty; return;
	  				case Lea:  etree[e].value = Auto;   etree[e].lChild = ty; return;
	  				default: node(Ptr, ty, null); return;
	  			}
			}
			function addr() {
  				ty += PTR;
	  			switch (etree[e].value) {
					case Fun: return; // XXX dont think ty is going to be right?
					case Leag: case Lea: return; // XXX
					case Static: etree[e].value = Leag; return;
					case Auto: etree[e].value = Lea; return;
					case Ptr: e -= 1; return;
					default: err("lvalue expected");
				}
			}
			function assign(n, b) {
  				node(n, b, null);
  				switch (ty) { // post-cast usually removed by trim()
  					case CHAR:   node(Cic, null, null); break;
 	 				case UCHAR:  node(Cuc, null, null); break;
  					case SHORT:  node(Cis, null, null); break;
  					case USHORT: node(Cus, null, null); break;
  				}
  			}
	  		function trim() // trim dead code from expression statements (just the common cases)
			{
	  			if (etree[e].value >= Cic && etree[e].value <= Cus) 
	  				e -= 1;
	  			if (etree[e].value == Add && etree[e].rChild.value == Num) 
	  				e = e.lChild.addr; // convert x++ into ++x
			}
			function cast(t) {
				if (t == DOUBLE || t == FLOAT) {
					if (ty < UINT) {
						if (etree[e].value == Num) {
							etree[e].value = Numf;
							ep = etree[e].rChild.addr;
							etree[ep].rChild.value = toDouble(etree[ep].rChild.value);
						} else 
							node(Cid, expr[e-1], null);
					} else if (ty != DOUBLE && ty != FLOAT) {
						if (etree[e].value == Num) {
							etree[e].value = Numf;
							ep = etree[e].rChild.addr;
							etree[ep].rChild.value = toDouble(etree[ep].rChild.value);
						} else 
							node(Cud, expr[e-1], null);
					}
				} else if (t < UINT) {
					if (ty == DOUBLE || ty == FLOAT) 
						if (etree[e].value == Numf) {
							etree[e].value = Num; 
							etree[e].lChild = toInt(etree[e].lChild);
						} else 
							node(cdi, null, null);
					switch (t) {
						case CHAR:   if (etree[e].value == Num) etree[e].rChild = toChar(expr[e-1].rChild);  else unode(Cic); break;
						case UCHAR:  if (etree[e].value == Num) etree[e].rChild = toUChar(expr[e-1].rChild); else unode(Cuc); break;
						case SHORT:  if (etree[e].value == Num) etree[e].rChild = toShort(expr[e-1].rChild); else unode(Cis); break;	
						case USHORT: if (etree[e].value == Num) etree[e].rChild = toUShort(expr[e-1].rChild);else unode(Cus); break;
					}
				} else if (ty == DOUBLE || ty == FLOAT) {
					if (etree[e].value == Numf) {
						etree[e].value = Num;
						etree[e].rChild = toUint(etree[e].rChild);
					} else unode(Cdu);
				}
			}
		
			
			function expr(lev) {
  				var b = null, d = null, dd = null; // int*
  				var t = 0, tt = 0; // uint
  				var m = null; // member_t*
  			
  				switch (tk) {
  					case Num:  node(Num, null, ival); next(); break;
  					case Numf: node(Num, null, fval); next(); break;
  					case '"':
						ty = PTR | CHAR;
						node(Leag, null, ival);
						next();
						while (tk == '"') next();
						data+=1;
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
						nodc(FFunl, 0, id);
						next();
						if (tk != Paren) 
							err("undefined symbol");
						else if (verbose != 0)
							print(sprintf("%s : [%s:%d] warning: undeclared function called here\n", cmd, file, line));
						break;
					case Va_arg: // va_arg(list,mode) *(mode *)(list += 8)
						next();
						skip(Paren);
						expr(Assign);
						skip(Comma);
						b = e; 
						node(Num, null, 8);
						node(Adda, b, null);
						tt = basetype() ;
						if (tt == 0) {
							err("bad_va_arg"); tt = INT;
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
					case Mul:
						next(); expr(Inc); ind();
					case And:
						next(); expr(Inc); ind();
					case '!':
						next(); expr(Inc);
						switch (etree[e].value) {
							case Eq:  etree[e].value = Ne;  break;
							case Ne:  etree[e].value = Eq;  break;
							case Lt:  etree[e].value = Ge;  break;
							case Ge:  etree[e].value = Lt;  break;
							case Ltu: etree[e].value = Geu; break;
							case Geu: etree[e].value = Ltu; break;
							case Eqf: etree[e].value = Nef; break;
							case Nef: etree[e].value = Eqf; break;
							case Ltf: etree[e].value = Gef; break;
							case Gef: etree[e].value = Ltf; break;
							default:
								if (ty < FLOAT || (ty & PMASK) != null) node(Not, null, null);
						   else if (ty >= STRUCT) err("bas operand to !");
						   else node(Notf, null, null);
						   		ty = INT;
						}
						break;
					case '~':
						next(); expr(Inc);
						if (ty >= FLOAT) 
							err("bad operand to ~");
						else {
							if (etree[e].value == Num)
								etree[e].rChild = ~etree[e].rChild;
							else {
								node(Num, null, -1);
								nodc(Xor, expr[e-2], expr[e-1]);
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
			   				if (etree[e].value == Numf)
			   					etree[e].rChild = -1.0;
			   				else {
			   					node(Numf, null, -1.0);
			   					nodc(Mulf, etree[e-2], etree[e-1]);
			   				}
			   				ty = DOUBLE;
			   			} else {
			   				if (etree[e].value == Num) 
			   					etree[e].rChild *= -1;
			   				else {
			   					node(Numf, null, -1.0);
			   					nodc(Mul, etree[e-2], etree[e-1]);
			   				}
			   				ty = ty < UINT ? INT : UINT;
			   			}
			   			break;
			   		case Inc:
			   			next(); expr(Inc);
			   			if ((ty & PMASK) != 0 && ty >= FLOAT)
			   				err("bad operand to ++");
			   			else {
			   				node(Num, null, tinc(ty));
			   				assign(Adda, etree[e]);
			   			}
			   			break;
			   		case Dec:
			   			next(); expr(Inc);
			   			if ((ty & PMASK) != 0 && ty >= FLOAT)
			   				err("bad operand to --");
			   			else {
			   				node(Num, null, tinc(ty));
			   				assign(Suba, etree[e]);
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
				   		node(Num, 0, tsize(ty));
				   		ty = INT;
				   		if (t != 0) skip(')');
				   		break;
			   		default:
			   			next();
			   			err("bad expression");
			   			return;
				}
				
				while (tk >= lev) {
    				b = e; t = ty;
    				switch (tk) {
    					case Comma: 
    						trim(); 
							b = e; 
							next(); 
							expr(Assign); 
							node(Comma, etree[b], null);
							continue;
						case Assign: 
    						next(); 
    						expr(Assign); 
    						cast(t < UINT ? INT : t); 
    						ty = t; 
    						assign(Assign, etree[b]); 
    						continue;
						case Adda:
							next(); 
							expr(Assign);
							if ((t & PAMASK) != 0 && ty <= UINT) { 
								if ((tt = tinc(t)) > 1) { 
									node(Num, null, tt);
									mul(etree[e]);
								}
								ty = t;
								assign(Adda, etree[b]);
							} else if ((tt = t|ty) >= STRUCT)
								err("bad operands to +=");
							else if ((tt & FLOAT) != 0) {
								e = flot(etree[e], ty);
								ty = t;
								assign(Addaf, etree[b]);
							} else {
								ty = t;
								assign(Adda, etree[b]);
							}
							continue;
						case Suba:
							next();
							expr(Assign);
							if ((t & PAMASK) != 0 && ty <= UINT) {
								if ((tt = tinc(t)) > 1) { 
									node(Num, null, tt);
									mul(etree[e]);
								}
								ty = t;
								assign(Suba, etree[b]);
							} else if ((tt = t|ty) >= STRUCT)
								err("bad operands to -=");
							else if ((tt & FLOAT) != 0) {
								e = flot(etree[e], ty);
								ty = t;
								assign(Subaf, etree[b]);
							} else {
								ty = t;
								assign(Suba, etree[b]);
							}
							continue;
						case Mula:
							next();
							expr(Assign);
							if ((tt = t|ty) >= STRUCT)
								err("bad operands to *=");
							else if ((tt & FLOAT) != 0) {
								e = flot(etree[e], ty);
								ty = t;
								assign(Mulaf, etree[b]);
							} else {
								ty = t;
								assign(Mula, etree[b]);
							}
							continue;
						case Diva:
							next();
							expr(Assign);
							if ((tt = t|ty) >= STRUCT)
								err("bad operands to /=");
							else if (tt & FLOAT) {
								e = flot(etree[e], ty);
								ty = t;
								assign(Divaf, etree[b]);
							} else {
								ty = t;
								assign((tt & UINT) ? Dvua : Diva, etree[b]);
							}
							continue;
						case Moda:
							next();
							expr(Assign);
							if ((tt = t|ty) >= STRUCT)
								err("bad operands to %=");
							else {
								ty = t;
								assign((tt & UINT) ? Mdua : Moda, etree[b]);
							}
							continue;
						case Anda:
							next();
							expr(Assign);
							if ((tt = t|ty) >= STRUCT)
								err("bad operands to &=");
							else {
								ty = t;
								assign(Anda, etree[b]);
							}
							continue;
						case Ora:
							next();
							expr(Assign);
							if ((tt = t|ty) >= STRUCT)
								err("bad operands to |=");
							else {
								ty = t;
								assign(Ora, etree[b]);
							}
							continue;
						case Xora:
							next();
							expr(Assign);
							if ((tt = t|ty) >= STRUCT)
								err("bad operands to ^=");
							else {
								ty = t;
								assign(Xora, etree[b]);
							}
							continue;
      					case Shla:
      						next();
							expr(Assign);
							if ((tt = t|ty) >= STRUCT)
								err("bad operands to <<=");
							else {
								ty = t;
								assign(Shla, etree[b]);
							}
							continue;
						case Shra:
      						next();
							expr(Assign);
							if ((tt = t|ty) >= STRUCT)
								err("bad operands to >>=");
							else {
								ty = t;
								assign(Shra, etree[b]);
							}
							continue;
						case Cond:
							if (ty == DOUBLE || ty == FLOAT) {
								b = e; node(Nzf, null, null);
							}
							next();
							expr(Comma);
							d = e; 
							t = ty; 
							skip(':'); 
							expr(Cond);
							dd = e;
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
					   		node(Cond, etree[b], etree[d]);
					   		etree[e].value3 = etree[dd];
					   		continue;
					   	
						case Lor:
      						if (ty == DOUBLE || ty == FLOAT) {
      							b = e; node(Nzf, null, null);
      						}
      						next(); expr(Lan);
      						if (ty == DOUBLE || ty == FLOAT) 
      							node(Nzf, null, null);
      						node(Lor, etree[b], null);
      						ty = INT;
      						continue;
      					case Lan:
      						if (ty == DOUBLE || ty == FLOAT) {
      							b = e; node(Nzf, null, null);
      						}
      						next(); expr(Or);
      						if (ty == DOUBLE || ty == FLOAT) 
      							node(Nzf, null, null);
      						node(Lan, etree[b], null);
      						ty = INT;
      						continue;
      					case Or:
      						next(); expr(Xor);
      						if ((tt = t|ty) >= FLOAT) 
      							err("bad operands to |");
      						else {
      							if (etree[b].value == Num && etree[e].value == Num)
      								etree[e].rChild |= etree[b].rChild;
      							else
      								nodc(Or, expr[b], etree[e]);
      							ty = ((tt & UINT) != 0) ? UINT : INT; 
      						}
      						continue;
      					case Xor:
      						next(); expr(And);
      						if ((tt=t|ty) >= FLOAT)
      							err("bad operands to ^");
      						else {
      							if (etree[b].value == Num && etree[e].value == Num)
      								etree[e].rChild |= etree[b].rChild;
      							else
      								nodc(Xor, etree[b], etree[e]);
      							ty = ((tt & UINT) != 0) ? UINT : INT;
      						}
      						continue;
      					
		  				case And:
		  					next(); expr(Eq);
		  					if ((tt=t|ty) >= FLOAT)
		  						err("bad operands to &");
		  					else {
		  						if (etree[b].value == Num && etree[e].value == Num)
		  							etree[e].rChild |= etree[b].rChild;
		  						else
		  							nodc(And, expr[b], expr[e-1]);
		  						ty = ((tt & UINT) != 0) ? UINT : INT;
		  					}
		  					continue;
		  				case Eq:
		  					next(); expr(Lt);
		  					if ((t < FLOAT || (t & PAMASK) != 0) && (ty < FLOAT || (ty & PAMASK) != 0)) { 
		  						if (etree[b].value == Num && etree[e].value == Num) 
		  							etree[e].rChild = (etree[b].rChild == etree[e].rChild); 
		  						else 
		  							nodc(Eq, etree[b], etree[e]); 
		  					} else if ((tt=t|ty) >= STRUCT) 
		  						err("bad operands to ==");
			  				else if (tt & FLOAT) {
								d = flot(e,ty); 
								b = flot(b,t);
								if (etree[b].value == Numf && etree[d].value == Numf) { 
									etree[e].value = Num; 
									etree[e].rChild = (Number(etree[b].rChild) == Number(etree[d].rChild));
								} else 
									nodc(Eqf, etree[b], etree[d]);
							} else {
								if (etree[b].value == Num && etree[e].value == Num) 
			  						etree[e].rChild = (etree[b].rChild == etree[e].rChild);
			  					else
			  						nodc(Eq, etree[b], etree[e]);
							}
							ty = INT;
							continue;
						
						case Ne:
							next(); expr(Lt);
							if ((t < FLOAT || (t & PAMASK) != 0) && (ty < FLOAT || (ty & PAMASK) != 0)) { 
		  						if (etree[b].value == Num && etree[e].value == Num) 
		  							etree[e].rChild = (etree[b].rChild == etree[e].rChild); 
		  						else 
		  							nodc(Ne, etree[b], etree[e]); 
		  					} else if ((tt=t|ty) >= STRUCT) 
		  						err("bad operands to !=");
			  				else if (tt & FLOAT) {
								d = flot(e,ty); 
								b = flot(b,t);
								if (etree[b].value == Numf && etree[d].value == Numf) { 
									etree[e].value = Num; 
									etree[e].rChild = (Number(etree[b].rChild) == Number(etree[d].rChild));
								} else 
									nodc(Nef, etree[b], etree[d]);
							} else {
								if (etree[b].value == Num && etree[e].value == Num) 
			  						etree[e].rChild = (etree[b].rChild == etree[e].rChild);
			  					else
			  						nodc(Ne, etree[b], etree[e]);
							}
							ty = INT;
							continue;
						
						case Lt:
							next(); expr(Shl);
							if ((t < FLOAT || (t & PAMASK) != 0) && (ty < FLOAT || (ty & PAMASK) != 0)) { 
		  						if (etree[b].value == Num && etree[e].value == Num) 
		  							etree[e].rChild = (etree[b].rChild < expr[e-1].rChild); 
		  						else 
		  							nodc(Ltu, etree[b], etree[e]); 
		  					} else if ((tt=t|ty) >= STRUCT) 
		  						err("bad operands to <");
			  				else if (tt & FLOAT) {
								d = flot(e,ty); 
								b = flot(b,t);
								if (etree[b].value == Numf && etree[d].value == Numf) { 
									etree[e].value = Num; 
									etree[e].rChild = (Number(etree[b].rChild) < Number(etree[d].rChild));
								} else 
									nodc(Ltf, etree[b], etree[d]);
							} else if (tt & UINT) {
								if (etree[b].value == Num && etree[e].value == Num) 
									etree[e].rChild = (etree[b].rChild < etree[e].rChild ? 1 : 0);
								else
									node(Ltu, etree[b], etree[e]);
							} else {
								if (etree[b].value == Num && etree[e].value == Num) 
									etree[e].rChild = (etree[b].rChild < etree[e].rChild ? 1 : 0);
								else
									node(Lt, etree[b], etree[e]);
							}
							ty = INT;
							continue;
						
						case Gt: 
							next(); expr(Shl);
							if ((t < FLOAT || (t & PAMASK) != 0) && (ty < FLOAT || (ty & PAMASK) != 0)) { 
		  						if (etree[b].value == Num && etree[e].value == Num) 
		  							etree[e].rChild = (etree[b].rChild > etree[e].rChild); 
		  						else 
		  							nodc(Ltu, etree[e], etree[b]); 
		  					} else if ((tt=t|ty) >= STRUCT) 
		  						err("bad operands to >");
			  				else if ((tt & FLOAT) != 0) {
								d = flot(e,ty); 
								b = flot(b,t);
								if (etree[b].value == Numf && etree[d].value == Numf) { 
									etree[e].value = Num; 
									etree[e].rChild = (Number(etree[b].rChild) > Number(etree[d].rChild));
								} else 
									nodc(Ltf, etree[d], etree[b]);
							} else if ((tt & UINT) != 0) {
								if (etree[b].value == Num && etree[e].value == Num) 
									etree[e].rChild = (etree[b].rChild < etree[e].rChild ? 1 : 0);
								else
									node(Ltu, etree[e], etree[b]);
							} else {
								if (etree[b].value == Num && etree[e].value == Num) 
									etree[e].rChild = (etree[b].rChild < etree[e].rChild ? 1 : 0);
								else
									node(Lt, etree[e], etree[b]);
							}
							ty = INT;
							continue;

						case Shl:
		  					next(); expr(Add);
		  					if ((tt=t|ty) >= FLOAT) 
		  						err("bad operands to <<");
		  					else { 
		  						if (etree[b].value == Num && etree[e].value == Num) 
		  							etree[e].rChild = (etree[b].rChild << etree[e].rChild);
		  						else
		  							node(Shl, etree[b], etree[e]);
		  						ty = (tt & UINT) ? UINT : INT;
		  					}
		  					continue;

						case Shr:
		  					next(); expr(Add);
		  					if ((tt=t|ty) >= FLOAT) 
		  						err("bad operands to >>");
		  					else if ((tt & UINT) != 0) {
		  						if (etree[b].value == Num && etree[e].value == Num)
		  							etree[e].rChild = (etree[b].rChild >> etree[e].rChild);
		  						else
		  							node(Sru, etree[b], etree[e]);
		  						ty = UINT;
		  					} else { 
		  						if (etree[b].value == Num && etree[e].value == Num) 
		  							etree[e].rChild = (etree[b].rChild >> etree[e].rChild);
		  						else
		  							node(Shr, etree[b], etree[e]);
		  						ty = (tt & UINT) ? UINT : INT;
		  					}
		  					continue;
					
						case Add:
							next(); expr(Mul);
							if ((t & PAMASK) != 0 && ty <= UINT) {
								if ((tt = tinc(t)) > 1) {
									node(Num, null, tt);
									etree[e].value = Num;
									mul(expr[e-1]);
								}
								add(expr[b]); ty = t;
							} else if ((ty & PAMASK) != 0 && t <= UINT) {
								if ((tt = tinc(ty)) > 1) {
									d = e;
									node(Num, null, tt);
									mul(expr[b]); add(expr[d]);
								} else
									add(expr[b]);
							} else if ((tt = t|ty) >= STRUCT)
								err("bad operands to +");
							else if ((tt && FLOAT) != 0) {
								d = flot(expr[e-1], ty);
								b = flot(expr[b], t);
								if (etree[b].value == Numf && etree[d].value == Numf) {
									etree[e].value = Numf;
									etree[e].rChild = Number(expr[b].rChild) + Number(expr[d].rChild);
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
								node(Sub, etree[b], etree[e]);
								d = e;
								node(Num, null, tt);
								node(Div, etree[d], etree[e]);
								ty = INT;
							} else if ((t & PAMASK) != 0 && ty <= UINT) {
								if ((tt = tinc(t)) > 1) {
									node(Num, null, tt);
									mul(etree[e]);
								}
								if (etree[e].value == Num) {
									etree[e].rChild *= -1;
									add(etree[b]);
								} else
									node(Sub, etree[b], etree[e]);
								ty = t;
							} else if ((tt=t|ty) >= STRUCT)
								err("bad operands to -");
							else if (tt & FLOAT) {
								d = flot(etree[e], ty);
								b = flot(etree[b], t);
								if (etree[b].value == Numf && etree[d].value == Numf) {
									etree[e].value = Numf;
									etree[e].rChild = Number(etree[b].rChild) - Number(etree[d].rChild);
								} else node(Subf, etree[b], etree[d]);
								ty = DOUBLE;
							} else {
								if (etree[e].value == Num) {
									etree[e].rChild *= -1;
									add(etree[b]);
								} else
									node(Sub, etree[b], etree[e]);
								ty = (tt & UINT) ? UINT : INT;
							}
							continue;
						
						case Mul:
		  					next(); expr(Inc);
		  					if ((tt=t|ty) >= STRUCT) 
		  						err("bad operands to *");
		  					else if ((tt & FLOAT) != 0) {
		    					d = flot(etree[e], ty); 
		    					b = flot(etree[b], t);
		    					if (etree[b].value == Numf && etree[d].value == Numf) {
		      						etree[e].value = Numf; 
		      						etree[e].rChild = Number(etree[b].rChild) & Number(etree[d].rChild);
		      					} else 
		      						nodc(Mulf, etree[b], etree[d]);
		      					ty = DOUBLE;
		      				} else {
		      					mul(etree[b]);
		      					ty = (tt & UINT) ? UINT : INT;
		      				}
		      				continue;
		      				
		      			case Div:
		      				next(); expr(Inc);
		      				if ((tt=t|ty) >= STRUCT) 
		  						err("bad operands to /");
		  					else if ((tt & FLOAT) != 0) {
		    					d = flot(etree[e], ty); 
		    					b = flot(etree[b], t);
		    					if (etree[b].value == Numf && etree[d].value == Numf) {
		      						etree[e].value = Numf; 
		      						etree[e].rChild = Number(etree[b].rChild) / Number(etree[d].rChild);
		      					} else 
		      						nodc(Divf, etree[b], etree[d]);
		      					ty = DOUBLE;
		      				} else if ((tt & UINT) != 0) {
		      					if (etree[b].value == Num && etree[e].value == Num && etree[e].rChild != 0) 
		      						etree[e].rChild = etree[b].rChild / etree[e].rChild;
		      					else
		      						node(Dvu, etree[b], etree[e]);
		      					ty = UINT;
		      				} else {
		      					if (etree[b].value == Num && etree[e].value == Num && etree[e].rChild != 0)
		      						etree[e].rChild = etree[b].rChild / etree[e].rChild;
		      					else
		      						node(Div, etree[b], etree[e]);
		      					ty = INT;
		      				}
		      				continue;
		  
		      			case Mod:
							next(); expr(Inc);
							if ((tt=t|ty) >= FLOAT) 
						  		err("bad operands to %");
						  	else if ((tt & UINT) != 0) { 
						  		if (etree[b].value == Num && etree[e].value == Num && etree[e].rChild != 0) 
						  			etree[e].rChild = etree[b].rChild % etree[e].rChild; 
						  		else 
						  			node(Mdu, etree[b], etree[e]); 
						  		ty = UINT; 
						  	} else { 
						  		if (etree[b].value == Num && etree[e].value == Num && etree[e].rChild != 0) 
						  			etree[e].rChild = etree[b].rChild % etree[e].rChild; 
						  		else 
						  			node(Mod, etree[b], etree[e]); 
						  		ty = INT; 
						  	}
						 	continue;

						case Inc:
							next();
						  	if ((ty & PMASK) == 0 && ty >= FLOAT) 
						  		err("bad operand to ++"); // XXX doesn't support floats
						  	else { 
						  		node(Num, null, -tinc(ty));
						  		node(Suba, etree[b], null);
						  		add(etree[e-1]);
						  	}
						  	continue;
		
						case Dec:
							next();
						  	if ((ty & PMASK) == 0 && ty >= FLOAT) 
						  		err("bad operand to --"); // XXX doesn't support floats
						  	else { 
						  		node(Num, null, tinc(ty));
						  		node(Suba, etree[b], null);
						  		add(etree[e-1]);
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
							for (m = va_var[ty>>TSHIFT].value.member; m != null; m = m.next) 
								if (m.id == id) found = true;
							if (found == false) { 
								err("struct or union member not found");
								next();
								continue;
							}
							node(Num, null, m.offset);
							add(etree[e-1]);
							if ((m.type & TMASK) == ARRAY)
								ty = m.type;
							else {
								ty = m.type + PTR; 
								ind(); 
							}      
		  					next();
		  					continue;
		
						case Brak: // XXX these dont quite work when used with pointers?  still? test?
		  					next();  // addr(); b = e; t = ty; // XXX
							expr(Comma);
							skip(']');
							d = e;
							node(Num, null, tinc(t));
							mul(etree[d]);
							add(etree[b]);
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
						  	d = e;
						  	b = 0;
						  	while (tk != ')') {
								expr(Assign);
								switch (tt & 3) {
									case 1: cast(DOUBLE); ty = DOUBLE; break;
									case 2: cast(INT); 	  ty = INT; break;
									case 3: cast(UINT);   ty = UINT;
								}
								tt >>= 2;
								node(b, ty, null);
								b = e;
								if (tk == Comma) next();
						  	}
						  	skip(')');
						  	node(Fcall, etree[d], etree[b]);
						  	ty = t;
						  	continue;
						  
						 default:
		  					print(sprintf("fatal compiler error expr() tk=%d\n", tk)); 
		  					return -1;
					}
	  			}
	  		}
	  		
	  		// --------------------------------------------------------------------------------------
	  		// 		expression generation
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
  				var d = 0.0; // double d;
  				switch (b.value) {
  					case Auto:   eml(LBL+lmod(b.lChild), b.rChild); return;
  					case Static: emg(LBG+lmod(b.lChild), b.rChild); return;
  					case Numf:
						d = Number(b.rChild);
						if ((parseInt(d*256.0)<<8>>8)/256.0 == d) 
							emi(LBIF, d*256.0);
						else { 
							data = (data+7)&-8; 
							gs_seg[data].value = d;
							gs_seg[data+1].addr = gs_seg[data].addr + 8;
							data += 1;
							emg(LBGD, data);
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
					case Numf: rv(a.lChild); lbf(b); return;
			  		default:
						rv(b); a = a.lChild;
						switch (a.value) {
							case Auto:
							case Static:
							case Numf: em(LBAD); rv(a); return;
							default: loc -= 8; em(PSHF); rv(a); em(POPG); loc += 8; return;
						}
				}
			}
			
			function opaf(a, o, comm) {
  				var t ;
  				var b = (a.rChild == null ? etree[a.addr-1] : a.rChild);
  				a = a.lChild;
  				var a2 = (a.rChild == null ? etree[a.addr-1] : a.rChild);
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
						if (t == 0) em(a.lChild < UINT ? CDI : CDU); 
						emg(SG+smod(a.lChild), a.rChild);
						return 0;
					case Ptr:
						switch (b.value) {
							case Auto:
							case Static:
							case Numf: rv(a2); lbf(b); loc -= 8; break; // *expr fop= simple
							default: rv(b); loc -= 8; em(PSHF); rv(a2); em(POPG); break; // *expr fop= expr
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
				var b = (a.rChild == null ? etree[a.addr-1] : a.rChild);
		  		switch (b.value) {
		  			case Auto:
					case Static:
					case Num: rv(a.lChild); lb(b); return;
					default:
						rv(b); a = a.lChild;
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
				var b = (a.rChild == null ? etree[a.addr-1] : a.rChild);
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
				var t = null;
				var b = (a.rChild == null ? etree[a.addr-1] : a.rChild);
		  		a = a.lChild;
		  		var a2 = (a.rChild == null ? etree[a.addr-1] : a.rChild);
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
							emg(LG+lmod(a.lChild),a.rChild); 
							eml(o+OPL,b.rChild); 
						} // glo op= locint
						else if (comm != 0) { 
							rv(b); 
							emg(LBG+lmod(a.lChild),a.rChild); 
							em(o); 
						} // glo comm= expr
						else { 
							lb(b); 
							emg(LG+lmod(a.lChild),a.rChild); 
							em(o); 
						} // glo op= expr
						emg(SG+smod(a.lChild),a.rChild);
						return;
		  			case Ptr: 
						if (b.value == Num && (b.rChild<<8)>>8 == b.rChild) { 
							rv(a2); 
							em(LBA); 
							em(LX+lmod(a.lChild)); 
							emi(o+OPI,b.rChild); 
						} // *expr op= num
						else if (b.value == Auto && !lmod(b.lChild))  { 
							rv(a2); 
							em(LBA); 
							em(LX+lmod(a.lChild)); 
							eml(o+OPL,b.rChild); 
						} // *expr op= locint
						else {
							switch (b.value) {
								case Auto:
								case Static:
						  		case Num: 
						  			rv(a2); 
						  			lb(b); 
						  			loc -= 8; 
						  			em(PSHA); 
						  			em(LX+lmod(a.lChild)); 
						  			em(o); 
						  			em(POPB); 
						  			loc += 8; 
						  			break; // *expr op= simple
						  		default: 
						  			rv(b); 
						  			loc -= 8; 
						  			em(PSHA); 
						  			rv(a2); 
						  			em(LBA); 
						  			em(LX+lmod(a.lChild)); em(o+OPL); emi(ENT,8); loc += 8; // *expr op= expr
			  				}    
						}
						em(SX+smod(a.lChild)); // XXX many more (SX,imm) optimizations possible (here and elsewhere)
						return;
		  			default: err("lvalue expected");
		  		}  
			}
			
			function test(a, t) {
  				var b = null, a2 = (a.rChild == null ? expr[a.addr-1] : a.rChild);
				switch (a.value) {
					case Eq:  opt(a); return emf(BE,  t);
			 	 	case Ne:  opt(a); return emf(BNE, t);
			  		case Lt:  opt(a); return emf(BLT, t);
			  		case Ge:  opt(a); return emf(BGE, t);
			  		case Ltu: opt(a); return emf(BLTU,t);
			  		case Geu: opt(a); return emf(BGEU,t);
			  		case Eqf: opf(a); return emf(BEF, t);
			  		case Nef: opf(a); return emf(BNEF,t);
			  		case Ltf: opf(a); return emf(BLTF,t);
			  		case Gef: opf(a); return emf(BGEF,t);
			  		case Lor: return test(a2,test(a.lChild, t));
			  		case Lan: b = testnot(a.lChild,0); t = test(expr[a.addr-1],t); patch(b,ip); return t;
			  		case Not: return testnot(expr[a.addr-1],t);
			  		case Notf: rv(a2); return emf(BZF, t);
			  		case Nzf:  rv(a2); return emf(BNZF,t);
			  		case Num: if (a.rChild != null) return emf(JMP,t); return t;
			  		case Numf: if (Number(a.rChild) == 0) return emf(JMP,t); return t;
			  		default: rv(a); return emf(BNZ,t);
				}
			}

			function testnot(a, t) {
				var b = null;
				switch (a.value) {
					case Eq:  opt(a); return emf(BNE, t);
				  	case Ne:  opt(a); return emf(BE,  t);
				  	case Lt:  opt(a); return emf(BGE, t);
				  	case Ge:  opt(a); return emf(BLT, t);
				  	case Ltu: opt(a); return emf(BGEU,t);
				  	case Geu: opt(a); return emf(BLTU,t);
				  	case Eqf: opf(a); return emf(BNEF,t);
				  	case Nef: opf(a); return emf(BEF, t);
				  	case Ltf: opf(a); return emf(BGEF,t);
				  	case Gef: opf(a); return emf(BLTF,t);
				  	case Lor: b = test(a.lChild,0); t = testnot(expr[a.addr-1],t); patch(b,ip); return t;
				  	case Lan: return testnot(expr[a.addr-1],testnot(a.lChild,t));
				  	case Not: return test(expr[a.addr-1],t);
				  	case Notf: rv(expr[a.addr-1]); return emf(BNZF,t);
				  	case Nzf: rv(expr[a.addr-1]); return emf(BZF,t);
				  	case Num: if (a.rChild == 0) return emf(JMP,t); return t;
				  	case Numf: if (Number(a.rChild) == 0) return emf(JMP,t); return t;
				  	default: rv(a); return emf(BZ,t);
				}
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
