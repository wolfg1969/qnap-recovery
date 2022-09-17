Overview
========

This data recovery method uses a host machine running Linux to assemble the
md raid and a guest VM running the QNAP firmware to access the LVM volumes.

A running QNAP device is not necessary.

## Recover QNAP harddisk data  by qemu virtualization in a Linux PC.

It is very troublesome to restore data after the QNAP NAS hardware is broken. The officially recommended method is to buy a new one with the same model, which is too expensive (~~QNAP will no longer be my choice.~~). QNAP uses the software Raid scheme and makes some modifications to LVM. On ordinary PCs, the LVM volume of QNAP cannot be mounted normally in Linux (we are fortunately enough, the Raid has not been changed by QNAP).  I modified the mkke's scheme to fit for the situation that the hard disks are not encrypted. Moreover,  the scheme boots the system with the full firmware, while the mkke's scheme uses the partially updated firmware (I use the full firmware just due to fact that the officially provided firmware already contains the full system). Only the firmware of TX-651 is tested, and my Raid5 scheme uses 4 hard disks without disk encryption.  Data recovery of other models and configurations may be different to mine.

**Tips:** 

1. It is recommended backing up the hard disk data before recovery.
2. If the hard disk interface is not enough, it will need a PCI SATA expansion card.

## 利用qemu虚拟化，在Linux PC中恢复QNAP Raid数据。

QNAP NAS硬件坏了之后要恢复数据是个很麻烦的事，官方的推荐方法是重新买一个同型号的硬件，这个成本太高(~~不会再考虑QNAP~~)。QNAP使用软件Raid方案，并对LVM做了一些修改，在普通PC上，无法用Linux正常挂载QNAP的LVM卷（还好没有改Raid）。在github上找到的这个方案使用qemu和QNAP固件虚拟QNAP软件系统，从而恢复数据。这里对原方案进行补充修改，与原方案不同之处是不考虑硬盘加密。另外，使用完整固件启动系统，而不是部分更新的固件（主要是官方找到的固件已包含完整系统）。此处仅测试了TX-651的固件，恢复4个硬盘构成的Raid5，未使用磁盘加密，其他型号和配置的数据恢复需自行参考解决。

**建议**

1. 建议在恢复之前先做好硬盘数据备份。
2. 如果硬盘接口不够，买一个PCI的SATA扩展卡




Preparing the disk array
========================

* 将QNAP Raid硬盘接到Linux PC
* the disk array should be visible on the device-mapper level, either
  automatically after boot, or after mdadm -A -R --scan
* test the md block device is accessible.
  We are only interested in the data device, which should be `/dev/md1`.

  ``` bash
  mdadm --detail /dev/md1
  mdadm /dev/md1
  ```

Preparing a VM with an up-to-date firmware
==========================================

* Download FW  from qnap.com (e.g. `TS-X51_20211223-4.5.4.1892.zip`)
  and unzip
  
  ```
  unzip TS-X51_20211223-4.5.4.1892.zip
  ```
  
* decrypt the firmware

  after clone the repo, do

  ``` bash
  make TS-X51_20211223-4.5.4.1892.tgz
  ```

* extract firmware and patch initrd

  ``` bash
  mkdir firmware
  tar xzf TS-X51_20211223-4.5.4.1892.tgz -C firmware
  cd firmware
  unlzma <../initrd.boot >initrd.cpio
  mkdir initrd
  cd initrd
  cpio -i <../initrd.cpio
  patch -p1 <../../init_check.sh.diff
  find . | cpio --quiet -H newc -o | lzma -9 >../initrd.lzma
  cd ..
  ```

* build disk image from rootfs2.bz

  ```
  dd if=/dev/zero of=usr.img bs=1k count=200k
  mke2fs -F usr.img
  mkdir rootfs2
  cd rootfs2
  tar --xz -xpf ../rootfs2.bz
  mount ../usr.img home
  cp -a usr/* home/
  umount home
  ```

* start the VM

  /dev/sdg1 is used to save the recovered data.

  多添加一块硬盘/dev/sdg1 ，用于保存恢复的数据

  ```
  qemu-system-x86_64 -s -kernel bzImage -nographic -initrd initrd.lzma -snapshot -hda /dev/md1 -hdb usr.img -hdc /dev/sdg1 -m 4G --enable-kvm
  ```

* login with admin / admin

* mount the device

  ``` bash
  # link to /dev/md1, so that pvscan recognizes it
  ln /dev/sda /dev/md1
  mkdir /usr
  mount /dev/sdb /usr
  pvscan --cache /dev/md1
  
  # pvs should now show the volume group, and lvs the volumes
  pvs
  lvs
  
  # activate the thin pool and the volume
  lvchange -a y vg1/lv2
  
  # mount the device
  # because we are read-only, a dirty ext4 can only be mounted with '-o ro,noload'
  # for a complete journal replay, switch to read-write mode, or to be safe
  # copy the raw block device to the host and replay it on the copy
  mount -t ext4 /dev/mapper/vg1-lv2 /mnt/ext/
  
  mkdir /mnt/recovered
  mount /dev/sdc /mnt/recovered
  cp -a /mnt/ext/* /mnt/recovered
  ```



