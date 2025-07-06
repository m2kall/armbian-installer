#!/bin/bash
# 这是为创建 EXT4 安装盘而优化的新构建脚本。
# 它包含了新的 'dd' 智能安装脚本以及其所有依赖。
set -e

echo "Install required tools on the host"
apt-get update
apt-get -y install debootstrap squashfs-tools xorriso isolinux syslinux-efi grub-pc-bin grub-efi-amd64-bin mtools dosfstools parted

echo "Create directory where we will make the image"
mkdir -p $HOME/LIVE_BOOT

echo "Install Debian base system (chroot)"
debootstrap --arch=amd64 --variant=minbase buster $HOME/LIVE_BOOT/chroot http://ftp.us.debian.org/debian/

echo "Copy supporting documents into the chroot"
cp -v /supportFiles/installChroot.sh $HOME/LIVE_BOOT/chroot/installChroot.sh
# 复制原始的 'ddd' 脚本 (用于 squashfs)
cp -v /supportFiles/immortalwrt/ddd $HOME/LIVE_BOOT/chroot/usr/bin/ddd
chmod +x $HOME/LIVE_BOOT/chroot/usr/bin/ddd
# 复制新的 'dd' 脚本 (用于 ext4)
cp -v /supportFiles/immortalwrt/dd $HOME/LIVE_BOOT/chroot/usr/bin/dd
chmod +x $HOME/LIVE_BOOT/chroot/usr/bin/dd
cp -v /supportFiles/sources.list $HOME/LIVE_BOOT/chroot/etc/apt/sources.list

echo "Mounting dev / proc / sys"
mount -t proc none $HOME/LIVE_BOOT/chroot/proc
mount -o bind /dev $HOME/LIVE_BOOT/chroot/dev
mount -o bind /sys $HOME/LIVE_BOOT/chroot/sys

# --- 关键步骤: 在 chroot 内部安装 GRUB，供 'dd' 脚本使用 ---
echo "Install GRUB inside the chroot for the installer script"
chroot $HOME/LIVE_BOOT/chroot apt-get update
chroot $HOME/LIVE_BOOT/chroot apt-get -y install grub-efi-amd64-bin

echo "Run main install script inside chroot"
chroot $HOME/LIVE_BOOT/chroot /installChroot.sh

echo "Cleanup chroot"
rm -v $HOME/LIVE_BOOT/chroot/installChroot.sh
mv -v $HOME/LIVE_BOOT/chroot/packages.txt /output/packages.txt

echo "Copy in systemd-networkd config"
cp -v /supportFiles/99-dhcp-en.network $HOME/LIVE_BOOT/chroot/etc/systemd/network/99-dhcp-en.network
chown -v root:root $HOME/LIVE_BOOT/chroot/etc/systemd/network/99-dhcp-en.network
chmod -v 644 $HOME/LIVE_BOOT/chroot/etc/systemd/network/99-dhcp-en.network

echo "Enable autologin"
mkdir -p -v $HOME/LIVE_BOOT/chroot/etc/systemd/system/getty@tty1.service.d/
cp -v /supportFiles/override.conf $HOME/LIVE_BOOT/chroot/etc/systemd/system/getty@tty1.service.d/override.conf

echo "Unmounting dev / proc / sys"
umount $HOME/LIVE_BOOT/chroot/proc
umount $HOME/LIVE_BOOT/chroot/dev
umount $HOME/LIVE_BOOT/chroot/sys

echo "Create directories for the live environment"
mkdir -p $HOME/LIVE_BOOT/{staging/{EFI/boot,boot/grub/x86_64-efi,isolinux,live},tmp}

echo "Copy the ext4 image into the chroot environment for installation"
# 此镜像将在 Live OS 中被 'dd' 脚本通过 /mnt/immortalwrt.img 路径访问
cp /mnt/immortalwrt.img ${HOME}/LIVE_BOOT/chroot/mnt/
ls -lh ${HOME}/LIVE_BOOT/chroot/mnt/

echo "Compress the chroot environment into a Squash filesystem"
mksquashfs $HOME/LIVE_BOOT/chroot $HOME/LIVE_BOOT/staging/live/filesystem.squashfs -e boot

echo "Copy kernel and initrd from chroot to the live environment"
cp -v $HOME/LIVE_BOOT/chroot/boot/vmlinuz-* $HOME/LIVE_BOOT/staging/live/vmlinuz
cp -v $HOME/LIVE_BOOT/chroot/boot/initrd.img-* $HOME/LIVE_BOOT/staging/live/initrd

echo "Copy boot config files"
cp -v /supportFiles/immortalwrt/isolinux.cfg $HOME/LIVE_BOOT/staging/isolinux/isolinux.cfg
cp -v /supportFiles/immortalwrt/grub.cfg $HOME/LIVE_BOOT/staging/boot/grub/grub.cfg
cp -v /supportFiles/grub-standalone.cfg $HOME/LIVE_BOOT/tmp/grub-standalone.cfg
touch $HOME/LIVE_BOOT/staging/DEBIAN_CUSTOM

echo "Copy boot images"
cp -v /usr/lib/ISOLINUX/isolinux.bin "${HOME}/LIVE_BOOT/staging/isolinux/"
cp -v /usr/lib/syslinux/modules/bios/* "${HOME}/LIVE_BOOT/staging/isolinux/"
cp -v -r /usr/lib/grub/x86_64-efi/* "${HOME}/LIVE_BOOT/staging/boot/grub/x86_64-efi/"

echo "Make UEFI grub files"
grub-mkstandalone --format=x86_64-efi --output=$HOME/LIVE_BOOT/tmp/bootx64.efi --locales="" --fonts="" "boot/grub/grub.cfg=$HOME/LIVE_BOOT/tmp/grub-standalone.cfg"

cd $HOME/LIVE_BOOT/staging/EFI/boot
SIZE=`expr $(stat --format=%s $HOME/LIVE_BOOT/tmp/bootx64.efi) + 65536`
dd if=/dev/zero of=efiboot.img bs=$SIZE count=1
/sbin/mkfs.vfat efiboot.img
mmd -i efiboot.img efi efi/boot
mcopy -vi efiboot.img $HOME/LIVE_BOOT/tmp/bootx64.efi ::efi/boot/

echo "Build the final ISO image"
xorriso \
    -as mkisofs \
    -iso-level 3 \
    -o "${HOME}/LIVE_BOOT/debian-custom.iso" \
    -full-iso9660-filenames \
    -volid "DEBIAN_CUSTOM" \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -eltorito-boot \
        isolinux/isolinux.bin \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        --eltorito-catalog isolinux/isolinux.cat \
    -eltorito-alt-boot \
        -e /EFI/boot/efiboot.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
    -append_partition 2 0xef ${HOME}/LIVE_BOOT/staging/EFI/boot/efiboot.img \
    "${HOME}/LIVE_BOOT/staging"

echo "Copy final ISO to output directory with a new name for EXT4"
cp -v $HOME/LIVE_BOOT/debian-custom.iso /output/immortalwrt-installer-generic-ext4-combined-x86_64.iso
chmod -v 666 /output/immortalwrt-installer-generic-ext4-combined-x86_64.iso
echo "Build finished. Final files in /output:"
ls -lah /output
