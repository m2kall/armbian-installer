#!/bin/bash

# 设置变量
WORKDIR="$HOME/LIVE_BOOT"
ISO_OUTPUT="$WORKDIR/debian-custom.iso"
EXT4_IMG="$WORKDIR/staging/live/filesystem.img"
MOUNT_PT="/mnt/ext4"

# 1. 安装必要工具
sudo apt-get update
sudo apt-get -y install debootstrap xorriso isolinux syslinux-efi grub-pc-bin grub-efi-amd64-bin mtools dosfstools parted grub-mkstandalone

# 2. 创建工作目录
mkdir -p "$WORKDIR"

# 3. 安装Debian到chroot
debootstrap --arch=amd64 --variant=minbase buster "$WORKDIR/chroot" http://ftp.us.debian.org/debian/

# 4. 复制支持文件
cp -v /supportFiles/installChroot.sh "$WORKDIR/chroot"
cp -v /supportFiles/immortalwrt/ddd "$WORKDIR/chroot/usr/bin/"
chmod +x "$WORKDIR/chroot/usr/bin/ddd"
cp -v /supportFiles/sources.list "$WORKDIR/chroot/etc/apt/sources.list"

# 5. 挂载必要的虚拟文件系统
sudo mount -t proc none "$WORKDIR/chroot/proc"
sudo mount --bind /dev "$WORKDIR/chroot/dev"
sudo mount --bind /sys "$WORKDIR/chroot/sys"

# 6. 运行安装脚本
sudo chroot "$WORKDIR/chroot" /installChroot.sh

# 7. 清理
rm -v "$WORKDIR/chroot/installChroot.sh"
mv -v "$WORKDIR/chroot"/packages.txt /output/packages.txt

# 8. 配置网络和autologin
cp -v /supportFiles/99-dhcp-en.network "$WORKDIR/chroot/etc/systemd/network/"
chown root:root "$WORKDIR/chroot/etc/systemd/network/99-dhcp-en.network"
chmod 644 "$WORKDIR/chroot/etc/systemd/network/99-dhcp-en.network"

mkdir -p "$WORKDIR/chroot/etc/systemd/system/getty@tty1.service.d/"
cp -v /supportFiles/override.conf "$WORKDIR/chroot/etc/systemd/system/getty@tty1.service.d/"

# 9. 卸载虚拟文件系统
sudo umount "$WORKDIR/chroot/proc"
sudo umount "$WORKDIR/chroot/dev"
sudo umount "$WORKDIR/chroot/sys"

# 10. 创建目录结构
mkdir -p "$WORKDIR"/{staging/{EFI/boot,boot/grub/x86_64-efi,isolinux,live},tmp}

# --------- 关键：创建ext4镜像并复制内容 ---------
echo "Creating ext4 filesystem image..."
# 调整大小，比如2G
dd if=/dev/zero of="$EXT4_IMG" bs=1G count=2
sudo mkfs.ext4 "$EXT4_IMG"

echo "Mounting ext4 image..."
sudo mkdir -p "$MOUNT_PT"
sudo mount -o loop "$EXT4_IMG" "$MOUNT_PT"

echo "Copying chroot content into ext4 image..."
sudo cp -a "$WORKDIR/chroot"/* "$MOUNT_PT"/

echo "Unmounting ext4 image..."
sudo umount "$MOUNT_PT"

# 11. 复制内核和initrd
cp -v "$WORKDIR/chroot"/boot/vmlinuz-* "$WORKDIR/staging/live/vmlinuz"
cp -v "$WORKDIR/chroot"/boot/initrd.img-* "$WORKDIR/staging/live/initrd"

# 12. 复制引导配置文件
cp -v /supportFiles/immortalwrt/isolinux.cfg "$WORKDIR/staging/isolinux/isolinux.cfg"
cp -v /supportFiles/immortalwrt/grub.cfg "$WORKDIR/staging/boot/grub/grub.cfg"
cp -v /supportFiles/grub-standalone.cfg "$WORKDIR/tmp/grub-standalone.cfg"
touch "$WORKDIR/staging/DEBIAN_CUSTOM"

# 13. 复制引导镜像
cp -v /usr/lib/ISOLINUX/isolinux.bin "$WORKDIR/staging/isolinux/"
cp -v /usr/lib/syslinux/modules/bios/* "$WORKDIR/staging/isolinux/"
cp -v -r /usr/lib/grub/x86_64-efi/* "$WORKDIR/staging/boot/grub/x86_64-efi/"

# 14. 生成UEFI启动文件
grub-mkstandalone --format=x86_64-efi --output="$WORKDIR/tmp/bootx64.efi" --locales="" --fonts="" "boot/grub/grub.cfg=$WORKDIR/tmp/grub-standalone.cfg"

# 15. 创建EFI引导镜像
cd "$WORKDIR/staging/EFI/boot"
SIZE=$(expr $(stat --format=%s "$WORKDIR/tmp/bootx64.efi") + 65536)
dd if=/dev/zero of=efiboot.img bs=$SIZE count=1
/sbin/mkfs.vfat efiboot.img
mmd -i efiboot.img efi efi/boot
mcopy -vi efiboot.img "$WORKDIR/tmp/bootx64.efi" ::efi/boot/

# --------- 重要：在ISO引导中挂载ext4镜像 ---------
# 你需要在ISO的initrd中加入挂载ext4的指令，示例（在initrd中加入）：
#   mount -o loop /path/to/filesystem.img /mnt
#   进行系统根目录切换或使用
#
# 这里在脚本中不做自动挂载，只提供镜像文件
# 在ISO的initrd中配置挂载脚本，确保系统启动后能挂载使用

# 16. 生成ISO镜像
echo "Building ISO..."
xorriso \
    -as mkisofs \
    -iso-level 3 \
    -o "$ISO_OUTPUT" \
    -full-iso9660-filenames \
    -volid "DEBIAN_CUSTOM" \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -eltorito-boot isolinux/isolinux.bin \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        --eltorito-catalog isolinux/isolinux.cat \
    -eltorito-alt-boot \
        -e /EFI/boot/efiboot.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
    -append_partition 2 0xef "$WORKDIR/staging/EFI/boot/efiboot.img" \
    "$WORKDIR/staging"

echo "Done. ISO located at: $ISO_OUTPUT"
ls -l "$ISO_OUTPUT"

echo Copy output
cp -v $HOME/LIVE_BOOT/debian-custom.iso /output/immortalwrt-installer-generic-ext4-combined-x86_64.iso
chmod -v 666 /output/immortalwrt-installer-generic-ext4-combined-x86_64.iso
ls -lah /output
