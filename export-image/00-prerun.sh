#!/bin/bash -e

IMG_FILE="${STAGE_WORK_DIR}/${IMG_FILENAME}${IMG_SUFFIX}.img"

if [ -f "$IMG_FILE" ]; then
    umount-pi-img "${IMG_FILE}" || true
fi

rm -f "${IMG_FILE}"

rm -rf "${ROOTFS_DIR}"
mkdir -p "${ROOTFS_DIR}"

BOOT_SIZE="$((256 * 1024 * 1024))"
ROOT_SIZE=$(du --apparent-size -s "${EXPORT_ROOTFS_DIR}" --exclude var/cache/apt/archives --exclude boot --block-size=1 | cut -f 1)

# All partition sizes and starts will be aligned to this size
ALIGN="$((4 * 1024 * 1024))"
# Add this much space to the calculated file size. This allows for
# some overhead (since actual space usage is usually rounded up to the
# filesystem block size) and gives some free space on the resulting
# image.
ROOT_MARGIN=$((800*1024*1024))

BOOT_PART_START=$((ALIGN))
BOOT_PART_SIZE=$(((BOOT_SIZE + ALIGN - 1) / ALIGN * ALIGN))
ROOT_PART_START=$((BOOT_PART_START + BOOT_PART_SIZE))
ROOT_PART_SIZE=$(((ROOT_SIZE + ROOT_MARGIN + ALIGN  - 1) / ALIGN * ALIGN))
IMG_SIZE=$((BOOT_PART_START + BOOT_PART_SIZE + ROOT_PART_SIZE))

[[ "$(df "${IMG_FILE}" --output=fstype | tail -1)" == "btrfs" ]] && chattr +C "${IMG_FILE}"
truncate -s "${IMG_SIZE}" "${IMG_FILE}"

parted --script "${IMG_FILE}" mklabel msdos
parted --script "${IMG_FILE}" unit B mkpart primary fat32 "${BOOT_PART_START}" "$((BOOT_PART_START + BOOT_PART_SIZE - 1))"
parted --script "${IMG_FILE}" unit B mkpart primary ext4 "${ROOT_PART_START}" "$((ROOT_PART_START + ROOT_PART_SIZE - 1))"

LOOP_DEV=$(losetup --show -Pf "${IMG_FILE}")
BOOT_DEV=${LOOP_DEV}p1
ROOT_DEV=${LOOP_DEV}p2

ROOT_FEATURES="^huge_file"
for FEATURE in metadata_csum 64bit; do
	if grep -q "$FEATURE" /etc/mke2fs.conf; then
	    ROOT_FEATURES="^$FEATURE,$ROOT_FEATURES"
	fi
done
mkdosfs -n boot -F 32 -v "$BOOT_DEV" > /dev/null
mkfs.ext4 -L rootfs -O "$ROOT_FEATURES" "$ROOT_DEV" > /dev/null

mount -v "$ROOT_DEV" "${ROOTFS_DIR}" -t ext4
mkdir -p "${ROOTFS_DIR}/boot"
mount -v "$BOOT_DEV" "${ROOTFS_DIR}/boot" -t vfat

rsync -aHAXx --exclude /var/cache/apt/archives --exclude /boot "${EXPORT_ROOTFS_DIR}/" "${ROOTFS_DIR}/"
rsync -rtx "${EXPORT_ROOTFS_DIR}/boot/" "${ROOTFS_DIR}/boot/"