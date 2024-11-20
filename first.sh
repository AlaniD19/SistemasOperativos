#### 2.4
# create a img for lfs system of 20GB
dd if=/dev/zero of=lfs.img bs=1M count=20000
# mount loop device
losetup -fP lfs.img
# create table partition
fdisk /dev/loop0
# boot partition
n
p
#enter
+500M
# swap partition
n
p
#enter
+2G
# root partition
n
p
#enter
#enter

#### 2.5
# create file system for img
mkfs.ext4 /dev/loop0p1  # ext4 for boot
mkswap /dev/loop0p2     # swap creation
swapon /dev/loop0p2     # activate swap
mkfs.ext4 /dev/loop0p3  # ext4 for /

#### 2.6
# LFS variable setting
export LFS=/mnt/lfs
# verify correctly set of LFS variable
echo $LFS

####2.7
# create a mount point
mkdir -pv /mnt/lfs
# mount img /
mount /dev/loop0p3 /mnt/lfs
# mount point for boot
mkdir -p /mnt/lfs/boot
mount /dev/sda1 /mnt/lfs/boot

#### 3.1
# create directory for packages and patches
mkdir -v  $LFS/sources
# add sticky bits
chmod -v a+wt $LFS/sources
# download packages and modules
wget --input-file=wget-list-sysv --continue --directory-prefix=$LFS/sources
# add UID bits
chown root:root $LFS/sources/*

#### 4.2
mkdir -pv $LFS/{etc,var} $LFS/usr/{bin,lib,sbin}
for i in bin lib sbin; do
    ln -sv usr/$i $LFS/$i
done
case $(uname -m) in
    x86_64) mkdir -pv $LFS/lib64 ;;
esac
mkdir -pv $LFS/tools

#### 4.3
# create user lfs
groupadd lfs
# add properties for lfs user
useradd -s /bin/bash -g lfs -m -k /dev/null lfs
# set password for lfs user
echo "lfs:pruebita" | chpasswd
# grant full access for directories
chown -v lfs $LFS/{usr{,/*},lib,var,etc,bin,sbin,tools}
case $(uname -m) in
x86_64) chown -v lfs $LFS/lib64 ;;
esac
# run shell like lfs user
su - lfs

#### 4.4
# setup enviroment
cat > ~/.bash_profile << "EOF"
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' /bin/bash
EOF
# new instance for shell
cat > ~/.bashrc << "EOF"
set +h
umask 022
LFS=/mnt/lfs
LC_ALL=POSIX
LFS_TGT=$(uname -m)-lfs-linux-gnu
PATH=/usr/bin
if [ ! -L /bin ]; then PATH=/bin:$PATH; fi
PATH=$LFS/tools/bin:$PATH
CONFIG_SITE=$LFS/usr/share/config.site
export LFS LC_ALL LFS_TGT PATH CONFIG_SITE
EOF
#
[ ! -e /etc/bash.bashrc ] || mv -v /etc/bash.bashrc /etc/bash.bashrc.NOUSE 
#
make -j32
#
export MAKEFLAGS=-j32
#
cat >> ~/.bashrc << "EOF"
export MAKEFLAGS=-j$(nproc)
EOF
#
source ~/.bash_profile

#### 5.2
# change to sources directory
cd $LFS/sources/
# for compiled each package I used:
# tar -xf package-1.0.tar.gz          # for unzip package
# cd package-1.0                      # change into directory
# ./configure --prefix=/usr           # compile package
# make

# Binutils-2.43.1 - pass 1
tar -xf binutils-2.43.1.tar.xz
cd binutils-2.43.1
mkdir -v build
cd       build
../configure --prefix=$LFS/tools \
             --with-sysroot=$LFS \
             --target=$LFS_TGT   \
             --disable-nls       \
             --enable-gprofng=no \
             --disable-werror    \
             --enable-new-dtags  \
             --enable-default-hash-style=gnu
make
make install
cd $LFS/sources

# GCC-14.2.0 - Pass 1
tar gcc-14.2.0.tar.xz
cd gcc-14.2.0
tar -xf ../mpfr-4.2.1.tar.xz
mv -v mpfr-4.2.1 mpfr
tar -xf ../gmp-6.3.0.tar.xz
mv -v gmp-6.3.0 gmp
tar -xf ../mpc-1.3.1.tar.gz
mv -v mpc-1.3.1 mpc
case $(uname -m) in
x86_64)
sed -e '/m64=/s/lib64/lib/' \
    -i.orig gcc/config/i386/t-linux64
;;
esac
mkdir -v build
cd       build
../configure                  \
    --target=$LFS_TGT         \
    --prefix=$LFS/tools       \
    --with-glibc-version=2.40 \
    --with-sysroot=$LFS       \
    --with-newlib             \
    --without-headers         \
    --enable-default-pie      \
    --enable-default-ssp      \
    --disable-nls             \
    --disable-shared          \
    --disable-multilib        \
    --disable-threads         \
    --disable-libatomic       \
    --disable-libgomp         \
    --disable-libquadmath     \
    --disable-libssp          \
    --disable-libvtv          \
    --disable-libstdcxx       \
    --enable-languages=c,c++
make
make install
cd ..
cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
`dirname $($LFS_TGT-gcc -print-libgcc-file-name)`/include/limits.h
cd $LFS/sources

# Linux-6.10.5 API Headers
tar -xf linux-6.11.8.tar.xz
cd linux-6.11.8
make mrpropoer
make headers
find usr/include -type f ! -name '*.h' -delete
cp -rv usr/include $LFS/usr
cd $LFS/sources

# Glibc-2.40
tar -xf glibc-2.40.tar.xz
cd glibc-2.40.tar.xz
case $(uname -m) in
    i?86)   ln -sfv ld-linux.so.2 $LFS/lib/ld-lsb.so.3
    ;;
    x86_64) ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64
           ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64/ld-lsb-x86-64.so.3
    ;;
esac
patch -Np1 -i ../glibc-2.40-fhs-1.patch
mkdir -v build
cd       build
echo "rootsbindir=/usr/sbin" > configparms
../configure                             \
      --prefix=/usr                      \
      --host=$LFS_TGT                    \
      --build=$(../scripts/config.guess) \
      --enable-kernel=4.19               \
      --with-headers=$LFS/usr/include    \
      --disable-nscd                     \
      libc_cv_slibdir=/usr/lib
make
make DESTDIR=$LFS install
sed '/RTLDLIST=/s@/usr@@g' -i $LFS/usr/bin/ldd
echo 'int main(){}' | $LFS_TGT-gcc -xc -
readelf -l a.out | grep ld-linux
echo "Press any key to continue and delete a.out"
read -n 1 -s  # Espera hasta que presiones una tecla
rm -v a.out
cd $LFS/sources

# Libstdc++ from GCC-14.2.0
cd gcc-14.2.0
mkdir -v build
cd       build
../libstdc++-v3/configure           \
    --host=$LFS_TGT                 \
    --build=$(../config.guess)      \
    --prefix=/usr                   \
    --disable-multilib              \
    --disable-nls                   \
    --disable-libstdcxx-pch         \
    --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/14.2.0
make
make DESTDIR=$LFS install
rm -v $LFS/usr/lib/lib{stdc++{,exp,fs},supc++}.la
cd $LFS/sources

#### 6 
# M4-1.4.19
tar -xf m4-1.4.19.tar.xz
cd m4-1.4.19
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cd $LFS/sources

# Ncurses-6.5
tar -xf ncurses-6.5.tar.gz
cd ncurses-6.5
sed -i s/mawk// configure
mkdir build
pushd build
    ../configure
    make -C include
    make -C progs tic
popd
./configure --prefix=/usr                \
            --host=$LFS_TGT              \
            --build=$(./config.guess)    \
            --mandir=/usr/share/man      \
            --with-manpage-format=normal \
            --with-shared                \
            --without-normal             \
            --with-cxx-shared            \
            --without-debug              \
            --without-ada                \
            --disable-stripping
make
make DESTDIR=$LFS TIC_PATH=$(pwd)/build/progs/tic install
ln -sv libncursesw.so $LFS/usr/lib/libncurses.so
sed -e 's/^#if.*XOPEN.*$/#if 1/' \
    -i $LFS/usr/include/curses.h
cd $LFS/sources

# Bash-5.2.32
tar -xf bash-5.2.32.tar.gz
cd bash-5.2.32
./configure --prefix=/usr                      \
            --build=$(sh support/config.guess) \
            --host=$LFS_TGT                    \
            --without-bash-malloc              \
            bash_cv_strtold_broken=no
make
make DESTDIR=$LFS install
ln -sv bash $LFS/bin/sh
cd $LFS/sources

# Coreutils-9.5
tar -xf coreutils-9.5.tar.xz
cd coreutils-9.5
./configure --prefix=/usr                     \
            --host=$LFS_TGT                   \
            --build=$(build-aux/config.guess) \
            --enable-install-program=hostname \
            --enable-no-install-program=kill,uptime
make
make DESTDIR=$LFS install
mv -v $LFS/usr/bin/chroot              $LFS/usr/sbin
mkdir -pv $LFS/usr/share/man/man8
mv -v $LFS/usr/share/man/man1/chroot.1 $LFS/usr/share/man/man8/chroot.8
sed -i 's/"1"/"8"/'                    $LFS/usr/share/man/man8/chroot.8
cd $LFS/sources

# Diffutils-3.10
tar -xf diffutils-3.10.tar.xz
cd diffutils-3.10
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(./build-aux/config.guess)
makemake DESTDIR=$LFS install
cd $LFS/sources

# File-5.45
tar -xf file-5.45.tar.gz
cd file-5.45
mkdir build
pushd build
  ../configure --disable-bzlib      \
               --disable-libseccomp \
               --disable-xzlib      \
               --disable-zlib
  make
popd
./configure --prefix=/usr --host=$LFS_TGT --build=$(./config.guess)
make FILE_COMPILE=$(pwd)/build/src/file
make DESTDIR=$LFS install
rm -v $LFS/usr/lib/libmagic.la
cd $LFS/sources

# Findutils-4.10.0
tar -xf findutils-4.10.tar.xz
cd findutils-4.10
./configure --prefix=/usr                   \
            --localstatedir=/var/lib/locate \
            --host=$LFS_TGT                 \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cd $LFS/sources

# Gawk-5.3.0
tar -xf gawk-5.3.0.tar.xz
cd gawk-5.3.0
sed -i 's/extras//' Makefile.in
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cd $LFS/sources

# Grep-3.11
tar -xf grep-3.11.tar.xz
cd grep-3.11
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(./build-aux/config.guess)
make
make DESTDIR=$LFS install
cd $LFS/sources

# Gzip-1.13
tar -xf gzip-1.13.tar.xz
cd gzip-1.13
./configure --prefix=/usr --host=$LFS_TGT
make
make DESTDIR=$LFS install
cd $LFS/sources

# Make-4.4.1
tar make-4.4.1.tar.gz
cd make-4.4.1
./configure --prefix=/usr   \
            --without-guile \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cd $LFS/sources

# Patch-2.7.6
tar -xf patch-2.7.6.tar.xz
cd patch-2.7.6
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cd $LFS/sources

# Sed-4.9
tar -xf sed-4.9.tar.xz
cd sed-4.9
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(./build-aux/config.guess)
make
make DESTDIR=$LFS install
cd $LFS/sources

# Tar-1.35
tar -xf tar-1.35.tar.xz
cd tar-1.35
./configure --prefix=/usr                     \
            --host=$LFS_TGT                   \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cd $LFS/sources

# Xz-5.6.2
tar -xf xz-5.6.2.tar.xz
cd xz-5.6.2
./configure --prefix=/usr                     \
            --host=$LFS_TGT                   \
            --build=$(build-aux/config.guess) \
            --disable-static                  \
            --docdir=/usr/share/doc/xz-5.6.2
make
make DESTDIR=$LFS install
rm -v $LFS/usr/lib/liblzma.la
cd $LFS/sources

# Binutils-2.43.1 - Pass 2
cd binutils-2.43.1
sed '6009s/$add_dir//' -i ltmain.sh
mkdir -v build
cd       build
../configure                   \
    --prefix=/usr              \
    --build=$(../config.guess) \
    --host=$LFS_TGT            \
    --disable-nls              \
    --enable-shared            \
    --enable-gprofng=no        \
    --disable-werror           \
    --enable-64-bit-bfd        \
    --enable-new-dtags         \
    --enable-default-hash-style=gnu
make
make DESTDIR=$LFS install
rm -v $LFS/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}
cd $LFS/sources

# GCC-14.2.0 - Pass 2
cd gcc-14.2.0
tar -xf ../mpfr-4.2.1.tar.xz
mv -v mpfr-4.2.1 mpfr
tar -xf ../gmp-6.3.0.tar.xz
mv -v gmp-6.3.0 gmp
tar -xf ../mpc-1.3.1.tar.gz
mv -v mpc-1.3.1 mpc
case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' \
        -i.orig gcc/config/i386/t-linux64
  ;;
esac
sed '/thread_header =/s/@.*@/gthr-posix.h/' \
    -i libgcc/Makefile.in libstdc++-v3/include/Makefile.in
mkdir -v build
cd       build
../configure                                       \
    --build=$(../config.guess)                     \
    --host=$LFS_TGT                                \
    --target=$LFS_TGT                              \
    LDFLAGS_FOR_TARGET=-L$PWD/$LFS_TGT/libgcc      \
    --prefix=/usr                                  \
    --with-build-sysroot=$LFS                      \
    --enable-default-pie                           \
    --enable-default-ssp                           \
    --disable-nls                                  \
    --disable-multilib                             \
    --disable-libatomic                            \
    --disable-libgomp                              \
    --disable-libquadmath                          \
    --disable-libsanitizer                         \
    --disable-libssp                               \
    --disable-libvtv                               \
    --enable-languages=c,c++
make
make DESTDIR=$LFS install
ln -sv gcc $LFS/usr/bin/cc
cd $LFS/sources

# 7


# 8


# 9

# 10

# 11
