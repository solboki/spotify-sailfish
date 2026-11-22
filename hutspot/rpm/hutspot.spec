# Hutspot, fork adapted to the Spotify Web API of 2026, French translation
# and Sailfish pull-down navigation.
#
# Build on the phone:  rpmbuild -bb hutspot.spec
# (see build-rpm.sh for the needed packages)

Name:       hutspot
Summary:    Spotify controller for Sailfish OS
Version:    0.11.0
Release:    1.fork
Group:      Applications/Multimedia
License:    MIT
URL:        https://github.com/sailfish-spotify/hutspot
Source0:    %{name}-%{version}.tar.bz2

Requires:   sailfishsilica-qt5 >= 0.10.9
Requires:   nemo-qml-plugin-notifications-qt5
Requires:   curl

BuildRequires:  pkgconfig(sailfishapp) >= 1.0.2
BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  pkgconfig(openssl)
BuildRequires:  qt5-qttools-linguist
BuildRequires:  desktop-file-utils

%description
Spotify controller for Sailfish OS. Playing is done on a Spotify Connect
device, for example Spotify Soloist running on the phone.

This fork is adapted to the Spotify Web API changes of February 2026,
translated to French and uses the Sailfish pull-down menu for navigation.

%prep
%setup -q -n %{name}-%{version}

%build
QMAKE=$(command -v qmake || echo /usr/lib/qt5/bin/qmake)
$QMAKE CONFIG+=release
make %{?_smp_mflags}

%install
rm -rf %{buildroot}
make install INSTALL_ROOT=%{buildroot}
desktop-file-install --delete-original \
  --dir %{buildroot}%{_datadir}/applications \
   %{buildroot}%{_datadir}/applications/*.desktop

%files
%defattr(-,root,root,-)
%{_bindir}/%{name}
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png

%changelog
* Sun Nov 15 2026 hutspot fork - 0.7.0-1.fork
- Adapted to the Spotify Web API changes of February 2026
- French translation
- Navigation with the Sailfish pull-down menu, mini player at the bottom
- My Library: sort albums by title, artist, genre or date added
- Featured page rebuilt from the endpoints still available
- SailJail disabled so the login is kept
