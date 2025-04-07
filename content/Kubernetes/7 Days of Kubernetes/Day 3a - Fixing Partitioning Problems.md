> [!note]
> This post is part of my [[7 Days Of Kubernetes]] where I explore setting up [a cheap MiniPC](https://amzn.to/42tenCq) as a single-node Kubernetes cluster using k3s.

At the end of yesterday's steps of [[Day 2b - Observability with Grafana and VictoriaMetrics|installing grafana and victoriametrics for observability]], we had discovered that my disk partitions were not what I wanted and we were quickly running out of disk on `/var`:

![[Screenshot 2025-04-05 at 11.03.42 PM.png]]

In light of that, I decided that now was the time to reformat the partitions, but I didn't want to lose any progress!

# Coming up with a plan to repartition without losing data

Looking at the order of disks using `fdisk -l`, I saw that the root partition (`/`) was first in the list:

```
# simulated output of: fdisk -l

Device         Start        End   Sectors   Size Type
/dev/sda1       2048    1050623   1048576   512M EFI System
/dev/sda2    1050624  105916761 104866137    50G Linux filesystem
/dev/sda3  105916762  210782899 104866137    50G Linux filesystem
/dev/sda4  210782900 1000215182 789432282 399.5G Linux filesystem
```

```
# simulated output of: df -Ph / /var /home

Filesystem      Size  Used   Avail Use% Mounted on
/dev/sda2        50G    2G     48G   4% /
/dev/sda3        50G   40G     10G  80% /var
/dev/sda4       400G    1G  399.5G   1% /home
```

The `df` command shows that `/` is placed on partition `/dev/sda2` which, conveniently, is the first partition after the EFI boot partition.

Also conveniently, there is still enough free space left on `/` such that I can fit all the data in both `/var` and `/home` on the `/` partition before I expand its size.

So we have a plan:

1. Stop all writes to `/var` and `/home`
2. Copy all data from `/var` into the `/` partition
3. Copy all data from `/home` into the `/` partition
4. Delete partitions `/dev/sda3` and `/dev/sda4`
5. Expand `/dev/sda2` to take up the disk.

# Repartitioning my Disk Over SSH Without Rebooting

As we've previously established, this is headless miniPC with only SSH access. Therefore if I was going to do this repartitioning without having to physically plug it into a monitor I'd have to do this entire operation over SSH.

The plan is this:

1. Stop all activity against the partition
2. Unmount the partition
3. Remount the partition somewhere else (e.g.: `/mount/var`)
4. Delete the old mount point (`rmdir /var`)
5. Copy all data from the old partition to the root partition: `cp -rpn /mount/var /var`
6. Unmount and delete the old partition

It seemed a simple enough operation, so I started out.

## Identifying what's using a partition

There is tooling available to help you identify which services are using directory: `lsof`

Simply put, you use `lsof +D /path/to/directory` and it will list ever file that is accessing the directory. The second column is the PID, so we can send that to `ps` to find out which process it is:

```bash
lsof +D /var | tail -n +2 | awk '{print $2}' | xargs --no-run-if-empty ps -f
```

This command will output the process information about every pid that is using `/var`. Immediately I realize that most of them are k3s, so I stop the k3s service:

```bash
systemctl stop k3s
```

And this really cleans up the list. There's one entry left though that is quite concerning:

```
root         800       1  0 Mar30 ?        Ss     0:00 dhclient -4 -v -i -pf /run/dhclient.enp2s0.pid -lf /var/lib/dhcp/dhclient.enp2s0.leases -I -df /var/lib/dhcp/dhclient6.enp2s0.leases enp2s0
```

Uh oh! `dhclient` is the DHCP client built into Debian. We don't want to stop the client or we risk losing network access in the middle of our data move. 

This leads us to a place we didn't want to be: plugging in an actual monitor!

# Plan B: Repartitioning Using the Rescue Media

Repatriating with the rescue media was, in general, pretty easy. I still had the USB stick set up to install Debian and the Debian installer comes with rescue mode.

![[debian-rescue-mode.png]]

Once you boot into rescue mode and answer some questions, you eventually get to a busybox prompt. This is where we can do our partitioning work.

## Mount the Partitions

First, you need to identify which partitions you want to mess with. 

Doing an `fdisk -l` I was able to confirm that `/dev/sda` still maps to my internal disk, so I was able to mount the partitions:

```bash
# create the mount directories
mkdir -p /internal-disk/{root,var,home}

# mount the root partition:
mount /dev/sda2 /internal-disk/root

# mount /var and /home as readonly so we don't accidently overwrite them
mount -o ro /dev/sda3 /internal-disk/var
mount -o ro /dev/sda4 /internal-disk/home
```

## Copy the Data

First, we want to delete the existing mountpouts int he root disk:

```bash
rmdir /internal-disk/root/home
rmdir /internal-disk/root/var
```

This allows us to copy the other folders in their entirety:

```bash
cp -rpn /internal-disk/home /internal-disk/var /internal-disk/root/.
```

I then did a spot-check of files in both the old and new location to make sure they matched (especially the permissions in `/home`!)

## Fix up the fstab

Now that we no longer want to use these partitions, we need to remove them from `/etc/fstab` so that they are not mounted on boot.

```bash
$ vim /etc/fstab
vim: applet not found
```

Uh oh! There's no vim installed! 

Fear not, we have `sed`! We can use a simple sed command to comment out the lines that have our mount points. 

```bash
cat /etc/fstab

# First do a dry run to make sure the correct line gets commented out:
sed -e '/ \/var / s/^/# /' /etc/fstab

# Then use the `-i` flag to repalce the file inplace:
sed -i -e '/ \/var / s/^/# /' /etc/fstab
sed -i -e '/ \/home / s/^/# /' /etc/fstab

# read the file to make sure our edits look correct:
cat /etc/fstab
```


> [!info] Description of the sed commands
> 
> | Flag      | Meaning                                                                |
> | --------- | ---------------------------------------------------------------------- |
> | -i        | in-place: edit the file in place                                       |
> | -e        | expression: the next argument is the expression to process             |
> | `/ABC/`   | match lines that contain ABC (or, in our case, `/home` or `/var`)      |
> | `s_^_# _` | For each line that matches, **s**wap the start of the line with a `# ` |
>
> Note that we need to escape the slash in `/home` because the line matcher syntax uses a slash for the opening and closing of the matcher.

## Reboot and Delete the Old Partitions

I decided that we'd be extra safe and reboot before I deleted the old partitions. This allows me to ensure that all my files copied correctly and everything behaves fine. From experience I know that I can delete the partitions if they aren't mounted and then expand the disk while it's running.

I shutdown the server and let it reboot. It came up and everything connected exactly like it was supposed to! 

## Cleanup The Old Partitions

Now that all my data was on the root partition, I could delete the old partitions. Once again, we'll use fdisk for this:

```bash
# Get into the fdisk shell
fdisk /dev/sda
```

Once in the fdisk shell, use `p` to see the current partition plan.

Then, use `d` to select the delete command

Then enter the partition number (just the digit!). So, in my case, I did `3` 

Use `p` again to confirm that the correct partition was removed.

> [!warning]- If you delete the wrong partition
> If you deleted the wrong partition, don't panic! Simply use `q` to `quit without saving`

Once the partition table looks like you want, type `w` to write your changes and exit. 

## Resize the Root Disk

Now that the space is available, we can bump up the disk size. To do this, we'll use the `growpart` command.

First we install the command:
```bash
apt install cloud-guest-utils -y
```

Then we use it to grow our root partition to its maximum size:
```bash
growpart /dev/sda 2
```

Finally we tell the filesystem that we resized the partition:
```bash
resize2fs /dev/sda2
```

And we confirm that our disk now shows the correct size:
```bash
$ df -Ph /
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda2       469G   13G  437G   3% /
```

Success!

# Other Possible Solutions

There are some other possible solutions I could have pursued, but I wanted to focus on fixing the partitioning issues and moving onto the fun problems so I gave in quickly to plugging in a monitor.

## Configure Static IP on the Host and Stop `dhclient`

I could have tried configuring a static network configuration on my host. I wasn't fond of this idea because I really wanted it to be "plug and play" if I decide to change router level settings. 

## Use DropBear to Get SSH Access During Preboot

[Dropbear SSH](https://matt.ucc.asn.au/dropbear/dropbear.html) is an SSH server designed to be accessible during boot time. I had done some brief searches on how to set up dropbear but most of them were thin on details. 

Once again, I didn't want to get into the weeds trying to setup a solution to my dhclient problem when I could just walk over and plug in a monitor.

I'd like to pursue setting up dropbear later on as being able to SSH into a downed machine to try fixing it would be a significant value-add.

---

Now that we've fixed up our partitions we can return to the kubernetes fun! In our next post, we'll set up a postfix proxy so we can send email alerts from Grafana: [[Day 3b - Sending Emails Through Gmail With Postfix Proxy]]