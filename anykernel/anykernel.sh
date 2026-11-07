### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=306kernels GKI (laguna) with KernelSU-Next + susfs + Droidspaces
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
do.check_boot_version=0
device.name1=frankel
device.name2=blazer
device.name3=mustang
device.name4=rango
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
keycheck.timeout=10
'; } # end properties


### AnyKernel install
## boot shell variables
block=boot
is_slot_device=auto
ramdisk_compression=auto
patch_vbmeta_flag=auto
no_magisk_check=1

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh

# boot install
split_boot

if [ -f "$SPLITIMG/ramdisk.cpio" ]; then
    unpack_ramdisk
    write_boot
else
    flash_boot
fi

ui_print " "

## 306kernels epilogue
# update-binary's ui_printfile is not inherited by this shell
printfile() {
  local line pad;
  (ps; ps -A) 2>/dev/null | grep -q '[z]ygote' || [ -e /twres ] || pad='| ';
  while IFS='' read -r line || [ -n "$line" ]; do ui_print "$pad$line"; done < "$1";
}
ui_print " ";
ui_print "Support me on Ko-Fi!  ko-fi.com/306bobby";
ui_print " ";
printfile "$AKHOME/kofi-qr.txt";
ui_print " ";
