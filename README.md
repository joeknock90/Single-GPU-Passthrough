
### If you go to reddit (specifically [r/vfio](https://www.reddit.com/r/vfio)) for help, try to mention [u/lellow_yedbetter](https://www.reddit.com/user/lellow_yedbetter/). You will probably get help faster from users in the sub, but it is easier for me to keep an eye on the github issues. 

# Single GPU Passthrough on Linux  
This guide is to help people through the process of using GPU Passthrough via libvirt/virt-manager on systems that only have one GPU. 

## Special Thanks to:
### [The Passthrough post](https://passthroughpo.st)
For hosting news and information about VFIO passthrough, and for the libvirt/qemu hook helper in this guide.

### andre-ritcher
For providing the vfio-pci-bind tool. A tool that is no longer used in this guide, but was previously used and he still deserves thanks.

### Matoking
For the Nvidia ROM patcher. Making passing the boot gpu to the VM without GPU bios problems.
Patching the rom is no longer required but I never would have written this guide without the original work so I'm keeping them here. 

### Sporif
For diagnosing, developing, and testing methods to successfully rebind the EFI-Framebuffer when passing the video card back to the host OS.

### droidman
For instructions on manually editing the vBIOS hex for use with VFIO passthrough

### [Yuri Alek](https://gitlab.com/YuriAlek/vfio)
A guide that is no doubt better than mine. Learning a few things from his implementation that can help me out a bit. This guide depends on libvirt at the base where as his has implementations that do not. 

#### So many other people and organizations I need to thank. If feel your name should be here, please contact me. Credit where credit is due is very important to me, and to making the Linux community a better place.

## Contents

1. [Disclaimer](#disclaimer) 
2. [Background](#background)
3. [Advantages](#advantages)
4. [Disadvantages](#disadvantages)
3. [Prerequisites](#prerequisites) and [Assumptions](#assumptions)
4. [Procedure](#procedure)

# Disclaimer
You are completely responsible for your hardware and software. This guide makes no guarentees that the process will work for you, or will not void your waranty on various parts or break your computer in some way. Everything from here on out is at your own risk. 

# Background
Historically, VFIO passthrough has been built on a very specific model. I.E.

* 2 GPUs, 1 for the host, and one for the VM
* 2 monitors *OR* a monitor with 2 inputs *OR* a KVM switch

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

## Assumptions
This guide is going to assume a few things

1. You have a system capable of VFIO passthrough. I.E. a processors that supports IOMMU, sane IOMMU groups, and etc.
2. I am going to start in a place where you have a working libvirt config, or qemu script, that boots a guest OS without PCI devices passed through.

I am not going to cover the basic setup of VFIO passthrough here. There are a lot of guides out there that cover the process from beginning to end.

What I will say is that using the [Arch Wiki][arch_wiki] is your best bet.

Follow the instructions found [here][arch_wiki]

[arch_wiki]: https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF

**Skip the Isolating the GPU section** We are not going to do that in this method as we still want the host to have access to it. I will cover this again in the procedure section.

## Prerequisites

1. A working Libvirt VM or Qemu script for your guest OS.
2. IOMMU enabled and Sane IOMMU groups
3. The Following Tools
	* (If using Libvirt) [The Libvirt Hook Helper](https://passthroughpo.st/simple-per-vm-libvirt-hooks-with-the-vfio-tools-hook-helper/)
	* (Optional) Another machine to SSH/VNC to your host with for testing might be useful

With all this ready. Let's move on to how to actually do this.

# Procedure

## Setting up Libvirt hooks

Using libvirt hooks will allow us to automatically run scripts before the VM is started and after the VM has stopped.

Using the instructions [here](https://passthroughpo.st/simple-per-vm-libvirt-hooks-with-the-vfio-tools-hook-helper/) to install the base scripts, you'll find a directory structure that now looks like this:

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

### Libvirt Hook Scripts]
#### Do not copy my scripts. Use them as a template, but write your own. 

I've made my start script ```/etc/libvirt/hooks/qemu.d/{VMName}/prepare/begin/start.sh```


### Start Script
```
#!/bin/bash
# Helpful to read output when debugging
set -x

# Stop display manager
systemctl stop display-manager.service
## Uncomment the following line if you use GDM
#killall gdm-x-session

# Unbind VTconsoles
echo 0 > /sys/class/vtconsole/vtcon0/bind
echo 0 > /sys/class/vtconsole/vtcon1/bind

# Unbind EFI-Framebuffer
echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/unbind

# Avoid a Race condition by waiting 2 seconds. This can be calibrated to be shorter or longer if required for your system
sleep 2

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
  
# Re-Bind GPU to Nvidia Driver
virsh nodedev-reattach pci_0000_0c_00_1
virsh nodedev-reattach pci_0000_0c_00_0

# Reload nvidia modules
modprobe nvidia
modprobe nvidia_modeset
modprobe nvidia_uvm
modprobe nvidia_drm

# Rebind VT consoles
echo 1 > /sys/class/vtconsole/vtcon0/bind
# Some machines might have more than 1 virtual console. Add a line for each corresponding VTConsole
#echo 1 > /sys/class/vtconsole/vtcon1/bind

nvidia-xconfig --query-gpu-info > /dev/null 2>&1
echo "efi-framebuffer.0" > /sys/bus/platform/drivers/efi-framebuffer/bind

# Restart Display Manager
systemctl start display-manager.service

```

# Running the VM
When running the VM, the scripts should now automatically stop your display manager, unbind your GPU from all drivers currently using it and pass control over the libvirt. Libvirt handles binding the card to VFIO-PCI automatically. 

When the VM is stopped, Libvirt will also handle removing the card from VFIO-PCI. The stop script will then rebind the card to Nvidia and SHOULD rebind your vtconsoles and EFI-Framebuffer. 

# Troubleshooting
First of all. If you ask for help, then tell me you skipped some step... I'm gonna be a little annoyed. So before moving on to troubleshooting, and DEFINATELY before asking for help, make sure you've follwed ALL of the steps of this guide. They are all here for a reason. 

## Logs
Logs can be found under /var/log/libvirt/qemu/[VM name].log

## Common issues
### Black Screen on VM Activation
1. Make sure you've removed the Spice Video and QXL video adapter on the VM
2. It can be extremely helpful to SSH into the host to check if scripts have executed properly, and that the VM is running. Try these in this order.
	1. SSH into the host, and manually run the start script. If the start script runs properly, the host monitors should go completely black, and the terminal should return you to the prompt. 
	2. If all goes well there, try running the vm manually using `sudo virsh start {vmname}`
	3. If there is a problem here, typically the command will hang. That would signify a problem with the VM libvirt configuration. 
	4. If you are returned to the prompt, check if the vm is in a running state by using `sudo virsh list`
	5. If it's running fine, and you've made sure that you are not having the issue in step 1 and 2, yell at me in the issue tracker or reddit
3. On certain GPU's (like my 3070 Laptop GPU) the vfio driver does not bind to the device properly hence the guest cannot make proper use of the gpu. When I ran in hybrid mode with the iGPU enabled I noticed lower performance in games or outright crashing. In single-gpu mode it seems the problem is a blackscreen as soon as the display is handed off to the gpu. The solution is to send your gpu vbios explicitly through the xml. 
`<rom file='path/to/file'/>`

### Audio
Check out the ArchWIKI entry for tips on audio. I've used both Pulseaudio Passthrough but am currently using a Scream IVSHMEM device on the VM. 

## NOTE
Either of these will require a user systemd service. You can keep user systemd services running by enabling linger for your user account like so:
`sudo loginctl enable-linger {username}`
This will keep services running even when your account is not logged in. I do not know the security implications of this. My assumption is that it's not a great idea, but oh well. 

# Tips and Tricks
## Personal Touches
Here's a few things I do to make managing the host easier. 

1. Start a VNC server on the host in the start script
2. Set pulseaudio volume to 100%
3. Anything you want the host to do upon VM activation.


# Let me know what works and what doesnt!
Let me know your success and failure stories. 


#### [Fuel my coffee addiction or help me test new hardware](https://www.paypal.com/donate?business=87AQBT5TGFRJS&item_name=Github+Testing&currency_code=USD)
#### Always appreciated, never required.

