> [!note]
> This post is part of my [[7 Days Of Kubernetes]] where I explore setting up [a cheap MiniPC](https://amzn.to/42tenCq) as a single-node Kubernetes cluster using k3s.

Before we get into the software-heavy fun of setting up Kubernetes and deploying services we need to have the hardware-heavy discussion of how I ended up with [a miniPC smaller than my hand](https://amzn.to/42tenCq) to serve my personal-server needs.

![[PXL_20250329_043321083.jpg|This tiny miniPC is now my personal-projects and home server and it's smaller than my hand!]]

# Why change servers now?

Historically I've used two servers:
- an old laptop running Linux as a "home server"
- the cheapest digital ocean droplet as a "project server"

The primary driver for the different servers is that they provide different utility. My home server sits inside the network and is able to control smart bulbs or my 3D Printer. My project server sits on the public internet and hosts random toy projects I write in my spare time.

A recent project I was working on required docker for its deployment. This was when I discovered that my long-languishing project server didn't support docker! And, to my great embarrassment, the OS was so far behind that I couldn't easily procure packages to run docker.

So I decided now was the time to spin up a new more powerful host, install k3s, and finally get the chance to run kubernetes for my project server!

# Defining the Requirements

I knew I wanted to run Kubernetes and the full suite of tools that's generally associated with that. While I don't have exact estimates for how many resources these services will require, I do know that my home server (an old laptop from 2015 with 8GB of RAM) struggled to run everything (including Plex) and not run out of memory.

> [!note] The Power of Hindsight
> Looking at my current stats on my miniPC, I'm using 4GB of RAM and haven't deployed any of my services yet. The majority of that is #victoriametrics and #argo-cd.
> ![[Screenshot 2025-04-06 at 11.12.11 PM.png]]

# Exploring VPS Options

## DigitalOcean

My first instinct was to procure another DigitalOcean droplet. However, looking at the pricing, anything powerful enough to run the workloads I was hoping to run (Prometheus, Grafana, Argo-CD, Go apps, k3s, etc.) would run me *at least* $24/month.

![[Screenshot 2025-04-06 at 10.27.28 PM.png|Anything in the green box is big enough for my workloads.]]


## Hostinger

Exploring outside of DigitalOcean's offerings, Hostinger came up as an option. Their prices were more in the range of what I was hoping to spend as the KVM 4 instance only runs for $10/month.

![[Screenshot 2025-04-06 at 10.47.22 PM.png|The KVM4 model at $10/month would fit my needs.]]

However, these prices also felt too good to be true! I googled around and found horror stories of Hostinger having availability issues as well as not having very fast CPU cores. To get the advertised price, I'd have to make a 2 year commitment so if Hostinger didn't provide the level of service I expected, I'd be stuck with a $240 loss. 

In the posts that panned Hostinger some users recommended OVH, so I checked them out next.

## OVHcloud

![[Screenshot 2025-04-06 at 10.45.32 PM.png]]

OVHcloud runs more expensive than Hostinger. If I went with the $10/mo option I'd only get 4 GB of RAM. If I wnet larger I'd be looking at up to $40/month!

Once again, not really the price point I was looking to pursue.

# Exploring miniPC's

Napkin math tells us that if we can buy a miniPC for ~$240 then we'd be "in the money" within as long as 2 years. 

| Host         | vCPU | RAM  | Cost/mo | Time to $240 |
| ------------ | ---- | ---- | ------- | ------------ |
| Hostinger    | 2    | 8 GB | $10     | 24 months    |
| OVHcloud     | 4    | 8 GB | $24     | 10 months    |
| DigitalOcean | 4    | 2 GB | $24     | 10 months    |

## Beelink

Beelink makes miniPC's like the [Beelink mini s13](https://amzn.to/3R6FwFS). Reviews of these were generally positive though I was concerned that the RAM was not upgradable. 

## Acemagic

As I was browsing amazon for options I came across the [acemagic mini k1](https://amzn.to/4iXRRs6) which was right in the price range, offered 16GB of RAM (upgradable) and an AMD 8 core processor. This was the sort of thing i was looking for!

To get an equivalent machine at DigitalOcean, it would cost $96/month! At that rate, we'll make our money back in savings after less than 3 months!

I googled around and found some pretty crazy stores about [acemagic shipping their PC's with viruses preinstalled](https://www.theregister.com/2024/02/29/acemagic_chinese_pc_malware_infection/)! However I had a sneaky trick that would get around that issue: wiping the disk and installing linux! 

# Tiny Computer, Big Potential

So I picked up the mini K1 and did exactly that! In the rest of my [[7 Days Of Kubernetes]] series I'll be walking through what I did with this tiny-but-powerful miniPC to turn it into a kubernetes workhorse!