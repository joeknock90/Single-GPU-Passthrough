# Single GPU Passthrough on Linux  
This guide is to help people through the process of using GPU Passthrough via libvirt/virt-manager on Legion 5 Pro in Discrete Graphics Mode. 

## Special Thanks to:
### [The Passthrough post](https://passthroughpo.st)
For hosting news and information about VFIO passthrough, and for the libvirt/qemu hook helper in this guide.

### Sporif
For diagnosing, developing, and testing methods to successfully rebind the EFI-Framebuffer when passing the video card back to the host OS.

### JoeKnock90 on Github.
For providing the start and stop scripts that I used to bind and unbind the gpu dynamically. This repo was forked from his original one and repurposed for mostly personal reference when implementing vfio on the Lenovo Legion 5 Pro.

#### If feel your name should be here, please contact me. Credit where credit is due is very important to me, and to making the Linux community a better place.

## Contents

1. [Disclaimer](#disclaimer) 
2. [Background](#background)
3. [Advantages](#advantages)
4. [Disadvantages](#disadvantages)
3. [Prerequisites](#prerequisites) and [Assumptions](#assumptions)
4. [Procedure](#procedure)

# Disclaimer
You are completely responsible for your hardware and software. This guide makes no guarentees that the process will work for you, or will not void your waranty on various parts or break your computer in some way. Everything from here on out is at your own risk. 

# Advantages
* As already stated, this model only requires one GPU
* The ability to switch back and forth between different OSes with FULL use of a discrete graphics processor (Linux on Host with full GPU, Windows 10 Guest with Full GPU, MacOS guest with full GPU)
* Bragging rights
* Could be faster than dual booting (this depends on your system)
* Using virtual disk images (like qcow) gives you management of snapshots, making breaking your guest os easy to recover from.
* Its really cool!!!
* Near native performance. More performance than dual on laptop at least.

# Disadvantages
* Can only use one OS at a time.
	- Once the VM is running, it's basically like running that as your main OS. You  will be logged out of your user on the host, but will be unable to manage the host locally at all. You can still use ssh/vnc/xrdp to manage the host.
* There are still some quirks (I need your help to iron these out!)
* Using virtual disk images could be a performance hit
	- You can still use raw partitions/lvm/pass through raw disks, but loose the more robust snapshot and management features
* If you DO have a second video card, solutions like looking-glass are WAYYY more convenient and need active testing and development.
* All VMs must be run as root. There are security considerations to be made there. This model requires a level of risk acceptance.

For my personal use case. This model is worth it to me and I just think its really really cool to do!

# Prerequisites and Assumptions

## Assumptions
This guide is going to assume a few things
You have read and understood thouroughly/implemented vfio using the [Arch Wiki][arch_wiki].

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
Ensure that you have edited the pci ids according to the output of `lspci -nnk` to match your gpu. Otherwise the vfio-pci driver will not recognize and bind to your gpu.

I've edited the start script ```/etc/libvirt/hooks/qemu.d/{VMName}/prepare/begin/start.sh```


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
virsh nodedev-detach pci_0000_01_00_0  #Replace numbers with your specific pci id. Use lspci -nnk
virsh nodedev-detach pci_0000_01_00_1  # This one too

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
virsh nodedev-reattach pci_0000_01_00_1 #Replace id with your gpu id number. Use lspci -nnk.
virsh nodedev-reattach pci_0000_01_00_0 #This too

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
3. **My 3070 Laptop GPU does not work well with the vfio driver hence it does not bind to the device properly and the guest cannot make proper use of the gpu. When I ran in hybrid mode with the iGPU enabled I noticed lower performance in games or outright crashing. In single-gpu mode it seems the problem is a blackscreen as soon as the display is handed off to the gpu. The solution is to send your gpu vbios explicitly through the xml. I have uploaded a rom file I got from TechPowerUp. I will upload my own VBIOS later. It is recommended that you dump the vbios for your own gpu and use it for best compatibility and security. **
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

1. Isolate all but 1 core from host for more performance.
2. Enable Remote Desktop on your VM and note down IP Address from Virt-Manager.
3. Anything you want the host to do upon VM activation.


# Let me know what works and what doesnt!
Let me know your success and failure stories. 


#### [This guide was forked from joeknock90 and edited for Legion 5 Pro. Here's a link to send some support if you desire.](https://www.paypal.com/donate?business=87AQBT5TGFRJS&item_name=Github+Testing&currency_code=USD)
#### Always appreciated, never required.

