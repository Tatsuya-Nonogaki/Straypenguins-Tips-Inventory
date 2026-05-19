#!/usr/bin/python3
# macgen.py script generates a MAC address for qemu guests
#
import random
mac = [ 0x52, 0x54, 0x00,
random.randint(0x00, 0x7f),
random.randint(0x00, 0xff),
random.randint(0x00, 0xff) ]
print (':'.join(map(lambda x: "%02x" % x, mac)))

