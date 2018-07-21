# Single GPU PCI Passthrough on Linux

### Disclaimer
My qualifications:

I have none. I am a Windows SysAdmin by trade. Linux is my hobby.

I am not, nor do I claim to be an expert here. Honestly I'm basically a moron. If you know of a better way to do this, please SHARE IT WITH THE COMMUNITY. Let me know and let everyone know. We can all make this better.

### Background

Historically guides for GPU passthrough have included much of the same hardware layout. 2 GPUs, one for the host, and one for the guest, as well as 2 monitors. On the advent of solutions like "Looking-Glass" this has continued to perpetuate the 2 GPU model for PCI passthrough.

I for one have no need for a second GPU. When I am in the unfortunate situation that a game requires a Windows machine, I am going to boot Windows and play it. Otherwise, I'd like to use my single 1080ti on my linux host.

#### Why not dual boot then? They ask.

Several reasons.

1. How can I brag about my Linux uptime if I'm constantly restarting my computer?

2. Windows doesn't touch bare hardware.

3. Snapshots are REALLY easy for when I want to break Windows

4. Easier storage management. Now I don't have to have a bunch of crappy partitions everywhere and everything can be BTRFS subvolumes.

There are more reasons I'm sure I'm not thinking of right now.

#### Sold? Good. How do we do it.

First, I'm going to assume that you've been able to get VFIO working in the past in some way. I'm not going to tell you which Distro to use as I've only ever used either Arch Linux or Fedora for PCI Passthrough. This can be adapted to I'm sure lots of other distribtuions as well, but I'm going to focus on my current setup, which is Arch.

I'll speed through the beggining while referencing the ArchWiki, noting the changes I made to the procedure on the way.

### Prerequisites
Here are a few of the tools we are going to be using to accomplish our task.

#### Libvirt Hook helper
This is going to help us run scripts automagically when starting and stopping our VM

https://passthroughpo.st/simple-per-vm-libvirt-hooks-with-the-vfio-tools-hook-helper/

#### VFIO PCI bind
This is basically optional, but I've been using it to simplify my own libvirt hooks scripts. Why do more work when someone else has already done it well enough?

https://github.com/andre-richter/vfio-pci-bind

Thanks andre-richter!

#### Nvidia ROM patcher

If you're using an nvidia card, you'll need to include a patched ROM file in your libvirt.xml so that the machine doesn't see a GPU that's already been initialized. There are some pre patched roms around, but we'll patch ours ourselves.

Tools and instructions found here:

https://github.com/Matoking/NVIDIA-vBIOS-VFIO-Patcher

Thanks Matoking!

**Optional**

Another machine to ssh into your host with for testing. Chances are, like everything in VFIO, you're going to need to adjust things.


### Procedure

1. Enable IOMMU
	It goes without saying that you still need to do this

2. Ensure the groups are valid.
	Yeah. We'll assmue that's the case



3. Isolate the GPU.
	**Well let's hold on there just a moment.**

	We don't really want to Isolate the gpu from the system entirely. So let's skip this step.

4. OVMF Libvirt Guest
	Go ahead and setup libvirt to use OVMF. We're going to need it for what we are doing with hotswapping the GPU.

	Setup a Windows VM with no devices passed through.

	Currently I'm using 2 qcow2 drives. One for Windows, and one to store Games. Reason being is it's not a huge deal if I lose the games drive, as I can just redownload those making the windows drive smaller and easier to back up so I don't have to go through the installation process again if I bork the host in another project.

	You can do whatever perfomance optimiztions you want to the host here as well. CPU pinning and/or hugepages for ram. I suggest both as they have given me moderate performance gains.

	5. Patching the Boot GPU rom.


### Patching GPU ROM

First we need an unpatched rom for your video card. You can either use the nvidia_flasher util which I am not providing a link to here, or you can download a rom for your video card from techpowerup here:

https://www.techpowerup.com/vgabios/

After getting that. We'll use nvidia_vbios_vfio_patcher to patch it. Following the instruction on the github page:

````
python nvidia_vbios_vfio_patcher.py -i <ORIGINAL_ROM> -o <PATCHED_ROM>
````

Now we have a patched rom. We'll save that somewhere safe. I put it in a folder I created called

````/var/lib/libvirt/vbios/````

After attaching the GPU to the VM in Libvirt, find the hostdev corresponding to your GPU in the Libvirt XML, and add the line for the rom file telling it where it is. 

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



### Libvirt Hooks

Here's the magic we're going to be using.

Libvirt has the ability to use hooks for Preparing to run, Running, Preparing to stop, and stopping VMs. The setup although was a bit convoluted, until someone cleaned it up in a nice little script located here.

https://passthroughpo.st/simple-per-vm-libvirt-hooks-with-the-vfio-tools-hook-helper/

Basically, this script and directory structure is going to help automate hooks based on VM name.

In my example, my gaming VM is called "Windows10" because I'm clever and not boring at all.

The directory structure created by the Libvirt Hook helper is located on the post, but we'll go over it here.

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

#### TL;DR

Anything in the directory ````/etc/libvirt/hooks/qmeu.d/{VM Name}/prepare/begin```` will run when starting your VM

Anything in the directory ````/etc/libvirt/hooks/qemu.d/{VM Name}/release/end```` will run when your VM is stopped

So let's make this work for us by creating a script that:
1. stops all services using X
2. Loads the required kernel modules
3. Unbinds the GPU from the kernel drivers.
4. Binds the GPU to VFIO.

## Here's basically how I unbind the GPU automatically

``` start.sh
# Stop all X services
systemctl stop lightdm.service
systemctl stop ckb-daemon
# Load VFIO kernel modules
modprobe vfio
modprobe vfio-pci
# Unbind Virtual Consoles
echo 'Unbinding vtconsole'
echo 0 | tee /sys/class/vtconsole/vtcon0/bind
echo 0 | tee /sys/class/vtconsole/vtcon1/bind
# Unbind EFI-Framebuffer
echo 'Unbinding efi-framebuffer'
echo efi-framebuffer.0 | tee /sys/bus/platform/drivers/efi-framebuffer/unbind
# Unbind Nvidia Driver
echo 'unbind nvidia driver'
/usr/local/bin/vfio-pci-bind "0000:01:00.0"
# Remove Nvidia Drivers
modprobe -r nvidia_drm
modprobe -r nvidia_modeset
modprobe -r nvidia
# Wait a second
sleep 1
```

the vfio-pci-bind script only requires that nothing be using the GPU so it can successfully unibind. Therefore, we unbind the virtual consoles, as well as the efi-Framebuffer

I leave the sleep 1 at the end due to a race condition that I ran into a few times when starting the VM. It might not be required for you.

## Here's how I rebind the GPU when I'm done

``` revert.sh
#!/bin/sh
# Reload the driver
modprobe -a nvidia
# Remove the GPU completely
echo 1 | tee /sys/bus/pci/devices/0000:01:00.0/remove
echo 1 | tee /sys/bus/pci/devices/0000:01:00.1/remove
# Rescan for the GPU which automatically rebinds to nvidia driver
echo 1 | tee /sys/bus/pci/rescan

sleep 1

# attempt rebind to virtual consoles
echo 1 | tee /sys/class/vtconsole/vtcon0/bind
echo 1 | tee /sys/class/vtconsole/vtcon1/bind

#restart lightdm
systemctl start lightdm.service
systemctl start ckb-daemon.service
```

Here is very simple. We remove the GPU completely from the PCI bus, and then rescan for it, which will automatically rebind it to the appropriate video driver (in my case Nvidia)

At the end it restarts my display manager for me and brings it back up and running.

This should have you back up and running on your linux desktop after stopping the VM.

## Problems with my method and where I need help.

Unforunately, I am unable to use the virtual consoles again after starting the VM and shutting it down the first time. I think this is tied in somewhere with the efi-framebuffer, which as of now, I do not know how to rebind.

## Other Issues.

You tell me! Where have I gone wrong here? Am I overcomplicating something?

Let me know.
