
## If you go to reddit for help yell at u/lellow_yedbetter

## See also: https://gitlab.com/YuriAlek/vfio
### A slightly different, more complete guide with different script implementations. I will continue to update this guide for myself and others who are interested in a more Libvirt approach. 


# Single GPU Passthrough on Linux  

#### Tested on Fedora 28 and Arch Linux
#### Currently working on 10 Series (Pascal) Nvidia GPUs
#### Now working with 5 through 10 Seires cards with manual hex editing
#### Pull Requests and Issues are welcome

## Special Thanks to:

### The Passthrough post (https://passthroughpo.st)
For hosting news and information about VFIO passthrough, and for the libvirt/qemu hook helper in this guide.

### andre-ritcher
For providing the vfio-pci-bind tool. A tool that is no longer used in this guide, but was previously used and he still deserves thanks.

### Matoking
For the Nvidia ROM patcher. Making passing the boot gpu to the VM without GPU bios problems.

### Sporif
For diagnosing, developing, and testing methods to successfully rebind the EFI-Framebuffer when passing the video card back to the host OS.

### droidman
For instructions on manually editing the vBIOS hex for use with VFIO passthrough

### Yuri Alek (https://gitlab.com/YuriAlek/vfio)
A guide that is no doubt better than mine. Learning a few things from his implementation that can help me out a bit. This guide depends on libvirt at the base where as his has implementations that do not. 

#### So many other people and organizations I need to thank. If feel your name should be here, please contact me. Credit where credit is due is very important to me, and to making the Linux community a better place.

## Contents

1. [Disclaimer](##disclaimer) 
2. [Background](##background)
	* [Advantages](###advantages)
	* [Disadvantages](###disadvantages)
3. [Prerequisites](##prerequisites) and [Assumptions](###assumptions)
4. [Procedure](##procedure)

# Disclaimer
I have no qualifications as a Linux admin/user/professional/intelligent person. I am a windows systems administrator. GNU/Linux is a hobby and passion. I have very little programming experience and I am very bad at all types of scripting. I have hacked together a lot of work that other people have done and put it in one place.

# Background
Historically, VFIO passthrough has been built on a very specific model. I.E.

* 2 GPUs, 1 for the host, and one for the VM
* 2 monitors *OR* a monitor with 2 inputs
	* or a KVM switch

I personally, as well as some of you out there, might not have those things available. Maybe You've got a Mini-ITX build with no iGPU. Or maybe you're poor like me, and can't shell out for new computer components without some financial  planning before hand.

Whatever your reason is. VFIO is still possible. But with caveats. Here's some advantages and disadvantages of this model.

This setup model is a lot like dual booting, without actually rebooting.

# Advantages
* As already stated, this model only requires one GPU
* The ability to switch back and forth between different OSes with FULL use of a discrete graphics processor (Linux on Host with full GPU, Windows 10 Guest with Full GPU, MacOS guest with full GPU)
* Bragging rights
* Could be faster than dual booting (this depends on your system)
* Using virtual disk images (like qcow) gives you management of snapshots, making breaking your guest os easy to recover from.

# Disadvantages
* Can only use one OS at a time.
	- Once the VM is running, it's basically like running that as your main OS. You  will be logged out of your user on the host, but will be unable to manage the host locally at all. You can still use ssh/vnc/xrdp to manage the host.
* There are still some quirks (I need your help to iron these out!)
* Using virtual disk images could be a performance hit
	- You can still use raw partitions/lvm/pass through raw disks, but loose the more robust snapshot and management features
* If you DO have a second video card, solutions like looking-glass are WAYYY more convenient and need active testing and development.
* All VMs must be run as root. There are security considerations to be made there. This model requires a level of risk acceptance.

For my personal use case. This model is worth it to me and it might be for you too!

# Prerequisites and Assumptions

# Assumptions
This guide is going to assume a few things

1. You have a system capable of VFIO passthrough. I.E. a processors that supports IOMMU, sane IOMMU groups, and etc.
2. Unfortunately for the time being, a 10 Series Nvidia GPU. the VFIO ROM patcher we will be using only works with these specifically.
3. I am going to start in a place where you have a working libvirt config, or qemu script, that boots a guest OS without PCI devices passed through.

I am not going to cover the basic setup of VFIO passthrough here. There are a lot of guides out there that cover the process from beginning to end.

What I will say is that using the Arch Wiki is your best bet.

Follow the instructions found here: https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF

**Skip the Isolating the GPU section** We are not going to do that in this method as we still want the host to have access to it. I will cover this again in the procedure section.

# Prerequisites

1. A working Libvirt VM or Qemu script for your guest OS.
2. IOMMU enabled and Sane IOMMU groups
3. The Following Tools
    * A hex editor 
	* (Optional/Only with 10 Series cards) Nvidia ROM Patcher: https://github.com/Matoking/NVIDIA-vBIOS-VFIO-Patcher
	* (Optional) nvflash for dumping your GPU bios: https://www.techpowerup.com/download/nvidia-nvflash/
		- Techpowerup also has a database of roms for your corresponding video card model
	* (If using Libvirt) The Libvirt Hook Helper  https://passthroughpo.st/simple-per-vm-libvirt-hooks-with-the-vfio-tools-hook-helper/
	* (Optional) Another machine to SSH/VNC to your host with for testing might be useful

With all this ready. Let's move on to how to actually do this.

# Procedure

## Patching the GPU Rom for the VM
First of all, we need a usable ROM for the VM. When the boot GPU is already initialized, you're going to get an error from QEMU about usage count. This will fix that problem

1. Get a rom for your GPU
	* You can either download one from here https://www.techpowerup.com/vgabios/ or
	* Use nvflash to dump the bios currently on your GPU. nvflash is pretty straigh forward, but I won't cover it here.
2. Patch the BIOS file:

#### With Nvidia vBios Patcher

In the directory where you saved the original vbios, use the patcher tool.
````
python nvidia_vbios_vfio_patcher.py -i <ORIGINAL_ROM> -o <PATCHED_ROM>
````
Now you should have a patched vbios file, which you should place where you can remember it later. I store mine with other libvirt files in ````/var/lib/libvirt/vbios/````

#### Manually 

Use the dumped/downloaded bios and open it in a hex editor.

Search in the strings for the line including "VIDEO" that starts with a "U"
![VIDEO_STRING_IN_HEX](https://user-images.githubusercontent.com/3674090/44610184-aa879c00-a7ea-11e8-9772-408e807aea02.png)

Delete all of the code above the found line.
![DELETE_FOUND_CODE](https://user-images.githubusercontent.com/3674090/44610217-c4c17a00-a7ea-11e8-908d-b988644681e3.png)

Save!


3. Attach the PCI device to your VM
	* In libvirt, use "+ Add Hardware" -> "PCI Host Device" to add the video card and audio device
4. Edit the libvirt XML file for the VM and add the patched vbios file that we've generated

````
sudo virsh edit {VM Name}
````
````
<hostdev>
	...
	<rom file='/var/lib/libvirt/vbios/patched-bios.bin'/>
	...
</hostdev>
````
5. Save and close the XML file

## Setting up Libvirt hooks

Using libvirt hooks will allow us to automatically run scripts before the VM is started and after the VM has stopped.

Using the instructions here https://passthroughpo.st/simple-per-vm-libvirt-hooks-with-the-vfio-tools-hook-helper/ to install the base scripts, you'll find a directory structure that now looks like this:

```
/etc/libvirt/hooks
├── qemu <- The script that does the magic
└── qemu.d
    └── {VM Name}
        ├── prepare
        │   └── begin
        │       └── start.sh
        └── release
            └── end
                └── revert.sh
```

Anything in the directory ````/etc/libvirt/hooks/qemu.d/{VM Name}/prepare/begin```` will run when starting your VM

Anything in the directory ````/etc/libvirt/hooks/qemu.d/{VM Name}/release/end```` will run when your VM is stopped

### Libvirt Hook Scripts
I've made my start script ```/etc/libvirt/hooks/qemu.d/{VMName}/prepare/begin/start.sh```


### Start Script
```
#!/bin/bash
# Helpful to read output when debugging
set -x

# Stop display manager
systemctl stop x11vnc.service
systemctl stop sddm.service
## Uncomment the following line if you use GDM
#killall gdm-x-session

# Unbind VTconsoles
echo 0 > /sys/class/vtconsole/vtcon0/bind
echo 0 > /sys/class/vtconsole/vtcon1/bind

# Unbind EFI-Framebuffer
echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/unbind

# Avoid a Race condition by waiting 2 seconds. This can be calibrated to be shorter or longer if required for your system
sleep 2

# Unload all Nvidia drivers
modprobe -r nvidia_drm
modprobe -r nvidia_modeset
modprobe -r nvidia_uvm
modprobe -r nvidia
# Looks like these might need to be unloaded on Ryzen Systems. Not sure yet.
modprobe -r ipmi_devintf
modprobe -r ipmi_msghandler

# Unbind the GPU from display driver
virsh nodedev-detach pci_0000_0c_00_0
virsh nodedev-detach pci_0000_0c_00_1

# Load VFIO Kernel Module  
modprobe vfio-pci  
```
NOTE: Gnome/GDM users. You have to uncommment the line ````killall gdm-x-session```` in order for the script to work properly. Killing GDM does not destroy all users sessions like other display managers do. 


### VM Stop script
My stop script is ```/etc/libvirt/hooks/qemu.d/{VMName}/release/end/revert.sh```
```
#!/bin/bash
set -x

# Unload VFIO-PCI Kernel Driver
modprobe -r vfio-pci
modprobe -r vfio_iommu_type1
modprobe -r vfio
  
# Re-Bind GPU to Nvidia Driver
virsh nodedev-reattach pci_0000_0c_00_1
virsh nodedev-reattach pci_0000_0c_00_0

# Rebind VT consoles
echo 1 > /sys/class/vtconsole/vtcon0/bind
#echo 1 > /sys/class/vtconsole/vtcon1/bind

nvidia-xconfig --query-gpu-info > /dev/null 2>&1
echo "efi-framebuffer.0" > /sys/bus/platform/drivers/efi-framebuffer/bind

modprobe nvidia_drm
modprobe nvidia_modeset
modprobe nvidia_uvm
modprobe nvidia
modprobe ipmi_devintf
modprobe ipmi_msghandler

# Restart Display Manager
systemctl start sddm.service
systemctl start x11vnc.service

```

# Running the VM
When running the VM, the scripts should now automatically stop your display manager, unbind your GPU from all drivers currently using it and pass control over the libvirt. Libvirt handles binding the card to VFIO-PCI automatically. 

When the VM is stopped, Libvirt will also handle removing the card from VFIO-PCI. The stop script will then rebind the card to Nvidia and SHOULD rebind your vtconsoles and EFI-Framebuffer. 

# TODO: QEMU Scripts without Libvirt 
This is also possible, but will require a significantly different process. I might write another process all together and separate the two entirely. 

# Want to test on other GPUs/Distributions/Other mad scientist stuff? 
Please let me know what you find! 

## As always. Make a pull request or issue. The issue tracker has already solved one problem for me. 

### Fuel my coffee addiction
#### Always appreciated, never required.

ETH: 0xE4Bf3fc0562f7F63d0F9dF94E87e01C217D30918
