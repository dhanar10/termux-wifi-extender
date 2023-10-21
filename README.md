# termux-wifi-extender
Use an Android phone as a dedicated WiFi extender

# Overview
* Many Android has WiFi hardware capabilities required for extending WiFi.
* Some of them, however, have software restrictions to be used as such. My
Nokia G20 for example, loses this capability when upgraded to Android 13
(when hotspot is enabled, WiFi is automatically disabled).
* Here, we will be bypassing Android restrictions and interface
directly with the Linux kernel to extend a WiFi network.
* This method follows roughly how OpenWRT implements WiFi extender.
* In theory, this method can also be adapted with PC or single-board-computers
running Linux as long as the WiFi hardware is capable.

# Requirements
* Android phone (rooted) - I am using Xiaomi Redmi 4x with the latest MIUI
available
  * Find tutorial online on how to root your specific Android phone
* Termux with Termux:Boot installed on the Android phone so that wake-lock
and sshd can be started automatically when the phone is turned on.
  * https://wiki.termux.com/wiki/Termux:Boot#:~:text=Example%3A%20to%20start%20an%20ssh
d%20server%20and%20prevent%20the%20device%20from%20sleeping%20at%20boot%2C
%20create%20the%20following%20file%20at
* Connect to to the phone via SSH to perform the steps.
* Nice to have:
  * Battery management script to manage the battery when the phone is plugged 24 hours so that it does not overcharge

# Steps
1. Install tools for compiling from source
   We will need these to compile and install libubox and relayd (from OpenWRT
git).
   ```shell
   $ pkg install git clang cmake
   
   $ pkg install stow    # This is nice to have because we want to be able to install binaries and libraries compiled from source cleanly
   $ mkdir /usr/stow
   ```
2. Compile and install `libubox`
   Required to be able to compile `relayd` after this.
   ```shell
   $ pkg install lua5.1 json-c
   $ git clone git://git.openwrt.org/project/libubox.git
   $ cd libubox
   $ mkdir build
   $ cd build
   $ cmake -DCMAKE_INSTALL_PREFIX=/data/data/com.termux/files/usr/stow/libubox ..
   $ make    # Fix lua related compile error by fixing lua*.h includes in uloop.c
   $ make install
   $ cd /data/data/com.termux/files/usr/stow
   $ stow libubox
   ```
3. Compile and install `relayd`
   Software bridge between 2 network interface.
   ```shell
   $ git clone https://git.openwrt.org/project/relayd.git
   $ cd relayd
   $ mkdir build
   $ cd build
   $ cmake -DCMAKE_INSTALL_PREFIX=/data/data/com.termux/files/usr/stow/relayd -DCMAKE_C_FLAGS=-D_BSD_SOURCE ..
   $ make # Fix compile error by removing #define NLMSG_ALIGN(len) in route.c
   $ make install
   $ cd /data/data/com.termux/files/usr/stow
   $ stow relayd
   ```
4. Disable WiFi multicast filter
   a. Redmi 4x uses Snapdragon SOC - Edit /data/misc/wifi/WCNSS_qcom_cfg.ini and reboot the phone.
      ```
      --- WCNSS_qcom_cfg.ini.orig 2023-10-03 19:37:29.598680264 +0700
      +++ WCNSS_qcom_cfg.ini 2023-10-03 19:38:05.328680250 +0700
      @@ -24,7 +24,7 @@
       # 1: Enable standby, 2: Enable Deep sleep, 3: Enable Mcast/Bcast Filter
      -gEnableSuspend=3
      +gEnableSuspend=2
      # Phy Mode (auto, b, g, n, etc)
      @@ -81,7 +81,7 @@
      # 2: Filter all Broadcast. 3: Filter all Mcast abd Bcast
      -McastBcastFilter=3
      +McastBcastFilter=0
      #Flag to enable HostARPOffload feature or not
      ```
   b. Alternatively, you can force the Android phone to keep screen on when plugged to a charger - WiFi multicast filter will never be engaged.
      ```shell
      # svc power
      Control the power manager
      usage: svc power stayon [true|false|usb|ac|wireless]
        Set the 'keep awake while plugged in' setting.
        svc power reboot [reason]
        Perform a runtime shutdown and reboot device with specified reason.
        svc power shutdown
        Perform a runtime shutdown and power off the device.
      # svc power stayon true
      ```
6. Configure WiFi interface, forwarding, and `iptables`.
   ```shell
   # iw dev wlan0 interface add wlan0-ap type __ap    # Quirk:the name need to be wlan0-ap, otherwise it will not work, at least for Redmi 4x
   # ip link set up dev wlan0-ap
   # echo 1 > /proc/sys/net/ipv4/ip_forward # Enable ip forwarding and arp filter
   # echo 1 > /proc/sys/net/ipv4/conf/wlan0/arp_filter
   # echo 1 > /proc/sys/net/ipv4/conf/wlan0-ap/arp_filter
   # iptables -I FORWARD -i wlan0-ap -s 192.168.1.0/24 -j ACCEPT    # Without these last 2 command, connected devices cannot access LAN 192.168.1.0/24
   # iptables -I FORWARD -i wlan0 -d 192.168.1.0/24 -j ACCEPT
   ```
7. Run `hostapd`
   ```shell
   # mkdir tmp
   # cd tmp
   
   # cat << EOF > hostapd.conf
   # network name
   ssid=asura_EXT
   # network interface to listen on
   interface=wlan0-ap
   # wi-fi driver
   driver=nl80211
   # WLAN channel to use # Quirk: In reality, the actual WiFi channel will follow the WiFi channel being extended
   channel=11
   # ser operation mode, what frequency to use
   hw_mode=g
   # enforce Wireless Protected Access (WPA)
   wpa=2
   # passphrase to use for protected access
   wpa_passphrase=<REDACTED>
   # WPA protocol
   wpa_key_mgmt=WPA-PSK
   EOF
   
   # hostapd hostapd.conf # Quirk: hostapd.conf must be alone in the current directory (maybe SELinux restriction?)
   ```
8. Run `relayd`
   ```shell
   # relayd
   Usage: relayd <options>
   Options:
    -d Enable debug messages
    -i <ifname> Add an interface for relaying
    -I <ifname> Same as -i, except with ARP cache and host route management
          You need to specify at least two interfaces
    -G <ip> Set a gateway IP for clients
    -R <gateway>:<net>/<mask>
          Add a static route for <net>/<mask> via <gateway>
    -t <timeout> Host entry expiry timeout
    -p <tries> Number of ARP ping attempts before considering a host dead
    -T <table> Set routing table number for automatically added routes
    -B Enable broadcast forwarding
    -D Enable DHCP forwarding
    -P Disable DHCP options parsing
    -L <ipaddr> Enable local access using <ipaddr> as source address
    # relayd -I wlan0 -I wlan0-ap -D -B -d
   ```
9. Extended WiFi is ready to use.

# References
* https://android.stackexchange.com/questions/201024/how-to-use-wi-fi-and-hotspot-at-the-same-time-on-android/202335#202335
* https://forums.raspberrypi.com/viewtopic.php?t=1763
* https://clockworkbird9.wordpress.com/2020/02/16/install-libubox-and-ubus-on-ubuntu/
* https://forum.fairphone.com/t/rom-unofficial-lineageos-16-0-for-fp3/59849/218?page=12
