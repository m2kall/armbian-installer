#!/bin/bash

echo "Install required tools"
apt-get update
apt-get -y install debootstrap xorriso isolinux syslinux-efi grub-pc-bin grub-efi-amd64-bin mtools dosfstools parted

echo "Create working directory"
mkdir -p "$HOME/LIVE_BOOT"

echo "Install Debian"
debootstrap --arch=amd64 --variant=minbase buster "$HOME/LIVE_BOOT/chroot" http://ftp.us.debian.org/debian/

echo "Copy supporting files into chroot"
cp -v /supportFiles/installChroot.sh "$HOME/LIVE_BOOT/chroot/installChroot.sh"
cp -v /supportFiles/immortalwrt/ddd "$HOME/LIVE_BOOT/chroot/usr/bin/ddd"
chmod +x "$HOME/LIVE_BOOT/chroot/usr/bin/ddd"
cp -v /supportFiles/sources.list "$HOME/LIVE_BOOT/chroot/etc/apt/sources.list"

echo "Mount dev / proc / sys"
mount -t proc none "$HOME/LIVE_BOOT/chroot/proc"
mount -o bind /dev "$HOME/LIVE_BOOT/chroot/dev"
mount -o bind /sys "$HOME/LIVE_BOOT/chroot/sys"

echo "Run install script inside chroot"
chroot "$HOME/LIVE_BOOT/chroot" /installChroot.sh

echo "Cleanup chroot"
rm -v "$HOME/LIVE_BOOT/chroot/installChroot.sh"
mv -v "$HOME/LIVE_BOOT/chroot"/packages.txt /output/packages.txt

echo "Copy network configuration"
cp -v /supportFiles/99-dhcp-en.network "$HOME/LIVE_BOOT/chroot/etc/systemd/network/99-dhcp-en.network"
chown -v root:root "$HOME/LIVE_BOOT/chroot/etc/systemd/network/99-dhcp-en.network"
chmod -v 644 "$HOME/LIVE_BOOT/chroot/etc/systemd/network/99-dhcp-en.network"

echo "Enable autologin"
mkdir -p -v "$HOME/LIVE_BOOT/chroot/etc/systemd/system/getty@tty1.service.d/"
cp -v /supportFiles/override.conf "$HOME/LIVE_BOOT/chroot/etc/systemd/system/getty@tty1.service.d/override.conf"

echo "Unmount dev / proc / sys"
umount "$HOME/LIVE_BOOT/chroot/proc"
umount "$HOME/LIVE_BOOT/chroot/dev"
umount "$HOME/LIVE_BOOT/chroot/sys"

echo "Create directories for live environment"
mkdir -p "$HOME/LIVE_BOOT"/{staging/{EFI/boot,boot/grub/x86_64-efi,isolinux,live},tmp}

# ------------------ 改动部分：用ext4镜像替代squashfs ------------------

# 1. 创建ext4镜像文件
EXT4_IMG="$HOME/LIVE_BOOT/staging/live/filesystem.img"
dd if=/dev/zero of="$EXT4_IMG" bs=1G count=2  # 根据需要调整大小
/sbin/mkfs.ext4 "$EXT4_IMG"

# 2. 挂载ext4镜像
MOUNT_PT="/mnt/ext4"
mkdir -p "$MOUNT_PT"
sudo mount -o loop "$EXT4_IMG" "$MOUNT_PT"

# 3. 复制chroot内容到挂载点
sudo cp -a "$HOME/LIVE_BOOT/chroot"/* "$MOUNT_PT"/

# 4. 卸载ext4
sudo umount "$MOUNT_PT"

# 5. 在ISO中引用这个ext4镜像
#（后续你可以在ISO配置中挂载这个ext4文件）

# -------------- 其他流程保持不变 ------------------

echo "Copy kernel and initrd"
cp -v "$HOME/LIVE_BOOT/chroot"/boot/vmlinuz-* "$HOME/LIVE_BOOT/staging/live/vmlinuz"
cp -v "$HOME/LIVE_BOOT/chroot"/boot/initrd.img-* "$HOME/LIVE_BOOT/staging/live/initrd"

echo "Copy boot config files"
cp -v /supportFiles/immortalwrt/isolinux.cfg "$HOME/LIVE_BOOT/staging/isolinux/isolinux.cfg"
cp -v /supportFiles/immortalwrt/grub.cfg "$HOME/LIVE_BOOT/staging/boot/grub/grub.cfg"
cp -v /supportFiles/grub-standalone.cfg "$HOME/LIVE_BOOT/tmp/grub-standalone.cfg"
touch "$HOME/LIVE_BOOT/staging/DEBIAN_CUSTOM"

echo "Copy boot images"
cp -v /usr/lib/ISOLINUX/isolinux.bin "$HOME/LIVE_BOOT/staging/isolinux/"
cp -v /usr/lib/syslinux/modules/bios/* "$HOME/LIVE_BOOT/staging/isolinux/"
cp -v -r /usr/lib/grub/x86_64-efi/* "$HOME/LIVE_BOOT/staging/boot/grub/x86_64-efi/"

echo "Make UEFI grub files"
grub-mkstandalone --format=x86_64-efi --output="$HOME/LIVE_BOOT/tmp/bootx64.efi" --locales="" --fonts="" "boot/grub/grub.cfg=$HOME/LIVE_BOOT/tmp/grub-standalone.cfg"

# UEFI引导文件的创建和挂载
cd "$HOME/LIVE_BOOT/staging/EFI/boot"
SIZE=$(expr $(stat --format=%s "$HOME/LIVE_BOOT/tmp/bootx64.efi") + 65536)
dd if=/dev/zero of=efiboot.img bs=$SIZE count=1
/sbin/mkfs.vfat efiboot.img
mmd -i efiboot.img efi efi/boot
mcopy -vi efiboot.img "$HOME/LIVE_BOOT/tmp/bootx64.efi" ::efi/boot/

# -------------- 最后：制作ISO ------------------
echo "Build ISO"
xorriso \
    -as mkisofs \
    -iso-level 3 \
    -o "$HOME/LIVE_BOOT/debian-custom.iso" \
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
    -append_partition 2 0xef "$HOME/LIVE_BOOT/staging/EFI/boot/efiboot.img" \
    "$HOME/LIVE_BOOT/staging"

echo "Copy output"
cp -v "$HOME/LIVE_BOOT/debian-custom.iso" /output/immortalwrt-installer-generic-ext4-combined-x86_64.iso
chmod -v 666 /output/immortalwrt-installer-generic-ext4-combined-x86_64.iso
ls -lah /output
