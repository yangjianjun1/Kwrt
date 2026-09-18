#!/bin/bash
set -e

#=================================================
# 玩客云 OpenWrt 固件 -> 标准 Amlogic 线刷包 转换脚本
# 输出：.burn.img（USB Burning Tool 可直接线刷）
#=================================================

echo "===== 开始打包标准 Amlogic 线刷包 ====="

# 关键：确保在仓库根目录工作
cd $GITHUB_WORKSPACE

# 1. 安装依赖工具（加 -y 自动确认）
echo "[1/7] 安装依赖工具..."
sudo apt update
sudo apt install -y android-sdk-libsparse-utils xz-utils

# 2. 下载 AmlImg 打包工具
echo "[2/7] 下载 AmlImg 工具..."
ver="v0.3.2"
curl -L -o ./AmlImg https://github.com/rmoyulong/AmlImg/releases/download/$ver/AmlImg_${ver}_linux_amd64
chmod +x ./AmlImg

# 3. 下载玩客云专用 uboot（eMMC 线刷底包模板）
echo "[3/7] 下载玩客云 uboot 模板..."
curl -L -o ./uboot.img https://github.com/rmoyulong/u-boot-onecloud/releases/download/Onecloud_Uboot_23.12.24_18.15.09/eMMC.burn.img

# 4. 解压 uboot 模板，得到 burn/ 目录
echo "[4/7] 解压 uboot 模板..."
./AmlImg unpack ./uboot.img burn/

# 5. 解压 OpenWrt 固件并提取分区
echo "[5/7] 提取 OpenWrt 固件分区..."
gunzip openwrt/bin/targets/*/*/*.gz

diskimg=$(ls openwrt/bin/targets/*/*/*.img)
echo "OpenWrt 镜像: $diskimg"
loop=$(sudo losetup --find --show --partscan $diskimg)
echo "循环设备: $loop"

# 准备 rootfs 镜像
img_ext="openwrt.img"
img_mnt="xd"
rootfs_mnt="img"

sudo rm -rf ${img_ext} ${img_mnt} ${rootfs_mnt}
sudo dd if=/dev/zero of=${img_ext} bs=1M count=2000
# 加 -F 强制格式化，避免交互提示
sudo mkfs.ext4 -F ${img_ext}
sudo mkdir -p ${img_mnt} ${rootfs_mnt}
sudo mount ${img_ext} ${img_mnt}
sudo mount ${loop}p2 ${rootfs_mnt}

# 复制 rootfs 内容（关键：用 cp -a 且用 . 而不是 *，确保隐藏文件也复制）
cd ${rootfs_mnt}
sudo cp -a . ../${img_mnt}/
cd ..
sudo sync
sudo umount ${img_mnt}
sudo umount ${rootfs_mnt}

# 6. 转换为 sparse 格式并打包
echo "[6/7] 转换 sparse 格式并打包..."
sudo img2simg ${loop}p1 burn/boot.simg
sudo img2simg openwrt.img burn/rootfs.simg

# 只删除我们创建的 openwrt.img，不要用通配符
sudo rm -f openwrt.img
sudo losetup -d $loop

# 添加分区配置
cat <<EOF >> burn/commands.txt
PARTITION:boot:sparse:boot.simg
PARTITION:rootfs:sparse:rootfs.simg
EOF

# 打包成标准线刷包
prefix=$(ls openwrt/bin/targets/*/*/*.img | sed 's/\.img$//')
burnimg=${prefix}.burn.img
echo "输出线刷包: $burnimg"
./AmlImg pack $burnimg burn/

# 7. 压缩并生成校验
echo "[7/7] 压缩并生成校验文件..."
cd openwrt/bin/targets/*/*/
for f in *.burn.img; do
  sha256sum "$f" > "${f}.sha"
  xz -9 --threads=0 --compress "$f"
done

# 删除原始 raw 镜像
sudo rm -f *.img
sudo rm -f *.gz

echo "===== 线刷包打包完成 ====="
ls -lh
echo "=========================="
