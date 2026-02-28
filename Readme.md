# Goals

To achieve a minimal Linux installation that:
- Can be rolled back with Snapper
- GRUB + systemd.targets for enabling different workflows
    - think ML workloads and APIs, that can be turned off for pure gaming
- Supports nvidia GPU
    - legit nvidia drivers
- Has Steam
    - mangohud
    - gamemoded/gamemoderun
- Uses GE-Proton

# Setup

## 1. Booted with Snapper
- Install Fedora with minimal base
- Partition whole disk (let Fedora decide)
- Set up users, etc
- Set up Snapper
- Test Snapper

Do not continue until Snapper is tested and fully working with `undochange` and `rollback`

### Testing


# Scripts & Utilities


## install-reboot-to-windows.sh

Don't use if you're on NixOS as it's set up in the nixos repository

## display-sync

I have a dummy plug plugged into my PC so I can stream from it when my main 
monitor is off. However, if they are both on at the same time, then some games 
cap at the dummy plug refresh rate. Therefore this script ensures that when 
the primary monitor (DP-3) is on, that the dummy plug is disabled.

# Troubleshooting

## Processing Vulkan shaders

Takes forever. You need to configure Steam to use more threads.

[Reddit link](https://www.reddit.com/r/linux_gaming/comments/1j06xpz/how_to_speed_up_steams_shader_precaching/)

