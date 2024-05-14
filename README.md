# 3CX installer
Repository hosting script for installing 3CX on clean Debian system without the need to use 3CX ISO, also you can find misc script for errors and upgrade.

`git clone` require git package installed on your system, please check if you have it before continuing.

## Features
- Install 3CX on clean Debian
- Version selection (Usefull for backup/restore)

## 3CX v20 - Debian 12 (bookworm)
``` 
git clone https://github.com/Rush-er/3CXinstaller
cd 3CXinstaller
chmod +x debian12_installer-v20.sh
./debian12_installer-v20.sh
```

## 3CX v18 - Debian 11 (bullseye)
``` 
git clone https://github.com/Rush-er/3CXinstaller
cd 3CXinstaller
chmod +x debian11_installer-v18.sh
./debian11_installer-v18.sh
```

## 3CX v16 - Debian 10 (buster)
``` 
git clone https://github.com/Rush-er/3CXinstaller
cd 3CXinstaller
chmod +x debian10_installer-v16.sh
./debian10_installer-v16.sh
```


## MISC

### Fix error libfreeimage3 while upgrading from v16 to v18
``` 
chmod +x install_libfreeimage3.sh
./libfreeimage3
```

### Upgrade from v16 to v18
``` 
chmod +x upgrade.sh
./upgrade
```
