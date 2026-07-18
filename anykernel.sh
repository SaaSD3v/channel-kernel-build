# AnyKernel3 Ramdisk Mod Script
# osm0sis @ xda-developers

## AnyKernel setup
## shell variables
kernel.string=Channel Kernel for Moto G7 Play
do.devicecheck=0
block.string=/dev/block/bootdevice/by-name/boot
is_slot_device=0
ramdisk.compression=gzip
patch.vbmeta.flag=auto
patch.type=boot
patch.flash=auto

## AnyKernel install
split_boot;
flash_boot;

## AnyKernel end
