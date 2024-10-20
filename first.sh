#### 2.4
# create a img for lfs system of 20GB
dd if=/dev/zero of=lfs.img bs=1M count=20000

#### 2.5
# create file system ext4 for img
mkfs.ext4 lfs.img

#### 2.6
# LFS variable setting
export LFS=/mnt/lfs
# verify correctly set of LFS variable
echo $LFS

####2.7
# create a mount point
mkdir -pv /mnt/lfs
# mount img
mount -o loop lfs.img /mnt/lfs

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
#


#
