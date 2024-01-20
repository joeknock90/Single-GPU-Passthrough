#!/bin/bash
 mkdir -p /etc/libvirt/hooks/qemu.d/win11/{prepare/begin,release/end}

 cp qemu /etc/libvirt/hooks/
 chmod +x /etc/libvirt/hooks/qemu

 cp start.sh /etc/libvirt/hooks/qemu.d/win11/prepare/begin/
 cp revert.sh /etc/libvirt/hooks/qemu.d/win11/release/end/

 systemctl restart libvirtd
