# ipv6_dyndns

IPv6 can be very well-suited to dynamic DNS because many implementations eschew NAT. It can also be very ill-suited for dynamic DNS when you lack exact control of _which_ address is being set.

Addresses that are computed from the machine's MAC address are undesirable, as are addresses that are pseudorandom and purposefully temporary. And on a particular machine of mine, while ethernet connectivity may sometimes happen, it's usually supposed to be on WiFi, and each of the two interfaces gets a different address.

Ergo this program is an opinionated client for my preferred dynamic DNS provider which sends its machine's address with the shortest human-readable representation, that isn't among those undesirable categories. And for convenience, it disables an annoying powersave feature that likes to knock this machine offline.
