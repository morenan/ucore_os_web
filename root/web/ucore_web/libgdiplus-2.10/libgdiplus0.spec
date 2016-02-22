%define real_name libgdiplus
# There may be strange bugs when using the system cairo
%define system_cairo 0

Name:           libgdiplus0
Version:        2.10
Release:        0
License:        LGPL v2.1 only ; MPL ; MIT License (or similar)
Url:            http://go-mono.org/
Source0:        %{real_name}-%{version}.tar.bz2
Summary:        Open Source Implementation of the GDI+ API
Group:          Development/Libraries/Other
BuildRoot:      %{_tmppath}/%{name}-%{version}-build
Obsoletes:      libgdiplus-devel
Provides:       libgdiplus-devel
Obsoletes:      libgdiplus
Provides:       libgdiplus
%if %system_cairo
BuildRequires:  cairo-devel >= 1.6.4
%endif
BuildRequires:  fontconfig-devel
BuildRequires:  freetype2-devel
BuildRequires:  giflib-devel
BuildRequires:  glib2-devel
BuildRequires:  libexif-devel
BuildRequires:  libjpeg-devel
BuildRequires:  libpng-devel
BuildRequires:  libtiff-devel
BuildRequires:  xorg-x11-libXrender-devel

%description
This is part of the Mono project. It is required when using
Windows.Forms.

%files
%defattr(-, root, root)
%_libdir/libgdiplus.so*
%_libdir/pkgconfig/libgdiplus.pc
%doc AUTHORS COPYING ChangeLog* NEWS README

%prep
%setup -q -n %{real_name}-%{version}

%build
export CFLAGS="$RPM_OPT_FLAGS"
%configure
make

%install
make install DESTDIR=%{buildroot}
# Unwanted files:
rm -f %{buildroot}%{_libdir}/libgdiplus.a
rm -f %{buildroot}%{_libdir}/libgdiplus.la
# Remove generic non-usefull INSTALL file... (appeases
#  suse rpmlint checks, saves 3kb)
find . -name INSTALL | xargs rm -f

%clean
rm -rf "$RPM_BUILD_ROOT"

%post -p /sbin/ldconfig

%postun -p /sbin/ldconfig

%changelog
