/* config.h.  Generated from config.h.in by configure.  */
/* config.h.in.  Generated from configure.in by autoheader.  */

/* Define if building universal (internal helper macro) */
/* #undef AC_APPLE_UNIVERSAL_BUILD */

/* OpenBSD */
/* #undef BSDOS */

/* Win32 */
/* #undef CYGWIN */

/* Define to 1 if you have the <byteswap.h> header file. */
#define HAVE_BYTESWAP_H 1

/* Define to 1 if you have the <dlfcn.h> header file. */
#define HAVE_DLFCN_H 1

/* Define to 1 if you have the `FcFini' function. */
#define HAVE_FCFINI 1

/* Define to 1 if you have the <inttypes.h> header file. */
#define HAVE_INTTYPES_H 1

/* Define if libexif is available. */
/* #undef HAVE_LIBEXIF */

/* Define to 1 if you have the `fontconfig' library (-lfontconfig). */
#define HAVE_LIBFONTCONFIG 1

/* Define if gif support is available */
/* #undef HAVE_LIBGIF */

/* Define to 1 if you have the `intl' library (-lintl). */
/* #undef HAVE_LIBINTL */

/* Define if jpeg support is available */
/* #undef HAVE_LIBJPEG */

/* Define if png support is available. Always defined. */
#define HAVE_LIBPNG 1

/* Define to 1 if you have the `pthread' library (-lpthread). */
#define HAVE_LIBPTHREAD 1

/* Define if tiff support is available */
/* #undef HAVE_LIBTIFF */

/* Define to 1 if you have the <memory.h> header file. */
#define HAVE_MEMORY_H 1

/* sigsetjmp is available */
#define HAVE_SIGSETJMP 1

/* Define to 1 if you have the <stdint.h> header file. */
#define HAVE_STDINT_H 1

/* Define to 1 if you have the <stdlib.h> header file. */
#define HAVE_STDLIB_H 1

/* Define to 1 if you have the <strings.h> header file. */
#define HAVE_STRINGS_H 1

/* Define to 1 if you have the <string.h> header file. */
#define HAVE_STRING_H 1

/* Define to 1 if you have the <sys/stat.h> header file. */
#define HAVE_SYS_STAT_H 1

/* Define to 1 if you have the <sys/types.h> header file. */
#define HAVE_SYS_TYPES_H 1

/* Define to 1 if you have the <unistd.h> header file. */
#define HAVE_UNISTD_H 1

/* Support for the visibility ("hidden") attribute */
#define HAVE_VISIBILITY_HIDDEN 1

/* Linux */
#define LINUX 1

/* Define to the sub-directory in which libtool stores uninstalled libraries.
   */
#define LT_OBJDIR ".libs/"

/* OS X */
/* #undef OSX */

/* Unknown */
/* #undef OTHEROS */

/* Name of package */
#define PACKAGE "libgdiplus"

/* Define to the address where bug reports for this package should be sent. */
#define PACKAGE_BUGREPORT ""

/* Define to the full name of this package. */
#define PACKAGE_NAME ""

/* Define to the full name and version of this package. */
#define PACKAGE_STRING ""

/* Define to the one symbol short name of this package. */
#define PACKAGE_TARNAME ""

/* Define to the version of this package. */
#define PACKAGE_VERSION ""

/* Solaris */
/* #undef SOLARIS */

/* Define to 1 if you have the ANSI C header files. */
#define STDC_HEADERS 1

/* Use Cairo/pixman bundled in libgdiplus */
#define USE_INCLUDED_CAIRO 1

/* Use Pango to measure and draw text (INCOMPLETE and UNSUPPORTED) */
/* #undef USE_PANGO_RENDERING */

/* Version number of package */
#define VERSION "2.10"

/* Define WORDS_BIGENDIAN to 1 if your processor stores words with the most
   significant byte first (like Motorola and SPARC, unlike Intel). */
#if defined AC_APPLE_UNIVERSAL_BUILD
# if defined __BIG_ENDIAN__
#  define WORDS_BIGENDIAN 1
# endif
#else
# ifndef WORDS_BIGENDIAN
/* #  undef WORDS_BIGENDIAN */
# endif
#endif

/* For libc reentrancy */
/* #undef _REENTRANT */
