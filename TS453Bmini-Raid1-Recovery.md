TS453Bmini, 因 UPS(APC BK650) 短路故障（原因~~仍未知~~见后记）导致主板损坏。咨询售后得知返修费用要 1200 多，或者购买同架构兼容设备可以恢复数据。不能接受，决定使用 Linux 系统恢复数据。

4 块磁盘，1 和 2 做了 Raid 1，系统里显示为原有卷（从 TS212P 升级而来）。3 和 4 均为独立的静态卷。

万幸的是绝大部分数据都有备份。

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

在 Github 找到了此方法，能够使用 QEMU 虚拟机来访问磁盘数据。

### 数据恢复步骤

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
### 后记

#### 故障直接原因

UPS 插座里的铜片被插头顶起，接触下面的电路板导致短路。UPS 插座与电路板之间无绝缘保护，NAS 也没有保护电路，两个缺陷造就了此次故障。

#### 磁盘 3 再次恢复的过程

磁盘 3 为静态卷，可以直接加载 LVS 分区，无需用 QEMU 的方式。但我也尝试了在 QEMU 环境里挂载，也正常。但再次放到 Debian 或者 OpenMediaVault 系统里时就没法访问了。md 设备有，但 pvs 和 lvs 命令都找不到卷信息。

```
# lsblk -f
NAME      FSTYPE            FSVER LABEL UUID                                 FSAVAIL FSUSE% MOUNTPOINT
sda                                                                                         
├─sda1    ext3              1.0         3a38abf8-154c-41f7-87ef-92773b98ec42                
├─sda2    linux_raid_member 1.0   256   e05970e7-fd0b-beb2-2a8b-d20f1f1a1001                
├─sda3    linux_raid_member 1.0   1     39074726-5200-9032-90ad-c2b681cca650                
│ └─md126 drbd              v08         11360af089a46a67                                    
├─sda4    ext3              1.0         83e60698-cf17-48e0-bc44-6eb3afea6f27                
└─sda5    linux_raid_member 1.0   322   7fce68e9-874f-caac-76f5-57ef863b0e4a
```

文件系统似乎变成了 ```drbd```，难道是在 QEMU 里挂载过的问题？

在 sda1 分区找到了 lvm 配置的备份，尝试恢复物理和逻辑卷

```
# pvcreate --test --uuid "LT5Amu-f11g-LUph-A858-KPat-dXV7-IHWppj" --restorefile /etc/lvm/backup/vg288 /dev/sda
  TEST MODE: Metadata will NOT be updated and volumes will not be (de)activated.
  WARNING: Couldn't find device with uuid LT5Amu-f11g-LUph-A858-KPat-dXV7-IHWppj.
  Cannot use /dev/sda: device is partitioned
 ```

报错已有分区，尝试清空分区信息

```
# wipefs --all --backup /dev/sda
wipefs: 错误：/dev/sda：探测初始化失败: 设备或资源忙
```

强制清空成功

```
# wipefs -f --all --backup /dev/sda
/dev/sda：8 个字节已擦除，位置偏移为 0x00000200 (gpt)：45 46 49 20 50 41 52 54
/dev/sda：8 个字节已擦除，位置偏移为 0x3a3817d5e00 (gpt)：45 46 49 20 50 41 52 54
/dev/sda：2 个字节已擦除，位置偏移为 0x000001fe (PMBR)：55 aa
# lsblk
NAME   MAJ:MIN RM   SIZE RO TYPE MOUNTPOINT
sda      8:0    0   3.6T  0 disk 
├─sda1   8:1    0 517.7M  0 part 
├─sda2   8:2    0 517.7M  0 part 
├─sda3   8:3    0   3.6T  0 part 
├─sda4   8:4    0 517.7M  0 part 
└─sda5   8:5    0     8G  0 part
```

恢复物理卷

```
# pvcreate --test --uuid "LT5Amu-f11g-LUph-A858-KPat-dXV7-IHWppj" --restorefile /etc/lvm/backup/vg288 /dev/sda
  TEST MODE: Metadata will NOT be updated and volumes will not be (de)activated.
  WARNING: Couldn't find device with uuid LT5Amu-f11g-LUph-A858-KPat-dXV7-IHWppj.
  Can't open /dev/sda exclusively.  Mounted filesystem?
  Can't open /dev/sda exclusively.  Mounted filesystem?
# pvcreate --test --uuid "LT5Amu-f11g-LUph-A858-KPat-dXV7-IHWppj" --restorefile /etc/lvm/backup/vg288 /dev/sda3
  TEST MODE: Metadata will NOT be updated and volumes will not be (de)activated.
  WARNING: Couldn't find device with uuid LT5Amu-f11g-LUph-A858-KPat-dXV7-IHWppj.
  Cannot use /dev/sda3: device is an md component
```
 
设备不对，要使用 md 设备（前面不该做 wipefs）
 
```
# pvcreate --test --uuid "LT5Amu-f11g-LUph-A858-KPat-dXV7-IHWppj" --restorefile /etc/lvm/backup/vg288 /dev/md126
# pvcreate  --uuid "LT5Amu-f11g-LUph-A858-KPat-dXV7-IHWppj" --restorefile /etc/lvm/backup/vg288 /dev/md126
 WARNING: Couldn't find device with uuid LT5Amu-f11g-LUph-A858-KPat-dXV7-IHWppj.
 WARNING: drbd signature detected on /dev/md126 at offset 3990593138748. Wipe it? [y/n]: y
  Wiping drbd signature on /dev/md126.
  Physical volume "/dev/md126" successfully created.
 ```
 
 物理卷创建成功了，drbd 签名也被清除了。
 
 恢复逻辑卷
 
 ```
 # vgcfgrestore -f /etc/lvm/archive/vg288_00000-1449380504.vg vg288
  Restored volume group vg288.
 ```
 
 激活卷
 
 ```
 # vgdisplay
 --- Volume group ---
  VG Name               vg288
  System ID             
  Format                lvm2
  Metadata Areas        1
  Metadata Sequence No  89
  VG Access             read/write
  VG Status             resizable
  MAX LV                0
  Cur LV                2
  Open LV               0
  Max PV                0
  Cur PV                1
  Act PV                1
  VG Size               <3.63 TiB
  PE Size               4.00 MiB
  Total PE              951431
  Alloc PE / Size       951431 / <3.63 TiB
  Free  PE / Size       0 / 0   
  VG UUID               05XzDC-l8cX-vUvc-gyR1-WiiA-xz6o-BU5mAi

# vgchange -ay vg288
 2 logical volume(s) in volume group "vg288" now active
```

换了机器后还是认不出分区，这是由于前面做了 wipefs 的原因，需要恢复分区信息

```
# lsblk
NAME   MAJ:MIN RM   SIZE RO TYPE MOUNTPOINT
sda      8:0    0   500G  0 disk 
├─sda1   8:1    0 220.6G  0 part /
├─sda2   8:2    0   954M  0 part /boot
├─sda3   8:3    0   8.4G  0 part [SWAP]
└─sda4   8:4    0 270.1G  0 part /home
sdb      8:16   0   3.6T  0 disk 
sr0     11:0    1  50.6M  0 rom 
```

可以看到 sdb 没有分区了，从 wipefs 的备份文件恢复：

```
# dd if=wipefs-sda-0x000001fe.bak of=/dev/sdb seek=$((0x000001fe)) bs=1
2+0 records in
2+0 records out
2 bytes copied, 0.0439901 s, 0.0 kB/s
# dd if=wipefs-sda-0x00000200.bak of=/dev/sdb seek=$((0x00000200)) bs=1
8+0 records in
8+0 records out
8 bytes copied, 0.111218 s, 0.1 kB/s
# dd if=wipefs-sda-0x3a3817d5e00.bak of=/dev/sdb seek=$((0x3a3817d5e00)) bs=1
8+0 records in
8+0 records out
8 bytes copied, 0.0391388 s, 0.2 kB/s
```

```
# lsblk
NAME              MAJ:MIN RM   SIZE RO TYPE  MOUNTPOINT
sda                 8:0    0   500G  0 disk  
├─sda1              8:1    0 220.6G  0 part  /
├─sda2              8:2    0   954M  0 part  /boot
├─sda3              8:3    0   8.4G  0 part  [SWAP]
└─sda4              8:4    0 270.1G  0 part  /home
sdb                 8:16   0   3.6T  0 disk  
├─sdb1              8:17   0 517.7M  0 part  
├─sdb2              8:18   0 517.7M  0 part  
├─sdb3              8:19   0   3.6T  0 part  
│ └─md1             9:1    0   3.6T  0 raid1 
│   ├─vg288-lv544 253:0    0  37.3G  0 lvm   
│   └─vg288-lv1   253:1    0   3.6T  0 lvm   
├─sdb4              8:20   0 517.7M  0 part  
└─sdb5              8:21   0     8G  0 part  
sr0                11:0    1  50.6M  0 rom

# pvdisplay
  --- Physical volume ---
  PV Name               /dev/md1
  VG Name               vg288
  PV Size               <3.63 TiB / not usable 1.15 MiB
  Allocatable           yes (but full)
  PE Size               4.00 MiB
  Total PE              951431
  Free PE               0
  Allocated PE          951431
  PV UUID               LT5Amu-f11g-LUph-A858-KPat-dXV7-IHWppj
   
root@osboxes:/shared# lvdisplay
  --- Logical volume ---
  LV Path                /dev/vg288/lv544
  LV Name                lv544
  VG Name                vg288
  LV UUID                A3ybpC-fgyH-He4O-yH4e-uPVN-xJmX-1EnbUG
  LV Write Access        read/write
  LV Creation host, time TS453Bmini, 2023-02-14 23:28:31 +0800
  LV Status              available
  # open                 0
  LV Size                <37.28 GiB
  Current LE             9543
  Segments               2
  Allocation             inherit
  Read ahead sectors     65536
  Block device           253:0
   
  --- Logical volume ---
  LV Path                /dev/vg288/lv1
  LV Name                lv1
  VG Name                vg288
  LV UUID                YfHVbB-F2q9-0peL-xpyq-2k2A-RWnd-P0Ppgy
  LV Write Access        read/write
  LV Creation host, time TS453Bmini, 2023-02-14 23:28:47 +0800
  LV Status              available
  # open                 0
  LV Size                3.59 TiB
  Current LE             941888
  Segments               1
  Allocation             inherit
  Read ahead sectors     65536
  Block device           253:1
```

恢复成功。放到 Open Media Vault 里也能够被系统正确识别和挂载 LVM 卷。

* [@mkke/qnap-recovery](https://github.com/mkke/qnap-recovery)
* [@lxzheng/qnap-recovery](https://github.com/lxzheng/qnap-recovery)
* [@andresiraola/qnap-recovery](https://github.com/andresiraola/qnap-recovery)

### 再次在 Windows 下尝试访问 RAID 1 磁盘

```
qemu-system-x86_64.exe -s -kernel bzImage -nographic -initrd initrd.lzma -snapshot  -hda \\.\PhysicalDrive2 -hdb usr.img -m 2G --enable-kvm
```

PhysicalDrive2 就是通过 usb 转 sata 转接线连接的 NAS 硬盘。

```
[   45.000655] drbd: initialized. Version: 8.4.10 (api:1/proto:86-101)
[   45.002576] drbd: srcversion: 1279A587E9CD8708A3DB014
[   45.004411] drbd: registered as block device major 147


[   64.933476] mpath_util[1908]: segfault at 7ffc1fe53ff8 ip 00007fd5d0779d8b sp 00007ffc1fe54000 error 6 in ld-2.21.so[7fd5d076b000+22000]
/sbin/daemon_mgr: error while loading shared libraries: libuLinux_config.so.0: cannot open shared object file: No such file or directory
```

启动信息有看到 drbd 服务启动的信息。最后会有一个报错信息，多等一会儿就看到登录提示了。

```
(none) login:
Password:
login[1967]: root login on 'ttyS0'
-sh: id: command not found
-sh: reset: command not found
[~] # mkdir /usr
[~] # mount /dev/sdb /usr
[~] # logout
```

再次登入，启动 lvmetad 服务

```
Welcome to use the QNAP's products.

(none) login: admin
Password:
login[1977]: root login on 'ttyS0'
[  263.218476] NOHZ: local_softirq_pending 10
[  263.221946] NOHZ: local_softirq_pending 212
[  263.223314] NOHZ: local_softirq_pending 212
[~] # /sbin/daemon_mgr lvmetad start "/sbin/lvmetad"
```

挂载硬盘，查看信息，关机

```
[~] # mdadm --examine --scan > /etc/mdadm.conf
[~] # mdadm --assemble --scan
[  435.567824] md: md9 stopped.
[  435.608479] md/raid1:md9: active with 1 out of 4 mirrors
[  435.625521] md9: detected capacity change from 0 to 542769152
mdadm: /dev/md9 has been started with 1 drive (out of 4).
[  435.724549] md: md256 stopped.
[  435.753420] md/raid1:md256: active with 1 out of 2 mirrors
[  435.761496] md256: detected capacity change from 0 to 542834688
mdadm: /dev/md/256 has been started with 1 drive (out of 2).
[  440.484931] md: md3 stopped.
[  440.514006] md/raid1:md3: active with 1 out of 2 mirrors
[  440.518431] md3: detected capacity change from 0 to 1990205046784
mdadm: /dev/md/3 has been started with 1 drive (out of 2).
[  445.307489] md: md13 stopped.
[  445.334744] md/raid1:md13: active with 1 out of 4 mirrors
[  445.354348] md13: detected capacity change from 0 to 469893120
mdadm: /dev/md13 has been started with 1 drive (out of 4).
[  445.461565] md: md322 stopped.
[  445.491436] md/raid1:md322: active with 1 out of 2 mirrors
[  445.501222] md322: detected capacity change from 0 to 7408779264
mdadm: /dev/md/322 has been started with 1 drive (out of 2).
[~] # pvscan --cache /dev/md3
[~] # pvs
  PV         VG   Fmt  Attr PSize PFree
  /dev/md3   vg1  lvm2 a--  1.81t    0
[~] # lvs
  LV    VG   Attr       LSize  Pool Origin Data%  Meta%  Move Log Cpy%Sync Convert
  lv3   vg1  Vwi---t---  1.20t tp1
  lv546 vg1  -wi------- 18.54g
  tp1   vg1  twi---t---  1.73t
[~] # lvchange -a y vg1/tp1
[  624.691495] device-mapper: thin metadata: __create_persistent_data_objects: block manger get correctly
[  624.938353] device-mapper: tier: passdown_tier_discard:4011, tier discard_passdown(4)
[  624.943398] device-mapper: thin metadata: dm_pool_set_mapped_threshold: threshold: 0 total_mapped_blocks: 2516480 new_threshold: 3623776
[  624.949234] device-mapper: thin: maybe_resize_data_dev: expand pool origin max threshold to 3623776
[~] # mount -t ext4 /dev/mapper/vg1-tp1 /mnt/ext
[  654.455095] ext4_init_reserve_inode_table0: dm-6, 9830
[  654.458816] ext4_init_reserve_inode_table2: dm-6, 9830, 0, 0, 4096
[  654.469257] EXT4-fs (dm-6): mounted filesystem with ordered data mode. Opts: (null)
[~] # umount /mnt/ext
[~] # halt
[~] # [  880.271204] md13: detected capacity change from 469893120 to 0
[  880.274521] md: md13 stopped.
The system is going down NOW!
Sent SIGTERM to all processes
Sent SIGKILL to all processes
Requesting system halt
[  883.529520] flashcache flashcache_notify_reboot
[  883.533401] sd 0:0:1:0: [sdb] Synchronizing SCSI cache
[  883.535787] sd 0:0:1:0: [sdb] Stopping disk
[  883.537424] sd 0:0:0:0: [sda] Synchronizing SCSI cache
[  883.539493] sd 0:0:0:0: [sda] Stopping disk
[  883.543050] reboot: System halted
```
