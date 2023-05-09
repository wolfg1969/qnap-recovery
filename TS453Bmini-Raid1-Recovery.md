TS453Bmini, 因 UPS(APC BK650) 短路故障（原因仍未知）导致主板损坏，咨询售后得知返修费用 1200 多块钱，或者购买同架构兼容设备可以恢复数据。

4 块磁盘，1 和 2 做了 Raid 1，系统里显示为原有卷。3 和 4 均为独立的静态卷。

幸运的是绝大部分数据都有备份。

决定使用 Linux 系统恢复数据。

硬件：J1900 CPU, 4 GB memory, 2 SATA ports, 1 USB3 port, 80 GB Hard Disk

系统：Debian GNU/Linux 11 (bullseye), Xfce

将 NAS 的磁盘取下（标记好插槽位置）接入 PC 的 SATA 接口检查。

磁盘 3 和 4 是静态卷，可以很容易的加载到系统中从而恢复出数据。参考：
* https://post.smzdm.com/p/301806
* https://forum.qnap.com/viewtopic.php?t=156819

磁盘 1 和 2 做了 RAID 1，按照上述方法无法加载，错误信息如下：
```
WARNING: Unrecognised segment type tier-thin-pool
WARNING: Unrecognised segment type thick
```

QNAP 使用了自己的 segment type，很无语。

幸好在 Github 找到了此方法，能够使用 QEMU 虚拟机来访问磁盘数据。

步骤：

将 Raid 1 中的任意一块磁盘接入 PC，开机。

```bash
$ sudo lsblk
$ cat /proc/mdstat
$ sudo mdadm -A -R /dev/md126 /dev/sdb3
mdadm: /dev/sdb3 is busy - skipping
$ sudo mdadm --stop /dev/md126
mdadm: stopped /dev/md126
$ sudo mdadm -A -R /dev/md126 /dev/sdb3
mdadm: /dev/md126 has been started with 1 drive (out of 2).
$ sudo mdadm --detail /dev/md126
$ sudo mdadm /dev/md126
/dev/md126: 1853.52GiB raid1 2 devices, 0 spares. Use mdadm --detail for more detail.
```

下载 QTS 固件后解压至项目目录（以下命令均以 root 用户运行）
```bash
unzip TS-X53B_20230416-4.5.4.2374.zip
```

处理固件文件
```bash
make TS-X53B_20230416-4.5.4.2374.tgz
```

给 initrd 打补丁
```bash
mkdir firmware
tar xzf TS-X53B_20230416-4.5.4.2374.tgz -C firmware
cd firmware
unlzma <./initrd.boot >initrd.cpio
mkdir initrd
cd initrd
cpio -i <../initrd.cpio
patch -p1 <../../init_check.sh.diff
find . | cpio --quiet -H newc -o | lzma -9 >../initrd.lzma
cd ..
```

构建新映像文件
```bash
dd if=/dev/zero of=usr.img bs=1k count=200k
mke2fs -F usr.img
mkdir rootfs2
cd rootfs2
tar --xz -xpf ../rootfs2.bz
mount ../usr.img home
cp -a usr/* home/
umount home
```

启动虚拟机，指定 Raid 1 磁盘为 hda，定制的 image 为 hdb，用于备份数据的移动硬盘（NTFS 格式）插在 USB 3 接口
```bash
lsusb
qemu-system-x86_64 -s -kernel bzImage -nographic -initrd initrd.lzma -snapshot \
  -hda /dev/md126 -hdb usr.img -m 2G --enable-kvm \
  -device qemu-xhci,id=xhci -device usb-host,hostdevice=/dev/bus/usb/002/002
```

以 admin:admin 登录虚拟机，执行命令加载各个磁盘，备份数据，忽略各种错误和警告信息。
```
Welcome to use the QNAP's products.

(none) login: admin
Password:
# ln /dev/sda /dev/md126
# mkdir /usr
# mount /dev/sdb /usr
# pvs
# lvs
# lvchange -a y vg1/tp1
# mount -t ext4 /dev/mapper/vg1-tp1 /mnt/ext
# mkdir /mnt/recorvered
# mount -t ufsd /dev/sdc1 /mnt/recovered
# cd /mnt/recovered/Backup
# cp -a /mnt/ext/* .

```
