#!/data/data/com.termux/files/usr/bin/bash

# Tested on Redmi 4x with latest MIUI (rooted)

# Requires: libubox 75a3b870ca, relayd f646ba4048 (compiled from openwrt git source)

# https://android.stackexchange.com/a/202335
# https://forums.raspberrypi.com/viewtopic.php?t=1763 
# https://clockworkbird9.wordpress.com/2020/02/16/install-libubox-and-ubus-on-ubuntu/
# https://forum.fairphone.com/t/rom-unofficial-lineageos-16-0-for-fp3/59849/218?page=12

set -e
set -o pipefail
set -x

WIFI_IF=wlan0
SSID='myssid'
PASS=mypassword

if [ "$(id -u)" != 0 ]; then
	echo 'Need root!'
	exit 1
fi

AP_IF=$WIFI_IF-ap	# $AP_IF must be $WIFI_IF-ap! 
WIFI_SUBNET=$(ip route | grep wlan0 | cut -d' ' -f1)

cleanup()
{
	iptables -D FORWARD -i $WIFI_IF -d 192.168.1.0/24 -j ACCEPT	# FIXME Hardcoded $WIFI_IF subnet 192.168.1.0/24
	iptables -D FORWARD -i $AP_IF -s 192.168.1.0/24 -j ACCEPT	# FIXME Hardcoded $WIFI_IF subnet 192.168.1.0/24
	echo 0 > /proc/sys/net/ipv4/ip_forward
	echo 0 > /proc/sys/net/ipv4/conf/$WIFI_IF/arp_filter
	echo 0 > /proc/sys/net/ipv4/conf/$AP_IF/arp_filter
        iw $AP_IF del
        rm -rf "$SSID"
}

trap cleanup EXIT

iw dev $WIFI_IF interface add $AP_IF type __ap
ip link set up dev $AP_IF
ip addr add 192.168.169.169/24 dev $AP_IF	# Arbitrary IP address different from $WIFI_IF
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 1 > /proc/sys/net/ipv4/conf/$WIFI_IF/arp_filter
echo 1 > /proc/sys/net/ipv4/conf/$AP_IF/arp_filter
iptables -I FORWARD -i $AP_IF -s 192.168.1.0/24 -j ACCEPT	# FIXME Hardcoded $WIFI_IF subnet 192.168.1.0/24
iptables -I FORWARD -i $WIFI_IF -d 192.168.1.0/24 -j ACCEPT	# FIXME Hardcoded $WIFI_IF subnet 192.168.1.0/24

mkdir -p "$SSID"
cat << EOF > "$SSID/hostapd.conf"
# network interface to listen on
interface=$AP_IF
# wi-fi driver
driver=nl80211
# WLAN channel to use
channel=11
# limit the frequencies used to those allowed in the country
#ieee80211d=1
# the country code
#country_code=ID
# 802.11n support
ieee80211n=1
# QoS support, also required for full speed on 802.11n/ac/ax
wmm_enabled=1
# ser operation mode, what frequency to use
hw_mode=g
# network name
ssid=$SSID
# enforce Wireless Protected Access (WPA)
wpa=2
# passphrase to use for protected access
wpa_passphrase=$PASS
# WPA protocol
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

(cd "$SSID" && hostapd hostapd.conf)&

relayd -I $WIFI_IF -I $AP_IF -D -B -d
